$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"

Write-Output "=== Filas SQS ==="
docker compose -f $composeFile exec -T localstack awslocal sqs list-queues

Write-Output "=== Lambda ==="
docker compose -f $composeFile exec -T localstack awslocal lambda get-function `
    --function-name fcg-notification

Write-Output "=== Gatilhos SQS ==="
docker compose -f $composeFile exec -T localstack awslocal lambda list-event-source-mappings `
    --function-name fcg-notification
