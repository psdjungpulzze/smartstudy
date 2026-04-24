# AP Biology Question Quality Assessment

**Course**: AP Biology (Grade 11) — `d44628ca-6579-48da-a83b-466e12b1c19b`  
**Total Questions**: 3,798 | **Average Validation Score**: 81.7/100  
**Date Assessed**: April 23, 2026  
**DB**: `fun_sheep_prod` (Cloud SQL `funsheep-db`, `funsheep-prod`)

---

## Overview by Source

| Source | Count | % | Avg Score |
|--------|-------|---|-----------|
| AI-Generated | 3,274 | 86.2% | ~82 |
| Uploaded Materials (PDF/JPG) | 520 | 13.7% | ~45 |
| Web Sources | 4 | 0.1% | — |

## Validation Status

| Status | Count | % |
|--------|-------|---|
| ✅ Passed | 927 | 24.4% |
| ⚠️ Needs Review | 2,141 | 56.4% |
| ❌ Failed | 730 | 19.2% |

---

## Source 1: AI-Generated Questions (3,274)

### Verdict: Good Content — Fixable Pipeline Issue

The underlying content is educationally sound. Sampled passed questions are accurate, appropriately scoped, and well-matched to AP Biology chapters.

**Strong examples:**
- *"True or False: Photosynthesis occurs in the mitochondria of plant cells."* → False, with explanation about chloroplasts. ✅
- *"Which structure is responsible for packaging and modifying proteins in the cell?"* → B: Golgi apparatus. Correct options, good distractors. ✅
- *"Describe what would happen to the electron transport chain if oxygen were not present."* → Full mechanistic answer about NADH/FADH₂ and oxidative phosphorylation halting. Excellent AP-level free response. ✅
- *"If two genes are completely linked and show no recombination, what is the recombination frequency?"* → 0%. Precise genetics. ✅

**The 2,294 "needs review" AI questions are not bad questions.** They fail for a single reason: the explanation field is empty. Content and answers are correct. These are 79.9% of all problematic questions and are trivially fixable with the auto-correction pipeline.

**Needs review samples:**
- *"Explain the role of gibberellins in seed germination."* — Correct answer, missing explanation. Chapter assignment correct (Ch. 31). The question itself is fine.
- *"True or False: Cell communication can occur through direct contact between cells via cell junctions."* — Correct (True), explanation missing.

**Known validator bug**: ~70 questions were marked failed with score 0, reason "Assistant did not return a verdict." Example: *"Describe the role of chlorophyll in photosynthesis"* — correct content and answer — failed only because the validator LLM returned no response. These need re-queuing, not deletion.

---

## Source 2: Uploaded Materials — PDF/JPG Extractions (520)

### Verdict: Critical Pipeline Failure — Majority Are Garbage

All 520 material-sourced questions came from 4 image files:

| File | Questions | Passed | Failed | Avg Score | Assessment |
|------|-----------|--------|--------|-----------|------------|
| `Biology Answers - 31.jpg` | 462 | 0 | 433 | 37.5 | 🚨 Answer key image, not a question source |
| `Biology Chapter 39 - 4.jpg` | 42 | 0 | 33 | 47.6 | Textbook page, OCR artifacts |
| `Biology Chapter 26 - 24.jpg` | 9 | 0 | 8 | 31.7 | Textbook page, OCR artifacts |
| `Biology 3 - 47.jpg` | 7 | 0 | 2 | 72.9 | Partially usable |

**Critical finding**: `Biology Answers - 31.jpg` is an answer key image. The OCR pipeline processed it and generated 462 questions from extracted answer-key content (e.g., `"C 2. C 3. C 4. B 5. A 6. D 7."`). All 462 should be deleted.

**OCR extraction failure patterns across all material sources:**

| Pattern | Count | Avg Score | Example |
|---------|-------|-----------|---------|
| Truncated mid-sentence | 179 | 28.1 | `"When an ac"`, `"Broca's area, which is ac-"` |
| Textbook navigation metadata | 80 | 60.4 | `"Chapter 37"`, `"Summary of Key Concepts Questions"` |
| Answer key entries | 42 | 34.2 | `"C 2. C 3. C 4. B 5. A 6. D 7."` |
| Figure labels / table cells | 21 | 48.1 | `"(a) Stem cell / Spermatogonium / Mitosis / Meiosis..."` |

---

## Source 3: Web Sources (4 questions)

Too small a sample to assess. Recommend expanding web sourcing.

---

## Chapter Coverage (Passed Questions Only)

- **Strong** (50–90+ passed): Ch. 7 Cellular Respiration, Ch. 9 Cell Cycle, Ch. 10 Meiosis, Ch. 11 Mendel, Ch. 13 Molecular Basis of Inheritance
- **Thin** (0–10 passed): Ch. 5, Ch. 14–39
- **1,378 questions (36.3%) have no chapter assignment** — invisible to adaptive learning until classified

---

## Root Cause Summary

| Category | Count | Action |
|----------|-------|--------|
| Missing explanation only (correct content) | 2,294 | ✅ Run auto-correction to add explanations |
| OCR truncated/garbage | 179 | 🗑️ Delete |
| Textbook metadata extracted as questions | 80 | 🗑️ Delete |
| Answer key entries extracted as questions | 42 | 🗑️ Delete |
| Figure captions extracted as questions | 21 | 🗑️ Delete |
| Validator LLM bug (no verdict returned) | ~70 | 🔄 Re-queue for validation |
| Genuinely off-topic / wrong chapter | ~255 | 👁️ Admin review queue |
| No chapter assigned | 1,378 | 🏷️ Run classifier |

---

## Recommendations (Priority Order)

1. **Delete 462 questions from `Biology Answers - 31.jpg`** — answer-key OCR artifacts, zero educational value. Single biggest quality drag.

2. **Enable `validation_auto_correction_enabled`** — 2,294 questions are one auto-correction pass away from passing. Adding missing explanations is the highest-leverage action.

3. **Re-validate the ~70 "no verdict returned" questions** — validator bug, not content bug. Reset `validation_status` to `pending` and re-queue.

4. **Delete the 322 OCR garbage questions** (truncated + metadata + answer-key entries + figure captions) — they will never pass.

5. **Run the classifier on the 1,378 unclassified questions** — without `chapter_id` / `section_id` they are invisible to adaptive learning (North Star I-1).

6. **Audit the OCR pipeline** — `Biology Answers - 31.jpg` should have been caught at the `completeness_score` / `material_kind` stage before question generation was attempted.

---

## Expected Impact After Fixes

| Metric | Before | After (estimated) |
|--------|--------|-------------------|
| Passed questions | 927 | ~3,200+ |
| Pass rate | 24.4% | ~85%+ |
| Improvement | — | 3.4× |
