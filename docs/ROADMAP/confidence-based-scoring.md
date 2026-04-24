# Confidence-Based Scoring (Don't Know / Not Sure / I Know)

> **Status:** Research & Proposal — not yet scheduled for implementation
>
> **Problem:** The current binary correct/incorrect system creates false positives when students guess correctly and false negatives are never detected for overconfident wrong answers. Adding a self-reported confidence signal transforms every answer into a 2D data point: correctness × certainty.

---

## Why the Current System Falls Short

FunSheep currently marks a topic weak only when a student answers incorrectly (confirmed by a second wrong answer on the same skill). This produces two systematic errors:

| Situation | Current Outcome | Correct Outcome |
|---|---|---|
| Student guesses correctly | Topic marked **strong** (false positive) | Should still flag for reinforcement |
| Student answers wrong but selects "I Know" | Topic marked **weak** (correct) but no overconfidence signal | Should prioritize — overconfidence is dangerous |
| Student answers correctly and selects "I Know" | Topic marked **strong** ✓ | Correct |
| Student answers correctly but selects "Not Sure" | Topic marked **strong** (false positive) | Should still loop for consolidation |

The result: readiness scores inflate, students are released from practice loops too early, and overconfident wrong-answerers get the same remediation path as students who knew they didn't know.

---

## Prior Art: How Other Systems Solve This

### 1. Certainty-Based Marking (CBM) — Gardner-Medwin, UCL (1995)

The foundational academic framework. Students select a confidence level before or after answering, and the score is adjusted accordingly.

**Classic CBM scoring table:**

| Confidence Level | Correct | Incorrect |
|---|---|---|
| C=1 (Low / "Don't Know") | +1 | 0 |
| C=2 (Medium / "Not Sure") | +2 | −2 |
| C=3 (High / "I Know") | +3 | −6 |

**Key insight:** The penalty is asymmetric. High confidence wrong is catastrophic; low confidence correct is safe. This forces students to be honest — gambling with C=3 on a guess is a losing strategy in expectation.

**Used in:** Medical licensing exams (UK), Cambridge University clinical assessments, OU online courses.

**Reference:** Gardner-Medwin, A.R. & Gahan, M. (2003). *Formative and Summative Confidence-Based Assessment.* Proceedings of 7th CAA International Computer Assisted Assessment Conference.

---

### 2. Anki / FSRS — Free Spaced Repetition Scheduler (2022–present)

Anki presents four confidence buttons after revealing the answer: **Again / Hard / Good / Easy** (with older SM-2 using a 0–5 scale). The student self-reports how well they recalled the answer.

**How it maps to FunSheep:**

| Anki Rating | FunSheep Equivalent | Effect |
|---|---|---|
| Again (0) | Wrong + Don't Know | Short interval (1 day), back to weak pool |
| Hard (1) | Wrong + Not Sure / Correct + Don't Know | Longer interval but still weak |
| Good (2) | Correct + Not Sure | Normal interval progression |
| Easy (3) | Correct + I Know | Fast-track interval increase |

**FSRS algorithm** (Supermemo Research, 2022): uses a Transformer-inspired model trained on 500M+ Anki reviews. It models `Stability` (how long a memory lasts) and `Difficulty` (how hard the card is for this user). Stability grows faster after Easy ratings, slower after Hard.

**Key lesson:** Confidence is used to adjust the *next review interval*, not to assign a binary pass/fail. FunSheep can use the same principle to adjust how quickly a skill exits the weak-practice loop.

---

### 3. Duolingo — "Hearts" + Crowdsourced Difficulty (2020–present)

Duolingo doesn't expose explicit confidence buttons, but infers confidence from:
- **Speed of response** (fast correct = high confidence proxy)
- **Streak consistency** (multiple sessions without error = mastery)
- **Half-life regression model (HLR):** Each word has a half-life; incorrect or slow answers decay it faster.

**Lesson for FunSheep:** Even without a confidence button, implicit signals (time taken already stored in `question_attempts.time_taken_seconds`) can supplement the explicit button.

---

### 4. Khan Academy — "I Got It" / "Skip" (Mastery Challenges)

Khan Academy's Mastery Challenge uses a 4-level skill model: **Attempted → Familiar → Proficient → Mastered**. Students can mark "I Got It" (self-report mastery attempt) which moves them directly to a mastery challenge. If they fail, they drop back to Proficient.

