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
if [ "$#" -gt 0 ]; then
  ANDROID_APP_ID="$1"
  shift
else
  ANDROID_APP_ID="1:336568095877:android:f757f959bbe6c96be8c5ec"
fi
if [ "$#" -gt 0 ]; then
  TESTER_GROUP="$1"
  shift
else
  TESTER_GROUP="Schuetzenlust"
fi

firebase deploy --only hosting \
  --app "${ANDROID_APP_ID}" \
  --groups "${TESTER_GROUP}" \
  --release-notes "Version ${BUILD_NAME}+${BUILD_NUMBER}"
