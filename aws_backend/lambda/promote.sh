#!/bin/bash -e
# Publishes the current $LATEST Lambda code as a new version and points the prod alias to it.
FUNC_NAME="vereins-app-beta-lambda_backend"

echo "Publishing new Lambda version..."
VERSION=$(aws lambda publish-version \
  --function-name "$FUNC_NAME" \
  --query 'Version' \
  --output text)
echo "Published version: $VERSION"

echo "Updating prod alias to version $VERSION..."
aws lambda update-alias \
  --function-name "$FUNC_NAME" \
  --name prod \
  --function-version "$VERSION"

echo ""
echo "prod alias now points to version $VERSION."
