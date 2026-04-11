#!/bin/bash -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  BUILD_NAME="$1"
  shift
else
  BUILD_NAME=$(date +"%Y.%m.%d")
fi
if [ "$#" -gt 0 ]; then
  BUILD_NUMBER="$1"
  shift
else
  BUILD_NUMBER=$(date +"%H%M")
fi

"$SCRIPT_DIR/bump-version.sh" "$BUILD_NAME"
echo "📦 Baue Web App mit Version ${BUILD_NAME}+${BUILD_NUMBER}"

flutter build web --build-name="${BUILD_NAME}" --build-number="${BUILD_NUMBER}" --release

echo "✅ Web Build abgeschlossen: Version ${BUILD_NAME}+${BUILD_NUMBER}"
