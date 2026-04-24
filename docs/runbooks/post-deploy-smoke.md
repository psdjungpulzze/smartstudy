# Post-Deploy Smoke Test Runbook

Run this after every `scripts/deploy/deploy-prod.sh` to prod Cloud Run. Total time: ~15–20 min end-to-end.

Assumes `.env.credentials` is present at repo root (gitignored) with `PROD_TEST_STUDENT_EMAIL`, `PROD_TEST_STUDENT_PASSWORD`, `TEST_ACCOUNT_PASSWORD`, `TEST_STUDENT_EMAIL`, etc.

---

## 0. Preflight (30 s)

Verify the deploy script's own health check passed (auto-rollback kicked in if not). Then confirm the service is reachable and rendering:

```bash
curl -sI https://funsheep.com/health            # expect 200
curl -sI https://funsheep.com/                  # expect 200 or 302
```

Optional — tail recent errors for anything glaring:

```bash
# needs gcloud auth; skip if unavailable
gcloud run services logs read funsheep --limit 50 --region us-central1 2>/dev/null | grep -iE "error|crash|500" | head -20
```

---

## 1. Automated broad smoke (~8 min)

These are the "does the app work at all" checks. Run in order, review screenshots after each.

### 1a. Basic flows — registration + login + course + test (parent & student)

```bash
node scripts/prod-verify.js
```

**What it covers**: 3 accounts (1 student, 2 parents), registration via Interactor, login, course creation, test creation. Saves screenshots to `screenshots/prod-verify-*`.
**Pass criteria**: all tasks report `status: "pass"`. Non-zero exit or any `status: "fail"` is a regression.

### 1b. Course creation E2E

```bash
node scripts/prod-course-flow-test.mjs
```

**What it covers**: Login → `/courses/new` → fill form → submit → verify navigation to `/courses/:id` → attempt test creation.
**Pass criteria**: final URL matches `/courses/:uuid/tests/new` or equivalent; no browser console errors.

### 1c. OAuth parent flow (verified account path)

```bash
node scripts/prod-oauth-full-psdjung.mjs
```

**What it covers**: OAuth login as verified parent, dashboard exploration, course/test creation attempts, logout. Exercises the auth-integration path specifically.
**Pass criteria**: all 5 tasks (login, dashboard, course, test, logout) report `status: "pass"`.

---

## 2. Feature-specific smoke (~5 min)

This section is for manually verifying **features that shipped in the most recent deploy**. Update this list each time a CR merges. Record results in a scratch file if you want an audit trail; otherwise, spot-check and move on.

### 2a. CR-001 (2026-04-24) — test-scoped assessment + primary-test pin

Sign in as the prod test student (`.env.credentials` → `PROD_TEST_STUDENT_EMAIL`) and verify on `https://funsheep.com`:

- [ ] `/dashboard` loads. Focus card is visible on the nearest-deadline test.
- [ ] **Pin mechanism** — click the ⭐ on a non-primary test in "Other Tests". The ⭐ Focus badge appears on that test's focus card. Reload → persists. Click the filled ⭐ to unpin → reverts to nearest-deadline.
- [ ] **No source picker on `/assess`** — click "Assess" on a scheduled test. You should land in the engine (question shown, readiness-block, or no-questions state) — NOT a "Question Sources" file-picker screen.
- [ ] **Empty-state CTAs** — if any test student has zero upcoming tests, `/dashboard` empty state shows "Connect School LMS" as primary CTA + a secondary "Create a test manually" fallback. (Usually not testable on the main test student; skip unless you can seed a zero-test account.)

### 2b. CR-001 (Task 8) — answer-key filename heuristic

Upload a PDF named `*-answer-key.pdf` (or similar) on a test course and verify via admin or DB that the `uploaded_materials.material_kind` column is set to `:answer_key`, NOT `:textbook`. The `QuestionExtractionWorker` should then skip it — zero new question rows should appear from that file.

If you have access to the `FunSheep.Workers.MaterialClassificationWorker` admin route, check that the classifier independently confirms `:answer_key` (second safety net).

---

## 3. Phase-specific QA (optional, ~8 min)

Run when the deploy touches the learning loop (assessment engine, readiness, study path, tutor, practice):

```bash
node scripts/qa/phase-0.5-prod-qa.mjs
```

**What it covers**: Runs the diagnostic twice on AP Biology as the prod student; captures screenshots of weak-topic CTAs, inline explanations, skill badges, readiness deltas.
**Pass criteria**: the four findings (`weak_topics_cta`, `inline_explanation`, `skill_badge`, `readiness_delta`) each report `status: "PASS"` or an explicit explanation in `notes`.

---

## 4. Post-smoke monitoring (ongoing, first hour)

Keep an eye on:

- **Cloud Run error rate** — if it spikes above baseline for 5+ min after deploy, consider rolling back via Cloud Run console.
- **Oban job failures** — unusual rate of `max_attempts` exhaustion in the `:ai` or `:default` queues suggests an Interactor/downstream issue.
- **User-facing errors** — scan `#funsheep-alerts` or equivalent for the first 30 min.

Rollback command (deploy script's auto-rollback handles most of this, but manual fallback):

```bash
gcloud run services update-traffic funsheep --to-revisions=<prior-revision>=100 --region us-central1
```

---

## When a smoke test fails

1. **Capture artifacts**: screenshots directory, script output, Cloud Run logs for the same window.
2. **Decide severity**:
   - P0 (users blocked) → rollback immediately, diagnose from rollback state.
   - P1 (degraded) → open an incident, fix-forward if small, rollback if big.
   - P2 (non-critical regression) → log as a bug, schedule fix.
3. **Update this runbook** if a new failure mode is surfaced that wasn't covered by an existing check.

---

## Maintenance

- Add a `2a/2b/2c` entry each time a CR introduces a user-visible feature that warrants a targeted smoke check.
- Prune entries when the feature becomes covered by the broader scripts in §1.
- Keep script paths in this doc in sync with `scripts/` — old script renames are the #1 source of runbook rot.
