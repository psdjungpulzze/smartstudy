# FunSheep — Subscription Purchase Flows: Implementation Prompt

> **For the Claude session implementing this feature.** Read the whole document before coding. The conversion-psychology framing in §2 and §8 is load-bearing — skipping it produces a generic paywall that converts at industry baseline instead of the tiger-mom-amplified rate this product can realistically achieve.

---

## 0. Project context

FunSheep is a Phoenix 1.7 / Elixir / LiveView test-prep product. Stack and rules (same as sibling prompts):

- **Repo**: `/home/pulzze/Documents/GitHub/personal/funsheep`
- **Web**: `FunSheepWeb.*` under `lib/fun_sheep_web/`
- **Roles** (`user_roles.role`): `:student | :parent | :teacher | :admin`
- **Auth**: Interactor Account Server
- **Billing**: Interactor Billing Server (mandated — see `.claude/rules/i/interactor-integration.md`: "Use Interactor First — Do NOT Reinvent")
- **Jobs**: Oban
- **Mailer**: `FunSheep.Mailer` (Swoosh)
- **UI**: Tailwind per `.claude/rules/i/ui-design.md` — pill controls (`rounded-full`), cards `rounded-2xl`, primary green `#4CD964`

You MUST read these project rules before coding:

- `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md` — especially the absolute rule on no fake content
- `.claude/rules/i/ui-design.md`
- `.claude/rules/i/interactor-integration.md` — **do NOT build a parallel billing system; extend the Interactor Billing wrapper**
- `.claude/rules/i/code-style.md`
- `.claude/rules/i/visual-testing.md` — Playwright verification is mandatory
- `.claude/rules/i/security.md`

Also read, if they exist, the sibling prompts in this same directory:
- `~/s/funsheep-parent-experience.md`
- `~/s/funsheep-teacher-experience.md`

---

## 1. What already exists (do NOT rebuild)

| Concern | Where | Notes |
|---|---|---|
| Billing context | `FunSheep.Billing` (344 lines) | `get_or_create_subscription/1`, `create_checkout/4`, `activate_subscription/2`, webhook entry points. Re-use. |
| Interactor Billing client | `FunSheep.Interactor.Billing` (411 lines) | Thin HTTP wrapper over Interactor Billing Server. Add methods if needed; do not fork. |
| Subscription schema | `FunSheep.Billing.Subscription` | `plan ∈ {free, monthly, annual}`, `status ∈ {active, cancelled, past_due, expired}`, unique on `user_role_id`. |
| Test-usage tracking | `FunSheep.Billing.TestUsage` | Per-test-completion row; `test_type ∈ {quick_test, assessment, format_test}`. Re-use for metering. |
| Subscription page | `FunSheepWeb.SubscriptionLive` (959 lines) — route `/subscription` | Full plan picker + checkout redirect. Re-use; extend with new entry points but do not fork. |
| Billing components | `FunSheepWeb.BillingComponents` | Re-use. |
| Webhook controller | `FunSheepWeb.WebhookController` | Receives Interactor billing events; activates/cancels subscriptions. |
| Guardian invite flow | `FunSheepWeb.GuardianInviteLive` at `/guardians` + `FunSheep.Accounts.StudentGuardian` | Parent↔student (and teacher↔student) linking. Re-use for Flows B and C. |
| Class invite (Teacher) | `FunSheep.Classrooms` (if Teacher prompt Phase 1 is shipped) | Teacher→student linking. If not yet shipped, use `student_guardians` for now. |

### The existing free-tier economics (from `FunSheep.Billing` module docstring)

