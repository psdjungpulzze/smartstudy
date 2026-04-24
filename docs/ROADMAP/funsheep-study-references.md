# Study References — Feature Roadmap

**Status**: Planning  
**Scope**: Inline practice references, Readiness Study Hub, video/textbook resource system  
**Depends on**: Existing `questions.explanation`, `figures` schema, `sections` table, `skill_scores`, Readiness by Topic roadmap

---

## 1. What Are Study References?

Study References are supplementary materials tied to a specific **skill tag** (section) that help a student understand *why* a concept works — not just whether their answer was right or wrong. They include:

| Material Type | Description | Source |
|---|---|---|
| **AI Explanation** | A short, personalized explanation of the underlying concept, woven with the student's hobbies | AI generation (static per question, or on-demand per topic) |
| **Video Lessons** | Curated YouTube / Khan Academy clips matched to the skill tag | Manually curated or YouTube API search |
| **Textbook References** | Images of the relevant textbook pages (figures) or a page-range citation | Already extracted via OCR pipeline into `figures` table |

---

## 2. Where to Show Them — Decision & Rationale

**First principle**: FunSheep is a test readiness assessment tool, not a tutoring platform. Study references exist to give students an escape hatch when they're stuck — they are never the focus. The UI must communicate this: resources are secondary, quiet, and opt-in. If a student ignores them entirely and keeps practicing, that is the intended behavior.

This was the hardest design question. Three candidate surfaces:

| Surface | Verdict | Reason |
|---|---|---|
| **Inside every question (assessment)** | ❌ Wrong surface | Assessment is diagnostic — showing teaching material during questions biases readiness scores and breaks the engine's adaptive logic. Teaching here undermines I-2 through I-4. |
| **After every answer in assessment** | ❌ Wrong surface | Same reason; also makes the assessment feel like a quiz game, not a diagnostic. The summary screen is acceptable but not per-question. |
| **After wrong answers in practice** | ✅ Primary surface | Practice IS the teaching moment. The student has already seen they were wrong. The tutor, explanation, and figures are already there — study references slot naturally into this feedback panel. |
| **After any answer in practice** | ✅ Acceptable for video | Video links can appear after correct answers too — watching a short video on a concept you got right reinforces mastery. Keep it subtle (collapsed by default). |
| **Readiness by Topic page** | ✅ Primary surface for topic-level | This is the "study planning" surface. A student preparing for a topic looks here first. Full resource list per topic belongs here. |
| **Assessment summary screen** | ✅ Light touch | Post-diagnostic, showing "here are resources for your weak topics" is appropriate because the diagnostic is complete. One CTA per weak topic — no deep content, just a gateway. |

### The Verdict: A Tiered Architecture

> **Core UI principle — ultra-discrete by design.** FunSheep's purpose is to assess test readiness, not to teach. Study references are escape hatches for students who need them, not the main event. Every tier must feel secondary: collapsed by default, small typography, muted color, never full-width or prominent. A student who wants to keep practicing should barely notice these resources exist.

```
Tier 1 — Reactive (Practice answer feedback)
  Trigger: Student submits a wrong answer
  Surface: Below the answer feedback card in practice_live.ex
  Content: AI explanation (existing) + relevant video link + textbook page reference
  Philosophy: You just saw you were wrong — here's a quiet pointer to the concept if you want it
  Default state: Collapsed. One small link/chip, not a panel. Student opts in.

Tier 2 — Proactive (Readiness → Topic Study Hub)
  Trigger: Student clicks a weak topic in their Readiness dashboard
  Surface: /courses/:id/study/:section_id (slide-in panel preferred; full page for MVP)
  Content: Topic overview, curated videos, textbook chapter reference, recent wrong questions
  Philosophy: Student explicitly chose to study — now give them everything in one place
  Default state: This is the one surface where content can be full-width; student is here to study

Tier 3 — Light post-diagnostic (Assessment summary)
  Trigger: Assessment complete
  Surface: Inline CTA beside each weak topic row in the summary screen
  Content: "Study materials →" link only — no content rendered inline
  Philosophy: You've been diagnosed — here's a quiet pointer to where to start
  Default state: A small secondary link. Summary screen stays clean and focused on scores.
```

---

## 3. What Already Exists (Do Not Rebuild)

Before writing a line of code, the following is already built and must be reused:

| Capability | Where | Notes |
|---|---|---|
| `questions.explanation` | `questions` schema, `explanation` field | Already generated (non-empty enforced at AI worker). Shown in practice after wrong answer. |
| `questions.hobby_context` | `questions` schema | Hobbies embedded at generation time per I-11. Explanation already personalized. |
| Tutor (explain/why_wrong/hint) | `practice_live.ex` lines 240–393, `tutor.ex` | Full conversational tutor already wired in practice. Real-time streaming via PubSub. |
| Figures (textbook images) | `figures` schema, `Questions.with_figures/1` | Already loaded in practice; displayed in question card before the stem. |
| Section-level skill tags | `questions.section_id` → `sections` table | Already exists; practice shows skill badge per I-1. Video links should live at this level. |
| Readiness data | `ReadinessScore`, `skill_scores`, `skill_deficits/2` | Already calculated; the Readiness by Topic UI is the missing layer (separate roadmap). |

---

## 4. What Needs to Be Built

### 4A. Video Links Data Model

Video links belong at the **section** (skill tag) level — a video on "Cell Membrane Transport" applies to every question tagged with that section, not to individual questions.

**Migration: Add `video_resources` table**

```sql
CREATE TABLE video_resources (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id   UUID NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
  course_id    UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title        VARCHAR(255) NOT NULL,
  url          TEXT NOT NULL,
  source       VARCHAR(32) NOT NULL,  -- 'youtube' | 'khan_academy' | 'other'
  thumbnail_url TEXT,
  duration_seconds INTEGER,
  inserted_at  TIMESTAMP NOT NULL DEFAULT now(),
  updated_at   TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX video_resources_section_id_idx ON video_resources (section_id);
CREATE INDEX video_resources_course_id_idx ON video_resources (course_id);
```

**Elixir Schema**

```elixir
defmodule FunSheep.Resources.VideoResource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "video_resources" do
    field :title,            :string
    field :url,              :string
    field :source,           Ecto.Enum, values: [:youtube, :khan_academy, :other]
    field :thumbnail_url,    :string
    field :duration_seconds, :integer

    belongs_to :section, FunSheep.Curriculum.Section
    belongs_to :course,  FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  def changeset(video, attrs) do
    video
    |> cast(attrs, [:title, :url, :source, :thumbnail_url, :duration_seconds, :section_id, :course_id])
    |> validate_required([:title, :url, :source, :section_id, :course_id])
    |> validate_url(:url)
  end
end
```

**Context functions needed**

```elixir
defmodule FunSheep.Resources do
  def list_videos_for_section(section_id)
  def list_videos_for_course(course_id)     # for the study hub
  def create_video_resource(attrs)
  def delete_video_resource(video)
end
```

**Why not a JSONB column on `sections`?**  
A separate table makes it straightforward to:
- Query "all videos for a course" (for the study hub)
- Add source-specific metadata later (e.g., YouTube chapter timestamps)
- Build an admin curation interface without schema changes

---

### 4B. Video Curation (How Videos Get Added)

Videos must be curated — not hallucinated. Two valid approaches:

| Approach | When to use | Risk |
|---|---|---|
| **Manual curation** (admin UI) | MVP: teacher/admin adds links for key sections | Labor-intensive at scale |
| **YouTube Data API search** | On-demand: search `"${section.name} ${course.subject} explained"` | Results vary; requires review workflow |
| **Khan Academy mapping** | Course setup: Khan's content library has consistent topic slugs | Best for common AP/SAT subjects |

**Recommendation for MVP**: Manual curation via admin interface. Build the admin page, seed videos for a pilot course (AP Biology), and see what students actually click. Khan Academy URLs for AP subjects are predictable and can be pre-seeded from a mapping table without API calls.

**Do not auto-embed YouTube results without human review.** Off-target or low-quality videos shown to students erode trust.

---

### 4C. Tier 1 — Practice Answer Feedback Enhancement

**File**: `lib/fun_sheep_web/live/practice_live.ex`

**Current feedback block** (after submitting):
```
[✓ Correct / ✗ Incorrect badge]
[Correct answer shown if wrong]
[AI explanation (questions.explanation)]  ← already exists
[Community stats: X% got this right]
[Tutor CTA buttons: Why wrong? / Explain / Step by step / Ask Tutor]
```

**Proposed addition** — ultra-discrete study reference row below the explanation:

```
[✓ Correct / ✗ Incorrect badge]
[Correct answer shown if wrong]
[AI explanation]
[Community stats]
──────────────────────────────────
  ▶ Khan Academy · 4:32  ·  📄 p. 47   ← small, muted, inline chips only
──────────────────────────────────
[Tutor CTA buttons]
```

