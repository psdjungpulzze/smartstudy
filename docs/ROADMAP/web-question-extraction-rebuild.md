# Web Question Extraction Pipeline — Architectural Rebuild Plan

**Goal:** Go from ~92 web-scraped questions for SAT Math to tens of thousands of high-quality,
extracted (not AI-created) questions for every standardized test in the roadmap.

**Guiding principle:** Every question shown to a student must be extracted from a real, reputable
source. AI generation is a supplement, not the primary supply.

---

## Three Test Criteria (Apply After Every Phase)

These three questions are the acceptance gate for the entire pipeline. Every phase must move
the needle on all three before it is considered done.

| # | Criterion | How to verify |
|---|-----------|---------------|
| 1 | **Did the search identify reputable, popular sources?** | Check `discovered_sources` — do the domains include College Board, Khan Academy, Albert.io, Varsity Tutors, PrepScholar, Kaplan, Princeton Review, ETS, Magoosh, etc.? Run `SELECT domain, COUNT(*) FROM discovered_sources WHERE course_id = ? GROUP BY domain ORDER BY count DESC` |
| 2 | **Did it extract (not create) questions and answers?** | Spot-check 10 random questions with `source_type = 'web_scraped'`. Navigate to the `source_url` and confirm the question text exists verbatim (or near-verbatim) on that page. Zero tolerance for questions that are AI-invented and tagged as web_scraped. |
| 3 | **Did it extract a large enough volume, or queue up enough sources?** | After discovery: `SELECT COUNT(*) FROM discovered_sources WHERE course_id = ?` must be >= 500 at Phase 1, >= 2000 at Phase 2, >= 10000 at Phase 4. After scraping: `SELECT COUNT(*) FROM questions WHERE course_id = ? AND source_type = 'web_scraped' AND validation_status = 'passed'` must be >= 1000 at Phase 2, >= 5000 at Phase 3, >= 20000 at Phase 5. |

---

## Current State (Baseline)

**What exists:** A 5-stage pipeline that produced only 92 web-scraped questions for SAT Math.

**Root causes (all compounding):**

| Bottleneck | Current value | Impact |
|---|---|---|
| Search queries per section | 3 × 24 sections = 72 total | Caps discovery at ~720 URLs |
| Anthropic `max_uses` per search call | 3 | ~10 URLs per query |
| URL validation pass rate | ~50% | 720 → ~360 valid URLs |
| AI extraction conservatism on messy HTML | High | ~100–120 questions from 360 URLs |
| Validation `:passed` threshold | 95% (calibrated for AI-generated) | Filters out legitimate web content |
| Scraper concurrency | 5 parallel | Slow throughput |
| No known-source targeting | None | Misses most reputable sites |
| No deduplication | None | Wastes API calls on repeat content |

**Key files:**
- `lib/fun_sheep/workers/web_content_discovery_worker.ex` — query generation (lines 305–330, 719–727), search execution (lines 461–480)
- `lib/fun_sheep/workers/web_question_scraper_worker.ex` — concurrency cap line 47, extraction lines 480–511
- `lib/fun_sheep/questions/extractor.ex` — hard gates lines 261–303
- `lib/fun_sheep/questions/validation.ex` — thresholds lines 24–25

---

## Phase 0 — Instrumentation & Baseline (3–5 days)

**Purpose:** You cannot fix what you cannot measure. Before touching any pipeline logic,
add telemetry so every subsequent phase has a before/after number.

### Todos

- [ ] Add `:telemetry.execute/3` calls at these events in existing workers:

  | Event | Where | Metadata |
  |---|---|---|
  | `[:fun_sheep, :discovery, :search_complete]` | After each `search_web/1` call | `%{query: query, results_count: n}` |
  | `[:fun_sheep, :discovery, :url_probe_complete]` | After each HEAD probe | `%{url: url, outcome: :keep | :drop, reason: atom}` |
  | `[:fun_sheep, :scraper, :source_complete]` | End of `scrape_and_extract/2` | `%{source_id: id, url: url, questions_extracted: n, outcome: :ok | :error}` |
  | `[:fun_sheep, :scraper, :extraction_gate_reject]` | Each rejected question in `accept?/1` | `%{reason: atom, source: :ai | :regex}` |
  | `[:fun_sheep, :validation, :verdict]` | After each `apply_verdict/2` | `%{verdict: atom, source_type: atom, score: float}` |

- [ ] Create `lib/fun_sheep/discovery/metrics.ex` with `Telemetry.Metrics` definitions for all events above. Attach to `FunSheepWeb.Telemetry`.

- [ ] Create read-only admin LiveView `FunSheepWeb.AdminWebPipelineLive` at `/admin/web-pipeline` showing:
  - Queries fired in last 24h
  - URL probe pass/fail breakdown
  - Questions extracted per domain
  - Extraction gate rejection reasons
  - Validation pass rate by `source_type`

