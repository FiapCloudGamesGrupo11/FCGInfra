# Guia do API Gateway e Serverless local do FCG

Este guia explica a arquitetura implementada, o papel de cada componente e como testar os fluxos. Salvo indicação contrária, execute os comandos na raiz do repositório `FCGInfra`.

## 1. Arquitetura

```text
Cliente / Swagger
       |
       v
Kong API Gateway :8000
       |----------------------|
       v                      v
UserAPI :8070          CatalogAPI :80
       |                      |
       | SQS                  | RabbitMQ: order-placed
       v                      v
LocalStack              PaymentAPI
       ^                      |-- RabbitMQ: payment.exchange --> CatalogAPI
       |                      `-- SQS: notification-payment-processed
       |
       +---- SQS ----> Lambda fcg-notification ----> e-mail simulado em log
```

Todos os componentes se comunicam pela rede Docker `fcg-network`.

## 2. O que é um API Gateway

Um API Gateway é a porta de entrada HTTP de um conjunto de serviços. O cliente chama um endereço único e o gateway escolhe o microsserviço de destino.

Neste projeto, o gateway é o **Kong**, exposto em `http://localhost:8000`. UserAPI e CatalogAPI não publicam portas HTTP diretamente no computador.

### O que o Kong está fazendo

- encaminha `/api/User` para `userapi:8070`;
- encaminha `/api/Game`, `/api/OnSale` e `/api/UsersGames` para `catalogapi:80`;
- libera `POST /api/User/CreateUser` e `POST /api/User/Login` sem token;
- exige JWT nas demais rotas configuradas;
- verifica assinatura HS256 e expiração do token;
- oferece os Swagger pelo mesmo ponto de entrada;
- esconde nomes e portas internos dos containers.

O Kong verifica a validade inicial do token. As APIs continuam responsáveis pelas permissões de negócio e pelas roles.

| Código | Significado |
|---|---|
| `200`, `201`, `204` | Sucesso |
| `400` | Dados inválidos |
| `401` | Token ausente, inválido ou expirado |
| `403` | Token válido, mas sem permissão |
| `404` na raiz `/` | Esperado: não existe rota para a raiz |
| `502` ou `503` | Kong não alcançou o serviço de destino |

### Kong DB-less

O Kong usa `KONG_DATABASE=off`. O arquivo `docker/kong/kong.yml` é a fonte das rotas, consumidores e plugins. A Admin API `http://localhost:8001` serve apenas para diagnóstico local.

## 3. O que é serverless

Serverless não significa ausência de servidores. Significa executar funções sob demanda, acionadas por eventos, deixando a plataforma administrar sua execução.

A NotificationsAPI deixou de ser um serviço HTTP sempre ativo e passou a ser a função `fcg-notification`. Quando uma mensagem chega ao SQS, o event source mapping chama a Lambda.

| Componente | Responsabilidade |
|---|---|
| LocalStack | Simular serviços AWS localmente e sem cobrança |
| SQS | Manter eventos até o processamento |
| Lambda | Executar a notificação sob demanda |
| Event source mapping | Conectar a fila à Lambda |
| DLQ | Guardar mensagens que falharam três vezes |
| CloudWatch Logs simulado | Armazenar logs da Lambda |

São usadas credenciais fictícias `test/test`; Access Key e Secret Key reais da AWS não são necessárias.

### Recursos locais

- Lambda `fcg-notification`;
- fila `user-created` e DLQ `user-created-dlq`;
- fila `notification-payment-processed` e DLQ `notification-payment-processed-dlq`.

Cada fila principal usa `maxReceiveCount=3`. Depois de três falhas, a mensagem vai para a DLQ e deixa de bloquear a fila principal.

## 4. Papel dos componentes

| Componente | Papel |
|---|---|
| UserAPI | Cadastro, login e publicação de `UserCreatedEvent` |
| CatalogAPI | Jogos, promoções, pedidos e biblioteca |
| PaymentAPI | Processamento do pedido e publicação do resultado |
| RabbitMQ | Eventos entre CatalogAPI e PaymentAPI |
| SQS/Lambda | Acionamento serverless das notificações |
| SQL Server | Persistência das APIs atuais |
| MongoDB | Persistência das funcionalidades que o utilizem |
| Docker Compose | Containers, rede e configurações locais |

RabbitMQ e SQS têm papéis diferentes: RabbitMQ permanece no domínio de compra; SQS aciona as notificações serverless.

## 5. Fluxos

### Usuário criado

```text
Cliente → Kong → UserAPI → SQS user-created
→ Lambda fcg-notification → log de boas-vindas
```

### Pagamento processado

```text
CatalogAPI → RabbitMQ order-placed → PaymentAPI
PaymentAPI → RabbitMQ payment.exchange → CatalogAPI
PaymentAPI → SQS notification-payment-processed
→ Lambda fcg-notification → confirmação ou rejeição em log
```

O PaymentAPI publica em dois destinos: o catálogo atualiza o pedido pelo RabbitMQ e a Lambda notifica pelo SQS.

> O fluxo funcional de compra está sob responsabilidade de outro desenvolvedor. Campos, regras e endpoints podem mudar; alinhe este roteiro ao contrato definitivo antes da entrega.

## 6. Iniciar o ambiente

