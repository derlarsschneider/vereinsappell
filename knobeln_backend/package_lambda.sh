#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENV=${1:-dev}
AWS_REGION=${2:-eu-central-1}
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

# Create necessary directories
echo -e "${YELLOW}🚀 Preparing Lambda deployment packages...${NC}"
mkdir -p .terraform/lambda_zips

# Create a temporary directory for packaging
temp_dir=$(mktemp -d)

echo -e "${GREEN}✅ Created temporary directory: ${temp_dir}${NC}"

# Install dependencies in a virtual environment
echo -e "${YELLOW}📦 Installing dependencies...${NC}"
python3 -m venv ${temp_dir}/venv
source ${temp_dir}/venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Package each Lambda function
for function in "${LAMBDA_FUNCTIONS[@]}"; do
  echo -e "\n${YELLOW}📦 Packaging ${function} Lambda function...${NC}"
  
  # Create a clean directory for this function
  function_dir="${temp_dir}/${function}"
  mkdir -p "${function_dir}"
  
  # Copy the function code
  cp "src/${function}.py" "${function_dir}/"
  
  # Copy the shared modules
  cp src/__init__.py "${function_dir}/"
  cp src/models.py "${function_dir}/"
  cp src/utils.py "${function_dir}/"
  
  # Install dependencies
  cd "${function_dir}" || exit
  mkdir -p package
  
  # Copy the site-packages to the package directory
  cp -r ${temp_dir}/venv/lib/python*/site-packages/* package/
  
  # Create the deployment package
  cd package || exit
  zip -r9 "${OLDPWD}/${function}.zip" .
  
  # Add the function code to the package
  cd "${OLDPWD}" || exit
  zip -g "${function}.zip" "${function}.py"
  zip -g "${function}.zip" "__init__.py"
  zip -g "${function}.zip" "models.py"
  zip -g "${function}.zip" "utils.py"
  
  # Move the package to the lambda_zips directory
  mv "${function}.zip" "${OLDPWD}/.terraform/lambda_zips/"
  
  # Clean up
  cd "${OLDPWD}" || exit
  rm -rf "${function_dir}"
  
  echo -e "${GREEN}✅ Successfully packaged ${function}${NC}"
done

# Clean up
echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
rm -rf "${temp_dir}"

echo -e "\n${GREEN}✨ All Lambda functions have been packaged successfully!${NC}"
echo -e "Packages are available in: ${PWD}/.terraform/lambda_zips/"

exit 0
