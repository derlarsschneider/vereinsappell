#!/bin/bash -e

function add_verein() {
TABLE_NAME="vereinsappell-customers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

application_id="$(uuidgen)"
# JSON korrekt mit jq erzeugen
jq -nc \
  --arg application_id   "${application_id}" \
  --arg application_name "$1" \
  --arg application_logo "$2" \
  --arg api_url          "$3" \
  '{
      application_id:   {S: $application_id},
      application_name: {S: $application_name},
      application_logo: {S: $application_logo},
      api_url:          {S: $api_url}
  }' | tee "$ITEM_FILE"

# Einfügen in DynamoDB über Datei
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --item file://"$ITEM_FILE"

# Aufräumen (optional)
rm "$ITEM_FILE"
}

add_verein "Schützenlust Neuss Gnadental" "URL OR BINARY OR BASE64" "https://vereinsappell.derlarsschneider.de"
