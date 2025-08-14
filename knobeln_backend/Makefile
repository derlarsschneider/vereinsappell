.PHONY: init plan apply destroy test clean

# Variables
ENV ?= dev
AWS_REGION ?= eu-central-1
TF_DIR = terraform
SRC_DIR = src
VENV = venv
PYTHON = $(VENV)/bin/python3
PIP = $(VENV)/bin/pip
TERRAFORM = terraform -chdir=$(TF_DIR)

# Initialize the development environment
init: venv terraform-init

# Set up Python virtual environment
venv:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

# Initialize Terraform
terraform-init:
	$(TERRAFORM) init

# Format Terraform code
fmt:
	$(TERRAFORM) fmt -recursive

# Validate Terraform configuration
validate:
	$(TERRAFORM) validate

# Show the Terraform execution plan
plan:
	$(TERRAFORM) plan -var="environment=$(ENV)" -var="aws_region=$(AWS_REGION)"

# Apply Terraform changes
apply:
	$(TERRAFORM) apply -var="environment=$(ENV)" -var="aws_region=$(AWS_REGION)" -auto-approve

# Destroy all Terraform-managed infrastructure
destroy:
	$(TERRAFORM) destroy -var="environment=$(ENV)" -var="aws_region=$(AWS_REGION)" -auto-approve

# Run tests
test: venv
	$(PYTHON) -m pytest tests/

# Lint Python code
lint: venv
	$(VENV)/bin/flake8 $(SRC_DIR)
	$(VENV)/bin/black --check $(SRC_DIR)
	$(VENV)/bin/isort --check-only $(SRC_DIR)

# Format Python code
format: venv
	$(VENV)/bin/black $(SRC_DIR)
	$(VENV)/bin/isort $(SRC_DIR)

# Package Lambda functions
package:
	./package_lambda.sh

# Deploy Lambda functions
deploy: package
	./deploy.sh $(ENV) $(AWS_REGION)

# Clean up generated files
clean:
	rm -rf $(VENV)
	find . -type d -name "__pycache__" -exec rm -r {} +
	find . -type d -name "*.pyc" -delete
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.pyd" -delete
	find . -type d -name ".pytest_cache" -exec rm -r {} +

# Show help
help:
	@echo "Available targets:"
	@echo "  init           Initialize the development environment"
	@echo "  plan           Show the Terraform execution plan"
	@echo "  apply          Apply Terraform changes"
	@echo "  destroy        Destroy all Terraform-managed infrastructure"
	@echo "  test           Run tests"
	@echo "  lint           Lint Python code"
	@echo "  format         Format Python code"
	@echo "  package        Package Lambda functions"
	@echo "  deploy         Deploy Lambda functions"
	@echo "  clean          Clean up generated files"
	@echo "  help           Show this help message"

.DEFAULT_GOAL := help
