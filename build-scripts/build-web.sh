#!/bin/bash -e

if [ "$#" -gt 0 ]; then
  BUILD_NAME="$1"
  shift
else
  BUILD_NAME=$(date +"%y.%m.%d")
fi
if [ "$#" -gt 0 ]; then
  BUILD_NUMBER="$1"
  shift
else
  BUILD_NUMBER=$(date +"%H%M")
fi

echo "📦 Baue Web App mit Version ${BUILD_NAME}+${BUILD_NUMBER}"

flutter build web --build-name="${BUILD_NAME}" --build-number="${BUILD_NUMBER}" --release

echo "✅ Web Build abgeschlossen: Version ${BUILD_NAME}+${BUILD_NUMBER}"
