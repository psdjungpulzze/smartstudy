#!/bin/bash
# =============================================================================
# FunSheep — Push to Production
# =============================================================================
# Reads .env.prod, upserts INTERACTOR_CLIENT_SECRET into Secret Manager,
# and deploys the Cloud Run service with all required env vars + secrets.
#
# Guardrails:
#   - Must run from clean `main` branch, in sync with origin
#   - Confirmation gate (type DEPLOY) unless --yes
#   - Post-deploy health check; auto-rolls back traffic on failure
#
# Usage:
#   ./scripts/deploy/deploy-prod.sh                # interactive, prompts
#   ./scripts/deploy/deploy-prod.sh --yes          # non-interactive
#   ./scripts/deploy/deploy-prod.sh --env-file PATH
# =============================================================================

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# --- Colors --------------------------------------------------------------
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; NC=""
fi
ok()   { echo "${GREEN}[ok]${NC}   $*"; }
info() { echo "[info] $*"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*" >&2; exit 1; }

# --- Parse args ----------------------------------------------------------
ENV_FILE="$ROOT/.env.prod"
AUTO_YES=0
SKIP_GIT_CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)        AUTO_YES=1 ;;
    --env-file)      shift; ENV_FILE="$1" ;;
    --skip-git-check) SKIP_GIT_CHECK=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) fail "Unknown flag: $1" ;;
    *)  ENV_FILE="$1" ;;
  esac
  shift
done

[ -f "$ENV_FILE" ] || fail "$ENV_FILE not found. Copy .env.prod.example to .env.prod and fill in values."

# --- Guardrail: git state -----------------------------------------------
if [ "$SKIP_GIT_CHECK" -ne 1 ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [ "$BRANCH" != "main" ]; then
    fail "Must deploy from 'main' (currently on: $BRANCH). Use --skip-git-check to override."
  fi

  # --ignore-submodules=dirty: treat nested-submodule working-tree dirt as
  # clean, since interactor-workspace/ is excluded by .gcloudignore and not
  # part of the Cloud Build upload. Changes to the submodule pointer itself
  # are still caught (those show up without the "dirty" marker).
  if [ -n "$(git status --porcelain --ignore-submodules=dirty)" ]; then
    echo "--- uncommitted changes ---" >&2
    git status --short --ignore-submodules=dirty >&2
    fail "Working tree not clean. Commit/stash first, or use --skip-git-check."
  fi

  info "Fetching origin/main..."
  git fetch --quiet origin main
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse origin/main)
  BASE=$(git merge-base HEAD origin/main)

  if [ "$LOCAL" = "$REMOTE" ]; then
    :  # up to date
  elif [ "$LOCAL" = "$BASE" ]; then
    fail "Local 'main' is behind origin/main. Run 'git pull' first."
  elif [ "$REMOTE" = "$BASE" ]; then
    fail "Local 'main' has unpushed commits. Push before deploying so prod matches the remote record."
  else
    fail "Local 'main' has diverged from origin/main. Reconcile before deploying."
  fi
  ok "Git: on main, clean, in sync with origin ($(git rev-parse --short HEAD))"
else
  warn "Git state check skipped (--skip-git-check)"
fi

# --- Preflight: validate env file ---------------------------------------
# Canonical check lives in lib/mix/tasks/funsheep.deploy.preflight.ex so CI
# and local deploy share one source of truth for required variables.
info "Preflight: validating $ENV_FILE..."
mix funsheep.deploy.preflight --env-file "$ENV_FILE" \
  || fail "Preflight failed — fix the issues above before deploying."

# --- Load env ------------------------------------------------------------
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# --- gcloud checks -------------------------------------------------------
command -v gcloud >/dev/null 2>&1 || fail "gcloud CLI not installed."

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 | grep -q '@' \
  || fail "Not authenticated. Run: gcloud auth login"

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)
gcloud config set project "$GCP_PROJECT_ID" >/dev/null

# --- Guardrail: confirmation --------------------------------------------
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
COMMIT_MSG=$(git log -1 --pretty=%s 2>/dev/null || echo "?")

echo ""
echo "${YELLOW}====================================================${NC}"
echo "${YELLOW} PRODUCTION DEPLOY${NC}"
echo "${YELLOW}====================================================${NC}"
echo "  Account:  $ACTIVE_ACCOUNT"
echo "  Project:  $GCP_PROJECT_ID"
echo "  Service:  $CLOUD_RUN_SERVICE ($GCP_REGION)"
echo "  Public:   https://$PHX_HOST"
echo "  Commit:   $COMMIT_SHORT — $COMMIT_MSG"
echo ""

