#!/bin/bash -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

authorizer/zip.sh
lambda/zip.sh

terraform apply -auto-approve

authorizer/update.sh
lambda/update.sh

echo "✅ Backend wurde aktualisiert."
