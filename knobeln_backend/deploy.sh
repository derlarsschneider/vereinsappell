#!/bin/bash
set -e

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-eu-central-1}
LAMBDA_RUNTIME="python3.11"
LAMBDA_FUNCTIONS=(
  "create_game"
  "join_game"
  "pick_sticks"
  "guess_total"
  "start_game"
  "pick_timeout"
  "websocket"
  "get_game"
)

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Starting deployment for environment: ${ENVIRONMENT} in region: ${AWS_REGION}${NC}"

# Create necessary directories
mkdir -p .terraform/lambda_zips

# Install Python dependencies
if [ ! -d "venv" ]; then
  echo -e "${GREEN}Creating Python virtual environment...${NC}"
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
else
  source venv/bin/activate
fi

# Package and deploy each Lambda function
for FUNCTION in "${LAMBDA_FUNCTIONS[@]}"; do
  echo -e "\n${YELLOW}📦 Packaging ${FUNCTION} Lambda function...${NC}"
  
  # Create a temporary directory for the function
  rm -rf /tmp/${FUNCTION}
  mkdir -p /tmp/${FUNCTION}
  
  # Copy the function code
  cp -r src/${FUNCTION}.py /tmp/${FUNCTION}/
  
  # Copy any additional files needed by the function
  if [ -d "src/${FUNCTION}_deps" ]; then
    cp -r src/${FUNCTION}_deps/* /tmp/${FUNCTION}/
  fi
  
  # Install dependencies if there's a requirements file
  if [ -f "src/requirements_${FUNCTION}.txt" ]; then
    pip install -r src/requirements_${FUNCTION}.txt -t /tmp/${FUNCTION}/
  fi
  
  # Create the zip file
  cd /tmp/${FUNCTION}

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    error_exit "Python 3 is not installed. Please install it first."
fi

# Package the Lambda functions
echo -e "\n${YELLOW}📦 Packaging Lambda functions...${NC}"
run_command "./package_lambda.sh ${ENVIRONMENT} ${AWS_REGION}"

# Initialize and apply Terraform
echo -e "\n${YELLOW}🛠️  Initializing Terraform...${NC}"
cd terraform
run_command "terraform init"

# Create a plan file
echo -e "\n${YELLOW}📝 Creating Terraform execution plan...${NC}"
run_command "terraform plan \
  -var=\"environment=${ENVIRONMENT}\" \
  -var=\"aws_region=${AWS_REGION}\" \
  -out=tfplan"

# Ask for confirmation before applying
read -p "Do you want to apply these changes? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${YELLOW}⚠️  Deployment cancelled by user.${NC}"
    exit 0
fi

# Apply the plan
echo -e "\n${YELLOW}🚀 Applying Terraform changes...${NC}"
run_command "terraform apply -auto-approve tfplan"

# Get the API endpoints
echo -e "\n${YELLOW}🔍 Retrieving API endpoints...${NC}"
HTTP_API_ENDPOINT=$(terraform output -raw http_api_endpoint 2>/dev/null || echo "Not available")
WEBSOCKET_API_ENDPOINT=$(terraform output -raw websocket_api_endpoint 2>/dev/null || echo "Not available")

# Print deployment summary
echo -e "\n${GREEN}✅ Deployment complete!${NC}"
echo -e "\n${YELLOW}📡 API Endpoints:${NC}"
echo "HTTP API: ${HTTP_API_ENDPOINT}"
echo "WebSocket API: ${WEBSOCKET_API_ENDPOINT}"

# Print environment variables for frontend configuration
if [[ "$HTTP_API_ENDPOINT" != "Not available" && "$WEBSOCKET_API_ENDPOINT" != "Not available" ]]; then
    echo -e "\n${YELLOW}To update the frontend configuration, set these environment variables:${NC}"
    echo "REACT_APP_API_URL=${HTTP_API_ENDPOINT}"
    echo "REACT_APP_WS_URL=${WEBSOCKET_API_ENDPOINT}"
    
    # Create/update .env file
    echo -e "\n${YELLOW}📝 Creating/updating .env file...${NC}"
    echo "REACT_APP_API_URL=${HTTP_API_ENDPOINT}" > ../.env
    echo "REACT_APP_WS_URL=${WEBSOCKET_API_ENDPOINT}" >> ../.env
    echo -e "${GREEN}✅ Created/updated .env file${NC}"
fi

# Print next steps
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Test the API endpoints to ensure they're working correctly"
echo "2. Update your frontend application with the new API endpoints"
echo "3. Monitor the application using AWS CloudWatch"

echo -e "\n${GREEN}✨ Deployment completed successfully!${NC}"

# Return to the original directory
cd ..
