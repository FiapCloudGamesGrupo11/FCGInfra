param(
    [ValidateSet("user-created", "notification-payment-processed")]
    [string]$Queue = "user-created",

    [ValidateRange(30, 300)]
    [int]$TimeoutSeconds = 150
)

$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"
$accountId = "000000000000"
$endpoint = "http://sqs.us-east-1.localhost.localstack.cloud:4566/$accountId"
$queueUrl = "$endpoint/$Queue"
$dlqUrl = "$endpoint/$Queue-dlq"
$testId = [guid]::NewGuid().ToString("N")
$invalidBody = "invalid-json-$testId"

$lambdaState = docker compose -f $composeFile exec -T localstack awslocal lambda get-function `
    --function-name fcg-notification `
    --query "Configuration.State" `
    --output text

if ($LASTEXITCODE -ne 0 -or $lambdaState.Trim() -ne "Active") {
    throw "A Lambda fcg-notification ainda nao esta Active. Aguarde a inicializacao e tente novamente."
}

$enabledMappings = docker compose -f $composeFile exec -T localstack awslocal lambda list-event-source-mappings `
    --function-name fcg-notification `
    --query "length(EventSourceMappings[?State=='Enabled'])" `
    --output text

if ($LASTEXITCODE -ne 0 -or [int]$enabledMappings -lt 2) {
    throw "Os dois gatilhos SQS da Lambda ainda nao estao Enabled. Aguarde e tente novamente."
}

function Get-VisibleMessageCount([string]$Url) {
    $count = docker compose -f $composeFile exec -T localstack awslocal sqs get-queue-attributes `
        --queue-url $Url `
        --attribute-names ApproximateNumberOfMessages `
        --query "Attributes.ApproximateNumberOfMessages" `
        --output text

    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel consultar a fila $Url."
    }

    return [int]$count
}

$initialDlqCount = Get-VisibleMessageCount $dlqUrl

$response = docker compose -f $composeFile exec -T localstack awslocal sqs send-message `
    --queue-url $queueUrl `
    --message-body $invalidBody `
    --output json

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel enviar a mensagem invalida."
}

$messageId = ($response | ConvertFrom-Json).MessageId
Write-Output "Mensagem invalida enviada. TestId=$testId MessageId=$messageId"
Write-Output "Aguardando tres tentativas e o redrive para $Queue-dlq..."

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Seconds 5
    $currentDlqCount = Get-VisibleMessageCount $dlqUrl

    if ($currentDlqCount -gt $initialDlqCount) {
        Write-Output "SUCESSO: a DLQ aumentou de $initialDlqCount para $currentDlqCount mensagem(ns)."
        Write-Output "Use .\docker\localstack\logs.ps1 para conferir as tentativas da Lambda."
        exit 0
    }
} while ([DateTime]::UtcNow -lt $deadline)

throw "A DLQ nao aumentou dentro de $TimeoutSeconds segundos. Consulte os logs da Lambda e o status das filas."
