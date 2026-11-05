[CmdletBinding()]
param(
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$accountId = (aws sts get-caller-identity --query Account --output text).Trim()
if ($LASTEXITCODE -ne 0 -or $accountId -notmatch '^\d{12}$') {
    throw "Credenciais AWS invalidas ou expiradas."
}

$registry = "$accountId.dkr.ecr.$Region.amazonaws.com"

foreach ($repository in @("store-api", "store-worker", "store-front")) {
    aws ecr describe-repositories --repository-names $repository --region $Region *> $null
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository `
            --repository-name $repository `
            --region $Region `
            --image-scanning-configuration scanOnPush=true | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao criar o repositorio ECR $repository."
        }
    }
}

$ecrPassword = aws ecr get-login-password --region $Region
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao obter o token de login do ECR."
}
$ecrPassword | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) {
    throw "Falha no login do Docker no ECR."
}

function Invoke-DockerBuild {
    param([string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no build/push: docker $($Arguments -join ' ')"
    }
}

Invoke-DockerBuild @(
    "buildx", "build", "--platform", "linux/amd64",
    "--build-arg", "APP_VERSION=1.0",
    "-t", "$registry/store-api:1.0", "--push",
    (Join-Path $repoRoot "store-api")
)
Invoke-DockerBuild @(
    "buildx", "build", "--platform", "linux/amd64",
    "--build-arg", "APP_VERSION=2.0",
    "-t", "$registry/store-api:2.0", "--push",
    (Join-Path $repoRoot "store-api")
)
Invoke-DockerBuild @(
    "buildx", "build", "--platform", "linux/amd64",
    "-t", "$registry/store-worker:1.0", "--push",
    (Join-Path $repoRoot "store-worker")
)
Invoke-DockerBuild @(
    "buildx", "build", "--platform", "linux/amd64",
    "-t", "$registry/store-front:1.0", "--push",
    (Join-Path $repoRoot "store-front")
)

Write-Host "Imagens publicadas em $registry."
