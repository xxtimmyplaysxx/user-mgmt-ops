# Prepares a dedicated synthetic user and k6 inputs. Does not start the load test.
$ErrorActionPreference = 'Stop'
$context = 'do-fra1-vsc-orchestrierung'
$namespace = 'user-mgmt-staging'
$opsRoot = Split-Path -Parent $PSScriptRoot

$job = kubectl --context $context -n $namespace get job user-mgmt-loadtest --ignore-not-found -o name
if ($LASTEXITCODE -ne 0) { throw 'Cannot check existing load-test Job.' }
if ($job) { throw 'A load-test Job already exists. Preserve its results and review it before starting another run.' }
$backend = kubectl --context $context -n $namespace get deployment user-mgmt-backend -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $backend.status.readyReplicas -lt 1) { throw 'Staging backend must be Ready.' }
$nodes = kubectl --context $context get nodes -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot check node health.' }
foreach ($node in $nodes.items) {
    if (@($node.status.conditions | Where-Object { ($_.type -eq 'Ready' -and $_.status -ne 'True') -or ($_.type -match 'Pressure$' -and $_.status -eq 'True') }).Count) {
        throw 'A worker is not Ready or has resource pressure. Resolve this before a load test.'
    }
}

try {
    # Secret contents stay in memory and are never printed or written to disk.
    $existing = kubectl --context $context -n $namespace get secret loadtest-credentials --ignore-not-found -o json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check load-test credentials.' }
    $register = -not [bool]$existing
    if ($register) {
        $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 32
        $random.GetBytes($bytes)
        $random.Dispose()
        $credentials = @{ email = "vsc-loadtest-$([guid]::NewGuid().ToString('N'))@example.com"; password = [Convert]::ToBase64String($bytes) }
    } else {
        $secret = $existing | ConvertFrom-Json
        if ($secret.metadata.labels.'app.kubernetes.io/managed-by' -ne 'vsc-loadtest') { throw 'Existing credentials were not created by this helper.' }
        $credentials = @{
            email = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.TEST_EMAIL))
            password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.TEST_PASSWORD))
        }
    }
    $payload = @{ credentials = $credentials; register = $register } | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    # Use the existing sidecar's Python to reach the internal API. The script,
    # including credentials, travels on stdin, never in process arguments.
    $probe = @'
import base64, json
from urllib.request import Request, urlopen
from urllib.error import HTTPError
config = json.loads(base64.b64decode('__PAYLOAD__'))
base = 'http://user-mgmt-backend.user-mgmt-staging.svc:8080'
def call(path, data, expected):
    try:
        with urlopen(Request(base + path, json.dumps(data).encode(), {'Content-Type': 'application/json'}), timeout=20) as response:
            if response.status != expected:
                raise SystemExit(f'{path}: unexpected HTTP {response.status}')
    except HTTPError as error:
        raise SystemExit(f'{path}: HTTP {error.code}')
    except Exception:
        raise SystemExit(f'{path}: connection failed')
if config['register']:
    call('/users/register', dict(config['credentials'], firstName='VSC', lastName='Loadtest'), 201)
call('/users/login', config['credentials'], 200)
print('PASS dedicated load-test user can log in; no credentials printed.')
'@
    $probe.Replace('__PAYLOAD__', $encoded) | kubectl --context $context -n monitoring exec -i deploy/monitoring-grafana -c grafana-sc-dashboard -- python -
    if ($LASTEXITCODE -ne 0) { throw 'Load-test user preparation failed.' }
    if ($register) {
        @{
            apiVersion = 'v1'; kind = 'Secret'; type = 'Opaque'
            metadata = @{ name = 'loadtest-credentials'; namespace = $namespace; labels = @{ 'app.kubernetes.io/managed-by' = 'vsc-loadtest' } }
            stringData = @{ TEST_EMAIL = $credentials.email; TEST_PASSWORD = $credentials.password }
        } | ConvertTo-Json -Depth 6 -Compress | kubectl --context $context create -f -
        if ($LASTEXITCODE -ne 0) { throw 'Could not store the load-test Secret.' }
    }
} finally {
    $credentials = $null; $secret = $null; $existing = $null; $payload = $null; $encoded = $null; $bytes = $null
}

$configMap = kubectl --context $context -n $namespace create configmap user-mgmt-loadtest "--from-file=test.js=$(Join-Path $opsRoot 'loadtest/test.js')" --dry-run=client -o json
if ($LASTEXITCODE -ne 0) { throw 'Could not build the k6 ConfigMap.' }
$configMap | kubectl --context $context apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the k6 ConfigMap.' }
kubectl --context $context apply --dry-run=server -f (Join-Path $opsRoot 'loadtest/job.yaml')
if ($LASTEXITCODE -ne 0) { throw 'The load-test manifest was rejected.' }
Write-Host 'Ready: credentials and test script prepared; load test has NOT started.'
