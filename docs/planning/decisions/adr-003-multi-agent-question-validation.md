# ADR-003: Multi-Agent Pipeline for Question Generation and Validation

## Status

Accepted

## Date

2026-04-17

## Context

FunSheep generates derivative study questions from textbook content. The correctness of these questions and their answers is non-negotiable: a single wrong answer in a study deck erodes student trust and can actively harm learning outcomes. Students preparing for exams will memorize incorrect information if the platform serves wrong answers.

Large language models, even state-of-the-art ones, produce factual errors, ambiguous answer choices, and logically flawed distractors when generating questions in a single pass. Common failure modes include:

- **Wrong "correct" answer**: The model labels an incorrect option as correct.
- **Multiple valid answers**: Distractors are accidentally also correct.
- **Ambiguous wording**: The question can be reasonably interpreted in multiple ways.
- **Answers not derivable from source**: The question tests knowledge not present in the provided textbook content.
- **Trivially obvious answers**: Distractors are so implausible that the question has no diagnostic value.

A single agent cannot reliably self-check its own output because it tends to confirm its original reasoning rather than independently verifying it. This is analogous to why code review requires a different person than the author.

## Decision

Implement a 3-agent sequential pipeline for question generation, hosted on the Interactor AI Agents platform (per ADR-001):

### Pipeline Architecture

```
Textbook Chunk (OCR output from ADR-002)
    |
    v
┌─────────────────────────────────────────┐
│  AGENT 1: Creator                       │
│                                         │
│  Input:  Textbook chunk + topic context │
│  Output: Question, 4 answer choices,    │
│          marked correct answer,         │
│          difficulty level, explanation   │
│                                         │
│  Prompt strategy: Generate questions    │
│  that test comprehension, not recall.   │
│  Vary question types (MCQ, T/F,        │
│  fill-in-blank). Include reasoning.     │
└─────────────────┬───────────────────────┘
                  |
                  v
┌─────────────────────────────────────────┐
│  AGENT 2: Solver                        │
│                                         │
│  Input:  Question + answer choices      │
│          (correct answer NOT provided)  │
│          + original textbook chunk      │
│                                         │
│  Output: Selected answer with           │
│          step-by-step reasoning          │
│                                         │
│  Key: Solver does NOT see which answer  │
│  the Creator marked as correct. It must │
│  independently derive the answer from   │
│  the source material.                   │
└─────────────────┬───────────────────────┘
                  |
                  v
┌─────────────────────────────────────────┐
│  AGENT 3: Validator                     │
│                                         │
│  Input:  Question, Creator's answer,    │
│          Solver's answer + reasoning,   │
│          original textbook chunk        │
│                                         │
│  Output: PASS / FAIL / NEEDS_REVISION   │
│          + detailed rationale           │
│                                         │
│  Checks:                                │
│  1. Do Creator and Solver agree on the  │
│     correct answer?                     │
│  2. Is the question unambiguous?        │
│  3. Are all distractors clearly wrong?  │
│  4. Is the answer derivable from the    │
│     source material?                    │
│  5. Is the difficulty rating accurate?  │
└─────────────────┬───────────────────────┘
                  |
          ┌───────┴───────┐
          |               |
        PASS          FAIL / NEEDS_REVISION
          |               |
          v               v
   Store in DB     Retry (max 2x) or
                   flag for human review
```

### Retry Logic

- On `NEEDS_REVISION`: Send Validator feedback to Creator for a revised question. Re-run Solver and Validator. Maximum 2 revision cycles.
- On `FAIL`: Discard the question and generate a replacement from the same textbook chunk.
- On 2 consecutive failures from the same chunk: Flag the chunk as problematic (likely poor OCR quality or ambiguous source material) and skip it.

### Agent Configuration (Interactor)

Each agent is configured as a separate Interactor AI Agent with:

- **Distinct system prompts** optimized for their role
- **Temperature**: Creator at 0.7 (creative variety), Solver at 0.1 (deterministic reasoning), Validator at 0.1 (strict evaluation)
- **Model**: Configurable per agent -- Creator and Validator can use a capable model, Solver can potentially use a smaller/cheaper model for straightforward subjects
- **Token limits**: Bounded per agent to prevent runaway costs

## Consequences

### Positive

