# Community-Driven Course & Test Validation

**Status:** Draft — Not yet prioritized  
**Author:** Peter Jung  
**Created:** 2026-04-23

---

## Problem

FunSheep is growing fast. Users create courses and tests at a volume that manual review cannot keep up with. Without a validation layer, low-quality, outdated, or wrong content stays visible and erodes trust. We need a scalable system where the community itself surfaces quality content and buries bad content — requiring minimal intervention from the team.

---

## Industry Research Synthesis

Before designing anything, we studied how major platforms solved this at scale.

### Stack Overflow — Reputation & Graduated Trust
- Users earn reputation through upvotes on their answers and questions
- Reputation unlocks capabilities: commenting (50), voting (125), closing/deleting bad content (2,000+)
- Suspicious voting patterns are automatically detected and reversed — all votes from a gaming account are nullified
- **Key lesson:** Trust should be earned, not given. Gate moderation power behind demonstrated quality.

### Reddit — Velocity-Weighted Voting
- Early votes (first few hours) matter far more than late ones — the algorithm amplifies velocity, not just volume
- Vote fuzzing: displayed scores are slightly obscured to confuse bots while preserving the real trend
- Downvotes reduce visibility; a high downvote ratio suppresses content regardless of raw upvote count
- **Key lesson:** Engagement speed is a quality signal. New content needs an exposure window to get that first-hour boost.

### Duolingo — Crowdsourced Error Reporting
- 200,000+ user error reports daily on course content
- Report Quality Estimation Tool prioritizes fixes using: reporter credibility + duplicate report count + deviation from known-good answers
- **Key lesson:** Aggregate signals are more reliable than individual reports. Many users flagging the same question is a strong quality signal.

### Khan Academy — Outcome-Based Quality
- Primary metric is "Skills to Proficient" — not views, not likes
- Courses are measured by whether students actually master the content, not just attempt it
- **Key lesson:** Completion and mastery rate is the highest-signal quality metric for educational content.

### Wikipedia — Multi-Tier Community Moderation
- Peer review (community requests feedback), specialist review, automated vandalism reversal
- Moderators are volunteers who have demonstrated judgment — they earn the role progressively
- **Key lesson:** Community moderation works when you define escalation tiers and give high-trust users real tools.

### Coursera/Udemy — Passive Quality Signals
- Track 30-day trends in learner feedback, not just aggregate ratings
- Content Quality Dashboard flags outdated content, poor audio, AI-generated filler
- Flagged content prompts creators to act — doesn't auto-remove
- **Key lesson:** Creators improve content when shown data. Notification > auto-removal as the first response.

### Cold Start — Solving New Content Invisibility
- New content has no votes, no engagement — recommendation systems bury it by default
- Solutions used across platforms:
  - Reserve 15–20% of recommendation slots for new content (quota system)
  - "New" label in feeds for first 48–72 hours
  - Content-based recommendations using topic/difficulty metadata before interaction data exists
- **Key lesson:** Without deliberate cold-start design, only popular content stays popular. New quality content never gets seen.

---

## Proposed System

### Core Design Principles

1. **Community signals, not admin decisions** — quality is determined by aggregate user behavior, not manual review
2. **Outcome quality over engagement quantity** — completing a test ranks higher than clicking it
3. **Gradual trust escalation** — users who have demonstrated good judgment get more moderation power
4. **Transparent demotion** — creators can see why their content is ranked lower and fix it
5. **Fail-safe cold start** — every new course/test gets a minimum visibility window before signals accumulate

---

## Scoring System

Every course and every test (and individual questions within tests) carries a **Quality Score**.

### Quality Score Formula

```
Quality Score = Base Engagement Score + Completion Bonus + Like Score + Creator Trust Multiplier

Base Engagement Score:
  = (Questions answered by users × 1.0)
  + (Unique users who attempted × 0.5)

Completion Bonus:
  = If test completed end-to-end: +5 points per completion
  (Rewards full engagement, not just cherry-picking questions)

Like Score:
  = (Likes × 2.0) - (Dislikes × 1.0)
  (Dislikes carry half the weight of likes — we don't want a small vocal minority to bury content)

Creator Trust Multiplier:
  = 1.0 (new user, no history)
  → 1.1 (creator has ≥3 courses with Quality Score > 50)
  → 1.25 (verified educator or ≥5 highly-rated courses)
  Applied as: Score × Multiplier
```

### Velocity Boost (Cold Start)