Design rules:
- **Never an accordion heading or "Study this concept" label** — that frames FunSheep as a tutoring product. Just the chips, no section title.
- **Always collapsed / minimal** — a single row of small chips (source icon + duration or page number). No expanded state in practice; the Study Hub is where expansion happens.
- **Never shown after a correct answer** — don't suggest the student needs to study something they just got right. Only surface resources after a wrong answer.
- **Muted visual weight** — secondary text color, small font, no background card. Should feel like a footnote, not a feature.
- Chips: source icon + duration (video) or "p. XX" (textbook); tap opens link/lightbox in new tab.
- If no video resources exist for the section: render nothing — no empty state, no placeholder.
- Textbook: if the question has figures, show a single "p. XX" chip; tap expands the existing figure lightbox (do not add a new lightbox).

**Implementation touches**:
- In `practice_live.ex mount` or `handle_event("submit_answer")`: preload `section.video_resources` for `current_question.section_id`
- Add `video_resources` to socket assigns
- Add accordion component to the feedback partial (lines ~700–715)

---

### 4D. Topic Study Hub (Tier 2 — Readiness Integration)

This is a new page: **`/courses/:course_id/study/:section_id`**

Or alternatively, a slide-in panel from the Readiness by Topic page when the student clicks a weak topic row. The slide-in is preferred (consistent with the 3-panel layout) but a full page works for MVP.

**What the hub shows:**

```
Section: Membrane Transport (Chapter 3: Cell Structure)

[Concept Overview]
── AI-generated paragraph explaining the concept at the student's level.
   Generated on demand (cached per section); includes the student's hobby
   analogies if profile hobbies exist.

[Video Lessons]  (from video_resources)
── [▶ 4:32] Membrane Transport — Khan Academy
── [▶ 7:11] Osmosis and Diffusion — CrashCourse

[Textbook Reference]
── Pages 47-52 · Chapter 3 · [view pages]

[Practice this topic]  ← launches practice_live filtered to section_id
── "You've answered 5 questions on this topic. 3 were wrong."
── [Practice Now →]

[Your recent wrong questions on this topic]
── Shows last 3 wrong attempts with the question stem (read-only)
── Tapping expands: shows student's answer + correct answer + explanation
```

**AI Concept Overview generation:**
- Triggered on first visit to the hub for that section
- Uses a short one-shot prompt: `"In 2-3 sentences, explain [section.name] to a student preparing for [course.subject]. The student enjoys [hobbies]. Use an analogy from their interests."`
- Cached in a new `section_overviews` table (section_id, user_role_id, body, generated_at)
- On subsequent visits: serve cached version. Regenerate if > 30 days old.
- If generation fails: show only the video + textbook resources (do not block the page with an error)

---

### 4E. Assessment Summary — Light Touch (Tier 3)

**File**: `lib/fun_sheep_web/live/assessment_live.ex` (summary section)

**Current summary per weak topic row:**
```
[Cell Structure]  ✗ Needs Work  2/5 correct  [Practice →]
```

**After change:**
```
[Cell Structure]  ✗ Needs Work  2/5 correct  [Practice →]  [Study materials ↗]
```

The "Study materials" link routes to the Topic Study Hub (`/courses/:id/study/:section_id`). No content rendered inline — keeps the summary clean.

---

## 5. AI Explanation Strategy

### Per-question explanation (already exists)
`questions.explanation` is generated at question creation time and personalized with `hobby_context`. **Do not regenerate this.** It is the right explanation for the right question and is already shown in practice.

### Per-topic overview (new, for Study Hub)
A short, human-readable concept summary for a section — not tied to any specific question. Generated on first visit, cached, hobby-personalized.

**This is the only new AI call this feature introduces.**

Prompt template:
```
You are a study coach helping a student prepare for {course.subject}.
The student enjoys: {hobbies joined by comma, or "general topics" if none}.
In 2-3 clear sentences, explain the concept: "{section.name}".
Use a concrete analogy from one of the student's interests if it fits naturally.
Do not introduce new vocabulary without defining it. Write at grade level {grade_level}.
```

If the student has no hobbies set: omit the analogy instruction. Do not fake a hobby.

---

## 6. What We Are NOT Building (Scope Boundaries)