- [ ] Run a SAT Math course creation and record the baseline numbers in a comment at the top of this document.

### Tests

- [ ] `mix test` passes with all existing tests — no regressions from adding telemetry.
- [ ] Manually verify telemetry fires: `iex> :telemetry.attach("test", [:fun_sheep, :discovery, :search_complete], fn e, m, _ -> IO.inspect({e, m}) end, nil)` then trigger a discovery job.
- [ ] Admin panel loads at `/admin/web-pipeline` with real numbers for the existing SAT Math course.

### Three-criteria check

Run the three criteria queries against the existing SAT Math course and record results as the
official baseline. This is the "before" number every other phase is compared against.

---

## Phase 1 — Discovery Layer: More Queries, Better Sources (1–2 weeks)

**Purpose:** The pipeline currently finds ~720 candidate URLs. This phase targets >= 5,000
reputable URLs for SAT Math by expanding search breadth and adding direct source targeting.

### Todos

**1.1 — Increase `max_uses` cap**
- [ ] In `web_content_discovery_worker.ex` line 478: change `max_uses: 3` to `max_uses: 8`.
  - Effect: each Anthropic search call can run 8 real web searches instead of 3, roughly tripling
    URL yield per query with no code structure change.

**1.2 — Expand query count per section**
- [ ] Expand `sat_search_queries/2` (line 719) from 3 queries to 10 per section:
  ```
  # Existing 3 (keep):
  "SAT math practice questions #{section}"
  "digital SAT #{section} practice problems answers"
  "Khan Academy SAT math #{section}"
  
  # Add 7 more:
  "site:khanacademy.org SAT math #{section} practice"
  "site:collegeboard.org SAT #{section}"
  "site:albert.io digital SAT #{section} questions"
  "site:varsitytutors.com SAT math #{section}"
  "\"SAT math\" \"#{section}\" multiple choice filetype:pdf"
  "SAT #{section} released questions 2023 2024"
  "digital SAT #{section} free practice test answers"
  ```
- [ ] Apply the same expansion pattern to all other test-type query functions
  (`act_search_queries/2`, `gre_search_queries/2`, etc.) or create a generic
  `test_search_queries/3` that handles any test type from the roadmap.
- [ ] **Result:** 24 sections × 10 queries × 8 max_uses ≈ **5,000+ candidate URLs**.

**1.3 — Add search result pagination**
- [ ] Create `lib/fun_sheep/discovery/query_paginator.ex`.
  - Implements multi-page search: page 1 is the standard query; pages 2–3 add
    "different from already-seen URLs" to the prompt to force novel results.
  - Maximum 3 pages per query. Early-exit when page N returns 0 novel URLs.
  - `WebContentDiscoveryWorker` delegates to `QueryPaginator` instead of calling
    `search_web/1` directly.

**1.4 — Direct API adapters for highest-tier sources**
- [ ] Create `lib/fun_sheep/discovery/adapters/khan_academy.ex`
  - Uses Khan Academy's public API (`/api/v1/exercises?channel_slug=sat-math`) to enumerate
    exercise URLs without web search. No auth required for public exercises.
  - Returns `[%{url: url, title: title, domain: "khanacademy.org", tier: 1}]`.
- [ ] Create `lib/fun_sheep/discovery/adapters/college_board.ex`
  - Fetches the College Board's publicly listed practice test PDFs from their known CDN pattern.
    These are static, well-known URLs (8 official SAT practice tests = ~800 math questions).
  - Returns PDF URLs to be processed by the PDF extraction path.

**1.5 — Sitemap crawler for mid-tier sources**
- [ ] Create `lib/fun_sheep/workers/source_sitemap_crawler_worker.ex` (Oban worker).
  - For domains with sitemaps (varsitytutors.com, albert.io), fetches `sitemap.xml`,
    extracts question-page URLs by keyword-matching against section names, stores up to
    200 URLs per domain per course.
  - Enqueued from `WebContentDiscoveryWorker.perform/1` after the regular search pass.

**1.6 — Migration: `add_discovery_strategy_to_discovered_sources`**
- [ ] Add columns to `discovered_sources`:
  ```elixir
  add :discovery_strategy, :string, default: "web_search"
  # Values: "web_search" | "sitemap" | "api_adapter" | "registry" | "seed_url"
  add :scrape_attempts, :integer, default: 0
  add :last_scraped_at, :utc_datetime
  ```
- [ ] Add indexes: `(discovery_strategy)`, `(status, scrape_attempts)`.

### Tests

- [ ] Unit test `QueryPaginator` — mock the search call; assert page 2 excludes URLs from page 1.
- [ ] Unit test Khan Academy adapter — record a real API response as a fixture; assert >= 10 URLs returned for SAT Math.
- [ ] Unit test College Board adapter — assert it returns the 8 known practice test PDF URLs.
- [ ] Integration test: create a course, run discovery, assert `discovered_sources` count >= 500.

