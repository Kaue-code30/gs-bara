[CmdletBinding()]
param(
    [switch]$SkipClusterCreation
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$clusterFile = Join-Path $repoRoot "cluster.yaml"

if ((Get-Content -LiteralPath $clusterFile -Raw) -match 'AWS_ACCOUNT_ID') {
    throw "Execute scripts/configure-environment.ps1 antes de criar o cluster."
}

if (-not $SkipClusterCreation) {
    eksctl create cluster -f $clusterFile
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar o cluster EKS."
    }
}

aws eks update-kubeconfig --name fiap-store --region us-east-1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao atualizar o kubeconfig."
}

kubectl get --raw=/readyz | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "O cluster nao esta respondendo."
}

kubectl apply -f (Join-Path $repoRoot "k8s\00-namespaces.yaml") | Out-Null

helm repo add traefik https://traefik.github.io/charts --force-update | Out-Null
helm repo add kedacore https://kedacore.github.io/charts --force-update | Out-Null
helm repo update | Out-Null

helm upgrade --install traefik traefik/traefik `
    --namespace traefik --create-namespace `
    --set deployment.replicas=2 --wait
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar o Traefik."
}

helm upgrade --install keda kedacore/keda `
    --namespace keda --create-namespace --wait
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar o KEDA."
}

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl apply -n argocd --server-side --force-conflicts `
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar o Argo CD."
}

kubectl rollout status deployment/argocd-server -n argocd --timeout=5m

$deadline = (Get-Date).AddMinutes(10)
$hostname = ""
while ((Get-Date) -lt $deadline -and -not $hostname) {
    $hostname = (kubectl get service traefik -n traefik `
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null).Trim()
    if (-not $hostname) {
        Start-Sleep -Seconds 10
    }
}

if (-not $hostname) {
    throw "O Load Balancer do Traefik nao recebeu hostname em 10 minutos."
}

Write-Host "Plataforma instalada."
Write-Host "Hostname do Traefik: $hostname"
Write-Host "Proximo passo: .\scripts\configure-environment.ps1 -Hostname '$hostname'"
