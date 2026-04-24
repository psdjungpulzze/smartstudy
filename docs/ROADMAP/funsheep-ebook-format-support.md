# FunSheep — eBook Format Support: Strategy, Architecture & Roadmap

> **For the Claude session implementing this feature.** Read the entire document before touching any code. eBook support is not simply "accept a new file extension." It is a new extraction pathway that sits alongside the existing PDF/Vision OCR pipeline and feeds into the same downstream materialclassification, relevance scoring, and course structure layers. The most valuable capability eBooks unlock — automatic TOC-driven chapter population — requires schema changes and coordinated work across the upload controller, OCR pipeline router, and course context. Skipping any section will produce a pipeline that accepts files but produces courses with no structure.

---

## 0. Why eBooks Are Different from PDFs

FunSheep's current ingest pipeline is **image-first**: it treats every file as a raster document, runs Google Vision OCR to extract text, then feeds that text to the AI classification and question-generation layers. This works well for PDFs (especially scanned academic textbooks) because PDFs can be split into pages and submitted as image batches to Vision.

**eBooks break this model in three ways:**

### 1. They already contain structured text
An EPUB file is a ZIP archive of XHTML documents. The text is machine-readable without OCR. Routing an EPUB through Vision OCR means: decompress → rasterize pages → OCR → get back nearly the same text, at Vision API cost. That is waste.

### 2. They already contain chapter structure
A well-formed EPUB (and most Kindle/MOBI files) embeds a machine-readable table of contents (NCX or Nav document) that maps chapter titles to HTML files. FunSheep currently spends significant AI effort discovering and proposing course chapters. For eBooks we can extract this structure for free at parse time, producing a pre-populated chapter tree that only needs the user's approval.

### 3. They come in multiple binary formats with different parsers
| Format | Container | Parser approach |
|--------|-----------|----------------|
| EPUB 2/3 | ZIP + XHTML | Native Elixir (`:zip` + `sweet_xml`) |
| MOBI | PalmDB binary | External tool (calibre CLI) |
| AZW3/KFX | Extended MOBI | External tool (calibre CLI) |
| PDF | Already handled | Existing pipeline |

Each format needs its own extraction path before reaching the unified `OcrPage` + chapter tree layers.

---

## 1. DRM Constraints — Non-Negotiable

**FunSheep must never help users circumvent DRM.**

Most ebooks purchased from Amazon (AZW3/MOBI) and many ePubs from major publishers are DRM-protected. DRM circumvention violates the DMCA, the EUCD, and every major regional equivalent. Building a pipeline that attempts to strip or work around DRM is a legal liability and a policy violation.

**What this means in practice:**

1. **DRM-protected files must fail loudly.** When a MOBI/AZW3 upload is detected as DRM-locked, the system must reject it at extraction time with a clear, user-facing message: "This file appears to be DRM-protected. Only DRM-free eBooks can be uploaded. Most academic publishers sell DRM-free PDFs or EPUBs directly."

2. **We detect DRM, we do not bypass it.** MOBI DRM can be detected by checking for an encryption flag in the PalmDB header. AZW3 DRM produces a recognizable calibre extraction error. Both paths must classify the material as `status: :failed` with `error_reason: :drm_protected`.

3. **EPUB DRM (Adobe Adept, LCP) behaves the same.** If extracting an EPUB ZIP produces an encrypted OPS document rather than readable XHTML, fail with the same error.

4. **Clearly supported inputs:**
   - DRM-free EPUBs (Project Gutenberg, Open Textbook Library, OpenStax, Bookboon, most direct-from-publisher sales)
   - DRM-free MOBI/AZW3 (Amazon DRM-free titles, personal conversions)
   - Academic open-access ebooks (arXiv, DOAJ, university presses with open license)

The upload UI must communicate these constraints before the user selects a file.

---

## 2. Format Taxonomy

### Tier 1 — Implement First (Phase 1)
**EPUB 2 and EPUB 3** (`.epub`)

