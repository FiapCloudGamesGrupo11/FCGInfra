# FCGInfra - Infraestrutura da Plataforma Cloud Games

> Guia completo de arquitetura, conceitos e testes: [API Gateway e Serverless local](docs/GUIA-GATEWAY-SERVERLESS.md).

## Fase 4 - estado da branch `feature/fase-4-aws`

### O que foi feito

- criação da branch dedicada à infraestrutura AWS, sem alteração da `main`;
- remoção do arquivo Kubernetes que continha credenciais versionadas;
- inclusão de `k8s/common/secrets.example.yaml` somente como modelo;
- inclusão de `k8s/common/secrets.yaml` no `.gitignore`;
- validação prévia no `k8s/apply-all.ps1` para impedir deploy local sem o arquivo de segredos;
- leitura das credenciais do RabbitMQ pelo Kubernetes Secret.

### Configuração local dos segredos

Crie o arquivo ignorado pelo Git:

```powershell
Copy-Item .\k8s\common\secrets.example.yaml .\k8s\common\secrets.yaml
```

Substitua todos os marcadores `REPLACE_AT_DEPLOY_TIME` no novo `secrets.yaml`. O modelo não deve ser aplicado diretamente ao cluster. Os valores reais nunca devem ser commitados.

O secret contempla conexões SQL e MongoDB, credenciais do RabbitMQ e configurações JWT consumidas pelos microsserviços. Em produção, sua criação será responsabilidade do pipeline ou do mecanismo de segredos definido pelo dono da conta AWS, preferencialmente integrado ao AWS Secrets Manager.

### Como validar

Execute na raiz deste repositório:

```powershell
git check-ignore k8s/common/secrets.yaml
kubectl apply --dry-run=client -f k8s/common/secrets.example.yaml
kubectl apply --dry-run=client -f k8s/common/configmap.yaml
kubectl apply --dry-run=client -f k8s/rabbitmq/rabbitmq-deployment.yaml
```

O primeiro comando deve retornar o caminho do arquivo ignorado, e os manifests devem passar pela validação sem serem aplicados.

Para o ambiente Docker completo, copie `docker/.env.example` para `docker/.env` e substitua os marcadores antes de executar o Compose.

### Como manter

- não versione valores reais em YAML, Docker Compose, scripts ou documentação;
- mantenha LocalStack e endpoints locais restritos ao ambiente de desenvolvimento;
- no EKS, use IAM Roles for Service Accounts ou EKS Pod Identity em vez de chaves estáticas;
- use tags imutáveis do ECR, probes de saúde, limites de recursos e rolling update nos deployments;
- a criação do overlay AWS/EKS, Ingress, ECR e serviços gerenciados pertence às próximas etapas desta branch.

### OpenSearch local e AWS

O Docker Compose e os manifests Kubernetes comuns incluem um nó OpenSearch exclusivamente para desenvolvimento local. O catálogo usa `http://opensearch:9200`, sem SigV4.

No overlay AWS/EKS, não será criado um OpenSearch dentro do cluster. O `OpenSearch__Endpoint` deverá apontar para o Amazon OpenSearch Service, `OpenSearch__UseAwsSigV4` será `true` e o pod receberá acesso por IAM Role. Os dados oficiais continuam no MongoDB e podem ser reindexados pela rota administrativa do catálogo.

O Kong encaminha `/search` para o catálogo, mas a validação JWT permanece nas próprias APIs. Isso evita duplicar o segredo de assinatura na configuração declarativa do gateway.

## Descrição

O **FCGInfra** é o repositório centralizado de infraestrutura da plataforma **FIAP Cloud Games (FCG)**. Ele contém as configurações e definições necessárias para executar toda a arquitetura de microsserviços em diferentes ambientes:

- **Desenvolvimento**: Docker Compose para desenvolvimento local
- **Produção/Staging**: Kubernetes manifests para deploy em clusters

