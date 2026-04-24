# Readiness by Topic — Feature Roadmap

**Status**: Planning  
**Scope**: Student-facing readiness surfaces, teacher/parent visibility  
**Depends on**: Existing `skill_scores`, `topic_mastery_map`, `ReadinessCalculator`

---

## 1. Context & Goal

FunSheep's north star is to surface each student's weak topics and drive them to mastery. The data model to support this already exists — `ReadinessScore.skill_scores` holds per-section (fine-grained skill) accuracy + mastery status, and functions like `topic_mastery_map/2`, `skill_deficits/2`, `topic_accuracy_trend/3` are live. What's missing is the right UI surface that tells different stories depending on where a student is in their journey.

This document covers three distinct UX states plus teacher/parent visibility.

---

## 2. The Three UX States

### State A — Untested (0 questions answered)

**User story**: A student opens their test schedule for the first time. They've done nothing. Show them something that motivates them to start, not a blank dashboard.

**What to show**:
- A "zero state" card with the test name, date countdown, and a prominent **Start Assessment** button
- A motivational message: something like "You haven't been tested yet — let's find out where you stand"
- Preview of what topics are *in scope* for the test (chapter list, no accuracy numbers yet)
- A readiness gauge showing 0% with a clear label "Not yet tested" — don't show 0% without context or it reads as failure

**What NOT to show**:
- Fake scores, estimated readiness, or placeholder percentages
- Any accuracy data (there is none to show)
- Study tips based on imagined weaknesses

**Trigger condition**: `readiness_score == nil` OR all `skill_scores` have `status: :insufficient_data`

---

### State B — In Progress (partial coverage)

**User story**: The student has answered some questions across some topics but hasn't covered everything. The system has enough signal on answered topics to say "these look weak" — even without full coverage, early signal is actionable.

**What to show**:
- **Weak Topics panel** (primary focus): list of topics where `status: :weak`, sorted by `score` ascending. Each row shows: topic name, chapter, accuracy %, a colored indicator (red/amber/green per threshold), and a **Practice Now** shortcut
- **Topics with Insufficient Data**: a separate, lower-prominence list of sections that haven't been attempted yet — label these "Not yet tested" so the student knows they need to visit them
- **Mastered**: a collapsed or subtly-shown list of already-mastered sections so students feel progress
- A headline readiness % with a footnote: "Based on X of Y topics tested — complete the assessment for your full picture"
- An **Assessment Progress bar**: how many of the in-scope chapters have been fully assessed (not just attempted)

**What NOT to show**:
- A final or authoritative readiness score without the coverage caveat
- The Mastered list prominently — weak topics deserve visual priority

**Trigger condition**: At least one `skill_score` has a status of `:weak`, `:mastered`, or `:probing` — and at least one other has `:insufficient_data`

**Key data calls**:
- `Assessments.topic_mastery_map(user_role_id, test_schedule_id)` — full breakdown
- `Assessments.latest_readiness(user_role_id, test_schedule_id)` — headline score
- Derive coverage: count of sections with data / total sections in scope

---

### State C — Full Coverage (all topics assessed)

**User story**: The student has been assessed across all in-scope topics. Now the system can give an authoritative, clear readiness picture.

**What to show**:
- **Readiness Score** prominently (the weakest-N-average, I-10) with a ring/gauge
- **Topics Ranked by Weakness**: full list sorted worst-first. Each row:
  - Topic name, chapter
  - Accuracy % bar (color-coded: <40% = red, 40–69% = amber, ≥70% = green)
  - Mastery status badge: `Mastered`, `Needs Work`, `Weak`
  - Last practiced date
  - **Practice** CTA
- **Chapter rollup summary**: collapsible groups showing chapter-level aggregate so a student can also navigate at chapter granularity
- **Readiness trend graph**: last 5 snapshots over time, per chapter (small sparklines)
- **Predicted score range**: `Assessments.predicted_score_range(readiness_score)` — "Based on your readiness you might score between X and Y on test day"
- **Study Guide CTA**: generates a prioritized study guide using weak sections

**Trigger condition**: All sections in scope have `status != :insufficient_data`

