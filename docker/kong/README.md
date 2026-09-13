# Kong API Gateway - Guia de desenvolvimento

O Kong funciona como a única entrada HTTP para UserAPI e CatalogAPI no ambiente Docker Compose. Os microsserviços não publicam portas HTTP diretamente no host.

## Arquitetura

```text
Cliente / Swagger
       |
       v
Kong Gateway :8000
       |-- UserAPI :8070 (rede Docker)
       `-- CatalogAPI :80 (rede Docker)
```

O Kong valida a assinatura HS256 e a expiração do JWT. UserAPI e CatalogAPI continuam validando issuer, audience, assinatura e expiração, além de aplicar autorização por role.

## Pré-requisitos

- Docker Desktop com o Docker Engine em execução.
- Docker Compose disponível pelo comando `docker compose`.
- Portas `8000`, `8001`, `1433`, `5672` e `15672` livres.
- Repositórios clonados como diretórios irmãos:

```text
FiapCloudGamesGrupo11/
  FCGCatalog/
  FCGInfra/
  FCGNotification/
  FCGPayment/
  FCGUser/
```

Use as branches de trabalho corretas dos microsserviços antes de construir as imagens. O Compose usa diretamente o código presente nesses diretórios.

## Endereços

| Componente | Endereço | Uso |
|------------|----------|-----|
| Kong Proxy | `http://localhost:8000` | Entrada das APIs |
| Kong Admin API | `http://localhost:8001` | Diagnóstico local |
| Swagger UserAPI | `http://user.localhost:8000/swagger` | Cadastro, login e usuários |
| Swagger CatalogAPI | `http://catalog.localhost:8000/swagger` | Jogos, promoções e bibliotecas |
| RabbitMQ Management | `http://localhost:15672` | Filas e exchanges |
| SQL Server | `localhost,1433` | Banco de desenvolvimento |

A Admin API está vinculada somente a `127.0.0.1`. Não a exponha publicamente.

## Rotas públicas

- `POST /api/User/CreateUser`
- `POST /api/User/Login`
- Swagger da UserAPI no host `user.localhost`
- Swagger da CatalogAPI no host `catalog.localhost`

## Rotas protegidas por JWT

- `/api/User`
- `/api/Game`
- `/api/OnSale`
- `/api/UsersGames`

## Validar antes de executar

A partir de `FCGInfra/docker`:

```powershell
docker compose config --quiet
```

Sem saída significa que o Compose é válido.

Valide também a configuração declarativa:

```powershell
docker run --rm -e KONG_DATABASE=off `
  -v "${PWD}\kong\kong.yml:/kong.yml:ro" `
  kong:3.9 `
  kong config parse /kong.yml
```

Resultado esperado:

```text
parse successful
```

Se estiver na raiz de `FCGInfra`, use `-f .\docker\docker-compose.yml` nos comandos do Compose e ajuste o volume para `${PWD}\docker\kong\kong.yml`.

## Construir e iniciar

A partir de `FCGInfra/docker`:

```powershell
docker compose up -d --build
docker compose ps
```

Na primeira execução, o download dos SDKs .NET, SQL Server, RabbitMQ e Kong pode demorar. O parâmetro `-d` passa a valer depois que o build termina.

Todos os containers devem aparecer como `Up`; Kong, SQL Server e RabbitMQ devem ficar `healthy`.

Confirme o carregamento da configuração:

```powershell
docker compose logs kong --tail 100
```

Procure por:

```text
declarative config loaded from /kong/declarative/kong.yml
```

## Verificar as rotas do Kong

```powershell
Invoke-RestMethod http://localhost:8001/services
Invoke-RestMethod http://localhost:8001/routes
Invoke-RestMethod http://localhost:8001/plugins
Invoke-RestMethod http://localhost:8001/consumers
```

Abrir `http://localhost:8000/` retorna `404`, pois não existe rota para `/`. Esse comportamento é esperado.

## Confirmar o ponto de entrada único

As chamadas diretas devem falhar:

```powershell
curl.exe -i http://localhost:8070/api/User/GetAll
curl.exe -i http://localhost:8080/api/Game/GetAllAsync
```

Uma chamada protegida pelo Gateway, sem token, deve retornar `401`:

```powershell
curl.exe -i http://localhost:8000/api/User/GetAll
```

