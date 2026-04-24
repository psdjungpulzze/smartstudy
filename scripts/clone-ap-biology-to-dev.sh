#!/usr/bin/env bash
# Clone the AP Biology course (d44628ca-6579-48da-a83b-466e12b1c19b) from
# prod into local dev DB. Safe to re-run; drops the specific course on
# dev first to avoid duplicate-key.
#
# Requires:
#   - Cloud SQL proxy running on 127.0.0.1:5433 (prod)
#   - Local Postgres on 127.0.0.1:5450 (dev)
#   - gcloud auth
#
# Usage:
#   ./scripts/clone-ap-biology-to-dev.sh

set -euo pipefail

COURSE_ID='d44628ca-6579-48da-a83b-466e12b1c19b'
TMP=/tmp/fs-clone
mkdir -p "$TMP"

# --- prod creds ---
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
PROD_URL=$(gcloud secrets versions access latest --secret="database-url" --project=funsheep-prod 2>/dev/null | sed 's#^ecto://##')
PROD_PASS=$(echo "$PROD_URL" | sed -E 's#^[^:]+:([^@]+)@.*#\1#')

prod() {
  PGPASSWORD="$PROD_PASS" psql -h 127.0.0.1 -p 5433 -U funsheep_app -d fun_sheep_prod "$@"
}

dev() {
  PGPASSWORD=postgres psql -h 127.0.0.1 -p 5450 -U postgres -d fun_sheep_dev "$@"
}

echo "==> Verifying prod proxy on 127.0.0.1:5433..."
prod -tAc "SELECT 1" >/dev/null

echo "==> Verifying dev DB on 127.0.0.1:5450..."
dev -tAc "SELECT 1" >/dev/null

echo "==> Exporting course $COURSE_ID from prod..."

# Columns that reference objects we don't clone get NULLed during export.
# school_id / created_by_id / textbook_id / pending_toc_* / source_material_id
# all point to data we're not bringing over.
prod -c "\COPY (
  SELECT
    id, name, subject, grade,
    NULL::uuid AS school_id,
    description, metadata,
    NULL::uuid AS created_by_id,
    inserted_at, updated_at,
    'ready' AS processing_status,
    processing_step, processing_error,
    ocr_completed_count, ocr_total_count,
    NULL::uuid AS textbook_id,
    custom_textbook_name, external_provider, external_id, external_synced_at,
    NULL::uuid AS pending_toc_id,
    NULL::uuid AS pending_toc_proposed_by_id,
    pending_toc_proposed_at
  FROM courses WHERE id = '$COURSE_ID'
) TO '$TMP/courses.csv' WITH (FORMAT csv, NULL '')"

prod -c "\COPY (
  SELECT id, course_id, name, position, inserted_at, updated_at, orphaned_at
  FROM chapters WHERE course_id = '$COURSE_ID'
) TO '$TMP/chapters.csv' WITH (FORMAT csv, NULL '')"

prod -c "\COPY (
  SELECT s.* FROM sections s JOIN chapters c ON c.id = s.chapter_id
  WHERE c.course_id = '$COURSE_ID'
) TO '$TMP/sections.csv' WITH (FORMAT csv, NULL '')"

# Questions — only adaptive-eligible so diagnostics and practice can run.
# source_material_id and school_id → NULL (we don't clone those tables).
prod -c "\COPY (
  SELECT
    id, content, answer, question_type, options, source_url, source_page,
    is_generated, hobby_context, difficulty, metadata, explanation,
    validation_status, validation_score, validation_report, validated_at,
    validation_attempts, classification_status, classification_confidence,
    classified_at, course_id, chapter_id, section_id,
    NULL::uuid AS school_id,
    NULL::uuid AS source_material_id,
    inserted_at, updated_at,
    source_type, generation_mode, grounding_refs
  FROM questions
  WHERE course_id = '$COURSE_ID'
    AND validation_status = 'passed'
    AND section_id IS NOT NULL
    AND classification_status IN ('ai_classified', 'admin_reviewed')
) TO '$TMP/questions.csv' WITH (FORMAT csv, NULL '')"

echo "==> Wiping existing course from dev..."
dev <<SQL
DELETE FROM questions WHERE course_id = '$COURSE_ID';
DELETE FROM sections WHERE chapter_id IN (SELECT id FROM chapters WHERE course_id = '$COURSE_ID');
DELETE FROM chapters WHERE course_id = '$COURSE_ID';
DELETE FROM courses WHERE id = '$COURSE_ID';
SQL

echo "==> Importing into dev..."

# Column orders match the exports above
dev -c "\COPY courses (
  id, name, subject, grade, school_id, description, metadata,
  created_by_id, inserted_at, updated_at, processing_status,
  processing_step, processing_error, ocr_completed_count, ocr_total_count,
  textbook_id, custom_textbook_name, external_provider, external_id,
  external_synced_at, pending_toc_id, pending_toc_proposed_by_id,
  pending_toc_proposed_at
) FROM '$TMP/courses.csv' WITH (FORMAT csv, NULL '')"

dev -c "\COPY chapters (id, course_id, name, position, inserted_at, updated_at, orphaned_at) FROM '$TMP/chapters.csv' WITH (FORMAT csv, NULL '')"

dev -c "\COPY sections (id, chapter_id, name, position, inserted_at, updated_at) FROM '$TMP/sections.csv' WITH (FORMAT csv, NULL '')"

dev -c "\COPY questions (
  id, content, answer, question_type, options, source_url, source_page,
  is_generated, hobby_context, difficulty, metadata, explanation,
  validation_status, validation_score, validation_report, validated_at,
  validation_attempts, classification_status, classification_confidence,
  classified_at, course_id, chapter_id, section_id, school_id,
  source_material_id, inserted_at, updated_at,
  source_type, generation_mode, grounding_refs
) FROM '$TMP/questions.csv' WITH (FORMAT csv, NULL '')"

echo "==> Cloned:"
dev -c "SELECT
  (SELECT COUNT(*) FROM courses WHERE id = '$COURSE_ID') AS course,
  (SELECT COUNT(*) FROM chapters WHERE course_id = '$COURSE_ID') AS chapters,
  (SELECT COUNT(*) FROM sections s JOIN chapters c ON c.id = s.chapter_id WHERE c.course_id = '$COURSE_ID') AS sections,
  (SELECT COUNT(*) FROM questions WHERE course_id = '$COURSE_ID') AS questions;"

echo "==> Done. Log in via /dev/login and you should see the AP Biology course."