Rationale: Most academic publishers (OpenStax, Pearson, Springer) offer DRM-free EPUB. Open Textbook Library, Project Gutenberg, and OpenStax distribute free EPUBs. This is the format most likely to be uploaded by the target student population. EPUB is a well-specified open standard (W3C EPUB 3.3). It can be parsed with zero external binary dependencies.

### Tier 2 — Implement Second (Phase 2)
**MOBI and AZW3** (`.mobi`, `.azw3`)

Rationale: Amazon Kindle is the dominant ebook reader. Students may own DRM-free MOBI/AZW3 files from Amazon's growing DRM-free catalogue or from personal Calibre conversions. calibre is an established open-source tool (GPL) that can be bundled in the Docker image for format conversion. The converted output is an EPUB that then routes through the Phase 1 parser.

### Tier 3 — Future Consideration (Phase 3+)
- **DJVU** (`.djvu`) — Common for scanned academic texts; requires `djvulibre` CLI
- **HTML/HTM bundles** — Some publishers distribute zip-of-HTML; partially overlaps with EPUB logic
- **DOCX** (`.docx`) — Word documents uploaded directly; `pandoc` can convert to EPUB

---

## 3. Architecture Overview

### Current Pipeline (PDF)
```
Upload → UploadedMaterial record
       → OCRMaterialWorker
         → PdfOcrDispatchWorker
           → pdf_splitter (pdfinfo + qpdf)
           → Google Vision async batch per chunk
           → PdfOcrPollerWorker (poll Vision ops)
             → OcrPage records created
               → MaterialClassificationWorker
               → MaterialRelevanceWorker
               → TextbookCompletenessWorker
```

### New Pipeline (eBook)
```
Upload → UploadedMaterial record (material_format: :epub | :mobi | :azw3)
       → OCRMaterialWorker (enhanced: detect ebook formats)
         │
         ├── [EPUB] → EbookExtractWorker
         │              → EpubParser.extract/1
         │                → DRM check → fail if protected
         │                → Parse OPF (metadata: title, author, publisher, isbn)
         │                → Parse TOC (NCX or Nav) → chapter tree
         │                → Extract spine items → OcrPage records (text from XHTML)
         │                → Extract embedded images → Vision OCR (optional, Phase 2)
         │              → EbookTocImportWorker
         │                → Propose chapters from ebook TOC → DiscoveredTOC records
         │                  (same approval flow as scraped TOC)
         │
         ├── [MOBI/AZW3] → MobiConvertWorker
         │                  → calibre ebook-convert → .epub in /tmp
         │                  → DRM check (calibre error = DRM) → fail if protected
         │                  → EbookExtractWorker (same as EPUB path above)
         │
         └── [Unknown/Unsupported] → fail with :unsupported_format
         
         ↓ (all paths converge here)
         MaterialClassificationWorker (existing, unchanged)
         MaterialRelevanceWorker (existing, unchanged)
         TextbookCompletenessWorker (existing, enhanced for ebook structure)
```

### Key Insight: OcrPage is Format-Agnostic
The `ocr_pages` table already stores `page_number`, `extracted_text`, and `status`. For eBooks, "page" maps to "spine item" (one HTML file = one logical chapter or section). This means:
- AI classification, question extraction, and all downstream workers consume `OcrPage` records identically regardless of source format
- No changes to workers downstream of extraction
- The extraction layer is a thin translation: EPUB spine items → OcrPage rows

---

## 4. Schema Changes

### 4a. `uploaded_materials` — add `material_format`

```elixir
# New migration
add :material_format, :string, default: "unknown"
# Values: "pdf", "epub", "mobi", "azw3", "image", "unknown"
```

This is separate from `file_type` (MIME) because:
- MIME detection can fail on poorly-named files
- MOBI and AZW3 share `application/vnd.amazon.ebook` MIME type
- We want a canonical format identifier that survives MIME ambiguity

Backfill: all existing records with `file_type ILIKE '%pdf%'` → `material_format = "pdf"`, images → `"image"`, unknown → `"unknown"`.

