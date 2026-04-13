#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereins-app-beta-lambda_backend"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
# Install dependencies inside the Amazon Linux 2 container that matches the Lambda runtime.
# This ensures native extensions (e.g. cryptography) are compiled for the correct GLIBC.
pip install --upgrade \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 310 \
  --only-binary=:all: \
  -r requirements.txt \
  -t "$SCRIPT_DIR"
