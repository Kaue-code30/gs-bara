[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$deploymentFiles = @(
    (Join-Path $repoRoot "cluster.yaml"),
    (Join-Path $repoRoot "k8s\kustomization.yaml"),
    (Join-Path $repoRoot "k8s\60-ingress.yaml")
)
$unresolved = $deploymentFiles | Select-String -Pattern 'AWS_ACCOUNT_ID|STORE_HOSTNAME'
if ($unresolved) {
    throw "Existem placeholders nao resolvidos. Execute scripts/configure-environment.ps1."
}

$gitChanges = git -C $repoRoot status --porcelain
if ($gitChanges) {
    throw "Ha alteracoes locais sem commit. O Argo CD le o GitHub; faca commit e push antes de continuar."
}

git -C $repoRoot fetch origin main
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao consultar origin/main."
}

$localCommit = (git -C $repoRoot rev-parse HEAD).Trim()
$remoteCommit = (git -C $repoRoot rev-parse origin/main).Trim()
if ($localCommit -ne $remoteCommit) {
    throw "O commit local ainda nao esta publicado em origin/main."
}

kubectl apply -f (Join-Path $repoRoot "k8s\90-argocd-application.yaml")
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar a Application do Argo CD."
}

$deadline = (Get-Date).AddMinutes(12)
do {
    $sync = (kubectl get application fiap-store -n argocd `
        -o jsonpath='{.status.sync.status}' 2>$null).Trim()
    $health = (kubectl get application fiap-store -n argocd `
        -o jsonpath='{.status.health.status}' 2>$null).Trim()
    Write-Host "Argo CD: sync=$sync health=$health"
    if ($sync -eq "Synced" -and $health -eq "Healthy") {
        break
    }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)

if ($sync -ne "Synced" -or $health -ne "Healthy") {
    throw "A Application nao ficou Synced/Healthy no tempo esperado."
}

kubectl rollout status deployment/store-api -n store-prod --timeout=5m
kubectl rollout status deployment/store-front -n store-prod --timeout=5m
kubectl rollout status statefulset/store-db -n store-data --timeout=5m

Write-Host "Aplicacao sincronizada e saudavel."