Este repositório não contém código de aplicação, mas sim toda a orquestração, configuração e infraestrutura que conecta os microsserviços (FCGUser, FCGCatalog, FCGPayment, FCGNotification).

No ambiente Docker Compose, o Kong API Gateway é a única entrada HTTP para UserAPI e CatalogAPI. As APIs permanecem acessíveis apenas pela rede interna do Compose.

> Para configurar, executar e testar o Gateway do zero, consulte o [guia completo do Kong](docker/kong/README.md).

---

## Objetivo

Centralizar e padronizar:
- Configuração de infraestrutura
- Definições de deployment
- Variáveis de ambiente
- Orquestração de serviços
- Networking e comunicação entre microsserviços

---

## Arquitetura

### Componentes Principais

```
┌─────────────────────────────────────────────────────────────────┐
│                    FCGInfra Platform                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  FCGUser API │  │FCGCatalog API│  │FCGPayment API│          │
│  │  (Port 8070) │  │ (Port 8080)  │  │(8090, 8091)  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                  │
│         └─────────────────┼──────────────────┘                  │
│                           │                                     │
│  ┌────────────────────────┴────────────────────────┐            │
│  │ FCGNotification Lambda (LocalStack: 4566)       │            │
│  └────────────────────────┬────────────────────────┘            │
│                           │                                     │
│  ┌────────────────────────┴────────────────────────┐            │
│  │ SQS (notificações) + RabbitMQ (demais fluxos)   │            │
│  └────────────────────────┬────────────────────────┘            │
│                           │                                     │
│         ┌─────────────────┴─────────────────┐                  │
│         │   Database (SQL Server 2022)      │                  │
│         │   (Port 1433, Shared Database)    │                  │
│         └─────────────────────────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Estrutura do Repositório

```
FCGInfra/
├── docker/
│   ├── docker-compose.yml          # Orquestração para desenvolvimento
│   └── kong/
│       ├── kong.yml                # Serviços, rotas e políticas do Gateway
│       └── README.md               # Guia de uso e validação do Gateway
├── k8s/
│   ├── apply-all.ps1               # Script para aplicar todos os manifests
│   ├── common/
│   │   ├── configmap.yaml          # Variáveis de ambiente compartilhadas
│   │   └── secrets.yaml            # Credenciais e senhas
│   ├── sqlserver/
│   │   ├── sqlserver-deployment.yaml
│   │   └── sqlserver-service.yaml
│   ├── rabbitmq/
│   │   ├── rabbitmq-deployment.yaml
│   │   └── rabbitmq-service.yaml
│   ├── mongo/
│   │   ├── mongo-deployment.yaml
│   │   └── mongo-service.yaml
│   ├── userapi/
│   │   ├── userapi-deployment.yaml
│   │   └── userapi-service.yaml
│   ├── catalogapi/
│   │   ├── catalogapi-deployment.yaml
│   │   └── catalogapi-service.yaml
│   ├── payment/
│   │   ├── paymentapi-deployment.yaml
│   │   └── paymentapi-service.yaml
│   └── notificationapi/
│       ├── notificationapi-deployment.yaml
│       └── notificationapi-service.yaml
└── README.md                       # Este arquivo
```

---

## Executar com Docker Compose

### Pré-requisitos

- Docker Desktop instalado e em execução
- Docker Compose (incluído no Docker Desktop)
- ~8GB de memória disponível
- Acesso às portas: 1433, 4566, 5672, 8000, 8001 e 15672

### Passos para Executar

1. **Clone o repositório FiapTC2**:

```bash
git clone <repository-url>
cd FiapTC2
```

2. **Navegue até a pasta de infraestrutura**:

```bash
cd FCGInfra/docker
```

3. **Inicie todos os serviços**:

```bash
docker-compose up -d
```

Com Docker Compose v2, prefira:

```powershell
docker compose config --quiet
docker compose up -d --build
```

Na primeira execução, o download das imagens e o build dos microsserviços podem demorar. Aguarde o retorno do prompt antes de consultar os containers.

4. **Verifique se todos os containers estão em execução**:

```bash
docker-compose ps
```

Saída esperada:

```
NAME              STATUS              PORTS
sqlserver         Up (healthy)        1433/tcp
rabbitmq          Up (healthy)        5672/tcp, 15672/tcp
catalogapi        Up (healthy)        8080/tcp
userapi           Up (healthy)        8070/tcp
paymentsapi       Up (healthy)        8090/tcp, 8091/tcp
localstack        Up (healthy)        127.0.0.1:4566->4566/tcp
kong-gateway      Up (healthy)        8000/tcp, 127.0.0.1:8001->8001/tcp
```

5. **Pare os serviços quando terminar**:

```bash
docker-compose down
```

---

##  Acessar os Serviços Localmente

### API Gateway

| Componente | URL | Finalidade |
|------------|-----|------------|
| Kong Proxy | http://localhost:8000 | Entrada para UserAPI e CatalogAPI |
| Kong Admin API | http://localhost:8001 | Administração local e diagnóstico |
| Swagger UserAPI | http://user.localhost:8000/swagger | Testes da API de usuários pelo Gateway |
| Swagger CatalogAPI | http://catalog.localhost:8000/swagger | Testes do catálogo pelo Gateway |

As portas HTTP dos microsserviços não são publicadas no host. Consulte `docker/kong/README.md` para as rotas públicas, rotas protegidas e exemplos de chamadas JWT.

### LocalStack, SQS e Lambda

O LocalStack executa localmente os serviços SQS, Lambda, IAM e CloudWatch Logs. O build do Compose compila o projeto `FCGNotification`, gera seu pacote ZIP e o inclui na imagem `fcg-localstack`.

No fluxo completo de pagamento, o RabbitMQ permanece entre catálogo e pagamento. Depois de processar o pedido, o FCGPayment publica o resultado no RabbitMQ para o catálogo e também na fila SQS `notification-payment-processed`. Essa fila aciona a Lambda `fcg-notification` no LocalStack.

Na inicialização são criados automaticamente:

| Recurso | Nome | Finalidade |
|---|---|---|
| Lambda | `fcg-notification` | Processar eventos de notificação |
| Fila SQS | `user-created` | Notificação de novo usuário |
| Fila SQS | `notification-payment-processed` | Notificação do resultado do pagamento |
| DLQ | `user-created-dlq` | Guardar eventos de usuário após três falhas |
| DLQ | `notification-payment-processed-dlq` | Guardar eventos de pagamento após três falhas |

Credenciais AWS reais não são utilizadas. O Compose fornece `test` como access key e secret key. Se a edição instalada exigir autenticação, defina seu token apenas no terminal, sem colocá-lo no repositório:

```powershell
$env:LOCALSTACK_AUTH_TOKEN = "seu-token-local"
docker compose up -d --build
```

Para conferir os recursos provisionados:

```powershell
.\localstack\status.ps1
```

O relatório apresenta separadamente mensagens disponíveis e mensagens que estão sendo processadas em cada fila principal e DLQ.

Para enviar um usuário criado:

```powershell
.\localstack\test-user-created.ps1
.\localstack\test-user-created.ps1 -Name "Maria" -Email "maria@fcg.local"
```

Para enviar pagamentos:

```powershell
.\localstack\test-payment-processed.ps1 -Status Approved
.\localstack\test-payment-processed.ps1 -Status Declined -Reason "Saldo insuficiente"
```

Os scripts podem ser executados de qualquer diretório. Para acompanhar a criação dos recursos:

```powershell
docker compose logs localstack --tail 200
docker compose logs localstack --follow
```

Use `Ctrl+C` para encerrar apenas o acompanhamento; os containers continuam ativos. Os logs das execuções da Lambda ficam no CloudWatch Logs simulado e podem ser consultados com:

```powershell
.\localstack\logs.ps1              # últimos 15 minutos
.\localstack\logs.ps1 -Minutes 60  # última hora
```

Uma mensagem como `[EMAIL] Bem-vindo enviado` ou `[EMAIL] Compra confirmada` confirma que o evento passou pelo SQS e executou a Lambda.

Para comprovar o tratamento de falhas e o redrive após três tentativas, envie propositalmente uma mensagem inválida:

```powershell
.\localstack\test-invalid-dlq.ps1
.\localstack\test-invalid-dlq.ps1 -Queue notification-payment-processed
```

O script não apaga nem lê o conteúdo da DLQ. Ele compara o contador inicial, envia um JSON inválido, aguarda as tentativas da Lambda e confirma que a DLQ recebeu uma nova mensagem. O processo pode levar cerca de dois minutos por causa do tempo de invisibilidade entre as tentativas.

Se estiver utilizando o CMD a partir da raiz do repositório, invoque os scripts por meio do PowerShell:

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\status.ps1"
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\logs.ps1" -Minutes 30
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-invalid-dlq.ps1"
```

