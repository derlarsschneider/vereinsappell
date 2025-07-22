#!/bin/bash -e

PORT="$1" ; shift
if [ "$#" -gt 0 ]; then
  STEP="$1"
fi

device="192.168.0.194:${PORT}"

#~/tools/android/platform-tools/adb pair 192.168.0.195:39763
echo CONNECT
~/tools/android/platform-tools/adb connect ${device}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd "$SCRIPT_DIR"

# if STEP is BUILD or empty:
if [ -z "$STEP" ] || [ "$STEP" == "BUILD" ]; then
  echo BUILD
  flutter build apk --release
fi

if [ -z "$STEP" ] || [ "$STEP" == "INSTALL" ]; then
  echo INSTALL
  ~/tools/android/platform-tools/adb -s ${device} uninstall de.derlarsschneider.vereinsappell
  ~/tools/android/platform-tools/adb -s ${device} install -d -r build/app/outputs/flutter-apk/app-release.apk
  ~/tools/android/platform-tools/adb -s ${device} shell monkey -p de.derlarsschneider.vereinsappell -c android.intent.category.LAUNCHER 1
fi

if [ -z "$STEP" ] || [ "$STEP" == "RUN" ]; then
  echo RUN
  ~/tools/android/platform-tools/adb -s ${device} shell monkey -p de.derlarsschneider.vereinsappell -c android.intent.category.LAUNCHER 1
fi
