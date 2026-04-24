# FunSheep OCR Throughput — Strategy Proposal

**Problem:** A single 940-image textbook currently takes ~14 hours to OCR end-to-end. At launch, multiple parents/teachers/students will be uploading textbooks in parallel. The current pipeline cannot absorb that without the queue building into days of backlog.

**Empirical baseline** (measured 2026-04-20 → 2026-04-21 on course `d44628ca`, 940 JPG pages):
- Effective throughput: **0.3–1.4 completions/min** (highly variable)
- Oban `ocr` queue concurrency: **4** workers, pinned to **1** Cloud Run instance
- Cloud SQL tier: **db-g1-small** (shared-core)
- Terminal success rate: **99.8%** once retries absorb transport errors
- Error profile during drain: ~100-500 transient `sndbuf :einval` / `socket closed` per hour; retries absorb 100%

---

## Root causes

The throughput ceiling is **not** Vision API. Google Vision itself responds in 2–5 seconds per call. The bottleneck is a stack of structural issues:

### 1. Cloud SQL db-g1-small is saturated at 4 workers

Oban's internal `Peer` and `Notifier` GenServers both time out at 5s roughly once per minute. These are not OCR errors — they're Oban waiting on a DB connection. Every timeout stalls job dispatch. The throughput ceiling we observe (~1/min) is the DB handling ~4 workers + Oban's own DB traffic, not the OCR itself.

### 2. Per-image materials model multiplies all overhead by the page count

A 940-page textbook uploaded as individual JPGs becomes:
- 940 Oban job rows
- 940 worker pickups
- 940 Vision API calls (one round-trip each)
- 940 `UPDATE uploaded_materials` transactions
- 940 `increment_ocr_completed` course-counter updates
- 940 PubSub broadcasts to the course detail LiveView
- 940 `MaterialRelevanceWorker` + `TextbookCompletenessWorker` enqueues

Per-job overhead dominates. Each material takes 5–10s of wall-clock even when Vision responds in 2s.

### 3. Cloud Run egress NAT drops idle HTTP/1 sockets faster than Finch's default pool recycles them

Result: periodic `sndbuf :einval` and `socket closed` storms. Retries absorb them, but each retry costs 2–8s of backoff, so throughput halves during storms.

### 4. Single worker instance at min/max_scale=1

Cloud Run scales horizontally by default. Hard-capping the worker at 1 instance is a deliberate configuration that caps total OCR concurrency at the 4 workers inside that one container. It should not exist.

### 5. Users are forced into the slowest path

