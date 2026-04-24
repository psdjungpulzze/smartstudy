# 🧠 Your Memory Span — Feature Roadmap

**Concept:** Turn "forgetting" into a fun, personal insight that motivates students to practice more often — like a coach pointing out that even great athletes need daily training.

---

## The Big Idea

Every student has a personal **memory span** per topic — the typical window between "I got it right!" and "wait… how did this work again?". Once we measure it, we can:

1. **Show students their memory span** in a playful, non-judgmental way.
2. **Predict when they're about to forget** and nudge them to review before it happens.
3. **Celebrate improvement** — when a student's memory span grows from 3 days to 2 weeks through consistent practice, that's a win worth celebrating.

---

## Why This Works (Learning Science)

The "forgetting curve" (Ebbinghaus, 1885) shows that memory decays exponentially unless reinforced. Spaced repetition (SM-2, already in FunSheep via `review_cards`) counteracts this — but students don't *feel* it working. Memory Span makes it **visible and personal**, answering "why do I keep practicing?" with concrete data.

---

## Fun Framing — Tone & Messaging

The feature should feel like a **witty coach**, not a judgment. Examples by span length:

| Memory Span | Fun Message |
|---|---|
| < 3 days | "⚡️ Speed runner! Your brain loves novelty but forgets fast. 3 days is your sweet spot — keep those daily reps going!" |
| 3–7 days | "🏃 Almost there! A quick review every 5 days keeps you sharp. Sprinters train daily — so do you!" |
| 1–2 weeks | "💪 Solid retention! Two weeks between reps and you start sliding. Schedule that mid-week refresh!" |
| 2–4 weeks | "🧩 Strong memory! Monthly touch-ups keep you match-ready. Like a musician — even pros stay sharp with regular practice." |
| > 1 month | "🏆 Elite-level retention! You've basically made this topic your best friend. Keep the streak alive!" |
| No decay detected | "🔥 Memory of steel! You've never forgotten this topic. Legendary." |

---

## Data We Already Have

All the raw data lives in `question_attempts`:

```
question_attempts
├── user_role_id      → which student
├── question_id       → which question (links to chapter/section for topic)
├── is_correct        → did they get it right?
├── inserted_at       → when they answered
└── difficulty_at_attempt → difficulty level (bonus signal)
```

**No new tables required for the core calculation.** We compute memory span by scanning each student's attempt history per question (or per topic), finding right→wrong transitions, and measuring the time gap.

---

## Algorithm Design

### Step 1: Per-Question Memory Span

For a given `(user_role_id, question_id)` pair, ordered by `inserted_at`:

```
Attempts: [✓ Jan 1] [✓ Jan 8] [✗ Feb 5] [✓ Feb 10] [✗ Mar 1]
                              ↑                        ↑
                         right→wrong: 28 days    right→wrong: 19 days
                         (last correct was Jan 8)
```

**Algorithm:**
1. Walk attempts chronologically.
2. Track `last_correct_at` — updated each time `is_correct = true`.
3. When `is_correct = false` AND `last_correct_at` is set:
   - Decay event: `gap = inserted_at - last_correct_at`
   - Record this gap.
   - Reset `last_correct_at = nil` (wait for next correct before tracking again).
4. Median of all recorded gaps = question-level memory span.

**Why median?** More robust than mean — outliers like a 6-month summer gap shouldn't skew the result.

### Step 2: Topic-Level Memory Span

Aggregate question-level spans across all questions in a chapter/section:

```
chapter_memory_span = median(per_question_spans for all questions in chapter)
```

This gives the student their "Cell Division memory span: ~12 days".

### Step 3: Subject-Level Memory Span

Aggregate across all chapters in a course:

```
course_memory_span = median(chapter_spans for all chapters in course)
```

"Your AP Biology memory span: ~18 days"

### Step 4: Trend Detection

Compare memory spans across time to detect improvement or decline:

- Split history into two halves (early vs. recent attempts).
- Compare median spans.
- "Your memory span for this topic has grown from 5 days to 3 weeks! 🎯"

---

## New Data to Persist

While spans *can* be computed on demand from `question_attempts`, storing computed results avoids expensive recalculation.

### New Schema: `memory_spans`

```elixir
schema "memory_spans" do
  belongs_to :user_role, FunSheep.Accounts.UserRole
  belongs_to :question, FunSheep.Questions.Question, on_replace: :nilify  # optional
  belongs_to :chapter, FunSheep.Courses.Chapter, on_replace: :nilify      # optional
  belongs_to :course, FunSheep.Courses.Course

  # Granularity: :question | :chapter | :course
  field :granularity, Ecto.Enum, values: [:question, :chapter, :course]

  # The computed span in hours (median of decay gaps)
  field :span_hours, :integer

  # Sample size — how many decay events contributed
  field :decay_event_count, :integer

  # Direction of trend vs. previous window
  field :trend, Ecto.Enum, values: [:improving, :declining, :stable, :insufficient_data]

  # Previous window span (for trend display)
  field :previous_span_hours, :integer

  # When this was last recalculated
  field :calculated_at, :utc_datetime

  timestamps()
end
```

**Indexes:**
- `[user_role_id, granularity, course_id]` — list all chapter spans for a student in a course
- `[user_role_id, granularity, chapter_id]` (unique) — upsert chapter span
- `[user_role_id, granularity, question_id]` (unique) — upsert question span

### Recalculation Trigger

Recalculate memory spans:
- **After every study session ends** (via Oban job, non-blocking) — scoped to questions attempted in that session.
- **Weekly background sweep** (Oban cron) — catch edge cases / stale spans.

---

## Feature Surfaces (UI)

### 1. Memory Span Dashboard Card

On the student's home / progress page, a card:

```
┌────────────────────────────────────────────────────┐
│ 🧠  Your Memory Span                               │
│                                                    │
│  AP Biology          ~18 days   📈 +6 days        │
│                                                    │
│  ⚡️ You tend to forget topics after ~18 days.     │
│     Schedule a review every 2 weeks to stay sharp! │
│                                                    │
│  [ See breakdown by topic → ]                      │
└────────────────────────────────────────────────────┘
```

### 2. Topic-Level Breakdown

Expanding the card (or a dedicated "Memory Span" tab in course view):

```
Chapter 3: Cell Division          🔴 7 days  ↓ declining
Chapter 5: Genetics               🟡 14 days  → stable
Chapter 8: Evolution              🟢 30 days  ↑ improving
```

Color coding:
- 🔴 Red: span < 7 days — needs frequent review
- 🟡 Yellow: 7–21 days — moderate retention
- 🟢 Green: > 21 days — strong retention

### 3. Pre-Session Nudge

Before a practice session, if the student hasn't reviewed a topic and the memory span predicts they're "about to forget":

```
💡 Heads up! You tend to forget Cell Division after ~7 days.
   It's been 9 days since your last review.
   Want to warm up with a quick review first?
   [ Yes, let's go! ]  [ Skip for now ]
```

### 4. Post-Session Celebration

After a session where a student answered questions correctly on a topic they previously forgot:

```
🎯 Memory span update!
   You just extended your Cell Division memory span
   from 7 days → 15 days this month.
   Keep going — you're training your brain like a pro! 💪
```

### 5. Fun "Memory Span Profile" (Optional / Playful)

A shareable card (like Spotify Wrapped) at the end of a term:

