# FunSheep Platform Quality Assessment

**Role**: AP Biology Teacher  
**Course**: AP Biology (Grade 11)  
**Date**: April 23, 2026  
**Scope**: Diagnostic → Weak Topic Identification → Practice Generation → Session-over-Session Update Loop

---

## 1. Mock Assessment (Diagnostic) — What Happens

**Setup:** Student creates a test schedule for AP Biology, scoped to Ch. 7 (Cellular Respiration), Ch. 9 (Cell Cycle), Ch. 10 (Meiosis), Ch. 11 (Mendel), Ch. 13 (Molecular Basis of Inheritance) — the 5 "strong" chapters with 50–90+ passed questions each.

**Engine behavior (code-traced in `engine.ex`):**

The adaptive diagnostic logic is genuinely well-built:
- Starts at medium difficulty (0.5), adjusts ±0.15 per answer
- On a wrong answer → triggers a "confirm" probe on the same section at same-or-lower difficulty (I-2)
- Two wrongs → marks section as `:weak` (I-4)
- On a correct answer at medium+ with ≥2 attempts → fires one harder depth probe (I-3)
- Max 6 questions per chapter, advances when mastered (≥70% correct, ≥3 attempts)

**What would actually happen for those 5 chapters:** The engine would function correctly. Those chapters have enough passed, section-tagged questions. A student weak in Meiosis I would get a confirm probe, get marked `:weak`, and the engine would surface that in the summary.

**For the other ~25 AP Biology chapters (Ch. 14–39, Ch. 5, etc.):** The engine immediately hits `:no_more` (zero passed questions), enqueues AI generation, silently skips the chapter. The student never gets assessed on those topics. The diagnostic is structurally incomplete for 70%+ of AP Biology content.

**Assessment engine verdict:** ✅ Algorithm is correct | ❌ Question pool is too thin to execute it on most chapters

---

## 2. Post-Diagnostic: Does the Student Know What to Do?

After the diagnostic completes, the summary screen shows:
- Overall score (e.g., "47%")
- Topic breakdown: each chapter shows "Needs Work" or "Mastered"
- **Two CTAs: "Back to Tests" and "Retake Assessment"**

**There is no "Practice Weak Topics" button on the diagnostic summary screen.**

The student who just got told Ch. 10 (Meiosis) "Needs Work" has to:
1. Navigate back to tests
2. Find the separate Practice page via the sidebar
3. Manually select "Meiosis" from the chapter dropdown

This is a broken study loop. The diagnostic produces a weak-topic diagnosis but doesn't route the student to the cure. An AP student under time pressure will just retake the assessment instead of practicing — which is the wrong action.

**Transition verdict:** ❌ No "Practice Weak Topics" CTA on the diagnostic summary | ❌ Practice page has no awareness of which diagnostic just ran

---

## 3. Practice Question Alignment with Weak Topics

**What the practice engine actually does (`practice_engine.ex` + `questions.ex`):**

`PracticeEngine.start_practice(user_role_id, course_id)` — note: **no `test_schedule_id`** parameter.

It calls `skill_deficits(user_role_id, course_id)` which looks at ALL question attempts across the ENTIRE course — not just the chapters in scope for the student's test. If this student previously answered Ch. 1 (Chemistry of Life) questions wrong for a different test, those are in their deficit map and will influence the practice pool.

`list_weak_questions(user_role_id, course_id, nil, 60)` — the `nil` chapter_id means no scope filter. Practice draws questions from any chapter where the student has ever gotten anything wrong.

**So: does the practice session reflect the diagnostic's weak topics?**

If this is the student's first-ever session, yes — their only wrong answers are from the diagnostic they just took. The practice will correctly surface Meiosis and Mendel questions.

But if they've used the platform before: **the practice is contaminated with off-scope content.** A student studying for their Ch. 7–13 test may get Ch. 25 (Immune System) questions they missed a month ago for a different test.

**Section-level targeting within chapters:**

For questions the student got wrong, the engine correctly tracks `section_id` (the sub-topic within a chapter). So within "Meiosis," it knows whether they're weak on "Meiosis I" vs "Consequences of Meiosis" and upweights questions from the specific failing section. This is the right granularity.

**But:** The student never sees this. Practice shows "Chapter 10" on the question card — it does NOT tell the student "This question is here because you're weak on *Meiosis I chromosomal separation*." The student has no visibility into which specific skill is being drilled.

**Practice alignment verdict:** ✅ Section-level skill targeting is correctly implemented | ❌ Not scoped to the current test schedule | ❌ Student doesn't know WHY each question appears | ⚠️ Works correctly for first-time students, degrades as history accumulates across multiple tests

---

## 4. What's Wrong and What's Missing

**Critical issues:**

| # | Problem | Impact |
|---|---------|--------|
| **A** | No "Practice Weak Topics" CTA after the diagnostic | Students don't start practice; they retake assessments instead |
| **B** | Practice has no `test_schedule_id` — not scoped to current test | Wrong chapters get drilled |
| **C** | 79.9% of AI questions have empty `explanation` field | On wrong answer: "Incorrect. Correct answer: X" — no learning happens |
| **D** | Practice summary: `improved: correct` — total correct labeled "Improved" | Misleading metric; correct ≠ improved |
| **E** | `no_questions_available` on diagnostic doesn't tell the student what's missing | Silent failure; student thinks diagnostic ran fully |

**Missing pedagogically:**

