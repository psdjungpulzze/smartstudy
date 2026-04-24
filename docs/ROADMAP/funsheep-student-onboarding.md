# FunSheep — Student Onboarding: Parent & Teacher Flows

> **For the Claude session implementing this feature.** Read the entire document before writing any code. §1 (what already exists) is load-bearing — the invite infrastructure is largely in place and must not be reinvented.

---

## 0. Project context

FunSheep is a Phoenix 1.7 / Elixir / LiveView test-prep product for K–12 students.

- **Repo**: `/home/pulzze/Documents/GitHub/personal/funsheep`
- **Web**: `FunSheepWeb.*` under `lib/fun_sheep_web/`
- **Roles** (`user_roles.role`): `:student | :parent | :teacher | :admin`
- **Auth**: Interactor Account Server (JWT in session; `current_user["interactor_user_id"]`)
- **Jobs**: Oban
- **Mailer**: `FunSheep.Mailer` (Swoosh)
- **UI**: Tailwind per `.claude/rules/i/ui-design.md` — pill controls (`rounded-full`), cards `rounded-2xl`, primary green `#4CD964`, outlined icons `stroke-width="1.5"`

You MUST read before coding:

- `CLAUDE.md` — especially **ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT**
- `.claude/rules/i/ui-design.md`
- `.claude/rules/i/code-style.md`
- `.claude/rules/i/visual-testing.md` — Playwright verification is mandatory before marking any UI task complete
- `.claude/rules/i/security.md`
- `docs/ROADMAP/Archives/funsheep-parent-experience.md` — parent persona research (load-bearing)
- `docs/ROADMAP/Archives/funsheep-teacher-experience.md` — teacher persona research (load-bearing)

---

## 1. What already exists (do NOT rebuild)

### 1.1 Core relationship model

| Asset | Location | State |
|---|---|---|
| `StudentGuardian` schema | `lib/fun_sheep/accounts/student_guardian.ex` | Complete. `guardian_id`, `student_id`, `relationship_type (:parent\|:teacher)`, `status (:pending\|:active\|:revoked)`, `invited_at`, `accepted_at`. |
| Email-only invite path | Same schema | `invited_email`, `invite_token` (32-byte URL-safe base64), `invite_token_expires_at` (14-day TTL). Used when guardian email has no local `UserRole` yet. |
| `InviteCode` schema | `lib/fun_sheep/accounts/invite_code.ex` | 8-char base32 code; `guardian_id`, `relationship_type`, `child_display_name`, `child_grade`, `child_email`, `redeemed_by_user_role_id`, `redeemed_at`, `expires_at` (14-day). Parent generates; student claims via `/claim/:code`. |
| `Accounts` context functions | `lib/fun_sheep/accounts.ex` | `invite_guardian_by_student/3`, `claim_guardian_invite_by_token/2`, `accept_guardian_invite/1`, `reject_guardian_invite/1`, `list_students_for_guardian/1`, `list_guardians_for_student/1`, `guardian_has_access?/2` |
| Guardian invite inbox | `FunSheepWeb.GuardianInviteLive` at `/guardians` | Pending invites inbox. Works for both parent and teacher roles. Extend; do not fork. |
| Guardian claim page | `FunSheepWeb.GuardianInviteClaimLive` at `/guardian-invite/:token` | Email-only claim flow. |
| Claim code page | `FunSheepWeb.ClaimCodeLive` at `/claim/:code` | Student claims parent-generated code. |
| Parent onboarding wizard | `FunSheepWeb.ParentOnboardingLive` at `/onboarding/parent` | Multi-step: parent info → code generation → (purchase). |
| Teacher onboarding wizard | `FunSheepWeb.TeacherOnboardingLive` at `/onboarding/teacher` | Multi-step: school → class details → (student add). Class details are **NOT yet persisted** to a `classrooms` table. |

### 1.2 The existing invite direction (critical)

