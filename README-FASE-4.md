# Fase 4 - Status da implantação AWS

Atualizado em 12 de novembro de 2026.

Este documento registra o estado verificado da Fase 4 da Fiap Cloud Games na AWS.
Ele complementa o README principal e diferencia o que já está operacional do que
ainda precisa ser concluído para a entrega acadêmica.

## Estado atual

### Infraestrutura operacional

- Cluster `fcg-prod-cluster` ativo no Amazon EKS 1.37.
- EKS Auto Mode habilitado com os node pools `general-purpose` e `system`.
- Node IAM Role dedicada: `AmazonEKSAutoNodeRole`.
- Nós Auto Mode registrados e `Ready`.
- StorageClass `auto-ebs-sc` usando `ebs.csi.eks.amazonaws.com` e volumes GP3.
- Repositórios privados `fcg-user` e `fcg-catalog` no Amazon ECR.

### Workloads operacionais

- SQL Server executando em StatefulSet com PVC EBS de 10 GiB.
- Banco `FiapCloudGames` criado e migrations do Entity Framework aplicadas.
- MongoDB executando em StatefulSet com PVC EBS de 10 GiB.
- Migrations e seed do MongoDB executados pelo CatalogAPI.
- RabbitMQ executando no cluster.
- UsersAPI executando com a imagem `fcg-user:1.0.1`.
- CatalogAPI executando com a imagem `fcg-catalog:1.0.0`.
- UsersAPI e CatalogAPI agendados explicitamente em nós do EKS Auto Mode.

### Correções realizadas

- Corrigida a Node IAM Role usada pelo EKS Auto Mode.
- Corrigido o provisionamento e binding dos PVCs no EBS.
- Adicionado `fsGroup: 10001` ao SQL Server para permitir escrita como usuário
  não-root.
- Atualizada a variável do SQL Server para `MSSQL_SA_PASSWORD`.
- Adicionada `startupProbe` ao CatalogAPI para proteger a inicialização durante
  migrations e seed.
- Corrigido o mapeamento de `RabbitMQ__Username` para `RabbitMQ__User` no
  CatalogAPI.
- Removida do CatalogAPI a dependência do sink SQL durante o bootstrap. Os logs
  continuam disponíveis no console e podem ser encaminhados para a plataforma de
  observabilidade.
- Corrigido o cadastro da UsersAPI para não retornar HTTP 500 depois de o usuário
  já ter sido persistido quando a publicação no SQS falhar. A falha de publicação
  é registrada no log.
- Adicionado teste para o comportamento degradado do cadastro quando o SQS está
  indisponível.

### Validações executadas

- UsersAPI: 10 testes automatizados aprovados.
- CatalogAPI: 17 testes automatizados aprovados.
- SQL Server pronto para conexões e acessível por `kubectl port-forward`.
- UsersAPI testada por Postman por meio de `kubectl port-forward`.
- PVCs do SQL Server e MongoDB em estado `Bound`.
- Pods atuais das APIs e dependências em estado `Running`.

## Pendências prioritárias

### P0 - Configuração e segurança de produção

- Criar um overlay/configuração exclusiva para AWS com
  `ASPNETCORE_ENVIRONMENT=Production`.
- Remover do ambiente EKS as configurações de LocalStack, incluindo
  `AWS__ServiceUrl`, `AWS_ACCESS_KEY_ID=test` e `AWS_SECRET_ACCESS_KEY=test`.
- Remover `k8s/common/secrets.yaml` do versionamento e rotacionar os valores que
  já tenham sido expostos.
- Integrar AWS Secrets Manager por External Secrets Operator ou Secrets Store CSI.
- Criar ServiceAccounts dedicados e associações EKS Pod Identity para UsersAPI e
  CatalogAPI.
- Confirmar a revogação da Access Key exposta durante a configuração do ambiente.

### P0 - Serviços AWS gerenciados

- Criar ou validar as filas reais do Amazon SQS e a integração da UsersAPI.
- Implementar retry, Outbox ou reprocessamento para eventos que não forem
  publicados no SQS.
