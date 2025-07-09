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

echo "📦 Baue iOS App mit Version ${BUILD_NAME}+${BUILD_NUMBER}"

# Flutter vorbereiten
flutter clean
flutter pub get

# iOS-Build (für reale Geräte)
flutter build ipa --release \
  --no-codesign \
  --build-name="${BUILD_NAME}" \
  --build-number="${BUILD_NUMBER}"

# Hinweis:
# ⚠️ Das funktioniert nur auf einem Mac mit Xcode installiert!
# Falls du CI wie Codemagic verwendest, dort ausführen.

echo "✅ iOS Build abgeschlossen: Version ${BUILD_NAME}+${BUILD_NUMBER}"