O painel gráfico do LocalStack exige que o container esteja conectado a uma conta/licença compatível. No ambiente local sem token, os scripts acima são a interface de diagnóstico oficial do projeto; a ausência de recursos no painel não significa que SQS ou Lambda estejam indisponíveis.

Se o container ficar `unhealthy`, consulte primeiro:

```powershell
docker compose logs localstack --tail 200
```

Erros de licença devem ser resolvidos configurando `LOCALSTACK_AUTH_TOKEN` localmente. O arquivo `.env` é ignorado pelo Git e nunca deve conter credenciais que serão versionadas.

### Validação rápida do Gateway

```powershell
# Deve falhar: UserAPI não está publicada diretamente
curl.exe -i http://localhost:8070/api/User/GetAll

# Deve retornar 401 pelo Kong
curl.exe -i http://localhost:8000/api/User/GetAll
```

Para o roteiro completo de Swagger, criação de Admin, testes `401`/`403`/`200` e diagnóstico, consulte o [guia do Kong](docker/kong/README.md).

### Ferramentas de Infraestrutura

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| RabbitMQ Management UI | http://localhost:15672 | guest / guest |
| SQL Server | localhost:1433 | valores definidos em `docker/.env` |

---

## Banco de Dados

### Conectar ao SQL Server

