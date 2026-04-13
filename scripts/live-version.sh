#!/bin/bash
# Ermittelt die aktuell deployte Version aus dem Live-Bundle auf Firebase Hosting.
# Die Versionsnummer ist als Dart-Konstante "Version YYYY.MM.DD" im kompilierten JS enthalten.

URL="https://vereinsappell.web.app/main.dart.js"

echo "🔍 Lade Live-Bundle von ${URL} ..."
VERSION=$(curl -s "$URL" | grep -oE 'Version .{15}' | head -1)

if [ -z "$VERSION" ]; then
  echo "❌ Version nicht gefunden (Bundle nicht erreichbar oder Format geändert?)"
  exit 1
fi

echo "✅ Live-Version: ${VERSION}"