The current `invite_guardian_by_student/3` function is **student-initiated**: the student types the guardian's email and the guardian receives a claim link or sees a pending invite in their inbox.

**This prompt adds the reverse direction**: guardian-initiated invite. The guardian types the student's email; the student receives an email and must accept. The `StudentGuardian` rows, token mechanism, and mailer infrastructure are all reusable — only the initiating party and the direction of the email are different.

### 1.3 What is missing

| Gap | Impact |
|---|---|
| Guardian-initiated invite path | Parents and teachers cannot proactively add students; students must invite first |
| `classrooms` table | Teacher class details vanish after onboarding; no persistent roster |
| Bulk CSV/Excel import for teachers | No batch invite mechanism; adding 30 students one-by-one is a non-starter for teachers |
| `student_guardians` initiator tracking | No `initiated_by` column — cannot tell whether invite came from student or guardian |
| Resend invite | No `resend_guardian_invite/1` function |
| Guardian relationship management UI | No way to view, revoke, or manage existing links from the guardian side |

---

## 2. Data model changes

### 2.1 Add `initiated_by` to `student_guardians`

```sql
ALTER TABLE student_guardians
  ADD COLUMN initiated_by varchar(20) NOT NULL DEFAULT 'student'
    CHECK (initiated_by IN ('student', 'guardian'));
```

- `'student'` — student sent the invite to the guardian (existing flow)
- `'guardian'` — guardian sent the invite to the student (new flow)

The `invite_token` and `invited_email` columns are reused for the guardian-initiated path. When `initiated_by = 'guardian'`, `invited_email` holds the **student's** email, and the token is sent to the student — not the guardian.

Migration: add column with default `'student'`; no backfill needed.

### 2.2 Create `classrooms` table

```sql
CREATE TABLE classrooms (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id    uuid NOT NULL REFERENCES user_roles(id) ON DELETE CASCADE,
  name          varchar(255) NOT NULL,        -- "AP Biology Period 3"
  subject       varchar(100),                  -- "AP Biology"
  grade         varchar(20),                   -- "11"
  period        varchar(50),                   -- "3rd Period"
  school_year   varchar(20),                   -- "2025-2026"
  school_id     uuid REFERENCES schools(id),
  archived_at   timestamptz,
  inserted_at   timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX classrooms_teacher_id_idx ON classrooms(teacher_id);
```

### 2.3 Link `student_guardians` to `classrooms` (optional but recommended)

Add a nullable FK so teacher-student links can be organised by class:

```sql
ALTER TABLE student_guardians
  ADD COLUMN classroom_id uuid REFERENCES classrooms(id) ON DELETE SET NULL;
```

This allows a teacher to have 140 students across 5 sections without one undifferentiated list.

### 2.4 Create `bulk_invite_imports` table (for async upload tracking)

```sql
CREATE TABLE bulk_invite_imports (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id      uuid NOT NULL REFERENCES user_roles(id) ON DELETE CASCADE,
  classroom_id    uuid REFERENCES classrooms(id) ON DELETE SET NULL,
  filename        varchar(255),
  row_count       integer,
  processed_count integer DEFAULT 0,
  failed_count    integer DEFAULT 0,
  status          varchar(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','done','failed')),
  error_log       jsonb,            -- [{row: 3, email: "x", reason: "invalid email"}]
  inserted_at     timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
```

Processing is an Oban job; the LiveView subscribes to PubSub for real-time progress.

---

## 3. Flow A — Parent-initiated invite

### 3.1 Design

```
Parent types child's email
        │
        ▼
System checks: does a student UserRole with that email exist?
   ├── YES ─▶ Create StudentGuardian{status: :pending, initiated_by: guardian}
   │           Notify student in-app (GuardianInviteLive inbox)
   │           Email student: "Your parent wants to monitor your progress"
   │
   └── NO  ─▶ Create StudentGuardian{status: :pending, initiated_by: guardian,
                   invited_email: student_email, invite_token: <token>}
               Email student: "Your parent has added you to FunSheep — accept to continue"
               Token link: /student-invite/:token → registers or links existing account
```

