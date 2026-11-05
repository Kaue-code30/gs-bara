# FIAP Store — Global Solution no Amazon EKS

Projeto final de Cloud Developer II — Kubernetes e Serverless. A aplicação fornecida é executada
em Amazon EKS com alta disponibilidade, segurança, escalonamento automático e entrega por GitOps.

## Integrantes

| Integrante | RM |
|---|---|
| Kaue Lima | 562071 |
| Dorivaldo Cordeiro | 565225 |

## Arquitetura

```text
Internet (HTTPS)
       |
   Traefik (AWS Load Balancer)
       |
   store-ingress ─────────────── namespace store-prod (Pod Security restricted)
     /api       /
       |       |
  store-api  store-front
   3..6 Pods    2 Pods
       |
       +---- Redis/pedidos ---- store-worker 0..5 Pods (KEDA)
       |
   PostgreSQL/EBS              namespace store-data
       ^
       ├── db-migrate (Job)
       └── store-report (CronJob)

Argo CD sincroniza k8s/ com prune e selfHeal.
Um DaemonSet de observação roda em todos os nós.
```

Decisões principais:

- cluster `fiap-store` em `us-east-1`, com quatro nós `t3.medium` distribuídos em três zonas;
- nós públicos, sem NAT Gateway, conforme as limitações do AWS Academy;
- `LabRole` para cluster e node group, sem OIDC/IRSA;
- Traefik para Ingress, KEDA para escala a zero e Argo CD para GitOps;
- PostgreSQL em StatefulSet com volume `gp3` provisionado pelo EBS CSI;
- namespace `store-prod` com Pod Security `restricted`;
- default deny no `store-data`, liberando somente os fluxos necessários;
- senha do banco e chave TLS criadas diretamente no cluster, nunca armazenadas no Git;
- Kustomize para organizar e parametrizar as imagens.

## Estrutura

```text
cluster.yaml                 definição do EKS
k8s/                         estado desejado sincronizado pelo Argo CD
scripts/                     criação, publicação, validação e destruição
store-api/                   API e Job de migração
store-worker/                worker e CronJob de relatório
store-front/                 interface web
avaliacao/verifica-gs.sh     corretor automático
avaliacao/trivy/             relatórios de vulnerabilidades
```

## Pré-requisitos

- AWS Academy Learner Lab ativo;
- AWS CLI com as credenciais temporárias da sessão;
- Docker Desktop com Buildx;
- `eksctl`, `kubectl`, Helm, OpenSSL, Git e Trivy no `PATH`;
- acesso de escrita ao repositório `https://github.com/Kaue-code30/gs-bara.git`.

As credenciais do Learner Lab expiram. Atualize o perfil AWS sempre que iniciar uma nova sessão e
nunca copie essas credenciais para este repositório.

Validação inicial:

```powershell
.\scripts\verify-prerequisites.ps1
```

## Criação completa do ambiente

### 1. Iniciar o Learner Lab e configurar a conta

Com as credenciais temporárias já configuradas no perfil AWS:

```powershell
.\scripts\configure-environment.ps1
```

O script descobre o Account ID e atualiza os ARNs da `LabRole` e os endereços do ECR. O Account ID
não é segredo; as chaves de acesso e o token de sessão são segredos.

### 2. Construir e publicar as imagens

```powershell
.\scripts\build-push-images.ps1
```

São publicadas quatro tags, todas para `linux/amd64`:

- `store-api:1.0`;
- `store-api:2.0`;
- `store-worker:1.0`;
- `store-front:1.0`.

Nenhum workload usa `latest`.

### 3. Criar o EKS e instalar a plataforma

```powershell
.\scripts\install-platform.ps1
```

Esse passo cria o cluster e instala Traefik, KEDA e Argo CD. Ao terminar, o script mostra o hostname
do Load Balancer. Se o cluster já existir, use:

```powershell
.\scripts\install-platform.ps1 -SkipClusterCreation
```