| Idea | Why Not Now |
|---|---|
| Auto-search YouTube API at study time | Results require human review before showing to students |
| Embedded video player in-app | External link is sufficient; avoids iOS content restrictions and copyright edge cases |
| AI-generated video recommendations | Not reliable enough for high-stakes test prep without curation |
| Per-question video links | Too granular; same video applies across many questions in a section |
| Study references in the diagnostic assessment | Breaks the diagnostic; conflicts with I-2/I-3/I-4 |
| Full in-app textbook viewer | Textbook images (figures) are already extracted; a lightbox over existing figures is enough |

---

## 7. Phased Implementation Plan

### Phase 1 — Foundation (Backend + data model)
- [ ] Create `video_resources` migration and schema
- [ ] Create `FunSheep.Resources` context with CRUD functions
- [ ] Create `section_overviews` migration and schema (for cached AI overviews)
- [ ] Build admin page: `/admin/courses/:id/sections` — list sections, add/edit/delete video links per section
- [ ] Seed pilot course (AP Biology) with Khan Academy video links for top 20 weak sections

**Exit criteria**: Can query `Resources.list_videos_for_section(section_id)` and get real results for at least one full course.

### Phase 2 — Tier 1 (Practice answer feedback)
- [ ] Preload `video_resources` in `practice_live.ex` when a question is loaded
- [ ] Add Study References accordion to the post-answer feedback partial
- [ ] Show collapsed on correct, expanded on wrong
- [ ] Show textbook figure thumbnails inline (use existing figures already loaded)
- [ ] Playwright visual test: practice a seeded question with video resources, screenshot the feedback card

**Exit criteria**: Student submits wrong answer, sees explanation + video chip + textbook page. No video resources → accordion hidden.

### Phase 3 — Tier 2 (Topic Study Hub)
- [ ] Create `FunSheepWeb.Live.StudyHubLive` LiveView at `/courses/:id/study/:section_id`
- [ ] Implement on-demand AI overview generation with caching
- [ ] Show video list, textbook reference, recent wrong questions, Practice CTA
- [ ] Add "Study materials" link from Readiness by Topic page (each weak topic row)
- [ ] Playwright visual test for all three content states (no resources, only video, full)

**Exit criteria**: Student navigates to a weak topic from Readiness, lands on hub, sees concept overview + videos + textbook refs.

### Phase 4 — Tier 3 (Assessment summary light touch)
- [ ] Add "Study materials ↗" CTA to assessment summary weak topic rows
- [ ] Route to Study Hub

**Exit criteria**: Post-assessment, each weak topic row has a study materials link.

### Phase 5 — Video Curation Scale
- [ ] Evaluate YouTube Data API integration for teacher-assisted video discovery
- [ ] Or: build teacher-facing video suggestion interface ("Suggest a video for this topic")
- [ ] Implement review/approval workflow before videos go live

---

## 8. Success Metrics

| Metric | Target | How to measure |
|---|---|---|
| Study References accordion open rate (after wrong answer) | > 50% of wrong-answer feedback views | Event: `study_references_opened` |
| Video click-through rate | > 15% of sessions where references are shown | Event: `video_resource_clicked` |
| Topic Study Hub visits per student per week | > 1 visit among students with ≥ 1 weak topic | Page view telemetry |
| Practice → Study Hub → Practice return rate | > 40% | Session funnel |
| Readiness improvement in topics with curated videos vs without | Measurable positive delta | A/B or cohort comparison |

---

## 9. Open Questions

1. **Who curates videos?** — Teachers? Admins? Both? A teacher-contributed video pool (teacher credit system, see separate roadmap) would scale better than admin-only curation.

2. **Khan Academy deep-link format** — Khan's URLs are stable for courses (e.g., `https://www.khanacademy.org/science/ap-biology/cell-structure-and-function`). Can we pre-map FunSheep sections to Khan slugs at course setup time, or does it require manual matching per section?

3. **Textbook page citations in Study Hub** — The `figures` table has page numbers from OCR. Should the Study Hub show a "Textbook: pages 47-52" citation even when no figure was attached to a specific question, if figures exist for that chapter? (Answer: yes — query figures by `chapter_id` rather than `question_id` for the hub view.)

4. **Section overview caching per user vs per section** — The hobby-personalized overview is per-user (different students get different analogies). This means N student × M section cache entries. Alternative: generate a generic overview per section (no hobbies), and let the tutor handle personalization. Simpler, but less personal.

5. **Grade level in prompts** — The section overview prompt uses `grade_level`. Where does this live? Currently on the test schedule? Course? Student profile?
