#!/bin/bash

# deploy.sh
# Deployment-Script für das Knobeln Backend

set -e  # Exit bei Fehlern

echo "🎲 Knobeln Backend Deployment Script"
echo "===================================="

# Konfiguration
AWS_REGION=${AWS_REGION:-eu-central-1}
ENVIRONMENT=${ENVIRONMENT:-dev}
PROJECT_NAME="knobeln"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktionen für Log-Output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prüfen ob erforderliche Tools installiert sind
check_requirements() {
    log_info "Checking requirements..."

    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi

    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi

    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi

    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi

    if ! command -v zip &> /dev/null; then
        log_error "zip is not installed. Please install zip first."
        exit 1
    fi

    log_info "All requirements satisfied ✓"
}

# AWS Credentials prüfen
check_aws_credentials() {
    log_info "Checking AWS credentials..."

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid."
        log_error "Please run 'aws configure' or set environment variables."
        exit 1
    fi

    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo $caller_identity | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    local user_arn=$(echo $caller_identity | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)

    log_info "AWS Account: $account_id"
    log_info "User/Role: $user_arn"
    log_info "Region: $AWS_REGION"
}

# Lambda Function Packages erstellen
build_lambda_packages() {
    log_info "Building Lambda function packages..."

    # Lambda-Verzeichnis erstellen
    mkdir -p lambda

    # Game Handler Lambda
    log_info "Building game-handler Lambda..."
    mkdir -p lambda/game-handler
    cp lambda/game-handler/index.js lambda/game-handler/ 2>/dev/null || echo "// lambda/game-handler/index.js" > lambda/game-handler/index.js
    cp package.json lambda/game-handler/

    cd lambda/game-handler
    npm install --production --silent
    zip -r ../game-handler.zip . -x "*.git*" "node_modules/.cache/*" > /dev/null
    cd ../..

    # WebSocket Handler Lambda
    log_info "Building websocket-handler Lambda..."
    mkdir -p lambda/websocket-handler
    cp lambda/websocket-handler/index.js lambda/websocket-handler/ 2>/dev/null || echo "// lambda/websocket-handler/index.js" > lambda/websocket-handler/index.js
    cp package.json lambda/websocket-handler/

    cd lambda/websocket-handler
    npm install --production --silent
    zip -r ../websocket-handler.zip . -x "*.git*" "node_modules/.cache/*" > /dev/null
    cd ../..

    # Game Timer Lambda
    log_info "Building game-timer Lambda..."
    mkdir -p lambda/game-timer
    cp lambda/game-timer/index.js lambda/game-timer/ 2>/dev/null || echo "// lambda/game-timer/index.js" > lambda/game-timer/index.js
    cp package.json lambda/game-timer/

    cd lambda/game-timer
    npm install --production --silent
    zip -r ../game-timer.zip . -x "*.git*" "node_modules/.cache/*" > /dev/null
    cd ../..

    log_info "Lambda packages built successfully ✓"
}

# Terraform initialisieren und deployen
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."

    # Terraform initialisieren
    log_info "Initializing Terraform..."
    terraform init

    # Terraform Plan erstellen
    log_info "Creating Terraform plan..."
    terraform plan \
        -var="aws_region=$AWS_REGION" \
        -var="environment=$ENVIRONMENT" \
        -var="project_name=$PROJECT_NAME" \
        -out=tfplan

    # Plan anzeigen und Bestätigung einholen
    echo ""
    log_warn "Terraform will make the above changes to your AWS account."
    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user."
        exit 0
    fi

    # Terraform Apply ausführen
    log_info "Applying Terraform configuration..."
    terraform apply tfplan

    # Outputs anzeigen
    echo ""
    log_info "Deployment completed! 🎉"
    echo ""
    log_info "=== Deployment Information ==="
    terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
}

