param(
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
$null = & (Join-Path $PSScriptRoot 'Assert-StagingDatabaseMaintenance.ps1') -Context $Context -Namespace $Namespace
Write-Output 'Maintenance verified: no backend pods, no backend HPA, no other source DB clients.'
$backup = & (Join-Path $PSScriptRoot 'Backup-StagingDatabase.ps1') -Context $Context -Namespace $Namespace -PassThru
if (-not $backup.local_path -or -not $backup.archive_list_verified) { throw 'A verified fresh source backup is required.' }
Write-Output "Fresh source backup verified: $($backup.local_path)"
& (Join-Path $PSScriptRoot 'Test-ManagedPostgresRestore.ps1') -BackupPath $backup.local_path -Context $Context -Namespace $Namespace -RefreshTrialRestore
Write-Output 'Source PostgreSQL and PVC are retained. Next: reviewed GitOps cutover and application verification.'
