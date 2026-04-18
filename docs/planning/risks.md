# StudySmart Risk Assessment

## Overview

Risk assessment for StudySmart, an AI-powered adaptive study platform built with Elixir/Phoenix and Interactor platform services. This document identifies technical, operational, and product risks with mitigation strategies.

**Risk Rating Scale:**
- **Probability**: Low (< 20%) | Medium (20-60%) | High (> 60%)
- **Impact**: Low (minor inconvenience) | Medium (degraded functionality) | High (critical failure or blocker)

---

## Technical Risks

| ID | Risk | Probability | Impact | Mitigation Strategy | Owner | Status |
|----|------|-------------|--------|---------------------|-------|--------|
| T-1 | **Interactor platform availability/dependency** -- All AI agents, authentication, workflows, and credential management depend on Interactor. An outage or breaking API change would disable core StudySmart functionality. | Medium | High | Implement circuit breakers and graceful degradation (e.g., cached questions still available offline). Define SLA expectations with Interactor team. Add health checks and alerting for Interactor endpoints. Maintain a local fallback for authentication tokens during short outages. | Platform Lead | Open |
| T-2 | **Google Cloud Vision OCR accuracy on varied textbook formats** -- Handwritten notes, old/low-quality scans, math formulas, and non-Latin scripts may produce poor OCR results, leading to garbage-in questions. | High | High | Implement a confidence scoring layer on OCR output; reject pages below a threshold and prompt users to re-upload or manually correct. Build format-specific preprocessing pipelines (contrast enhancement, deskewing). For math formulas, evaluate supplementary models (e.g., Mathpix) as a secondary pass. Provide a user-facing "OCR review" step before question generation. | AI/ML Lead | Open |
| T-3 | **Multi-agent question validation pipeline reliability** -- If the Creator, Solver, and Validator agents frequently disagree, the pipeline stalls and question throughput drops. Edge cases (ambiguous source material, subjective topics) may cause high rejection rates. | Medium | Medium | Track disagreement rates per subject/topic and tune agent prompts accordingly. Implement a configurable disagreement threshold -- if agents disagree beyond N rounds, flag for human review rather than infinite retry. Log all agent reasoning for post-hoc prompt improvement. Set a maximum of 2 retry cycles before escalation. | AI/ML Lead | Open |
| T-4 | **Adaptive testing algorithm effectiveness** -- The spaced repetition and difficulty adaptation algorithm is untested with real students. It may not correlate with actual learning outcomes until validated with real usage data. | Medium | High | Start with a well-studied algorithm (SM-2 or FSRS) as the baseline rather than inventing from scratch. Instrument all study sessions for A/B testing. Plan a beta cohort to validate test readiness scores against actual exam results before public launch. Build the algorithm as a pluggable module so it can be swapped without system-wide changes. | Product Lead | Open |
| T-5 | **Real-time SSE streaming reliability for AI agent responses** -- Server-Sent Events may drop connections on mobile networks, behind corporate proxies, or during long-running agent responses, leading to incomplete answers or frozen UI. | Medium | Medium | Implement automatic reconnection with `Last-Event-ID` for resumability. Add client-side timeout detection with user-visible retry UI. Fall back to polling if SSE connection fails repeatedly. Use Phoenix PubSub to decouple agent execution from the SSE connection so work is never lost. | Backend Lead | Open |
| T-6 | **Local-to-S3 storage migration complexity** -- Initial development uses local file storage. Migrating to S3 for production introduces new failure modes (network latency, IAM permissions, multipart upload handling) and requires updating all file reference paths. | Low | Medium | Use an abstracted file storage behaviour (`StudySmart.Storage`) from day one with local and S3 adapters. Write integration tests against both adapters. Plan the migration as a dedicated sprint with a dual-write period to verify correctness before cutover. | Backend Lead | Open |
| T-7 | **Copyright risk with derivative questions** -- Generating questions derived from copyrighted textbook content may expose the platform to DMCA or publisher takedown requests, especially if questions closely mirror original text. | Medium | High | Ensure generated questions are transformative (test concepts, not reproduce text). Never store or display original textbook passages -- only derived questions. Add a content provenance field so questions can be traced and removed per-source if a takedown is received. Consult legal counsel on fair use boundaries before launch. Implement a DMCA takedown response process. | Legal / Product Lead | Open |
| T-8 | **Hobby contextualization quality** -- Wrapping study questions in hobby contexts (e.g., "If you're building a guitar, what wood has the highest tensile strength?") may produce forced, confusing, or irrelevant references that hurt rather than help comprehension. | Medium | Medium | Make hobby contextualization optional and off by default until quality is validated. Include a per-question "Was this helpful?" feedback button. A/B test contextualized vs. plain questions to measure impact on retention. Build a curated set of hobby-topic mappings rather than relying on free-form generation. | AI/ML Lead | Open |

| T-9 | **Role escalation: student gaining parent/teacher access** -- If `metadata.role` is not strictly validated on every request, a student could manipulate their role to access parent or teacher views, potentially viewing other students' data or administrative functions. | Low | High | Enforce role checks via `RequireRole` Phoenix Plug on every request -- never trust client-supplied role. Role changes require an Interactor API call with App JWT (not user-controllable). Audit log all role changes. Do not allow role self-modification from the UI. Validate `metadata.role` against the local `user_roles` table on each session creation. | Security Lead | Open |
| T-10 | **Guardian relationship abuse: unauthorized linking to student accounts** -- A malicious user could attempt to link themselves as a parent/teacher to students they have no relationship with, gaining access to student performance data. | Medium | High | Require student-side acceptance for all guardian links (pending → active flow). Rate-limit invitation attempts per user. Notify students and existing guardians when new link requests arrive. Allow students to revoke any guardian link at any time. For teacher links, consider requiring school-level verification (same `school_id`). Log all guardian relationship changes for audit. | Security Lead | Open |
| T-11 | **Data privacy: parent/teacher access to student data** -- Parents and teachers viewing student assessment data raises consent and age-appropriate access concerns. Under COPPA/FERPA, student data access by third parties requires proper consent mechanisms. | Medium | High | Implement explicit consent flow: students must actively accept guardian links. For students under 13, require parental consent during registration (COPPA). Define clear data visibility boundaries: parents see readiness scores and study progress but not individual question answers; teachers see aggregate class metrics with opt-in individual detail. Provide students with a privacy dashboard showing who can see their data. Document data sharing in privacy policy. Comply with FERPA requirements if used by educational institutions. | Legal / Security Lead | Open |

