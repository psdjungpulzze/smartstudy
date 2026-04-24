# FunSheep — "Parent" Experience: Implementation Prompt

> **For the Claude session implementing this feature.** Read the entire document before writing any code. The persona research and design principles are load-bearing; skipping them will produce a creepy surveillance product instead of a powerful, defensible one.

---

## 0. Project context (what FunSheep is)

FunSheep is a Phoenix 1.7 / Elixir / LiveView test-prep product for K–12 students. The stack:

- **Repo**: `/home/pulzze/Documents/GitHub/personal/funsheep`
- **Web**: `FunSheepWeb.*` under `lib/fun_sheep_web/`
- **Business contexts**: `FunSheep.Accounts`, `FunSheep.Courses`, `FunSheep.Questions`, `FunSheep.Assessments`, `FunSheep.Engagement`, `FunSheep.Gamification`
- **Auth**: delegated to Interactor Account Server (JWT in session; `current_user["interactor_user_id"]`); local `user_roles` table maps to Interactor identity
- **Roles** (`user_roles.role`): `:student | :parent | :teacher | :admin`
- **Background jobs**: Oban (queue defined; existing workers are all content-generation, no notification workers yet)
- **Mailer**: `FunSheep.Mailer` (Swoosh)
- **UI**: Tailwind, must follow `.claude/rules/i/ui-design.md` — pill-shaped buttons/inputs (`rounded-full`), cards `rounded-2xl`, primary green `#4CD964`, outlined icons stroke-width 1.5

You MUST read these project rules before coding:

- `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md` — especially **ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT**
- `.claude/rules/i/ui-design.md` — design tokens
- `.claude/rules/i/code-style.md` — Elixir/Phoenix style
- `.claude/rules/i/visual-testing.md` — Playwright verification is mandatory before marking UI tasks complete
- `.claude/rules/i/security.md` — auth/authorization patterns

---

## 1. What already exists (do NOT rebuild)

| Concern | Where | Notes |
|---|---|---|
| Parent-child relationship | `FunSheep.Accounts.StudentGuardian` schema + `student_guardians` table | Columns: `guardian_id`, `student_id`, `relationship_type (:parent \| :teacher)`, `status (:pending \| :active \| :revoked)`, `invited_at`, `accepted_at` |
| Invite flow | `FunSheepWeb.GuardianInviteLive` at `/guardians` | Parent sends email invite; student accepts. **Keep and extend.** |
| Parent dashboard (v1) | `FunSheepWeb.ParentDashboardLive` at `/parent` | Shows linked students, upcoming tests (90d), aggregate readiness, trend, percentile, weakest chapter, activity summary, gamification. **Keep and extend** — do not start from scratch. |
| Readiness engine | `FunSheep.Assessments.readiness_calculator`, `list_upcoming_schedules/2`, `latest_readiness/2`, `readiness_trend/2`, `readiness_percentile/2` | Re-use; do NOT duplicate logic |
| Activity summary | `FunSheep.Engagement.StudySessions.parent_activity_summary/1` | Re-use |
| Gamification summary | `FunSheep.Gamification.dashboard_summary/1` | Re-use |
| Shareable proof card | Existing `/share/progress/:token` route | Re-use; add parent-initiated share |

**Before implementing any feature below, grep for existing functions that may already cover it.** If a helper exists, extend it rather than adding a parallel path.

---

## 2. Who the parent persona is (research-grounded)

The primary parent persona for FunSheep is a high-involvement, achievement-focused parent — archetypally the "tiger mom" / Asian immigrant parent, but the design generalises to any high-engagement parent (Indian, Eastern European, American high-achievers, etc.).

**Research-backed characteristics of this persona** (sources: Amy Chua, NPR, Kim et al. 2013 *Developmental Psychology*, APA Div 7, Wikipedia *Tiger Parenting*):

