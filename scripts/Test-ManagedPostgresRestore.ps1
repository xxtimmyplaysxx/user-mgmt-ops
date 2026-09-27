param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
$opsRoot = Split-Path -Parent $PSScriptRoot
$metadataPath = "$BackupPath.metadata.json"
$backup = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$prepared = Get-Content -LiteralPath (Join-Path $opsRoot 'tmp\managed-databases.json') -Raw | ConvertFrom-Json
if ($prepared.context -ne $Context -or $prepared.namespace -ne $Namespace -or
    $backup.context -ne $Context -or $backup.namespace -ne $Namespace) {
    throw 'Backup, prepared Secrets, namespace, and context must match.'
}
if ((Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $backup.sha256) {
    throw 'Backup checksum mismatch.'
}
$pg = $prepared.databases.postgres
$podName = 'vsc-db-migration'
$labels = @{ 'app.kubernetes.io/name' = $podName }
$policy = @{
    apiVersion = 'networking.k8s.io/v1'; kind = 'NetworkPolicy'
    metadata = @{ name = $podName; namespace = $Namespace }
    spec = @{
        podSelector = @{ matchLabels = $labels }; policyTypes = @('Egress', 'Ingress')
        ingress = @()
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
            name = 'postgres-client'; image = 'postgres:16-alpine'; command = @('sleep', '3600')
            securityContext = @{ allowPrivilegeEscalation = $false; capabilities = @{ drop = @('ALL') } }
            resources = @{ requests = @{ cpu = '50m'; memory = '64Mi' }; limits = @{ cpu = '200m'; memory = '128Mi' } }
            env = @(
                @{ name = 'PGHOST'; value = $pg.host }, @{ name = 'PGPORT'; value = [string]$pg.port },
                @{ name = 'PGDATABASE'; value = $pg.database }, @{ name = 'PGSSLMODE'; value = 'verify-full' },
                @{ name = 'PGSSLROOTCERT'; value = '/etc/postgres-tls/ca.crt' }, @{ name = 'PGCONNECT_TIMEOUT'; value = '15' },
                @{ name = 'PGUSER'; valueFrom = @{ secretKeyRef = @{ name = 'user-mgmt-managed-postgres'; key = 'SPRING_DATASOURCE_USERNAME' } } },
                @{ name = 'PGPASSWORD'; valueFrom = @{ secretKeyRef = @{ name = 'user-mgmt-managed-postgres'; key = 'SPRING_DATASOURCE_PASSWORD' } } }
            )
            volumeMounts = @(@{ name = 'ca'; mountPath = '/etc/postgres-tls'; readOnly = $true })
        })
        volumes = @(@{ name = 'ca'; secret = @{ secretName = 'user-mgmt-managed-postgres'; items = @(@{ key = 'ca.crt'; path = 'ca.crt' }) } })
    }
}
$createdPod = $false
$createdPolicy = $false
try {
    # create (not apply): never take over or delete somebody else's existing pod/policy.
    $policy | ConvertTo-Json -Depth 20 -Compress | kubectl --context $Context create -f -
    if ($LASTEXITCODE -ne 0) { throw 'Could not create migration NetworkPolicy.' }
    $createdPolicy = $true
    $pod | ConvertTo-Json -Depth 20 -Compress | kubectl --context $Context create -f -
    if ($LASTEXITCODE -ne 0) { throw 'Could not create migration client Pod.' }
    $createdPod = $true
    kubectl --context $Context -n $Namespace wait "pod/$podName" --for=condition=Ready --timeout=60s
    if ($LASTEXITCODE -ne 0) { throw 'Migration client Pod did not become Ready.' }

    $tableCount = kubectl --context $Context -n $Namespace exec $podName -- psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f');"
    if ($LASTEXITCODE -ne 0) { throw 'Managed PostgreSQL connection/TLS test failed.' }
    if ([string]$tableCount -ne '0') { throw 'Target public schema is not empty. Refusing to overwrite existing data.' }
    Push-Location (Split-Path -Parent (Resolve-Path -LiteralPath $BackupPath).Path)
    try {
        kubectl --context $Context -n $Namespace cp "./$(Split-Path -Leaf $BackupPath)" "${podName}:/tmp/restore.dump"
        if ($LASTEXITCODE -ne 0) { throw 'Could not copy backup to migration client.' }
    } finally { Pop-Location }
    $copiedHash = kubectl --context $Context -n $Namespace exec $podName -- sha256sum /tmp/restore.dump
    if ($LASTEXITCODE -ne 0 -or ($copiedHash -split '\s+')[0] -ne $backup.sha256) { throw 'Copied backup checksum mismatch.' }
    # One transaction: a failure rolls back the entire restore. No DROP/clean option.
    kubectl --context $Context -n $Namespace exec $podName -- sh -ceu 'pg_restore --dbname="$PGDATABASE" --no-owner --no-acl --exit-on-error --single-transaction /tmp/restore.dump'
    if ($LASTEXITCODE -ne 0) { throw 'Restore failed; transaction rolled back.' }

    $sql = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'database-fingerprint.sql') -Raw
    $target = @($sql | kubectl --context $Context -n $Namespace exec -i $podName -- psql -X -qAt -v ON_ERROR_STOP=1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not fingerprint restored database.' }
    $source = @($sql | kubectl --context $Context -n $Namespace exec -i $backup.source_pod -c postgres -- sh -ceu 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -qAt -v ON_ERROR_STOP=1')
    if ($LASTEXITCODE -ne 0) { throw 'Could not fingerprint source database.' }
    $matched = ($target.Count -gt 0) -and (($source -join "`n") -ceq ($target -join "`n"))
    $tls = kubectl --context $Context -n $Namespace exec $podName -- psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT ssl, version FROM pg_stat_ssl WHERE pid=pg_backend_pid();'
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify TLS session.' }
    $report = [ordered]@{
        checked_at = (Get-Date).ToString('o'); context = $Context; namespace = $Namespace
        backup_sha256 = $backup.sha256; restore_successful = $true
        tls = [string]$tls; sslmode = 'verify-full'; fingerprints_match_current_source = $matched
        checked_objects = $target.Count; application_switched = $false
    }
    $report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $opsRoot 'tmp\postgres-restore-report.json') -Encoding utf8
    $backup.restore_tested = $true
    $backup | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8
    Write-Output "Restore completed over TLS ($tls). Compared $($target.Count) tables/sequences; current source matches: $matched."
    if (-not $matched) { throw 'Restore succeeded, but source/target differ. Source may have changed since backup. Do not switch the application.' }
    Write-Output 'Application still uses the old database. Final cutover requires a write freeze and a fresh backup/data comparison.'
} finally {
    if ($createdPod) { kubectl --context $Context -n $Namespace delete pod $podName --wait=false }
    if ($createdPolicy) { kubectl --context $Context -n $Namespace delete networkpolicy $podName --wait=false }
}
