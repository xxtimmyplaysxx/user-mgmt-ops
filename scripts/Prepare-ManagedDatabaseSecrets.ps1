param(
    [string]$Context = 'do-fra1-vsc-orchestrierung',
    [string]$Namespace = 'user-mgmt-staging'
)

$ErrorActionPreference = 'Stop'
$opsRoot = Split-Path -Parent $PSScriptRoot
$terraform = Join-Path $env:LOCALAPPDATA 'Programs\Terraform\terraform.exe'
$ids = & $terraform "-chdir=$opsRoot\terraform" output -json database_ids | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $ids.postgres -or -not $ids.mysql) {
    throw 'Terraform must contain both managed databases before preparing Secrets.'
}

$taskToken = (doctl auth token).Trim()
if ($LASTEXITCODE -ne 0 -or -not $taskToken) { throw 'doctl authentication is unavailable.' }
$headers = @{ Authorization = "Bearer $taskToken" }
$endpoints = [ordered]@{}
try {
    foreach ($key in @('postgres', 'mysql')) {
        $id = $ids.$key
        $db = (Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/databases/$id" -Headers $headers).database
        if ($db.status -ne 'online') { throw "$key is not online yet." }
        $connection = $db.private_connection
        if (-not $connection.host -or -not $connection.password) { throw "No private connection for $key." }
        $ca = (Invoke-RestMethod -Uri "https://api.digitalocean.com/v2/databases/$id/ca" -Headers $headers).ca
        $certificate = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ca.certificate))
        if ($certificate -notmatch '^-----BEGIN CERTIFICATE-----') { throw "Invalid CA for $key." }
        $addresses = @([Net.Dns]::GetHostAddresses($connection.host) | Where-Object {
            $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
        })
        if ($addresses.Count -ne 1) { throw "Expected one private IPv4 address for $key." }
        $database = if ($key -eq 'postgres') { 'usermgmt_staging' } else { 'modules' }
        $endpoints[$key] = [ordered]@{
            id = $id; host = $connection.host; port = $connection.port
            database = $database; cidr = "$($addresses[0].IPAddressToString)/32"
        }
        $data = @{ 'ca.crt' = $certificate }
        if ($key -eq 'postgres') {
            $secretName = 'user-mgmt-managed-postgres'
            $data.SPRING_DATASOURCE_URL = "jdbc:postgresql://$($connection.host):$($connection.port)/${database}?sslmode=verify-full&sslrootcert=/etc/postgres-tls/ca.crt"
            $data.SPRING_DATASOURCE_USERNAME = $connection.user
            $data.SPRING_DATASOURCE_PASSWORD = $connection.password
        } else {
            $secretName = 'user-mgmt-module-db'
            $encodedUser = [Uri]::EscapeDataString($connection.user)
            $encodedPassword = [Uri]::EscapeDataString($connection.password)
            $data.DATABASE_URL = "mysql+pymysql://${encodedUser}:${encodedPassword}@$($connection.host):$($connection.port)/$database"
        }
        # Credentials travel on stdin, never in arguments, files, or terminal output.
        # Server-side apply avoids a last-applied annotation containing the Secret.
        $encodedData = @{}
        foreach ($field in $data.Keys) {
            $encodedData[$field] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($data[$field]))
        }
        $secret = @{
            apiVersion = 'v1'; kind = 'Secret'; type = 'Opaque'
            metadata = @{ name = $secretName; namespace = $Namespace }
            data = $encodedData
        }
        $result = $secret | ConvertTo-Json -Depth 10 -Compress |
            kubectl --context $Context apply --server-side --field-manager=vsc-database-preparation -f - 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Could not apply $secretName. Secret payload/output deliberately withheld." }
        Write-Output "Secret prepared: $Namespace/$secretName"
    }
    $tmp = Join-Path $opsRoot 'tmp'
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $metadata = @{ context = $Context; namespace = $Namespace; databases = $endpoints }
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tmp 'managed-databases.json') -Encoding utf8
    Write-Output 'Private endpoint metadata saved under tmp/ (no credentials). Applications have not been switched.'
} finally {
    $taskToken = $null; $headers = $null; $db = $null; $connection = $null
    $data = $null; $encodedData = $null; $secret = $null; $result = $null
    $encodedPassword = $null
}
