#!/bin/bash -e

# parse command line parameters
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD="1"
      shift
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

authorizer/zip.sh
lambda/zip.sh

terraform apply -auto-approve

authorizer/update.sh

# if flag --skip-build is set, don't build the lambda
if [ "${SKIP_BUILD}" == "1" ]; then
  echo "⚠️ --skip-build flag set, skipping lambda build."
  lambda/update.sh
else
  lambda/build.sh && lambda/update.sh
fi

echo "✅ Backend wurde aktualisiert."
