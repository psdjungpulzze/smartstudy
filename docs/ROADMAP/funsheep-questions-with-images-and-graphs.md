# Questions with Images & Graphs — Strategy & Roadmap

**Status**: Planning  
**Scope**: End-to-end image support across all three question ingestion pathways — uploaded files (OCR), web-scraped, and AI-generated  
**Depends on**: Existing `SourceFigure` / `QuestionFigure` schema, GCS storage layer, OCR pipeline, `FigureExtractor` (currently disabled), Interactor Agents, Oban workers

---

## 1. Problem Statement

A significant proportion of exam questions require visual context. A student practicing AP Biology sees "Refer to the diagram below" but FunSheep shows only text. A student practicing calculus sees a question about a graph with no graph. This silently corrupts the diagnostic signal — we score wrong answers that are wrong only because the image is missing.

Three ingestion pathways each have the same gap:

| Pathway | Current State | Gap |
|---|---|---|
| **Uploaded files** (PDFs, images) | `FigureExtractor` exists, **disabled** 2026-04-20 to stabilize OCR throughput | Figures detected by Vision API but never extracted, stored, or linked to questions |
| **Web-scraped questions** | Scraper fetches text only | `<img>` tags near questions ignored; external image URLs never downloaded |
| **AI-generated questions** | AI returns text-only content | Questions requiring graphs, charts, or diagrams generated without any figure |

The fix is not one feature — it is an abstraction layer that handles figure acquisition, storage, and rendering regardless of how the question was created.

---

## 2. Existing Infrastructure (What We Already Have)

Before listing what to build, recognize what already exists:

| Component | File | Status |
|---|---|---|
| `SourceFigure` schema | `lib/fun_sheep/content/source_figure.ex` | Active — `figure_type` enum: `:figure`, `:table`, `:graph`, `:chart`, `:diagram`, `:image` |
| `QuestionFigure` join table | Migration `20260418045452` | Active — links questions ↔ figures with position metadata |
| `FigureExtractor` | `lib/fun_sheep/ocr/figure_extractor.ex` | **Disabled** — detects figure captions via regex, estimates bbox |
| Manual figure upload | `question_bank_live.ex` lines 29–33 | Active — 3 files/question, PNG/JPG/WEBP, 5MB, stored in GCS `user-figures/` |
| GCS storage abstraction | `lib/fun_sheep/storage.ex` | Active — `put/3`, `gcs_uri/1`, resumable upload session support |
| OCR bounding boxes | `OcrPage.bounding_boxes` | Active — Vision API block/word/paragraph/page JSON stored per page |
| Vision image annotations | `OcrPage.images` | Active — Vision returns `images[]` array per page (coordinates, confidence) |
| Interactor Agents | `lib/fun_sheep/interactor/agents.ex` | Active — `chat/3` call to any named assistant |

The schema foundations are solid. The work is primarily: un-disable extraction, extend it to actually crop pixels, add web scraper image harvesting, add AI figure generation, and render correctly.

---

## 3. Abstraction Model

All figures — regardless of source — resolve to the same runtime shape: a GCS-stored binary with an `alt_text`, a `figure_type`, optional dimensions, and a `caption`. The `QuestionFigure` join row adds a `position` field that controls rendering order.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                       Question (text content)                           │
│                                                                         │
│   QuestionFigure [position: :above | :inline | :below | :reference]    │
│         │                                                               │
│         ▼                                                               │
│   Figure (unified)                                                      │
│   ├── gcs_key          → Storage path in GCS                            │
│   ├── figure_type      → :graph | :chart | :table | :diagram | :image  │
│   ├── alt_text         → Screen reader description                      │
│   ├── caption          → "Figure 1: Distribution of X"                 │
│   ├── width / height   → For aspect ratio preservation                 │
│   └── source           → :ocr_extracted | :web_scraped | :ai_generated  │
└─────────────────────────────────────────────────────────────────────────┘
```

Three source pipelines produce figures; one rendering component consumes them:

```
Uploaded File (PDF/image)
   │── Vision OCR → bounding boxes → crop pixels → GCS → SourceFigure
   └── Linked to questions by proximity

Web-Scraped Page
   │── Parse <img> tags near question text → download → GCS → SourceFigure
   └── Linked to question during extraction

