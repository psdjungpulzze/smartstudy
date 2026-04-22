#!/bin/bash
# =============================================================================
# FunSheep — Ingest NCES Common Core of Data into the prod database
# =============================================================================
# Creates (or updates) a Cloud Run Job that runs
#   bin/fun_sheep eval 'FunSheep.Release.ingest_us_schools()'
# against the currently-deployed funsheep-api image, pointed at the same
# Cloud SQL + secrets as the API service.
#
# Safe to re-run. Ingestion upserts on (source, source_id), so a second
# invocation after a new NCES annual file is published updates existing
# rows and inserts new ones. The first run takes 5–15 min; the second and
# later ones hit the GCS cache tier and complete in a couple of minutes.
#
# Usage:
#   ./scripts/deploy/ingest-nces.sh                # creates job + executes
#   ./scripts/deploy/ingest-nces.sh --job-only     # just (re)create, don't run
#   ./scripts/deploy/ingest-nces.sh --env-file PATH
# =============================================================================

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; NC=""
fi
ok()   { echo "${GREEN}[ok]${NC}   $*"; }
info() { echo "[info] $*"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
fail() { echo "${RED}[fail]${NC} $*" >&2; exit 1; }

ENV_FILE="$ROOT/.env.prod"
JOB_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) shift; ENV_FILE="$1" ;;
    --job-only) JOB_ONLY=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "Unknown flag: $1" ;;
  esac
  shift
done

[ -f "$ENV_FILE" ] || fail "$ENV_FILE not found."

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

command -v gcloud >/dev/null 2>&1 || fail "gcloud CLI not installed."

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null \
  | head -1 | grep -q '@' || fail "Not authenticated. Run: gcloud auth login"

gcloud config set project "$GCP_PROJECT_ID" >/dev/null

JOB_NAME="funsheep-ingest-nces"

# Reuse the currently-deployed api image — that way the job's code is
# always in sync with whatever revision of the release is serving traffic.
IMAGE=$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --region="$GCP_REGION" \
  --format='value(spec.template.spec.containers[0].image)' 2>/dev/null) \
  || fail "Could not read $CLOUD_RUN_SERVICE image. Deploy the service first."

[ -n "$IMAGE" ] || fail "No image returned for $CLOUD_RUN_SERVICE."
ok "Using image: $IMAGE"

CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format='value(connectionName)')

# Mirror the env vars and secrets the api service uses so the release task
# connects to the same DB, GCS bucket, and Interactor environment.
ENV_VARS="DB_SOCKET_DIR=/cloudsql/$CONNECTION_NAME,GCS_BUCKET=$GCS_BUCKET,INTERACTOR_URL=$INTERACTOR_URL,INTERACTOR_ORG_NAME=$INTERACTOR_ORG_NAME,INTERACTOR_CLIENT_ID=$INTERACTOR_CLIENT_ID,PHX_HOST=$PHX_HOST"
SECRETS="DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest,INTERACTOR_CLIENT_SECRET=interactor-client-secret:latest,GOOGLE_VISION_API_KEY=google-vision-api-key:latest,SMTP_PASSWORD=smtp-password:latest"

if gcloud run jobs describe "$JOB_NAME" --region="$GCP_REGION" >/dev/null 2>&1; then
  info "Updating existing job $JOB_NAME to latest image..."
  gcloud run jobs update "$JOB_NAME" \
    --region="$GCP_REGION" \
    --image="$IMAGE" \
    --service-account="$GCS_SERVICE_ACCOUNT" \
    --set-cloudsql-instances="$CONNECTION_NAME" \
    --set-env-vars="$ENV_VARS" \
    --set-secrets="$SECRETS" \
    --command="bin/fun_sheep" \
    --args="eval,FunSheep.Release.ingest_us_schools()" \
    --task-timeout=3600 \
    --memory=2Gi \
    --quiet >/dev/null
else
  info "Creating job $JOB_NAME..."
  gcloud run jobs create "$JOB_NAME" \
    --region="$GCP_REGION" \
    --image="$IMAGE" \
    --service-account="$GCS_SERVICE_ACCOUNT" \
    --set-cloudsql-instances="$CONNECTION_NAME" \
    --set-env-vars="$ENV_VARS" \
    --set-secrets="$SECRETS" \
    --command="bin/fun_sheep" \
    --args="eval,FunSheep.Release.ingest_us_schools()" \
    --task-timeout=3600 \
    --memory=2Gi \
    --quiet >/dev/null
fi
ok "Job $JOB_NAME ready"

if [ "$JOB_ONLY" -eq 1 ]; then
  info "--job-only: not executing. Run:"
  info "  gcloud run jobs execute $JOB_NAME --region=$GCP_REGION --wait"
  exit 0
fi

info "Executing $JOB_NAME (streaming until completion, ~5–15 min)..."
gcloud run jobs execute "$JOB_NAME" --region="$GCP_REGION" --wait
ok "Ingestion complete. Verify with: gcloud sql … or SELECT count(*) FROM schools;"
