$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"
$queues = @(
    "user-created",
    "user-created-dlq",
    "notification-payment-processed",
    "notification-payment-processed-dlq"
)

Write-Output "=== Filas SQS e contadores ==="
foreach ($queue in $queues) {
    $queueUrl = "http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/$queue"
    $attributes = docker compose -f $composeFile exec -T localstack awslocal sqs get-queue-attributes `
        --queue-url $queueUrl `
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible `
        --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel consultar a fila '$queue'."
    }

    $values = $attributes | ConvertFrom-Json
    $ready = $values.Attributes.ApproximateNumberOfMessages
    $processing = $values.Attributes.ApproximateNumberOfMessagesNotVisible
    Write-Output ("{0}: disponiveis={1}, em-processamento={2}" -f $queue, $ready, $processing)
}

Write-Output "=== Lambda ==="
docker compose -f $composeFile exec -T localstack awslocal lambda get-function `
    --function-name fcg-notification `
    --query "Configuration.{Nome:FunctionName,Estado:State,Runtime:Runtime,Handler:Handler}" `
    --output table

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel consultar a Lambda fcg-notification."
}

Write-Output "=== Gatilhos SQS ==="
docker compose -f $composeFile exec -T localstack awslocal lambda list-event-source-mappings `
    --function-name fcg-notification `
    --query "EventSourceMappings[*].{Fila:EventSourceArn,Estado:State,Resposta:FunctionResponseTypes}" `
    --output table

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel consultar os gatilhos da Lambda."
}
