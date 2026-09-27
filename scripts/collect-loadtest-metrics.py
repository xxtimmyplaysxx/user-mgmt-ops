"""Export non-secret Prometheus time series through the authenticated Kubernetes API."""
import argparse
import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlencode

parser = argparse.ArgumentParser()
parser.add_argument('--start', required=True, help='ISO timestamp including timezone')
parser.add_argument('--end', required=True, help='ISO timestamp including timezone')
parser.add_argument('--output', required=True)
args = parser.parse_args()
start = dt.datetime.fromisoformat(args.start.replace('Z', '+00:00'))
end = dt.datetime.fromisoformat(args.end.replace('Z', '+00:00'))
if not start.tzinfo or not end.tzinfo or not start < end <= dt.datetime.now(dt.timezone.utc):
    raise SystemExit('Use an ordered time window with explicit timezones, ending in the past.')

context = 'do-fra1-vsc-orchestrierung'
ns = 'user-mgmt-staging'
pod_filter = f'namespace="{ns}",container="backend"'
# Authentication is handled in a security filter and is labelled uri=UNKNOWN.
# Keep all business API requests instead of silently excluding these logins.
api = f'namespace="{ns}",uri!~"/actuator.*"'
queries = {
    'cpu_cores': f'sum by(pod)(rate(container_cpu_usage_seconds_total{{{pod_filter}}}[1m]))',
    'memory_bytes': f'max by(pod)(container_memory_working_set_bytes{{{pod_filter}}})',
    'restarts': f'max by(pod)(kube_pod_container_status_restarts_total{{{pod_filter}}})',
    'oom_events': f'max by(pod)(container_oom_events_total{{{pod_filter}}})',
    'available_replicas': f'max(kube_deployment_status_replicas_available{{namespace="{ns}",deployment="user-mgmt-backend"}})',
    'desired_replicas': f'max(kube_horizontalpodautoscaler_status_desired_replicas{{namespace="{ns}",horizontalpodautoscaler="user-mgmt-backend"}})',
    'request_rate': f'sum(rate(http_server_requests_seconds_count{{{api}}}[1m]))',
    'request_p95_seconds': f'histogram_quantile(0.95,sum by(le)(rate(http_server_requests_seconds_bucket{{{api}}}[1m])))',
}
total = f'sum(rate(http_server_requests_seconds_count{{{api}}}[1m]))'
errors = f'sum(rate(http_server_requests_seconds_count{{{api},status=~"5.."}}[1m]))'
queries['server_5xx_ratio'] = f'({errors} or (0 * {total})) / clamp_min({total},0.001)'

def kubectl(*command):
    result = subprocess.run(['kubectl', '--context', context, *command],
                            capture_output=True, text=True, timeout=45, check=True)
    return json.loads(result.stdout)

job = kubectl('-n', ns, 'get', 'job', 'user-mgmt-loadtest', '-o', 'json')
deployment = kubectl('-n', ns, 'get', 'deployment', 'user-mgmt-backend', '-o', 'json')
application = kubectl('-n', 'argocd', 'get', 'application', 'user-mgmt-staging', '-o', 'json')
log = subprocess.run(['kubectl', '--context', context, '-n', ns, 'logs', 'job/user-mgmt-loadtest'],
                     capture_output=True, text=True, encoding='utf-8', timeout=45, check=True).stdout
success = re.search(r'business_success\.{2,}:\s+([\d.]+)%\s+(\d+) out of (\d+)', log)
failed = re.search(r'http_req_failed\.{2,}:\s+([\d.]+)%', log)
duration = re.search(r'^\s*http_req_duration\.{2,}:\s*(.+)$', log, re.MULTILINE)
iterations = re.findall(r'(\d+) complete and (\d+) interrupted iterations', log)
max_vus = re.search(r'vus_max\.{2,}:\s+(\d+)', log)
if not all([success, failed, duration, iterations, max_vus]):
    raise SystemExit('The complete k6 summary is not available.')
p95 = re.search(r'p\(95\)=([\d.]+)(ms|s)', duration[1])
if not p95:
    raise SystemExit('Cannot read k6 P95 unit.')
document = {
    'collected_at': dt.datetime.now(dt.timezone.utc).isoformat(),
    'context': context, 'namespace': ns, 'start': args.start, 'end': args.end, 'step_seconds': 15,
    'job': {'uid': job['metadata']['uid'], 'status': job['status']},
    'image': deployment['spec']['template']['spec']['containers'][0]['image'],
    'ops_revision': application['status']['sync']['revision'], 'series': {},
    'k6': {'successful_logins': int(success[2]), 'requests': int(success[3]),
           'success_percent': float(success[1]), 'http_failed_percent': float(failed[1]),
           'p95_seconds': float(p95[1]) / (1000 if p95[2] == 'ms' else 1),
           'interrupted_iterations': int(iterations[-1][1]), 'max_vus': int(max_vus[1])},
}
path = '/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-prometheus:9090/proxy/api/v1/query_range'
for name, expression in queries.items():
    url = path + '?' + urlencode({'query': expression, 'start': args.start, 'end': args.end, 'step': '15s'})
    response = kubectl('get', '--raw', url)
    if response.get('status') != 'success' or not response['data']['result']:
        raise SystemExit(f'Missing or invalid Prometheus result for {name}')
    document['series'][name] = {'query': expression, 'result': response['data']['result']}
    print(f'{name}: {len(response["data"]["result"])} series exported')
target = Path(args.output)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(document, indent=2) + '\n', encoding='utf-8')
target.with_suffix('.k6.txt').write_text(log[log.index('THRESHOLDS'):], encoding='utf-8')
print(f'Saved non-secret metrics: {target}')