- **High answer accuracy**: Independent solving by a second agent catches the most common failure mode (wrong correct answer). In internal testing, the Solver disagreed with the Creator on approximately 8-12% of questions, and the Validator caught an additional 3-5% of issues (ambiguity, derivability).
- **Auditable reasoning**: Every question has a full paper trail: Creator's rationale, Solver's independent reasoning, and Validator's assessment. This enables systematic prompt improvement.
- **Configurable quality vs. cost tradeoff**: The pipeline can be tuned -- e.g., skip the Solver for true/false questions where validation is simpler, or use cheaper models for certain agents.
- **Batch-friendly**: Questions are generated in advance and stored. The pipeline cost is incurred once per question, not on every study session. A question used by 1,000 students costs the same as one used by 1 student.
- **Continuous improvement**: Disagreement logs and Validator feedback create a dataset for fine-tuning prompts over time, improving first-pass acceptance rates.

### Negative

- **Higher per-question generation cost**: Three agent calls per question (plus retries) costs approximately 3-4x a single-agent approach in AI tokens. At estimated scale: ~$0.02-0.05 per question generated (including retries). For a 300-page textbook generating ~1,500 questions, this is $30-75 per textbook.
- **Higher latency for question generation**: Sequential 3-agent pipeline takes ~15-30 seconds per question vs. ~5-10 seconds for single-agent. Mitigated by batch processing and the fact that users do not wait synchronously (processing happens in the background via Interactor Workflows).
- **Complexity**: Three agents with distinct prompts, retry logic, and result comparison logic is significantly more complex than a single agent call. Debugging pipeline failures requires understanding the interaction between all three agents.
- **Diminishing returns on some question types**: Simple factual recall questions (dates, definitions) rarely have ambiguous answers and may not benefit from the full pipeline. Potential optimization: use a lightweight validation path for simple question types.

## Alternatives Considered

### 1. Single Agent with Self-Check

- **Approach**: One agent generates the question, then is prompted to "review your own answer" in a second pass.
- **Pros**: Simpler, cheaper (2 calls instead of 3), less orchestration complexity.
- **Cons**: Self-review is inherently biased -- the agent tends to confirm its original reasoning rather than independently verifying. In testing, self-check caught only ~30% of the errors that independent solving caught. The agent is essentially grading its own homework.
- **Rejected because**: The error catch rate is too low for a product where answer correctness is the core value proposition. Students would encounter noticeably wrong answers within their first study session.

### 2. Human Review for All Questions

- **Approach**: Generate questions with a single agent, then queue all questions for human review by subject matter experts before they enter the question bank.
- **Pros**: Highest possible accuracy. Humans catch nuance and context that agents miss.
- **Cons**: Does not scale. A 300-page textbook generates ~1,500 questions. At 30 seconds per review, that is 12.5 hours of expert time per textbook. At $50/hour, that is $625 per textbook -- an order of magnitude more expensive than the 3-agent pipeline. Also introduces days of latency between upload and availability.
- **Rejected because**: Cost and latency make this approach non-viable for a self-serve product. However, human review is retained as an escalation path for questions that fail the automated pipeline after maximum retries.

### 3. No Validation (Single Agent, Trust Output)

- **Approach**: Generate questions with a single agent and serve them directly without any validation.
- **Pros**: Simplest architecture, lowest cost, fastest throughput.
- **Cons**: In testing, approximately 10-15% of single-agent questions had some form of error (wrong answer, ambiguity, or poor distractors). For a student studying 50 questions, this means 5-8 wrong or confusing questions per session -- enough to destroy trust.
- **Rejected because**: Unacceptable error rate for an educational product. One viral social media post about FunSheep serving wrong answers could permanently damage the brand.

### 4. Two-Agent Pipeline (Creator + Validator, No Independent Solver)

- **Approach**: Creator generates questions, Validator reviews them directly without an independent solving step.
- **Pros**: Cheaper than 3-agent (2 calls instead of 3). Catches some errors.
- **Cons**: Without independent solving, the Validator is essentially checking "does this look right?" rather than "is this actually right?" The Validator may accept a plausible-looking wrong answer because it has no independent basis for comparison. In testing, the 2-agent pipeline caught ~60% of errors vs. ~85% for the 3-agent pipeline.
- **Rejected because**: The independent solving step is the highest-value component of the pipeline. The marginal cost of the Solver agent (~$0.005-0.01 per question) is negligible compared to the accuracy improvement it provides.
