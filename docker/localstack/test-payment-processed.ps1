param(
    [ValidateSet("Approved", "Declined")]
    [string]$Status = "Approved",
    [string]$Reason = "Pagamento recusado pela operadora"
)

$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"
$queueUrl = "http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/notification-payment-processed"
$message = @{
    orderId = "order-$([guid]::NewGuid().ToString('N'))"
    paymentId = "payment-$([guid]::NewGuid().ToString('N'))"
    userId = "user-$([guid]::NewGuid().ToString('N'))"
    gameId = "game-$([guid]::NewGuid().ToString('N'))"
    amount = 99.90
    status = $Status
    reason = if ($Status -eq "Approved") { $null } else { $Reason }
    processedAt = [DateTime]::UtcNow.ToString("o")
} | ConvertTo-Json -Compress

# Enviar o JSON pela entrada padrão preserva aspas, espaços e caracteres
# especiais ao atravessar Windows PowerShell, Docker e AWS CLI.
$message | docker compose -f $composeFile exec -T localstack awslocal sqs send-message `
    --queue-url $queueUrl `
    --message-body file:///dev/stdin

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel enviar o PaymentProcessedEvent."
}

Write-Output "PaymentProcessedEvent ($Status) enviado para $queueUrl"
