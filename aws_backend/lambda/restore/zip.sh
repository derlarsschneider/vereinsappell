#!/bin/bash -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="$SCRIPT_DIR/.."
cd "$SCRIPT_DIR"
zip --filesync -r lambda.zip restore_handler.py
# firebase_backup and its dependencies (google-auth, requests transport)
zip --filesync -r lambda.zip \
    "$LAMBDA_DIR/firebase_backup.py" \
    "$LAMBDA_DIR/google" \
    "$LAMBDA_DIR/cachetools" \
    "$LAMBDA_DIR/pyasn1" \
    "$LAMBDA_DIR/pyasn1_modules" \
    "$LAMBDA_DIR/rsa" \
    "$LAMBDA_DIR/requests" \
    "$LAMBDA_DIR/urllib3" \
    "$LAMBDA_DIR/certifi" \
    "$LAMBDA_DIR/charset_normalizer" \
    "$LAMBDA_DIR/idna"