AI-Generated Question
   │── AI returns figure spec (chart JSON or diagram description)
   ├── Charts → VegaLite spec → headless render → PNG → GCS → SourceFigure
   └── Diagrams → Gemini image gen via Interactor SKB → GCS → SourceFigure
```

---

## 4. Decision: AI Image Generation Provider

Image generation for diagrams and illustrations routes through **Interactor SKB** using the **Gemini** model (API key to be provided by Peter). This keeps all AI calls inside the existing `Interactor.Agents` abstraction — no direct vendor SDK or HTTP client needed in FunSheep itself.

The codebase uses a behaviour so the provider remains swappable:

```elixir
defmodule FunSheep.Figures.ImageGenerator do
  @callback generate(prompt :: String.t(), opts :: keyword()) ::
    {:ok, binary()} | {:error, reason :: String.t()}
end
```

Concrete implementations:
- `FunSheep.Figures.GeminiGenerator` — production, calls Interactor SKB assistant (assistant name TBD, configured with Gemini API key in SKB)
- `FunSheep.Figures.LocalMockGenerator` — test/dev (returns a placeholder PNG)

**Fallback policy**: If image generation fails, the question is flagged with `figure_generation_status: :failed` and the question text must contain a description sufficient to answer without the image. Generation failure must NOT mark the question as invalid — only log and alert.

---

## 5. Decision: Chart/Graph Programmatic Rendering

For questions with **data-driven charts** (bar charts, scatter plots, line graphs, histograms), AI-generated images are unreliable — numbers and axis labels will be wrong. Use programmatic rendering instead:

1. During question generation, the AI returns a **VegaLite JSON spec** embedded in a structured `figure_spec` field alongside the question JSON.
2. A `ChartRendererWorker` submits the spec to a headless Chromium instance (already available via the Playwright renderer service running on port 3000).
3. Chromium renders the VegaLite chart and screenshots it as PNG.
4. PNG is stored in GCS and linked as a `SourceFigure`.

This guarantees axis labels, data points, and tick marks are correct — something no diffusion model can reliably produce.

**Routing rule**: If the question is about reading a data chart → programmatic rendering. If the question is about a biological diagram, anatomical figure, geographic map, or conceptual illustration → Gemini image generation via Interactor SKB.

---

## 6. Phase Plan

### Phase 1 — Schema & Storage Extension (Scope: ~1 day)

**Goal**: Extend the data model to support all figure sources without migration conflicts.

**Changes:**

1. **Extend `source_figures` table** (new migration):
   - Add `gcs_key` (string, nullable — populated once image is stored)
   - Add `alt_text` (string)
   - Add `content_type` (string — `image/png`, `image/jpeg`, etc.)
   - Add `width` / `height` (integer, pixels)
   - Add `figure_source` (enum: `:ocr_extracted`, `:web_scraped`, `:ai_generated`, `:user_uploaded`)
   - Add `generation_prompt` (text, nullable — stores the prompt used for AI generation)

2. **Extend `questions` table** (new migration):
   - Add `figure_specs` (map, default: `[]`) — array of figure spec objects emitted by AI during generation. Each spec: `%{"spec_type" => "vegalite"|"diagram", "spec" => <json_or_prompt>, "position" => "above"|"below"|"inline", "alt_text" => "...", "caption" => "..."}`
   - Add `figure_generation_status` (enum: `:not_needed`, `:pending`, `:generating`, `:complete`, `:failed`, default: `:not_needed`)

3. **Extend `question_figures` join table**:
   - Add `position` (enum: `:above`, `:below`, `:inline`, `:reference`) with default `:above`
   - Add `display_order` (integer, default: 0)

4. **New module: `FunSheep.Figures`** — context wrapping all figure creation, attachment, and retrieval logic.

---

### Phase 2 — OCR Figure Extraction (Scope: ~3 days)

**Goal**: Re-enable figure extraction for uploaded PDFs and images, crop real pixels, store in GCS.

**Current state**: `FigureExtractor` detects figure captions (`Figure N`, `Table N`, `Fig. N`) and estimates a bounding box by merging the caption's bbox with the nearest large non-text block. The extracted `%SourceFigure{}` structs are never persisted because GCS PUT is not called — this is why it was disabled.

**What to build:**

#### 2a. PDF Figure Cropping
Vision API returns a `pages[].images[]` array with bounding boxes (normalized vertices) for detected image blocks. For PDF materials, use `pdftoppm` (already in the OCR environment for PDF splitting) to rasterize a specific page to PNG, then crop the bounding box region using `Mogrify` (Elixir wrapper for ImageMagick).

```
Vision response: pages[0].images[0].boundingPoly.vertices = [{x:120,y:200},{x:400,y:200},{x:400,y:500},{x:120,y:500}]
Page dimensions from Vision: pages[0].width=612, pages[0].height=792