New content (< 72 hours old) receives a temporary ranking boost to ensure it appears in feeds and gets initial exposure:

```
Velocity Boost = base score × 1.5 for first 24h
               = base score × 1.25 for hours 24–48
               = base score × 1.1 for hours 48–72
               = no boost after 72h (pure merit-based from here)
```

---

## Like & Feedback Placement Strategy

Asking for feedback at the wrong moment is ignored or annoying. Based on psychology research on optimal prompt timing:

### Where to Show Like/Dislike Prompts

| Trigger | UI Placement | What We Ask |
|---|---|---|
| After answering a question correctly | Subtle thumb-up below the answer | "Was this question clear?" |
| After answering a question incorrectly and reviewing the explanation | After the explanation card | "Was this explanation helpful?" |
| After completing a full test | End-of-test summary screen | "Rate this test (👍 / 👎)" |
| After reaching 50% progress through a course | Floating prompt on sidebar | "How is this course so far?" |
| After mastering a topic (readiness hits 100%) | Celebration modal | "Did this course help you master this topic?" |

**Do NOT** ask for feedback:
- Immediately on course entry (user hasn't seen anything yet)
- Repeatedly in the same session
- Mid-question (interrupts focus)

### Feedback Aggregation

Individual question-level feedback is aggregated:
- Questions with < 60% "clear" rating get flagged to the course creator
- Questions with < 40% "helpful explanation" rating get flagged AND added to the admin review queue
- These signals are shown on the creator's dashboard — they are not auto-removed

---

## Content Ranking & Visibility Rules

### Ranking Tiers

Content is ranked in search results and course discovery using Quality Score + recency:

```
Ranking Score = Quality Score × Recency Factor

Recency Factor:
  = 1.0 (< 7 days old — new content protected)
  = 0.95^(weeks_since_creation) (gradual decay for old content with no new engagement)
```

This means a course created 3 months ago with no recent engagement slowly loses rank, while recently active courses stay visible.

### Visibility States

| State | Condition | User-Visible Effect |
|---|---|---|
| **Boosted** | New (< 72h) or Quality Score > 100 | Appears in "New & Popular" sections |
| **Normal** | Quality Score 0–100, some engagement | Standard search/browse ranking |
| **Reduced** | Quality Score < 0 AND > 20 total attempts | Ranked lower in search; not shown in recommendations |
| **Flagged** | Quality Score < -10 OR ≥ 5 community reports | Hidden from recommendations; creator notified |
| **Pending Review** | Flagged + no creator response in 14 days | Admin queue for manual review |
| **Delisted** | Admin action OR creator removes | Not visible; creator can re-submit |

### The Inactivity Rule

Courses and tests that receive **zero attempts for 90 days** are automatically moved to a "Dormant" state:
- Not shown in search or recommendations
- Creator is notified: "Your course [X] has had no activity for 90 days and has been hidden. Update or re-submit it to restore visibility."
- Creator can update content and reactivate — no penalty, just incentive to keep content fresh

---

## Reporting & Flagging

Any user can flag a question or course for:
- Incorrect answer or explanation
- Outdated content
- Duplicate of another course
- Inappropriate content

### Flag Weighting
Flags are not equal — they are weighted by reporter credibility:

```
Effective Flag Weight = 1.0 (new user)
                      = 1.5 (user with ≥ 10 completed tests on the platform)
                      = 2.0 (user with "Trusted Reviewer" reputation tier)
```

When a course accumulates **Effective Flag Weight ≥ 5**:
- Course creator is notified with the specific reason
- Creator has 14 days to respond/fix
- If no action: enters Pending Review state

### Preventing Abuse of Flagging
- A user who flags content that is later reviewed and found valid by admins: their credibility increases
- A user who flags content that is reviewed and found fine: their credibility decreases
- Users who consistently bad-flag lose their ability to flag (temporary, escalating lockouts: 7 days → 30 days → permanent)

---

## Reputation & Trust System

Users who contribute quality content and helpful feedback earn reputation, which unlocks moderation capabilities.

### Reputation Earning

| Action | Reputation Gained |
|---|---|
| Complete a full test | +1 |
| Your course/test gets a Like | +5 |
| Your flagged content is confirmed as a valid issue by admin | +10 |
| Another user's course gets high ratings after you rated it | +2 (accuracy bonus) |

### Reputation Costs

| Action | Reputation Cost |
|---|---|
| Your course/test gets a Dislike | -2 |
| Your flag is reviewed and dismissed | -1 |
| Your account flagged for voting manipulation | -50 (immediate, plus lockout) |

### Trust Tiers & Unlocked Capabilities

| Tier | Reputation Required | Unlocked Capability |
|---|---|---|
| Learner | 0 | Browse, take tests, submit feedback |
| Contributor | 50 | Can Like/Dislike courses and questions |
| Reviewer | 200 | Can flag content; flag weight = 1.5 |
| Trusted Reviewer | 500 | Flag weight = 2.0; can see aggregate quality data |
| Community Moderator | 1,000 | Can vote to delist content (5 votes needed) |

---

## Creator Dashboard

Creators need visibility into how their content is performing so they can improve it — not just get surprised by demotion.

### What Creators See

- Quality Score for each course and test
- Attempt count, completion rate, Like/Dislike ratio
- Individual question breakdown: clarity rating, helpfulness rating
- Flags received: how many, what reason, from what trust tier
- Ranking position in their subject area
- Specific improvement suggestions (auto-generated):
  - "3 questions have < 40% clarity rating — consider rewriting them"
  - "Your completion rate is 22% (average is 61%) — consider shortening this test"

### Notification Triggers

Creators receive notifications (in-app, not email-spam) when:
- Quality Score drops below 0
- A flag is submitted on their content
- Their content enters "Flagged" state
- A question receives repeated incorrect-answer flags
- Content is approaching Dormant status (notified at 60 days of inactivity)

---

## Anti-Gaming Measures

### Vote Manipulation Detection

- Track voting patterns per user session and IP range
- Detect: same user voting on own content (alt accounts), voting bursts from the same IP
- If manipulation detected: all votes from that session/account nullified silently; account reputation penalized
- Repeat offenders: escalating ban from voting (7 days → 30 days → permanent)

### Like Throttling

- A single user can Like a course only once
- A single user can Like individual questions only once per question
- Likes from accounts < 24 hours old carry zero weight
- Likes from accounts that have never taken a test carry zero weight (must have engagement history)

### Score Display Fuzzing

- Display the rounded Quality Score to creators (e.g., "Score: ~85") — not exact
- Prevents creators from gaming the exact threshold to avoid demotion

---

## Implementation Phases

### Phase 1 — Foundation (Core Scoring)
- Question attempt tracking (already partially built)
- Test completion tracking with bonus
- Like button on courses and tests
- Quality Score calculation (backend, not yet surfaced to users)
- Creator dashboard showing basic metrics (attempts, completions, likes)

### Phase 2 — Ranking & Discovery
- Search and browse results ordered by Quality Score + recency
- Cold start velocity boost for new content
- "New & Trending" section on discovery pages
- Dormant content auto-hiding after 90 days inactivity

### Phase 3 — Feedback & Flagging
- Strategically placed Like/Dislike prompts (per placement rules above)
- Per-question clarity and explanation ratings
- Community flagging system with weighted reporter credibility
- Creator notifications when content is flagged

### Phase 4 — Reputation & Moderation
- User reputation system
- Trust tiers and unlocked capabilities
- Community delist voting for Trusted Reviewers and Moderators
- Anti-gaming detection (vote throttling, duplicate account detection)

### Phase 5 — Creator Tools
- Full creator dashboard with improvement suggestions
- Granular per-question quality breakdown
- Creator response workflow for flagged content
- Re-submission flow for dormant/delisted content

---

## Open Questions

Before implementation begins, these need answers:

1. **Do courses created by teachers get a trust bonus from the start?** (Verified educators)
2. **What is the Like UI?** Thumb up/down only? Star rating (1–5)? Both?
3. **How do we handle courses with very few students?** (A course for a niche AP class may only have 10 students — it should not be penalized vs. a course taken by 500 students)
4. **Should the demotion/dormant rules apply to teacher-created courses?** (Teachers may be hurt by seeing their professionally-made content get flagged by a student who just got a question wrong)
5. **How do we notify creators about their content performance** without becoming annoying notification noise?
6. **What happens to a course's score when the underlying textbook is replaced?** (Questions may now be wrong — existing likes become misleading)

---

## Related Documents

- `docs/PRODUCT_NORTH_STAR.md` — invariants that community scoring must not violate
- `docs/ROADMAP.md` — Community Contribution Rewards section (related: test schedule confirmation workflow)
- `docs/discovery/requirements.md` — formal requirements