1. **Treats the child's academic record as the parent's own report card.** Chinese mothers in Kim et al. explicitly described "my child is my report card."
2. **Views B grades — and middling A grades — as failure.** Expectation is top-decile performance.
3. **Closely monitors academic performance; arranges additional tutorials when scores are judged insufficient.** Surveillance is an expression of care, not a trust violation.
4. **Competitive frame.** Measures success relative to peers, cousins, the children of friends. Percentile and rank are more emotionally salient than absolute score.
5. **Low tolerance for unstructured leisure.** Expects every free hour to be spent on cognitive skill-building.
6. **Needs levers, not just visibility.** Wants to assign more work, not just see that work is insufficient.
7. **Immigrant-context driver.** Many hold memories of gaokao-style single-shot national exams determining life outcomes — the psychological stakes feel existential.

**Critical counter-finding (Kim et al. 2013, N=444 Chinese American families, 8-year longitudinal):**

> Tiger-parented children had **lower GPA** (3.01 HS vs 3.3 for supportive parents), **more depressive symptoms**, greater **alienation from parents**, and **lower sense of family obligation** than supportively-parented peers. The "tiger" approach **underperforms** warm, high-expectation parenting on the very metric it optimises for.

### Design implication — the core tension

If FunSheep builds pure surveillance, we are selling the tiger-mom persona a tool that **harms the student**, who is our actual end user and the person whose experience determines retention, word-of-mouth, and long-term LTV. Build for the parent's felt needs (control, visibility, competitive signal, levers), but channel those needs into behaviours that research shows are **effective** (structured support, autonomy-supportive involvement, warmth), not destructive (yelling, humiliation, micromanagement).

**This is the product strategy in one line:** *Give tiger parents the data and levers they crave, presented in a frame that converts anxiety into effective support instead of hostile pressure.*

If a proposed feature would train a parent to be more abusive, redesign it. If a proposed feature gives the parent what they want **and** nudges them toward supportive behaviour, ship it.

---

## 3. Design principles (non-negotiable)

1. **Parental visibility is earned through student consent.** The existing invite flow is the contract. Never expose a student's data to a guardian whose `student_guardians.status` is not `:active`.
2. **Every data surface has a "why this matters" framing.** Raw numbers alone trigger tiger-mom panic → counterproductive behaviour. A score must be paired with *"this is good / on track / worth a conversation"* language and a *suggested supportive action*.
3. **The parent gets levers, not a lecture.** Don't moralise. Don't hide data. Instead, make the *effective action* the easiest action.
4. **Competitive framing is allowed, but anonymised and statistical.** Percentile against cohort is fine; named leaderboards of classmates are not (the student is the one who has to live with the social fallout).
5. **The student can see everything the parent sees.** No secret surveillance dashboards. If the parent sees "studied only 12 min yesterday," the student knows the parent sees that. This preserves the student's sense of fairness and avoids breaking the core relationship.
6. **Emotional-wellbeing signal is first-class.** If a student's engagement pattern suggests distress (e.g., study minutes spiking but accuracy collapsing, streak maintained only in the 11pm–1am window, self-reported mood dropping), the **parent view dampens the competitive framing and surfaces a supportive-conversation prompt** instead.
7. **No fake data, ever.** Per `CLAUDE.md` absolute rule: if a metric cannot be computed from real student activity, the UI shows "Not enough data yet" — never a plausible-looking fake number.
8. **Visual testing is mandatory.** Every LiveView page you touch or create must be verified via the `visual-tester` agent before you mark the task complete. See `.claude/rules/i/visual-testing.md`.

---

## 4. Feature scope — phased

Deliver in four phases. Each phase must ship as a working, tested, visually-verified slice. Do not start phase N+1 until phase N is shipped and reviewed.

### Phase 1 — Depth & evidence (extend the existing `/parent` dashboard)
Goal: satisfy the parent's surveillance appetite with *real, granular, legible* evidence that what FunSheep is doing is working (or isn't).

### Phase 2 — Benchmarking & forecasting
Goal: answer the two questions a tiger parent actually asks — *"how does my child compare?"* and *"will they hit the target score?"*

### Phase 3 — Levers & accountability
Goal: give the parent the ability to *assign, commit, and follow up* — converting their control urge into structured, student-consented practice plans.

