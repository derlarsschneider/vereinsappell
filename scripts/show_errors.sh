#!/usr/bin/env bash
# Show recent error logs from the Lambda backend (500s, exceptions, tracebacks).
#
# Usage:
#   ./show_errors.sh [workspace] [minutes]
#
# workspace defaults to "vereins-app-beta"
# minutes  defaults to 30 (look back 30 minutes)

set -euo pipefail

WORKSPACE="${1:-vereins-app-beta}"
MINUTES="${2:-30}"
REGION="eu-central-1"
LOG_GROUP="/aws/lambda/${WORKSPACE}-lambda_backend"

START_TIME=$(( ($(date +%s) - MINUTES * 60) * 1000 ))

echo ">>> Log group : $LOG_GROUP"
echo ">>> Looking back: ${MINUTES} minutes"
echo ""

aws logs filter-log-events \
  --region "$REGION" \
  --log-group-name "$LOG_GROUP" \
  --start-time "$START_TIME" \
  --filter-pattern '?"ERROR" ?"Error" ?"Exception" ?"Traceback" ?"500" ?"Task timed out"' \
  --query 'events[*].message' \
  --output text \
| tr '\t' '\n'