#### Com SQL Server Management Studio (SSMS):

1. Server: `localhost,1433`
2. Authentication: SQL Server Authentication
3. Login: `sa`
4. Password: use o valor local de `FCG_SQL_PASSWORD`
5. Trust server certificate: Yes

#### Com sqlcmd (CLI):

```bash
sqlcmd -S localhost,1433 -U sa -P "SENHA_LOCAL"
```

### Banco de Dados

- **Nome**: FiapCloudGames
- **Tabelas**: Criadas automaticamente pelos microsserviços via Entity Framework Core

---

## RabbitMQ

### Acessar Management UI

1. Abra http://localhost:15672
2. Credenciais:
   - Usuário: `guest`
   - Senha: `guest`

### Filas Principais

| Fila | Produzido por | Consumido por | Descrição |
|------|---------------|---------------|-----------|
| `order-placed` | FCGCatalog | FCGPayment | Pedidos de compra de jogos |
| `user-created` | FCGUser | FCGNotification | Novos usuários registrados |
| `payment-processed` | FCGPayment | FCGCatalog | Pagamentos processados |
| `notification-payment-processed` | FCGPayment | FCGNotification | Notificações de pagamento |

### Exchanges

| Exchange | Tipo | Uso |
|----------|------|-----|
| `order.exchange` | Direct | Roteamento de pedidos |
| `payment.exchange` | Fanout | Broadcast de eventos de pagamento |

---