**Key insight:** Self-reported confidence can gate students into *harder evaluation paths* rather than adjusting scores. A student who says "I Know" should face a harder question next — not just get credit. FunSheep's existing depth-probe logic (I-3) maps well to this.

---

### 5. Panopto / Lecture-Based Formative Assessment (Academic Use)

Universities using "clicker" systems and real-time polling (Poll Everywhere, iClicker) often pair multiple-choice questions with a confidence slider. Research shows:

- Students who answer correctly with **low confidence** benefit most from immediate explanation.
- Students who answer **incorrectly with high confidence** (overconfidence) require targeted misconception correction, not just more practice.

**Reference:** Kruger, J. & Dunning, D. (1999). *Unskilled and unaware of it.* This overconfidence effect is well-documented; detecting it early is the core pedagogical value of confidence marking.

---

## Proposed Scoring Matrix for FunSheep

Combining correctness (system-measured) and confidence (student-reported):

```
                        STUDENT CONFIDENCE
                  Don't Know  Not Sure    I Know
               ┌───────────┬───────────┬───────────┐
CORRECT        │  Lucky    │  Shaky    │  Solid    │
               │  Guess    │  Ground   │  Mastery  │
               │  → loop   │  → loop   │  → probe  │
               ├───────────┼───────────┼───────────┤
INCORRECT      │  Honest   │  Normal   │  Danger!  │
               │  Weak     │  Weak     │  Overconf │
               │  → weak   │  → weak   │  → HIGH   │
               │  pool     │  pool     │  priority │
               └───────────┴───────────┴───────────┘
```

### Six Outcomes Mapped to Skill State Transitions

| # | Correct? | Confidence | Label | Skill Disposition | Next Action |
|---|---|---|---|---|---|
| 1 | ✓ | I Know | **Solid Mastery** | Credit toward mastery streak | Proceed to depth probe (I-3) |
| 2 | ✓ | Not Sure | **Shaky Ground** | Partial credit — do NOT count toward mastery streak | Loop for consolidation |
| 3 | ✓ | Don't Know | **Lucky Guess** | No credit — treat as incorrect for mastery purposes | Flag as weak, same flow as incorrect |
| 4 | ✗ | I Know | **Dangerous Overconfidence** | Mark weak + overconfidence flag | Priority weak pool; use misconception explanation first |
| 5 | ✗ | Not Sure | **Honest Weakness** | Mark weak (standard) | Standard weak-pool practice |
| 6 | ✗ | Don't Know | **Acknowledged Gap** | Mark weak | Standard weak-pool practice |

---

## Impact on Existing Invariants (PRODUCT_NORTH_STAR.md)

| Invariant | Change Required |
|---|---|
| **I-2** Confirm on wrong | No change — wrong answers still trigger confirmation |
| **I-4** Weak flag | Extended: outcomes 3, 4, 5, 6 all mark weak; outcome 2 blocks mastery streak |
| **I-9** Mastery = N correct in a row | Restrict to "I Know" responses only — "Not Sure" correct does not count toward streak |
| **I-10** Readiness via weakest-N | Overconfidence (outcome 4) could weight readiness negatively beyond standard weak |
| **I-14** Explanation on weak | Outcome 4 (overconfidence) should surface misconception-focused explanation, not just re-explanation |

New proposed invariant:

> **I-17 (proposed).** A correct answer MUST carry a "I Know" confidence rating to count toward a mastery streak. Correct answers with "Not Sure" or "Don't Know" reset the streak or provide no streak credit.

---

## Data Model Changes Required

### `question_attempts` table — add `confidence` field

```elixir
# New field in question_attempt.ex schema
field :confidence, Ecto.Enum, values: [:dont_know, :not_sure, :i_know]
```

Migration: `ALTER TABLE question_attempts ADD COLUMN confidence VARCHAR(20)` — nullable (existing records have no confidence data).

### Derived signal: `effective_correctness`

Rather than changing the `is_correct` boolean (historical data must be preserved), compute an effective signal:

```elixir
def effective_correctness(is_correct, confidence) do
  case {is_correct, confidence} do
    {true,  :i_know}    -> :strong       # counts toward mastery streak
    {true,  :not_sure}  -> :partial      # no streak credit
    {true,  :dont_know} -> :lucky_guess  # treated as weak
    {false, :i_know}    -> :overconfident # high-priority weak
    {false, :not_sure}  -> :weak
    {false, :dont_know} -> :weak
    {_, nil}            -> :binary       # legacy: use is_correct as-is
  end
end
```

