#!/bin/bash -e
version="$(date +%y.%m.%d.%H.%M)"
firebase appdistribution:distribute build/app/outputs/flutter-apk/app-release.apk \
  --app 1:336568095877:android:f757f959bbe6c96be8c5ec \
  --release-notes "Version ${version}" \
  --groups "Schuetzenlust"
