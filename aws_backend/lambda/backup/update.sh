#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereins-app-beta-backup"
cd "$SCRIPT_DIR"
./zip.sh
aws lambda update-function-code \
  --function-name "$FUNC_NAME" \
  --zip-file fileb://lambda.zip
echo "Deployed backup-lambda."
