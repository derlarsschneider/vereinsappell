#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="${SCRIPT_DIR}/marschbefehl2026.json"
TABLE_NAME="vereins-app-beta-marschbefehl"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

function add_marschbefehl() {
    jq -nc \
       --arg type "marschbefehl" \
       --arg datetime "$1" \
       --arg text "$2" \
       '{type: {S: $type}, datetime: {S: $datetime}, text: {S: $text}}' | tee "$ITEM_FILE"

    aws dynamodb put-item \
        --table-name "$TABLE_NAME" \
        --item file://"$ITEM_FILE"

    rm "$ITEM_FILE"
}

jq -c '.[]' "$JSON_FILE" | while IFS= read -r entry; do
    datetime=$(printf '%s' "$entry" | jq -r '.datetime')
    text=$(printf '%s' "$entry" | jq -r '.text')
    add_marschbefehl "$datetime" "$text"
done

echo "✅ Marschbefehl wurde erstellt."