### 4b. `uploaded_materials` — add `ebook_metadata` (JSONB)

```elixir
add :ebook_metadata, :map
# Shape:
# {
#   "title": "Biology: The Science of Life",
#   "authors": ["Sally Raven", "George Johnson"],
#   "publisher": "Pearson",
#   "isbn": "9780134710228",
#   "language": "en",
#   "subject": "Biology",
#   "publication_year": 2019,
#   "spine_item_count": 42,
#   "toc_depth": 3
# }
```

This metadata feeds the course creation suggestion flow and the material relevance score (an ebook whose `subject` matches the course subject gets a relevance boost before AI scoring).

### 4c. `discovered_tocs` — source tracking

The existing `DiscoveredTOC` schema already supports proposing a chapter tree for user approval. Add `source_material_id` (FK to `uploaded_materials`) to track which ebook generated a TOC proposal:

```elixir
add :source_material_id, references(:uploaded_materials, on_delete: :nilify_all)
add :source_type, :string, default: "scraped"
# Values: "scraped", "ebook_toc", "ai_inferred"
```

This allows the UI to label proposals: "Proposed from your uploaded EPUB" vs. "Proposed from web discovery."

---

## 5. Format Detection

Extend `OCRMaterialWorker` (or the `ocr/pipeline.ex` router) with format detection before dispatching to the appropriate sub-worker.

```elixir
defmodule FunSheep.Ocr.FormatDetector do
  @doc """
  Detects the canonical format of a file from its magic bytes and/or extension.
  Downloads only the first 8 bytes for magic byte check before committing to download.
  Returns one of: :pdf | :epub | :mobi | :azw3 | :image | :unknown
  """
  
  # PDF: %PDF- at offset 0
  def detect(<<0x25, 0x50, 0x44, 0x46, _rest::binary>>, _ext), do: :pdf
  
  # EPUB: ZIP magic bytes (PK\x03\x04) + presence of "mimetype" file
  # We check the ZIP header; the full mimetype verification happens in EpubParser
  def detect(<<0x50, 0x4B, 0x03, 0x04, _rest::binary>>, ext) when ext in ["epub"], do: :epub
  def detect(<<0x50, 0x4B, 0x03, 0x04, _rest::binary>>, _ext), do: :epub  # attempt EPUB regardless
  
  # MOBI: PalmDB header magic "BOOK" + "MOBI" at offsets 60-63
  # First 4 bytes are the database name (variable); check at offset 60
  def detect(bytes, ext) when ext in ["mobi"], do: :mobi
  def detect(bytes, ext) when ext in ["azw", "azw3", "kfx"], do: :azw3
  
  # Images
  def detect(<<0xFF, 0xD8, 0xFF, _rest::binary>>, _ext), do: :image  # JPEG
  def detect(<<0x89, 0x50, 0x4E, 0x47, _rest::binary>>, _ext), do: :image  # PNG
  def detect(<<0x47, 0x49, 0x46, _rest::binary>>, _ext), do: :image  # GIF
  
  def detect(_bytes, _ext), do: :unknown
end
```

**Detection order in `OCRMaterialWorker`:**
1. Fetch first 128 bytes from storage (cheap, no full download)
2. Call `FormatDetector.detect(bytes, Path.extname(file_name))`
3. Update `material_format` field on the `UploadedMaterial` record
4. Dispatch to appropriate worker

---

## 6. EPUB Extraction (Phase 1 — Core)

### 6a. `FunSheep.Ebook.EpubParser`

```elixir
defmodule FunSheep.Ebook.EpubParser do
  @doc """
  Extracts all content from a DRM-free EPUB file.
  
  Returns {:ok, %EpubContent{}} or {:error, reason}
  
  Reasons:
    :drm_protected    — encryption detected in OPS manifest
    :invalid_epub     — ZIP valid but not a conformant EPUB
    :missing_opf      — container.xml present but OPF not found
  """
  
  defstruct [
    :metadata,    # %{title, authors, isbn, publisher, language, ...}
    :toc,         # [%{title, depth, spine_id, children: [...]}]
    :spine_items, # [%{id, href, text, images: [...]}]  — ordered
  ]
end
```