## Testar pelo Swagger

1. Abra `http://user.localhost:8000/swagger`.
2. Execute `POST /api/User/CreateUser`. Essa rota não precisa de token, mesmo que o Swagger exiba um cadeado global.
3. Execute `POST /api/User/Login`.
4. Copie o token retornado.
5. Clique em **Authorize** e informe `Bearer SEU_TOKEN`.
6. Execute `GET /api/User/GetAll`.
7. Abra `http://catalog.localhost:8000/swagger`.
8. Clique em **Authorize** e informe o mesmo token.
9. Execute `GET /api/Game/GetAllAsync`.

Cada host de Swagger mantém sua própria autorização no navegador. Autorize separadamente as duas interfaces.

## Criar o primeiro Admin de desenvolvimento

Cadastre um usuário normal pela UserAPI usando uma senha conhecida. Depois promova somente essa conta no banco:

```powershell
docker exec -it sqlserver `
  /opt/mssql-tools18/bin/sqlcmd `
  -S localhost `
  -U sa `
  -P "Your_strong!Passw0rd" `
  -C `
  -d FiapCloudGames `
  -Q "UPDATE dbo.Users SET Role = 1, Status = 1 WHERE Email = 'admin.gateway@test.com'; SELECT Id, Name, Email, Role, Status FROM dbo.Users WHERE Email = 'admin.gateway@test.com';"
```

Faça login novamente após o `UPDATE`. A role é inserida no JWT durante o login.

Valores atuais:

- `Role.Admin = 1`
- `Role.Common = 2`
- `Status.Active = 1`

Esse procedimento é exclusivo para desenvolvimento local.

## Roteiro de validação

| Cenário | Resultado esperado | Responsável |
|---------|--------------------|-------------|
| Rota protegida sem token | `401 Unauthorized` | Kong |
| Token Common em rota Admin | `403 Forbidden` | Microsserviço |
| Token Admin em rota Admin | `200 OK` | Kong + microsserviço |
| Porta direta da API | Falha de conexão | Docker Compose |

Para testar Admin no Catalog, use `POST /api/Game/CreateGame`:

```json
{
  "name": "Cyber Quest",
  "description": "Jogo criado durante o teste do API Gateway",
  "category": "Adventure",
  "price": 149.90
}
```

## Consultar usuários no banco

```powershell
docker exec -it sqlserver `
  /opt/mssql-tools18/bin/sqlcmd `
  -S localhost `
  -U sa `
  -P "Your_strong!Passw0rd" `
  -C `
  -d FiapCloudGames `
  -Q "SELECT Id, Name, LastName, Email, Role, Status, CreatedAt FROM dbo.Users;"
```

## Diagnóstico

```powershell
docker compose ps
docker compose logs kong --tail 200
docker compose logs userapi --tail 200
docker compose logs catalogapi --tail 200
docker compose logs db --tail 100
```

- `404` em `/`: esperado, não existe rota raiz.
- `401`: token ausente, inválido ou expirado.
- `403`: token válido, mas role insuficiente.
- `502` ou `503`: Kong não conseguiu alcançar o microsserviço; confira container, porta e logs.
- Erro sobre banco ou tabela: confira SQL Server e migrations.
- Swagger não abre: confirme que o Kong está saudável e tente `http://user.localhost:8000/swagger/index.html`.
- `user.localhost` não resolve: teste `ping user.localhost`; navegadores modernos normalmente resolvem `*.localhost` para loopback.

## Reiniciar após mudar configurações

Alteração no `kong.yml`:

```powershell
docker compose up -d --force-recreate kong
```

Alteração em código ou Dockerfile:

```powershell
docker compose up -d --build
```

## Parar o ambiente

```powershell
docker compose down
```

Não use `docker compose down -v` sem intenção explícita de apagar os volumes e os dados locais.

## Segurança

- As credenciais e a chave JWT atuais são somente para desenvolvimento.
- Não reutilize esses valores em produção.
- A Admin API do Kong deve permanecer restrita ao loopback.
- Em produção, armazene credenciais em um gerenciador de segredos e faça rotação periódica.
- `kong.yml` é a fonte da verdade no modo DB-less; mudanças manuais pela Admin API não substituem o arquivo versionado.
