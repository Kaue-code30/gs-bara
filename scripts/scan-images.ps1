[CmdletBinding()]
param(
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repoRoot "avaliacao\trivy"

if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
    throw "Trivy nao encontrado no PATH. Instale-o antes de gerar os relatorios."
}

$accountId = (aws sts get-caller-identity --query Account --output text).Trim()
if ($LASTEXITCODE -ne 0 -or $accountId -notmatch '^\d{12}$') {
    throw "Credenciais AWS invalidas ou expiradas."
}

$registry = "$accountId.dkr.ecr.$Region.amazonaws.com"
$images = [ordered]@{
    "store-api-2.0" = "$registry/store-api:2.0"
    "store-worker-1.0" = "$registry/store-worker:1.0"
    "store-front-1.0" = "$registry/store-front:1.0"
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

foreach ($entry in $images.GetEnumerator()) {
    $tablePath = Join-Path $outputDirectory "$($entry.Key).txt"
    $jsonPath = Join-Path $outputDirectory "$($entry.Key).json"

    $currentErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    trivy image --quiet --skip-java-db-update --scanners vuln --severity HIGH,CRITICAL `
        --format table --output $tablePath $entry.Value
    $tableExitCode = $LASTEXITCODE
    $ErrorActionPreference = $currentErrorPreference
    if ($tableExitCode -ne 0) {
        throw "Falha no scan da imagem $($entry.Value)."
    }

    $currentErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    trivy image --quiet --skip-java-db-update --scanners vuln --severity HIGH,CRITICAL `
        --format json --output $jsonPath $entry.Value
    $jsonExitCode = $LASTEXITCODE
    $ErrorActionPreference = $currentErrorPreference
    if ($jsonExitCode -ne 0) {
        throw "Falha no scan JSON da imagem $($entry.Value)."
    }
}

Write-Host "Relatorios gravados em avaliacao/trivy."
Write-Host "Revise e justifique qualquer vulnerabilidade CRITICAL antes da entrega."
