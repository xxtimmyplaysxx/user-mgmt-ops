param(
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
$opsRoot = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $opsRoot 'tmp\backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupName = "$Namespace-$stamp.dump"
$localBackup = Join-Path $backupDir $backupName
$remoteBackup = "/tmp/$backupName"

$podList = kubectl --context $Context -n $Namespace get pods -l app.kubernetes.io/component=postgres -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not list source database pods.' }
$runningPods = @($podList.items | Where-Object { $_.status.phase -eq 'Running' })
if ($runningPods.Count -ne 1) { throw 'Expected exactly one running source PostgreSQL pod.' }
$sourcePod = $runningPods[0].metadata.name

# A consistent pg_dump snapshot; no passwords or row contents enter terminal output.
$dumpScript = 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-acl --file="$1"; pg_restore --list "$1" >/dev/null'
kubectl --context $Context -n $Namespace exec $sourcePod -c postgres -- sh -ceu $dumpScript sh $remoteBackup
if ($LASTEXITCODE -ne 0) { throw 'Database dump or archive verification failed.' }

# kubectl cp interprets a Windows drive colon as a remote spec, so use a relative path.
Push-Location $backupDir
try {
    kubectl --context $Context -n $Namespace cp "${sourcePod}:$remoteBackup" "./$backupName" -c postgres
    if ($LASTEXITCODE -ne 0) { throw 'Could not download the database archive.' }
} finally {
    Pop-Location
}
if ((Get-Item -LiteralPath $localBackup).Length -eq 0) { throw 'Downloaded backup is empty.' }

$localHash = (Get-FileHash -LiteralPath $localBackup -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteHashOutput = kubectl --context $Context -n $Namespace exec $sourcePod -c postgres -- sha256sum $remoteBackup
if ($LASTEXITCODE -ne 0) { throw 'Could not verify source archive checksum.' }
$remoteHash = ($remoteHashOutput -split '\s+')[0].ToLowerInvariant()
if ($localHash -ne $remoteHash) { throw 'Backup checksum mismatch.' }

# Save only metadata alongside the ignored archive. Keep the actual dump out of Git.
$metadata = [ordered]@{
    created_at = (Get-Date).ToString('o')
    context = $Context
    namespace = $Namespace
    source_pod = $sourcePod
    remote_path = $remoteBackup
    local_path = $localBackup
    bytes = (Get-Item -LiteralPath $localBackup).Length
    sha256 = $localHash
    archive_list_verified = $true
    restore_tested = $false
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath "$localBackup.metadata.json" -Encoding utf8
Write-Output "Backup verified (archive readable, SHA256 matches): $localBackup"
Write-Output "Size: $($metadata.bytes) bytes. Restore test is the next migration step."
