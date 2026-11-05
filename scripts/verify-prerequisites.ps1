[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$requiredCommands = @(
    "aws",
    "docker",
    "eksctl",
    "git",
    "helm",
    "kubectl",
    "openssl"
)

$missing = @()
foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        $missing += $commandName
    }
}

if ($missing.Count -gt 0) {
    throw "Ferramentas ausentes no PATH: $($missing -join ', ')"
}

$identity = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "As credenciais do AWS Academy nao estao validas. Inicie o Learner Lab e atualize o perfil AWS."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw "O Docker Desktop nao esta em execucao."
}

Write-Host "Pre-requisitos OK."
Write-Host "Conta AWS: $($identity.Account)"
Write-Host "Identidade: $($identity.Arn)"
