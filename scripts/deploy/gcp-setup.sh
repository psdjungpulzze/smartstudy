#!/bin/bash
# =============================================================================
# FunSheep — Google Cloud Platform Setup Script
# =============================================================================
#
# Adapted from ShareWants hosting guide for Elixir/Phoenix + PostgreSQL.
#
# Prerequisites:
#   1. gcloud CLI installed: https://cloud.google.com/sdk/docs/install
#   2. Authenticated: gcloud auth login
#   3. A billing account linked to GCP
#
# Architecture:
#   - Cloud Run (Elixir/Phoenix release in Docker)
#   - Cloud SQL for PostgreSQL 15
#   - Secret Manager (DATABASE_URL, SECRET_KEY_BASE)
#   - Scale-to-zero (0-5 instances)
#
# Usage:
#   ./scripts/deploy/gcp-setup.sh              # Interactive full setup
#   ./scripts/deploy/gcp-setup.sh --step N      # Run specific step
#   ./scripts/deploy/gcp-setup.sh --deploy-only # Just redeploy backend
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these for your project
# ---------------------------------------------------------------------------
PROJECT_ID="funsheep-prod"
PROJECT_NAME="FunSheep"
REGION="us-central1"
DB_INSTANCE="funsheep-db"
DB_NAME="fun_sheep_prod"
DB_USER="funsheep_app"
CLOUD_RUN_SERVICE="funsheep-api"
CLOUD_RUN_MEMORY="512Mi"
CLOUD_RUN_CPU="1"
CLOUD_RUN_MIN_INSTANCES="0"
CLOUD_RUN_MAX_INSTANCES="5"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${GREEN}========================================${NC}"; echo -e "${GREEN}  Step $1: $2${NC}"; echo -e "${GREEN}========================================${NC}\n"; }

# ---------------------------------------------------------------------------
# Helper: generate secure password
# ---------------------------------------------------------------------------
gen_password() {
  openssl rand -base64 32 | tr -d '=/+' | head -c 32
}

# ---------------------------------------------------------------------------
# Deploy-only mode
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--deploy-only" ]]; then
  info "Redeploying $CLOUD_RUN_SERVICE..."
  cd "$(git rev-parse --show-toplevel)"

  CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(connectionName)" 2>/dev/null)

  gcloud run deploy "$CLOUD_RUN_SERVICE" \
    --source=. \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --add-cloudsql-instances="$CONNECTION_NAME" \
    --memory="$CLOUD_RUN_MEMORY" \
    --cpu="$CLOUD_RUN_CPU" \
    --min-instances="$CLOUD_RUN_MIN_INSTANCES" \
    --max-instances="$CLOUD_RUN_MAX_INSTANCES" \
    --set-env-vars="PHX_SERVER=true" \
    --set-env-vars="PHX_HOST=${PHX_HOST:-funsheep.com}" \
    --set-secrets="DATABASE_URL=database-url:latest" \
    --set-secrets="SECRET_KEY_BASE=secret-key-base:latest"

  ok "Deploy complete!"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: GCP Project Setup
# ---------------------------------------------------------------------------
run_step_1() {
  step "1" "GCP Project Setup"

  # Check if project exists
  if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    ok "Project $PROJECT_ID already exists"
  else
    info "Creating project $PROJECT_ID..."
    gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME"
    ok "Project created"
  fi

  gcloud config set project "$PROJECT_ID"

  # Check billing
  BILLING=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || true)
  if [[ -z "$BILLING" ]]; then
    warn "No billing account linked. Available accounts:"
    gcloud billing accounts list
    echo ""
    read -rp "Enter billing account ID to link: " BILLING_ACCOUNT
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
  else
    ok "Billing already linked: $BILLING"
  fi

  # Enable APIs
  info "Enabling required APIs..."
  gcloud services enable \
    run.googleapis.com \
    sqladmin.googleapis.com \
    secretmanager.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com

  gcloud config set run/region "$REGION"
  ok "Project setup complete"
}

