# Question Bank — Feature Roadmap

**Status**: Planning  
**Route**: `/courses/:course_id/questions`  
**Depends on**: Existing `QuestionBankLive`, `Questions` context, `Course → Chapter → Section` hierarchy

---

## 1. Context & Goal

The `/courses/:course_id/questions` route and `QuestionBankLive` already exist, but they render a **flat list** of questions with sidebar filters. At small scale this works; at thousands of questions per course it collapses.

The goal of this feature is to turn the question bank into a **genuinely usable management and browsing surface** — hierarchically organized by the textbook's Chapter → Section structure, with role-appropriate access controls and tools for each of the four roles (admin, teacher, student, parent).

---

## 2. Role Matrix

| Capability | Admin | Teacher | Student | Parent |
|---|:---:|:---:|:---:|:---:|
| Browse questions grouped by Chapter → Section | ✅ | ✅ | ✅ | ✅ |
| See **all validation statuses** (pending, needs_review, failed) | ✅ | ❌ | ❌ | ❌ |
| See only **passed** (validated) questions | ✅ (can toggle) | ✅ (default) | ✅ (only) | ✅ (only) |
| Create questions | ✅ | ✅ (school-scoped) | ❌ | ❌ |
| Edit questions | ✅ (any) | ✅ (own school's) | ❌ | ❌ |
| Delete questions | ✅ (any) | ✅ (own school's) | ❌ | ❌ |
| Approve / reject in review queue | ✅ | ❌ | ❌ | ❌ |
| See coverage analytics (questions per chapter × difficulty) | ✅ | ✅ | ❌ | ❌ |
| See question source type (generated, uploaded, scraped) | ✅ | ❌ | ❌ | ❌ |
| See classification status | ✅ | ❌ | ❌ | ❌ |
| See student attempt counts / stats | ✅ | ✅ (own school) | ❌ | ❌ |
| Export questions | ✅ | Planned | ❌ | ❌ |

**Teacher scoping rule**: A teacher can only see/edit questions where `school_id` matches their own `UserRole.school_id`. Questions with `school_id = nil` (global/shared pool) are visible but not editable by teachers.

**Student rule**: Only questions with `validation_status: :passed` are shown. No admin metadata visible. Read-only.

**Parent rule**: Mirrors student visibility. This is not a core use-case — parents browsing the question bank is informational at best. Show the same view a student sees for that course.

---

## 3. The Core UX Problem: Thousands of Questions

Flat lists break at scale. The fix is **hierarchical lazy loading** anchored to the textbook structure.

### 3.1 Browsing Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│  AP Biology — Question Bank                   [+ Add Question]  │
│                                                                  │
│  ┌───────────────────────┐  ┌──────────────────────────────────┐│
│  │ CHAPTERS              │  │ Chapter 1: Cell Biology      (87) ││
│  │                       │  │ ──────────────────────────────── ││
│  │ ▶ Ch 1: Cell Biology  │  │ 1.1  Cell Structure          (24) ││
│  │   87 questions        │  │ 1.2  Cell Membrane           (18) ││
│  │                       │  │ 1.3  Transport               (22) ││
│  │ ▼ Ch 2: Genetics      │  │ 1.4  Cell Cycle              (23) ││
│  │   104 questions       │  │                                   ││
│  │   ├ 2.1 DNA Structure │  │ [Selected: Section 1.1]           ││
│  │   ├ 2.2 Transcription │  │                                   ││
│  │   └ 2.3 Translation   │  │ ┌──────────────────────────────┐  ││
│  │                       │  │ │ Q: What is the primary...    │  ││
│  │ ▶ Ch 3: Evolution     │  │ │ Type: Multiple Choice        │  ││
│  │   63 questions        │  │ │ Difficulty: Medium           │  ││
│  │                       │  │ │ [Edit] [Delete]              │  ││
│  └───────────────────────┘  │ └──────────────────────────────┘  ││
│                              │ ┌──────────────────────────────┐  ││
│  FILTERS                     │ │ Q: The cell wall is made...  │  ││
│  Type: [All ▾]               │ │ Type: True/False             │  ││
│  Difficulty: [All ▾]         │ │ Difficulty: Easy             │  ││
│  Status: [Passed ▾]  (admin) │ │ [Edit] [Delete]              │  ││
│                              │ └──────────────────────────────┘  ││
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Key Design Decisions

**Left panel — Chapter tree (always visible)**
- Lists all chapters with total question count badge
- Clicking a chapter expands it to show sections
- Clicking a section loads that section's questions in the right panel
- Clicking a chapter header loads all questions for that chapter (paginated)
- "All questions" link at top for when you need the full firehose (admin only, paginated)

**Right panel — Question list (lazy loaded)**
- Only loads questions for the selected chapter or section
- Paginated: 25 per page (keeps DOM manageable)
- Each card shows: question text (truncated to 2 lines), type badge, difficulty badge
- Admin/teacher: also shows validation status badge, source type
- Click to expand inline (no page navigation) for full question text, options, explanation

**No "flat list with filters" mode** (current state)
- The current flat-list approach is replaced entirely for admin/teacher
- Students and parents get a read-only version of the same hierarchical layout

---

## 4. UI Surfaces by Role

### 4.1 Admin View

**Primary goal**: Manage quality and coverage of the entire question pool for a course.

**Additional panels above the question list**:

**Coverage Summary bar** (collapsible, shown at top):
```
Coverage: 87% of sections have ≥5 questions
  Easy ████████░░  78%    Needs review: 14    Failed: 3    Pending: 22
  Med  ██████████  94%
  Hard ████████░░  81%
```

**Admin-only filter toggles**:
- Validation status: All / Pending / Passed / Needs Review / Failed
- Classification status: All / Uncategorized / AI Classified / Admin Reviewed / Low Confidence
- Source type: All / AI Generated / Web Scraped / User Uploaded / Curated

**Inline question actions**:
- Edit (opens inline form)
- Delete (with confirm)
- Approve (if status = needs_review or pending)
- Reject (if status = needs_review)
- View validation report (expandable accordion)

**Batch selection** (for bulk operations):
- Select all in section / chapter
- Bulk approve
- Bulk delete

### 4.2 Teacher View

**Primary goal**: See the question pool for their school's students, optionally add school-specific questions.

**Same hierarchical layout as admin**, with:
- No validation status filter (shows only `:passed` questions by default)
- No source type filter
- No classification status filter
- Coverage summary: simplified (just question counts per section)
- Add question: only allowed if `school_id` matches teacher's school OR if admin created course
- Edit/Delete: only for questions where `school_id == teacher.school_id`

**Attempt stats** (teacher-specific):
- Each question card optionally shows: "X students in your school have answered this — YZ% correct"
- Requires a query scoped to `school_id` on `question_attempts` join

### 4.3 Student View

**Primary goal**: Browse what questions exist in the bank for a course (informational, not a core flow — students normally encounter questions via adaptive practice, not manual browsing).

**Simplified read-only layout**:
- Same chapter/section tree on left
- Questions shown without admin metadata (no validation status, no source type)
- No add/edit/delete actions
- Can optionally see their own attempt history inline: "You answered this correctly 2/3 times"
- No coverage analytics

**Gating consideration**: Should students even have access to this page? Arguments:
- **For**: Transparency — students can see what they're working toward
- **Against**: Spoils the adaptive flow if students memorize questions before attempting them

**Recommendation**: Gate behind a feature flag or course setting. Default: **hidden for students**. Admin/teacher can enable per-course. See Section 7 for implementation.

### 4.4 Parent View

Mirror of student view. Parents see the same questions a student in that course would see. Used for "what is my child being tested on?" conversations. Purely read-only, no attempt history shown (that's on the progress/readiness pages).

---

## 5. Data & Context Functions Needed

### 5.1 What Already Exists (Don't Rebuild)

| Function | File | Purpose |
|---|---|---|
| `list_questions_by_course/2` | `questions.ex` | Student-visible questions with filters |
| `list_all_questions_by_course/2` | `questions.ex` | Admin: all statuses with filters |
| `coverage_by_chapter/1` | `questions.ex` | (chapter_id, difficulty) counts |
| `classification_coverage/1` | `questions.ex` | Classification status breakdown |
| `QuestionBankLive` | `question_bank_live.ex` | Existing LiveView (needs redesign) |

### 5.2 New Context Functions Needed

**`Questions.list_chapter_section_counts(course_id, role_filter)`**  
Returns a map of `%{chapter_id => %{total: N, by_section: %{section_id => N}}}` for the left-panel tree. Accepts `:all` or `:passed` as `role_filter`. Called once on mount to build the sidebar — does NOT load question content.

```elixir
@spec list_chapter_section_counts(binary(), :all | :passed) :: map()
```

**`Questions.list_questions_for_section(section_id, role_filter, opts)`**  
Paginated question list for a single section. Returns `{questions, total_count}`.

```elixir
@spec list_questions_for_section(binary(), :all | :passed, keyword()) ::
  {[Question.t()], non_neg_integer()}
```

**`Questions.list_questions_for_chapter(chapter_id, role_filter, opts)`**  
Same but for an entire chapter (when user clicks chapter header). Paginated.

```elixir
@spec list_questions_for_chapter(binary(), :all | :passed, keyword()) ::
  {[Question.t()], non_neg_integer()}
```

**`Questions.list_questions_for_section_with_attempt_stats(section_id, school_id, opts)`**  
Teacher-specific: attaches per-school attempt stats to each question.

**`Questions.coverage_summary(course_id)`**  
Admin coverage bar: returns `%{total_sections: N, sections_with_min_questions: N, by_difficulty: %{...}, needs_review: N, failed: N, pending: N}`.

### 5.3 LiveView Architecture

**Replace** the existing flat `QuestionBankLive` with a new layout:

```
QuestionBankLive (mount, params, role dispatch)
  ├── QuestionBankSidebar component (chapter/section tree, counts)
  ├── QuestionBankFilters component (type, difficulty, status — role-scoped)
  ├── QuestionBankList component (paginated question cards for selected chapter/section)
  │     └── QuestionCard component (expand/collapse, role-scoped actions)
  └── QuestionBankCoverage component (admin/teacher only, coverage bar)
```

**State managed in socket assigns**:
- `selected_chapter_id` — nil = "all" (admin only), else specific chapter
- `selected_section_id` — nil = chapter-level view
- `expanded_chapter_ids` — set of chapters with open section list
- `filters` — map of active filters
- `page` — current pagination page
- `questions` — current page of question structs
- `question_counts` — chapter→section count map (loaded once on mount)
- `role` — `:admin | :teacher | :student | :parent`

**`handle_event` needed**:
- `select_chapter` — expand chapter, load section counts if not already loaded
- `select_section` — load questions for section (resets page to 1)
- `set_filter` — update filter, reload questions
- `next_page / prev_page` — pagination
- `delete_question` — admin/teacher only
- `approve_question` — admin only
- `reject_question` — admin only
- `toggle_question_expand` — inline question detail

---

## 6. Implementation Phases

### Phase 1 — Hierarchical Sidebar + Paginated List (Core)

**Scope**: Replace the flat list with the chapter→section tree + paginated question panel. No new admin features yet, just the navigation structure.

**Backend**:
- [ ] Add `list_chapter_section_counts/2` to Questions context
- [ ] Add `list_questions_for_section/3` (paginated)
- [ ] Add `list_questions_for_chapter/3` (paginated)

**Frontend**:
- [ ] Redesign `QuestionBankLive` layout (3-panel: sidebar tree, filters, question list)
- [ ] `QuestionBankSidebar` component with chapter expand/collapse and count badges
- [ ] `QuestionBankList` component with pagination controls
- [ ] `QuestionCard` component (truncated preview + inline expand)
- [ ] Role-based rendering: admin sees all statuses; student/parent see only passed

**Tests**:
- [ ] Unit tests for new context functions
- [ ] LiveView test for mount, chapter select, section select, pagination
- [ ] LiveView test confirming students cannot see non-passed questions

**Visual verification**: Playwright screenshot of chapter tree expanded, question card displayed

---

### Phase 2 — Admin Coverage Dashboard + Bulk Actions

**Scope**: Give admins the coverage summary bar and batch operations.

**Backend**:
- [ ] Add `coverage_summary/1` to Questions context
- [ ] Add `bulk_approve_questions/2` (list of ids, reviewer_id)
- [ ] Add `bulk_delete_questions/2` (list of ids)

**Frontend**:
- [ ] `QuestionBankCoverage` component (coverage bar, breakdown by difficulty)
- [ ] Admin filter extensions (validation status, classification status, source type)
- [ ] Checkbox multi-select on question cards
- [ ] Bulk action toolbar (appears when selection > 0)
- [ ] Inline validation report accordion on question card

**Tests**:
- [ ] Unit tests for bulk operations
- [ ] LiveView test for bulk selection + approve
- [ ] LiveView test confirming non-admins cannot access bulk actions

---

### Phase 3 — Teacher School-Scoped View + Attempt Stats

**Scope**: Teacher-specific features: school-scoped editing, per-school attempt stats on cards.

**Backend**:
- [ ] Add `list_questions_for_section_with_attempt_stats/3`
- [ ] Add `can_edit_question?(user_role, question)` authorization helper to Questions context (checks `school_id` match)

**Frontend**:
- [ ] Teacher-scoped edit/delete buttons (only where `question.school_id == teacher.school_id`)
- [ ] Attempt stat micro-label on question cards (teacher view only): "XX% correct, N attempts (your school)"
- [ ] Question creation form pre-sets `school_id` to teacher's school

**Tests**:
- [ ] Test that teacher cannot edit/delete questions from other schools
- [ ] Test attempt stats only include school-scoped attempts

---

### Phase 4 — Student Visibility Gating (Feature Flag)

**Scope**: Make the question bank opt-in for students, controlled per-course.

**Backend**:
- [ ] Add `question_bank_visible_to_students` boolean field to `courses` table (default `false`)
- [ ] Add migration
- [ ] Gate `QuestionBankLive` mount: if student and `!course.question_bank_visible_to_students` → redirect with informative flash

**Frontend**:
- [ ] Course settings admin panel: toggle "Show question bank to students"
- [ ] If hidden: student navigating to `/courses/:id/questions` gets a friendly "Not available" page, not a 404

**Tests**:
- [ ] Test redirect behavior when flag is false for student
- [ ] Test access allowed when flag is true for student

---

## 7. Student Access Gating — Design Decision

**Should students be able to browse the question bank?**

The adaptive learning north star (PRODUCT_NORTH_STAR.md) works by *serving* questions to students via diagnostic/practice flows — students don't choose which questions to answer. Exposing the full question bank to students risks:

1. **Spoiling diagnostics**: A student who browses questions before the diagnostic has prior exposure, skewing weak-topic detection (I-1, I-15 invariants).
2. **Memorization over understanding**: Students who memorize answers rather than learning the material.
3. **Cognitive load**: Browsing thousands of questions is not a learning activity.

**Recommendation**: Default `question_bank_visible_to_students = false`. Allow admin/teacher to enable per-course for edge cases (e.g., open-book courses, review sessions).

Parents follow the same flag as students for that course.

---

## 8. Technical Notes

### What's Already Built (Reuse)

- `list_questions_by_course/2` and `list_all_questions_by_course/2` — valid query foundations; new functions can delegate to shared `base_question_query/2` clauses
- `QuestionBankLive` — the existing LiveView already handles the add-question form and delete; Phase 1 keeps these and adds the hierarchy on top
- `AdminQuestionReviewLive` — the global review queue remains a separate page; the inline approve/reject in Phase 2 is a convenience shortcut, not a replacement
- `coverage_by_chapter/1` — already returns `{chapter_id, difficulty}` tuples; `coverage_summary/1` is a thin wrapper that enriches this with section-level counts and status breakdowns

### Performance Considerations

- **Chapter tree counts**: Run once on mount as an aggregate query, not per-question. Use `group_by` on `chapter_id` + `section_id`.
- **Paginate aggressively**: 25 questions per page. The DOM cannot handle 1000+ question cards.
- **No client-side filtering**: All filtering server-side via Ecto queries. LiveView re-renders the list on filter change.
- **Preloads scoped to the page**: Don't preload chapter/section on every question — they're already known from the selected tree node.

### Authorization Checkpoints

- `QuestionBankLive.mount/3`: Determine role from `conn.assigns[:current_role]`, set `role` assign, determine `can_edit` and `can_create` booleans
- `handle_event("delete_question", ...)`: Re-check `can_edit_question?(socket.assigns.role, socket.assigns.current_user_role, question)` server-side — never trust client-only guards
- `handle_event("approve_question", ...)`: Re-check `socket.assigns.role == :admin` — admin-only operation

---

## 9. Out of Scope (This Roadmap)

- **Question import/export** (CSV, PDF) — separate roadmap item
- **Question tagging / custom labels** — future enhancement
- **Collaborative editing** (multi-user simultaneous edit) — out of scope
- **Version history for questions** — not planned
- **Cross-course question reuse** — questions are course-scoped today; multi-course linking is a larger schema change
- **Search** — full-text search across question content is Phase 5+; use Postgres `ilike` as a stopgap filter in Phase 1

---

## 10. Open Questions

1. **Teacher "own school" question creation scope**: When a teacher adds a question, should it be visible globally (all schools using this course) or only to their school? Current assumption: `school_id` is set to the teacher's school, meaning it's school-scoped. If the answer should be "visible globally", it requires an admin review/approval step first.

2. **Orphaned chapters**: The `orphaned_at` field on Chapter marks chapters that had attempts but don't match a newer textbook ToC. Should orphaned chapters appear in the question bank sidebar? Recommendation: show them in a separate collapsed "Orphaned Chapters" section with a warning badge, so admins can decide what to do with those questions.

3. **Section-less questions**: Questions with `chapter_id` set but `section_id = nil` exist (they were added before section classification). Where do they appear in the tree? Recommendation: Show them under a "Unclassified questions" node within the chapter.

4. **"All questions" entry point for admin**: Admins sometimes need a pure flat list (e.g., for bulk review of newly generated questions). Keep the flat view accessible via a "View All" toggle or a separate `/admin/courses/:id/questions` route that bypasses the hierarchy.