## Deploy com Kubernetes

O perfil local usa APIs, bancos, RabbitMQ, Redis e Kong no Kubernetes do Docker
Desktop. SQS e Lambda continuam no LocalStack gerenciado pelo Compose.
Consulte [o roteiro completo](k8s/README.md).

### Pré-requisitos

- Kubectl instalado e configurado
- Kubernetes habilitado no Docker Desktop, contexto `docker-desktop`
- Acesso ao cluster
- Variável `NEW_RELIC_LICENSE_KEY` definida na sessão

### Passos para Deploy

1. **Navegue até a pasta k8s**:

```bash
cd FCGInfra/k8s
```

2. **Aplique a configuração comum (ConfigMap e Secrets)**:

```bash
kubectl apply -f common/configmap.yaml
kubectl apply -f common/secrets.yaml
```

3. **Aplique todos os manifests de uma vez**:

```powershell
# No Windows PowerShell
.\apply-all.ps1
```

O script também compila as imagens, prepara o LocalStack, aguarda a Lambda e seus
gatilhos e remove a antiga Notification contínua de uma instalação existente.
Para outros clusters, adapte imagens, armazenamento e endpoint SQS antes do deploy.

4. **Verifique o status dos pods**:

```bash
kubectl get pods
```

5. **Verifique os services**:

```bash
kubectl get svc
```

6. **Ver logs de um pod específico**:

```bash
kubectl logs <pod-name>
```

### Acessar Serviços em Kubernetes

No Docker Desktop, o Gateway atende em `http://user.localhost:30000/swagger`
e `http://catalog.localhost:30000/swagger`. Para diagnóstico, use:

```bash
# Obter informações de acesso
kubectl get svc

# Port-forward para RabbitMQ Management
kubectl port-forward svc/rabbitmq 15672:15672

# Port-forward para SQL Server
kubectl port-forward svc/db 1433:1433

# Port-forward para User API
kubectl port-forward svc/userapi 8070:8070
```

---

## Variáveis de Ambiente

### ConfigMap (Variáveis Públicas)

Arquivo: `k8s/common/configmap.yaml`

```yaml
ASPNETCORE_ENVIRONMENT: "Development"

# RabbitMQ
RabbitMQ__Host: "rabbitmq"
RabbitMQ__Port: "5672"
RabbitMQ__Username: "guest"
RabbitMQ__Password: "guest"

# Filas
RabbitMQ__OrderPlacedQueue: "order-placed"
RabbitMQ__PaymentProcessedQueue: "catalog-payment-processed"
RabbitMQ__NotificationPaymentProcessedQueue: "notification-payment-processed"
RabbitMQ__UserCreatedQueue: "user-created"

# APIs
CatalogAPI__BaseUrl: "http://catalog-api:8080"

# Exchanges
RabbitMQ__OrderExchange: "order.exchange"
RabbitMQ__PaymentExchange: "payment.exchange"
```

### Secrets (Credenciais Sensíveis)

Arquivo: `k8s/common/secrets.yaml`

```yaml
ConnectionStrings__ConnectionString: "Server=db,1433;Initial Catalog=FiapCloudGames;User Id=sa;[PASSWORD];TrustServerCertificate=True;"
SA_PASSWORD: "${FCG_SQL_PASSWORD}"
RabbitMQ__Host: "rabbitmq"
RabbitMQ__Port: "5672"
RabbitMQ__Username: "guest"
RabbitMQ__Password: "guest"
```

### Docker Compose

As variáveis estão definidas diretamente no `docker-compose.yml` com valores de desenvolvimento.

---

## Fluxo de Comunicação

### 1. Registro de Novo Usuário

```
User Service → SQS (user-created) → FCGNotification Lambda
                ↓
         Banco de Dados
```

### 2. Compra de Jogo

```
Catalog Service (Order) → RabbitMQ (order-placed queue) → Payment Service
                              ↓
                         Banco de Dados
```