Confirme a distribuição dos nós:

```powershell
kubectl get nodes -L topology.kubernetes.io/zone
```

### 4. Configurar o hostname público

Substitua o valor abaixo pelo hostname exibido no passo anterior:

```powershell
$hostname = "SEU-LOAD-BALANCER.us-east-1.elb.amazonaws.com"
.\scripts\configure-environment.ps1 -Hostname $hostname
```

### 5. Criar os Secrets fora do Git

```powershell
.\scripts\create-secrets.ps1 -Hostname $hostname
```

O script:

- gera uma senha aleatória forte ou preserva a senha já existente;
- cria `store-db-credentials`, chave `password`, em `store-prod` e `store-data`;
- gera um certificado autoassinado com o hostname no SAN;
- cria `store-tls`, do tipo `kubernetes.io/tls`, em `store-prod`;
- apaga os arquivos temporários do certificado.

Não execute a rotação da senha enquanto o PVC existente estiver sendo reutilizado. O PostgreSQL lê
a senha de inicialização somente quando cria o banco.

### 6. Publicar a configuração da versão 1.0

O Argo CD lê o GitHub, portanto o Account ID e o hostname precisam estar publicados antes da
primeira sincronização:

```powershell
git add .
git commit -m "feat: configura plataforma EKS e deploy inicial 1.0"
git push origin main
```

Confirme que nenhum Secret foi adicionado ao commit:

```powershell
git grep -n -I -E "AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|BEGIN.*PRIVATE KEY|store-db-password"
```

O comando não deve retornar valores sensíveis.

### 7. Ativar o GitOps

```powershell
.\scripts\deploy-application.ps1
```

O script só prossegue se o repositório estiver limpo e o commit local já existir em `origin/main`.
A Application precisa terminar como `Synced` e `Healthy`.

Para abrir o Argo CD localmente:

```powershell
kubectl port-forward service/argocd-server -n argocd 8081:443
```

