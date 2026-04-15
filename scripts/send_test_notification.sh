#!/usr/bin/env bash
# Send a test reminder notification to a specific member via FCM.
#
# Usage:
#   ./send_test_notification.sh <memberId> [workspace]
#
# workspace defaults to the Terraform workspace "vereins-app-beta".
#
# The script:
#   1. Looks up the member's FCM token from DynamoDB
#   2. Fetches the Firebase service-account JSON from Secrets Manager
#   3. Mints an OAuth2 access token (uses google-auth from the lambda/ directory)
#   4. Posts a test notification to Firebase Cloud Messaging HTTP v1 API

set -euo pipefail

MEMBER_ID="${1:-}"
WORKSPACE="${2:-vereins-app-beta}"
REGION="eu-central-1"
FIREBASE_SECRET_NAME="firebase-credentials"
LAMBDA_DIR="$(cd "$(dirname "$0")/lambda" && pwd)"

if [[ -z "$MEMBER_ID" ]]; then
  echo "Usage: $0 <memberId> [workspace]"
  exit 1
fi

MEMBERS_TABLE="${WORKSPACE}-members"

echo ">>> Looking up member '${MEMBER_ID}' in table '${MEMBERS_TABLE}'..."

FCM_TOKEN=$(aws dynamodb get-item \
  --region "$REGION" \
  --table-name "$MEMBERS_TABLE" \
  --key "{\"memberId\": {\"S\": \"${MEMBER_ID}\"}}" \
  --query 'Item.token.S' \
  --output text)

if [[ -z "$FCM_TOKEN" || "$FCM_TOKEN" == "None" ]]; then
  echo "ERROR: No FCM token found for member '${MEMBER_ID}'"
  exit 1
fi

echo ">>> FCM token found: ${FCM_TOKEN:0:20}..."

echo ">>> Fetching Firebase credentials from Secrets Manager..."

# Write to a temp file to avoid shell interpolation corrupting the JSON private key
SA_FILE=$(mktemp /tmp/firebase-sa-XXXXXX.json)
trap 'rm -f "$SA_FILE"' EXIT

aws secretsmanager get-secret-value \
  --region "$REGION" \
  --secret-id "$FIREBASE_SECRET_NAME" \
  --query SecretString \
  --output text > "$SA_FILE"

echo ">>> Minting Firebase access token..."

read -r ACCESS_TOKEN PROJECT_ID < <(PYTHONPATH="$LAMBDA_DIR" python3 - "$SA_FILE" <<'PYEOF'
import json, sys
from google.oauth2 import service_account
from google.auth.transport.requests import Request

with open(sys.argv[1]) as f:
    sa = json.load(f)

creds = service_account.Credentials.from_service_account_info(
    sa,
    scopes=["https://www.googleapis.com/auth/firebase.messaging"],
)
creds.refresh(Request())
print(creds.token, sa["project_id"])
PYEOF
)

EVENT_TIME=$(date -d "+2 hours" +"%d.%m.%Y %H:%M Uhr" 2>/dev/null \
  || date -v+2H +"%d.%m.%Y %H:%M Uhr")  # macOS fallback

echo ">>> Sending test notification to member '${MEMBER_ID}' (project: ${PROJECT_ID})..."

RESPONSE=$(curl -sf \
  -X POST \
  "https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"message\": {
      \"token\": \"${FCM_TOKEN}\",
      \"data\": {
        \"title\": \"Erinnerung: Testtermin\",
        \"body\": \"Termin am ${EVENT_TIME}\",
        \"type\": \"reminder\"
      }
    }
  }")

echo ">>> Response:"
echo "$RESPONSE" | python3 -m json.tool

echo ""
echo "Done."