The student receives an email and can:
- **Accept** → `status` becomes `:active`; parent gains visibility
- **Decline** → `status` becomes `:revoked`; parent sees "declined" in their list
- **Ignore** → token expires after 14 days; parent sees "pending"

A student can have **multiple** active parent/guardian links (no upper limit enforced — family structures vary).

### 3.2 New routes

```elixir
# router.ex — add to authenticated live_session :authenticated
live "/parent/students", ParentStudentManageLive, :index
live "/parent/students/invite", ParentStudentManageLive, :invite
live "/parent/students/:id", ParentStudentManageLive, :show

# Public (no auth required — student clicking email link)
live "/student-invite/:token", StudentInviteClaimLive, :claim
```

### 3.3 New LiveView: `ParentStudentManageLive`

Three actions on one LiveView:

- **`:index`** — Lists all linked students (active), pending invites (pending), and declined/expired. Each row shows: student display name (or "Pending — student@email.com"), status badge, accepted_at or invited_at, actions (revoke / resend).
- **`:invite`** — Modal/slide-in form: email input + optional note. On submit calls `Accounts.invite_student_by_guardian/3`.
- **`:show`** — Quick preview of a linked student's dashboard (read-only; redirects to `/parent` for full view).

### 3.4 New context function: `invite_student_by_guardian/3`

```elixir
@spec invite_student_by_guardian(UserRole.t(), String.t(), atom()) ::
        {:ok, StudentGuardian.t()} | {:error, :already_linked | Ecto.Changeset.t()}
def invite_student_by_guardian(guardian, student_email, relationship_type \\ :parent)
```

Logic:
1. Check for existing active or pending link → return `{:error, :already_linked}` if found
2. Look up `UserRole` by email where role = `:student`
3. If found: create `StudentGuardian{guardian_id, student_id, initiated_by: :guardian, status: :pending}` → enqueue `StudentInviteEmail` Oban job
4. If not found: create with `invited_email`, `invite_token`, `invite_token_expires_at` → enqueue `StudentInviteEmail` Oban job
5. Return `{:ok, student_guardian}`

### 3.5 New public LiveView: `StudentInviteClaimLive` at `/student-invite/:token`

For students who aren't logged in yet when they click the email link:

1. Validate token — if expired, show "This invite has expired; ask your parent to resend"
2. If student is not logged in: redirect to Interactor login with `return_to` = `/student-invite/:token`
3. After login, re-visit the route; `handle_params` calls `Accounts.claim_student_invite_by_token/2`
4. Show accept/decline choice with parent's name and relationship type
5. On accept: set `status: :active`, `accepted_at: now()` → redirect to `/dashboard`
6. On decline: set `status: :revoked` → redirect to `/dashboard` with a flash

### 3.6 Resend invite

```elixir
@spec resend_guardian_invite(StudentGuardian.t()) ::
        {:ok, StudentGuardian.t()} | {:error, :not_pending | Ecto.Changeset.t()}
```

- Only allowed when `status == :pending` and `invite_token_expires_at < now() + 1 hour` (prevent spam)
- Regenerates token, resets `invite_token_expires_at`
- Enqueues email job

---

## 4. Flow B — Teacher single invite

Teachers use the same guardian-initiated path (§3) but with `relationship_type: :teacher`.

The teacher adds a student from `/teacher/classroom/:id/students` → "Add Student" button → email form.

The key difference from the parent flow: teacher invites are scoped to a classroom. When `invite_student_by_guardian/3` is called from the teacher context, pass `classroom_id` to create the `StudentGuardian` with the classroom association.

No separate function needed — the classroom association is set on the `StudentGuardian` row, not embedded in the invite logic.

---

## 5. Flow C — Teacher bulk import (CSV / Excel)

### 5.1 Supported formats

