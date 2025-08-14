#!/bin/bash

# deploy.sh
# Dieses Skript packt die Lambda-Funktionen und führt terraform apply aus.

# Stoppt bei Fehlern
set -e

echo ">>> Creating Lambda deployment packages..."

# Erstelle Verzeichnisse für die Builds, falls sie nicht existieren
mkdir -p lambda_build

# Verpacke die game_logic Funktion
# (In einem echten Projekt würde man hier Abhängigkeiten mit pip installieren)
echo "Zipping game_logic..."
cd lambda/game_logic
zip -r ../../lambda_build/game_logic.zip .
cd ../..

# Verpacke die ws_handler Funktion
echo "Zipping ws_handler..."
cd lambda/ws_handler
zip -r ../../lambda_build/ws_handler.zip .
cd ../..

echo ">>> Lambda packages created successfully."

# Führe Terraform aus
echo ">>> Initializing Terraform..."
terraform init

echo ">>> Applying Terraform configuration..."
# -auto-approve überspringt die manuelle Bestätigung
terraform apply -auto-approve

echo ">>> Deployment complete!"

# Gib die Endpunkte aus
HTTP_ENDPOINT=$(terraform output -raw http_api_endpoint)
WS_ENDPOINT=$(terraform output -raw ws_api_endpoint)

echo "--------------------------------------------------"
echo "HTTP API Endpoint: ${HTTP_ENDPOINT}"
echo "WebSocket API Endpoint: ${WS_ENDPOINT}"
echo "--------------------------------------------------"