**Key data calls**:
- All calls from State B, plus:
- `Assessments.list_readiness_history(user_role_id, schedule_id, 5)` — trend
- `Assessments.predicted_score_range(readiness_score)` — forecast

---

## 3. Topic Readiness Component Design

A single `<TopicReadinessByState>` LiveView component (or set of components) that selects its template based on which state applies.

### State Detection Logic

```elixir
defmodule FunSheepWeb.TopicReadiness do
  def state(readiness_score, section_count) when is_nil(readiness_score), do: :untested
  def state(%{skill_scores: scores}, total) do
    tested = Enum.count(scores, fn {_, v} -> v.status != :insufficient_data end)
    cond do
      tested == 0              -> :untested
      tested < total           -> :in_progress
      true                     -> :complete
    end
  end
end
```

### Topic Row Component (shared across B and C)

Each row shows:
- **Topic name** (section name)
- **Chapter** (parent chapter name)
- **Accuracy bar**: visual width = accuracy %, colored by threshold
- **Status badge**: `Mastered` (green), `Needs Work` (amber), `Weak` (red), `Not Tested` (gray)
- **Attempts count**: "8 of 10 correct"
- **Practice CTA**: routes to `/practice?section_id=<id>&schedule_id=<id>`

Thresholds (align with product spec):
- `score >= 0.70` AND `status: :mastered` → green / Mastered  
- `score >= 0.40` AND `status != :weak` → amber / Needs Work  
- `score < 0.40` OR `status: :weak` → red / Weak  
- `status: :insufficient_data` → gray / Not Tested  

---

## 3.5 The Tappable Sheep — "Why Am I Here?"