# ---------------------------------------------------------------------------
# Step 2: Cloud SQL (PostgreSQL)
# ---------------------------------------------------------------------------
run_step_2() {
  step "2" "Cloud SQL PostgreSQL Setup"

  DB_ROOT_PASSWORD=$(gen_password)

  if gcloud sql instances describe "$DB_INSTANCE" &>/dev/null; then
    ok "Cloud SQL instance $DB_INSTANCE already exists"
  else
    # Tier: db-custom-1-3840 (1 dedicated vCPU + 3.84GB RAM, ~\$48/mo).
    # Shared-core tiers (db-f1-micro, db-g1-small) saturate under Oban's
    # Peer/Notifier + OCR worker DB traffic once worker concurrency crosses
    # ~4 slots, producing cascading 5s GenServer timeouts that halve OCR
    # throughput. The dedicated-core tier removes that ceiling.
    info "Creating PostgreSQL 15 instance (db-custom-1-3840, ~\$48/mo)..."
    gcloud sql instances create "$DB_INSTANCE" \
      --database-version=POSTGRES_15 \
      --tier=db-custom-1-3840 \
      --region="$REGION" \
      --storage-type=SSD \
      --storage-size=10GB \
      --storage-auto-increase \
      --backup-start-time=03:00 \
      --availability-type=zonal \
      --root-password="$DB_ROOT_PASSWORD"

    ok "Instance created. Root password: $DB_ROOT_PASSWORD"
    warn "Save this root password securely! It won't be shown again."
  fi

  # Create database
  if gcloud sql databases describe "$DB_NAME" --instance="$DB_INSTANCE" &>/dev/null; then
    ok "Database $DB_NAME already exists"
  else
    info "Creating database $DB_NAME..."
    gcloud sql databases create "$DB_NAME" --instance="$DB_INSTANCE"
    ok "Database created"
  fi

  # Create app user
  DB_APP_PASSWORD=$(gen_password)
  info "Creating database user $DB_USER..."
  gcloud sql users create "$DB_USER" \
    --instance="$DB_INSTANCE" \
    --password="$DB_APP_PASSWORD" 2>/dev/null || warn "User may already exist"

  CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(connectionName)")
  ok "Connection name: $CONNECTION_NAME"
  echo ""
  info "DATABASE_URL for Cloud Run (via Unix socket):"
  echo "  ecto://${DB_USER}:${DB_APP_PASSWORD}@/${DB_NAME}?socket=/cloudsql/${CONNECTION_NAME}/.s.PGSQL.5432"
  echo ""

  # Save for later steps
  export DB_APP_PASSWORD
  export CONNECTION_NAME
}

# ---------------------------------------------------------------------------
# Step 3: Secret Manager
# ---------------------------------------------------------------------------
run_step_3() {
  step "3" "Secret Manager Setup"

  CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(connectionName)")
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

  # Get or set DB password
  if [[ -z "${DB_APP_PASSWORD:-}" ]]; then
    echo ""
    read -rsp "Enter the database password for $DB_USER: " DB_APP_PASSWORD
    echo ""
  fi

  # Build DATABASE_URL for Cloud Run (Unix socket for Cloud SQL)
  DATABASE_URL="ecto://${DB_USER}:${DB_APP_PASSWORD}@/${DB_NAME}?socket=/cloudsql/${CONNECTION_NAME}/.s.PGSQL.5432"

  # Generate SECRET_KEY_BASE
  SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

  # Create secrets
  for secret_name in database-url secret-key-base; do
    if gcloud secrets describe "$secret_name" &>/dev/null; then
      ok "Secret $secret_name already exists"
    else
      case "$secret_name" in
        database-url)
          echo -n "$DATABASE_URL" | gcloud secrets create "$secret_name" \
            --data-file=- --replication-policy=automatic
          ;;
        secret-key-base)
          echo -n "$SECRET_KEY_BASE" | gcloud secrets create "$secret_name" \
            --data-file=- --replication-policy=automatic
          ;;
      esac
      ok "Secret $secret_name created"
    fi

    # Grant Cloud Run access
    gcloud secrets add-iam-policy-binding "$secret_name" \
      --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
      --role="roles/secretmanager.secretAccessor" \
      --quiet
  done

  ok "Secrets configured"
}

# ---------------------------------------------------------------------------
# Step 4: Deploy to Cloud Run
# ---------------------------------------------------------------------------
run_step_4() {
  step "4" "Deploy to Cloud Run"

  cd "$(git rev-parse --show-toplevel)"

  CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(connectionName)")

  info "Deploying $CLOUD_RUN_SERVICE to Cloud Run..."
  info "This will build the Docker image via Cloud Build and deploy it."
  echo ""

  gcloud run deploy "$CLOUD_RUN_SERVICE" \
    --source=. \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --add-cloudsql-instances="$CONNECTION_NAME" \
    --memory="$CLOUD_RUN_MEMORY" \
    --cpu="$CLOUD_RUN_CPU" \
    --min-instances="$CLOUD_RUN_MIN_INSTANCES" \
    --max-instances="$CLOUD_RUN_MAX_INSTANCES" \
    --set-env-vars="PHX_SERVER=true" \
    --set-env-vars="PHX_HOST=${PHX_HOST:-funsheep.com}" \
    --set-secrets="DATABASE_URL=database-url:latest" \
    --set-secrets="SECRET_KEY_BASE=secret-key-base:latest"

  SERVICE_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$REGION" --format="value(status.url)")
  ok "Deployed! Service URL: $SERVICE_URL"
}

