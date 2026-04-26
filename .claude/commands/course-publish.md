# /course-publish — Publish a Test Course to Production

Validates readiness, deploys code, seeds the production DB via the admin panel, and marks the course live.

## Usage

```
/course-publish SAT
/course-publish ACT
/course-publish "GRE Verbal"
```

---

## Step-by-step Instructions

### Step 1 — Parse the test name from `$ARGUMENTS`

Lowercase it and strip spaces to get `test_type` (e.g. `"sat"`, `"act"`, `"gre"`).

### Step 2 — Readiness check (local dev DB)

Query the local dev DB:

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep && ~/.asdf/shims/mix run -e "
alias FunSheep.{Repo, Courses}
alias FunSheep.Courses.{Course, Chapter}
import Ecto.Query

test_type = \"<test_type_lowercase>\"

courses =
  Repo.all(
    from c in Course,
    where: c.catalog_test_type == ^test_type and c.is_premium_catalog == true,
    select: [:id, :name, :processing_status, :published_at, :price_cents, :metadata]
  )

IO.puts(\"\\nCourses for #{test_type}: #{length(courses)}\")
Enum.each(courses, fn c ->
  q_count = Repo.aggregate(from(q in FunSheep.Questions.Question, where: q.course_id == ^c.id), :count)
  IO.puts(\"  #{c.name} | status=#{c.processing_status} | questions=#{q_count} | published=#{c.published_at != nil}\")
end)
"
```

**Gate conditions — ALL must pass:**

- At least 1 course exists for this test type
- Every course has `processing_status = "ready"` (if any are `pending` or `processing`, stop and report)
- Every course has question count > 0 (if any have 0 questions, stop and report)
- At least 1 course still has `published_at = nil` (otherwise already published — nothing to do)

If any gate fails, stop and report what is missing. Do NOT proceed.

### Step 3 — Export the course spec(s) from dev DB

For each course that passes the gate, reconstruct its COURSE_SPEC JSON by querying the DB:

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep && ~/.asdf/shims/mix run -e "
alias FunSheep.{Repo}
alias FunSheep.Courses.{Course, Chapter, Section}
alias FunSheep.Courses.TestFormatTemplate
import Ecto.Query

test_type = \"<test_type_lowercase>\"

courses =
  Repo.all(
    from c in Course,
    where: c.catalog_test_type == ^test_type and c.is_premium_catalog == true,
    preload: [chapters: :sections]
  )

Enum.each(courses, fn c ->
  template = Repo.one(from t in TestFormatTemplate, where: t.course_id == ^c.id, limit: 1)
  gen_config = c.metadata[\"generation_config\"] || %{}
  weights = c.metadata[\"score_predictor_weights\"] || %{}

  chapters =
    Enum.map(c.chapters, fn ch ->
      %{name: ch.name, sections: Enum.map(ch.sections, & &1.name)}
    end)

  exam_simulation =
    if template do
      structure = template.structure
      %{
        time_limit_minutes: structure[\"time_limit_minutes\"],
        sections: structure[\"sections\"]
      }
    end

  spec = %{
    name: c.name,
    test_type: c.catalog_test_type,
    subject: c.catalog_subject,
    grades: c.grades,
    description: c.description,
    price_cents: c.price_cents,
    currency: c.currency || \"usd\",
    chapters: chapters,
    exam_simulation: exam_simulation,
    score_predictor_weights: weights,
    generation_config: gen_config
  }
  |> Map.reject(fn {_, v} -> is_nil(v) end)

  IO.puts(Jason.encode!(spec, pretty: false))
end)
"
```

Capture the JSON output for each course. You'll paste these into the production admin panel in Step 6.

### Step 4 — Git and code deploy pre-flight

```bash
git status --porcelain --ignore-submodules=dirty
git fetch origin main
git rev-parse HEAD
git rev-parse origin/main
```

**Checks:**
- Working tree must be clean. If there are uncommitted changes, stop and report them.
- If local main is ahead of origin/main, push: `git push origin main`
- If behind, stop: the user must pull and resolve.
- If already in sync, proceed.

### Step 5 — Deploy to production

```bash
cd /home/pulzze/Documents/GitHub/personal/funsheep && ./scripts/deploy/deploy-prod.sh --yes
```

Wait for the deploy to complete. The script:
- Builds and deploys the Cloud Run image (includes all new code)
- Runs DB migrations on the production DB
- Promotes the worker service with the same image
- Smoke-tests `/health` and rolls back automatically on failure

If the deploy fails, stop and report the error from the script output. Do NOT proceed to Step 6.

### Step 6 — Seed the production database

The production DB is a separate Cloud SQL instance. The course structure (chapters, sections, exam template) must be created there. There are two paths:

#### Path A — Admin panel (recommended)

1. Navigate to **https://funsheep.com/admin/course-builder** (production admin panel)
2. For each course spec from Step 3, paste the JSON into the "Create New Test Course" textarea
3. Click **"Validate & Preview"** — verify the chapter/section counts match dev
4. Click **"Create Course"** — the CourseBuilder will create the course idempotently
5. Repeat for each course in the test (Math, then RW, then include the bundle spec on the last one)

#### Path B — Remote Mix task via Cloud SQL proxy (advanced)

If Cloud SQL Auth Proxy is running locally at port 5433:

```bash
DATABASE_URL="postgresql://postgres:password@localhost:5433/funsheep_prod" \
~/.asdf/shims/mix funsheep.course.create --spec '<json>'
```

Use Path A unless the user explicitly asks for Path B.

### Step 7 — Trigger question generation in production

After the course structure is created in production:

1. Navigate to **https://funsheep.com/admin/course-builder**
2. For each course just created, click **"Generate Questions"**
3. Monitor progress in the admin panel — generation takes 10–30 minutes per course
4. Wait until `processing_status` changes from `processing` to `ready`

Generation runs on the production worker service (Oban queue) using the `generation_config` metadata stored on the course.

### Step 8 — Publish in production

Once generation is complete (all courses show `ready` status):

1. In the admin panel, click **"Publish"** for each course
   — OR run this one-time SQL if you have Cloud SQL access:

```sql
UPDATE courses
SET published_at = NOW()
WHERE catalog_test_type = '<test_type_lowercase>'
  AND processing_status = 'ready'
  AND published_at IS NULL
  AND is_premium_catalog = TRUE;
```

2. Verify the course is live at **https://funsheep.com/courses** — it should appear in the premium catalog

### Step 9 — Report

Print a summary:

```
## Published: SAT

### Deploy
- Commit: <sha> — <message>
- Cloud Run revision: <revision>
- Worker revision: <revision>

### Courses
- SAT Math — <id> — ready, published ✓
- SAT Reading & Writing — <id> — ready, published ✓

### Bundle
- SAT Full Prep Bundle — $49 — active ✓

### Next steps
1. Verify courses appear at https://funsheep.com/courses
2. Test purchase flow with a test student account
3. Monitor question generation logs: gcloud run services logs tail funsheep-worker --region=<region>
```

---

## Common Issues

| Issue | Fix |
|-------|-----|
| `processing_status = "processing"` (not ready) | Wait for generation to finish. Check Oban queue in admin. |
| `processing_status = "failed"` | Re-run generation from admin panel. Check worker logs. |
| `0 questions` | Course was never generated. Click "Generate Questions" in admin. |
| Deploy fails at smoke test | Check `/health` endpoint and Cloud Run logs. |
| Course already exists in prod | CourseBuilder is idempotent — safe to re-run. It skips existing records. |
| Bundle not created | Include the bundle key on the LAST course spec only (all course names must exist first). |
