# FCGInfra - Infraestrutura da Plataforma Cloud Games

## Descrição

O **FCGInfra** é o repositório centralizado de infraestrutura da plataforma **FIAP Cloud Games (FCG)**. Ele contém as configurações e definições necessárias para executar toda a arquitetura de microsserviços em diferentes ambientes:

- **Desenvolvimento**: Docker Compose para desenvolvimento local
- **Produção/Staging**: Kubernetes manifests para deploy em clusters

Este repositório não contém código de aplicação, mas sim toda a orquestração, configuração e infraestrutura que conecta os microsserviços (FCGUser, FCGCatalog, FCGPayment, FCGNotification).

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
│  │     FCGNotification API (Port 5001)             │            │
│  └────────────────────────┬────────────────────────┘            │
│                           │                                     │
│         ┌─────────────────┴─────────────────┐                  │
│         │       Message Bus (RabbitMQ)      │                  │
│         │  (AMQP: 5672, Management: 15672) │                  │
│         └─────────────────┬─────────────────┘                  │
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
│   └── docker-compose.yml          # Orquestração para desenvolvimento
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
- Acesso às portas: 1433, 5672, 15672, 8070, 8080, 8090, 8091, 5001

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
notifications-api Up (healthy)        5001/tcp
```

5. **Pare os serviços quando terminar**:

```bash
docker-compose down
```

---

##  Acessar os Serviços Localmente

### APIs dos Microsserviços

| Microsserviço | URL | Swagger/Docs |
|---------------|-----|--------------|
| FCGCatalog | http://localhost:8080 | http://localhost:8080/swagger |
| FCGUser | http://localhost:8070 | http://localhost:8070/swagger |
| FCGPayment | http://localhost:8090 | http://localhost:8090/swagger |
| FCGNotification | http://localhost:5001 | http://localhost:5001/swagger |

### Ferramentas de Infraestrutura

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| RabbitMQ Management UI | http://localhost:15672 | guest / guest |
| SQL Server | localhost:1433 | sa / Your_strong!Passw0rd |

---

## Banco de Dados

### Conectar ao SQL Server

#### Com SQL Server Management Studio (SSMS):

1. Server: `localhost,1433`
2. Authentication: SQL Server Authentication
3. Login: `sa`
4. Password: `Your_strong!Passw0rd`
5. Trust server certificate: Yes

#### Com sqlcmd (CLI):

```bash
sqlcmd -S localhost,1433 -U sa -P "Your_strong!Passw0rd"
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

### Pré-requisitos

- Kubectl instalado e configurado
- Cluster Kubernetes em execução (Docker Desktop, Minikube, AKS, EKS, GKE, etc.)
- Acesso ao cluster

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

Ou manualmente:

```bash
# SQL Server
kubectl apply -f sqlserver/sqlserver-deployment.yaml
kubectl apply -f sqlserver/sqlserver-service.yaml

# RabbitMQ
kubectl apply -f rabbitmq/rabbitmq-deployment.yaml
kubectl apply -f rabbitmq/rabbitmq-service.yaml

# Microsserviços
kubectl apply -f userapi/userapi-deployment.yaml
kubectl apply -f userapi/userapi-service.yaml

kubectl apply -f catalogapi/catalogapi-deployment.yaml
kubectl apply -f catalogapi/catalogapi-service.yaml

kubectl apply -f payment/paymentapi-deployment.yaml
kubectl apply -f payment/paymentapi-service.yaml

kubectl apply -f notificationapi/notificationapi-deployment.yaml
kubectl apply -f notificationapi/notificationapi-service.yaml
```

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

Para acessar os serviços em um cluster Kubernetes local (Minikube/Docker Desktop), use:

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
SA_PASSWORD: "Your_strong!Passw0rd"
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
User Service → RabbitMQ (user-created queue) → Notification Service
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
                       ↓
                 Notification Service
```

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

**Última atualização**: 2026-07-12  
**Versão**: 1.0.0  