# ---------------------------------------------------------------------------
# Step 5: Run Migrations
# ---------------------------------------------------------------------------
run_step_5() {
  step "5" "Run Database Migrations"

  info "Migrations run automatically on Cloud Run container startup."
  info "To run manually, use Cloud Run Jobs or exec into the container:"
  echo ""
  echo "  # Option A: Run as a Cloud Run Job"
  echo "  gcloud run jobs create funsheep-migrate \\"
  echo "    --image=\$(gcloud run services describe $CLOUD_RUN_SERVICE --region=$REGION --format='value(spec.template.spec.containers[0].image)') \\"
  echo "    --region=$REGION \\"
  echo "    --set-secrets=DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest \\"
  echo "    --add-cloudsql-instances=\$(gcloud sql instances describe $DB_INSTANCE --format='value(connectionName)') \\"
  echo "    --command=bin/migrate"
  echo ""
  echo "  # Option B: Use cloud-sql-proxy locally"
  echo "  cloud-sql-proxy $PROJECT_ID:$REGION:$DB_INSTANCE --port=5433 &"
  echo "  DATABASE_URL=ecto://$DB_USER:PASSWORD@localhost:5433/$DB_NAME mix ecto.migrate"
  echo ""

  read -rp "Would you like to trigger a migration job now? (y/N) " RUN_MIGRATE
  if [[ "${RUN_MIGRATE,,}" == "y" ]]; then
    IMAGE=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$REGION" --format='value(spec.template.spec.containers[0].image)' 2>/dev/null || true)
    if [[ -n "$IMAGE" ]]; then
      CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" --format="value(connectionName)")

      gcloud run jobs create funsheep-migrate \
        --image="$IMAGE" \
        --region="$REGION" \
        --set-secrets="DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest" \
        --add-cloudsql-instances="$CONNECTION_NAME" \
        --command="bin/migrate" \
        --execute-now \
        2>/dev/null || \
      gcloud run jobs update funsheep-migrate \
        --image="$IMAGE" \
        --region="$REGION" \
        --set-secrets="DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest" \
        --add-cloudsql-instances="$CONNECTION_NAME" \
        --command="bin/migrate" \
        --execute-now

      ok "Migration job triggered"
    else
      warn "No Cloud Run service found. Deploy first (Step 4), then run migrations."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Step 6: Verify
# ---------------------------------------------------------------------------
run_step_6() {
  step "6" "Verify Deployment"

  SERVICE_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE" --region="$REGION" --format="value(status.url)" 2>/dev/null || true)

  if [[ -z "$SERVICE_URL" ]]; then
    error "Cloud Run service not found. Run Step 4 first."
    return 1
  fi

  info "Service URL: $SERVICE_URL"
  echo ""

  info "Health check..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    ok "Health check passed (HTTP $HTTP_CODE)"
  else
    warn "Health check returned HTTP $HTTP_CODE (service may still be starting)"
  fi

  echo ""
  info "Useful commands:"
  echo "  # View logs"
  echo "  gcloud run services logs tail $CLOUD_RUN_SERVICE --region=$REGION"
  echo ""
  echo "  # Redeploy after code changes"
  echo "  ./scripts/deploy/gcp-setup.sh --deploy-only"
  echo ""
  echo "  # Check status"
  echo "  gcloud run services describe $CLOUD_RUN_SERVICE --region=$REGION"
  echo ""
  echo "  # Connect to database"
  echo "  cloud-sql-proxy $PROJECT_ID:$REGION:$DB_INSTANCE --port=5433 &"
  echo "  psql -h 127.0.0.1 -p 5433 -U $DB_USER -d $DB_NAME"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo ""
  echo "========================================"
  echo "  FunSheep GCP Hosting Setup"
  echo "  Project: $PROJECT_ID"
  echo "  Region:  $REGION"
  echo "========================================"
  echo ""

  # Check gcloud is installed
  if ! command -v gcloud &>/dev/null; then
    error "gcloud CLI not installed. Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
  fi

  # Check authentication
  if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1 | grep -q "@"; then
    error "Not authenticated. Run: gcloud auth login"
    exit 1
  fi

  ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1)
  ok "Authenticated as: $ACTIVE_ACCOUNT"

  # Run specific step or all
  if [[ "${1:-}" == "--step" ]]; then
    run_step_"${2}"
  else
    run_step_1
    run_step_2
    run_step_3
    run_step_4
    run_step_5
    run_step_6
  fi
}

main "$@"
