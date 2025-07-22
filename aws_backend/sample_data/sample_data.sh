#!/bin/bash

function add_member() {
TABLE_NAME="vereins-app-beta-members"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

# JSON korrekt mit jq erzeugen
jq -nc \
  --arg id "$1" \
  --arg name "$2" \
  --arg isSpiess "$3" \
  --arg isAdmin "$4" \
  '{memberId: {S: $id}, name: {S: $name}, isSpiess: {BOOL: ($isSpiess == "true")}, isAdmin: {BOOL: ($isAdmin == "true")}}' | tee "$ITEM_FILE"

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

function add_marschbefehl() {
TABLE_NAME="vereins-app-beta-marschbefehl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ITEM_FILE="${SCRIPT_DIR}/temp_item.json"

# JSON korrekt mit jq erzeugen
jq -nc \
  --arg type "marschbefehl" \
  --arg datetime "$1" \
  --arg text "$2" \
  '{type: {S: $type}, datetime: {S: $datetime}, text: {S: $text}}' | tee "$ITEM_FILE"

# Einfügen in DynamoDB über Datei
aws dynamodb put-item \
  --table-name "$TABLE_NAME" \
  --item file://"$ITEM_FILE"

# Aufräumen (optional)
rm "$ITEM_FILE"
}

add_marschbefehl "2026-05-30 18:00" "Kirmesplatzeröffnung an der Frankenheim-Bude
Anschl. Kirmeseröffnungsparty im Festzelt (freiwillig)"
add_marschbefehl "2026-05-31 12:00" "Eröffnung des Schützenfestes"
add_marschbefehl "2026-05-31 12:15" "Schießwettbewerbe des Regiments"
echo "✅ Marschbefehl wurde erstellt."

add_member "m1" "André Muller"          "false" "false"
add_member "m6" "Theo Schneider"        "false" "false"
add_member "m3" "Thomas Becker"         "false" "false"
add_member "m4" "René Müller"           "false" "false"
add_member "m5" "Lars Schiller"         "true"  "true"
add_member "m2" "Jannik Müller"         "false" "false"
add_member "m7" "Volker Maasch"         "false" "false"
add_member "m8" "Daniel Fellert"        "false" "false"
add_member "m9" "Dominik Schiefer"      "false" "false"
add_member "m10" "Eckhard Linden"       "false" "false"
add_member "m11" "Hermann-Josef Becker" "false" "false"
add_member "m12" "Jochen Schmidt"       "false" "false"
add_member "m13" "Jörg Michels"         "false" "false"
add_member "m14" "Michael Overmann"     "false" "false"
add_member "m15" "Willi Müller"         "false" "false"
add_member "m16" "Wolfgang Fiedler"     "false" "false"
echo "✅ Alle Mitglieder wurden eingefügt."

add_fine "f1" "m1" "Falsche Kleidung" "1.00"
add_fine "f2" "m2" "Unpünktlichkeit" "2.00"
add_fine "f3" "m3" "Unangebrachtes Verhalten" "3.00"
add_fine "f4" "m4" "Nicht erscheinen" "4.00"
add_fine "f5" "m5" "Verletzung der Regeln" "5.00"
add_fine "f6" "m6" "Sonstiges" "6.00"
echo "✅ Alle Strafen wurden eingefügt."