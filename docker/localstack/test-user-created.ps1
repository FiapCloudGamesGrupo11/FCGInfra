param(
    [string]$Name = "Usuario Teste",
    [string]$Email = "usuario.teste@fcg.local"
)

$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"
$queueUrl = "http://sqs.us-east-1.localhost.localstack.cloud:4566/000000000000/user-created"
$message = @{
    userId = [guid]::NewGuid().ToString()
    name = $Name
    email = $Email
} | ConvertTo-Json -Compress

# Enviar o JSON pela entrada padrão preserva aspas, espaços e caracteres
# especiais ao atravessar Windows PowerShell, Docker e AWS CLI.
$message | docker compose -f $composeFile exec -T localstack awslocal sqs send-message `
    --queue-url $queueUrl `
    --message-body file:///dev/stdin

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel enviar o UserCreatedEvent."
}

Write-Output "UserCreatedEvent enviado para $queueUrl"