### Phase 4 — Notifications & multi-child household
Goal: keep the parent informed between logins, and support parents with 2+ children.

Details for each phase follow.

---

## 5. Phase 1 — Depth & evidence

### 5.1 Study-activity timeline (new component)

**What**: A scrollable timeline for the selected student showing every `study_session` and `question_attempt` in the last 30 days, with:

- Date, start time (time-of-day band: morning / afternoon / evening / late-night), duration
- Session type (`:review | :practice | :assessment | :quick_test | :daily_challenge`)
- Course / chapter / topic tags
- Questions attempted, % correct
- XP earned
- A one-line *interpretation* of the session (e.g., "Strong — 92% correct on Fractions, a previous weak area" or "Short session — 6 min on Geometry; consider a longer block next time")

**Implementation**:

- New LiveComponent: `FunSheepWeb.ParentLive.ActivityTimeline`
- Data source: `StudySessions.list_for_student_in_window(student_id, days)` — add this function to `FunSheep.Engagement.StudySessions` if it does not exist. Must preload chapter/course via existing associations; do **not** N+1.
- Interpretation line: compute from real session data (session accuracy vs. student's rolling accuracy; duration vs. median; topic vs. latest readiness `chapter_scores`). No hardcoded strings paired to fake data.
- When fewer than 3 sessions in the window: show "Not enough activity yet — encourage your student to start a practice session" (no fake fill).

**UI**: card (`rounded-2xl`), group by day, collapsible. Each session is a row with the interpretation in secondary text. Time-of-day band shown as a small pill (`rounded-full`) — colour-code but subtly (do not red-flag late-night sessions; the system should note them, not shame them).

### 5.2 Time-of-day heatmap

**What**: 7-day × 4-band (morning/afternoon/evening/night) grid showing when the student actually studies, with cell intensity = minutes studied. Helps the parent see patterns (e.g., "studies only right before bed" — a legitimately useful insight for structuring routine).

**Implementation**: Aggregate `study_sessions.time_window` × day-of-week for the last 4 weeks. Component `FunSheepWeb.ParentLive.StudyHeatmap`.

### 5.3 Topic-level mastery map (replaces/extends "weakest chapter")

**What**: For each upcoming test, show a grid of chapters → topics, each cell coloured by mastery (derived from `readiness_scores.chapter_scores` and per-topic attempt accuracy). Click a cell → drill-down modal showing:

- Last 10 question attempts in that topic (question stem preview, correct/incorrect, time taken)
- Chart of accuracy trend on that topic over last 30 days
- "Assign 10 practice questions on this topic" button (lever — Phase 3 wires it up)

**Implementation**: Reuse `FunSheep.Assessments.readiness_calculator`. If topic-level aggregation does not already exist, add `Assessments.topic_mastery_map(student_id, test_schedule_id)` and back it with `question_attempts` grouped by `question.topic`. Do not fabricate topics that don't exist in the data.

### 5.4 Wellbeing signal (quiet but present)

**What**: A small, non-alarming indicator on the student card showing an inferred engagement-health signal, one of: `thriving | steady | under-pressure | disengaged`. Derived **only from real observable signals**:

- `thriving`: streak ≥ 7, accuracy trending up, sessions spread across ≥ 3 time-of-day bands
- `steady`: consistent sessions, stable accuracy
- `under-pressure`: sessions spiking in late-night band, accuracy dropping while minutes increasing
- `disengaged`: no sessions in last 5 days, streak broken, upcoming test within 14 days

**Behaviour**:
- On `under-pressure`, the parent view replaces the competitive-framing copy ("percentile: 78th") with a supportive-conversation prompt ("Your student has been studying longer but accuracy is dipping — often a sign of fatigue. A non-academic check-in may help more than extra practice this week.")
- On `disengaged` with an imminent test, surface a practical prompt ("Short 15-min sessions tend to restart momentum better than a long one — here's a way to suggest one.")

This is the design-principle #6 mechanism. **Do not** build this as a "mental health score" the parent can track as a number; that's creepy and counterproductive. It should only change the *framing* of the rest of the dashboard when triggered.

### 5.5 Acceptance criteria (Phase 1)

- [ ] `/parent` renders the existing v1 content plus: activity timeline, heatmap, topic mastery map, wellbeing-aware framing
- [ ] All data is real — no placeholder sessions, topics, or scores
- [ ] Empty states render correctly for brand-new linked students
- [ ] Tests: LiveView tests for mount, student-switch event, timeline drill-down; unit tests for `topic_mastery_map`, `list_for_student_in_window`, wellbeing classifier
- [ ] Coverage stays ≥ 80% (`mix test --cover`)
- [ ] `mix format --check-formatted`, `mix credo --strict`, `mix sobelow` pass
- [ ] Visual verification via `visual-tester` agent at 375px / 768px / 1440px, light and dark modes

---

## 6. Phase 2 — Benchmarking & forecasting

### 6.1 Percentile, rank, and cohort context (extend existing `readiness_percentile/2`)

**What**: For each upcoming test, show:

- Percentile vs. same-grade cohort within FunSheep (already exists — make it prominent)
- Percentile trend over last 4 weekly snapshots (sparkline)
- "Target score" — parent and student can jointly set a target readiness score (see Phase 3); show current vs. target with days-until-test context

**Implementation**: Add `Assessments.readiness_percentile_history(student_id, test_schedule_id, weeks)` that returns a list of weekly percentile snapshots. Back it with real readiness data; if fewer than 2 snapshots exist, render "Check back next week — we'll show trend once we have two weekly snapshots."

### 6.2 Readiness forecast

**What**: A forecast card: *"At current pace, projected readiness by test day: 84% (target: 90%). To hit target, roughly 25 more min/day of practice on the two weakest chapters."*

**Implementation**:

- New module `FunSheep.Assessments.Forecaster`
- Input: recent readiness trajectory (`readiness_trend/2`), practice minutes/day over last 14 days, days until `test_schedule.test_date`
- Output: projected readiness, gap to target, recommended daily-minute delta
- Keep the model simple and interpretable (linear projection of recent readiness slope is fine) — this is a product signal, not a research claim. Show the confidence qualitatively ("wide range — not enough history yet" vs "tight — based on 6 weeks of consistent practice").
- If inputs are insufficient (e.g., <14 days of data or no target set), the card shows "Set a target score to see a forecast" — not a fabricated number.

**Copy pattern**: Always frame the delta as a *suggestion of a behaviour change*, never as a judgement. "25 more min/day would close the gap" is fine; "your child is behind" is not.

### 6.3 Peer-comparison card (anonymised)

**What**: A single card showing, for the student's grade and course:

- This student's readiness vs. the 25th / 50th / 75th / 90th percentile within FunSheep's same-grade same-course cohort
- Honest about cohort size — if cohort < 20 students, say so and suppress sub-percentile granularity

**Implementation**: `Assessments.cohort_percentile_bands(course_id, grade)` — compute in Elixir, cache via ETS with short TTL (15 min) to avoid hammering the DB on every parent-dashboard mount.

**Forbidden**: named leaderboards ("Sarah ranked #3 in Ms. Park's 6th-grade class") — that breaks design principle #4 and would weaponise the student's social life.

### 6.4 Acceptance criteria (Phase 2)

- [ ] Percentile + trend sparkline + target visible on upcoming-test card
- [ ] Forecaster returns real projections from real data; shows "not enough history" when inputs insufficient
- [ ] Peer-comparison card renders at cohort ≥ 20; falls back to "small cohort — comparison hidden" otherwise
- [ ] No named peers exposed anywhere
- [ ] Tests: unit tests for `Forecaster`, `cohort_percentile_bands`, `readiness_percentile_history`; LiveView tests for the cards rendering correctly in empty / partial / full data states
- [ ] Visual verification

---

## 7. Phase 3 — Levers & accountability

This is the heart of the tiger-mom value prop. Watch the framing carefully.

### 7.1 Joint goal-setting (parent + student)

**New schema** — create a migration:

```
study_goals
  id (uuid)
  student_id -> user_roles.id
  guardian_id -> user_roles.id (the parent who initiated)
  course_id -> courses.id (nullable — "all courses" allowed)
  test_schedule_id -> test_schedules.id (nullable)
  goal_type :: enum(:daily_minutes, :weekly_practice_count, :target_readiness_score, :streak_days)
  target_value :: integer
  start_date :: date
  end_date :: date (nullable for open-ended)
  status :: enum(:proposed, :active, :paused, :achieved, :abandoned)
  proposed_by :: enum(:guardian, :student) -- who initiated
  accepted_at :: utc_datetime (nullable — null until the other party accepts)
  created_at, updated_at
```

**Flow**:
1. Parent proposes a goal from the parent dashboard ("40 min/day, weekdays, until May 15 test")
2. Student sees a pending-goal notification on the student dashboard and can Accept, Counter-propose, or Decline with a reason
3. Only `:active` goals count toward tracking; `:proposed` goals do not appear as commitments
4. Progress is computed daily against real `study_sessions` / `question_attempts` — never backfilled

**Why the counter-propose**: research shows **autonomy-supportive** parental involvement (Grolnick et al.) outperforms directive involvement on academic outcomes. The counter-propose mechanism is the product-level translation of that finding — the parent gets a lever, but it passes through a negotiation that converts the dynamic from directive to collaborative.

**Module**: `FunSheep.Accountability` context — `propose_goal/2`, `accept_goal/2`, `counter_goal/3`, `list_active_goals/1`, `goal_progress/1`.

### 7.2 Parent-assigned practice (bounded)

**What**: From a topic-mastery drill-down (Phase 1.3), the parent can click "Assign 10 practice questions on Fractions." This creates a **`practice_assignment`** that:

- Appears on the student's dashboard as a tagged-by-parent practice set
- Pulls real questions from the existing question bank (weighted to the assigned topic and the student's last known difficulty band — reuse the existing practice engine)
- Has a soft due date (default: 3 days)
- Completion is tracked and visible on the parent dashboard

**Bound**: a parent can have at most **3 open assignments** per student at a time, and an assignment can be at most 20 questions. Rationale: without these bounds, the feature becomes a weapon. With them, it encodes "parent can nudge, not flood."

**Schema**:

```
practice_assignments
  id
  student_id, guardian_id, course_id, chapter_id (or topic ref)
  question_count :: integer (max 20)
  due_date :: date
  status :: enum(:pending, :in_progress, :completed, :expired)
  completed_at, created_at, updated_at
```

Questions for an assignment are resolved at session-start time via the existing practice engine — do **not** denormalise a question list into this table (topics mutate; difficulty adapts).

### 7.3 Follow-up conversation prompts

**What**: Instead of raw "your child missed 3 sessions this week" alerts, the dashboard surfaces a *conversation prompt card*:

> "Sarah has practised 2 out of 5 planned days this week on the May 15 Algebra test. This often reflects scheduling friction, not motivation. A good opening: *'What's been hardest about getting started this week?'* — research shows open questions outperform directives here."

The prompt is generated from real goal-adherence data and is parameterised (student name, metric, target, suggested opener). The **opener suggestion** is the Trojan horse for design principle #3 — the easiest thing for the parent to do is the supportive thing.

**Do not** auto-send these to the student. They are scripts for the parent.

### 7.4 Acceptance criteria (Phase 3)

- [ ] `study_goals` and `practice_assignments` migrations run cleanly; `mix ecto.rollback` is safe
- [ ] Parent can propose / student can accept / counter / decline — full round trip tested with LiveView tests
- [ ] `goal_progress/1` reflects real activity; no fill data
- [ ] Assignment caps (3 open, 20 questions) enforced with clear error copy
- [ ] Conversation prompts render from real data; fallback when insufficient
- [ ] Coverage ≥ 80%, all lints pass, visual verification at all viewports

---

## 8. Phase 4 — Notifications & household

### 8.1 Weekly parent digest (Oban + Swoosh)

**What**: Every Sunday 6pm local (use student's timezone, fall back to UTC), email each guardian a per-student digest:

- Practice minutes (vs goal if any)
- Readiness change this week
- Top improvement area + top concern area
- One conversation prompt (from §7.3)
- Upcoming tests within 14 days

**Implementation**:

- New Oban worker: `FunSheep.Workers.ParentDigestWorker` in a new `:notifications` queue
- Cron via `Oban.Plugins.Cron` configured in `application.ex`; schedule one row per active guardian-student pair via a scheduler job (do not statically schedule — use a scheduler that enqueues per-recipient jobs)
- Swoosh template: `FunSheepWeb.ParentEmail.weekly_digest/2`
- Guardian must be `status: :active`; honor a `digest_frequency` preference on `user_roles.metadata` (`:weekly | :off`) — default `:weekly`

### 8.2 Actionable alerts (opt-in)

**What**: Short-circuit alerts (email) for specific events, gated behind explicit opt-in:

- Student skipped scheduled study days (≥ 3 consecutive days with an active `:daily_minutes` goal)
- Readiness dropped by > 10% week-over-week within 21 days of a test
- Goal achieved (celebratory — ship this one; positive reinforcement is the single behaviour all the research agrees works)

**Defaults**: all off, except `goal_achieved` which is on by default. The parent turns surveillance alerts on themselves — we don't push them.

### 8.3 Multi-child household view

**What**: If a guardian is linked to ≥ 2 students, the `/parent` route shows a household overview first (side-by-side cards), with a drill-down into any single student's dashboard. The single-student view is the existing `/parent` page in selected-student mode.

**Implementation**: same LiveView, branch on `length(students) >= 2` to render overview vs single. Already partially there — formalise it.

### 8.4 Acceptance criteria (Phase 4)

- [ ] Digest worker sends real digests to real guardian emails in dev (use `Swoosh.Adapters.Local` to preview at `/dev/mailbox`)
- [ ] Alerts opt-in UI on `/parent/settings` (new route)
- [ ] Multi-child overview renders correctly at N=0, 1, 2, 5
- [ ] Unsubscribe link in every email honours a signed token; no auth required to unsubscribe
- [ ] Tests: worker test with `perform/1`, email rendering tests, LiveView tests for settings page
- [ ] Visual verification of email at desktop and mobile widths (Swoosh preview)

---

## 9. Cross-cutting technical requirements

### 9.1 Authorization

Every data-fetching function called from a parent context MUST check that the requesting `guardian_user_role_id` is linked to the target `student_user_role_id` via a `student_guardians` row with `status: :active`. Centralise this in `FunSheep.Accounts.guardian_has_access?/2` and call it at the edge of every context function that takes a `student_id` in a parent flow. Do not trust the LiveView to enforce it.

### 9.2 Query performance

- Add indexes on `study_sessions(user_role_id, completed_at)`, `question_attempts(user_role_id, inserted_at)`, `readiness_scores(user_role_id, test_schedule_id, calculated_at)` if not already present
- Preload associations in the context layer; do not let LiveView trigger N+1
- Cohort percentile computation (§6.3) must use ETS or Cachex with 15-min TTL keyed on `{course_id, grade}`

### 9.3 Timezone

Parents and students may be in different timezones. Prefer student timezone for "today / this week" boundaries and study-heatmap day bucketing. Add a `timezone` column to `user_roles` if it isn't there; default from the browser on first login. All times rendered in parent UI: explicitly label "student local time."

### 9.4 Internationalisation

Copy will eventually need Korean / Chinese translation (this is the persona). Wrap all user-facing strings in `gettext` from the start. Do not hardcode English literals.

### 9.5 Testing requirements

Per `CLAUDE.md`:

- Every LiveView you create or modify must have a `*_test.exs` file covering mount, every `handle_event/3`, and rendering in at least: unauthenticated, authorised-parent-with-students, authorised-parent-with-no-students, student-mistakenly-visiting states.
- Every context function must have unit tests.
- `mix test --cover` overall coverage must remain ≥ 80%.
- Before marking any phase complete, launch the `visual-tester` agent to verify the changed pages at mobile / tablet / desktop in light and dark mode.

### 9.6 Commits and branching

- Work in `feature/parent-experience-<phase>` branches
- One PR per phase, not one giant PR
- Commit prefixes: `feat(parent):`, `test(parent):`, `refactor(parent):`
- The project has `smartstudy` as origin, not `product-dev-template` — if git push targets the wrong remote, stop and ask. (There is prior context about a leak incident on the wrong remote.)
- Do not bypass pre-commit hooks (no `--no-verify`)

### 9.7 What you must NOT do

- Do **not** seed fake students, fake sessions, fake questions, or fake scores to make the parent dashboard "demo well." Per `CLAUDE.md` absolute rule: if there's nothing to show, show the empty state.
- Do **not** add named-peer leaderboards visible to parents.
- Do **not** create a "secret" parent view that shows the student data the student can't see themselves.
- Do **not** wire unbounded parent-assigned practice (enforce the §7.2 caps).
- Do **not** `mix compile` while a dev server is running — the Phoenix live-reloader handles recompilation.
- Do **not** start a test server on port 4040; use `./scripts/i/visual-test.sh start` to get an isolated port.

---

## 10. Before you start

1. Start a todo list with `TaskCreate` containing the four phases as parent tasks and each numbered section (5.1, 5.2, …) as a child task. Mark one `in_progress` at a time.
2. Read, in order:
   - The existing `ParentDashboardLive` (`lib/fun_sheep_web/live/parent_dashboard_live.ex`) and its `.heex` partner if separate
   - `FunSheep.Accounts.StudentGuardian` and `FunSheep.Accounts` public functions beginning `list_students_for_guardian`, `invite_guardian`, `accept_guardian_invite`, `guardian_has_access?`
   - `FunSheep.Assessments` — `list_upcoming_schedules`, `latest_readiness`, `readiness_trend`, `readiness_percentile`
   - `FunSheep.Engagement.StudySessions` — `parent_activity_summary`
   - The router: `lib/fun_sheep_web/router.ex` for the `:authenticated` live_session
3. Confirm the dev environment runs: `mix deps.get && mix ecto.setup && iex -S mix phx.server`. If the DB is empty, create a couple of real test users (student + parent) via the existing auth flow and run a real practice session so you have real data to render against — never seed fake activity.
4. Pick Phase 1 and start with §5.1 (activity timeline). Extract any shared helpers you'll need before you start on §5.2.

---

## 11. What "done" looks like (whole project)

- The `/parent` experience ships the four phases above, each behind a code review and visual verification gate.
- A parent with one linked student who has been actively using FunSheep for ≥ 2 weeks sees: timeline, heatmap, topic mastery map, forecast, percentile trend, any active goals and assignments, and a wellbeing-aware framing.
- A parent with a newly linked student sees honest empty states that explain what they'll see once there's data — no fake content.
- A parent receives a real weekly digest email summarising real activity.
- A parent can propose a goal; the student can accept or counter-propose.
- Tests: coverage ≥ 80%, LiveView tests for every parent-facing route.
- No named-peer data is ever exposed.
- The `/share/progress/:token` proof card continues to work and can be initiated by the parent.

If at any point during implementation a feature starts to feel like it's optimising for the parent's control at the expense of the student's wellbeing, stop and re-read §2 and §3 — the tension is the product. Ship the lever, but with the guardrail.

---

## 12. Questions to ask before starting

If any of the following are unclear after reading the code, ask the user before writing any implementation:

1. Is there a specific target launch date or milestone this feature is tied to? (Affects phase prioritisation.)
2. Is there existing user research / analytics on current `/parent` usage — which parts are used, which are not?
3. Is a "student-has-seen-this" acknowledgement required for parent-assigned practice, or is visibility on the student dashboard sufficient?
4. Does FunSheep already have a notion of "target score" for a test, or is §6.1 introducing it for the first time?
5. Is the project using Cachex, ETS, or neither for in-process caching? (Affects §6.3 and §9.2.)

Answer these, then begin Phase 1.