Crop calculation:
  left   = round(120 / 612 * page_px_width)
  top    = round(200 / 792 * page_px_height)
  width  = round((400-120) / 612 * page_px_width)
  height = round((500-200) / 792 * page_px_height)

pdftoppm -r 150 -png -f {page_num} -l {page_num} material.pdf → page_001.png
convert page_001.png -crop {width}x{height}+{left}+{top} figure.png
```

Store at `figures/<material_id>/<page_num>-<figure_idx>.png`.

#### 2b. Figure-to-Question Proximity Matching
After cropping and storing figures for a page, determine which question (if any) the figure belongs to by comparing text proximity:
1. Each extracted question has `source_page` and (eventually) a character position in the OCR text.
2. Figures on the same page whose bounding box is within N pixels above the question's text bounding box are considered "above the question" → `position: :above`.
3. If no question proximity match, create an "orphan" `SourceFigure` attached to the material only — admin can manually link it later.

#### 2c. Re-enable FigureExtractor in Pipeline
In `lib/fun_sheep/ocr/pipeline.ex` (lines 206–214, currently commented out), re-enable `FigureExtractor.extract_figures/2` after verifying:
- GCS PUT calls use fire-and-forget (do NOT block the OCR page completion with image uploads)
- Each GCS PUT is wrapped in a separate supervised Task with a 30s timeout
- Figure extraction failures are logged but do not fail the OCR page itself

#### 2d. New Worker: `FigureExtractionWorker`
Do not run figure extraction synchronously in the OCR pipeline. After a page completes OCR, enqueue a `FigureExtractionWorker` job:
- Queue: `:default` (2 concurrency slots)
- Args: `%{material_id: ..., page_id: ..., page_num: ...}`
- Flow: load page bounding boxes → identify image regions → rasterize page → crop figures → upload to GCS → create `SourceFigure` → run proximity matching → attach to questions

---

### Phase 3 — Web Scraper Image Harvesting (Scope: ~2 days)

**Goal**: When scraping questions from web pages, also harvest associated images.

**Integration point**: `WebQuestionScraperWorker` already uses Playwright for SPA support. Playwright's page DOM is already available — add image extraction before navigating away.

#### 3a. Image Extraction Strategy
After extracting question text from a page, for each extracted question:
1. Find the nearest `<img>`, `<figure>`, `<canvas>`, or `<svg>` element within N pixels (by DOM position) of the question text container.
2. For `<img>`: capture the `src` attribute. If relative, absolutize using the page URL.
3. For `<canvas>` / `<svg>` (common for interactive graphs on Khan Academy): use Playwright `element.screenshot()` to capture the rendered graphic as PNG directly.
4. Apply relevance filters:
   - Minimum dimensions: 80×80 px (skip icons, decorations)
   - Skip tracking pixels, avatars, site logos (block common patterns: `avatar`, `logo`, `icon`, `emoji`)
   - Skip images with `role="presentation"` or `aria-hidden="true"`

#### 3b. Download & Store
For `<img>` sources: HTTP GET the image URL → validate content-type is `image/*` → store in GCS at `scraped-figures/<source_id>/<hash>.<ext>`.

For canvas/SVG captures: already binary PNG from Playwright → store directly.

Maximum image size to accept: 10MB. Reject and log if exceeded.

#### 3c. Linking
During question creation from web-scraped content, attach harvested images to the question with `position: :above` by default. The scraper already has question-to-DOM-element mapping — use the same mapping to determine which figure belongs to which question.

#### 3d. Deduplication
Many questions on a page may share the same figure (e.g., a graph at the top of a multi-part question). Hash the image binary (SHA-256) before upload. If a `SourceFigure` with the same hash already exists for the source, re-use it rather than uploading a duplicate.

---

### Phase 4 — AI Figure Generation (Scope: ~4 days)

**Goal**: When AI generates questions that require visual context, generate the figures.

This is the most complex phase because it requires changes to prompt engineering, a new worker, and two rendering backends.

#### 4a. Prompt Engineering for Figure Specs

Update the `question_gen` Interactor assistant prompt to instruct the model to emit a `figures` array alongside each question JSON:

```json
{
  "content": "In the graph below, which variable shows exponential growth between t=0 and t=5?",
  "answer": "Variable A",
  "options": {...},
  "figures": [
    {
      "position": "above",
      "figure_type": "graph",
      "caption": "Figure 1: Growth curves of Variables A, B, and C",
      "alt_text": "Line graph with three curves. Variable A curves sharply upward (exponential). Variable B is linear. Variable C is flat.",
      "spec_type": "vegalite",
      "spec": {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
        "data": {"values": [...]},
        "mark": "line",
        "encoding": {...}
      }
    }
  ]
}
```

For diagrams and illustrations where programmatic rendering is not appropriate:

```json
{
  "figures": [
    {
      "position": "above",
      "figure_type": "diagram",
      "caption": "Figure 1: The mitotic spindle during metaphase",
      "alt_text": "Cell diagram showing chromosomes aligned at the metaphase plate with spindle fibers extending from centrioles at each pole.",
      "spec_type": "image_prompt",
      "spec": "Scientific diagram of a cell in metaphase of mitosis. Show chromosomes (blue, condensed, X-shaped) aligned at the cell equator. Spindle fibers (green lines) extend from two centrioles (orange) at opposite poles. Label: chromosomes, spindle fibers, centriole, metaphase plate. White background, clean scientific illustration style."
    }
  ]
}
```

**Routing rule embedded in the assistant prompt:**
- Questions about reading data from charts, interpreting graphs, analyzing trends → `spec_type: "vegalite"`
- Questions about biological processes, anatomy, geography, physics setups, chemical structures → `spec_type: "image_prompt"`
- Questions that can be fully answered from text alone (definitions, date-based history, word problems with no spatial component) → emit `figures: []`

#### 4b. New Worker: `FigureGenerationWorker`

After question generation, if `figure_specs` is non-empty:
1. Set `figure_generation_status: :pending` on the question.
2. Enqueue `FigureGenerationWorker` for each spec.
3. Worker flow:
   - Route by `spec_type`:
     - `"vegalite"` → `FunSheep.Figures.ChartRenderer.render(spec_json)`
     - `"image_prompt"` → `FunSheep.Figures.ImageGenerator.generate(prompt)`
   - On success: upload PNG to GCS, create `SourceFigure`, attach to question
   - On failure: log, increment `figure_generation_attempts` (cap at 3), keep status `:failed`
4. When all specs for a question are processed, set `figure_generation_status: :complete` or `:failed`.

Queue: `:ai` (shares concurrency with other AI tasks — keep this light, 1-2 concurrent figure gen jobs max to respect Interactor SKB / Gemini rate limits).

#### 4c. ChartRenderer (VegaLite → PNG)

Use the Playwright renderer service already running at `http://localhost:3000` (or production equivalent).

```elixir
defmodule FunSheep.Figures.ChartRenderer do
  def render(vegalite_spec) do
    # POST to Playwright renderer with VegaLite JSON
    # Returns binary PNG
    playwright_url = Application.get_env(:fun_sheep, :playwright_renderer_url)
    body = %{type: "vegalite", spec: vegalite_spec, width: 600, height: 400}
    # ...
  end
end
```

The Playwright renderer service needs a `/render/vegalite` endpoint that:
1. Receives a VegaLite JSON spec
2. Renders it in Chromium with `vega-embed`
3. Screenshots the chart element
4. Returns the PNG binary

If the Playwright service cannot be extended, fallback: call the `vl2png` CLI (from `vega-cli` npm package) via `System.cmd/3`.

#### 4d. Gemini Image Generation via Interactor SKB

Image generation calls go through the existing `FunSheep.Interactor.Agents.chat/3` interface. An Interactor SKB assistant (e.g., `"figure_gen"`) is configured server-side with the Gemini API key — FunSheep never holds the key directly.

```elixir
defmodule FunSheep.Figures.GeminiGenerator do
  @behaviour FunSheep.Figures.ImageGenerator

  @assistant "figure_gen"

  @impl true
  def generate(prompt, _opts \\ []) do
    case FunSheep.Interactor.Agents.chat(@assistant, prompt, []) do
      {:ok, response} ->
        # SKB returns base64-encoded PNG in response body — decode to binary
        decode_image(response)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_image(response) do
    # Exact response shape depends on how SKB assistant is configured —
    # confirm with Interactor SKB team before implementing
    {:ok, Base.decode64!(response)}
  end
end
```

**Integration checklist (unblock when Gemini API key is provided):**
- [ ] Add `"figure_gen"` assistant to Interactor SKB, configured with Gemini API key
- [ ] Confirm SKB assistant response format (base64 PNG? URL? inline binary?)
- [ ] Confirm which Gemini image model to use (Imagen 3 via Vertex AI, or `gemini-2.0-flash-preview-image-generation`)
- [ ] Confirm rate limits exposed through SKB
- [ ] Test with a sample diagram prompt end-to-end before wiring into `FigureGenerationWorker`

---

### Phase 5 — Question Rendering (Scope: ~2 days)

**Goal**: Render images correctly in all student-facing and admin-facing surfaces.

#### 5a. `QuestionFigureComponent`

New Phoenix component:

```heex
<.question_figure figure={@figure} position={@position} />
```

Handles:
- Loading state (skeleton placeholder while GCS image loads)
- Alt text for accessibility
- Caption below image
- Responsive sizing (max-width: 100%, max-height: 400px for inline questions)
- Lightbox on click for larger images (especially tables, multi-part graphs)
- Graceful fallback: if `gcs_key` is nil (figure generation pending/failed), show a muted placeholder with the `alt_text` as visible text

#### 5b. Inline Figure Anchors in Question Text

For questions with `"inline"` position figures, the question text may contain `{{figure:1}}` markers. The rendering layer must parse these and replace with the `QuestionFigureComponent`. Example:

```
"content": "Study the diagram in {{figure:1}}. Which structure is responsible for...?"
```

Parser: simple regex `~r/\{\{figure:(\d+)\}\}/` → replace with rendered component at display time.

This is optional for MVP — all figures can default to `:above` position first.

#### 5c. Surfaces to Update

| Surface | File | Change |
|---|---|---|
| **Practice question card** | `lib/fun_sheep_web/live/practice_live.ex` | Render figures above question text |
| **Assessment question card** | `lib/fun_sheep_web/live/assessment_live.ex` | Same |
| **Question bank admin** | `lib/fun_sheep_web/live/question_bank_live.ex` | Show figures in question row, allow unlinking |
| **Admin question review** | `lib/fun_sheep_web/live/admin_question_review_live.ex` | Show figures during review, allow admin to delete/replace |
| **Answer feedback panel** | Practice wrong-answer feedback | Show figure alongside explanation |

#### 5d. Figure Management in Admin

Admin should be able to:
- View all figures for a question
- Delete a figure (and optionally regenerate)
- Manually upload a replacement figure
- Trigger re-generation for `:failed` figures
- Approve/reject AI-generated figures before they become student-visible

Add `figure_admin_status` (enum: `:auto_approved`, `:pending_review`, `:approved`, `:rejected`) to `source_figures`. AI-generated figures default to `:pending_review` until an admin approves.

**North Star alignment**: A question with `figure_admin_status: :rejected` or `figure_generation_status: :failed` and no fallback image must **not** reach students (add to the visibility filter in `Questions.student_visible_query/1`). An image that is broken is worse than text-only — it signals the question is broken.

---

## 7. Figure Visibility Rules (North Star Alignment)

Extend the existing student-visible query:

```
Student can see a question with figures IF:
  - question.validation_status == :passed
  - question.classification_status in [:ai_classified, :admin_reviewed]
  - EITHER: question.figure_generation_status in [:not_needed, :complete]
  - OR: all figures have figure_admin_status in [:auto_approved, :approved]
  - AND: NO figure has figure_admin_status == :rejected (reject cascades to question)
```

Questions with `figure_generation_status: :pending` or `:generating` are withheld until generation completes. Students never see a "Figure 1" reference with no figure.

---

## 8. Implementation Order & Dependencies

```
Phase 1 (Schema)
  └─▶ Phase 2 (OCR Extraction) — needs gcs_key, figure_source fields
  └─▶ Phase 3 (Web Scraper)   — needs gcs_key, figure_source fields
  └─▶ Phase 4 (AI Generation) — needs figure_specs, figure_generation_status on questions
        └─▶ Gemini API key provided → configure SKB assistant → implement GeminiGenerator
        └─▶ Phase 5 (Rendering) — needs all figure sources working
```

Phase 2 and Phase 3 can run in parallel once Phase 1 is done.
Phase 4 and Phase 5 can begin once Phase 1 is done (Phase 4 is independent of 2/3).

---

## 9. Open Questions & Blockers

| Question | Owner | Priority |
|---|---|---|
| Gemini API key (to be provided by Peter) → configure `"figure_gen"` assistant in Interactor SKB | Peter | P0 — blocks Phase 4d |
| Confirm Interactor SKB `"figure_gen"` assistant response format (base64 PNG? URL? binary?) | Interactor SKB team | P0 — blocks Phase 4d |
| Does Playwright renderer service support a `/render/vegalite` endpoint, or do we extend it? | Peter | P1 — blocks Phase 4c |
| What is the acceptable latency budget for figure generation? (Student should not wait >X seconds for figures to appear) | Product | P1 — informs whether we show questions before figures are ready or gate on them |
| Are AI-generated figures reviewed by admin before students see them, or auto-approved? | Product | P1 — determines figure_admin_status default and workflow |
| Which question categories on FunSheep most commonly have figures? (AP Bio? Calculus? Chemistry?) | Analytics | P2 — informs prompt engineering priority |
| Should students be able to zoom/expand figures? | Design | P2 |
| Copyright status of web-scraped images — are we allowed to store them? | Legal | P2 — may force web-scraper to link rather than store |

---

## 10. Metrics for Success

| Metric | Target |
|---|---|
| % of uploaded-material questions that have their associated figures attached | >80% of questions where Vision detected an image on the same page |
| % of AI-generated questions that required a figure and got one | >90% |
| Figure generation failure rate | <5% |
| Admin review queue throughput (AI-generated figures reviewed within) | <48 hours of generation |
| Student-visible questions with broken/missing "Figure X" references | 0 — this is a North Star invariant violation |

---

## 11. File Map

| New/Changed File | Purpose |
|---|---|
| `priv/repo/migrations/XXXXXX_extend_figures.exs` | Phase 1 schema changes |
| `priv/repo/migrations/XXXXXX_question_figure_specs.exs` | Phase 1 question fields |
| `lib/fun_sheep/figures.ex` | New context: figure creation, attachment, retrieval |
| `lib/fun_sheep/figures/image_generator.ex` | Behaviour definition |
| `lib/fun_sheep/figures/gemini_generator.ex` | Gemini via Interactor SKB implementation |
| `lib/fun_sheep/figures/local_mock_generator.ex` | Dev/test mock |
| `lib/fun_sheep/figures/chart_renderer.ex` | VegaLite → PNG via Playwright |
| `lib/fun_sheep/workers/figure_extraction_worker.ex` | OCR figure extraction (Phase 2) |
| `lib/fun_sheep/workers/figure_generation_worker.ex` | AI figure generation (Phase 4) |
| `lib/fun_sheep/ocr/figure_extractor.ex` | Re-enable, extend with GCS PUT |
| `lib/fun_sheep_web/components/question_figure_component.ex` | Rendering component (Phase 5) |
| `lib/fun_sheep_web/live/practice_live.ex` | Add figure rendering |
| `lib/fun_sheep_web/live/assessment_live.ex` | Add figure rendering |
| `lib/fun_sheep_web/live/question_bank_live.ex` | Figure management UI |
| `lib/fun_sheep_web/live/admin_question_review_live.ex` | Admin approve/reject figures |
