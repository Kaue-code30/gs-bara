# Relatórios do Trivy

Os relatórios das três imagens construídas pelo grupo são gerados por:

```powershell
.\scripts\scan-images.ps1
```

Antes da entrega, revisar os arquivos `.txt` e `.json` gerados. Toda vulnerabilidade `CRITICAL`
deve ser corrigida ou acompanhada de uma justificativa técnica documentada neste diretório.

Não adicionar credenciais AWS, tokens do ECR nem outros segredos aos relatórios.
