"""Controlled STAGING network outage, with restoration in finally and a timer.

Default: read-only preflight. --execute creates one synthetic user, briefly
disables staging Argo auto-sync, removes ONLY module ingress from the backend, tests the
deployed image and restores both original settings. No workloads are restarted.
Requires Python 3.10+, kubectl and the existing monitoring Grafana Python sidecar.
Run when no other person is modifying this staging application.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import queue
import subprocess
import threading
import time

CONTEXT = 'do-fra1-vsc-orchestrierung'
NS = 'user-mgmt-staging'
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--execute', action='store_true')
parser.add_argument('--diagnose', action='store_true', help='Capture a JVM thread dump during the fault')
args = parser.parse_args()


def kube(*command, timeout=15):
    result = subprocess.run(['kubectl', '--context', CONTEXT, '--request-timeout=10s',
                             *command], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'kubectl failed')
    return result.stdout


def get(namespace, kind, name=None):
    return json.loads(kube('-n', namespace, 'get', kind, *([name] if name else []), '-o', 'json'))


def pod_summary():
    return {pod['metadata']['name']: {
        'uid': pod['metadata']['uid'],
        'containers': [{'name': s['name'], 'ready': s['ready'], 'restarts': s['restartCount']}
                       for s in pod['status'].get('containerStatuses', [])]}
        for pod in get(NS, 'pods')['items']
        if pod['metadata'].get('labels', {}).get('app.kubernetes.io/component') in ('backend', 'module')}


app = get('argocd', 'application', NS)
assert app['status']['sync']['status'] == 'Synced' and app['status']['health']['status'] == 'Healthy'
assert app.get('status', {}).get('operationState', {}).get('phase') not in ('Running', 'Terminating')
automated = app['spec']['syncPolicy']['automated']
assert automated.get('selfHeal') and automated.get('prune')
assert automated.get('enabled', True)
deploy = get(NS, 'deployment', 'user-mgmt-backend')
assert deploy['spec']['replicas'] == deploy['status'].get('readyReplicas') == 1
assert not any(job['status'].get('active') for job in get(NS, 'jobs')['items'])
policy = get(NS, 'networkpolicy', 'user-mgmt-module')
ingress = policy['spec']['ingress']
assert len(ingress) == 1, 'Unexpected network policy; review before injecting a fault'
assert len(ingress[0]['from']) == 1
assert ingress[0]['from'][0]['podSelector']['matchLabels']['app.kubernetes.io/component'] == 'backend'
assert ingress[0]['ports'] == [{'port': 8080, 'protocol': 'TCP'}]
initial_pods = pod_summary()
assert len(initial_pods) == 2 and all(s['ready'] for pod in initial_pods.values() for s in pod['containers'])
print('PASS preflight: healthy staging, one backend, no active Job, scoped module ingress rule.', flush=True)
if not args.execute:
    print('Read-only preflight complete. Add --execute to run the outage test.')
    raise SystemExit(0)

run_dir = ROOT / 'tmp' / ('module-outage-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
run_dir.mkdir(parents=True)


def patch_file(filename, document):
    path = run_dir / filename
    path.write_text(json.dumps(document), encoding='utf-8')
    return str(path)


network_restore = patch_file('restore-network.json', {'spec': {'ingress': ingress}})
argo_restore = patch_file('restore-argocd.json', {'spec': {'syncPolicy': {'automated': automated}}})
network_fault = patch_file('inject-network.json', {'spec': {'ingress': []}})
argo_pause = patch_file('pause-argocd.json', {'spec': {'syncPolicy': {'automated': None}}})
report = {'context': CONTEXT, 'namespace': NS, 'ops_revision': app['status']['sync']['revision'],
          'image': deploy['spec']['template']['spec']['containers'][0]['image'],
          'initial_pods': initial_pods, 'events': [], 'passed': False}
lock = threading.Lock()
dirty_network = dirty_argo = False


def patch(namespace, kind, name, filename):
    kube('-n', namespace, 'patch', kind, name, '--type=merge', '--patch-file', filename)


def restore():
    global dirty_network, dirty_argo
    with lock:
        try:
            if dirty_network:
                current = get(NS, 'networkpolicy', 'user-mgmt-module')
                assert current['metadata']['uid'] == policy['metadata']['uid']
                assert current['spec'].get('ingress', []) in (ingress, []), 'Unexpected concurrent network edit'
                patch(NS, 'networkpolicy', 'user-mgmt-module', network_restore)
                dirty_network = False
                report['network_restored_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        finally:
            if dirty_argo:
                current_app = get('argocd', 'application', NS)
                assert current_app['metadata']['uid'] == app['metadata']['uid']
                assert current_app['spec']['syncPolicy'].get('automated') in (None, automated), 'Unexpected concurrent Argo edit'
                patch('argocd', 'application', NS, argo_restore)
                dirty_argo = False
                report['autosync_restored_at'] = dt.datetime.now(dt.timezone.utc).isoformat()


client = None
timer = None
messages = queue.Queue()


def receive():
    for line in client.stdout:
        messages.put(line)
    messages.put(None)


def read_stage(expected, timeout=35):
    line = messages.get(timeout=timeout)
    if not line:
        detail = client.stderr.read().strip()
        raise RuntimeError(f'Client ended before {expected}: {detail}')
    row = json.loads(line)
    assert row['stage'] == expected, f'Unexpected client stage: {row["stage"]}'
    report['events'].append(row)
    print(json.dumps(row), flush=True)
    return row


try:
    code = Path(__file__).with_name('module-outage-client.py').read_text(encoding='utf-8')
    client = subprocess.Popen(['kubectl', '--context', CONTEXT, '-n', 'monitoring',
                               'exec', '-i', 'deploy/monitoring-grafana', '-c', 'grafana-sc-dashboard',
                               '--', 'python', '-u', '-c', code],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, encoding='utf-8')
    threading.Thread(target=receive, daemon=True).start()
    baseline = read_stage('ready')
    with lock:
        dirty_argo = True
        patch('argocd', 'application', NS, argo_pause)
        # A second restore path also runs on slow/stuck clients. The API must remain reachable.
        timer = threading.Timer(18, restore)
        timer.start()
        dirty_network = True
        patch(NS, 'networkpolicy', 'user-mgmt-module', network_fault)
        report['network_fault_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
    time.sleep(1)  # Let the cluster network enforce the changed rule.
    client.stdin.write('outage\n')
    client.stdin.flush()
    if args.diagnose:
        time.sleep(4)
        kube('-n', NS, 'exec', 'deploy/user-mgmt-backend', '--', 'kill', '-3', '1')
        (run_dir / 'backend-threads.txt').write_text(
            kube('-n', NS, 'logs', 'deploy/user-mgmt-backend', '--since=15s'), encoding='utf-8')
    outage = read_stage('outage', timeout=12)
    restore()
    time.sleep(1)
    client.stdin.write('restored\n')
    client.stdin.flush()
    read_stage('cooldown')
    read_stage('recovery')
    read_stage('passed')
    client.stdin.close()
    assert client.wait(timeout=10) == 0, 'Remote client failed'
    assert outage['module_requests'] == baseline['module_requests'], 'Fault did not isolate downstream'
    report['final_pods'] = pod_summary()
    assert report['initial_pods'] == report['final_pods'], 'Pod readiness, identity or restarts changed'
    assert get(NS, 'networkpolicy', 'user-mgmt-module')['spec'] == policy['spec']
    assert get('argocd', 'application', NS)['spec']['syncPolicy']['automated'] == automated
    report['passed'] = True
finally:
    try:
        restore()
    finally:
        if timer:
            timer.cancel()
        if client and client.poll() is None:
            client.terminate()
        report['ended_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        (run_dir / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print('Report and emergency restore patches:', run_dir, flush=True)
print('PASS outage, bounded 503, open-circuit fast failure, independent login and recovery.')
