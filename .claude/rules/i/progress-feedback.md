---
paths: [
  "**/*.heex",
  "**/*.html",
  "**/*.jsx",
  "**/*.tsx",
  "**/live/**/*.ex",
  "**/components/**/*.ex",
  "**/templates/**/*.ex",
  "**/channels/**/*.ex",
  "**/workers/**/*.ex"
]
excludePaths: [
  "**/*_test.exs",
  "**/test/**"
]
alwaysApply: true
---

# Progress Feedback Rule — Never Leave Users Hanging

**Any UI operation that takes longer than ~2 seconds MUST show real-time, contextual, informative progress — not a generic spinner.**

This rule applies whenever a user triggers work that runs asynchronously: AI generation, OCR, imports, question/lesson generation, multi-step workflows, background jobs (Oban), webhook-driven flows, or any request that can't finish in a single synchronous response.

---

## The Four Requirements

Every long-running UI operation MUST satisfy ALL of these:

### 1. Real-Time
- Updates arrive as the backend makes progress, not on a timer or page refresh.
- Use Phoenix PubSub + LiveView `handle_info/2`, Channels, or streaming SSE. Never poll every N seconds and call that real-time.
- If the operation runs in Oban or a GenServer, broadcast state transitions the moment they happen.

### 2. Contextual
- Tell the user **what specifically is happening right now**, named in domain terms.
- ❌ "Processing..." / "Loading..." / "Please wait"
- ✅ "Extracting Chapter 3: Cell Division from your textbook (page 47 of 89)"
- ✅ "Generating 12 of 20 questions for 'Photosynthesis'"
- ✅ "Classifying content type for Chapter 5..."

### 3. Informative
- Show **substeps, counts, and current item names** — not a single bar crawling left to right.
- Surface intermediate artifacts when helpful (e.g. "Found 14 chapters" once OCR finishes, even while questions are still generating).
- If something retries or recovers, say so: "Chapter 2 generation failed, retrying (attempt 2 of 3)…"

### 4. Bounded (user knows when it ends)
- The user must be able to answer **"how much longer?"** at a glance.
- Prefer, in order:
  1. **Known total + current index**: "Chapter 4 of 12" (best)
  2. **Percentage from real work units**: "63% — 19 of 30 questions generated"
  3. **ETA based on measured rate**: "~45 seconds remaining" (only if rate is stable)
  4. **Bounded window with honest caveat**: "Usually 1–2 minutes; longer for large PDFs" (fallback only)
- Never show an unbounded indeterminate spinner for more than ~5 seconds without adding at least a textual context message.
- When the process completes, show a clear terminal state (success/failure) — do not just hide the indicator.

---

## Required Pattern: Named Phases + Progress Within Phase

Every long operation should be modeled as a sequence of named phases, each with its own progress signal. Broadcast both the phase change and the within-phase progress.

```elixir
# Broadcast shape — use this or similar across LiveView/PubSub
%{
  job_id: "uuid",
  phase: :generating_questions,          # atom, domain-named
  phase_label: "Generating questions",   # user-facing
  phase_index: 3,
  phase_total: 5,
  detail: "Chapter 3: Cell Division",    # what's happening right now
  progress: %{current: 12, total: 20, unit: "questions"},
  eta_seconds: 45,                       # optional, only if reliable
  started_at: ~U[...],
  status: :running                       # :queued | :running | :succeeded | :failed
}
```

The UI renders: phase label, detail, `current/total` within the phase, and overall phase progress (e.g. "Step 3 of 5").

---

## Required UI Elements (for anything > 2s)

| Element | Purpose | Example |
|---|---|---|
| **Phase label** | What stage we're in | "Extracting chapters (2 of 5)" |
| **Active detail** | The specific item being worked on right now | "Chapter 3: Cell Division" |
| **Progress metric** | Real count or % from real work | "12 / 20 questions" |
| **Time signal** | Bound on remaining time | "~45s remaining" or "Step 3 of 5" |
| **Terminal state** | Clear success OR failure message, not a silent disappearance | "✓ 20 questions ready" / "✗ Chapter 3 failed — retry" |
| **Cancellability** (where safe) | Let the user abandon if they made a mistake | "Cancel generation" |

A single "Usually takes about a minute" toast does NOT satisfy this rule.

---

## Anti-Patterns (DO NOT DO THESE)

| Anti-pattern | Why it fails | What to do instead |
|---|---|---|
| Lone spinner for > 5s | User can't tell if it's stuck | Add phase + detail text |
| `<.progress value={50} />` with no label | A number with no meaning | Label units and current item |
| `setInterval(fetch, 2000)` polling | Not real-time; wasteful | PubSub / Channels / LiveView `push` |
| Toast on start, silence until done | User assumes it died | Stream phase updates into the same surface |
| Hiding the indicator on error | User thinks it succeeded | Show terminal failure state + next action |
| "Please wait..." | Says nothing, infantilizing | Name the phase and item |
| Fake progress (a bar that just grows on a timer) | Lies about work being done | Tie to real server-side progress units |
| Optimistic "Done!" before it's actually done | Trust erosion when reality catches up | Only mark complete when server confirms |

---

## Implementation Checklist

Before merging any UI change that triggers a > 2s operation, verify:

- [ ] Real-time channel exists (LiveView PubSub, Channel, or SSE) — no polling
- [ ] Backend broadcasts at every meaningful state transition (phase enter/exit, per-item completion, retries, failures)
- [ ] UI shows named phase + current item + numeric progress
- [ ] User can estimate remaining time (phase-of-total, count-of-total, or honest window)
- [ ] Terminal state is distinct and actionable (success confirmation OR failure with retry/next action)
- [ ] Errors are surfaced immediately with domain detail — not silently swallowed
- [ ] If the operation can be cancelled safely, a cancel affordance exists
- [ ] Visual test with Playwright observes the progress UI updating during a real run (not just the start/end states)

---

## Reference Patterns

See `docs/i/ui-design/progress-feedback.md` for full LiveView + Oban + PubSub patterns, copy-pasteable components, and concrete FunSheep examples (question regeneration, OCR pipeline, chapter discovery).

## Related Rules

- `.claude/rules/i/ui-design.md` — visual design standards (colors, spacing, components)
- `.claude/rules/i/visual-testing.md` — Playwright verification requirement (also applies to progress states)

---

**Rule Version**: 1.0
