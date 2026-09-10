$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"

docker compose -f $composeFile exec -T localstack awslocal logs filter-log-events `
    --log-group-name /aws/lambda/fcg-notification `
    --query "events[*].message" `
    --output text

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel consultar os logs da Lambda. Verifique se ela ja foi executada."
}
