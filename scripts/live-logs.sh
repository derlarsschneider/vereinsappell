#!/usr/bin/env bash
# Stream live logs from the Lambda backend to the console (like tail -f).
#
# Usage:
#   ./live-logs.sh [workspace] [filter]
#
# workspace  defaults to "vereins-app-beta"
# filter     optional CloudWatch filter pattern, e.g. "ERROR" or "500"
#
# Examples:
#   ./live-logs.sh
#   ./live-logs.sh vereins-app-beta "ERROR"
#   ./live-logs.sh vereins-app-beta "500"

set -euo pipefail

WORKSPACE="${1:-vereins-app-beta}"
FILTER="${2:-}"
REGION="eu-central-1"
LOG_GROUP="/aws/lambda/${WORKSPACE}-lambda_backend"

echo ">>> Log group : $LOG_GROUP"
echo ">>> Filter    : ${FILTER:-<none>}"
echo ">>> Streaming live (Ctrl+C to stop) ..."
echo ""

ARGS=(
  "$LOG_GROUP"
  --region "$REGION"
  --follow
  --format short
)

if [[ -n "$FILTER" ]]; then
  ARGS+=(--filter-pattern "$FILTER")
fi

aws logs tail "${ARGS[@]}"
