# TOC Rebasing — Design

**Status:** Draft — awaiting approval before implementation
**Owner:** Peter (reviewing) / Claude (implementing)
**Branch:** `feat/toc-rebasing`
**Date:** 2026-04-22

---

## The problem

A FunSheep course's table of contents (TOC) — its chapter + section structure — is discovered from whatever material is available:

1. **Web discovery** (first pass, before any upload) — scraped study sites, question-bank listings. Usually approximate.
2. **Partial textbook upload** — a few chapters OCR'd; TOC discovered from those.
3. **Full textbook upload** — the real table of contents, 20-50 chapters.

Today, whichever ran first wins. The current `EnrichDiscoveryWorker` does `Repo.delete_all(chapters)` then recreates from the latest OCR. That's destructive: it blows away any question/attempt history tied to the old chapters.

Seen in prod 2026-04-22: course `d44628ca` stuck at 16 chapters from web-discovery. A full AP Bio textbook upload (OCR'd) would reveal ~42 real chapters. But the student has already logged 25 attempts against the 16 chapters — we can't just delete them.

## The product invariant

> Everything in the course is based on the most complete textbook source available, and no student work is lost when the TOC advances.

## Completeness — how do we decide TOC A is "better" than TOC B?

Three signals, combined into a single score:

| Signal | Weight | Why |
|---|---|---|
| **Source authority** | Highest | `textbook_full > textbook_partial > web` — the textbook is ground truth |
| **Chapter count** | Medium | More chapters ≈ more complete (heuristic, not absolute) |
| **OCR character volume** | Medium | More extracted text → more confident discovery |
| **Overlap with current** | Informational | Higher overlap = safer rebase; low overlap = warning |

Proposed score:

```
authority_weight = %{web: 1, textbook_partial: 3, textbook_full: 10}
score(toc) = authority_weight[toc.source] * log(1 + toc.chapter_count) * log(1 + toc.ocr_char_count)
```

A new TOC *replaces* the current one only if `score(new) > score(current) * 1.2` (20% meaningful improvement gate, avoids thrashing on each discovery run).

## Preserving attempts during rebase

**Never delete a chapter that has attempts against its questions.** The rebase is a join, not a replace:

```
For each chapter in new_toc:
  If fuzzy-matches (normalized name, trigram sim ≥ 0.6) a current chapter → keep current chapter id, rename to new
  Else → create new chapter

For each current chapter not matched:
  If has questions with attempts → keep as-is, flag "orphan in new TOC"
  Else → delete
```

Result: student's `question_attempts` stay valid because `question.chapter_id` is preserved for any chapter that had activity. Orphan chapters (in old but not new) remain visible but get a warning.

## Data model

Add one table:

```elixir
# priv/repo/migrations/..._create_discovered_tocs.exs
create table(:discovered_tocs, primary_key: false) do
  add :id,              :binary_id, primary_key: true
  add :course_id,       references(:courses, type: :binary_id, on_delete: :delete_all), null: false
  add :source,          :string, null: false  # "web" | "textbook_partial" | "textbook_full"
  add :chapter_count,   :integer, null: false
  add :ocr_char_count,  :integer, default: 0
  add :chapters,        :map, null: false      # [{name, sections: [name]}...]
  add :score,           :float, null: false
  add :applied_at,      :utc_datetime          # null = candidate; set = this is the current TOC
  add :superseded_at,   :utc_datetime          # set when a better TOC replaces it
  timestamps(type: :utc_datetime)
end

create index(:discovered_tocs, [:course_id, :applied_at])
create index(:discovered_tocs, [:course_id, :score])
```

Every discovery run inserts a row. The "current" TOC is the one with the most recent non-null `applied_at` and null `superseded_at`.

## Flow

### Before (current, destructive)

```
OCR done → EnrichDiscoveryWorker → delete chapters → discover from OCR → insert chapters → generate questions
```

### After

```
OCR done → EnrichDiscoveryWorker → discover from OCR → TOCRebase.propose/2
    ↓
  score(new) > score(current) * 1.2?
    ├─ yes → TOCRebase.apply/2 (join-not-replace, preserves attempts)
    │         ↓
    │       mark new TOC applied, old superseded
    │       generate questions for any NEW chapters
    │
    └─ no  → store as candidate row, do nothing (no user-visible change)
```

### Admin visibility

- `/admin/courses/:id` grows a "TOC history" section showing all discovered TOCs (score, source, applied status).
- For course owners: a small "A more complete textbook has been detected — 42 chapters vs 16" banner on course detail, with an "Apply" button that calls `TOCRebase.apply/2`.

## Module layout

```
lib/fun_sheep/courses/
  toc_rebase.ex         # context — propose/apply/score/compare
  discovered_toc.ex     # schema
lib/fun_sheep/workers/
  enrich_discovery_worker.ex  # modified — stops deleting, calls TOCRebase
lib/fun_sheep_web/live/
  course_detail_live.ex       # modified — TOC upgrade banner
  admin_courses_live.ex       # modified — TOC history drawer
```

## Open questions / explicit scope decisions

1. **Auto-apply vs. admin-approve?** Proposed: auto-apply when score beats current by 1.2×, *and* the new TOC fuzzy-contains every chapter that has student attempts (safety). Otherwise surface as a pending suggestion. Want it more conservative?
2. **What about sections?** Sections (sub-skills) matter for adaptive signals. For v1 I'll preserve sections on matched chapters and add new sections from new TOC. Deleting sections follows the same attempt-safety rule.
3. **Backfill for existing courses?** Not in v1. Course `d44628ca` specifically won't auto-upgrade — owner would have to re-upload or click a "Re-run TOC discovery" admin button (deferred to v2).
4. **Question re-mapping?** When chapter A is renamed to match new TOC chapter A', questions stay on A' (since same id). When a new chapter A'' is discovered that didn't exist, existing questions are NOT moved to it — they stay on whichever chapter they were generated against. `QuestionClassificationWorker` handles re-categorization separately.

## v1 shipping list

- [ ] Migration + `DiscoveredTOC` schema
- [ ] `Courses.TOCRebase` context: `score/1`, `compare/2`, `propose/3`, `apply/2`, `list_history/1`
- [ ] `EnrichDiscoveryWorker` rewired to use `TOCRebase.propose/3` instead of `delete_all + insert`
- [ ] Admin UI: TOC history drawer on course row
- [ ] Owner UI: "TOC upgrade available" banner on course detail (only when not auto-applied)
- [ ] Tests: scoring, rebase join math, attempt preservation, admin drawer render
- [ ] One-off mix task or admin button to trigger `TOCRebase.propose_from_ocr/1` for an existing stuck course (useful for recovering `d44628ca`)

## Out of scope (explicitly)

- Cross-course TOC sharing / templates
- Teacher-curated canonical TOCs
- AI-driven section-to-section migration (we just match by name for v1)
- LiveView push updates during rebase (it's usually sub-second; users don't need a progress bar)

---

## Implementation plan (once approved)

1. Migration + schema (~30 LOC)
2. `TOCRebase` context with scoring + compare + apply — heart of the feature (~200 LOC)
3. Hook into `EnrichDiscoveryWorker` (~50 LOC diff — mostly removing the `delete_all`)
4. Admin UI: history drawer (~80 LOC)
5. Owner UI: upgrade banner (~40 LOC)
6. Tests: +15–20 tests across context + worker + LiveView
7. Visual verify via Playwright before PR ready

Open PR when steps 1–6 are green. Expected PR size: ~600 LOC.
