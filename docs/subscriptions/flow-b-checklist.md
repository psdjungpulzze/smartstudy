# Flow B — Parent-initiated — Delivery Checklist

Full spec: `~/s/funsheep-subscription-flows.md` §5, §7 (shared migration), §11.4.

**Narrative**: parent signs up, onboards, invites child, optionally buys upfront — but the *intended* conversion is Flow A firing organically once the child hits the free-tier wall.

Ship in its own worktree **after** Flow A (steps 1–3) is live in production. Flow B depends on the Flow A migrations and the `paid_by_user_role_id` column.

---

## Prerequisites

- [ ] Flow A PRs 1, 2, 3 merged to `main`
- [ ] `user_roles.timezone` column present (from Flow A PR 1)
- [ ] `subscriptions.paid_by_user_role_id` column present (from Flow A PR 1)
- [ ] `Accounts.invite_guardian/3` confirmed working end-to-end (existing `/guardians` flow)

---

## Entry points (§5.1)

- [ ] Marketing site "I'm a parent" CTA → parent signup flow
- [ ] `/signup` in-app with role selector — if "I'm a parent" chosen, the subsequent flow is Flow B

---

## Parent onboarding wizard — `/onboarding/parent` (§5.2)

New LiveView: `FunSheepWeb.ParentOnboardingLive`.

### Step 1 — "Who are you studying for?"

- [ ] Child name (required)
- [ ] Child email OR phone (phone only if SMS is enabled — §13 Q4; default: email only)
- [ ] Grade (dropdown)
- [ ] Optional upcoming test: test name, date, subject
- [ ] Support **multi-child**: `[+ Add another child]` button loops this step before moving to Step 2
- [ ] Form validation on blur — do not let parent advance with malformed email

### Step 2 — "Link the child"

- [ ] For each child entered in Step 1, call `Accounts.invite_guardian/3` (reuse existing)
- [ ] For children WITHOUT email: **parent-managed mode**:
  - [ ] Generate a claim code
  - [ ] Display the code + simple instructions for the parent to share with the child in person
  - [ ] Claim code must be single-use and expire after 14 days
  - [ ] Redeem path: `/claim/{code}` → child signs in and redeems
- [ ] Confirmation UI shows one row per invited child with status (Invite sent / Claim code ready)

### Step 3 — "Optional upfront purchase"

- [ ] Header copy: "Most parents wait until their kid asks — but if you'd rather set this up now, here's what unlimited looks like."
- [ ] **Soft CTA**, not primary. Secondary-styled button "Set up now for {{Student name}}"
- [ ] Tap → existing `/subscription` page, scoped to the child via URL or session (`subscription?beneficiary_id=<uuid>`)
- [ ] Checkout webhook stamps `paid_by_user_role_id = parent`, `user_role_id = student`, `origin_practice_request_id = nil`
- [ ] `[Skip for now]` primary CTA — advances to Step 4
- [ ] Multi-child: if >1 child invited, per-child button rows; bundle discount is Phase 2 (defer)

### Step 4 — "Done"

- [ ] Summary of what happens next:
  - Kid gets email/invite/claim-code
  - Parent can see dashboard once kid activates
  - Weekly digest begins after kid's first activity
  - *If kid hits wall, parent will get an ask email (Flow A)*
- [ ] CTA: "[Go to parent dashboard]" → `/parent`

---

## Acceptance criteria (§5.4)

- [ ] `/onboarding/parent` LiveView implements all 4 steps; navigation between them respects validation
- [ ] Child invite fires via existing `Accounts.invite_guardian/3` for each child added
- [ ] Parent-managed temporary claim code path works for children without email (generate → display → redeem → student activated)
- [ ] Upfront purchase path routes to existing `/subscription` checkout scoped to the just-added child
- [ ] Multi-child: adding N children in Step 1 creates N pending invites / claim codes
- [ ] Wizard progress is persisted across reloads (so parent doesn't lose state if they refresh)
- [ ] If a parent abandons mid-wizard and returns, resume from their last completed step

---

## Tests

- [ ] LiveView test: wizard navigation (step 1→2→3→4 happy path)
- [ ] LiveView test: validation blocks advance on malformed email
- [ ] LiveView test: multi-child loop in Step 1 (add 2 children, both invites fire)
- [ ] LiveView test: child-without-email path yields a claim code and does NOT call `invite_guardian` for that child
- [ ] Context test: claim-code generation + redemption (single-use, 14-day expiry)
- [ ] Integration test: parent onboarding → child accepts invite → child takes tests → Flow A fires normally when wall hit (verifies Flow A still works for Flow B-onboarded students)
- [ ] Integration test: parent onboarding → upfront purchase → subscription activates with `paid_by_user_role_id = parent`, `origin_practice_request_id = nil`
- [ ] Coverage ≥ 80%, all lints clean

---

## Visual verification

Use `scripts/i/visual-test.sh start`. Light + dark at 375, 768, 1440.

- [ ] Each wizard step
- [ ] Multi-child variant of Step 1
- [ ] Parent-managed claim code display
- [ ] Validation error states
- [ ] Upfront-purchase Step 3 both states (single-child, multi-child)
- [ ] Final "Done" screen

---

## What NOT to do

- [ ] Do NOT lead with the upfront purchase. The wizard under-pressures Step 3 deliberately (§5.3) — this primes the parent to say yes when Flow A fires
- [ ] Do NOT bundle a trial. Pure freemium — if parent skips Step 3, child lands on free tier
- [ ] Do NOT auto-convert skipped Step 3 into a 7-day trial
- [ ] Do NOT create a leaderboard of "other parents signed up"
- [ ] Do NOT require the child to be online for the parent to complete the wizard
- [ ] Do NOT charge `paid_by = parent` without `user_role_id = student` — the invariant from §3.1 holds

---

## Regression surface

- [ ] Existing `/guardians` flow still works for parents who don't use the new wizard
- [ ] Existing `/subscription` direct-purchase still works (adult self-purchase)
- [ ] Flow A still fires normally for students onboarded via Flow B (test end-to-end)
- [ ] Parent dashboard `/parent` still works

---

## Deferred to Phase 2 (explicitly not in this PR)

- Multi-child bundle discount
- SMS invite channel
- Rich parent dashboard overhaul (the spec notes this doesn't block Flow A/B)
