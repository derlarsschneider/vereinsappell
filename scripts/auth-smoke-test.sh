#!/usr/bin/env bash
# Smoke test for API authorization: verifies that unknown members are rejected
# and, optionally, that a plain member cannot list all clubs.
#
# Usage:
#   ./auth-smoke-test.sh <applicationId> [memberId-of-plain-member] [stage]
#
# applicationId  a real club applicationId (e.g. from an invite link)
# memberId       optional: memberId of a plain member (no admin/super admin) of that club
# stage          optional: "prod" (default, $default stage) or "dev"
#
# Examples:
#   ./auth-smoke-test.sh 1234-abcd
#   ./auth-smoke-test.sh 1234-abcd 1234-abcd1700000000000
#   ./auth-smoke-test.sh 1234-abcd "" dev
#
# Exit code: 0 if all checks pass, 1 otherwise.

set -euo pipefail

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
  echo "Usage: $0 <applicationId> [memberId-of-plain-member] [stage]" >&2
  exit 1
fi

APP_ID="$1"
MEMBER_ID="${2:-}"
STAGE="${3:-prod}"
REGION="eu-central-1"
API_NAME="vereins-app-beta-api"

API_ID=$(aws apigatewayv2 get-apis --region "$REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" --output text)
if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  echo "API '${API_NAME}' not found in ${REGION}" >&2
  exit 1
fi

BASE="https://${API_ID}.execute-api.${REGION}.amazonaws.com"
if [ "$STAGE" = "dev" ]; then
  BASE="${BASE}/dev"
fi
echo "API: $BASE"
echo

FAILED=0

# check <description> <expected status> <curl args...>
check() {
  local description="$1" expected="$2"
  shift 2
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" "$@")
  if [ "$status" = "$expected" ]; then
    echo "✅ ${description}: ${status}"
  else
    echo "❌ ${description}: ${status} (expected ${expected})"
    FAILED=1
  fi
}

# $RANDOM avoids hitting the authorizer's 5-minute result cache.
check "real applicationId + unknown memberId" 403 \
  -H "applicationId: ${APP_ID}" -H "memberId: unknown-${RANDOM}" \
  "${BASE}/marschbefehl"

check "unknown applicationId + unknown memberId" 403 \
  -H "applicationId: unknown-${RANDOM}" -H "memberId: unknown-${RANDOM}" \
  "${BASE}/marschbefehl"

check "no identity headers" 401 \
  "${BASE}/marschbefehl"

if [ -n "$MEMBER_ID" ]; then
  check "plain member lists all clubs (GET /customers)" 403 \
    -H "applicationId: ${APP_ID}" -H "memberId: ${MEMBER_ID}" \
    "${BASE}/customers"

  check "plain member reads monitoring (GET /monitoring/stats)" 403 \
    -H "applicationId: ${APP_ID}" -H "memberId: ${MEMBER_ID}" \
    "${BASE}/monitoring/stats"

  # Empty body on purpose: if the gate were missing, the handler fails (500)
  # instead of actually creating a club.
  check "plain member creates a club (POST /customers)" 403 \
    -H "applicationId: ${APP_ID}" -H "memberId: ${MEMBER_ID}" \
    -H "Content-Type: application/json" -X POST -d '{}' \
    "${BASE}/customers"
else
  echo "ℹ️  No plain memberId given — skipping role checks."
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed."
else
  echo "Some checks FAILED."
fi
exit "$FAILED"