The walking sheep on the readiness progress bar (see `funsheep-fun-animations.md`, animation #1) is the most visible readiness signal on the dashboard. But a student at 17% might genuinely not know *why* the sheep is stuck near the left edge — or what to do about it.

**Interaction**: Tap/click the sheep on any progress bar (dashboard card OR readiness dashboard gauge) → a friendly bottom sheet slides up.

### What the Sheet Shows

The sheet is the sheep speaking directly to the student. No clinical language. Three beats:

**Beat 1 — What readiness means (one sentence)**
> "I'm at 17% because I've only seen a small slice of what's on your Final exam. The more topics you practice and ace, the further right I walk! 🐑"

The copy adjusts by state:
| State | Sheep says |
|-------|-----------|
| A (untested) | "I haven't moved yet because you haven't taken the assessment! Take it so I can find out where to start." |
| B (partial) | "I'm stuck at X% — you've covered Y of Z topics. There are [N] topics I haven't seen yet, plus [M] that need more work." |
| C (full coverage) | "I'm at X% because [N] topics are still weak. Practice those and watch me run! 🐑💨" |

**Beat 2 — Top 3 things to do right now**

Pulls from `skill_deficits/2`, sorted by score ascending (weakest first). Shows max 3 rows:

```
┌─────────────────────────────────────────────────┐
│ 🔴  6.1 Eukaryotic Cells          0% · Weak     │
│     [Practice Now →]                             │
├─────────────────────────────────────────────────┤
│ 🟠  7.2 Cell Membrane Transport  28% · Needs Work│
│     [Practice Now →]                             │
├─────────────────────────────────────────────────┤
│ ⬜  Chapter 9: The Cell Cycle     Not tested yet │
│     [Start Assessment →]                         │
└─────────────────────────────────────────────────┘
```

"Practice Now" links to `/courses/:id/practice?section_id=<id>&schedule_id=<id>`.
"Start Assessment" links to the assessment page.

**Beat 3 — Encouragement + full breakdown link**

> "Fix those three and I'll be past 40% 🐑  
> [See your full readiness breakdown →]"

The link navigates to the readiness dashboard (`/courses/:id/tests/:id/readiness`), which already shows the complete topic list.

### Where the Sheep is Tappable

| Surface | Sheep location | Sheet trigger |
|---------|---------------|---------------|
| Dashboard test card | Readiness bar trailing edge | Tap the sheep SVG |
| Readiness dashboard | Arc gauge outer edge (see animation #18) | Tap the sheep SVG |
| Practice bar | Progress bar trailing edge | Tap opens a lighter "quick tip" version (just Beat 1 + Beat 2, no full breakdown link — student is already in practice) |

### Implementation Notes

- The bottom sheet is a LiveView component that receives `section_deficits` as assigns (already available via `skill_deficits/2`)
- Triggered by a `phx-click="open_sheep_tip"` on the sheep SVG wrapper
- On desktop: renders as a popover/tooltip anchored to the sheep position rather than a full bottom sheet
- The sheet should NOT open automatically — only on tap. The sheep's walking animation already communicates progress passively; the tap is for students who want to know more
- State A students see a special CTA sheet since there are no deficits yet (just the "take the assessment" nudge)

---

## 4. Where to Surface This

### 4.1 Student: Readiness Dashboard (`readiness_dashboard_live.ex`)

This is the primary home for all three states. Currently it shows a chapter breakdown; it needs a full rebuild around the three-state model.

**Current state**: Shows chapter breakdown + last 5 snapshots + recalculate button.  
**Target state**: Three-state template switcher with topic-level breakdown.

Changes needed:
- Detect state (A/B/C) in `mount/3` based on skill_scores
- Render different heex partials per state
- Replace chapter-only breakdown with section-level `TopicRow` list
- Add coverage progress bar for State B

### 4.2 Student: Main Dashboard (`dashboard_live.ex`)

The test card for each upcoming test currently shows a single readiness % bubble. Extend it:

**State A**: Show "Not yet tested" label + prominent Start Assessment button  
**State B**: Show readiness % + "X of Y topics assessed" + a summary of weak count ("3 weak topics")  
**State C**: Show readiness % + weak count badge + quick-link to Readiness Dashboard

Keep it compact — the test card is not the primary surface. Drive them to the readiness dashboard for detail.

### 4.3 Teacher Dashboard (`teacher_dashboard_live.ex`)

Currently a skeleton. Wire it up with per-student readiness by topic.

**Student list row** (per student):
- Student name
- Test name
- Aggregate readiness %
- State indicator (A/B/C as icon or label)
- Weak topic count
- Last active date

**Student drill-down** (click a row):
- Show the same topic breakdown as State B/C, but read-only
- Teacher sees accuracy per topic, mastery status, recent attempts
- Use existing `topic_mastery_map/2` + `recent_attempts_for_topic/3`
- No practice CTAs; replace with note/message options (future phase)

**Class summary** (top of page):
- Average readiness across linked students
- Distribution chart: how many students are in each state (A/B/C)
- "Needs attention" list: students with most weak topics or no recent activity

### 4.4 Parent Dashboard (`parent_dashboard_live.ex`)

Parent dashboard already has the richest topic-level display (`TopicMasteryMap` component + drill-down modal). The gap is surfacing the three-state context clearly.

Changes needed:
- Add state banner (State A: motivational zero-state; State B: coverage caveat; State C: full picture label)
- Ensure weak topics are visually sorted first in the mastery map
- Add a "Not yet tested" section for State B incomplete coverage

---

## 5. Data Model — No Changes Required

The existing data model fully supports this feature:

| Needed | Source |
|--------|--------|
| Per-skill accuracy | `ReadinessScore.skill_scores[section_id].score` |
| Per-skill mastery status | `ReadinessScore.skill_scores[section_id].status` |
| All skills in scope | `Assessments.topic_mastery_map/2` |
| Coverage (tested vs not) | Count skill_scores with status != :insufficient_data |
| Trend | `Assessments.list_readiness_history/3` |
| Headline aggregate | `ReadinessScore.aggregate_score` |
| Predicted score | `Assessments.predicted_score_range/1` |
| Recent attempts per topic | `Assessments.recent_attempts_for_topic/3` |

No new schemas or migrations needed for MVP.

---

## 6. Implementation Phases

### Phase 1 — Student State Detection + Basic UI (Highest Priority)

**Goal**: Students can see the right message based on where they are.

Tasks:
1. Add `TopicReadiness.state/2` helper module
2. Rebuild `readiness_dashboard_live.ex` with three-state template switcher
   - State A: motivational zero-state with in-scope chapter preview
   - State B: weak topics panel + "not yet tested" panel + coverage bar
   - State C: full ranked topic list + readiness gauge
3. Add topic row component (shared across B/C)
4. Update test card in `dashboard_live.ex` with state-aware labels

**Acceptance criteria**:
- Student with 0 attempts sees motivational UX, not a broken/empty dashboard
- Student mid-assessment sees weak topics highlighted, coverage progress shown
- Student who completed assessment sees full ranked list with Mastered/Needs Work/Weak badges

---

### Phase 2 — Teacher Dashboard Wiring

**Goal**: Teachers can see per-student readiness by topic, not just a placeholder.

Tasks:
1. Wire `topic_mastery_map/2` into `teacher_dashboard_live.ex`
2. Build student list with readiness %, state badge, weak count
3. Build student drill-down panel (click-to-expand)
4. Add class summary bar (avg readiness, distribution)

**Acceptance criteria**:
- Teacher sees all linked students' readiness at a glance
- Clicking a student shows topic-level breakdown
- "Needs attention" surface shows students with 0 activity or high weak count

---

### Phase 3 — Parent Dashboard State Context

**Goal**: Parent dashboard surfaces the three states clearly, not just raw accuracy numbers.

Tasks:
1. Add state banner to parent dashboard
2. Ensure weak topics sort to top in `TopicMasteryMap`
3. Add "not yet tested" section for incomplete coverage (State B)
4. Persist which mastery-map topics are expanded between sessions (nice-to-have)

---

### Phase 4 — Predictive & Trend Layer (Future)

**Goal**: Give students and parents a forward-looking picture.

Tasks:
1. Per-topic trend sparklines (daily accuracy for each section over last 2 weeks)
2. "At current pace" projection: estimate days to mastery per weak topic
3. Test-day readiness forecast vs target readiness

These are lower priority and depend on students having enough data history to be meaningful.

---

## 7. UX Copy Guidelines

| State | Headline | Subtext |
|-------|----------|---------|
| A (untested) | "Let's find your starting point" | "Take the diagnostic assessment to see which topics you're ready for and which need work" |
| B (in progress) | "Here's what we know so far" | "You've been assessed on X of Y topics. Complete the assessment to get your full readiness picture." |
| C (complete) | "Your readiness: [X%]" | "Based on your performance across all [N] topics" |

For weak topics (States B and C):
- Label: **"Needs Work"** not "Weak" (less discouraging; same threshold)
- For sections at < 40%: **"Focus Here"** to convey urgency without alarm
- Mastered sections: **"Ready"** with a checkmark

---

## 8. Non-Goals (Out of Scope for This Roadmap)

- Per-skill readiness targets (only test-level targets today)
- Push notifications for "you have 3 weak topics to review"
- AI-generated study plans per weak topic (Study Path feature, future phase)
- Video linked to skill tags (I-14 — not yet built)
- Cohort/class comparison on the student-facing surface (parent dashboard only)

---

## 9. Open Questions

1. **Coverage threshold for State C**: Should we require 100% coverage or allow a high-confidence threshold (e.g., >80% of sections have data) to declare "complete"? The current invariant requires all sections to be tested, but in practice a student might skip a few. Recommendation: use 100% per invariant but show a "Y sections not yet assessed" callout for any remaining gaps.

2. **Recalculate cadence**: Readiness is computed lazily and saved on demand. For the three-state detection to be accurate in real-time, should we auto-recalculate on every assessment question answered? The `latest_readiness` function computes live without persisting, so real-time state detection can use it without a DB write. Recommendation: use live computation for state detection; persist only on explicit recalculate or end-of-session.

3. **Teacher "not yet started" students**: Students who haven't linked a schedule yet would always appear in State A. Teacher dashboard needs a way to distinguish "linked but untested" from "no schedule at all."

4. **Mobile-first layout**: The topic list in State C can be long (20–40 topics for a full AP course). Consider a paginated or collapsible-by-chapter layout for mobile. The parent dashboard's existing `TopicMasteryMap` accordion pattern (chapters expand to show sections) is a good model.
