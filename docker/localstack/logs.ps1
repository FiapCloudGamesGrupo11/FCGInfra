param(
    [ValidateRange(1, 1440)]
    [int]$Minutes = 15
)

$composeFile = Join-Path $PSScriptRoot "..\docker-compose.yml"
$startTime = [DateTimeOffset]::UtcNow.AddMinutes(-$Minutes).ToUnixTimeMilliseconds()

Write-Output "=== Logs da Lambda dos ultimos $Minutes minuto(s) ==="

docker compose -f $composeFile exec -T localstack awslocal logs filter-log-events `
    --log-group-name /aws/lambda/fcg-notification `
    --start-time $startTime `
    --query "events[*].message" `
    --output text

if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel consultar os logs da Lambda. Verifique se ela ja foi executada no ambiente atual."
}