Application: [fiap-store no Argo CD](https://localhost:8081/applications/fiap-store)

### 8. Executar o rollout obrigatório 1.0 → 2.0

A primeira sincronização usa `store-api:1.0`. Depois que ela estiver saudável:

```powershell
.\scripts\promote-api-v2.ps1
git add k8s/kustomization.yaml
git commit -m "feat: promove store-api para 2.0"
git push origin main
kubectl rollout status deployment/store-api -n store-prod
kubectl get replicasets -n store-prod -l app=store-api
```

O Deployment usa `maxUnavailable: 0` e mantém histórico suficiente para o corretor encontrar pelo
menos dois ReplicaSets. O rollout deve ser refeito no cluster usado na apresentação.

### 9. Gerar os relatórios do Trivy

```powershell
.\scripts\scan-images.ps1
```

Revise `avaliacao/trivy/` e corrija ou justifique tecnicamente qualquer vulnerabilidade `CRITICAL`.

### 10. Validar a entrega

Espere ao menos uma execução agendada do `store-report` — o CronJob roda a cada minuto — e execute
no Git Bash:

```bash
./avaliacao/verifica-gs.sh "https://SEU-LOAD-BALANCER.us-east-1.elb.amazonaws.com"
```

O resultado esperado é `Pontuacao automatica: 80 / 80`.

Antes da entrega final:

```powershell
git tag -a gs-final -m "Global Solution final"
git push origin gs-final
```

## Destruição do ambiente

O ambiente custa créditos enquanto está ligado. A destruição segue a ordem exigida: Application,
namespaces/PVC, Load Balancer e cluster.

```powershell
.\scripts\destroy-environment.ps1 -ConfirmDestruction
```

Ao terminar, confira no console da AWS se não restaram volumes EBS ou Load Balancers. O script exige
que o contexto atual do `kubectl` pertença ao cluster `fiap-store` para reduzir o risco de apagar o
ambiente errado.

## Preparação para os desafios ao vivo

### 1. Self-healing

```bash
pod="$(kubectl get pods -n store-prod -l app=store-api \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
kubectl delete pod "$pod" -n store-prod
kubectl get pods -n store-prod -l app=store-api -w
```

### 2. Drenagem de nó

Primeiro identifique o nó do banco e escolha outro nó:

```bash
kubectl get pod store-db-0 -n store-data -o wide
kubectl get nodes
kubectl drain NOME_DO_NO --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n store-prod -o wide
kubectl uncordon NOME_DO_NO
```

### 3. Rollback por GitOps

Reverta o commit da promoção, nunca altere o Deployment manualmente:

```bash
git log --oneline -5
git revert HASH_DO_COMMIT_DA_VERSAO_2
git push origin main
kubectl rollout status deployment/store-api -n store-prod
```

### 4. Escala a zero

Use o botão de lote na interface para criar 50 pedidos e acompanhe:

```bash
kubectl get deployment store-worker -n store-prod -w
kubectl get scaledobject store-worker -n store-prod
```

### 5. Persistência

```bash
kubectl delete pod store-db-0 -n store-data
kubectl get pod store-db-0 -n store-data -w
kubectl get pvc -n store-data
```

### 6. Pod Security

O comando precisa ser recusado pelo admission controller:

```bash
kubectl run teste-privilegiado -n store-prod --restart=Never --image=busybox:1.36.1 \
  --overrides='{"spec":{"containers":[{"name":"teste-privilegiado","image":"busybox:1.36.1","securityContext":{"privileged":true}}]}}'
```

### 7. RBAC dos desenvolvedores

```bash
kubectl auth can-i list pods -n store-prod --as=dev.aluno --as-group=fiap:devs
kubectl auth can-i get pods/log -n store-prod --as=dev.aluno --as-group=fiap:devs
kubectl auth can-i delete pods -n store-prod --as=dev.aluno --as-group=fiap:devs
kubectl auth can-i get secrets -n store-prod --as=dev.aluno --as-group=fiap:devs
kubectl auth can-i create pods/exec -n store-prod --as=dev.aluno --as-group=fiap:devs
```

Resultados esperados: `yes`, `yes`, `no`, `no`, `no`.

### 8. Correção de drift

```bash
kubectl delete service store-front -n store-prod
kubectl get service store-front -n store-prod -w
```

O Argo CD recria o Service automaticamente.

### 9. Isolamento de rede

```bash
kubectl exec -n store-prod deploy/store-front -- \
  wget -T 3 -q -O /dev/null http://store-db.store-data.svc.cluster.local:5432/

kubectl exec -n store-prod deploy/store-api -- python -c \
  "import socket; socket.create_connection(('store-db.store-data.svc.cluster.local',5432),3)"
```

O front deve falhar e a API deve conectar.

### 10. Relatório sob demanda

```bash
kubectl create job --from=cronjob/store-report "store-report-manual-$(date +%s)" -n store-prod
kubectl get jobs -n store-prod -w
```

O relatório aparece na página após a conclusão do Job.

## Gerando carga para o HPA

O Pod de carga roda em `default`, pois `store-prod` usa Pod Security `restricted`:

```bash
kubectl run carga -n default --rm -it --restart=Never --image=busybox:1.36.1 -- \
  sh -c 'while true; do wget -q -O- "http://store-api.store-prod/api/carga?ms=300" >/dev/null; done'
```

## Execução local da aplicação

```bash
cd local
docker compose up --build
```

A loja fica em `http://localhost:8080`. Itens dependentes do Kubernetes aparecem como falha no
painel local, o que é esperado.

## Uso de inteligência artificial

O grupo utilizou OpenAI Codex para analisar o enunciado, estruturar os manifestos Kubernetes,
automatizar tarefas operacionais e revisar a documentação. Os integrantes revisaram os artefatos e
são responsáveis por compreender e explicar as decisões técnicas durante a demonstração.
