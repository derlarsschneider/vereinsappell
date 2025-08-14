#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Setting up Knobeln Game Backend development environment...${NC}"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}❌ Python 3 is required but not installed. Please install Python 3.8 or higher.${NC}"
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}❌ pip3 is required but not installed. Please install pip3.${NC}"
    exit 1
fi

# Create a virtual environment
echo -e "\n${YELLOW}🔧 Creating Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
echo -e "\n${YELLOW}⬆️  Upgrading pip...${NC}"
pip install --upgrade pip

# Install development dependencies
echo -e "\n${YELLOW}📦 Installing development dependencies...${NC}"
pip install -r requirements-dev.txt

# Install pre-commit hooks
echo -e "\n${YELLOW}🔧 Setting up pre-commit hooks...${NC}"
pre-commit install

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo -e "\n${YELLOW}📝 Creating .env file from .env.example...${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit the .env file with your configuration.${NC}"
else
    echo -e "\n${YELLOW}ℹ️  .env file already exists.${NC}"
fi

# Install Terraform if not installed
if ! command -v terraform &> /dev/null; then
    echo -e "\n${YELLOW}📦 Installing Terraform...${NC}"
    # This is for Ubuntu/Debian - adjust for other distributions
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform
else
    echo -e "\n${YELLOW}ℹ️  Terraform is already installed.${NC}"
fi

# Install AWS CLI if not installed
if ! command -v aws &> /dev/null; then
    echo -e "\n${YELLOW}📦 Installing AWS CLI...${NC}"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
else
    echo -e "\n${YELLOW}ℹ️  AWS CLI is already installed.${NC}"
fi

# Make scripts executable
echo -e "\n${YELLOW}🔧 Making scripts executable...${NC}"
chmod +x deploy.sh
chmod +x cleanup.sh
chmod +x package_lambda.sh
chmod +x setup_development.sh

# Initialize Terraform
echo -e "\n${YELLOW}🛠️  Initializing Terraform...${NC}"
cd terraform
terraform init
cd ..

echo -e "\n${GREEN}✨ Development environment setup complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Edit the .env file with your configuration"
echo "2. Run 'source venv/bin/activate' to activate the virtual environment"
echo "3. Run 'make test' to run the tests"
echo "4. Run 'make lint' to check code style"
echo "5. Run 'make format' to format the code"
echo -e "\n${YELLOW}Happy coding! 🚀${NC}"
