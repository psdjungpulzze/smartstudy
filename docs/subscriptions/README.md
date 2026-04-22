# Subscription Flows — Delivery Checklists

This directory is the source of truth for what we're delivering across Subscription Flows A, B, and C. Each checklist captures every acceptance criterion from the implementation guide (`~/s/funsheep-subscription-flows.md` on Peter's machine) verbatim so nothing drifts between worktrees.

## The three flows

| Flow | Who initiates | Who pays | Doc |
|---|---|---|---|
| **A — Student-initiated** (upsell) | Student hits 85% of weekly cap → asks parent | Parent | [flow-a-checklist.md](flow-a-checklist.md) |
| **B — Parent-initiated** | Parent signs up, invites child, may pay upfront | Parent | [flow-b-checklist.md](flow-b-checklist.md) |
| **C — Teacher-initiated** | Teacher onboards students into free-tier classroom | **No one** (student free unless Flow A fires later → parent pays) | [flow-c-checklist.md](flow-c-checklist.md) |

## Delivery order

Per spec §11, each numbered step is its own shippable PR:

1. **Migrations** — `practice_requests`, alter `subscriptions` (`paid_by_user_role_id`, `origin_practice_request_id`), `user_roles.timezone`. Must merge alone.
2. **Flow A backend** — `FunSheep.PracticeRequests` context, `Billing` helpers, `RequestExpiryWorker`, `ParentRequestEmailWorker`. Pure Elixir.
3. **Flow A UI** — usage meter, pre-prompt, ask card, request modal, waiting states, parent in-app card, parent email, `/subscription` activation with `paid_by`.
4. **Flow B** — `/onboarding/parent` wizard.
5. **Flow C** — `/onboarding/teacher` wizard; teacher-visited `/subscription` free-for-educators message; route Flow A from teacher-added students to the student's parent.
6. **Analytics + admin funnel dashboard.**
7. **Polish + A/B copy variants.**

Flow A is the revenue driver and ships first (steps 1–3 in this worktree). Flows B and C follow in separate worktrees.

## Invariants that cross all three flows (§3, §9, §10)

**Payer vs beneficiary model.**
- `Subscription.user_role_id` is always the **beneficiary** (student).
- `Subscription.paid_by_user_role_id` is the **payer** (parent, or student themselves for self-purchase).
- Teachers **never** appear as payer or beneficiary.

**Free-tier caps are locked.**
- 50 lifetime free tests + 20 free tests per rolling 7-day window.
- Monthly $30 / Annual $90, both unlimited for the student beneficiary.
- Do not change without a product-level decision.

**Ethical guardrails (§2.3).**
- Conversion may only fire on real, voluntary, positive student behaviour.
- No manufactured student requests. No dark-pattern "oops" buttons. No re-prompting after dismissal. No shame copy on decline. No leaderboards of other-parent upgrades.
- 20/week is enough capacity for a motivated student to do meaningful unpaid work. Do not reduce it.

**Absolute rule on no fake content (CLAUDE.md).**
- Every metric rendered in a parent email or in-app card must come from real `TestUsage` / activity data.
- If a streak is 1 day, say 1 day. If there is no upcoming test, omit the line — do not fabricate one.

**Do not rebuild existing infrastructure.**
- `FunSheep.Billing` and `FunSheep.Interactor.Billing` are the only billing paths. No parallel Stripe code.
- Guardian links (`student_guardians`) are the only parent↔student relationship store.
- Interactor Account Server owns auth; do not add local password handling.

## Using the checklists

When building a flow:
1. Open the matching checklist.
2. Copy-paste each section into the PR description as you implement it.
3. Check items off only when the test exists AND passes AND the visual verification is done where applicable.
4. Do not mark a flow "done" until every unchecked item is either ticked or explicitly deferred with a tracked follow-up.

Each checklist ends with a **regression surface** section — lists existing features that must continue to work after the flow lands. Always re-verify those before merging.