### Three-criteria check

After Phase 1:
1. **Reputable sources?** — `SELECT DISTINCT domain FROM discovered_sources WHERE course_id = ?` must include `khanacademy.org`, `collegeboard.org`, `albert.io`, `varsitytutors.com`.
2. **Extraction not creation?** — Not testable until Phase 2 (no scraping yet, just discovery).
3. **Volume queued?** — `SELECT COUNT(*) FROM discovered_sources WHERE course_id = ?` >= 2,000.

---

## Phase 2 — Extraction Layer: Per-Site Extractors and Structured Parsing (2–3 weeks)

**Purpose:** The generic AI extractor on stripped HTML loses structure (numbered options, math
formulas, tables). This phase adds site-specific extractors and a proper HTML parser so the
pipeline reliably pulls complete, correctly-structured questions from each domain.

### Todos

**2.1 — Replace `strip_html/1` with `FunSheep.Scraper.HtmlParser`**
- [ ] Create `lib/fun_sheep/scraper/html_parser.ex` using Floki (already in `mix.exs`):
  - Extracts `<main>` / `[role=main]` content; falls back to `<body>`.
  - Strips `nav`, `header`, `footer`, `script`, `style`, `.advertisement`, `[aria-hidden]`.
  - Preserves `<ol>/<li>` as numbered lines (critical for MCQ options).
  - Converts `<math>`, MathJax `\(...\)` spans to plain-text LaTeX.
  - Renders `<table>` as tab-separated rows with headers.
- [ ] Replace `strip_html/1` calls in `web_question_scraper_worker.ex` with `HtmlParser.parse/1`.

**2.2 — `FunSheep.Scraper.SiteExtractor` behaviour**
- [ ] Create `lib/fun_sheep/scraper/site_extractor.ex` — a dispatch module:
  ```elixir
  # Maps host → extractor module. Unknown hosts fall back to Generic.
  @extractors %{
    "khanacademy.org"    => FunSheep.Scraper.Extractors.KhanAcademy,
    "varsitytutors.com"  => FunSheep.Scraper.Extractors.VarsityTutors,
    "albert.io"          => FunSheep.Scraper.Extractors.Albert,
    "collegeboard.org"   => FunSheep.Scraper.Extractors.CollegeBoard
  }
  ```
- [ ] Define the behaviour: `@callback extract(html, url, opts) :: {:ok, [question_map()]} | {:error, term()}`.

**2.3 — Site-specific extractor modules**
- [ ] `lib/fun_sheep/scraper/extractors/khan_academy.ex`
  - Parses `<script id="__NEXT_DATA__">` JSON blob (Perseus format). No AI call needed.
  - Key path: `props.pageProps.dehydratedState` → find objects with `"question"` and `"answers"` keys.
  - Falls back to `Generic` extractor if Perseus data not found.
- [ ] `lib/fun_sheep/scraper/extractors/varsity_tutors.ex`
  - Uses Floki CSS selectors: `.question-text`, `.answer-choice`, `.correct-answer`.
  - No AI call needed for well-structured pages.
- [ ] `lib/fun_sheep/scraper/extractors/albert.ex`
  - Albert.io renders server-side HTML with predictable question structure.
  - Use Floki selectors targeting Albert's question card pattern.
- [ ] `lib/fun_sheep/scraper/extractors/college_board.ex`
  - For PDF URLs: delegate to the existing OCR pipeline (treat as uploaded material).
  - For HTML pages: Floki-based selector extraction.
- [ ] `lib/fun_sheep/scraper/extractors/generic.ex`
  - Wrapper around the existing `FunSheep.Questions.Extractor.extract/2` AI path.
  - This is the fallback for all unknown domains.
- [ ] Replace `extract_questions_from_text/3` call in `web_question_scraper_worker.ex` with
  `FunSheep.Scraper.SiteExtractor.extract(html, source.url, opts)`.

**2.4 — Enrich AI extraction prompt (for Generic extractor)**
- [ ] Add `:test_profile` and `:section_hint` opts to `Extractor.extract/2`.
- [ ] Thread into `build_user_prompt/2`:
  ```
  TEST FORMAT: #{test_profile.format_rules}
  EXPECTED TOPIC: #{section_hint}
  SOURCE URL: #{url}
  If content is a blog post, nav page, or ad, return [].
  ```
