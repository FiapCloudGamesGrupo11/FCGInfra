param([switch]$SkipBuild)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$composeFile = Join-Path $PSScriptRoot "../docker/docker-compose.yml"

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command falhou (codigo $LASTEXITCODE)." }
}

# Local profile: shared Docker Desktop images and host.docker.internal.
$contextName = & kubectl config current-context
if ($LASTEXITCODE -ne 0 -or $contextName.Trim() -ne "docker-desktop") {
    throw "Este roteiro requer o contexto docker-desktop. Adapte imagens e endpoint SQS para outros clusters."
}

if ([string]::IsNullOrWhiteSpace($env:NEW_RELIC_LICENSE_KEY)) {
    throw "Defina a variável NEW_RELIC_LICENSE_KEY antes de executar o script."
}

if (-not $SkipBuild) {
    Invoke-Checked docker @("compose", "-f", $composeFile, "build", "userapi", "catalogapi", "paymentsapi")
}
# Lambda runs on Docker, managed by the existing LocalStack initialization script.
Invoke-Checked docker @("compose", "-f", $composeFile, "up", "-d", "--build", "localstack")
$deadline = (Get-Date).AddMinutes(4)
$ready = $false
do {
    $state = & docker compose -f $composeFile exec -T localstack awslocal lambda get-function-configuration `
        --function-name fcg-notification --query State --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and ($state -join "").Trim() -eq "Active") {
        $mappings = & docker compose -f $composeFile exec -T localstack awslocal lambda list-event-source-mappings `
            --function-name fcg-notification --query 'EventSourceMappings[?State==`Enabled`].UUID' --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and @((($mappings -join "") | ConvertFrom-Json)).Count -eq 2) {
            $ready = $true
            break
        }
    }
    Start-Sleep -Seconds 3
} while ((Get-Date) -lt $deadline)
if (-not $ready) { throw "Lambda ou gatilhos nao ficaram prontos. Consulte os logs do LocalStack." }

$secret = & kubectl create secret generic newrelic-secret `
    --from-literal="license-key=$($env:NEW_RELIC_LICENSE_KEY)" `
    --dry-run=client `
    -o yaml
if ($LASTEXITCODE -ne 0) { throw "Falha ao preparar Secret do New Relic." }
$secret | & kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar Secret do New Relic." }

# Dependencies first, including cache and the single payment replica's journal.
foreach ($manifest in @(
    "common/configmap.yaml", "common/secrets.yaml",
    "rabbitmq/rabbitmq-deployment.yaml", "rabbitmq/rabbitmq-service.yaml",
    "mongo/mongo-deployment.yaml", "mongo/mongo-service.yaml",
    "sqlserver/sqlserver-deployment.yaml", "sqlserver/sqlserver-service.yaml",
    "redis/redis.yaml", "payment/payment-data.yaml"
)) {
    Invoke-Checked kubectl @("apply", "-f", $manifest)
}

# Retired continuous Notification workload (upgrade existing installations).
Invoke-Checked kubectl @("delete", "deployment", "notification-api", "--ignore-not-found")
Invoke-Checked kubectl @("delete", "service", "notification-api", "--ignore-not-found")

foreach ($manifest in @(
    "userapi/userapi-deployment.yaml", "userapi/userapi-service.yaml",
    "catalogapi/catalogapi-deployment.yaml", "catalogapi/catalogapi-service.yaml",
    "payment/paymentapi-deployment.yaml", "payment/paymentapi-service.yaml",
    "kong/kong-config.yaml", "kong/kong-deployment.yaml", "kong/kong-service.yaml"
)) {
    Invoke-Checked kubectl @("apply", "-f", $manifest)
}

# Reload rebuilt local images even when their tags have not changed.
foreach ($deployment in @("user-api", "catalog-api", "payments-api", "kong")) {
    Invoke-Checked kubectl @("rollout", "restart", "deployment/$deployment")
    Invoke-Checked kubectl @("rollout", "status", "deployment/$deployment", "--timeout=180s")
}
