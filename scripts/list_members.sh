#!/usr/bin/env bash
# List all members with their ID, name and active status.
#
# Usage:
#   ./list_members.sh [workspace]
#
# workspace defaults to "vereins-app-beta"

set -euo pipefail

WORKSPACE="${1:-vereins-app-beta}"
REGION="eu-central-1"
TABLE="${WORKSPACE}-members"

echo ">>> Table: $TABLE"
echo ""

aws dynamodb scan \
  --region "$REGION" \
  --table-name "$TABLE" \
  --projection-expression "memberId, #n, isActive" \
  --expression-attribute-names '{"#n": "name"}' \
  --query 'Items[*].{id: memberId.S, name: name.S, active: isActive.BOOL}' \
  --output json \
| python3 -c "
import json, sys
members = json.load(sys.stdin)
members.sort(key=lambda m: (m.get('name') or '').lower())
for m in members:
    active = '' if m.get('active') != False else '  [inaktiv]'
    print(f\"{m['id']:<36}  {m['name']}{active}\")
"