- [ ] Create `lib/fun_sheep/discovery/known_test_profiles.ex` — a compile-time map of format
  rules per test type (e.g., SAT Math: "4 options A–D, no partial credit", GRE Quant: "may have
  multiple correct answers").

**2.5 — Increase AI chunk size and concurrency**
- [ ] In `extractor.ex`: `@ai_chunk_size 24_000`, `@ai_max_chunks 8`, `@ai_chunk_overlap 1_000`.
- [ ] Increase per-chunk concurrency from 2 to 4 in `extract_with_ai/3`.

**2.6 — Deduplication before insertion**
- [ ] Create `lib/fun_sheep/questions/deduplicator.ex`:
  - Fingerprint = SHA256(normalize(content)) where normalize = downcase + remove punctuation/whitespace + remove common stopwords.
  - Returns first 16 hex chars (64-bit; negligible collision risk at this scale).
- [ ] Migration `add_content_fingerprint_to_questions`:
  ```elixir
  add :content_fingerprint, :string
  # Unique index:
  create unique_index(:questions, [:course_id, :content_fingerprint])
  ```
- [ ] In `insert_question/3`: compute fingerprint, use `on_conflict: :nothing` with
  `conflict_target: [:course_id, :content_fingerprint]`.

### Tests

- [ ] `test/fun_sheep/scraper/html_parser_test.exs`:
  - `<ol><li>` → numbered plain-text lines.
  - MathJax spans preserved.
  - `<nav>`, `<footer>`, `<script>` stripped.
  - `<table>` → tab-separated rows.
- [ ] `test/fun_sheep/scraper/extractors/khan_academy_test.exs`:
  - Fixture: save a real KA exercise page HTML to `test/fixtures/scraper/khan_academy/`.
  - Assert >= 1 question returned with `content`, `options`, `answer` populated.
  - Assert `{:ok, []}` for a KA category listing page (fixture: non-exercise page).
- [ ] Same fixture-based tests for VarsityTutors and Albert extractors.
- [ ] `test/fun_sheep/questions/deduplicator_test.exs`:
  - Same content differing only in case/punctuation → same fingerprint.
  - Different questions → different fingerprints.
  - Fingerprint always 16 chars.
- [ ] Integration test: run scraper on 10 Khan Academy fixture URLs; assert 0 duplicate
  fingerprints inserted on second run.

### Three-criteria check

After Phase 2:
1. **Reputable sources?** — Spot-check `source_url` of 20 random web-scraped questions.
   All should be on recognizable domains.
2. **Extraction not creation?** — Open 5 random `source_url` links and confirm the question
   text appears verbatim on that page. This is the most important manual check.
3. **Volume?** — `SELECT COUNT(*) FROM questions WHERE course_id = ? AND source_type = 'web_scraped'` >= 1,000.

---

## Phase 3 — Quality Layer: Source-Aware Validation (1 week)

**Purpose:** The 95% `:passed` threshold was calibrated for AI-generated content. A College Board
question at 82% relevance is far more trustworthy than an AI-generated question at 82%. This phase
separates validation thresholds by source reputation so reputable web content passes more easily.

### Todos

**3.1 — `FunSheep.Scraper.SourceReputation`**
- [ ] Create `lib/fun_sheep/scraper/source_reputation.ex`:
  ```elixir
  # Tier 1 = official test maker
  @tier_1 ~w(collegeboard.org ets.org mcat.org lsac.org act.org)
  # Tier 2 = established, widely-cited prep companies
  @tier_2 ~w(khanacademy.org albert.io varsitytutors.com prepscholar.com magoosh.com kaplan.com)
  # Tier 3 = popular student-sharing sites (lower trust)
  @tier_3 ~w(quizlet.com sparknotes.com studocu.com coursehero.com)
  # Tier 4 = unknown domain (default)
  ```
  - Returns `%{tier: 1|2|3|4, passed_threshold: float, review_threshold: float}`.
  - Tier 1: passed >= 75%, review >= 60%.
  - Tier 2: passed >= 82%, review >= 65%.
  - Tier 3: passed >= 90%, review >= 70%.
  - Tier 4: passed >= 95%, review >= 70% (current default — no regression for unknown sources).

**3.2 — Store `source_tier` on questions**
- [ ] Migration `add_source_tier_to_questions`:
  ```elixir
  add :source_tier, :integer  # 1–4; nil for AI-generated
  ```
- [ ] Set `source_tier` from `SourceReputation.score(source.url).tier` during `insert_question/3`.

**3.3 — Thread reputation into `Validation.apply_verdict/2`**
- [ ] Modify `derive_status/2` to accept a `thresholds` map.
- [ ] In `QuestionValidationWorker.perform/1`: call `SourceReputation.score(question.source_url)`
  and pass the thresholds down. AI-generated questions continue to use the hardcoded 95%/70%.

**3.4 — Enrich validation prompt by source tier**
- [ ] In `Validation.build_batch_user_prompt/2`, for web-scraped questions add:
  ```
  SOURCE: #{url} (Tier #{tier} — #{tier_label})
  For Tier 1 sources (official test makers): accept minor formatting issues if the
  question stem and answer are clearly correct. For Tier 4 sources: apply full strictness.
  ```

**3.5 — Separate Oban queue for web validation**
- [ ] Add `web_validation: 5` queue to `config/runtime.exs`.
- [ ] In `web_question_scraper_worker.ex`, enqueue `QuestionValidationWorker` with `queue: :web_validation`.
  This prevents large web scraping batches from blocking the AI-generation validation queue.

**3.6 — Admin review UI: source tier filter**
- [ ] Add `source_tier` filter to the admin question review LiveView.
- [ ] Add "Bulk approve Tier 1" action — marks all `:needs_review` Tier 1 questions as `:passed`.

### Tests

- [ ] `test/fun_sheep/scraper/source_reputation_test.exs`:
  - `collegeboard.org` → tier 1, `passed_threshold: 75.0`.
  - `www.khanacademy.org` → tier 2 (www. prefix handled).
  - Unknown domain → tier 4, `passed_threshold: 95.0`.
- [ ] `test/fun_sheep/questions/validation_threshold_test.exs`:
  - `topic_relevance_score: 80`, `source_tier: 1` → `:passed`.
  - Same score, `source_tier: 4` → `:needs_review`.
  - `score: 50`, any tier → `:failed`.
- [ ] No regression: AI-generated questions (no `source_tier`) still require >= 95 to `:pass`.

### Three-criteria check

After Phase 3, re-run three-criteria check. Focus on criterion 1 (reputable sources) — does the
tier distribution match expectations? Tier 1+2 sources should account for > 50% of all web-scraped
questions.

---

## Phase 4 — Scale and Performance Layer (1–2 weeks)

**Purpose:** At 5 concurrent scrapers, processing 5,000 URLs takes ~8 hours. This phase reshapes
the job architecture so the pipeline can process tens of thousands of URLs per course in a
reasonable timeframe without losing work on container restarts.

### Todos

**4.1 — Per-source Oban job: `FunSheep.Workers.WebSourceScraperWorker`**
- [ ] Create `lib/fun_sheep/workers/web_source_scraper_worker.ex`:
  ```elixir
  use Oban.Worker,
    queue: :web_scrape,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]
  
  # Scrapes exactly one DiscoveredSource. Independent retry.
  def perform(%Oban.Job{args: %{"source_id" => source_id}}) do ...
  ```
- [ ] Add `:web_scrape: 20` queue to `config/runtime.exs`.
- [ ] Convert `WebQuestionScraperWorker` from a monolithic fan-out to a coordinator:
  it queries all pending `discovered_sources` for the course and enqueues one
  `WebSourceScraperWorker` per source, then returns `:ok`. All concurrency is now
  managed by Oban's queue (20 concurrent), not `Task.async_stream`.
- [ ] Remove `Enum.take(@max_sources_per_run)` cap — no longer needed when each source
  is its own job.

**4.2 — Domain rate limiter: `FunSheep.Scraper.DomainRateLimiter`**
- [ ] Create `lib/fun_sheep/scraper/domain_rate_limiter.ex` (GenServer + ETS):
  ```elixir
  @limits %{
    "khanacademy.org"   => {5, 1_000},   # 5 req/sec max
    "collegeboard.org"  => {2, 1_000},   # 2 req/sec max
    "varsitytutors.com" => {10, 1_000},
    "default"           => {20, 1_000}
  }
  # acquire/1 blocks until a slot is available
  def acquire(url) :: :ok
  ```
- [ ] Add to `application.ex` supervisor tree.
- [ ] Call `DomainRateLimiter.acquire(source.url)` at the top of `WebSourceScraperWorker.perform/1`.

**4.3 — Crawl batch tracking: `crawl_batches` table**
- [ ] Migration `create_crawl_batches`:
  ```elixir
  create table(:crawl_batches, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :course_id, references(:courses, type: :binary_id, on_delete: :delete_all)
    add :test_type, :string
    add :strategy, :string        # "web_search" | "sitemap" | "api" | "registry"
    add :total_urls, :integer, default: 0
    add :processed_urls, :integer, default: 0
    add :questions_extracted, :integer, default: 0
    add :status, :string, default: "running"   # running | paused | complete | failed
    add :config, :map, default: %{}
    timestamps(type: :utc_datetime)
  end
  ```
- [ ] `WebContentDiscoveryWorker` creates a `crawl_batch` record at start; marks it
  `:complete` when all `WebSourceScraperWorker` jobs are enqueued.
- [ ] A `CrawlBatchProgressWorker` (simple Oban cron, every 5 minutes) updates
  `processed_urls` and `questions_extracted` from DB counts.

**4.4 — Playwright renderer horizontal scaling**
- [ ] Update `config/runtime.exs` to accept comma-separated renderer URLs:
  ```elixir
  config :fun_sheep, :playwright_renderers,
    System.get_env("PLAYWRIGHT_RENDERER_URLS", "http://localhost:3000")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  ```
- [ ] In `fetch_via_renderer/1`, pick a renderer URL with `Enum.random(renderers)`.
  Replace with ETS round-robin counter when more than 3 renderers are configured.

### Tests

- [ ] Unit test `DomainRateLimiter` — assert that 10 concurrent `acquire("khanacademy.org")` calls
  all complete within 2 seconds (no deadlock), and that no more than 5 occur within any 1-second window.
- [ ] Integration test: fan-out coordinator enqueues exactly N `WebSourceScraperWorker` jobs for N sources.
- [ ] Chaos test: kill the Oban worker process mid-scrape; restart; assert all in-progress jobs are
  retried and no questions are lost (Oban `max_attempts: 3` handles this automatically).
- [ ] Throughput benchmark: 100 fixture URLs → all processed within 60 seconds at concurrency 20.

### Three-criteria check

After Phase 4:
3. **Volume?** — `SELECT COUNT(*) FROM questions WHERE course_id = ? AND source_type = 'web_scraped'`
   >= 5,000 for SAT Math.

---

## Phase 5 — Source Registry: Long-Term Maintainability (1 week)

**Purpose:** For 76 test types in the roadmap, the pipeline must not start from zero each time a
new test is added. A curated, database-backed source registry ensures every new course immediately
seeds from the best known sources.

### Todos

**5.1 — Schema: `source_registry_entries`**
- [ ] Migration `create_source_registry_entries`:
  ```elixir
  create table(:source_registry_entries, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :test_type, :string, null: false      # "sat" | "act" | "ap_biology" etc.
    add :catalog_subject, :string             # "mathematics" | "verbal" | nil (all subjects)
    add :url_or_pattern, :string, null: false # direct URL or glob pattern
    add :domain, :string, null: false
    add :source_type, :string, null: false    # "question_bank" | "practice_test" | "official"
    add :tier, :integer, null: false          # 1–4 per SourceReputation
    add :is_enabled, :boolean, default: true
    add :extractor_module, :string            # nil = Generic
    add :avg_questions_per_page, :integer
    add :consecutive_failures, :integer, default: 0
    add :last_verified_at, :utc_datetime
    add :notes, :text
    timestamps(type: :utc_datetime)
  end
  create index(:source_registry_entries, [:test_type, :catalog_subject, :is_enabled])
  ```

**5.2 — Admin CRUD: `FunSheepWeb.AdminSourceRegistryLive`**
- [ ] LiveView at `/admin/source-registry`.
- [ ] List by `test_type`, show tier badge, enabled toggle, avg_questions_per_page.
- [ ] "Verify" button: runs a one-off `WebSourceScraperWorker` for a sample URL and shows
  questions extracted count.
- [ ] "Seed course" button: triggers `RegistrySeeder.seed_from_registry/1` for a selected course.

**5.3 — `FunSheep.Discovery.RegistrySeeder`**
- [ ] Create `lib/fun_sheep/discovery/registry_seeder.ex`:
  - Queries all enabled registry entries matching `(test_type, catalog_subject)`.
  - Creates `DiscoveredSource` records with `discovery_strategy: "registry"`.
  - Called from `WebContentDiscoveryWorker.perform/1` before the web search pass.
  - Registry sources get highest priority in `list_scrapable_sources/1` ordering.

**5.4 — Initial seed data**
- [ ] Create `priv/repo/seeds/source_registry.exs` (run separately, not inside an Ecto migration):
  - Minimum entries for the top 10 most-demanded test types:
    SAT, ACT, AP Calculus AB, AP Biology, AP Chemistry, AP US History, GRE, LSAT, MCAT, PRAXIS.
  - Each entry includes at least 3 Tier 1–2 sources.

**5.5 — Nightly registry health check**
- [ ] Create `lib/fun_sheep/workers/source_registry_verifier_worker.ex`:
  - Queries entries not verified in the last 7 days.
  - HEAD-probes each URL; on failure increments `consecutive_failures`.
  - After 3 consecutive failures: `is_enabled: false` + sends admin alert email.
- [ ] Add cron to `config/runtime.exs`: `{"0 2 * * *", FunSheep.Workers.SourceRegistryVerifierWorker}`.

### Tests

- [ ] Unit test `RegistrySeeder` — mock registry entries; assert correct `DiscoveredSource` records created.
- [ ] Integration test: add MCAT to registry, run `RegistrySeeder.seed_from_registry/1` on a new MCAT course,
  assert >= 3 `discovered_sources` created with `discovery_strategy: "registry"`.
- [ ] Test `SourceRegistryVerifierWorker`: mock a 404 response for an entry; assert `consecutive_failures`
  incremented; after 3 mocked failures assert `is_enabled: false`.
- [ ] Test admin LiveView: "Verify" button triggers job; result count is displayed.

### Three-criteria check

After Phase 5:
1. **Reputable sources?** — `SELECT domain, tier FROM source_registry_entries WHERE test_type = 'sat' AND is_enabled = true ORDER BY tier` must show >= 5 entries with tier <= 2.
2. **Volume queued?** — A brand-new test type added to the registry and seeded should produce >= 50 `discovered_sources` before any web search runs.

---

## Phase 6 — Monitoring and Observability (3–5 days setup, then ongoing)

**Purpose:** Know immediately when the pipeline degrades — whether a domain starts blocking
scrapers, the Playwright renderer goes down, or extraction yield drops.

### Todos

**6.1 — Admin pipeline audit per course**
- [ ] Add `FunSheep.Questions.pipeline_audit_for_course/1` to the Questions context:
  ```elixir
  # Returns a map:
  %{
    sources_discovered: 2400,
    sources_scraped: 2100,
    sources_failed: 200,
    questions_extracted: 8500,
    questions_passed: 6200,
    questions_needs_review: 1800,
    questions_failed: 500,
    by_domain: [
      %{domain: "khanacademy.org", tier: 2, extracted: 1800, pass_rate: 0.94},
      ...
    ]
  }
  ```
  This is a SQL join of `discovered_sources` and `questions` on `source_url` — no new schema.
- [ ] Show this audit on the admin course show page.

**6.2 — Extraction rate alerting**
- [ ] In `SourceRegistryVerifierWorker`, also check daily extraction rate:
  if `questions_extracted_today < questions_extracted_yesterday * 0.5`, send admin alert.
- [ ] Alert triggers: Playwright renderer down, major source blocking, Anthropic API errors.

**6.3 — Real-time scrape progress via PubSub**
- [ ] Broadcast on `[:fun_sheep, :scraper, :source_complete]` events to a PubSub topic
  `"course:#{course_id}:pipeline"`.
- [ ] Admin pipeline LiveView subscribes and updates a live counter without polling.

### Tests

- [ ] Unit test `pipeline_audit_for_course/1` — insert known fixture data; assert correct totals.
- [ ] Simulate renderer outage in test (mock `fetch_via_renderer/1` to return error); assert
  alert email is sent within the verifier's next run.

---

## Phase 7 — Full Test Suite and Regression Protection (ongoing)

**Purpose:** Prevent regressions as new test types are added and as external sites change their HTML.

### Todos

**7.1 — HTML fixture library**
- [x] Create `test/fixtures/scraper/` directory with one subdirectory per domain.
- [x] Save a real HTML snapshot for each site-specific extractor (Khan Academy exercise page,
  VarsityTutors question page, Albert.io question page, CollegeBoard question page).
- [x] These fixtures are the regression baseline — if an extractor starts returning 0 questions
  on a previously-working fixture, something broke.
- [x] Add a CI step that runs all extractor fixture tests on every PR.

**7.2 — Mox-based pipeline integration test**
- [x] Create `test/fun_sheep/workers/web_pipeline_integration_test.exs`:
  - Coordinator fan-out: asserts one `WebSourceScraperWorker` job enqueued per discovered source.
  - Coordinator skips non-discovered (already scraped) sources.
  - Per-source scraper (Req.Test stub): extracts and inserts web_scraped questions.
  - Inserted questions have `source_url` matching the scraped source.
  - Re-running on the same source does not duplicate questions.
  - Uses `Req.Test` stub that handles both plain GET and renderer POST (/render) paths.

**7.3 — Extraction honesty test (critical)**
- [x] Create `test/fun_sheep/questions/extraction_honesty_test.exs`:
  - For each site-specific extractor, assert that extracted `content` words (≥6 chars) appear
    in the source HTML. This is the automated version of criterion 2 ("not creation").
  - Any extractor that returns content not present in the input HTML fails this test.

**7.4 — Volume regression test**
- [x] Create `test/fun_sheep/workers/volume_regression_test.exs`:
  - Runs extraction layer against 50 fixture URLs across 4 supported domains.
  - Asserts ≥80% of fixture URLs yield at least one question (92% in practice).
  - Asserts 0 extracted questions are tagged `is_generated: true`.
  - Fast (< 200ms) — runs on every PR, not weekly-only.

**7.5 — Three-criteria automated check**
- [x] Created Mix task `mix funsheep.pipeline.verify COURSE_ID` that runs all three criteria
  checks and prints a pass/fail report. Used after every deployment to production.
  Exit code 0 = all pass, 1 = one or more fail.

---

## New Modules Summary

| Module | Path |
|---|---|
| `FunSheep.Discovery.QueryPaginator` | `lib/fun_sheep/discovery/query_paginator.ex` |
| `FunSheep.Discovery.Adapters.KhanAcademy` | `lib/fun_sheep/discovery/adapters/khan_academy.ex` |
| `FunSheep.Discovery.Adapters.CollegeBoard` | `lib/fun_sheep/discovery/adapters/college_board.ex` |
| `FunSheep.Discovery.KnownTestProfiles` | `lib/fun_sheep/discovery/known_test_profiles.ex` |
| `FunSheep.Discovery.SourceRegistry` | `lib/fun_sheep/discovery/source_registry.ex` |
| `FunSheep.Discovery.RegistrySeeder` | `lib/fun_sheep/discovery/registry_seeder.ex` |
| `FunSheep.Discovery.Metrics` | `lib/fun_sheep/discovery/metrics.ex` |
| `FunSheep.Scraper.HtmlParser` | `lib/fun_sheep/scraper/html_parser.ex` |
| `FunSheep.Scraper.SiteExtractor` | `lib/fun_sheep/scraper/site_extractor.ex` |
| `FunSheep.Scraper.Extractors.KhanAcademy` | `lib/fun_sheep/scraper/extractors/khan_academy.ex` |
| `FunSheep.Scraper.Extractors.VarsityTutors` | `lib/fun_sheep/scraper/extractors/varsity_tutors.ex` |
| `FunSheep.Scraper.Extractors.Albert` | `lib/fun_sheep/scraper/extractors/albert.ex` |
| `FunSheep.Scraper.Extractors.CollegeBoard` | `lib/fun_sheep/scraper/extractors/college_board.ex` |
| `FunSheep.Scraper.Extractors.Generic` | `lib/fun_sheep/scraper/extractors/generic.ex` |
| `FunSheep.Scraper.SourceReputation` | `lib/fun_sheep/scraper/source_reputation.ex` |
| `FunSheep.Scraper.DomainRateLimiter` | `lib/fun_sheep/scraper/domain_rate_limiter.ex` |
| `FunSheep.Questions.Deduplicator` | `lib/fun_sheep/questions/deduplicator.ex` |
| `FunSheep.Workers.WebSourceScraperWorker` | `lib/fun_sheep/workers/web_source_scraper_worker.ex` |
| `FunSheep.Workers.SourceSitemapCrawlerWorker` | `lib/fun_sheep/workers/source_sitemap_crawler_worker.ex` |
| `FunSheep.Workers.SourceRegistryVerifierWorker` | `lib/fun_sheep/workers/source_registry_verifier_worker.ex` |
| `FunSheepWeb.AdminWebPipelineLive` | `lib/fun_sheep_web/live/admin_web_pipeline_live.ex` |
| `FunSheepWeb.AdminSourceRegistryLive` | `lib/fun_sheep_web/live/admin_source_registry_live.ex` |

---

## Existing Files with Key Changes

| File | Change |
|---|---|
| `web_content_discovery_worker.ex` | `max_uses: 3→8`; expand queries to 10/section; add sitemap enqueue; call RegistrySeeder |
| `web_question_scraper_worker.ex` | Convert to fan-out coordinator; delegate scraping to `WebSourceScraperWorker` |
| `questions/extractor.ex` | Add `:test_profile`, `:section_hint` opts; thread into prompt |
| `questions/validation.ex` | Accept `thresholds` arg in `derive_status/2` |
| `question_validation_worker.ex` | Route web-scraped batches to `:web_validation` queue; pass reputation thresholds |
| `application.ex` | Add `DomainRateLimiter` to supervisor tree |
| `config/runtime.exs` | Add `:web_scrape: 20`, `:web_validation: 5` queues; add nightly cron |

---

## Database Migrations (in order)

| # | Migration name | Adds |
|---|---|---|
| 1 | `add_discovery_strategy_to_discovered_sources` | `discovery_strategy`, `scrape_attempts`, `last_scraped_at` |
| 2 | `add_content_fingerprint_to_questions` | `content_fingerprint`, unique index `(course_id, content_fingerprint)` |
| 3 | `add_source_tier_to_questions` | `source_tier :integer` |
| 4 | `create_crawl_batches` | New `crawl_batches` table |
| 5 | `create_source_registry_entries` | New `source_registry_entries` table |

---

## Expected Question Volume Trajectory

| After Phase | SAT Math web-scraped questions (`:passed`) |
|---|---|
| Baseline (today) | ~92 |
| Phase 0 (measurement) | ~92 (unchanged) |
| Phase 1 (more discovery) | 800–1,500 |
| Phase 2 (better extraction) | 3,000–6,000 |
| Phase 3 (quality thresholds) | 5,000–10,000 |
| Phase 4 (scale) | 15,000–30,000 |
| Phase 5 (registry) | 30,000–100,000 |

---

## Phase Dependency Order

```
Phase 0 (Baselines — measure first)
    ├── Phase 1 (Discovery — more queries)  ─┐
    └── Phase 2 (Extraction — per-site)     ─┤── Phase 3 (Quality thresholds)
                                              │       └── Phase 4 (Scale — per-source jobs)
                                              │               └── Phase 5 (Source Registry)
Phase 6 (Monitoring — start after P0, deepen after P5)
Phase 7 (Testing — continuous throughout all phases)
```

Phases 1 and 2 can be implemented in parallel by different work sessions since they touch
different parts of the codebase (discovery vs. extraction).
