param(
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
$opsRoot = Split-Path -Parent $PSScriptRoot
$prepared = Get-Content -LiteralPath (Join-Path $opsRoot 'tmp\managed-databases.json') -Raw | ConvertFrom-Json
if ($prepared.context -ne $Context -or $prepared.namespace -ne $Namespace) { throw 'Prepared database metadata does not match the requested environment.' }
$pg = $prepared.databases.postgres
$backend = kubectl --context $Context -n $Namespace get deployment user-mgmt-backend -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $backend.status.readyReplicas -lt 1) { throw 'Backend must be Ready before verifying its database connections.' }
if ($backend.spec.template.spec.containers[0].envFrom[-1].secretRef.name -ne 'user-mgmt-managed-postgres') {
    throw 'Backend is not configured to use the Managed PostgreSQL Secret.'
}
$podName = 'vsc-pg-verify'
$labels = @{ 'app.kubernetes.io/name' = $podName }
$policy = @{
    apiVersion = 'networking.k8s.io/v1'; kind = 'NetworkPolicy'
    metadata = @{ name = $podName; namespace = $Namespace }
    spec = @{
        podSelector = @{ matchLabels = $labels }; policyTypes = @('Ingress', 'Egress'); ingress = @()
        egress = @(
            @{ to = @(@{ ipBlock = @{ cidr = $pg.cidr } }); ports = @(@{ protocol = 'TCP'; port = [int]$pg.port }) },
            @{ to = @(@{ namespaceSelector = @{ matchLabels = @{ 'kubernetes.io/metadata.name' = 'kube-system' } } });
               ports = @(@{ protocol = 'UDP'; port = 53 }, @{ protocol = 'TCP'; port = 53 }) }
        )
    }
}
$pod = @{
    apiVersion = 'v1'; kind = 'Pod'; metadata = @{ name = $podName; namespace = $Namespace; labels = $labels }
    spec = @{
        restartPolicy = 'Never'; automountServiceAccountToken = $false
        securityContext = @{ runAsNonRoot = $true; runAsUser = 1001; seccompProfile = @{ type = 'RuntimeDefault' } }
        containers = @(@{
            name = 'postgres-client'; image = 'postgres:16-alpine'; command = @('sleep', '600')
            securityContext = @{ allowPrivilegeEscalation = $false; capabilities = @{ drop = @('ALL') } }
            resources = @{ requests = @{ cpu = '50m'; memory = '64Mi' }; limits = @{ cpu = '200m'; memory = '128Mi' } }
            env = @(
                @{ name = 'PGHOST'; value = $pg.host }, @{ name = 'PGPORT'; value = [string]$pg.port },
                @{ name = 'PGDATABASE'; value = $pg.database }, @{ name = 'PGSSLMODE'; value = 'verify-full' },
                @{ name = 'PGSSLROOTCERT'; value = '/etc/postgres-tls/ca.crt' }, @{ name = 'PGCONNECT_TIMEOUT'; value = '15' },
                @{ name = 'PGAPPNAME'; value = $podName }, @{ name = 'PGOPTIONS'; value = '-c default_transaction_read_only=on' },
                @{ name = 'PGUSER'; valueFrom = @{ secretKeyRef = @{ name = 'user-mgmt-managed-postgres'; key = 'SPRING_DATASOURCE_USERNAME' } } },
                @{ name = 'PGPASSWORD'; valueFrom = @{ secretKeyRef = @{ name = 'user-mgmt-managed-postgres'; key = 'SPRING_DATASOURCE_PASSWORD' } } }
            )
            volumeMounts = @(@{ name = 'ca'; mountPath = '/etc/postgres-tls'; readOnly = $true })
        })
        volumes = @(@{ name = 'ca'; secret = @{ secretName = 'user-mgmt-managed-postgres'; items = @(@{ key = 'ca.crt'; path = 'ca.crt' }) } })
    }
}
$createdPolicy = $false
$createdPod = $false
try {
    $policy | ConvertTo-Json -Depth 20 -Compress | kubectl --context $Context create -f -
    if ($LASTEXITCODE -ne 0) { throw 'Could not create verification NetworkPolicy.' }
    $createdPolicy = $true
    $pod | ConvertTo-Json -Depth 20 -Compress | kubectl --context $Context create -f -
    if ($LASTEXITCODE -ne 0) { throw 'Could not create verification client.' }
    $createdPod = $true
    kubectl --context $Context -n $Namespace wait "pod/$podName" --for=condition=Ready --timeout=60s
    if ($LASTEXITCODE -ne 0) { throw 'Verification client did not become Ready.' }
    $sql = @'
SELECT json_build_object(
  'database', current_database(),
  'client_tls', (SELECT version FROM pg_stat_ssl WHERE pid=pg_backend_pid() AND ssl),
  'jdbc_connections', count(*),
  'all_jdbc_tls', coalesce(bool_and(coalesce(s.ssl, false)), false),
  'jdbc_tls_versions', json_agg(DISTINCT s.version)
)
FROM pg_stat_activity a LEFT JOIN pg_stat_ssl s ON s.pid=a.pid
WHERE a.datname=current_database() AND a.application_name='PostgreSQL JDBC Driver';
'@
    $result = $sql | kubectl --context $Context -n $Namespace exec -i $podName -- psql -X -qAt -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'Managed PostgreSQL read-only verification query failed.' }
    $connection = $result | ConvertFrom-Json
    if ($connection.database -ne $pg.database -or -not $connection.client_tls -or
        $connection.jdbc_connections -lt 1 -or -not $connection.all_jdbc_tls) {
        throw 'Expected live encrypted JDBC connections in the managed database.'
    }
    $report = [ordered]@{
        checked_at = (Get-Date).ToString('o'); context = $Context; namespace = $Namespace
        sslmode = 'verify-full'; connection = $connection; backend_image = $backend.spec.template.spec.containers[0].image
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $opsRoot 'tmp\postgres-connection-report.json') -Encoding utf8
    $connection | ConvertTo-Json -Compress
    Write-Output 'PASS: Ready backend uses Managed PostgreSQL with encrypted JDBC connections.'
} finally {
    if ($createdPod) { kubectl --context $Context -n $Namespace delete pod $podName --wait=false }
    if ($createdPolicy) { kubectl --context $Context -n $Namespace delete networkpolicy $podName --wait=false }
}