| Format | Parsing |
|---|---|
| `.csv` | Elixir `NimbleCSV` — already available in most Elixir projects; add to mix.exs if not present |
| `.xlsx` | `xlsxir` or `elixlsx` for reading; **`xlsxir`** is read-only and simpler |

Accepted column names (case-insensitive, order-agnostic):

```
email           (required)
first_name      (optional)
last_name       (optional)
grade           (optional)
period          (optional — overrides classroom period if provided)
```

A template file is generated on demand and downloadable from the UI.

### 5.2 Upload flow (LiveView + Oban)

```
Teacher uploads file (LiveView allow_upload)
        │
        ▼
Server parses rows synchronously in handle_event/upload_handler:
  - Validate CSV/XLSX structure (headers, no empty email column)
  - Trim whitespace, normalise emails to lowercase
  - Deduplicate within the file
  - Return immediate feedback: "Found 32 rows. 2 rows have invalid emails — fix and re-upload, or skip them."
        │
        ▼ (teacher confirms)
Create BulkInviteImport{status: :pending, row_count: N}
Enqueue Oban job: BulkInviteWorker(import_id)
Subscribe LiveView to PubSub topic "bulk_import:#{import_id}"
        │
        ▼ (async, Oban worker)
For each valid row:
  - Call invite_student_by_guardian/3
  - Broadcast progress: {processed: N, total: M, last_email: "..."}
  - On error: log to BulkInviteImport.error_log (do NOT stop processing)
Set BulkInviteImport{status: :done, processed_count, failed_count}
Broadcast: {status: :done, processed_count, failed_count}
        │
        ▼ (LiveView receives broadcast)
Show summary card:
  "32 invites sent. 1 failed (bad email: student@bad). Download error report."
```

### 5.3 Rate limiting

The Oban worker processes rows at **max 10 emails/second** using `Process.sleep(100)` between sends to avoid Swoosh/SMTP rate limits. At 140 students this takes ~14 seconds — well within Oban's default job timeout (30 min).

### 5.4 Duplicate detection in bulk import

Before creating a `StudentGuardian`, check:
- Already active → skip silently, do NOT count as error
- Already pending → skip, count as "already invited"
- Revoked or expired → re-invite (create fresh pending row)

### 5.5 Template download

```elixir
# Controller action (not LiveView — binary download)
get "/teacher/classrooms/:id/import-template", ClassroomController, :import_template
```

Returns a CSV with example rows and a comment row explaining each column.

### 5.6 New routes

```elixir
# router.ex — add to authenticated live_session :authenticated
live "/teacher/classrooms",                    TeacherClassroomLive, :index
live "/teacher/classrooms/new",                TeacherClassroomLive, :new
live "/teacher/classrooms/:id",                TeacherClassroomLive, :show
live "/teacher/classrooms/:id/students",       TeacherClassroomStudentsLive, :index
live "/teacher/classrooms/:id/students/invite", TeacherClassroomStudentsLive, :invite
live "/teacher/classrooms/:id/students/import", TeacherClassroomStudentsLive, :import

# Regular controller for binary file download
get "/teacher/classrooms/:id/import-template", TeacherClassroomController, :import_template
```

---

## 6. Student acceptance for teacher invites

Same `/student-invite/:token` flow as parent invites (§3.5). The email wording differs:

- **Parent flow**: "Your parent [Name] wants to monitor your progress on FunSheep."
- **Teacher flow**: "Your teacher [Name] has added you to their [Class Name] class on FunSheep."

The student can accept or decline. If a student declines a teacher invite, the teacher sees "declined" on the roster — students cannot be force-enrolled.

---

## 7. Multi-guardian model

A student can have **multiple** active guardian relationships simultaneously:

- 2 parents + 1 teacher = 3 active `StudentGuardian` rows (no upper cap)
- Each guardian sees only their own relationship and the student's data
- Guardians cannot see each other (no "co-parent" relationship disclosure)
- Revoking one guardian does not affect others

