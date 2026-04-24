# Runbook: Backfill Material Classification

For existing `UploadedMaterial` rows that were ingested before the Phase 2 AI classifier shipped (or via filename heuristic only). Use this when you suspect answer keys or other non-question content slipped into the extractor and produced bogus `questions` rows.

**Tools this runbook uses — all already in the repo**:
- `mix funsheep.materials.classify` (Phase 2 backfill)
- `mix funsheep.questions.cleanup audit` (health snapshot)
- `mix funsheep.questions.cleanup delete_garbage` (content-pattern cleanup)
- Direct SQL for the material-classification-scoped deletion (no subcommand exists for that specific pivot today — if it becomes routine, see "Productizing" at the bottom).

Time: ~15 minutes for a single course, ~30–60 min for the full database.

---

## Phase 1 — Take a snapshot before you change anything

```bash
# For one course at a time (preferred — keeps the diff inspectable):
mix funsheep.questions.cleanup audit --course <course-id>
```

Capture the output (pipe to a file or paste to the incident doc). You're looking for:
- `source_type` distribution → how many rows are at risk?
- `validation_status` breakdown → are they reaching students (`:passed`) or queued for validation (`:pending`)?
- I-1 adaptive eligibility (`section_id`, `classification_status`) → a `:passed` bogus row with a skill tag *will* surface in adaptive flows. That's the urgent case.

---

## Phase 2 — Run the Phase 2 classifier over existing materials

The classifier is idempotent; re-running is free. Start with a dry-run to see the scope:

```bash
# Dry-run — counts how many materials need classification, enqueues nothing
mix funsheep.materials.classify --prod-db

# Scoped to one course first
mix funsheep.materials.classify --prod-db --course <course-id> --confirm

# After spot-checking a few courses, run unscoped
mix funsheep.materials.classify --prod-db --confirm
```

Watch Oban — the classifier runs in the `:ai` queue. Give it time to drain before Phase 3.

---

## Phase 3 — Identify questions from materials now flagged as junk

After classification completes, answer-key and unusable materials have `classified_kind ∈ {:answer_key, :unusable}`. Any questions hanging off those materials are garbage.

```sql
-- Quick counts (no writes)
SELECT
  m.classified_kind,
  m.file_name,
  COUNT(q.id) AS bogus_question_count,
  COUNT(q.id) FILTER (WHERE q.validation_status = 'passed') AS currently_student_visible
FROM uploaded_materials m
JOIN questions q ON q.source_material_id = m.id
WHERE m.classified_kind IN ('answer_key', 'unusable')
GROUP BY m.id, m.classified_kind, m.file_name
ORDER BY bogus_question_count DESC;
```

If `bogus_question_count` is > 0 for any row, you have cleanup to do. If `currently_student_visible` is > 0, you have an **immediate student-facing impact** — prioritize deletion.

---

## Phase 4 — Delete the bogus rows

Manual SQL path (dry-run first, then a transaction):

```sql
-- DRY-RUN: how many rows would we delete? Compare with Phase 3 counts.
SELECT COUNT(*)
FROM questions q
JOIN uploaded_materials m ON m.id = q.source_material_id
WHERE m.classified_kind IN ('answer_key', 'unusable');
```

If the count matches expectations, delete in a transaction:

```sql
BEGIN;

-- Actual delete
DELETE FROM questions q
USING uploaded_materials m
WHERE m.id = q.source_material_id
  AND m.classified_kind IN ('answer_key', 'unusable');

-- Verify before commit
SELECT COUNT(*) FROM questions q
JOIN uploaded_materials m ON m.id = q.source_material_id
WHERE m.classified_kind IN ('answer_key', 'unusable');
-- expect 0

COMMIT;
```

Roll back (`ROLLBACK`) if the counts don't match what Phase 3 reported.

**Why direct SQL and not a mix task**: this is a one-shot Phase 0 cleanup. Productizing a subcommand adds a permanent "delete from classified-sources" code path that we want to discourage — the goal is for the classifier + upload-time filename heuristic (CR-001) to make post-hoc cleanup unnecessary going forward.

---

## Phase 5 — Follow-up content cleanup (optional)

Some bogus rows slipped past the source-material pivot — e.g., questions whose `source_material_id` was `NULL` because the extractor didn't tag provenance, or question bodies that regex-match the answer-key pattern but come from a legitimately-classified question bank (false positives in extraction). Use the existing content-pattern cleanup for those:

```bash
mix funsheep.questions.cleanup delete_garbage --course <course-id>            # dry-run
mix funsheep.questions.cleanup delete_garbage --course <course-id> --confirm  # destructive
```

---

## Phase 6 — Re-audit and close the incident

```bash
mix funsheep.questions.cleanup audit --course <course-id>
```

Diff against the Phase 1 snapshot. Expect:
- `source_type = :unknown` bucket unchanged (source_type is separate from classified_kind)
- Total question counts lower by the Phase 4 delete count
- `:passed` student-visible counts lower by however many were currently live

If the new totals look wrong, investigate before moving on.

---

## Safeguards

- **Always audit before and after.** Phase 1 + Phase 6 are not optional.
- **Scope to a single course first** whenever possible. Full-DB runs only after at least one single-course run has been verified clean.
- **Don't delete `question_attempts`.** The schema doesn't cascade, and attempt history is useful for auditing even after the question itself is gone. (If the student-facing UI shows a "question no longer exists" artifact post-cleanup, that's a separate bug to fix.)
- **Don't use `--skip-provision`** on any deploy while this cleanup is in flight. If the Interactor assistants API is the reason you're running this (a classifier outage produced bad classifications), let that recover first before running `mix funsheep.materials.classify` again — otherwise you'll re-run the classifier on already-classified materials and maybe flip verdicts.

---

## Productizing

If this operation becomes routine (e.g. > 3x/quarter), add a `mix funsheep.questions.cleanup delete_from_misclassified_sources` subcommand that encapsulates Phase 4 as a dry-run-default, per-course-scoped mix task. Until then, the direct-SQL path is safer because it forces the operator to read the counts at each step.
