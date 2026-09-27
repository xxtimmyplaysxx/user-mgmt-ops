param(
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
# This cutover is deliberately limited to the known course staging environment.
if ($Context -ne 'do-fra1-vsc-orchestrierung' -or $Namespace -ne 'user-mgmt-staging') {
    throw 'This migration only supports the reviewed course staging environment.'
}
$deployment = kubectl --context $Context -n $Namespace get deployment user-mgmt-backend -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staging backend.' }
if ($deployment.spec.replicas -ne 0) { throw 'Backend must first be scaled to zero through GitOps maintenance values.' }
$pods = kubectl --context $Context -n $Namespace get pods -l app.kubernetes.io/component=backend -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or @($pods.items).Count -ne 0) { throw 'Wait until every staging backend pod has terminated.' }
$hpas = kubectl --context $Context -n $Namespace get hpa -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staging autoscalers.' }
if (@($hpas.items | Where-Object { $_.spec.scaleTargetRef.name -eq 'user-mgmt-backend' }).Count -ne 0) {
    throw 'The backend HPA must be disabled through GitOps before migration.'
}
$config = kubectl --context $Context -n $Namespace get configmap user-mgmt-config -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $config.data.SPRING_DATASOURCE_URL -ne 'jdbc:postgresql://user-mgmt-postgres:5432/usermgmt_staging') {
    throw 'Expected the original staging PostgreSQL URL before cutover.'
}
$backend = @($deployment.spec.template.spec.containers | Where-Object { $_.name -eq 'backend' })
if ($backend.Count -ne 1 -or
    @($backend[0].envFrom | Where-Object { $_.secretRef.name -eq 'user-mgmt-managed-postgres' }).Count -ne 0 -or
    @($backend[0].env | Where-Object { $_.name -eq 'SPRING_DATASOURCE_URL' }).Count -ne 0) {
    throw 'The application may already use Managed PostgreSQL. Refusing to overwrite it.'
}
$sourcePods = kubectl --context $Context -n $Namespace get pods -l app.kubernetes.io/component=postgres -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect source PostgreSQL.' }
$ready = @($sourcePods.items | Where-Object {
    -not $_.metadata.deletionTimestamp -and $_.status.phase -eq 'Running' -and
    @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -eq 1
})
if ($ready.Count -ne 1) { throw 'Expected exactly one Ready source PostgreSQL pod.' }
$sourcePod = $ready[0].metadata.name
$sql = "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND backend_type='client backend' AND pid<>pg_backend_pid();"
$connections = $sql | kubectl --context $Context -n $Namespace exec -i $sourcePod -c postgres -- sh -ceu 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -qAt -v ON_ERROR_STOP=1'
if ($LASTEXITCODE -ne 0 -or ([string]$connections).Trim() -ne '0') {
    throw 'The source database still has other client connections. Do not migrate while a writer may be active.'
}
[pscustomobject]@{ context = $Context; namespace = $Namespace; source_pod = $sourcePod }
