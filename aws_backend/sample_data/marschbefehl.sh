#!/bin/bash

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