- Provisionar ou validar Amazon ElastiCache para Redis.
- Provisionar ou validar Amazon OpenSearch Service com endpoint privado e SigV4.
- Conceder ao CatalogAPI somente as permissões necessárias para OpenSearch.
- Validar a Lambda/Notification e o fluxo completo de notificações na AWS.

### P0 - Exposição e resiliência

- Criar Ingress/ALB e URLs externas para UsersAPI e CatalogAPI.
- Manter SQL Server, MongoDB e RabbitMQ somente como `ClusterIP`.
- Aumentar UsersAPI e CatalogAPI para pelo menos duas réplicas durante a
  demonstração.
- Adicionar probes completas à UsersAPI.
- Configurar RollingUpdate com `maxUnavailable: 0` e `maxSurge: 1`.
- Criar PodDisruptionBudgets e distribuir as réplicas entre nós.
- Executar e registrar teste de rollout sem indisponibilidade e rollback.

### P0 - Imagens e CI/CD

- Publicar a correção atual do CatalogAPI em uma nova imagem, substituindo
  `fcg-catalog:1.0.0`.
- Configurar autenticação do GitHub Actions na AWS por OIDC.
- Publicar imagens no ECR automaticamente com tag por commit SHA e digest.
- Automatizar o deploy no EKS, a espera pelo rollout e o rollback em caso de falha.
- Ativar imutabilidade de tags, scan de imagens e política de retenção no ECR.
- Fixar versões ou digests das imagens de SQL Server, MongoDB e RabbitMQ.

### P0 - Infraestrutura como código

- Versionar VPC, subnets, EKS, ECR, IAM, Pod Identity, SQS, ElastiCache,
  OpenSearch, Security Groups e Secrets Manager com Terraform ou ferramenta
  equivalente.
- Configurar remote state, locking, tags de custo e proteção de recursos de dados.
- Documentar backup, snapshots EBS, restore e retenção de SQL Server e MongoDB.

### P0 - Testes e evidências

- Validar cache miss, cache hit, invalidação e fallback do Redis.
- Validar indexação automática de create/update no OpenSearch.
- Validar `/search` com correspondência exata, erros de digitação e relevância.
- Criar smoke tests e testes de performance reproduzíveis.
- Medir p50, p95, throughput, taxa de erro e ganho do cache.
- Registrar evidências do EKS, ECR, ALB, SQS, OpenSearch, ElastiCache e pipelines.

### Entrega acadêmica

- Atualizar ADR e diagrama da arquitetura de produção.
- Atualizar a matriz de rastreabilidade dos requisitos.
- Preparar o roteiro e gravar o pitch final com até 25 minutos.
- Montar o relatório final com integrantes, Discord, repositórios, README e vídeo.
- Validar todos os links em sessão anônima antes da entrega.

## Comandos de validação

```powershell
kubectl get nodes -L eks.amazonaws.com/compute-type
kubectl get pods -A -o wide
kubectl get deployments,statefulsets,services -A
kubectl get pvc -A
kubectl get ingress -A
kubectl get pdb -A
```

Para acessar temporariamente as APIs sem exposição pública:

```powershell
kubectl port-forward service/user-api 18070:8070
kubectl port-forward service/catalog-api 18080:8080
```

Para acessar o SQL Server pelo SSMS:

```powershell
kubectl port-forward service/db 15433:1433
```

Use `127.0.0.1,15433` no SSMS e mantenha o terminal do port-forward aberto.

## Observações

- O MongoDB no EKS atende à persistência atual, mas ainda precisa de estratégia de
  backup e recuperação documentada.
- O cadastro de usuário funciona quando o SQS está indisponível, porém o evento
  não é reprocessado automaticamente. Essa tolerância é temporária até a integração
  com SQS/Outbox ser concluída.
- O ambiente atual comprova a fundação técnica, mas ainda não comprova exposição
  externa, serviços gerenciados, GitOps e zero downtime exigidos pela Fase 4.