**Extraction steps:**
1. Download file from storage to `/tmp/<material_id>.epub`
2. Open as ZIP using `:zip.unzip/2` with `[:memory]` option (no disk write for small files; stream for large)
3. Read `META-INF/container.xml` → extract OPF path
4. Parse OPF (`content.opf`):
   - Dublin Core metadata → `ebook_metadata`
   - `<manifest>` items (id → href map)
   - `<spine>` idrefs (ordered list of content documents)
5. Parse navigation document:
   - EPUB 3: `nav.xhtml` with `<nav epub:type="toc">`
   - EPUB 2: `toc.ncx` with `<navMap>` / `<navPoint>`
   - Build nested `%{title, depth, children}` tree
6. For each spine item (in order):
   - Read XHTML file from ZIP
   - Strip HTML tags with `Floki.text/1` (or custom stripper — no JS needed, just text nodes)
   - Normalize whitespace
   - Store as one `OcrPage` record per spine item
7. For each `<img>` in spine items:
   - Extract from ZIP, store in `source_figures`
   - Optionally enqueue Vision OCR for figure text (Phase 2)

**Library dependencies to add:**
```elixir
# mix.exs
{:floki, "~> 0.36"},     # HTML parsing + text extraction (already common in Phoenix projects)
{:sweet_xml, "~> 0.7"},  # XPath for XML (OPF, NCX parsing)
```

Both are lightweight Elixir libraries. No external binaries required for EPUB.

### 6b. `FunSheep.Workers.EbookExtractWorker`

```elixir
defmodule FunSheep.Workers.EbookExtractWorker do
  use Oban.Worker, queue: :ebook, max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)
    
    with {:ok, file_path} <- Storage.get(material.file_path, dest: "/tmp/#{material_id}.epub"),
         {:ok, epub} <- EpubParser.extract(file_path),
         :ok <- update_ebook_metadata(material, epub.metadata),
         :ok <- create_ocr_pages(material, epub.spine_items),
         :ok <- propose_toc_from_ebook(material, epub.toc) do
      Content.update_material_ocr_status(material, :completed)
      :ok
    else
      {:error, :drm_protected} ->
        Content.update_material_ocr_status(material, :failed,
          error: "DRM-protected file. Only DRM-free eBooks are supported.")
        :ok  # Don't retry; this won't fix itself
      
      {:error, reason} ->
        {:error, reason}  # Oban will retry
    end
  after
    File.rm("/tmp/#{material_id}.epub")
  end
end
```

**Queue:** Add `:ebook` queue to Oban config, concurrency 5 (EPUB extraction is CPU-light).

### 6c. TOC Import Worker

```elixir
defmodule FunSheep.Workers.EbookTocImportWorker do
  use Oban.Worker, queue: :ai, max_attempts: 2
  
  @doc """
  Converts an EPUB TOC tree into DiscoveredTOC chapter proposals
  that the user can approve in the existing TOC rebase UI.
  """
end
```

The TOC import creates `DiscoveredTOC` records with `source_type: "ebook_toc"` and `source_material_id` pointing to the uploaded EPUB. The existing TOC approval UI (already built) surfaces these proposals to the user with a label indicating they came from the ebook itself.

This is a significant UX advantage over PDF uploads, where the TOC must be AI-inferred from OCR text.

---

## 7. MOBI/AZW3 Extraction (Phase 2)

### 7a. calibre Integration

calibre's `ebook-convert` CLI can convert MOBI/AZW3 → EPUB. It is the industry standard and handles edge cases (embedded fonts, split files, AZW3 extensions) better than any library-based approach.

**Docker image change:** Add `calibre` to the Dockerfile:
```dockerfile
RUN apt-get install -y calibre
# calibre installs ebook-convert at /usr/bin/ebook-convert
```