- **No explanation shown after wrong answer.** In AP prep, the explanation is where the learning happens. Getting a question wrong and seeing only "Correct answer: B" teaches nothing. The Tutor button exists but requires a click and an active AI call — it doesn't auto-surface the explanation that should already exist on the question.
- **No "why this question is here" context.** A good practice session should tell the student: *"You missed 3 of 4 questions on chromosomal crossover. Here's a question on that exact concept."* The platform drills the right questions but never tells the student what to focus on.
- **No study guide or concept summary between diagnostic and practice.** After identifying "Meiosis: Needs Work," a good prep tool says *"Here's what you need to review"* before throwing questions at the student. Currently it just starts drilling.

---

## 5. Performing the Practice Session

**Simulated flow for a student who got Meiosis and Mendel wrong in the diagnostic:**

Session: `PracticeEngine.start_practice(user_role_id, course_id)` fetches:
- `skill_deficits` → e.g., `{"meiosis-I-sec": %{correct: 0, total: 2, deficit: 1.0}, "mendel-sec": %{correct: 1, total: 3, deficit: 0.67}}`
- `list_weak_questions` → the 2 Meiosis I questions and 2 Mendel questions answered wrong, ordered: never-correct first
- `list_review_candidates` → empty (no sections with deficit ≤ 0.3 and ≥ 2 attempts) → no review interleaving
- `compose_session(20 questions)` → 20 questions from the weak pool, weighted by deficit × difficulty
- Meiosis I (deficit=1.0) gets ~3× the weight of Mendel (deficit=0.67), so more Meiosis questions appear

**Does this match the weak topics?** Yes — for a first-session student, the practice correctly targets the weak sections identified in the diagnostic.

**During practice:** The student sees a Meiosis I question. They get it wrong again. `record_answer` updates `skill_deficits` live (I-7), and the remaining tail of questions reweights to add even more Meiosis I. This is correct and educationally sound.

**On "wrong" feedback:** The student sees "Incorrect. Correct answer: Meiosis I results in two haploid cells." No context, no mechanism explanation, no "you might be confusing this with...". Nothing. For AP Biology, where understanding the WHY is essential for free-response questions, this is a failure.

---

## 6. Do Subsequent Practice Sessions Update Correctly?

**Session 2 (student clicks "Practice Again"):**

`PracticeEngine.start_practice(user_role_id, course_id)` reruns from scratch:
- `skill_deficits` recomputes from ALL historical attempts (including session 1 answers) ✅
- If the student got 3 Meiosis I questions right in session 1, that section's deficit drops: `1.0 → 0.25`
- `list_weak_questions` still requires at least one `is_correct = false` attempt. Questions the student now gets right move to lower priority (they have correct attempts), but they don't leave the weak pool until the section deficit drops below 0.3 (the review floor)
- Recently-answered questions are excluded first, with backfill if needed ✅

**Does it correctly update to reflect newly-weak areas?**

Within AP Biology, yes. If in session 1 the student encountered their first questions on Mendel's dihybrid crosses and got them wrong, session 2 will upweight those questions. The deficit-tracking is correct.

**Structural limitation:** The practice pool is fetched once at session start and doesn't grow during a session. If the student reveals a new weakness mid-session (a section they hadn't attempted before), that section can get reweighted in the remaining questions, but only if those questions were already in the initial `weak_pool`. Since `weak_pool = list_weak_questions(limit * 3 = 60)`, sections not in the top-60 wrong questions can't enter the current session even if the student just revealed weakness in them.

**Between sessions, updates work correctly. Within sessions, the pool is static.** This matters most for AP Biology students who have hundreds of weak questions — the within-session tail reranks are meaningful, but the session scope is fixed at launch.

---

## Overall Verdict

| Area | Score | Assessment |
|------|-------|------------|
| **Diagnostic algorithm** | 8/10 | Sound adaptive logic; question pool scarcity limits it to ~5 of 39 chapters |
| **Post-diagnostic routing** | 2/10 | No CTA to practice; student abandoned at summary screen |
| **Practice scope alignment** | 5/10 | Correct for first-time users; unscoped to test schedule for returning users |
| **Practice question quality** | 3/10 | 79.9% missing explanations; feedback teaches nothing after wrong answer |
| **Session-to-session updates** | 7/10 | Deficit-based re-ranking is correct and pedagogically sound |
| **Student transparency** | 2/10 | Student never knows which skill is weak or why a question was chosen |
| **AP exam readiness signal** | 4/10 | Readiness % is a reasonable heuristic but based on 24.4% of the question pool |

**Bottom line:** The engine logic is the right idea, but the product breaks down at the three most important moments — after the diagnostic (no routing), during wrong-answer feedback (no explanation), and in scope management (no test schedule linkage). A student who uses this platform diligently will practice questions in the right skill areas, but they'll do so without understanding what they're practicing or why, and on questions that give them no explanation when they fail.

---

## Priority Fix List

1. **Add "Practice Weak Topics" button to diagnostic summary** — routes to `/courses/:id/practice` with `schedule_id` param so practice is pre-scoped to the test's chapters
2. **Pass `test_schedule_id` into `PracticeEngine`** — scope `list_weak_questions` and `skill_deficits` to the schedule's `chapter_ids`
3. **Run auto-correction pipeline on 2,294 AI questions missing explanations** — the pipeline exists; run it
4. **Show explanation inline after wrong answer in practice** — don't require a Tutor click; surface `question.explanation` directly in the feedback card
5. **Show the skill name on the practice question card** — "Practicing: Meiosis I chromosomal separation" makes the drill purposeful
6. **Fix `improved` metric** — it currently equals `correct`, which is meaningless; compute actual questions-gone-from-wrong-to-right within the session
