#!/bin/bash
# Starts a local Flutter web dev server for browser testing.
# Usage: ./scripts/run-web.sh [--port 8080]

set -e

PORT=${PORT:-8080}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p) PORT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting Flutter web server at http://localhost:$PORT ..."
cd "$ROOT"
flutter run -d web-server --web-port "$PORT" --web-hostname localhost
