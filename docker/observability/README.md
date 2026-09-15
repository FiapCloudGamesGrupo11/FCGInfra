# Logs da Lambda no New Relic

O servico `notification-log-forwarder` consulta o grupo
`/aws/lambda/fcg-notification` do CloudWatch Logs do LocalStack e envia seus
registros para a API de Logs do New Relic por HTTPS. Nao altera o UserAPI,
PaymentAPI nem o handler da Lambda.

## Executar

Na pasta `FCGInfra/docker`, use a chave de ingestao ja configurada em `NEW_RELIC_LICENSE_KEY`
na sessao ou no `.env` ignorado pelo Git. Nao use uma chave pessoal de consultas.
Defina `NEW_RELIC_REGION` como `US` (padrao), `EU` ou `JP`, conforme sua conta.

```powershell
docker compose up -d --build --no-deps notification-log-forwarder
docker compose logs -f notification-log-forwarder
```

O LocalStack precisa estar rodando. `--no-deps` evita recria-lo e perder o historico
local. Um `docker compose up -d --build` completo tambem inclui o encaminhador.
No perfil Kubernetes local, suba o mesmo servico do Compose, que coleta da Lambda
executada no LocalStack do Docker.

O servico imprime somente contagens e erros operacionais, sem expor a chave nem
copiar o conteudo dos logs para sua propria saida. HTTP 401/403: confira chave e
regiao; HTTP 429: o servico espera o intervalo `Retry-After` antes de repetir.
Uma resposta HTTP 2xx confirma aceitacao pela API, nao a disponibilidade imediata
na busca. Aguarde alguns minutos para a indexacao.

## Consultar

No New Relic, selecione a conta correta e as ultimas 24 horas. Execute no Query Builder:

```sql
SELECT timestamp, message FROM Log
WHERE `service.name` = 'FCG-NotificationLambda'
SINCE 24 hours ago LIMIT 100
```

Procure `UserCreatedEvent processado`, `Bem-vindo enviado`,
`PaymentProcessedEvent processado` e `Compra confirmada`.
Os registros preservam o horario original da Lambda e incluem `aws.logGroup`,
`aws.logStream`, `aws.logEventId`, `environment` e `service.name`.
Esse atributo permite filtrar logs; nao cria automaticamente uma entidade APM.

## Retomada e limites

- A cada 15 segundos consulta todas as paginas da janela das ultimas 24 horas.
  Essa abordagem se destina ao baixo volume do ambiente local.
- O volume `notification-log-state` armazena IDs aceitos em SQLite. Reiniciar ou
  recriar apenas o encaminhador preserva a deduplicacao.
- Eventos com o mesmo horario, novos streams e registros atrasados dentro da janela
  sao encontrados. IDs so sao gravados depois da aceitacao HTTP de cada lote.
- A entrega e pelo menos uma vez: queda apos aceitar e antes de gravar pode duplicar
  um lote. `aws.logEventId` identifica o evento original.
- `LOOKBACK_HOURS` permite 1 a 47 horas. Eventos fora dessa janela nao sao enviados,
  inclusive apos uma indisponibilidade longa. New Relic pode descartar eventos
  com mais de 48 horas. Nao alteramos os horarios para contornar esse limite.
- Apagar o volume pode reenviar registros; recriar o LocalStack sem persistencia
  apaga registros de origem que ainda nao foram enviados.
- Mensagens `NR_LAMBDA_MONITORING` sao excluidas: sao payloads de telemetria, nao
  logs de aplicacao. Este servico resolve logs centralizados, nao metricas/traces
  serverless. Mantenha a integracao especifica para esses dados.
- Os logs existentes da aplicacao podem conter e-mail e identificadores de usuario;
  o encaminhador os envia a conta configurada, como os demais logs do sistema.

## Testes locais (sem rede e sem chave)

```powershell
python -m unittest discover -s docker/observability -p test_*.py -v
```

Referencia: https://docs.newrelic.com/docs/logs/log-api/introduction-log-api/
