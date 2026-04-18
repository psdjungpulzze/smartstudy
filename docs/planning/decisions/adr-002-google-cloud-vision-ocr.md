# ADR-002: Use Google Cloud Vision for Textbook OCR

## Status

Accepted

## Date

2026-04-17

## Context

StudySmart's core workflow begins with a student uploading a textbook (PDF or image). The platform must extract text from these uploads with high accuracy so that the AI question generation pipeline receives clean input. Poor OCR quality cascades downstream: garbled text produces nonsensical questions, which erode user trust.

Textbook uploads present specific OCR challenges:

- **Mixed content**: Textbooks contain prose, headings, tables, diagrams with labels, footnotes, and sidebars -- often on the same page.
- **Math and scientific notation**: STEM textbooks include formulas, chemical equations, and symbols that many OCR engines handle poorly.
- **Variable scan quality**: Students may photograph pages with their phone (skewed, uneven lighting) or upload old, low-contrast scans.
- **Handwritten annotations**: Some uploads include handwritten margin notes that users may want included.

The OCR engine must achieve approximately 98% character-level accuracy on clean textbook pages to produce usable input for question generation. Lower accuracy requires expensive post-processing or manual correction, which defeats the "upload and go" value proposition.

## Decision

Use Google Cloud Vision API (specifically the `DOCUMENT_TEXT_DETECTION` feature) as the primary OCR engine for all textbook processing.

### Integration Design

```
Upload (PDF/Image)
    |
    v
Preprocessing (deskew, contrast, split PDF to pages)
    |
    v
Google Cloud Vision API (DOCUMENT_TEXT_DETECTION)
    |
    v
Confidence scoring (reject pages below 90% confidence)
    |
    v
Structured text output (paragraphs, sections, page numbers)
    |
    v
Question generation pipeline
```

### Cost Model

- **Pricing**: $1.50 per 1,000 pages (as of 2026-04)
- **Typical textbook**: 300-600 pages
- **Cost per textbook**: $0.45 - $0.90
- **With deduplication** (same textbook uploaded by multiple students): Cost is incurred once and shared across all users of that textbook edition

At projected scale (10,000 unique textbooks in year one), total OCR cost is approximately $4,500-$9,000/year -- negligible relative to AI agent token costs.

## Consequences

### Positive

- **High accuracy**: Google Cloud Vision achieves 97-99% accuracy on printed text, including complex layouts with tables and multi-column formatting.
- **Layout understanding**: The `DOCUMENT_TEXT_DETECTION` mode returns paragraph and block boundaries, preserving document structure that aids question generation.
- **Language support**: Supports 100+ languages out of the box, enabling future internationalization without changing OCR providers.
- **Managed service**: No infrastructure to maintain, no model updates to deploy, automatic scaling.
- **Handwriting support**: Provides reasonable handwriting recognition for margin notes (though accuracy drops to ~85-90%).
- **Credential management**: API key stored in Interactor Credential Store (per ADR-001), not in application config.

### Negative

- **External dependency**: Adds a Google Cloud dependency alongside the Interactor platform dependency. Mitigated by the fact that OCR is a batch process (not real-time), so temporary outages only delay processing.
- **Cost at scale**: While currently negligible, costs scale linearly with unique textbook uploads. Mitigated by content-hash deduplication.
- **Math formula limitations**: While better than alternatives, Google Cloud Vision still struggles with complex LaTeX-style math notation. A supplementary pass with a math-specific OCR model may be needed for STEM-heavy textbooks.
- **Data residency**: Textbook pages are sent to Google's servers for processing. Must ensure this is disclosed in privacy policy and complies with data handling requirements (see risk O-4).
- **No on-premise option**: Cannot run locally for development or in air-gapped environments. Mitigated by using mock OCR responses in test/dev environments.

## Alternatives Considered

### 1. Tesseract OCR (Open Source)

- **Pros**: Free, self-hosted, no external dependency, large community, supports 100+ languages.
- **Cons**: Accuracy ranges from 85-95% depending on input quality -- significantly below the 98% threshold needed for reliable question generation. Struggles with complex layouts (multi-column, tables, sidebars). Requires significant preprocessing to achieve acceptable results. Math/formula recognition is poor. Must self-host and manage infrastructure.
- **Rejected because**: The 5-13% accuracy gap on real-world textbook pages would produce noticeably garbled questions, undermining the core product value. The preprocessing and tuning effort to close this gap would exceed the cost savings from being free.

### 2. PaddleOCR (Open Source)

- **Pros**: Free, strong performance on structured documents, good table recognition, active development.
- **Cons**: Accuracy on English text is competitive with Tesseract but still below Google Cloud Vision. Documentation is primarily in Chinese. Community support for edge cases is limited. Requires GPU infrastructure for acceptable throughput. Self-hosted operational burden.
- **Rejected because**: While PaddleOCR's table recognition is impressive, overall accuracy on varied English textbook formats does not meet the 98% threshold. Operational complexity of self-hosting a GPU-dependent OCR service is not justified at StudySmart's current scale.

### 3. AWS Textract

- **Pros**: High accuracy (comparable to Google Cloud Vision), excellent table extraction, form understanding, AWS ecosystem integration.
- **Cons**: More expensive than Google Cloud Vision (~$1.50/page for tables vs. $1.50/1000 pages for Vision). Pricing model is complex (different rates for different features). Requires AWS account and IAM setup.
- **Rejected because**: Cost is 100-1000x higher than Google Cloud Vision for equivalent functionality. Textract's strength is form/table extraction, which is less critical for textbook prose. If table extraction becomes a priority, Textract could be added as a supplementary service for table-heavy pages.

### 4. Azure AI Document Intelligence (formerly Form Recognizer)

- **Pros**: High accuracy, good layout analysis, prebuilt models for common document types.
- **Cons**: Pricing comparable to AWS Textract for full document analysis. Adds a Microsoft Azure dependency. Prebuilt models are optimized for business documents (invoices, receipts), not textbooks.
- **Rejected because**: No accuracy advantage over Google Cloud Vision for textbook content, and the prebuilt models are not tuned for educational materials. Adding an Azure dependency alongside Google Cloud and Interactor increases operational complexity without clear benefit.

### 5. Mathpix (Specialized Math OCR)

- **Pros**: Best-in-class for math formulas, LaTeX output, diagram recognition.
- **Cons**: Expensive ($0.004/page, ~$4/1000 pages). Specialized for math -- not a general-purpose textbook OCR solution. Would need to be combined with another engine for prose.
- **Considered as supplement**: Mathpix may be added as a secondary pass specifically for STEM textbooks where math formula accuracy is critical. This would be a future enhancement, not part of the initial architecture.