---

## Operational Risks

| ID | Risk | Probability | Impact | Mitigation Strategy | Owner | Status |
|----|------|-------------|--------|---------------------|-------|--------|
| O-1 | **AI token costs scaling with user growth** -- Each question generation uses the 3-agent pipeline (Creator + Solver + Validator), and adaptive hints/explanations consume tokens at study time. Costs could grow faster than revenue. | High | High | Pre-generate and cache question banks so repeated study sessions cost zero tokens. Batch question generation during off-peak hours for cost optimization. Set per-user daily token budgets. Track cost-per-question and cost-per-study-session as key metrics. Evaluate smaller/cheaper models for the Solver and Validator agents where full reasoning capability is not required. | Platform Lead | Open |
| O-2 | **OCR costs at scale** -- Google Cloud Vision charges ~$1.50/1K pages. A popular course with a 500-page textbook uploaded by 1,000 students would cost $750 if each upload is processed independently. | Medium | Medium | Deduplicate textbook uploads by content hash -- process each unique textbook once and share the question bank across all students using the same edition. Cache OCR results permanently. Implement upload quotas per user. Monitor per-textbook processing costs. | Backend Lead | Open |
| O-3 | **Question bank cold start** -- New courses have zero pre-generated questions. First users must wait for the full OCR + generation pipeline before they can study, creating a poor first experience. | High | Medium | Seed popular courses with pre-generated question banks before launch. Implement a "processing" state with estimated completion time so users know what to expect. Allow users to start studying with early questions while the rest of the textbook is still processing. Prioritize chapter-by-chapter generation over whole-book processing. | Product Lead | Open |
| O-4 | **Data privacy compliance (COPPA/FERPA)** -- Student data, study performance, and uploaded educational materials are sensitive. If users are under 13 (COPPA) or the platform is used by educational institutions (FERPA), strict compliance is required. | Medium | High | Restrict signup to users 13+ and enforce age verification at registration. Do not collect unnecessary PII. Encrypt student performance data at rest. Implement data retention policies with user-controlled deletion. If targeting institutional use, engage a FERPA compliance consultant before launch. Store all data in US regions. Document data flows for compliance audits. | Legal / Security Lead | Open |

---

## Product Risks

| ID | Risk | Probability | Impact | Mitigation Strategy | Owner | Status |
|----|------|-------------|--------|---------------------|-------|--------|
| P-1 | **User adoption** -- Students already have Quizlet, Anki, and ChatGPT. StudySmart must demonstrate clear value over existing tools to overcome switching costs and habit inertia. | High | High | Focus launch messaging on the unique value: "Upload your textbook, get a personalized test prep plan in minutes." Target a specific underserved niche first (e.g., nursing students, CPA exam prep) rather than all students. Offer a generous free tier. Build viral mechanics (share question banks with classmates). Gather testimonials from beta users showing grade improvements. | Product Lead | Open |
| P-2 | **Test readiness score accuracy** -- The "readiness score" is a core differentiator, but if it poorly predicts actual exam performance, students will lose trust and abandon the platform. | Medium | High | Calibrate the score against beta user exam results before marketing it as predictive. Display the score as a confidence range rather than a single number. Be transparent about methodology ("based on X questions across Y topics"). Continuously refine the model with opt-in exam result feedback. Avoid making guarantees about grades. | AI/ML Lead | Open |
| P-3 | **Mobile UX quality for card swipe interactions** -- The study card swipe interface is web-based (Phoenix LiveView), not native. Touch gestures, animations, and responsiveness may feel inferior to native apps, especially on older devices. | Medium | Medium | Use a proven JavaScript touch library (e.g., Hammer.js) integrated with LiveView hooks for gesture handling. Test on a matrix of real devices (not just emulators). Set a performance budget: card transitions must complete in < 100ms. Consider a Progressive Web App (PWA) approach for offline study and home screen installation. Gather early user feedback specifically on mobile UX. | Frontend Lead | Open |

---

## Risk Summary Matrix

```
                    Low Impact    Medium Impact    High Impact
                   +-----------+--------------+-------------+
  High Probability |           | O-1, O-3     | T-2, P-1    |
                   +-----------+--------------+-------------+
Medium Probability |           | T-3, T-5,    | T-1, T-4,   |
                   |           | T-8, O-2     | T-7, O-4,   |
                   |           |              | P-2, T-10,  |
                   |           |              | T-11         |
                   +-----------+--------------+-------------+
   Low Probability |           | T-6          | T-9          |
                   +-----------+--------------+-------------+
```

## Review Schedule

- **Weekly**: Review all High probability / High impact risks (T-2, P-1, O-1)
- **Bi-weekly**: Review all Medium/High risks (including T-10, T-11 guardian/privacy risks)
- **Monthly**: Full risk register review and update
- **Ad-hoc**: Any risk whose status changes to "Triggered"