if [ "$AUTO_YES" -ne 1 ]; then
  if [ ! -t 0 ]; then
    fail "Non-interactive shell detected. Pass --yes to confirm deploy."
  fi
  read -rp "Type 'DEPLOY' to continue (anything else aborts): " CONFIRM
  [ "$CONFIRM" = "DEPLOY" ] || fail "Aborted."
else
  info "--yes supplied; skipping interactive confirmation"
fi

# --- Capture previous revision (for rollback) ---------------------------
PREV_REVISION=$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --region="$GCP_REGION" \
  --format='value(status.latestReadyRevisionName)' 2>/dev/null || echo "")
info "Previous revision (rollback target): ${PREV_REVISION:-<none — first deploy>}"

# --- Secret Manager: upsert interactor-client-secret --------------------
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')
# Cloud Run service runs as GCS_SERVICE_ACCOUNT (set via --service-account
# below), so that SA — not the default compute SA — must have secret access.
CLOUD_RUN_SA="$GCS_SERVICE_ACCOUNT"

upsert_secret() {
  local name="$1"
  local value="$2"

  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    current=$(gcloud secrets versions access latest --secret="$name" 2>/dev/null || echo "")
    if [ "$current" = "$value" ]; then
      ok "Secret $name unchanged"
    else
      ok "Adding new version to secret $name"
      printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
    fi
  else
    ok "Creating secret $name"
    printf '%s' "$value" | gcloud secrets create "$name" \
      --data-file=- --replication-policy=automatic >/dev/null
  fi

  gcloud secrets add-iam-policy-binding "$name" \
    --member="serviceAccount:$CLOUD_RUN_SA" \
    --role='roles/secretmanager.secretAccessor' \
    --quiet >/dev/null
}

upsert_secret interactor-client-secret "$INTERACTOR_CLIENT_SECRET"
upsert_secret google-vision-api-key "$GOOGLE_VISION_API_KEY"

for required_secret in database-url secret-key-base; do
  gcloud secrets describe "$required_secret" >/dev/null 2>&1 \
    || fail "Secret '$required_secret' missing. Run scripts/deploy/gcp-setup.sh to bootstrap."

  # Ensure the Cloud Run service account (GCS_SERVICE_ACCOUNT) can read these,
  # since it replaces the default compute SA originally bound in gcp-setup.sh.
  gcloud secrets add-iam-policy-binding "$required_secret" \
    --member="serviceAccount:$CLOUD_RUN_SA" \
    --role='roles/secretmanager.secretAccessor' \
    --quiet >/dev/null
done

# Cloud Run needs permission to run the container as GCS_SERVICE_ACCOUNT.
# The deploying user must have iam.serviceAccounts.actAs on that SA; for
# Cloud Build source deploys the Cloud Build SA also needs it.
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
gcloud iam service-accounts add-iam-policy-binding "$GCS_SERVICE_ACCOUNT" \
  --member="serviceAccount:$CLOUD_BUILD_SA" \
  --role='roles/iam.serviceAccountUser' \
  --quiet >/dev/null 2>&1 || true

# --- Cloud SQL connection -----------------------------------------------
CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format='value(connectionName)')
ok "Cloud SQL: $CONNECTION_NAME"

# --- Build env-vars file (YAML) -----------------------------------------
ENV_VARS_FILE=$(mktemp)
trap 'rm -f "$ENV_VARS_FILE"' EXIT

cat > "$ENV_VARS_FILE" <<EOF
PHX_SERVER: "true"
PHX_HOST: "$PHX_HOST"
DB_SOCKET_DIR: "/cloudsql/$CONNECTION_NAME"
INTERACTOR_URL: "$INTERACTOR_URL"
INTERACTOR_CORE_URL: "$INTERACTOR_CORE_URL"
INTERACTOR_UKB_URL: "$INTERACTOR_UKB_URL"
INTERACTOR_UDB_URL: "$INTERACTOR_UDB_URL"
INTERACTOR_ORG_NAME: "$INTERACTOR_ORG_NAME"
INTERACTOR_CLIENT_ID: "$INTERACTOR_CLIENT_ID"
GCS_BUCKET: "$GCS_BUCKET"
EOF

# --- Deploy --------------------------------------------------------------
info "Deploying $CLOUD_RUN_SERVICE to $GCP_REGION..."

gcloud run deploy "$CLOUD_RUN_SERVICE" \
  --source=. \
  --region="$GCP_REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --service-account="$GCS_SERVICE_ACCOUNT" \
  --add-cloudsql-instances="$CONNECTION_NAME" \
  --env-vars-file="$ENV_VARS_FILE" \
  --set-secrets="DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest,INTERACTOR_CLIENT_SECRET=interactor-client-secret:latest,GOOGLE_VISION_API_KEY=google-vision-api-key:latest"

