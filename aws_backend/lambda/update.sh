#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_NAME="vereins-app-beta-lambda_backend"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
./zip.sh
aws lambda update-function-code \
  --function-name "$FUNC_NAME" \
  --zip-file fileb://"$ZIP"

API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='vereins-app-beta-api'].ApiId" --output text)
echo ""
echo "Deployed to \$LATEST. Dev URL:"
echo "  https://${API_ID}.execute-api.eu-central-1.amazonaws.com/dev"
echo ""
echo "To promote to prod, run: ./promote.sh"