**Calibre usage:**
```elixir
defmodule FunSheep.Ebook.MobiConverter do
  def convert(input_path, output_path) do
    case System.cmd("ebook-convert", [input_path, output_path],
           stderr_to_stdout: true, timeout: 60_000) do
      {_output, 0} ->
        {:ok, output_path}
      
      {output, _exit_code} when output =~ "DRM" or output =~ "encrypted" ->
        {:error, :drm_protected}
      
      {output, exit_code} ->
        {:error, {:conversion_failed, exit_code, output}}
    end
  end
end
```

calibre explicitly errors with DRM-related messages when encountering encrypted MOBI/AZW3. This is our DRM detection mechanism for Kindle formats.

**Worker:**
```elixir
defmodule FunSheep.Workers.MobiConvertWorker do
  use Oban.Worker, queue: :ebook, max_attempts: 2
  
  # Downloads MOBI/AZW3 → converts to EPUB via calibre → enqueues EbookExtractWorker
end
```

### 7b. calibre Image Size Consideration

calibre is approximately 700 MB installed. This may affect Docker image size and cold-start time on Cloud Run. Mitigation options:

1. **Multi-stage build**: Only include calibre in the prod image, not the build stage
2. **Separate microservice**: A small sidecar service that only runs calibre, called via HTTP from the BEAM worker (overkill for V1)
3. **Accept the size**: Cloud Run keeps instances warm; cold starts are infrequent and the 700 MB amortizes across all other capabilities

Recommendation for Phase 2: accept the image size increase. If it becomes a problem, extract to a microservice later.

---

## 8. Upload UI Changes

### 8a. File Accept Attribute
Update the upload LiveView component to accept ebook MIME types:

```elixir
# Phase 1
accept: ".pdf,.epub,application/pdf,application/epub+zip"

# Phase 2 (add)
accept: ".mobi,.azw,.azw3,application/vnd.amazon.ebook"
```

### 8b. Material Kind Heuristics
Extend `normalize_kind/1` in the upload controller:

```elixir
defp normalize_kind(filename) do
  lower = String.downcase(filename)
  cond do
    String.contains?(lower, ["answer", "answer-key", "solutions", "key"]) -> :answer_key
    String.contains?(lower, ["quiz", "practice-test", "sample-questions", "past-exam", "mock-exam"]) -> :sample_questions
    Path.extname(lower) in [".epub", ".mobi", ".azw", ".azw3"] -> :textbook  # ebooks are almost always textbooks
    true -> :textbook
  end
end
```

### 8c. Pre-upload DRM Warning
Add a callout in the upload UI for ebook formats:

> **eBook files:** Only DRM-free eBooks are supported. Most publisher-sold and Amazon-sold eBooks include DRM encryption that prevents processing. DRM-free sources include OpenStax, Project Gutenberg, Open Textbook Library, and some direct publisher sales. If you're unsure whether your file has DRM, try uploading — you'll receive a clear error if it does.

---

## 9. Error States

Every ebook-specific failure must produce a user-visible, actionable error. The material `ocr_status` must be `failed` with a descriptive `error_message`. Silently dropping the file or leaving it in a `processing` state indefinitely is not acceptable (per the CLAUDE.md no-fake-content policy — failures must be honest).

| Error | `error_message` |
|-------|----------------|
| DRM detected (EPUB) | "This eBook file is DRM-protected. Only DRM-free eBooks can be uploaded." |
| DRM detected (MOBI/AZW3) | "This Kindle file is DRM-protected. Only DRM-free Kindle files can be uploaded." |
| Invalid EPUB structure | "The EPUB file appears to be corrupted or malformed. Try re-downloading it from the source." |
| Empty spine | "The EPUB file contains no readable text content." |
| calibre timeout | "eBook conversion timed out. The file may be too large or malformed." |
| Unsupported format | "This file format is not yet supported. Supported formats: PDF, EPUB, MOBI, AZW3." |

---

