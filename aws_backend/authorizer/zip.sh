#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP="lambda.zip"
cd "$SCRIPT_DIR"
zip --filesync -r "$ZIP" . -x 'tests/*' '__pycache__/*'
