#!/bin/bash
# =============================================================================
# FunSheep — Pre-Deploy Interactor Verification
# =============================================================================
# Reads .env.prod and verifies the Interactor configuration without touching
# GCP or Cloud Build. Runs in ~2 seconds.
#
# Checks:
#   1. Required Interactor env vars are populated (no XXXX placeholders)
#   2. /oauth/jwks is publicly reachable on INTERACTOR_URL
#   3. OAuth client_credentials grant returns a token
#   4. /api/v1/agents/assistants responds with all 5 required assistants
#
# Usage:
#   ./scripts/deploy/verify-interactor.sh
#   ./scripts/deploy/verify-interactor.sh path/to/.env.prod
# =============================================================================

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="${1:-$ROOT/.env.prod}"

REQUIRED_ASSISTANTS=(course_discovery web_search question_gen question_extract question_quality_reviewer question_skill_tagger)

# --- Colors ---------------------------------------------------------------
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; NC=""
fi
ok()   { echo "${GREEN}[ok]${NC}   $*"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*" >&2; exit 1; }

# --- Dependencies ---------------------------------------------------------
command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v jq   >/dev/null 2>&1 || fail "jq not found (install: apt install jq / brew install jq)"

# --- Load .env.prod -------------------------------------------------------
[ -f "$ENV_FILE" ] || fail "$ENV_FILE not found. Copy .env.prod.example and fill in values."

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

REQUIRED=(INTERACTOR_URL INTERACTOR_CORE_URL INTERACTOR_CLIENT_ID INTERACTOR_CLIENT_SECRET)
for v in "${REQUIRED[@]}"; do
  val="${!v:-}"
  if [ -z "$val" ]; then
    fail "$v is empty in $ENV_FILE"
  fi
  if [[ "$val" == *XXXX* ]]; then
    fail "$v still contains placeholder (XXXX) in $ENV_FILE"
  fi
done

ok "Env vars present in $ENV_FILE"

# --- 1. OIDC discovery → JWKS --------------------------------------------
DISCOVERY_URL="${INTERACTOR_URL%/}/.well-known/openid-configuration"
echo "[step] OIDC discovery: $DISCOVERY_URL"

DISC_STATUS=$(curl -sS -o /tmp/fs-disc.json -w '%{http_code}' "$DISCOVERY_URL" || echo "000")
if [ "$DISC_STATUS" != "200" ]; then
  # Fall back to conventional JWKS path if discovery isn't served
  warn "OIDC discovery returned HTTP $DISC_STATUS — falling back to /.well-known/jwks.json"
  JWKS_URL="${INTERACTOR_URL%/}/.well-known/jwks.json"
  TOKEN_URL="${INTERACTOR_URL%/}/oauth/token"
else
  JWKS_URL=$(jq -r '.jwks_uri // empty' /tmp/fs-disc.json)
  TOKEN_URL=$(jq -r '.token_endpoint // empty' /tmp/fs-disc.json)
  [ -n "$JWKS_URL" ]  || fail "OIDC discovery missing jwks_uri"
  [ -n "$TOKEN_URL" ] || fail "OIDC discovery missing token_endpoint"
fi

echo "[step] Checking JWKS: $JWKS_URL"
JWKS_STATUS=$(curl -sS -o /tmp/fs-jwks.json -w '%{http_code}' "$JWKS_URL" || echo "000")
if [ "$JWKS_STATUS" != "200" ]; then
  fail "JWKS endpoint returned HTTP $JWKS_STATUS (expected 200)"
fi
if ! jq -e '.keys | length > 0' /tmp/fs-jwks.json >/dev/null 2>&1; then
  fail "JWKS response is missing .keys array or it's empty"
fi
ok "JWKS reachable with $(jq -r '.keys | length' /tmp/fs-jwks.json) key(s)"

# --- 2. OAuth client_credentials grant -----------------------------------
echo "[step] Fetching access token: $TOKEN_URL"

TOKEN_RESP=$(curl -sS -o /tmp/fs-token.json -w '%{http_code}' \
  -X POST "$TOKEN_URL" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$INTERACTOR_CLIENT_ID" \
  --data-urlencode "client_secret=$INTERACTOR_CLIENT_SECRET" || echo "000")

if [ "$TOKEN_RESP" != "200" ]; then
  echo "--- response body ---" >&2
  cat /tmp/fs-token.json >&2 || true
  echo >&2
  fail "Token endpoint returned HTTP $TOKEN_RESP (expected 200). Check client_id/secret."
fi

ACCESS_TOKEN=$(jq -r '.access_token // empty' /tmp/fs-token.json)
EXPIRES_IN=$(jq -r '.expires_in // "?"' /tmp/fs-token.json)

if [ -z "$ACCESS_TOKEN" ]; then
  fail "Token response did not include access_token"
fi
ok "Got access_token (expires_in=${EXPIRES_IN}s)"

# --- 3. List assistants ---------------------------------------------------
ASSISTANTS_URL="${INTERACTOR_CORE_URL%/}/api/v1/agents/assistants"
echo "[step] Listing assistants: $ASSISTANTS_URL"

AS_STATUS=$(curl -sS -o /tmp/fs-assistants.json -w '%{http_code}' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$ASSISTANTS_URL" || echo "000")

if [ "$AS_STATUS" != "200" ]; then
  echo "--- response body ---" >&2
  cat /tmp/fs-assistants.json >&2 || true
  echo >&2
  fail "Assistants endpoint returned HTTP $AS_STATUS (expected 200)"
fi

AVAILABLE=$(jq -r '.data[].name' /tmp/fs-assistants.json 2>/dev/null || true)
if [ -z "$AVAILABLE" ]; then
  fail "Assistants response had no .data[].name entries"
fi

echo "[info] Assistants found on Interactor:"
echo "$AVAILABLE" | sed 's/^/         - /'

MISSING=()
for want in "${REQUIRED_ASSISTANTS[@]}"; do
  if ! grep -Fxq "$want" <<<"$AVAILABLE"; then
    MISSING+=("$want")
  fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
  echo "${RED}[fail]${NC} Missing required assistants: ${MISSING[*]}" >&2
  echo "       Register them on the prod Interactor before deploying." >&2
  exit 1
fi
ok "All ${#REQUIRED_ASSISTANTS[@]} required assistants present"

# --- Summary --------------------------------------------------------------
echo ""
echo "${GREEN}================================================${NC}"
echo "${GREEN} Interactor prod config looks good — safe to deploy.${NC}"
echo "${GREEN}================================================${NC}"
echo "Next: ./scripts/deploy/deploy-prod.sh"
