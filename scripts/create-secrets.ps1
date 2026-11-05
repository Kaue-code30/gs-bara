[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$Hostname,

    [Parameter()]
    [string]$DatabasePassword
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

kubectl apply -f (Join-Path $repoRoot "k8s\00-namespaces.yaml") | Out-Null

if (-not $DatabasePassword) {
    foreach ($namespace in @("store-data", "store-prod")) {
        $currentErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $encoded = kubectl get secret store-db-credentials -n $namespace `
            -o jsonpath='{.data.password}' 2>$null
        $getSecretExitCode = $LASTEXITCODE
        $ErrorActionPreference = $currentErrorPreference
        if ($getSecretExitCode -eq 0 -and $encoded) {
            $DatabasePassword = [System.Text.Encoding]::UTF8.GetString(
                [System.Convert]::FromBase64String($encoded)
            )
            break
        }
    }
}

if (-not $DatabasePassword) {
    $alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $characters = foreach ($byte in $bytes) {
        $alphabet[$byte % $alphabet.Length]
    }
    $DatabasePassword = -join $characters
}

foreach ($namespace in @("store-prod", "store-data")) {
    kubectl create secret generic store-db-credentials `
        -n $namespace `
        --from-literal="password=$DatabasePassword" `
        --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar o Secret do banco em $namespace."
    }
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("fiap-store-tls-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
$certificatePath = Join-Path $temporaryDirectory "tls.crt"
$privateKeyPath = Join-Path $temporaryDirectory "tls.key"

try {
    $currentErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 30 `
        -keyout $privateKeyPath `
        -out $certificatePath `
        -subj "/CN=fiap-store" `
        -addext "subjectAltName=DNS:$Hostname" 2>$null
    $opensslExitCode = $LASTEXITCODE
    $ErrorActionPreference = $currentErrorPreference
    if ($opensslExitCode -ne 0) {
        throw "Falha ao gerar o certificado TLS."
    }

    kubectl create secret tls store-tls `
        -n store-prod `
        --cert=$certificatePath `
        --key=$privateKeyPath `
        --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar o Secret TLS."
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Host "Secrets criados nos namespaces corretos. Nenhum valor foi gravado no repositorio."
