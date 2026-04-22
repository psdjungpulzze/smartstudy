# Flow C — Teacher-initiated — Delivery Checklist

Full spec: `~/s/funsheep-subscription-flows.md` §6, §8.5, §11.5.

**Narrative**: teacher onboards a class, adds students, schedules a test. Students practice on free tier. If a student hits the wall, Flow A fires — **routed to the student's parent, not the teacher**. Teachers never see pricing, never get billing emails.

Ship in its own worktree after Flow A (and ideally Flow B) is live. Flow C depends on the teacher-visit guard on `/subscription` that should ALREADY ship in Flow A PR 3 (cross-referenced in that checklist).

---

## Prerequisites

- [ ] Flow A PRs 1, 2, 3 merged (meter, request flow, teacher `/subscription` guard)
- [ ] Existing class/classroom infrastructure reviewed — see §6.2 Step 1 note about `Classrooms.create_class/2`; if not shipped, fall back to guardian-invite-as-teacher and add a TODO migration for classrooms proper

---

## Entry points (§6.1)

- [ ] Marketing site "I'm a teacher" CTA → teacher signup
- [ ] `/signup` with "I'm a teacher" role chosen → Flow C wizard

---

## Teacher onboarding wizard — `/onboarding/teacher` (§6.2)

New LiveView: `FunSheepWeb.TeacherOnboardingLive` (unless Teacher experience Phase 1 already shipped it — check before creating).

### Step 1 — "Create your first class"

- [ ] Name, period, course, school year
- [ ] If `Classrooms.create_class/2` exists, use it
- [ ] Otherwise, fallback: create `student_guardians` rows with `relationship_type: :teacher` when students are added — document the TODO for proper classrooms migration

### Step 2 — "Add students"

- [ ] Manual email entry (CSV import + roster sync deferred to Teacher Phase 5)
- [ ] Each entered email triggers the existing invite flow (`Accounts.invite_guardian/3` with `:teacher` relationship)
- [ ] Duplicate-email guard — same email cannot be added twice to the same class
- [ ] Show live list of added students with invite status

### Step 3 — "Schedule an upcoming test"

- [ ] Test name, date, subject, scope (chapters/standards if available in the data model)
- [ ] Optional — teacher can skip
- [ ] If set, this test surfaces in each student's dashboard and seeds `metadata.upcoming_test` when a Flow A request eventually fires for one of these students

### Step 4 — "Done"

- [ ] Summary copy: students will be invited; they start on free tier; when a student hits the weekly limit, a **parent ask** fires automatically; teacher never sees a billing prompt
- [ ] CTA: "[Go to your classroom]" → teacher dashboard

---

## Teacher-visited `/subscription` (§6.3, §8.5) — already shipped in Flow A PR 3

Re-verify after Flow C lands:

- [ ] `SubscriptionLive` renders the free-for-educators copy (§8.5) when mounted by a `:teacher` role
- [ ] No plan picker, no prices, no checkout buttons for teachers
- [ ] Link back to teacher dashboard

---

## Flow A routing from teacher-added students (§6.2 Step 5)

The critical correctness property: when a student who was added via a teacher invite hits the wall, the Flow A request must route to the **student's parent**, not the teacher.

- [ ] When student hits 85% threshold and opens the Ask modal, the guardian picker lists `relationship_type: :parent` guardians only
- [ ] If the student has **no parent** linked, falls back to the §4.8 invite-a-grown-up flow — prompts the student to enter a parent email
- [ ] Teachers do NOT appear in the guardian picker under any circumstance
- [ ] `list_active_guardians_for_student/1` must have an `only: :parent` option (or the caller filters by relationship_type) — verify in Flow A's context or add here

---

## Billing visibility rules (§6.3)

- [ ] Teacher dashboard may (optionally) show free-vs-unlimited icon per student — **only if the teacher's school/district has opted in**. Default: hidden, FERPA-safe
- [ ] Teacher never receives billing emails (check `ParentRequestEmailWorker` — recipient must be a parent guardian, never a teacher)
- [ ] Teacher never sees `paid_by_user_role_id` values
- [ ] Parent dashboard is NOT cross-linked to the teacher's view

---

## Acceptance criteria (§6.3)

- [ ] `/onboarding/teacher` wizard implements the 4-step flow
- [ ] Teacher-added students land on free tier with no billing touch
- [ ] Student from a teacher invite hitting the wall routes the request to the student's **parent** (not the teacher); fallback to invite-a-grown-up if no parent linked
- [ ] `/subscription` for a `:teacher` role renders the "free for educators" message (verified via test)
- [ ] Teachers do not receive any `ParentRequestEmail`

---

## Tests

- [ ] LiveView test: teacher onboarding wizard navigation
- [ ] LiveView test: teacher `/subscription` renders educator copy, not plan picker
- [ ] Integration test (critical): student added via teacher → hits weekly limit → Ask modal → guardian picker lists parent(s) only → request sent to parent (not teacher) → teacher receives nothing
- [ ] Integration test: teacher-added student with NO parent linked → hits wall → invite-a-grown-up flow fires
- [ ] Context test: `ParentRequestEmailWorker` rejects teacher recipients (regression guard)
- [ ] Coverage ≥ 80%, all lints clean

---

## Visual verification

Light + dark at 375, 768, 1440.

- [ ] Each teacher wizard step
- [ ] Teacher dashboard (with and without FERPA opt-in — verify icon visibility)
- [ ] Teacher `/subscription` free-for-educators page (re-verify)
- [ ] Duplicate-email guard state in Step 2

---

## What NOT to do

- [ ] Do NOT surface pricing or checkout UI anywhere in the teacher role
- [ ] Do NOT send `ParentRequestEmail` to any `:teacher` UserRole — ever
- [ ] Do NOT let teachers appear in a student's guardian picker for Flow A
- [ ] Do NOT expose `paid_by_user_role_id` to teacher dashboards
- [ ] Do NOT default FERPA-sensitive billing-status icons to visible
- [ ] Do NOT bundle a class-level subscription (teachers don't pay; that's the whole point)

---

## Regression surface

- [ ] Existing `/guardians` flow still works for teacher-as-guardian invites (if that's the fallback path)
- [ ] Existing teacher dashboard (if any) still renders
- [ ] Flow A still works for students onboarded via Flow B (parent) — Flow C should not regress anything
- [ ] `/subscription` still serves `:student` and `:parent` roles as plan picker (only `:teacher` gets the educator message)

---

## Deferred to Phase 5+ (explicitly not in this PR)

- CSV / SIS roster sync
- Class-level analytics / teacher classroom reports
- Parent-teacher messaging
- District admin tier
