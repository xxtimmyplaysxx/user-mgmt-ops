"""Internal helper for verify-module-outage.py; credentials stay in this process."""
import concurrent.futures
import datetime as dt
import json
import secrets
import sys
import time
import uuid
from urllib.error import HTTPError
from urllib.request import Request, urlopen

BASE = 'http://user-mgmt-backend.user-mgmt-staging.svc:8080'
MODULE = 'http://user-mgmt-module.user-mgmt-staging.svc:8080'


def call(method, path, body=None, token=None, base=BASE):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = token
    data = json.dumps(body).encode() if body is not None else None
    start = time.monotonic()
    try:
        response = urlopen(Request(base + path, data, headers, method=method), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        result = response.read()
        return response.status, response.headers, result, round(time.monotonic() - start, 4)


def metric_count():
    status, _, body, _ = call('GET', '/metrics', base=MODULE)
    assert status == 200
    return sum(float(line.rsplit(' ', 1)[1]) for line in body.decode().splitlines()
               if line.startswith('module_http_requests_total{'))


def emit(stage, **data):
    print(json.dumps({'stage': stage, 'at': dt.datetime.now(dt.timezone.utc).isoformat(),
                      **data}), flush=True)


email = f'vsc-resilience-{uuid.uuid4().hex}@example.com'
password = secrets.token_urlsafe(24)
status, _, body, _ = call('POST', '/users/register', {
    'firstName': 'VSC', 'lastName': 'Resilience', 'email': email, 'password': password})
assert status == 201, f'Registration status: {status}'
user_id = json.loads(body)['id']
status, headers, _, _ = call('POST', '/users/login', {'email': email, 'password': password})
assert status == 200 and headers.get('Authorization')
token = headers['Authorization']
path = f'/users/{user_id}/modules/c02f58f2-3aca-4f1e-8076-bacf6f1999e6'


def assign():
    status, _, _, elapsed = call('PUT', path, token=token)
    return {'status': status, 'seconds': elapsed}


baseline = [assign() for _ in range(3)]
assert all(row['status'] == 204 for row in baseline), 'Baseline assignment failed'
emit('ready', baseline=baseline, module_requests=metric_count())
assert sys.stdin.readline().strip() == 'outage'
started = time.monotonic()
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    failures = list(pool.map(lambda _: assign(), range(5)))
fast = [assign() for _ in range(3)]
login, _, _, login_seconds = call('POST', '/users/login', {'email': email, 'password': password})
health, _, _, _ = call('GET', '/actuator/health/readiness')
module_health, _, _, _ = call('GET', '/health/ready', base=MODULE)
emit('outage', failures=failures, fast_failures=fast, login_status=login,
     login_seconds=login_seconds, backend_readiness=health, module_readiness=module_health,
     module_requests=metric_count())
assert sys.stdin.readline().strip() == 'restored'
# The healthy module is reachable while the breaker is still cooling down.
before = metric_count()
cooldown = [assign() for _ in range(3)]
after = metric_count()
emit('cooldown', results=cooldown, module_requests_before=before,
     module_requests_after=after)
# Opens after failed logical calls (~3.4-6.4 s); allow its 15 s open interval.
time.sleep(max(0, 24 - (time.monotonic() - started)))
recovery = [assign() for _ in range(3)]
emit('recovery', results=recovery, module_requests=metric_count())
assert all(row['status'] == 503 and row['seconds'] < 8 for row in failures)
assert all(row['status'] == 503 and row['seconds'] < .5 for row in fast + cooldown)
assert login == health == module_health == 200
assert before == after, 'Open circuit still sent downstream requests'
assert all(row['status'] == 204 for row in recovery)
emit('passed')
