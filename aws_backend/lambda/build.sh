#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereins-app-beta-lambda_backend"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
# Install dependencies for arm64/Python 3.12 Lambda runtime.
# manylinux2014_aarch64 matches the Amazon Linux 2 arm64 environment.
pip install --upgrade \
  --platform manylinux2014_aarch64 \
  --implementation cp \
  --python-version 312 \
  --only-binary=:all: \
  -r requirements.txt \
  -t "$SCRIPT_DIR"
