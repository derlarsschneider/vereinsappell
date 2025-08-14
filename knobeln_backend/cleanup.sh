#!/bin/bash
set -e

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-eu-central-1}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display error messages
error_exit() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    exit 1
}

# Function to run a command with error handling
run_command() {
    echo -e "${YELLOW}▶ $1${NC}"
    eval $1 || error_exit "Command failed: $1"
}

echo -e "${YELLOW}🚀 Starting cleanup for environment: ${ENVIRONMENT} in region: ${AWS_REGION}${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install it first."
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    error_exit "Terraform is not installed. Please install it first."
fi

# Ask for confirmation before proceeding
read -p "Are you sure you want to destroy all resources for environment '${ENVIRONMENT}'? This cannot be undone! (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${YELLOW}⚠️  Cleanup cancelled by user.${NC}"
    exit 0
fi

# Navigate to the terraform directory
cd terraform

# Initialize Terraform if not already done
if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}🛠️  Initializing Terraform...${NC}"
    run_command "terraform init"
fi

# Destroy the infrastructure
echo -e "\n${YELLOW}💥 Destroying infrastructure...${NC}"
run_command "terraform destroy -auto-approve \
    -var=\"environment=${ENVIRONMENT}\" \
    -var=\"aws_region=${AWS_REGION}\""

# Clean up local files
echo -e "\n${YELLOW}🧹 Cleaning up local files...${NC}"
cd ..
rm -rf .terraform
rm -f terraform.tfstate* .terraform.lock.hcl
rm -f .terraform.lock.hcl
rm -f .terraform.tfstate.lock.info
rm -rf .terraform/lambda_zips

# If this is a production environment, also clean up the S3 backend
if [ "$ENVIRONMENT" == "prod" ]; then
    echo -e "\n${YELLOW}🧹 Cleaning up S3 backend...${NC}"
    # Extract the S3 bucket name from the backend configuration
    S3_BUCKET=$(grep -A 2 'backend "s3"' terraform/backend.tf | grep 'bucket' | awk -F'"' '{print $2}')
    
    if [ -n "$S3_BUCKET" ]; then
        echo "Deleting contents of S3 bucket: $S3_BUCKET"
        if aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
            aws s3 rm "s3://${S3_BUCKET}" --recursive
            echo "S3 bucket contents deleted."
        else
            echo "S3 bucket not found or already empty."
        fi
    fi
fi

echo -e "\n${GREEN}✨ Cleanup completed successfully!${NC}"
echo -e "All resources for environment '${ENVIRONMENT}' have been destroyed."

# Return to the original directory
cd ..
