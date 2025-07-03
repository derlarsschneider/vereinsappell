#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereins-app-beta-lambda_backend"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
pip install --upgrade -r requirements.txt -t .
zip -r "$ZIP" .
aws lambda update-function-code \
  --function-name "$FUNC_NAME" \
  --zip-file fileb://"$ZIP"
