#!/bin/bash
# =============================================================================
# FunSheep — Google Cloud Storage Setup
# =============================================================================
#
# Creates the uploads bucket, configures lifecycle rules for cost control,
# creates a dedicated service account for the Cloud Run service, and binds
# least-privilege IAM so the app can read/write objects in the bucket only.
#
# Idempotent — safe to re-run.
#
# Prerequisites:
#   - gcloud CLI authenticated (gcloud auth login)
#   - scripts/deploy/gcp-setup.sh has already run (project + APIs exist)
#
# Usage:
#   ./scripts/deploy/gcs-setup.sh
#
# Output: prints the bucket name + service account email to paste into .env.prod
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT_ID="${GCP_PROJECT_ID:-funsheep-prod}"
REGION="${GCP_REGION:-us-central1}"
BUCKET_NAME="${GCS_BUCKET:-funsheep-uploads-prod}"
STORAGE_SA_NAME="funsheep-storage"
STORAGE_SA_EMAIL="${STORAGE_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-funsheep-api}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "========================================"
echo "  FunSheep GCS Setup"
echo "  Project: $PROJECT_ID"
echo "  Region:  $REGION"
echo "  Bucket:  $BUCKET_NAME"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
if ! command -v gcloud >/dev/null 2>&1; then
  error "gcloud CLI not installed. https://cloud.google.com/sdk/docs/install"
  exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 | grep -q '@'; then
  error "Not authenticated. Run: gcloud auth login"
  exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

# ---------------------------------------------------------------------------
# Enable Cloud Storage API
# ---------------------------------------------------------------------------
info "Enabling storage.googleapis.com and iamcredentials.googleapis.com..."
gcloud services enable storage.googleapis.com iamcredentials.googleapis.com --quiet

# ---------------------------------------------------------------------------
# Create bucket (regional, uniform access, no public-read)
# ---------------------------------------------------------------------------
if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  ok "Bucket gs://${BUCKET_NAME} already exists"
else
  info "Creating bucket gs://${BUCKET_NAME}..."
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
  ok "Bucket created"
fi

# ---------------------------------------------------------------------------
# Lifecycle rules — keep costs low
#   - staging/* older than 7 days: delete (abandoned uploads)
#   - anything in Standard older than 30 days: → Nearline (50% cheaper)
#   - older than 90 days: → Coldline (80% cheaper)
# ---------------------------------------------------------------------------
info "Applying lifecycle rules..."
LIFECYCLE_FILE=$(mktemp)
trap 'rm -f "$LIFECYCLE_FILE"' EXIT
cat > "$LIFECYCLE_FILE" <<'JSON'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 7,
          "matchesPrefix": ["staging/"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {
          "age": 30,
          "matchesStorageClass": ["STANDARD"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {
          "age": 90,
          "matchesStorageClass": ["NEARLINE"]
        }
      }
    ]
  }
}
JSON
gcloud storage buckets update "gs://${BUCKET_NAME}" --lifecycle-file="$LIFECYCLE_FILE"
ok "Lifecycle rules applied"

# ---------------------------------------------------------------------------
# CORS — required for browser-side resumable uploads
#
# The JS client POSTs to /api/uploads/sign (same-origin, no CORS needed),
# then PUTs the file body directly to the GCS session URI returned by that
# endpoint (cross-origin — storage.googleapis.com).  Without CORS the browser
# refuses the preflight OPTIONS request and every upload fails immediately.
#
# Allowed headers cover:
#   content-type       — sent on every PUT
#   content-range      — sent on chunked PUTs (>8 MB files)
#   x-goog-resumable   — GCS-specific header echoed in initiation responses
# ---------------------------------------------------------------------------
info "Configuring CORS for browser-side uploads..."
CORS_FILE=$(mktemp)
# Add CORS file to the cleanup trap alongside LIFECYCLE_FILE
trap 'rm -f "$LIFECYCLE_FILE" "$CORS_FILE"' EXIT

# APP_ORIGIN may be overridden; defaults to the production URL.
APP_ORIGIN="${APP_ORIGIN:-https://funsheep.com}"

cat > "$CORS_FILE" <<JSON
[
  {
    "origin": ["${APP_ORIGIN}"],
    "method": ["PUT", "GET", "OPTIONS"],
    "responseHeader": [
      "Content-Type",
      "Content-Range",
      "Authorization",
      "X-Goog-Resumable"
    ],
    "maxAgeSeconds": 3600
  }
]
JSON
gcloud storage buckets update "gs://${BUCKET_NAME}" --cors-file="$CORS_FILE"
ok "CORS configured for ${APP_ORIGIN}"

# ---------------------------------------------------------------------------
# Service account for the app (least privilege, bucket-scoped)
# ---------------------------------------------------------------------------
if gcloud iam service-accounts describe "$STORAGE_SA_EMAIL" >/dev/null 2>&1; then
  ok "Service account ${STORAGE_SA_EMAIL} already exists"
else
  info "Creating service account ${STORAGE_SA_NAME}..."
  gcloud iam service-accounts create "$STORAGE_SA_NAME" \
    --display-name="FunSheep App — Cloud Storage" \
    --description="Used by Cloud Run service to read/write user uploads"
  ok "Service account created"
fi

# Bind object-level access on this bucket only (not project-wide)
info "Granting objectAdmin on gs://${BUCKET_NAME} to ${STORAGE_SA_EMAIL}..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${STORAGE_SA_EMAIL}" \
  --role="roles/storage.objectAdmin" \
  --quiet >/dev/null
ok "Bucket IAM bound"

# ---------------------------------------------------------------------------
# Grant Cloud Run service secret access + SA impersonation
# (Cloud Run needs to be able to mint tokens for this SA to use it at runtime)
# ---------------------------------------------------------------------------
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# If the Cloud Run service is using the default compute SA, we bind the
# storage SA directly to Cloud Run instead (via --service-account on deploy).
# No extra impersonation needed here — just make sure the Cloud Run deployment
# uses --service-account=${STORAGE_SA_EMAIL}.
info "Cloud Run should be deployed with: --service-account=${STORAGE_SA_EMAIL}"

# ---------------------------------------------------------------------------
# Output for .env.prod
# ---------------------------------------------------------------------------
echo ""
ok "Setup complete!"
echo ""
echo "Add these to your .env.prod:"
echo ""
echo "  GCS_BUCKET=${BUCKET_NAME}"
echo "  GCS_SERVICE_ACCOUNT=${STORAGE_SA_EMAIL}"
echo ""
echo "Verify with:"
echo "  gcloud storage ls gs://${BUCKET_NAME}/"
echo "  gcloud storage buckets describe gs://${BUCKET_NAME} --format='value(lifecycle)'"