Scanner output is a pile of JPGs, so users upload 940 separate files. The PDF path (`files:asyncBatchAnnotate`, shipped in PR #9) can process an entire textbook in **one** async Vision operation that Google parallelizes server-side, but nothing in the UI encourages or auto-converts to PDF.

---

## Solution strategy — four tiers

Deploy tier by tier; each tier independently moves the needle.

---

### Tier 1 — Infrastructure (deploy today, ~10x throughput, ~$130/mo delta)

These are config changes. No code required except the deploy script edit.

| Change | File | Effect |
|---|---|---|
| Cloud SQL: `db-g1-small` → `db-custom-1-3840` | `scripts/deploy/gcp-setup.sh` or one-time `gcloud sql instances patch` | 1 dedicated vCPU + 3.84GB RAM. Removes Oban.Peer/Notifier timeout storms. |
| Worker min/max scale: `1`/`1` → `2`/`5` | `scripts/deploy/deploy-prod.sh` worker promote step | Horizontal scaling; throughput scales near-linearly with instance count. |
| Worker OCR concurrency: `4` → `8` | `config/runtime.exs` `oban_queues` | With DB headroom, the sndbuf issue no longer cascades. |
| `POOL_SIZE`: `35` → `50` | deploy script env var | Headroom for 2–5 workers × (default 10 + ocr 8 + ai 5 + ingest 1 + Oban internals). |

**Expected throughput:** 2–5 instances × 8 OCR workers = **16–40 concurrent OCR jobs** globally. At ~5s per Vision call with no DB contention:

- Single-instance baseline: 4 jobs / 10s = **~24/min** (20× current)
- 3-instance scale-out: 24 jobs / 10s = **~144/min**
- **940-page textbook: ~7 min** (currently 14 hours)
- **10 concurrent textbooks: ~70 min**

**Cost delta (fixed monthly):**
| Item | Before | After | Delta |
|---|---|---|---|
| Cloud SQL tier | db-g1-small (~$15) | db-custom-1-3840 (~$48) | **+$33/mo** |
| Cloud Run worker always-on (cpu=2, mem=1Gi, min=1→2) | ~$95/mo | ~$190/mo | **+$95/mo** |
| Scale-out to max=5 | — | Pay-per-second, only during sustained drain load | **$0–$285/mo variable** |
| Vision API, GCS, egress | unchanged | unchanged | $0 |
| **Fixed delta** | | | **~$128/mo** |
| **With sustained peak** | | | **up to ~$413/mo** |

**Risk:** Low. All changes are reversible via deploy rollback. Cloud SQL tier upgrade has a ~1-min failover but we have min-instance=1 so API stays up.

---

### Tier 2 — UX honesty (1–2 days, perception > reality)

Even a 7-minute wait feels long if the user stares at a spinner. These changes make waiting tolerable.

#### 2a. Accurate progress + moving-average ETA

Currently the course detail shows `"OCR processing: 450/940 files..."` but it increments on **all** terminal states (including failures) and has no time estimate. Users can't tell if it's stuck.

- Add `ocr_started_at` to `uploaded_materials` or `courses`
- Compute rolling throughput: `completed_in_last_5_min / 5`
- Display: `"Processing... 420 of 940 pages done. Expected ready at 3:42 PM."`

#### 2b. "Come back later" flow

For any job expected to take > 3 minutes:
- Show: `"Your textbook is being processed. We'll email you when it's ready — roughly 12 minutes from now. Feel free to close this page."`
- Send an email via Swoosh when the course transitions to `ready` status.
- Add a `/course/:id` route that hydrates ready content regardless of processing state.

#### 2c. Progressive unlock (highest-impact UX)

Don't gate the student on **full** OCR completion. Question extraction already keys off individual `OcrPage` records — we can generate questions from the first 100 completed pages while the rest process in parallel.

- Flip `process_course_worker` to trigger `QuestionExtractionWorker` after every N pages instead of after all pages
- Incremental question generation means the student can open the course and start practicing within ~1 minute, even for a 1,000-page textbook
- Show a "More questions being added..." banner until the backlog drains

#### 2d. Upload guidance

Surface PDF as the recommended upload format:
- Upload dialog primary CTA: "Upload PDF textbook (fastest)"
- Secondary: "Upload page images" with a warning: "Images are processed individually — for faster results, combine into a single PDF first."
- Provide a free in-browser JPG → PDF combiner if we want to remove the friction entirely (use [pdf-lib](https://pdf-lib.js.org/) client-side).

---

### Tier 3 — Architectural (1 week, solves the root problem)

#### 3a. Server-side JPG → PDF batching

When a user uploads many JPGs to the same course folder in one batch:
- Group them by `batch_id` + `folder_name` on the server
- When batch completes, combine into a single PDF using ImageMagick or pdfkit
- Enqueue one `PdfOcrPollerWorker` job instead of N image jobs
- Net effect: 940-job batch collapses to 1 Vision async call that Google processes in parallel server-side

Implementation surface: new `FunSheep.Workers.BatchPdfifyWorker` that fires when `ingest_worker` finishes enqueuing. Cheap: ImageMagick combine is single-digit seconds for 1,000 images.

#### 3b. Move Google Vision calls to gRPC with persistent HTTP/2 connection

The sndbuf/socket-closed storm comes from REST over HTTP/1 pool churn. gRPC to Vision uses one long-lived HTTP/2 connection with ping/keepalive that survives NAT idle-kills.

Elixir gRPC story:
- `grpc-elixir` + `google_api_vision` hex packages
- Or write a thin wrapper using `grpc_elixir` against `google/cloud/vision/v1/image_annotator.proto`
- One-time cost; eliminates transport errors entirely

#### 3c. Per-page progressive OCR result streaming

Vision's `files:asyncBatchAnnotate` writes output JSON to GCS as pages complete. Today's `PdfOcrPollerWorker` (PR #9) waits until `done: true` then reads all outputs. Alternative: poll the GCS output prefix during processing and ingest pages as they appear. User sees progress every few seconds.

---

### Tier 4 — Cost vs speed SKUs (business decision)

Google Vision is cheap (~$1.50 / 1,000 pages). For premium-tier users who need sub-1-minute turnaround, benchmark alternatives:

| Provider | Per-page cost estimate | Latency characteristic |
|---|---|---|
| Google Vision (current) | $0.0015 | 2–5s sync, async scales to hundreds of pages/sec |
| Anthropic Claude Sonnet vision | $0.01–0.02 | ~3–5s per page, can batch many pages per call |
| OpenAI GPT-4o vision | $0.01–0.02 | Similar to Claude |
| AWS Textract | $0.0015–0.004 | Async, similar pattern to Google |

Claude/GPT-4o give **better extraction quality** on complex layouts (charts, diagrams, handwriting). Worth benchmarking on a sample of the AP Biology textbook pages for accuracy.

Suggested model:
- **Free tier:** Google Vision + honest ETA (Tier 1+2 above) — "processed within 10 minutes"
- **Paid tier:** Claude/GPT-4o for premium speed + accuracy — "processed within 2 minutes, with figure understanding"

This also opens up a moat: higher-accuracy OCR → better question quality → better study outcomes.

---

## Recommended deployment order

1. **This week (Tier 1):** Cloud SQL tier upgrade + worker autoscale. Code change: ~1 hour. **Expected: 14h → 7min per textbook.** One flag flip gets us most of the way.

2. **Next week (Tier 2a, 2b, 2d):** Progress tracking with ETA, email notification, upload guidance. Two engineer-days.

3. **Week after (Tier 2c):** Progressive unlock — students can use the course at 100 pages of 940 completed. Requires reworking `QuestionExtractionWorker` trigger logic but unlocks the UX permanently.

4. **Month out (Tier 3a, 3b):** Server-side JPG→PDF batching + gRPC Vision client. Removes the last architectural hotspots.

5. **Quarter (Tier 4):** Benchmark Claude/OpenAI OCR, decide on tiered product SKUs.

---

## Estimated impact table

| State | Per-textbook time | Concurrent textbooks | Monthly fixed infra delta |
|---|---|---|---|
| Today (baseline) | 14 hours | Effectively 1 (rest queue) | $0 |
| + Tier 1 | ~7 min | 10 concurrent fit in 70 min | +$128/mo fixed, up to +$413/mo at sustained peak |
| + Tier 2c (progressive unlock) | User-perceived: 1 min (start studying); full drain same as above | Same | +$0 infra, 3–5 dev-days |
| + Tier 3a (PDF batching) | ~2 min (Google parallelizes server-side) | 50+ concurrent | +$0 infra, 3–4 dev-days |
| + Tier 3b (gRPC) | ~1.5 min | 100+ concurrent | +$0 infra, 5–7 dev-days |

---

## Full cost model — fixed, variable, and per-textbook

### Fixed monthly infrastructure

| Component | Today | After Tier 1 | After Tier 3 |
|---|---|---|---|
| Cloud SQL | db-g1-small ~$15 | db-custom-1-3840 ~$48 | same as Tier 1 |
| Cloud Run API | scale-to-zero, ~$5–20 | unchanged | unchanged |
| Cloud Run worker (always-on instances) | 1 × cpu=2 ~$95 | 2 × cpu=2 ~$190 | 2 × cpu=2 ~$190 |
| GCS storage (at 10,000 textbooks × ~500MB) | ~$100 | ~$100 | ~$100 |
| Egress (Vision is intra-Google = free; API → users minimal) | ~$5 | ~$5 | ~$5 |
| **Fixed subtotal** | **~$220/mo** | **~$348/mo** | **~$348/mo** |

### Variable — Cloud Run worker scale-out

Only billed when traffic sustains a second/third instance active. At cpu=2, mem=1Gi, ~$95 per always-on instance-month.

- Light usage (2–5 textbooks/hour): stays at min=2, no variable cost
- Medium (20–50 textbooks/hour): max=3–4 instances during peaks → ~$95–190/mo extra
- Heavy (100+ textbooks/hour sustained): max=5 pegged → ~$285/mo extra

### Variable — per-textbook Vision API cost

Google Vision DOCUMENT_TEXT_DETECTION: **$0.0015 per page** (first 1K pages/mo free, then $1.50/1K, then tiered discounts above 5M).

| Volume | Cost/day | Cost/mo |
|---|---|---|
| 10 textbooks/day (940 pages each) | $14 | $420 |
| 100 textbooks/day | $141 | $4,230 |
| 500 textbooks/day | $705 | $21,150 |
| 1,000 textbooks/day | $1,410 | $42,300 |

**This is the dominant cost at scale**, not infrastructure. Two critical mitigations:

**Mitigation A — Textbook dedup (single biggest cost lever).** If 10,000 students all upload the same AP Biology textbook, we should OCR it once and reuse. Architectural work:
- Hash (md5/sha256) each uploaded PDF/image set on ingest
- Check against a canonical `textbooks` catalog
- If match, reuse `OcrPage` rows — Vision cost = $0 for this user
- Expected hit rate at maturity: 60–90% (popular courses dominate)
- **Effective per-textbook Vision cost could drop to $0.15–0.50 instead of $1.41**

**Mitigation B — Only OCR pages that yield questions.** Today we OCR the entire textbook. Often the first 100–200 pages are enough for the student's current chapters. Lazy OCR (on-demand by chapter) could cut the average pages-per-student by 3–5× without hurting UX.

### Variable — Tier 4 premium OCR (if we add paid tier)

| Provider | Per-page | 940-page textbook |
|---|---|---|
| Google Vision (base) | $0.0015 | $1.41 |
| Claude Sonnet vision (batched ~10 pages/call, ~1,500 output tokens) | ~$0.012 | ~$11.30 |
| GPT-4o vision | ~$0.01 | ~$9.40 |
| Claude Opus vision (highest accuracy) | ~$0.04 | ~$37.60 |

Premium tier pricing concept: charge $5–10/textbook for premium, margin of $0–5 after Claude/GPT cost. Value prop = speed + figure understanding + handwriting.

### Dev time estimate (opportunity cost)

| Tier | Effort | At $100/hr contractor rate | Internal engineer (opportunity cost) |
|---|---|---|---|
| Tier 1 | 1–2 hours | $100–200 | 0.25 engineer-day |
| Tier 2 (all four sub-items) | 3–5 days | $2,400–4,000 | ~1 engineer-week |
| Tier 3a (JPG→PDF batching) | 3–4 days | $2,400–3,200 | ~1 engineer-week |
| Tier 3b (gRPC Vision client) | 5–7 days | $4,000–5,600 | ~1.5 engineer-weeks |
| Tier 4 (benchmark + paid tier build) | 2–4 weeks | $16,000–32,000 | ~1 engineer-month |
| **Textbook dedup (Mitigation A)** | 3–5 days | $2,400–4,000 | ~1 engineer-week |

### Cost summary at target scale (500 textbooks/day)

Without optimization:
- Fixed: $348/mo (Tier 1 deployed)
- Scale-out: ~$190/mo average
- Vision: **$21,150/mo** ← overwhelming
- **Total: ~$21,688/mo**

With textbook dedup (Mitigation A, 80% hit rate):
- Fixed: $348/mo
- Scale-out: ~$190/mo
- Vision: **$4,230/mo** (80% cache hits, 20% uncached)
- **Total: ~$4,768/mo — 78% reduction**

**Verdict:** Tier 1 is the cheapest win and must happen first. Textbook dedup (Mitigation A) is the highest-ROI engineering investment after Tier 1 — at $500/day of Vision spend it pays for itself in a week.

---

## Immediate action items for the next Claude session

1. `scripts/deploy/gcp-setup.sh` — patch Cloud SQL tier:
   ```bash
   gcloud sql instances patch funsheep-db \
     --project=funsheep-prod \
     --tier=db-custom-1-3840
   ```
   Expect ~1 min of DB failover; web API's health check will retry through it.

2. `scripts/deploy/deploy-prod.sh` — change the worker promote step:
   - `--min-instances` from `1` to `2`
   - `--max-instances` (add flag) to `5`
   - `POOL_SIZE=35` → `POOL_SIZE=50`

3. `config/runtime.exs` — change `[default: 10, ocr: 4, ai: 5, ingest: 1]` → `[default: 10, ocr: 8, ai: 5, ingest: 1]`.

4. Deploy via `scripts/deploy/deploy-prod.sh` — verify worker logs no longer show `Oban.Peer.leader?/2 check failed` timeouts within the first 10 minutes of drain activity.

5. Verify single-textbook end-to-end time on a fresh test upload: target < 10 minutes for 940 pages.

---

## What NOT to do

- **Don't switch from Google Vision to Claude/GPT-4o for the free tier.** The 10× cost kills unit economics for students who upload huge textbooks. Reserve for paid SKU.
- **Don't add Oban Cron-based cleanup workers "just in case."** Lifeline already handles job orphans. Materials with `ocr_status=:processing` and no active job is a real bug we'd want to know about, not silently fix.
- **Don't increase Finch's default pool size to "handle" sndbuf errors.** The fix is gRPC or a named pool with HTTP/2 — not bigger pool = more dead sockets.
- **Don't batch multiple textbooks into one Vision async call.** Per-course isolation matters for failure domains and billing accuracy.
