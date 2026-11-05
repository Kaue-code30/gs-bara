[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^\d{12}$')]
    [string]$AccountId,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$Hostname
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $AccountId) {
    $AccountId = (aws sts get-caller-identity --query Account --output text).Trim()
    if ($LASTEXITCODE -ne 0 -or $AccountId -notmatch '^\d{12}$') {
        throw "Nao foi possivel descobrir o Account ID da AWS."
    }
}

$clusterPath = Join-Path $repoRoot "cluster.yaml"
$cluster = [System.IO.File]::ReadAllText($clusterPath)
$cluster = [regex]::Replace(
    $cluster,
    'arn:aws:iam::(?:AWS_ACCOUNT_ID|\d{12}):role/LabRole',
    "arn:aws:iam::$AccountId`:role/LabRole"
)
[System.IO.File]::WriteAllText($clusterPath, $cluster, $utf8NoBom)

$kustomizationPath = Join-Path $repoRoot "k8s\kustomization.yaml"
$kustomization = [System.IO.File]::ReadAllText($kustomizationPath)
$kustomization = [regex]::Replace(
    $kustomization,
    '(?:AWS_ACCOUNT_ID|\d{12})\.dkr\.ecr\.us-east-1\.amazonaws\.com',
    "$AccountId.dkr.ecr.us-east-1.amazonaws.com"
)
[System.IO.File]::WriteAllText($kustomizationPath, $kustomization, $utf8NoBom)

if ($Hostname) {
    $ingressPath = Join-Path $repoRoot "k8s\60-ingress.yaml"
    $ingress = [System.IO.File]::ReadAllText($ingressPath)
    $hostMatch = [regex]::Match($ingress, 'fiap\.io/public-host:\s*([^\s]+)')
    if (-not $hostMatch.Success) {
        throw "A anotacao fiap.io/public-host nao foi encontrada no Ingress."
    }
    $previousHost = $hostMatch.Groups[1].Value
    $ingress = $ingress.Replace($previousHost, $Hostname)
    [System.IO.File]::WriteAllText($ingressPath, $ingress, $utf8NoBom)
}

Write-Host "Account ID configurado: $AccountId"
if ($Hostname) {
    Write-Host "Hostname publico configurado: $Hostname"
} else {
    Write-Host "Hostname ainda nao alterado. Execute novamente com -Hostname depois que o Traefik receber o Load Balancer."
}
