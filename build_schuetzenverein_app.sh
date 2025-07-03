#!/bin/bash

# Name des Flutter-Projekts
PROJECT_NAME="schuetzenverein_app"

# Dart-Code Datei (Input)
INPUT_DART_FILE="schuetzenverein_app.txt"

# Prüfen ob Flutter installiert ist
if ! command -v flutter &> /dev/null
then
    echo "Flutter ist nicht installiert oder nicht im PATH."
    exit 1
fi

# Neues Flutter-Projekt erstellen (überschreibt nicht vorhandene)
if [ -d "$PROJECT_NAME" ]; then
  echo "Projektverzeichnis $PROJECT_NAME existiert bereits."
else
  flutter create $PROJECT_NAME
fi

# Dart-Code in lib/main.dart kopieren
cp "$INPUT_DART_FILE" "$PROJECT_NAME/lib/main.dart"
echo "Kopiert $INPUT_DART_FILE nach $PROJECT_NAME/lib/main.dart"

# In Projektverzeichnis wechseln
cd $PROJECT_NAME || exit 1

# Release APK bauen
flutter build apk --release

if [ $? -eq 0 ]; then
  echo "Build erfolgreich!"
  echo "APK befindet sich unter: build/app/outputs/flutter-apk/app-release.apk"
else
  echo "Build fehlgeschlagen."
  exit 1
fi
