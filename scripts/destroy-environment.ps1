[CmdletBinding()]
param(
    [switch]$ConfirmDestruction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$clusterFile = Join-Path $repoRoot "cluster.yaml"

if (-not $ConfirmDestruction) {
    throw "Operacao destrutiva. Execute novamente com -ConfirmDestruction."
}

$context = (kubectl config current-context 2>$null).Trim()
if ($context -notmatch 'fiap-store') {
    throw "Contexto atual inesperado: '$context'. Selecione o cluster fiap-store antes de destruir."
}

kubectl delete application fiap-store -n argocd `
    --ignore-not-found=true --wait=true --timeout=10m

kubectl delete namespace store-prod store-data platform-observer `
    --ignore-not-found=true --wait=true --timeout=10m

$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    $persistentVolumes = kubectl get pv --no-headers 2>$null
    if (-not $persistentVolumes) {
        break
    }
    Write-Host "Aguardando remocao dos volumes persistentes..."
    Start-Sleep -Seconds 10
}

helm uninstall traefik -n traefik --ignore-not-found

eksctl delete cluster -f $clusterFile --disable-nodegroup-eviction
if ($LASTEXITCODE -ne 0) {
    throw "O eksctl informou falha durante a exclusao do cluster."
}

Write-Host "Cluster removido. Confira no console da AWS se nao restaram volumes EBS ou Load Balancers."