Pré-requisitos: Docker Desktop iniciado, repositórios como diretórios irmãos e portas `8000`, `8001`, `1433`, `5672`, `15672`, `27018` e `4566` disponíveis.

```cmd
cd /d C:\Users\andre\source\repos\FiapCloudGamesGrupo11\FCGInfra
docker compose -f ".\docker\docker-compose.yml" config --quiet
docker compose -f ".\docker\docker-compose.yml" up -d --build
docker compose -f ".\docker\docker-compose.yml" ps
```

Espere SQL Server, MongoDB, RabbitMQ, LocalStack e Kong aparecerem como `healthy`.

## 7. Testar o Gateway e o fluxo real de usuário

1. Abra `http://user.localhost:8000/swagger`.
2. Execute `POST /api/User/CreateUser`:

```json
{
  "name": "Usuario",
  "lastName": "Teste",
  "email": "usuario.teste@fcg.local",
  "password": "SuaSenha123!"
}
```

3. Execute `POST /api/User/Login` com o mesmo e-mail e senha.
4. Copie o JWT.
5. Clique em **Authorize** e informe `Bearer SEU_TOKEN`.
6. Execute uma rota protegida, como `GET /api/User/GetAll`.

O cadastro já testa um fluxo real até a Lambda. Confirme:

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\logs.ps1" -Minutes 15
```

Procure por `[EMAIL] Bem-vindo enviado` e `UserCreatedEvent processado`.

## 8. Testar o fluxo real de compra

1. Abra `http://catalog.localhost:8000/swagger`.
2. Autorize novamente com o JWT; cada Swagger mantém sua própria sessão.
3. Execute `GET /api/Game/GetAllAsync` e copie um `gameId`.
4. No contrato atual, execute `POST /api/UsersGames/Post`:

```json
{
  "userId": "GUID_DO_USUARIO",
  "gameId": "GUID_DO_JOGO",
  "valuePay": 99.90
}
```

5. Acompanhe cada parte:

```cmd
docker compose -f ".\docker\docker-compose.yml" logs paymentsapi --tail 150
docker compose -f ".\docker\docker-compose.yml" logs catalogapi --tail 150
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\logs.ps1" -Minutes 15
```

O mesmo pedido deve aparecer no catálogo, no pagamento e na Lambda. A confirmação final do estado do pedido e da biblioteca depende da versão entregue pelo responsável pelo fluxo de compra.

## 9. Testes isolados do serverless

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-user-created.ps1"
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-payment-processed.ps1" -Status Approved
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-payment-processed.ps1" -Status Declined -Reason "Saldo insuficiente"
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\logs.ps1" -Minutes 15
```

Esses comandos testam SQS → Lambda sem depender do Swagger.

## 10. Testar falha e DLQ

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-invalid-dlq.ps1"
```

O script confirma Lambda `Active` e gatilhos `Enabled`, envia JSON inválido, espera três falhas e verifica o aumento da DLQ. Ele não apaga mensagens e pode levar cerca de dois minutos.

Para a fila de pagamento:

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\test-invalid-dlq.ps1" -Queue notification-payment-processed
```

## 11. Observar RabbitMQ e LocalStack

### RabbitMQ

Abra `http://localhost:15672` e use `guest/guest`.

- **Queues and Streams → order-placed** mostra pedidos;
- **Exchanges → payment.exchange** mostra resultados publicados;
- gráficos `Publish`, `Deliver` e `Ack` comprovam o trânsito.

O consumo é rápido, portanto a fila normalmente volta para zero.

### LocalStack sem painel licenciado

`http://localhost:4566` é o endpoint das APIs locais. Se o painel mostrar `No resources` e aviso de licença, consulte:

```cmd
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\status.ps1"
powershell -ExecutionPolicy Bypass -File ".\docker\localstack\logs.ps1" -Minutes 30
```

O relatório mostra filas, contadores, Lambda e gatilhos. Fila principal em zero normalmente significa que a mensagem já foi consumida.

## 12. Diagnóstico

```cmd
docker compose -f ".\docker\docker-compose.yml" ps
docker compose -f ".\docker\docker-compose.yml" logs kong --tail 100
docker compose -f ".\docker\docker-compose.yml" logs userapi --tail 100
docker compose -f ".\docker\docker-compose.yml" logs catalogapi --tail 100
docker compose -f ".\docker\docker-compose.yml" logs paymentsapi --tail 100
docker compose -f ".\docker\docker-compose.yml" logs localstack --tail 150
```

| Sintoma | Verificação |
|---|---|
| Compose não encontra arquivo | Use `-f .\docker\docker-compose.yml` |
| `401` | Confira o JWT e o prefixo `Bearer` |
| `403` | Confira a role do usuário |
| `502/503` | Confira container e porta interna do destino |
| Lambda `Pending` | Aguarde o provisionamento terminar |
| Gatilhos ausentes | Consulte os logs do LocalStack |
| Mensagem desapareceu | Ela pode ter sido consumida; veja os logs |
| Falhas repetidas | Consulte a DLQ com `status.ps1` |
| Painel LocalStack vazio | Use os scripts; o painel pode exigir licença |

## 13. Parar e recriar

```cmd
docker compose -f ".\docker\docker-compose.yml" down
docker compose -f ".\docker\docker-compose.yml" up -d --build
```

Não use `down -v` sem intenção explícita, pois ele remove volumes e pode apagar dados locais.