`list_guardians_for_student/1` already supports this — returns all guardians with any status.

---

## 8. Email templates

Four new Swoosh email templates (plain-text + HTML):

| Template | Trigger | Subject |
|---|---|---|
| `student_invite_existing_email.heex` | Parent/teacher invites a student who already has an account | "Your [parent/teacher] wants to connect with you on FunSheep" |
| `student_invite_new_email.heex` | Parent/teacher invites a student with no account | "You've been invited to FunSheep by your [parent/teacher]" |
| `student_invite_resend_email.heex` | Resend of either of the above | "Reminder: [Parent/teacher name] is waiting for you on FunSheep" |
| `guardian_invite_accepted_email.heex` | Student accepts a guardian-initiated invite | "🎉 [Student name] has accepted your FunSheep connection" |

All emails must:
- Include the guardian's display name
- Include a clear CTA button (accept / view profile)
- Include an unsubscribe / opt-out note (even in transactional email)
- Never include the student's password, scores, or personal data in the email body itself

---

## 9. Permissions and authorization

| Action | Allowed by |
|---|---|
| Send invite (guardian-initiated) | Any `:parent` or `:teacher` role |
| Accept/decline student invite | The student whose email matches the invite only |
| Revoke an active link | Either party (guardian OR student) |
| View student data | Only guardians with `guardian_has_access?/2 == true` (i.e., `status == :active`) |
| Bulk import | `:teacher` only |
| Create/edit classroom | `:teacher` who owns the classroom only |
| View classroom roster | `:teacher` who owns the classroom only |

No admin override on these checks — admins use their own separate tooling to manage relationships directly in the context.

---

## 10. Progress feedback (mandatory)

Both the single invite and bulk import must satisfy the project's **mandatory progress feedback rule**:

- **Single invite**: After submission, show a transient success state ("Invite sent to student@email.com") within the same LiveView. No separate loading state needed — the operation is fast.
- **Bulk import**: MUST show real-time progress. Subscribe to `PubSub.topic("bulk_import:#{import_id}")` and render a progress bar: "Processed 12 of 32 invites…" with the last processed email shown. On completion, show a summary card with counts and a downloadable error CSV if any rows failed. **Never** use a timer-based poll — use PubSub.

See `.claude/rules/i/progress-feedback.md` and `docs/i/ui-design/progress-feedback.md` for the pattern.

---

## 11. Teacher onboarding wizard — update

The existing `TeacherOnboardingLive` captures class name, period, subject, school year but does NOT persist them. Update the wizard to:

1. On completion of the class details step, call `Classrooms.create_classroom/2` and store the returned `classroom_id` in the wizard state.
2. In the "add students" step (currently stubbed), wire the email invite and bulk import flows from §4 and §5.
3. After adding students (or skipping), redirect to `/teacher/classrooms/:id`.

**Do not rebuild the wizard from scratch.** Patch the three specific gaps above.

---

## 12. Parent onboarding wizard — update

The existing `ParentOnboardingLive` generates `InviteCode` entries (parent generates a code, student claims it). That code-based flow remains valid. Add a second path:

1. After "your info" step, present two options side by side:
   - **"I know my child's email"** → email invite form (§3)
   - **"Let my child scan a code"** → existing code generation flow
2. Either path completes onboarding.

The code-based path (existing) and the email-invite path (new) produce different `StudentGuardian` records but the same eventual outcome (active link). Both are valid for families with different technical comfort.

---

## 13. Acceptance criteria

### Parent flow

- [ ] A logged-in parent can enter a student's email and send an invite
- [ ] A student with an existing account sees the invite in `/guardians` inbox and can accept or decline
- [ ] A student without an account receives an email, registers, and claims the invite
- [ ] After acceptance, parent sees child in `/parent` dashboard
- [ ] Parent can view list of all their linked students (active, pending, declined)
- [ ] Parent can resend a pending invite
- [ ] Parent can revoke an active link
- [ ] Student can revoke a guardian link from their side
- [ ] A student can have two active parent links simultaneously

