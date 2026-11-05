[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repoRoot "k8s\kustomization.yaml"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($path)
$pattern = '(?ms)(- name: store-api-image\s+newName:.*?\s+newTag:)\s+"[^"]+"'

if (-not [regex]::IsMatch($content, $pattern)) {
    throw "Bloco da imagem store-api nao encontrado."
}

$content = [regex]::Replace($content, $pattern, '$1 "2.0"', 1)
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)

Write-Host "Manifesto atualizado para store-api:2.0."
Write-Host "Agora faca commit e push para o Argo CD executar o rolling update:"
Write-Host "  git add k8s/kustomization.yaml"
Write-Host "  git commit -m 'feat: promove store-api para 2.0'"
Write-Host "  git push origin main"