### `readiness_scores` — add overconfidence signal

Track per-skill overconfidence rate so it can surface in the student dashboard and parent reports:

```elixir
# In skill_scores map, add per-skill fields:
%{
  "section_id" => %{
    correct: 4,
    total: 6,
    score: 66.7,
    status: :weak,
    overconfidence_count: 1,    # times answered wrong with "I Know"
    lucky_guess_count: 0         # times answered correct with "Don't Know"
  }
}
```

---

## UI Considerations

### Button Labels

The three buttons replace the existing two-button model. Exact labels matter for student honesty:

| Option | Label | Notes |
|---|---|---|
| A | "I Don't Know" / "Not Sure" / "I Know" | Clear but clinical |
| B | "No Idea" / "Kinda" / "Definitely" | More natural/casual |
| C | "Guessing" / "Unsure" / "Confident" | Explicitly acknowledges guessing |

**Recommendation:** Option A with distinct visual weights — "I Don't Know" in muted gray, "Not Sure" in neutral, "I Know" in the primary green (#4CD964). This visually signals that "I Know" is the high-stakes choice.

### When to Show Buttons

Two timing models used in practice:
1. **Prospective (before revealing answer):** Student commits to confidence before seeing if they're right. More accurate, but slows UI.
2. **Retrospective (after seeing answer):** Student rates how well they knew it. Faster UX, slightly less honest.

Anki uses retrospective (after revealing). CBM academic systems use prospective (before revealing).

**Recommendation for FunSheep:** Use the existing pattern where answer is submitted first, then show the three confidence buttons *alongside* the answer result. This is retrospective but fits the current flow where "Next" replaces answer submission. The student sees correct/incorrect feedback and then chooses their confidence level before moving on.

---

## Implementation Phases (Suggested)

### Phase 1 — Data Layer (Low Risk)
- Add `confidence` enum column to `question_attempts`
- Add `effective_correctness/2` function to mastery module
- No UI changes; column is nullable for backward compat

### Phase 2 — UI: Three Confidence Buttons
- Replace existing two-button `mark_known` / `mark_unknown` events with three events: `mark_dont_know`, `mark_not_sure`, `mark_i_know`
- Each event records `confidence` alongside `is_correct`
- No change to downstream scoring yet — observe distribution first

### Phase 3 — Scoring Integration
- Mastery streak counts only `:strong` (`correct + i_know`) responses
- Lucky guesses (`correct + dont_know`) enter weak pool
- Overconfident wrong answers get priority slot in weak pool

### Phase 4 — Readiness & Reporting
- Surface overconfidence rate per skill in student/parent dashboard
- Adjust readiness score weighting to discount shaky ground

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Students game the system by always clicking "Don't Know" to avoid penalty | "Don't Know" on a correct answer sends to weak pool — no gaming benefit |
| Students always click "I Know" hoping for mastery credit | Wrong + "I Know" is high-priority weak — penalizes overconfidence |
| UI friction slows down practice sessions | Retrospective placement minimizes disruption; buttons appear after answer feedback already visible |
| Historical data lacks confidence → readiness score gaps | Keep legacy `is_correct` path active; only enrich new attempts |
| Overconfidence flag distresses students | Frame in dashboard as "confidence calibration" not "overconfidence" — neutral language |

---

## References

1. Gardner-Medwin, A.R. (1995). *Confidence Assessment in the Teaching of Basic Science.* ALT-J, 3(1), 80–85.
2. Gardner-Medwin, A.R. & Gahan, M. (2003). *Formative and summative confidence-based assessment.* 7th CAA Conference Proceedings.
3. Ye, S. et al. (2022). *A New Algorithm for Spaced Repetition (FSRS).* Supermemo Research.
4. Kornell, N. & Bjork, R.A. (2008). *Learning concepts and categories.* Psychological Science, 19(6), 585–592.
5. Kruger, J. & Dunning, D. (1999). *Unskilled and unaware of it.* JPSP, 77(6), 1121–1134.
6. Duolingo Research (2021). *Half-Life Regression for Adaptive Learning.*
