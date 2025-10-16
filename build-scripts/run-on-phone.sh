#!/bin/bash -e

# ADB executable path
ADB=~/tools/android/platform-tools/adb
ADB=adb

PORT="$1" ; shift
if [ "$#" -gt 0 ]; then
  STEP="$1"
fi

device="192.168.0.194:${PORT}"

#~/tools/android/platform-tools/adb pair 192.168.0.195:39763
echo CONNECT
${ADB} connect ${device}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd "$SCRIPT_DIR"

# if STEP is BUILD or empty:
if [ -z "$STEP" ] || [ "$STEP" == "BUILD" ]; then
  echo BUILD
  flutter build apk --release
fi

if [ -z "$STEP" ] || [ "$STEP" == "INSTALL" ]; then
  echo INSTALL
  ${ADB} -s ${device} uninstall de.derlarsschneider.vereinsappell
  ${ADB} -s ${device} install -d -r build/app/outputs/flutter-apk/app-release.apk
  ${ADB} -s ${device} shell monkey -p de.derlarsschneider.vereinsappell -c android.intent.category.LAUNCHER 1
fi

if [ -z "$STEP" ] || [ "$STEP" == "RUN" ]; then
  echo RUN
  ${ADB} -s ${device} shell monkey -p de.derlarsschneider.vereinsappell -c android.intent.category.LAUNCHER 1
fi
