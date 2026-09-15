# Kubernetes local com Docker Desktop

Este roteiro usa as APIs, bancos, RabbitMQ, Redis e Kong no Kubernetes. O LocalStack
continua no Docker Compose de `FCGInfra/docker` e executa SQS e a Lambda. Nao ha
Deployment nem Service da Notification no cluster.

## Executar

1. Habilite Kubernetes no Docker Desktop e selecione o contexto `docker-desktop`.
2. Mantenha os cinco repositorios como pastas irmas.
3. Defina `NEW_RELIC_LICENSE_KEY` na sessao, como descrito no README principal.
4. Execute `./apply-all.ps1` nesta pasta.

O script compila as imagens das APIs, sobe o LocalStack e espera a Lambda e os dois
gatilhos SQS. Inicia tambem o encaminhador de logs da Lambda para New Relic no Docker.
Depois aplica Secrets, bancos, Redis, volume de pagamentos e APIs.
Os Deployments usam os mesmos nomes de imagem do Compose. `-SkipBuild` pula apenas
o build das APIs; use somente quando as imagens atuais ja estiverem disponiveis.

Ao atualizar um cluster antigo, o script remove exclusivamente o Deployment e o
Service `notification-api`. Nao remove bancos, PVCs nem mensagens para fazer essa
migracao. A recriacao do LocalStack pelo Compose, entretanto, perde seu estado,
pois esse ambiente de desenvolvimento esta configurado com `PERSISTENCE=0`.

## Rede

- UserAPI, CatalogAPI e PaymentsAPI usam Services `ClusterIP`.
- Entrada de negocio: Kong, porta `30000` no host.
- Swagger: `http://user.localhost:30000/swagger` e
  `http://catalog.localhost:30000/swagger`.
- Redis: `redis:6379`, interno ao cluster; seu conteudo e descartavel.
- SQS: `http://host.docker.internal:4566`, configurado no ConfigMap.
- LocalStack usa `SQS_ENDPOINT_STRATEGY=dynamic` para devolver URLs de fila
  correspondentes ao endereco usado pelo cliente (Docker ou Kubernetes).

Esse perfil depende da rede e das imagens locais do Docker Desktop. Em Minikube
ou nuvem, ajuste o endpoint SQS, carregue/publice as imagens e configure credenciais
adequadas. O script recusa outro contexto para nao aplicar configuracoes locais por
engano. Nao execute `kubectl apply -R` como substituto do roteiro: isso nao prepara
as imagens nem o LocalStack.

## Persistencia do pagamento

`payment-data` e um PVC de 1 GiB, montado em `/app/payment-data`. Mantem o resultado
por OrderId e as confirmacoes de envio ao RabbitMQ e SQS. O Deployment usa uma replica
e estrategia `Recreate`; nao aumente replicas com esse armazenamento local.
Nao apague o PVC para reiniciar a API: ele conserva a protecao contra repeticoes.

## Validar

```powershell
kubectl get pods
kubectl get svc user-api catalog-api payments-api redis
kubectl get pvc payment-data
kubectl logs deployment/payments-api --tail=100
kubectl exec deployment/redis -- redis-cli ping
../docker/localstack/status.ps1
../docker/localstack/logs.ps1
```

Crie um usuario e uma compra pelos endpoints do Kong para testar o fluxo completo.
Os scripts `test-*-processed.ps1` enviam diretamente ao SQS e nao comprovam o
trajeto CatalogAPI/RabbitMQ/PaymentsAPI. O envio do e-mail continua simulado.
