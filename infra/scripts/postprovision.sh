#!/bin/bash
set -euo pipefail

echo "Running post-provision script..."
if ! output=$(azd env get-values); then
    echo "Failed to read values from the azd environment." >&2
    exit 1
fi

ServiceBusNamespace=""
ServiceBusQueueName=""
while IFS= read -r line; do
    value="${line#*=}"
    value="${value#\"}"
    value="${value%\"}"
    if [[ $line == SERVICE_BUS_CONNECTION__fullyQualifiedNamespace=* ]]; then
        ServiceBusNamespace="$value"
    elif [[ $line == SERVICE_BUS_QUEUE_NAME=* ]]; then
        ServiceBusQueueName="$value"
    fi
done <<< "$output"

if [ -z "$ServiceBusNamespace" ] || [ -z "$ServiceBusQueueName" ]; then
    echo "SERVICE_BUS_CONNECTION__fullyQualifiedNamespace or SERVICE_BUS_QUEUE_NAME is missing from the azd environment." >&2
    exit 1
fi

settingsPath=./src/local.settings.json
if [ -f "$settingsPath" ]; then
    # Never overwrite an existing local.settings.json; it may contain your own values.
    # Exit codes: 0 = values match, 2 = read/parse error, 3 = values differ.
    settingsStatus=0
    node -e '
const [file, namespace, queue] = process.argv.slice(1);
let settings;
try {
    settings = JSON.parse(require("fs").readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
} catch {
    console.error("Cannot read src/local.settings.json as JSON. Check syntax and access, then rerun azd provision.");
    process.exit(2);
}
const values = (settings && settings.Values) || {};
process.exit(values.ServiceBusConnection__fullyQualifiedNamespace === namespace && values.ServiceBusQueueName === queue ? 0 : 3);
' "$settingsPath" "$ServiceBusNamespace" "$ServiceBusQueueName" || settingsStatus=$?

    if [ "$settingsStatus" -eq 0 ]; then
        echo "src/local.settings.json already exists and references the provisioned resources."
    elif [ "$settingsStatus" -eq 3 ]; then
        echo "src/local.settings.json already exists and was not changed. Set these values under \"Values\" to use the provisioned resources:"
        echo "  ServiceBusConnection__fullyQualifiedNamespace = $ServiceBusNamespace"
        echo "  ServiceBusQueueName = $ServiceBusQueueName"
    else
        exit "$settingsStatus"
    fi
else
    echo "Creating src/local.settings.json..."
    cat > "$settingsPath" << EOF
{
    "IsEncrypted": false,
    "Values": {
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "FUNCTIONS_WORKER_RUNTIME": "node",
        "ServiceBusConnection__fullyQualifiedNamespace": "$ServiceBusNamespace",
        "ServiceBusQueueName": "$ServiceBusQueueName"
    }
}
EOF
    echo "src/local.settings.json has been created successfully!"
fi

echo "Creating/updating send-message.sh..."
cat > ./send-message.sh << EOF
#!/bin/bash
set -euo pipefail
az rest --method POST --uri "https://$ServiceBusNamespace/$ServiceBusQueueName/messages" --headers "Content-Type=application/atom+xml;type=entry;charset=utf-8" --body "Hello from the CLI" --resource "https://servicebus.azure.net"
EOF
chmod +x ./send-message.sh

echo "send-message.sh has been created successfully!"
echo ""
echo "Service Bus Namespace: $ServiceBusNamespace"
echo "Service Bus Queue: $ServiceBusQueueName"
echo ""
echo "Running locally and sending test messages from your machine require VNET_ENABLED=false."
echo "You can now run the function locally with 'cd src && func start'"
echo "Send test messages with './send-message.sh'"