- **50 initial free tests (lifetime)**
- **20 free tests per week (rolling 7-day window)**
- Paid plans: **$30/month** or **$90/year** — both unlimited
- Students are the metered role; parents/teachers/admins are free (they don't take tests)

**Do not change these numbers without a product-level decision.** If they need to change, surface the question in §13 before coding.

### What's missing

1. **Student → parent "ask" bridge.** The existing `/subscription` page lets whoever is logged in check out. There's no flow for "student hits wall → parent gets request → parent converts."
2. **Parent-initiated child onboarding + optional upfront purchase.** Parents can sign up and invite via `/guardians`, but there's no narrative flow that positions purchase at the right moment.
3. **Teacher-initiated flow where students stay on free tier.** The plumbing exists (class invites, student activation) but no explicit "teacher path" UX that makes the teacher's no-purchase role clear.
4. **Soft-wall copy, usage meter, gentle escalation.** The existing paywall is a hard-wall. We need soft / hard-wall UX tuned to the three personas.
5. **A payer-vs-beneficiary model.** Today `Subscription.user_role_id` is the beneficiary. When a parent pays for a student, we need to record the payer. Add a nullable `paid_by_user_role_id`.

---

## 2. Strategy: three flows, one conversion engine

### 2.1 The three flows at a glance

| Flow | Initiator | Who pays | Primary conversion moment |
|---|---|---|---|
| **A. Student-initiated (upsell)** | Kid | Parent | Kid hits ~85% of weekly limit → asks parent → parent converts in email/in-app |
| **B. Parent-initiated** | Parent | Parent | Parent signs up, invites child, **may** convert upfront or wait for kid's first "ask" |
| **C. Teacher-initiated** | Teacher | **No one** (teacher doesn't pay; student stays on free unless parent converts) | Student adoption via classroom context; conversion only happens if Flow A triggers later |

### 2.2 Why Flow A is the growth engine

The three flows share a conversion endpoint, but Flow A is where the product's structural advantage lives. Here's why:

- **Most EdTech freemium-to-paid conversion is parent-initiated** (parent reads reviews, decides to buy, pushes kid to use). This has industry-baseline conversion rates and parent/kid motivation misalignment — parent wants it, kid resents it.
- **FunSheep can flip the flow**: the kid asks for more practice. When the kid asks an anxious, academically-invested parent for *more studying*, the parent is presented with an emotional/behavioural surplus no other EdTech product generates.
- **Tiger-mom / high-investment-parent personas (see `funsheep-parent-experience.md` §2) treat their child's academic effort as their own report card.** A kid *asking to practice more* is the event that parent persona is wired to reward. It bypasses every normal purchase objection (cost, value, trust).
- **The moment is rare and time-bounded.** If we surface the request well and close the conversion in a tight loop (same evening, one tap), we capture it. If we delay or frame it poorly, the moment evaporates.

This reframes the problem: **don't design a paywall. Design a "child asks parent for more study" moment, and let the paywall be the way the parent says yes.**

### 2.3 Ethical guardrail (tied to the Parent experience doc)

The Parent experience prompt establishes a core ethical principle: tiger-mom surveillance empirically harms students (Kim et al. 2013 — lower GPA, more depression, more alienation). We do not want this feature to become part of that harm.

The conversion loop is **only valid when it fires on a real, voluntary, positive student behaviour** (the kid actually wanted to do more practice and hit the wall). We do **not**:

- Fabricate or simulate student requests
- Encourage the student to send a request they don't want to send
- Add dark-pattern "oops" request buttons that get tapped accidentally
- Re-prompt an irritated student who just dismissed the ask
- Surface conversion friction as shame to the student
- Use the conversion as a gate on a legitimate educational need the student can't get past without paying (keep enough free capacity that a motivated student can do meaningful work for free — 20/week already satisfies this)

If any design choice during implementation starts to look like manufacturing consent from the student to manipulate the parent, **stop and re-read this section**.

---

## 3. Design principles (non-negotiable)

1. **Parent pays, student benefits, teacher doesn't pay.** `Subscription.user_role_id` is always the student. Add `paid_by_user_role_id` nullable → points to the parent (or student themselves, for self-purchase). Teachers never appear as payer.
2. **The request is the product, the paywall is the receipt.** Design for the *moment of asking*, not the moment of paying. The paywall UI is a thin layer over the Interactor Billing checkout — most of the conversion design goes into the request → parent-notification → decision moment.
3. **Meter is always visible, never scary.** Students see their usage meter continuously, framed positively ("8 of 20 practice questions this week — you're building a streak"), not as a depleting counter.
4. **Soft wall before hard wall.** At 70% show a cheerful heads-up. At 85% show the "Ask a grown-up" card. Only at 100% do we block.
5. **One-tap ask, one-tap accept.** Kid sends request in ≤2 taps. Parent converts in ≤3 taps from email. Anything more kills the moment.
6. **Time-bound requests (7 days).** A request older than 7 days is stale — mark it expired, let the kid re-request after a cooldown. Avoids nag fatigue and stale-pending clutter.
7. **Transparency to all parties.** Student sees whether the parent viewed/decided. Parent sees what the student requested and why. Teacher sees neither — billing is none of their business.
8. **Never fake data.** If a kid hasn't actually hit 85%, don't show the ask card. If a parent has no linked students, don't show the "your kid requested" email ever. Per `CLAUDE.md` absolute rule.
9. **Honest pricing.** Always show monthly AND annual side by side. Never hide the cancel-anytime link. Never auto-convert a trial without a clear, unmissable pre-notice.
10. **Visual testing mandatory.** Per `.claude/rules/i/visual-testing.md`.

---

## 4. Flow A — Student-initiated (the upsell flow)

This is the feature that will disproportionately drive revenue. Spend the most design effort here.

### 4.1 Usage meter (always-on, ambient)

**Where**: Persistent pill in the student app bar (visible on every authenticated student page). On the student dashboard, a larger card.

**States**:

| Usage | Pill copy | Tone |
|---|---|---|
| 0–50% (0–10 of 20) | "🐑 10 free practice left this week" | Neutral/positive |
| 50–70% (10–14) | "🐑 6 free practice left — nice streak" | Encouraging |
| 70–85% (14–17) | "🐑 3 left this week — great momentum" | Light nudge; dashboard shows soft pre-prompt |
| 85–99% (17–19) | "🐑 1 left — ask a grown-up for more?" | Ask-card unlocks on dashboard |
| 100% (20/20) | "🌿 Weekly practice complete — unlock more?" | Soft hard-wall: cannot start new practice, but can review completed work |

**Do not**: call it a "limit," "quota," "paywall," or show red/warning colours. Frame as a positive boundary ("complete," "left") until the hard wall, and even there stay encouraging.

**Implementation**: extend `FunSheep.Billing` with `weekly_usage/1` returning `%{used: n, limit: 20, remaining: m, resets_at: datetime}`. Render as a LiveComponent `FunSheepWeb.BillingComponents.UsageMeter` reused on the app bar and dashboard. Re-use existing `TestUsage` data; do not add a parallel counter.

### 4.2 Soft pre-prompt at 70%

At 14 of 20, the student dashboard surfaces a small card: *"You're on a 🔥 roll this week! Want unlimited practice? Send Mom or Dad a quick ask — they'll love it."* with a single "Ask a grown-up" button.

The card is **dismissible** with a "Not yet" link that hides it until the next threshold (85%). Respect dismissal.

### 4.3 The Ask card at 85%

Bigger, more prominent card on the dashboard. Copy draft (tune with PM):

> **Almost at your weekly free practice 🦁**
>
> You're clearly into this. Want unlimited practice for the rest of the term?
>
> It takes one tap to ask your parent — and research shows *parents love it* when their kid asks for more practice.
>
> *(They really do. This is one of those rare parent-wins. Use it wisely.)*
>
> [💚 Ask a grown-up]

The dry-humour parenthetical is deliberate — it signals to the kid that we know what we're doing and defuses any "this is cheesy" reaction.

### 4.4 The request-builder modal

Opens when the student taps the ask button. Ultra-short form — **≤2 taps to send**:

1. **Pick a grown-up** — a radio list of linked guardians. If only one linked guardian: auto-selected. If none: fallback to the "invite a grown-up" flow (§4.8).
2. **Pick a reason** — 3–4 pre-written one-liners (no free-text required; free-text optional). Reason copy should give the parent receiver emotional ammunition, so write them to double as parent-persuasion:
   - "I want to ace my [test name] on [date]"
   - "I'm working on [weakest topic] and want to get it right"
   - "I'm on a streak and I want to keep going"
   - "Other" (free-text, 140 char max)
3. **Send** — single green button. Also shows: "Your grown-up will get an email + a notification in the app."

After send: confetti animation (short — 800ms), then a friendly waiting state (§4.5).

**Copy around the send button for the kid** (very important for priming):

> *"Your parents will love this. Parents literally post on social media when their kid asks for more practice. Hit send. 🦁💚"*

### 4.5 Student "waiting" state

Dashboard shows a small card:

> **Request sent to Mom 💌**
>
> *Sent 3 minutes ago — typically answered within a few hours.*
>
> *You can keep reviewing what you've already done while you wait.*

If still pending after 24h: softer nudge card *"No rush — your grown-up hasn't opened this yet. You could remind them nicely."* with a "Send a reminder" secondary button (max 1 reminder per request).

If pending beyond 7 days: the request auto-expires; the student sees *"This request expired — feel free to send a new one."*

**Do not** badge or notify excessively. One reminder max. Respect the student's patience and avoid training them to see the app as pestery.

### 4.6 Parent notification (the moment that converts)

Two channels fire simultaneously when the student sends a request:

#### 4.6.1 Email (the primary conversion channel)

Sent via `FunSheep.Mailer` / Swoosh; routed through a new `FunSheep.Workers.ParentRequestEmailWorker` Oban job. Respect time-of-day: **do not send between 10pm and 7am local** (parent's timezone, fall back to student timezone if unknown) — hold the job until the send window reopens.

**Subject** (test these; shortlist):
- "{{Student name}} just asked you for more practice 💚"
- "{{Student name}} wants more study time. (Yes, really.)"
- "A rare parent-win in your inbox"

**Body** — see §8 for full copy draft. Summary of what it contains:
- Lead with the behaviour (child asked)
- Show evidence (real activity data: streak, minutes, accuracy, upcoming test)
- The specific reason the child gave
- Pricing comparison (annual is the default recommendation)
- One giant CTA button → checkout
- Honest anti-manipulation: a clear "decline politely" secondary link
- FERPA / privacy note
- Unsubscribe

#### 4.6.2 In-app notification

If the parent has an active session or logs in within the 7-day window, the parent's dashboard surfaces the request as a top-of-page card (see §5.1 for the parent dashboard integration). Same information as the email, single green CTA.

### 4.7 Parent decision → checkout → activation

**Accept path**:
1. Parent taps "Unlock unlimited for {{Student name}}" (email or in-app)
2. Lands on a 1-page confirm screen: plan choice (annual highlighted as best value), price, what's unlocked, "who pays" clarity, cancel-anytime note
3. Tap "Continue to checkout" → Interactor Billing `create_checkout_session` with plan_id and `metadata.student_user_role_id`
4. Stripe checkout completes → webhook fires → `Billing.activate_subscription/2` runs with `user_role_id = student`, `paid_by_user_role_id = parent`, `request_id` stamped into metadata
5. Student immediately unlocked (Oban pushes a PubSub event to student LiveView — if the student is online, the meter updates live and a celebration toast fires)
6. Parent lands on "✅ Unlocked" page with a prompt: "Tell {{Student name}} — they'll be waiting. [Send them a note]"

**Decline path**:
1. Parent taps "Not right now"
2. Lands on a gentle confirm page (not a guilt trip — single screen with "Send a kind note back" option)
3. Student sees: *"Your grown-up saw your request and said maybe later. They left you a note: '...'"* (if parent wrote one) or *"...said maybe later. Keep practising what you have!"* (default).
4. Student request enters `:declined` state; cooldown of 48h before they can re-request.

**Ignore path**:
1. No action within 7 days
2. Request auto-expires
3. Student sees: *"Your grown-up hasn't responded yet — you can send a new ask when you want."*

### 4.8 Edge: student has no linked guardian

If the student has no `student_guardians` row with a guardian, the ask button opens an "invite a grown-up" flow instead:

1. *"First, let's invite your grown-up so we can send them your request."*
2. Enter grown-up email
3. System sends a two-part email to the parent: **(a)** an invite to join FunSheep as the student's guardian, **(b)** a preview of the student's request, activated once they accept the invite.
4. Student sees a waiting state that covers both steps.

### 4.9 Edge: multiple linked guardians

If the student has 2+ linked guardians:
- Request-builder modal defaults to "all grown-ups" but lets the student pick one specifically ("Send to Mom only")
- Both guardians get the email/notification
- First to purchase wins; the other gets a "({{Other parent name}} already handled this — thanks team 💚)" confirmation so no duplicate purchase
- Implementation: checkout idempotency via `request_id` in Interactor Billing metadata; webhook handler short-circuits if subscription for that student is already active.

### 4.10 Edge: student already has an active paid subscription

- The ask card does not surface (it's gated on `!Subscription.paid?(student_sub)`)
- If somehow triggered (race condition), request creation fails gracefully with a friendly "You're already unlimited! 🎉" message.

### 4.11 Acceptance criteria (Flow A)

- [ ] `practice_requests` schema migrated (see §7) and integrated with existing `Subscription` / `TestUsage`
- [ ] Usage meter visible and accurate on every student page
- [ ] Soft pre-prompt at 70%, ask card at 85%, soft hard-wall at 100%
- [ ] Request-builder modal sends in ≤2 taps; stores a `practice_request` row
- [ ] `ParentRequestEmailWorker` dispatches email respecting quiet hours; in-app notification shows on parent dashboard
- [ ] Parent accept path completes checkout via Interactor Billing; webhook activates student subscription with correct `paid_by_user_role_id`
- [ ] Parent decline path records decision and routes message to student
- [ ] 7-day auto-expire Oban job (`RequestExpiryWorker` running hourly) transitions stale requests
- [ ] Tests: LiveView tests for every state (below threshold / above / pending / accepted / declined / expired); worker tests for email + expiry; integration test for the full accept → webhook → unlock loop
- [ ] Coverage ≥ 80%, `mix format`, `mix credo --strict`, `mix sobelow` pass
- [ ] Visual verification at 375/768/1440 light+dark, for student, parent email (via Swoosh dev mailbox), and parent in-app surfaces

---

## 5. Flow B — Parent-initiated

Simpler flow. Most of the plumbing already exists; the work is connecting existing pieces into a clean narrative.

### 5.1 Entry points

- Marketing site → "I'm a parent" CTA → parent signup
- `/signup` on-app with a role selector — if "I'm a parent" chosen, the subsequent flow is Flow B

### 5.2 Steps

1. **Parent signs up** via Interactor Account Server auth (existing flow). Role = `:parent`.
2. **Onboarding wizard** (new — `FunSheepWeb.ParentOnboardingLive` at `/onboarding/parent`):
   - Step 1: *Who are you studying for?* — parent enters child name, email (or phone — for SMS invite if supported), grade, and (optional) upcoming test info (test name, date, subject)
   - Step 2: *Link the child* — sends the existing guardian invite (reuse `Accounts.invite_guardian/3`). If the child has no email, show a parent-managed mode: system generates a temporary claim code the parent shares with the child to redeem in-app.
   - Step 3: *Optional upfront purchase* — "Most parents wait until their kid asks — but if you'd rather set this up now, here's what unlimited looks like." Soft CTA to `/subscription` scoped to the child.
   - Step 4: *Done* — summary page with "what happens next": kid gets email/invite, parent sees dashboard once kid activates, weekly digest begins after kid's first activity.
3. **Child activates** (existing `/guardians` accept flow).
4. **Child takes tests** on free tier.
5. **Either** Flow A fires organically when kid hits 85% (the high-probability conversion path), **or** parent converts upfront in step 3 above.

### 5.3 Design notes

- The wizard's **step 3 framing** is counter-intuitive but correct. Many parent-initiated sign-ups convert better when we *under-pressure* the upfront buy and set expectations that the kid will ask. This primes the parent to say yes to Flow A when it fires — often within the first 1–2 weeks of the child using the product — and the conversion is warmer because it's initiated by the child's genuine engagement.
- For parents who want to pay upfront, make it trivially easy, don't hide it. But don't lead with it.
- Multi-child families: the wizard loops — after step 2 shows a "+ Add another child" button before step 3. Step 3 offers a slight bundle discount (future — Phase 2 of this feature).

### 5.4 Acceptance criteria (Flow B)

- [ ] `/onboarding/parent` LiveView implements the 4-step wizard
- [ ] Child invite fires via existing `Accounts.invite_guardian/3`
- [ ] "Parent-managed" temporary claim code path works for children without email
- [ ] Upfront purchase path uses existing `/subscription` checkout but scoped to the just-added child
- [ ] Multi-child: adding N children in step 1 creates N pending invites
- [ ] Tests: wizard navigation, happy path, each step, child-without-email path
- [ ] Visual verification

---

## 6. Flow C — Teacher-initiated

Teacher doesn't pay. Student is added to a class and uses FunSheep on free tier. If the student hits the weekly wall, Flow A fires (student asks parent — same as self-initiated path).

### 6.1 Entry points

- Marketing site → "I'm a teacher" CTA → teacher signup
- `/signup` with "I'm a teacher" role chosen

### 6.2 Steps

1. **Teacher signs up** via Interactor auth. Role = `:teacher`.
2. **Teacher onboarding** (`FunSheepWeb.TeacherOnboardingLive` at `/onboarding/teacher` — if not already created in the Teacher experience Phase 1):
   - Step 1: *Create your first class* — name, period, course, school year (reuses `Classrooms.create_class/2` from Teacher prompt Phase 1; if Teacher prompt not yet shipped, fall back to the existing guardian-invite-as-teacher flow and TODO a migration)
   - Step 2: *Add students* — manual email entry (CSV and roster sync come in Teacher Phase 5)
   - Step 3: *Schedule an upcoming test* — name, date, subject, scope (chapters / standards if available)
   - Step 4: *Done* — summary: students will be invited, they'll start on the free tier, and when a student hits the weekly limit **a parent ask fires automatically** — teacher never sees a billing prompt
3. **Students receive invite** — existing invite flow.
4. **Students activate and practise** on free tier.
5. **When a student hits the wall**, Flow A fires — but routed to the student's *parent* if linked, not to the teacher. If the student has no linked parent, the invite-a-grown-up flow (§4.8) fires.

### 6.3 What the teacher sees about billing (and what they don't)

- Teacher dashboard per-class roster (from Teacher prompt Phase 1): may show an icon indicating which students are on unlimited vs free, **only if the teacher's school / district has opted in to sharing that information** (default: hidden, FERPA-safe)
- Teacher **never** sees pricing, never sees the parent's payment status, never gets billing emails
- If the teacher tries to manually visit `/subscription`, show a friendly "Teachers don't need to subscribe — FunSheep is free for educators" page with a link back to the teacher dashboard

### 6.4 Acceptance criteria (Flow C)

- [ ] `/onboarding/teacher` wizard implements the 4-step flow
- [ ] Teacher-added students land on free tier with no billing touch
- [ ] When one of those students hits the weekly wall, request routes to the *parent* (not the teacher); if no parent linked, invite-a-grown-up fallback fires
- [ ] `/subscription` for a `:teacher` role renders the "free for educators" message, not the plan picker
- [ ] Tests: teacher onboarding wizard; end-to-end test of student added via teacher → hits limit → parent flow fires correctly
- [ ] Visual verification

---

## 7. Data model changes

### 7.1 `practice_requests` (new)

```
practice_requests
  id (uuid)
  student_id :: uuid -> user_roles.id      (who asked)
  guardian_id :: uuid -> user_roles.id     (who was asked; nullable if sent to "all linked")
  reason_code :: enum(:upcoming_test, :weak_topic, :streak, :other)
  reason_text :: text (nullable; free-text if reason_code = :other)
  status :: enum(:pending, :viewed, :accepted, :declined, :expired, :cancelled)
  sent_at :: utc_datetime
  viewed_at :: utc_datetime (nullable)
  decided_at :: utc_datetime (nullable)
  expires_at :: utc_datetime (sent_at + 7 days)
  parent_note :: text (nullable; optional note from parent on decision)
  subscription_id :: uuid (nullable; fk to subscriptions.id when accepted)
  reminder_sent_at :: utc_datetime (nullable; enforces 1-reminder-max)
  metadata :: map (stash student's activity snapshot at request time — streak, minutes, accuracy, upcoming test — so email body renders from immutable data even if activity changes later)
  inserted_at, updated_at
```

Indexes: `(student_id, status)`, `(guardian_id, status)`, `(expires_at)` (for expiry worker).

Rules:
- A student may have at most **one `:pending` request at a time**. Creating a second one returns an error ("You already have a pending ask with {{Parent name}}").
- Expiry worker (`FunSheep.Workers.RequestExpiryWorker`) runs hourly, transitions `:pending` rows past `expires_at` to `:expired`.

### 7.2 `subscriptions` — add `paid_by_user_role_id`

```
alter table(:subscriptions) do
  add :paid_by_user_role_id, references(:user_roles, type: :binary_id, on_delete: :nilify_all)
  add :origin_practice_request_id, references(:practice_requests, type: :binary_id, on_delete: :nilify_all)  # nullable; links a paid sub back to the request that produced it
end

create index(:subscriptions, [:paid_by_user_role_id])
```

- When the student themselves pays (adult learners, or parents buying via the Parent onboarding wizard for themselves): `paid_by_user_role_id = user_role_id`
- When the parent pays for the student: `paid_by_user_role_id = parent.user_role_id`
- Teachers never appear here.

Update `Billing.activate_subscription/2` to accept both fields from webhook metadata.

### 7.3 New `Billing` functions

Add to `FunSheep.Billing`:

```
weekly_usage(user_role_id) :: %{used, limit, remaining, resets_at}
lifetime_usage(user_role_id) :: %{used, limit, remaining}
usage_state(user_role_id) :: :fresh | :warming | :nudge | :ask | :hardwall
can_start_test?(user_role_id) :: boolean
```

These roll up the existing `TestUsage` data; do **not** add a parallel counter table.

### 7.4 New `Accounts` functions

```
list_active_guardians_for_student(student_id) :: [UserRole.t()]   # excludes revoked
find_primary_guardian(student_id) :: UserRole.t() | nil
```

### 7.5 New `PracticeRequests` context

`FunSheep.PracticeRequests` — `create/3`, `view/1`, `accept/2`, `decline/3`, `expire/1`, `list_pending_for_guardian/1`, `count_pending_for_student/1`, `send_reminder/1`.

---

## 8. Copy strategy — the conversion content

This section is the most leverage-per-line in the document. Ship the copy, iterate on it with A/B tests. A mediocre implementation of great copy converts better than a great implementation of mediocre copy.

### 8.1 The parent email (primary conversion surface)

Ship two variants; A/B test. Both respect the ethical guardrails (§2.3) — frame the kid's genuine behaviour, don't manufacture urgency.

#### Variant A — "The rare parent-win"

```
Subject: {{Student name}} just asked you for more practice 💚

Hi {{Parent first name}},

{{Student name}} just sent you a request from FunSheep:

  > "{{Student's chosen reason}}"

They've hit this week's free practice cap and asked you to
unlock more. This happens to be the kind of message most
parents never get.

Here's what {{Student name}} has actually done on FunSheep:

  • {{Current streak}}-day streak
  • {{Weekly minutes}} min of focused practice this week
  • {{Accuracy}}% accuracy across {{Questions this week}} questions
  • {{If upcoming test exists:}} {{Upcoming test name}} is in {{Days to test}} days

                    [Unlock unlimited for {{Student name}}]

Two plans — both unlock unlimited practice for {{Student name}}:

  • $90 / year  — best value ($7.50 / month equivalent)
  • $30 / month — cancel any time

You can also say not right now — {{Student name}} will be told
kindly, and they can ask again later. [Send a kind pass]

Thanks,
The FunSheep team

P.S. If you'd like to see what {{Student name}} has been
working on before you decide, the parent dashboard is at
{{parent dashboard url}}.
```

#### Variant B — "Straight to the evidence"

```
Subject: Your kid asked to do more studying. (Yes, really.)

{{Parent first name}} —

{{Student name}} maxed out this week's free practice and sent
you a request to keep going.

Their reason: "{{Student's chosen reason}}"

Evidence this is real and not a cosmetic ask:

  Streak:       {{Current streak}} days
  This week:    {{Weekly minutes}} min focused, {{Questions}} Qs, {{Accuracy}}% accurate
  {{If upcoming test:}} Test coming: {{Upcoming test name}} in {{Days}} days

                    [Keep them going — $90/year]
                    [or $30/month, cancel any time]

Not right now is always a fine answer. [Decline politely]

— FunSheep
```

### 8.2 Critical copy guardrails

- **Use the student's real name**, pulled from `UserRole.display_name`. Never a placeholder.
- **Use real activity numbers.** If the streak is 1 day, say 1 day. Do not round up or embellish. If there's no upcoming test, omit that line entirely — do not fabricate one.
- **Never use fear framing** ("don't let them fall behind"). Always use pride framing ("here's what they're doing").
- **Always show both plans.** Lead with annual value but do not hide monthly.
- **Always show cancel-anytime language.**
- **Always include a visible decline-politely link.** This is a trust signal to the parent and an ethical commitment to the student.
- **Never trigger before 7am or after 10pm local.** Oban `schedule_at` to the next valid window.

### 8.3 In-app parent notification (same data, tighter frame)

A dismissible card at the top of `/parent`:

```
💚 {{Student name}} just asked for unlimited practice

"{{reason}}"

[See the evidence and decide]   [Not right now]
```

Tap → modal with the email content minus the unsubscribe/header scaffolding, plus the green checkout CTA and the polite-decline link.

### 8.4 Student-side copy (the asking experience)

Already drafted in §4.3 and §4.4. Two further notes:

- The post-send celebration should be **genuine, brief, and age-neutral** — confetti + "Sent! Your grown-up will get this in a minute." (800ms animation). Kids above ~10 hate cartoonish over-celebration; kids below 8 like it. Default to restrained — over-celebration screams "upsell trick" to the exact kid most likely to convert.
- If a parent declines, the student-side copy is the hardest in the whole product: keep it genuinely supportive, short, non-passive-aggressive. *"Your grown-up said maybe later — totally fine. You've still got 0 practice left this week, but {{resets_in}} your free practice resets. Keep the streak alive with review!"* ("Review" = revisiting completed questions, which should remain free.)

### 8.5 Teacher-visited `/subscription` copy

```
Teachers don't need a subscription — FunSheep is free for educators.

Your students will practise on the free tier (20 practice questions
per week). When one of your students is ready for more, their parent
will get an invitation to upgrade — you won't need to handle payment.

[Back to your classroom]
```

---

## 9. Cross-cutting technical requirements

### 9.1 Authorization

- A parent can only see/accept requests from students linked via an `:active` `student_guardians` row
- Webhook handler must validate Interactor Billing signatures (existing — don't weaken)
- The student LiveView's `usage_state` is computed server-side every mount/update; never trust a client-sent value

### 9.2 Concurrency

The accept path has a classic race: both parents tap "Accept" within seconds. Handle it by making `create_checkout` idempotent on the `practice_request_id` in Interactor Billing metadata, and by using a DB-level uniqueness check on `subscriptions.user_role_id` (already unique) plus a `SELECT ... FOR UPDATE` when flipping `practice_request.status` to `:accepted`.

### 9.3 Timezones

Quiet-hours logic needs the parent's timezone. Pull from `user_roles.timezone` (add if not present; default to UTC; browser detection during onboarding). Apply to `ParentRequestEmailWorker` via `Oban.Job.schedule_at`.

### 9.4 Observability

Emit telemetry events at each state transition: `request.created`, `request.email_sent`, `request.viewed`, `request.accepted`, `request.declined`, `request.expired`. Wire to existing metrics stack. These are the KPIs the product team will watch daily.

Track funnel metrics explicitly (create a small dashboard in `/admin`):
- % of active students who see the 70% pre-prompt
- % who tap the 85% ask card
- % who send a request
- % of requests viewed by parent
- % of viewed requests accepted
- Median time: ask → view, view → decide, decide → activation
- Revenue attributable to Flow A vs Flow B vs upfront

### 9.5 Testing

Per `CLAUDE.md`:
- LiveView tests for every route added: usage-meter rendering at all states; request-builder modal; waiting state; parent in-app card; parent onboarding wizard; teacher onboarding wizard; teacher `/subscription` message
- Worker tests: email dispatch respects quiet hours; expiry transitions requests correctly; reminder enforcement (max 1)
- Integration test: full happy path — student reaches 20/20 → opens ask modal → sends → email in Swoosh dev mailbox → parent accepts → checkout webhook fires (use `bypass` or a fake Interactor billing server) → subscription activates → student unlocked → PubSub message received
- Race condition test: two parents accepting concurrently produces exactly one subscription
- Coverage ≥ 80%; all lints; `mix sobelow` clean
- Visual verification across student meter states, parent email, parent in-app card, teacher onboarding, teacher free-for-educators page

### 9.6 Commits and branching

- Branch: `feature/subscription-flows-<slug>` per flow (A/B/C as separate PRs; §7 migrations can land first as their own PR)
- Origin must be `smartstudy`, not `product-dev-template`
- No `--no-verify`; no bypassing hooks

---

## 10. What you must NOT do

- Do **not** build a parallel billing system. Extend `FunSheep.Billing` and `FunSheep.Interactor.Billing`.
- Do **not** add new Stripe integration code directly — Interactor Billing Server is the only supported path.
- Do **not** fabricate activity data in the parent email. If a streak is 1 day, show 1 day. If there's no upcoming test, omit that line.
- Do **not** pre-tick or default-select a reason on the kid's request. Make them actively choose.
- Do **not** show the "ask" card if the student already has a paid subscription.
- Do **not** send parent emails between 10pm–7am parent-local. Schedule the Oban job.
- Do **not** send more than 1 reminder per request.
- Do **not** let an accepted subscription lag behind the student's UI. The celebration toast + meter update must fire within seconds of webhook receipt (use Phoenix.PubSub).
- Do **not** make the decline flow friction-heavy. "Not right now" should be as easy as "Accept."
- Do **not** show leaderboards of "other parents upgraded" — it violates both the ethical and privacy principles.
- Do **not** auto-convert trials (there's no trial in this plan — pure freemium with caps).
- Do **not** remove or weaken the existing free-tier caps (50 lifetime + 20/week). If a PM wants to change them, route that through a product decision, not a code change.
- Do **not** `mix compile` while the dev server is running — the live reloader handles it.
- Do **not** start a test server on port 4040; use `./scripts/i/visual-test.sh start`.

---

## 11. Delivery plan (suggested ordering)

1. **Migration PR** — add `practice_requests`; alter `subscriptions` to add `paid_by_user_role_id` and `origin_practice_request_id`; add `user_roles.timezone` if missing. Merge first, alone.
2. **Flow A, bottom half** — `PracticeRequests` context, `Billing` helper functions (`weekly_usage`, `usage_state`, etc.), `RequestExpiryWorker`, `ParentRequestEmailWorker`. Pure Elixir; testable without UI.
3. **Flow A, top half** — student usage meter, pre-prompt, ask card, request modal, waiting states; parent in-app card on `/parent`; parent email template. Full loop end-to-end with real Interactor Billing in a dev profile.
4. **Flow B** — parent onboarding wizard at `/onboarding/parent`. Mostly UI glue over existing auth + invite + subscription infrastructure.
5. **Flow C** — teacher onboarding wizard at `/onboarding/teacher`; teacher-visited `/subscription` free-for-educators page; wire routing so teacher-added students route Flow A to *parent* correctly.
6. **Analytics + admin dashboard** — telemetry events; small admin page showing funnel metrics.
7. **Polish + A/B copy variants** — ship variant A of the parent email first; wire a feature flag for variant B; hand to PM for analysis once both have been live for ≥ 2 weeks.

Each numbered item above is a shippable PR. Do not bundle 2 with 3 or 4 with 5.

---

## 12. What "done" looks like

- A student on free tier who has completed 20 practice tests this week can send a parent request in 2 taps, including choosing a pre-written reason.
- The parent receives a well-rendered email within seconds (respecting quiet hours) and an in-app notification on their dashboard.
- The parent can accept in 3 taps and the student is unlocked within 5 seconds of checkout completion.
- The parent can politely decline in 2 taps without shame, and the student sees a kind message.
- A request auto-expires in 7 days if untouched, and the student can re-ask after a cooldown.
- A teacher who signs up, creates a class, adds students, and schedules a test never sees a checkout page, and their students still route correctly to parents when they hit the wall.
- A parent who signs up and invites their child sees a clean onboarding that doesn't pressure upfront purchase but makes it trivial if they want to.
- The existing `/subscription` page continues to work for direct purchase (e.g., adult learners buying for themselves).
- Telemetry events fire for every state transition; a small admin funnel view exists.
- Tests ≥ 80% coverage, LiveView tests for every route, all lints pass, no `mix sobelow` findings.
- No fake content anywhere — every metric in every email and every UI is pulled from real student activity.

If a student's parent-ask experience becomes cheesy, pestery, or manipulative during implementation, stop and re-read §2.3 and §3.1. The product's long-term moat depends on this flow being something students tell friends about (positively), not something parents later resent.

---

## 13. Questions to ask before starting

If any of the following are unclear after reading the code, ask the user before writing implementation:

1. Are the free-tier caps (50 lifetime + 20/week) and the pricing ($30/mo, $90/yr) locked for this implementation, or open for tuning?
2. Is there a target date / launch tied to this feature? (Affects phase ordering.)
3. Should the parent email fire in addition to the in-app notification, or only when the parent hasn't opened the app in ≥ X hours? (Current plan: both simultaneously; change if PM disagrees.)
4. Is SMS a supported channel for the parent notification, or email + in-app only? (Affects §4.6 and the onboarding data model.)
5. Is there a family-plan / multi-child discount the PM wants to introduce in this phase, or purely per-child pricing? (Current plan defers; confirm.)
6. For the "student has no linked guardian" edge case (§4.8), do we prefer the student-invites-grown-up flow, or should we instead show a "your school admin can help" path in classroom deployments?
7. Is the Interactor Billing Server configured with product IDs for `monthly` and `annual` plans already? (If not, that's a separate provisioning task before coding.)
8. Who owns the copy final sign-off — product, marketing, or the CEO? (The parent email is the highest-leverage copy in the product; don't ship variant A without explicit approval.)

Answer these, then begin with the migration PR (§11, step 1).