NEW_REVISION=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$GCP_REGION" --format='value(status.latestReadyRevisionName)')
SERVICE_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$GCP_REGION" --format='value(status.url)')
ok "Deployed revision: $NEW_REVISION"
ok "Cloud Run URL:     $SERVICE_URL"

# --- Post-deploy smoke test + auto-rollback -----------------------------
rollback() {
  local reason="$1"
  warn "Smoke test FAILED: $reason"
  if [ -n "$PREV_REVISION" ] && [ "$PREV_REVISION" != "$NEW_REVISION" ]; then
    warn "Rolling traffic back to $PREV_REVISION..."
    gcloud run services update-traffic "$CLOUD_RUN_SERVICE" \
      --region="$GCP_REGION" \
      --to-revisions="$PREV_REVISION=100" >/dev/null
    fail "Rollback complete. Revision $NEW_REVISION kept (zero traffic) for inspection."
  else
    fail "No previous revision to roll back to. Revision $NEW_REVISION is live but failing."
  fi
}

info "Smoke test: GET $SERVICE_URL/health"
sleep 3  # brief grace period for the new revision to settle
HEALTH_CODE=$(curl -sS -o /tmp/fs-deploy-health.txt -w '%{http_code}' --max-time 30 "$SERVICE_URL/health" || echo "000")
if [ "$HEALTH_CODE" != "200" ]; then
  rollback "Cloud Run /health returned HTTP $HEALTH_CODE"
fi
ok "Cloud Run /health: 200"

info "Smoke test: GET https://$PHX_HOST/health"
PUBLIC_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 "https://$PHX_HOST/health" || echo "000")
if [ "$PUBLIC_CODE" != "200" ]; then
  warn "Public https://$PHX_HOST/health returned HTTP $PUBLIC_CODE — Cloud Run revision is healthy, so NOT rolling back."
  warn "Check domain mapping / DNS / cert: gcloud beta run domain-mappings describe --domain=$PHX_HOST --region=$GCP_REGION"
else
  ok "Public /health: 200"
fi

# --- Promote worker service in lockstep ---------------------------------
# funsheep-worker drains the Oban queue using the same image as funsheep-api
# but with RUN_OBAN_WORKERS=true. Without this step, the worker would keep
# running stale code (and missing newly added secrets) after every deploy —
# which is exactly how production silently failed for ~5 hours after the
# Vision API key fix shipped to the api but not the worker.
WORKER_SERVICE="funsheep-worker"
if gcloud run services describe "$WORKER_SERVICE" --region="$GCP_REGION" >/dev/null 2>&1; then
  NEW_IMAGE=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$GCP_REGION" \
    --format='value(spec.template.spec.containers[0].image)')

  info "Promoting $WORKER_SERVICE to image $NEW_IMAGE"
  # POOL_SIZE must cover the sum of Oban queue concurrencies in runtime.exs
  # (default=10 + ocr=15 + ai=5 + ingest=1 = 31) plus a small headroom for
  # Lifeline / Pruner plugins. Setting it to 35 leaves 4 slots of slack.
  gcloud run services update "$WORKER_SERVICE" \
    --region="$GCP_REGION" \
    --image="$NEW_IMAGE" \
    --update-env-vars="POOL_SIZE=35" \
    --update-secrets="DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest,INTERACTOR_CLIENT_SECRET=interactor-client-secret:latest,GOOGLE_VISION_API_KEY=google-vision-api-key:latest" \
    --quiet >/dev/null

  WORKER_REVISION=$(gcloud run services describe "$WORKER_SERVICE" --region="$GCP_REGION" \
    --format='value(status.latestReadyRevisionName)')
  ok "Worker promoted: $WORKER_REVISION"
else
  warn "$WORKER_SERVICE service not found in $GCP_REGION — Oban jobs will not drain. Create it before next deploy."
fi

echo ""
echo "${GREEN}====================================================${NC}"
echo "${GREEN} Deploy succeeded${NC}"
echo "${GREEN}====================================================${NC}"
echo "  API Revision:    $NEW_REVISION"
echo "  Worker Revision: ${WORKER_REVISION:-<not deployed>}"
echo "  URL:             https://$PHX_HOST"
echo ""
echo "  Tail logs:  gcloud run services logs tail $CLOUD_RUN_SERVICE --region=$GCP_REGION"
echo "  Tail worker: gcloud run services logs tail $WORKER_SERVICE --region=$GCP_REGION"
echo "  Rollback:   gcloud run services update-traffic $CLOUD_RUN_SERVICE --region=$GCP_REGION --to-revisions=${PREV_REVISION:-PREV}=100"