### Teacher bulk import

- [ ] Teacher can upload a CSV or XLSX file with at least `email` column
- [ ] File is validated before submission (invalid emails flagged inline, not after processing)
- [ ] Processing happens asynchronously; LiveView shows real-time progress via PubSub
- [ ] On completion, teacher sees: N invites sent, N already linked, N failed (with reasons)
- [ ] Failed rows are downloadable as a CSV
- [ ] A template CSV is downloadable before upload
- [ ] Duplicate emails (already linked) are silently skipped, not counted as errors

### Teacher single invite

- [ ] Teacher can add a student by email from the classroom roster page
- [ ] Student receives appropriate email (different wording from parent invite)
- [ ] Student can accept or decline
- [ ] Teacher sees real-time status update in the roster after acceptance

### Classroom management

- [ ] Teacher onboarding wizard persists class details to `classrooms` table
- [ ] Teacher can create, edit, and archive classrooms after onboarding
- [ ] Each classroom has its own student roster
- [ ] A student can appear in multiple classrooms (different teachers)

---

## 14. Open questions (resolve before coding)

1. **Email ownership for minors.** If a student is under 13, they may not have a personal email — parents often control the inbox. Should we support a "parent's email on behalf of child" path, or require a student-owned email? **Recommended default:** require student to have their own login; flag during onboarding if the student email matches a parent's existing account.

2. **Classroom deletion.** When a teacher archives or deletes a classroom, what happens to the `student_guardians` rows? Soft-delete the classroom (`archived_at`), set `classroom_id = NULL` on related rows, or cascade-delete? **Recommended default:** soft-delete classroom only; preserve `student_guardians` links (teacher retains access to those students' data even after the class ends, for final reporting).

3. **Teacher invite: subject-scoped or cross-subject?** A student could have two different teachers (Math and Science). Each gets their own `StudentGuardian` row. Teachers should only see their own classroom's students, not all students who listed the school. Confirm this matches product intent.

4. **FERPA / COPPA.** Does FunSheep currently have a COPPA compliance flow for students under 13 (parental consent to collect data)? The guardian-initiated flow where a parent adds a child could be interpreted as the parent granting consent. Legal review recommended before launch.

5. **Google Classroom / Clever rostering.** The teacher experience doc notes this is a top practitioner request. Out of scope for this prompt but flag it: a bulk-import CSV today, a Clever/Google Classroom OAuth integration later. Design the `BulkInviteImport` table to support a `source` column (`csv | xlsx | google_classroom | clever`) so the pattern can be extended.

---

## 15. Implementation order

Implement in this sequence to avoid blocking dependencies:

1. **Migrations** — `initiated_by` column on `student_guardians`, `classrooms` table, `classroom_id` FK on `student_guardians`, `bulk_invite_imports` table
2. **Context functions** — `Accounts.invite_student_by_guardian/3`, `claim_student_invite_by_token/2`, `resend_guardian_invite/1`; `Classrooms` context (CRUD)
3. **Oban workers** — `StudentInviteEmailWorker`, `BulkInviteWorker`
4. **Email templates** — 4 templates listed in §8
5. **Parent manage students UI** — `ParentStudentManageLive` (single invite + list)
6. **Student claim page** — `StudentInviteClaimLive` at `/student-invite/:token`
7. **Teacher classroom UI** — `TeacherClassroomLive` (CRUD) + `TeacherClassroomStudentsLive` (roster + single invite)
8. **Bulk import UI + worker** — `TeacherClassroomStudentsLive :import` action + `BulkInviteWorker`
9. **Patch onboarding wizards** — Parent wizard (add email-invite path); Teacher wizard (persist classroom)
10. **Tests** — Context unit tests (invite, claim, revoke, resend, duplicate detection); LiveView tests; email job tests