```
┌─────────────────────────────────────────────┐
│        🧠 Your Memory Profile               │
│                                             │
│   Subject: AP Biology                       │
│   Memory Span: 18 days                      │
│                                             │
│   You're a: CONSISTENT PRACTITIONER 🏃      │
│                                             │
│   Best topic:  Evolution (45 days!)        │
│   Trickiest:   Cell Division (6 days)      │
│                                             │
│   "Even LeBron practices free throws daily.│
│    You've got this." 🏀                     │
└─────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1 — Core Computation (Backend Only)

**Deliverables:**
- `FunSheep.MemorySpan` context
- `FunSheep.MemorySpan.Calculator` — pure functions for span calculation
- `FunSheep.MemorySpan.Span` schema + migration
- `FunSheep.Workers.MemorySpanWorker` (Oban) — triggered post-session
- Unit tests for calculator (edge cases: first attempt wrong, no decay events, summer gap, etc.)

**Key functions:**
```elixir
MemorySpan.Calculator.compute_question_span(attempts)
  # :: {:ok, span_hours} | {:insufficient_data, reason}

MemorySpan.Calculator.compute_topic_span(question_spans)
  # :: {:ok, median_hours} | {:insufficient_data, reason}

MemorySpan.upsert_for_session(study_session)
  # :: :ok
```

**Definition of done:** Memory spans are computed and stored after each study session ends. Spans can be queried per student per chapter.

---

### Phase 2 — Student-Facing UI

**Deliverables:**
- Memory span card component on student home/progress page
- Chapter-level breakdown view (expand/collapse)
- Fun messaging copy (all tiers from the table above)
- Dark mode support

**Definition of done:** Student can see their memory span for each chapter, with color coding and fun messaging. Playwright-verified.

---

### Phase 3 — Nudges & Predictions

**Deliverables:**
- "About to forget" detection: a chapter is flagged when `days_since_last_correct > span_hours / 24`
- Pre-session nudge UI (shown when about to forget a topic)
- Post-session celebration UI (when span improves)
- Oban scheduled job: `FunSheep.Workers.MemorySpanNudgeJob` — daily check, PubSub or push notification if configured

**Definition of done:** Students receive a nudge when they're predicted to forget a topic, and a celebration when their span improves.

---

### Phase 4 — Memory Span Profile (Shareable / Fun)

**Deliverables:**
- End-of-term "Memory Profile" card
- Athlete archetype assignment (Speed Runner, Consistent Practitioner, Iron Memory, etc.)
- Optional sharing (screenshot-friendly layout)

**Definition of done:** Student can view their Memory Profile at end of each test-prep cycle.

---

## Edge Cases to Handle

| Case | Handling |
|---|---|
| Student only ever answered once | `insufficient_data` — show "Keep practicing to unlock your memory span!" |
| Student never got a topic wrong | Show "Memory of steel! 🔥" — infinite memory span |
| Long gaps (summer break, months) | Cap decay gap at 90 days to prevent outlier distortion |
| Single question per topic | Show question-level span but label it "early estimate" |
| Negative signal: always wrong | No decay events recorded — show "Let's build your first correct answer!" |

---

## Success Metrics

| Metric | Target |
|---|---|
| Students who view their memory span | > 40% weekly active users |
| Practice sessions started from "about to forget" nudge | > 20% of nudges acted on |
| Average memory span growth over a test-prep cycle | Measurable improvement (baseline TBD) |
| Student-reported motivation (in-app survey) | > 70% find it helpful |

---

## Open Questions

1. **Minimum decay events for reliable span?** Suggest requiring ≥ 2 decay events before showing a span (otherwise label it "early estimate"). Needs tuning.
2. **Summer gap cap:** 90 days seems reasonable, but should this be configurable per school calendar?
3. **Guardian visibility:** Should parents see their child's memory spans? Likely yes — add to parent dashboard in Phase 2.
4. **Gamification tie-in:** Could memory span improvement award XP or badges? ("Extended your memory span 2x!" = badge unlock.)
5. **Teacher view:** Teachers could see class-level memory spans per chapter to identify topics needing re-teaching.

---

## Related Features

- `funsheep-readiness-by-topic.md` — Memory Span is a *leading indicator* of readiness drops.
- `review_cards` (SM-2) — Memory Span data could inform SM-2 ease factor adjustments.
- `confidence-based-scoring.md` — Confidence + memory span together = powerful readiness signal.