## 10. Testing Requirements

Per CLAUDE.md, every new module needs tests. eBook parsing is especially important to test thoroughly because it is the only code path where we're parsing user-supplied binary files (attack surface).

### Unit Tests

| Module | What to test |
|--------|-------------|
| `EpubParser` | Valid EPUB 2, valid EPUB 3, DRM-detected EPUB, empty spine, malformed ZIP, missing OPF, missing NCX, deeply nested TOC |
| `FormatDetector` | PDF magic bytes, EPUB magic bytes, MOBI extension, AZW3 extension, unknown bytes |
| `MobiConverter` | Successful conversion (mock System.cmd), DRM error output, timeout, generic failure |
| `EbookTocImportWorker` | Creates DiscoveredTOC records from parsed TOC, correct depth mapping, nil TOC gracefully skipped |

### Test Fixtures
Create small, legally distributable fixture files in `test/fixtures/ebooks/`:
- `valid_epub2.epub` — minimal valid EPUB 2 (generated via script)
- `valid_epub3.epub` — minimal valid EPUB 3 with nav.xhtml
- `drm_epub.epub` — ZIP with encrypted OPS (simulate DRM)
- `empty_spine.epub` — valid OPF but empty `<spine>`
- `corrupt.epub` — truncated ZIP

Generate these in a `test/support/ebook_fixtures.ex` factory using `:zip` directly, so no binary blobs need to be committed.

---

## 11. Implementation Phases

### Phase 1 — EPUB Support
**Estimated scope:** ~2–3 days of implementation

Tasks:
1. `mix ecto.gen.migration add_ebook_fields_to_uploaded_materials`
   - Add `material_format :string`
   - Add `ebook_metadata :map`
   - Add `source_material_id` FK to `discovered_tocs`
2. Add `floki` and `sweet_xml` to `mix.exs` (check if `sweet_xml` already present)
3. Implement `FunSheep.Ocr.FormatDetector`
4. Implement `FunSheep.Ebook.EpubParser`
   - OPF parsing
   - NCX parsing (EPUB 2)
   - Nav parsing (EPUB 3)
   - Spine text extraction via Floki
   - DRM detection
5. Implement `FunSheep.Workers.EbookExtractWorker`
6. Implement `FunSheep.Workers.EbookTocImportWorker`
7. Extend `OCRMaterialWorker` to detect format and route to `EbookExtractWorker`
8. Add `:ebook` queue to Oban config
9. Update upload controller: accept `.epub`, DRM warning text
10. Write all unit tests (fixtures generated in test support)
11. Visual verify: upload an OpenStax Biology EPUB; confirm chapters proposed, OCR pages created

**Definition of done:**
- Uploading a DRM-free EPUB creates `OcrPage` records, one per spine item
- EPUB metadata is stored in `ebook_metadata`
- A `DiscoveredTOC` proposal appears in the course UI for user approval
- Uploading a DRM-protected EPUB sets `ocr_status: :failed` with a human-readable message
- `mix test --cover` shows > 80% coverage across new modules

### Phase 2 — MOBI/AZW3 Support
**Estimated scope:** ~1–2 days of implementation

Tasks:
1. Add calibre to Dockerfile
2. Implement `FunSheep.Ebook.MobiConverter`
3. Implement `FunSheep.Workers.MobiConvertWorker`
4. Extend `FormatDetector` for MOBI PalmDB magic bytes
5. Extend upload controller: accept `.mobi`, `.azw3`
6. Write tests (mock `System.cmd` for calibre calls)
7. Visual verify: upload a DRM-free MOBI file; confirm identical outcome to EPUB path

**Definition of done:**
- MOBI/AZW3 files route through calibre → EPUB → existing Phase 1 extractor
- DRM-locked files fail with clear message
- Dockerfile size increase is documented in release notes

### Phase 3 — Image Extraction from eBooks (Optional Enhancement)
**Estimated scope:** ~1 day

