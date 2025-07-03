#!/bin/bash

function add_member() {
TABLE_NAME="vereins-app-beta-members"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

# JSON korrekt mit jq erzeugen
jq -nc \
  --arg id "$1" \
  --arg name "$2" \
  '{memberId: {S: $id}, name: {S: $name}}' | tee "$ITEM_FILE"

# Einfügen in DynamoDB über Datei
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --item file://"$ITEM_FILE"

# Aufräumen (optional)
rm "$ITEM_FILE"
}

function add_fine() {
TABLE_NAME="vereins-app-beta-fines"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

# JSON korrekt mit jq erzeugen
jq -nc \
  --arg id "$1" \
  --arg memberId "$2" \
  --arg reason "$3" \
  --arg amount "$4" \
  '{fineId: {S: $id}, memberId: {S: $memberId}, reason: {S: $reason}, amount: {N: $amount}}' | tee "$ITEM_FILE"

# Einfügen in DynamoDB über Datei
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --item file://"$ITEM_FILE"

# Aufräumen (optional)
rm "$ITEM_FILE"
}

add_member "m1" "Jürgen Muller"
add_member "m2" "Franz Schäfer"
add_member "m3" "Lena Weiß"
add_member "m4" "André Krüger"
echo "✅ Alle Mitglieder wurden eingefügt."

add_fine "f1" "m1" "Verletzung der Regeln" "5.00"
add_fine "f2" "m2" "Verletzung der Regeln" "5.00"
add_fine "f3" "m3" "Verletzung der Regeln" "5.00"
add_fine "f4" "m4" "Verletzung der Regeln" "5.00"
echo "✅ Alle Fines wurden eingefügt."