# Lambda-Code nach Deployment aktualisieren
update_lambda_functions() {
    log_info "Updating Lambda function code..."

    # Lambda Function Namen aus Terraform Output holen
    local game_handler_name=$(terraform output -raw games_table_name | sed 's/-games$/-game-handler/')
    local websocket_handler_name=$(terraform output -raw games_table_name | sed 's/-games$/-websocket-handler/')
    local game_timer_name=$(terraform output -raw games_table_name | sed 's/-games$/-game-timer/')

    # Game Handler aktualisieren
    log_info "Updating game-handler function..."
    aws lambda update-function-code \
        --function-name "$game_handler_name" \
        --zip-file fileb://lambda/game-handler.zip \
        --region "$AWS_REGION" > /dev/null

    # WebSocket Handler aktualisieren
    log_info "Updating websocket-handler function..."
    aws lambda update-function-code \
        --function-name "$websocket_handler_name" \
        --zip-file fileb://lambda/websocket-handler.zip \
        --region "$AWS_REGION" > /dev/null

    # Game Timer aktualisieren
    log_info "Updating game-timer function..."
    aws lambda update-function-code \
        --function-name "$game_timer_name" \
        --zip-file fileb://lambda/game-timer.zip \
        --region "$AWS_REGION" > /dev/null

    log_info "Lambda functions updated successfully ✓"
}

# API-Endpunkte testen
test_endpoints() {
    log_info "Testing API endpoints..."

    local http_api_url=$(terraform output -raw http_api_url)
    local websocket_api_url=$(terraform output -raw websocket_api_url)

    echo ""
    log_info "=== API Endpoints ==="
    echo "HTTP API: $http_api_url"
    echo "WebSocket API: $websocket_api_url"
    echo ""

    # Einfacher Health-Check
    log_info "Testing HTTP API health..."
    local health_response=$(curl -s -o /dev/null -w "%{http_code}" "$http_api_url/games" -X GET) || health_response="000"

    if [[ "$health_response" == "404" ]]; then
        log_info "HTTP API is responding (404 expected for GET /games) ✓"
    else
        log_warn "HTTP API returned status: $health_response (might be normal)"
    fi

    echo ""
    log_info "=== Example Usage ==="
    echo "Create a game:"
    echo "curl -X POST $http_api_url/games \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"playerId\":\"player1\",\"playerName\":\"Player 1\"}'"
    echo ""
    echo "Join a game:"
    echo "curl -X POST $http_api_url/games/{gameId}/join \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"playerId\":\"player2\",\"playerName\":\"Player 2\"}'"
    echo ""
    echo "WebSocket connection:"
    echo "ws://${websocket_api_url#wss://}?gameId={gameId}"
}

# Cleanup-Funktion
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf lambda/game-handler lambda/websocket-handler lambda/game-timer
    rm -f tfplan
    log_info "Cleanup completed ✓"
}

# Destroy-Funktion
destroy_infrastructure() {
    log_warn "This will DESTROY all resources created by Terraform!"
    read -p "Are you sure you want to destroy the infrastructure? (y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destroying infrastructure..."
        terraform destroy \
            -var="aws_region=$AWS_REGION" \
            -var="environment=$ENVIRONMENT" \
            -var="project_name=$PROJECT_NAME" \
            -auto-approve
        log_info "Infrastructure destroyed ✓"
    else
        log_info "Destroy cancelled by user."
    fi
}

# Hauptfunktion
main() {
    case "${1:-deploy}" in
        "deploy")
            check_requirements
            check_aws_credentials
            build_lambda_packages
            deploy_infrastructure
            update_lambda_functions
            test_endpoints
            cleanup
            ;;
        "destroy")
            check_requirements
            check_aws_credentials
            destroy_infrastructure
            ;;
        "update")
            check_requirements
            build_lambda_packages
            update_lambda_functions
            cleanup
            ;;
        "test")
            test_endpoints
            ;;
        *)
            echo "Usage: $0 [deploy|destroy|update|test]"
            echo ""
            echo "Commands:"
            echo "  deploy  - Deploy the complete infrastructure (default)"
            echo "  destroy - Destroy all infrastructure"
            echo "  update  - Update only Lambda function code"
            echo "  test    - Test API endpoints"
            echo ""
            echo "Environment variables:"
            echo "  AWS_REGION    - AWS region (default: eu-central-1)"
            echo "  ENVIRONMENT   - Environment name (default: dev)"
            exit 1
            ;;
    esac
}

# Trap für Cleanup bei Interrupts
trap cleanup EXIT

# Script ausführen
main "$@"