Many textbook EPUBs include figures, diagrams, and graphs as embedded images. Phase 1 skips these. Phase 3 would:
1. During spine extraction, collect `<img>` references from XHTML
2. Extract images from ZIP, store as `SourceFigure` records
3. Enqueue Vision OCR for each image (same as existing figure extraction for PDFs)
4. Associate extracted figure text back to the relevant `OcrPage`

This is valuable for STEM textbooks where diagrams carry significant content.

---

## 12. Files to Create / Modify

### New Files
```
lib/fun_sheep/ebook/
├── epub_parser.ex                  ← EPUB extraction (OPF, NCX, Nav, spine text)
├── mobi_converter.ex               ← calibre wrapper
└── format_detector.ex              ← magic bytes + extension heuristic

lib/fun_sheep/workers/
├── ebook_extract_worker.ex         ← Oban worker: EPUB extraction → OcrPage creation
├── ebook_toc_import_worker.ex      ← Oban worker: TOC → DiscoveredTOC proposals
└── mobi_convert_worker.ex          ← Oban worker: MOBI → calibre → EPUB

priv/repo/migrations/
└── YYYYMMDDHHMMSS_add_ebook_fields.exs

test/fun_sheep/ebook/
├── epub_parser_test.exs
├── mobi_converter_test.exs
└── format_detector_test.exs

test/fun_sheep/workers/
├── ebook_extract_worker_test.exs
└── ebook_toc_import_worker_test.exs

test/support/
└── ebook_fixtures.ex               ← Generates minimal in-memory EPUB fixtures
```

### Modified Files
```
lib/fun_sheep/workers/ocr_material_worker.ex    ← Add format detection + ebook routing
lib/fun_sheep/content/uploaded_material.ex      ← Add material_format, ebook_metadata fields
lib/fun_sheep/courses/discovered_toc.ex         ← Add source_material_id, source_type fields
lib/fun_sheep_web/controllers/upload_controller.ex  ← Accept ebook MIME types, kind heuristic
config/config.exs                               ← Add :ebook Oban queue
mix.exs                                         ← Add :floki (if not present), :sweet_xml
Dockerfile                                      ← Add calibre (Phase 2 only)
```

---

## 13. Open Questions (Resolve Before Implementation)

1. **`sweet_xml` already a dependency?** Check `mix.exs` — if it is, no change needed. If not, also evaluate `xmerl` (built-in OTP) as an alternative to avoid a new dep.

2. **`floki` already a dependency?** Floki is commonly used in Phoenix test helpers. Check before adding.

3. **Oban queue name conflict?** Confirm `:ebook` does not conflict with any existing queue name.

4. **GCS partial download API?** The current GCS client downloads full files. For EPUB, we only need to read the ZIP central directory to check for DRM before downloading the full file. Check if `Storage.get_partial/3` is feasible or if full download is acceptable given typical EPUB sizes (5–50 MB vs PDF 50–500 MB).

5. **DiscoveredTOC approval UI labeling:** The existing TOC approval screen should show "Imported from EPUB" vs "Discovered from web" to help users understand the proposal's origin. Confirm with product/design whether a simple label in the existing UI suffices or if a separate list section is needed.

6. **Phase 2 Docker image size:** Measure `calibre` apt-get install size in CI. If it exceeds acceptable limits, evaluate `ebook-convert` standalone package alternatives or deferred microservice extraction.

---

## 14. Success Metrics

| Metric | Target |
|--------|--------|
| EPUB upload → first OcrPage created | < 30 seconds for a 20 MB textbook |
| EPUB TOC proposal accuracy | TOC chapters match ebook chapters with 0 hallucination (deterministic parse) |
| DRM rejection rate accuracy | 0% false positives (DRM-free files rejected), ≥ 95% true positive (DRM-locked files caught) |
| MOBI conversion success rate | ≥ 95% for DRM-free MOBI files |
| Test coverage on new ebook modules | ≥ 80% (per project standard) |

---

*Document created: 2026-04-24*
*Status: Planning complete, awaiting implementation*
