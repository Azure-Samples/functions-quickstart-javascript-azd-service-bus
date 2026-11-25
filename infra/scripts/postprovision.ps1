$ErrorActionPreference = "Stop"

Write-Host "Running post-provision script..." -ForegroundColor Yellow

$envValues = azd env get-values --output json
if ($LASTEXITCODE -ne 0) {
    throw "Failed to read values from the azd environment."
}
$outputs = $envValues | Out-String | ConvertFrom-Json
$ServiceBusNamespace = $outputs.SERVICE_BUS_CONNECTION__fullyQualifiedNamespace
$ServiceBusQueueName = $outputs.SERVICE_BUS_QUEUE_NAME

if (-not $ServiceBusNamespace -or -not $ServiceBusQueueName) {
    throw "SERVICE_BUS_CONNECTION__fullyQualifiedNamespace or SERVICE_BUS_QUEUE_NAME is missing from the azd environment."
}

$settingsPath = ".\src\local.settings.json"
if (Test-Path $settingsPath) {
    # Never overwrite an existing local.settings.json; it may contain your own values.
    $settings = $null
    $settingsMatch = $false
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Cannot read src/local.settings.json as JSON. Check syntax and access, then rerun azd provision."
    }

    if ($null -eq $settings) {
        throw "src/local.settings.json must contain a JSON object. Fix it and rerun azd provision."
    }
    if ($settings.Values.ServiceBusConnection__fullyQualifiedNamespace -ceq $ServiceBusNamespace -and $settings.Values.ServiceBusQueueName -ceq $ServiceBusQueueName) {
        Write-Host "src/local.settings.json already exists and references the provisioned resources." -ForegroundColor Green
        $settingsMatch = $true
    }
    else {
        Write-Host "src/local.settings.json already exists and was not changed. Set these values under ""Values"" to use the provisioned resources:" -ForegroundColor Yellow
    }

    if (-not $settingsMatch) {
        Write-Host "  ServiceBusConnection__fullyQualifiedNamespace = $ServiceBusNamespace" -ForegroundColor Cyan
        Write-Host "  ServiceBusQueueName = $ServiceBusQueueName" -ForegroundColor Cyan
    }
}
else {
    Write-Host "Creating src/local.settings.json..." -ForegroundColor Yellow
    [ordered]@{
        "IsEncrypted" = $false
        "Values" = [ordered]@{
            "AzureWebJobsStorage" = "UseDevelopmentStorage=true"
            "FUNCTIONS_WORKER_RUNTIME" = "node"
            "ServiceBusConnection__fullyQualifiedNamespace" = "$ServiceBusNamespace"
            "ServiceBusQueueName" = "$ServiceBusQueueName"
        }
    } | ConvertTo-Json | Out-File -FilePath $settingsPath -Encoding utf8
    Write-Host "src/local.settings.json has been created successfully!" -ForegroundColor Green
}

Write-Host "Creating/updating send-message.ps1..." -ForegroundColor Yellow

@"
az rest --method POST --uri 'https://$ServiceBusNamespace/$ServiceBusQueueName/messages' --headers 'Content-Type=application/atom+xml;type=entry;charset=utf-8' --body 'Hello from the CLI' --resource 'https://servicebus.azure.net'
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@ | Out-File -FilePath ".\send-message.ps1" -Encoding utf8 -Force

Write-Host "send-message.ps1 has been created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Service Bus Namespace: $ServiceBusNamespace" -ForegroundColor Cyan
Write-Host "Service Bus Queue: $ServiceBusQueueName" -ForegroundColor Cyan
Write-Host ""
Write-Host "With VNet enabled, local use requires private endpoint connectivity and DNS." -ForegroundColor Yellow
Write-Host "You can now run the function locally with 'cd src && func start'" -ForegroundColor Green
Write-Host "Send test messages with './send-message.ps1'" -ForegroundColor Green