### 3. Processamento de Pagamento

```
Payment Service → RabbitMQ (payment.exchange) → Catalog Service
       └───────→ SQS (notification-payment-processed) → FCGNotification Lambda
```

---

## Observabilidade com New Relic

Os logs da Lambda local sao enviados pelo servico `notification-log-forwarder`
do Compose. Veja [configuracao, consultas e limites](docker/observability/README.md).

O New Relic foi escolhido como plataforma de APM para centralizar métricas, logs e traces da aplicação.

O agente .NET foi adicionado aos seguintes microsserviços:

- `FCG-UsersAPI`
- `FCG-CatalogAPI`
- `FCG-PaymentsAPI`
- `FCG-NotificationLambda`

Os deployments do Kubernetes habilitam o trace distribuído e o encaminhamento dos logs. A licença é fornecida pelo Secret `newrelic-secret` e não deve ser gravada nos arquivos do repositório.

### Configurar a licença

Antes do deploy, defina a licença na sessão atual do PowerShell:

```powershell
$env:NEW_RELIC_LICENSE_KEY = "SUA_LICENCA"
```

Em seguida, execute o script dentro da pasta `k8s`:

```powershell
.\apply-all.ps1
```

O script cria ou atualiza o Secret `newrelic-secret` no Kubernetes sem salvar a licença no repositório.

### Dados monitorados

O dashboard deve apresentar:

- latência das requisições;
- quantidade de requisições e throughput;
- respostas agrupadas por status HTTP;
- taxa de erros;
- logs dos microsserviços.

O trace distribuído será utilizado para acompanhar o fluxo de compra entre o CatalogAPI e o PaymentsAPI por meio do RabbitMQ.

### Consultar no New Relic

Após o deploy e a geração de tráfego, os serviços poderão ser encontrados em **APM & Services** com os seguintes nomes:

- `FCG-UsersAPI`
- `FCG-CatalogAPI`
- `FCG-PaymentsAPI`
- - `FCG-NotificationLambda`

A função Serverless `FCG-NotificationLambda` também utiliza o agente .NET do New Relic. A instrumentação foi validada localmente no LocalStack com eventos das filas `user-created` e `notification-payment-processed`, incluindo a geração do payload `NR_LAMBDA_MONITORING`.

No LocalStack, esse payload permanece disponível nos logs da função. Para enviar a telemetria ao painel do New Relic em um ambiente AWS, também será necessária a integração pelo New Relic Lambda Extension ou pelo CloudWatch.

---

## Monitoramento

### Docker Compose

```bash
# Ver logs de todos os containers
docker-compose logs -f

# Ver logs de um serviço específico
docker-compose logs -f catalogapi

# Ver estatísticas de recursos
docker stats
```

### Kubernetes

```bash
# Ver status dos pods
kubectl get pods

# Ver logs de um pod
kubectl logs <pod-name>

# Ver logs em tempo real
kubectl logs -f <pod-name>

# Descrever um pod (útil para troubleshooting)
kubectl describe pod <pod-name>

# Ver eventos do cluster
kubectl get events
```

---

## Documentação Relacionada

- [README FCGUser](../FCGUser/README.md)
- [README FCGCatalog](../FCGCatalog/README.md)
- [README FCGPayment](../FCGPayment/README.md)
- [README FCGNotification](../FCGNotification/README.md)

---

## Autores

Integrantes:
  --Anderson Alves Koshimizu - RM371858 (Anderson Koshimizu)
  --André Felipe da Costa - RM373980 (Fe-costa)
  --Esterffeson José Duarte de Abreu - RM372754 (EsterffesonDuarte)
  --Esther Novais Pinheiro Silva - RM373639  (Esther Novais)
  --Jacqueline Nascimento Albuquerque - RM366275  (Jacqueline)

---

**Última atualização**: 2026-09-12
**Versão**: 1.1.0
