Set-Location $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($env:NEW_RELIC_LICENSE_KEY)) {
    throw "Defina a variável NEW_RELIC_LICENSE_KEY antes de executar o script."
}

kubectl create secret generic newrelic-secret `
    --from-literal="license-key=$($env:NEW_RELIC_LICENSE_KEY)" `
    --dry-run=client `
    -o yaml |
    kubectl apply -f -

# Aplicar configs comuns
kubectl apply -f common/configmap.yaml
kubectl apply -f common/secrets.yaml

# User API
kubectl apply -f userapi/userapi-deployment.yaml
kubectl apply -f userapi/userapi-service.yaml

# Catalog API
kubectl apply -f catalogapi/catalogapi-deployment.yaml
kubectl apply -f catalogapi/catalogapi-service.yaml

# Payment API
kubectl apply -f payment/paymentapi-deployment.yaml
kubectl apply -f payment/paymentapi-service.yaml

# Notification API
kubectl apply -f notificationapi/notificationapi-deployment.yaml
kubectl apply -f notificationapi/notificationapi-service.yaml

# RabbitMQ
kubectl apply -f rabbitmq/rabbitmq-deployment.yaml
kubectl apply -f rabbitmq/rabbitmq-service.yaml

# SQL Server
kubectl apply -f sqlserver/sqlserver-deployment.yaml
kubectl apply -f sqlserver/sqlserver-service.yaml
