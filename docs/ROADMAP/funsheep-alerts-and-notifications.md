# FunSheep Alerts & Notifications

**Status:** Planning  
**Date:** 2026-04-24  
**Scope:** Engagement › Habit Formation + Multi-Role Notification System

---

## Overview

FunSheep's adaptive learning loop only produces outcomes when students actually show up. This document defines the notification architecture that turns occasional visits into daily study habits — modeled on what the best e-learning platforms (Duolingo, Anki, Khan Academy) have proven to work.

**Core philosophy:** Notifications are scaffolding, not the building. The goal is to use external triggers to build internal habits, so students eventually open FunSheep without needing a prompt. Notifications should become less necessary over time — not more aggressive.

### Three Psychological Levers (Evidence-Based)

| Lever | Mechanism | FunSheep Application |
|-------|-----------|---------------------|
| **Loss Aversion** | Losing a streak hurts 2× more than gaining it feels good (Kahneman) | Streak-at-risk alerts; readiness score drops |
| **Variable Rewards** | Unpredictable rewards trigger stronger dopamine response than fixed ones (Skinner) | Sometimes XP, sometimes badges, sometimes skill unlock — unpredictable mix |
| **Social Proof** | Knowing peers are ahead triggers action (Cialdini) | Friend milestones, class leaderboard nudges |

### Channels

| Channel | Open Rate | Best For | Limitation |
|---------|-----------|----------|-----------|
| **Push (mobile/web)** | ~28% CTR | Students: streak at risk, quick drills | Requires opt-in; easy to disable |
| **In-app alerts** | ~100% (when active) | All roles: contextual session nudges | Only reaches active users |
| **Email** | ~25% open, 2.6% CTR | Parents/teachers: weekly digest, reports | Slow; ineffective for habit formation |
| **SMS** | ~98% open | Parents: test-day critical alerts only | Regulatory burden; opt-in only |

---

## User-Role Notification Maps

### Student Notifications

Students are the primary habit-formation target. All notifications are timed to high-probability engagement windows (8–9am, 6–8pm local time) and suppressed during school hours (9am–3pm on school days) and quiet hours (9pm–8am).

#### Tier 1 — Critical (Always Send, Real-Time)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Streak At Risk** | 18+ hours since last practice, streak > 0 | Push | "Your 7-day streak ends in 4 hours! Answer 1 question to keep it alive." |
| **Weak Skill Confirmed** | ≥2 wrong answers on the same skill tag in a session | In-app | "You've missed Cell Division twice. Let's drill that now before it grows." |
| **Test In 3 Days** | test_schedules.scheduled_at = T−3 | Push + In-app | "AP Bio in 3 days. Your readiness: 68%. Weak area: Photosynthesis. Start now?" |
| **Test In 1 Day** | test_schedules.scheduled_at = T−1 | Push | "Test tomorrow. Readiness: 72%. 15 targeted questions = ~20 min. Let's go." |
| **Invite Received** | teacher or parent sends invite | Push + In-app | "Mr. Chen added you to AP Biology. Tap to join your class." |
| **Share Received** | peer shares a course or question set | Push + In-app | "Marcus shared 'Chapter 5 Drills' with you. Check it out." |

#### Tier 2 — Engagement (Contextual, Throttled to 3×/week)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Readiness Drop** | Overall readiness drops ≥5% since last session | Push | "Your Biology readiness dipped to 65% (was 72%). Top weak skill: Meiosis." |
| **Readiness Milestone** | Hits 25%, 50%, 75%, 90% | In-app + Push | "You hit 75% readiness! 3 more skills to master before you're exam-ready." |
| **Skill Mastered** | N correct in a row at ≥medium difficulty (per I-9 invariant) | In-app | "You mastered Cellular Respiration! 🔬 Next up: Photosynthesis." |
| **Study Path Complete** | All in-scope skills reach mastery | Push + Email | "You completed the study path. Mastered 12/15 skills. Exam ready!" |
| **Inactivity (48h)** | 48 hours without any practice | Push | "Haven't studied in 2 days. Your Algebra readiness: 65%. Miss your streak?" |
| **Friend Milestone** | A connected friend reaches readiness milestone or mastery | Push | "Marcus just mastered Fractions — he's at 80% readiness. You're at 65%." |
| **Friend Joined** | A friend creates an account or joins same class | Push | "Alex just joined FunSheep! They're already at 30% readiness on Bio." |

#### Tier 3 — Habit Formation (Soft, Opt-In, 1×/day max)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Daily Habit Nudge** | User-set time (configurable, default 6pm) | Push | "Quick 2-min question? Your streak: 5 days. Don't break it now." |
| **Spaced Repetition Prompt** | Skill approaching forgetting window (Ebbinghaus curve) | Push | "Time to review: you nailed Osmosis 4 days ago. Keep it fresh." |
| **Encouragement After Struggle** | 3+ consecutive wrong answers in session | In-app | "That one's tough. You're building real understanding — stay with it." |
| **Hobby-Personalized Drill** | Weak skill + student has hobby profile set | Push | "Your Biology question uses K-pop — ready to try it your way?" |

#### Student Notification Settings (User-Controlled)

- **Notification frequency**: Off / Light (1–2/week) / Standard (3–5/week) / All
- **Quiet hours**: Configurable (default 9pm–8am)
- **Streak alerts**: Toggle (default on)
- **Friend activity**: Toggle (default on)
- **Daily habit nudge**: Toggle + custom time
- **School hours suppression**: Toggle (default on, 9am–3pm weekdays)

---

### Parent Notifications

Parents are the accountability layer for K-12 students. They need insight into progress, not daily nudges. Over-notifying parents creates noise and loses trust.

#### Tier 1 — Critical (Always Send)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Upcoming Test (3 days)** | test_schedules.scheduled_at = T−3 | Push + Email | "Maria's AP Bio test is in 3 days. Current readiness: 65%. Weak area: Cell Division." |
| **Upcoming Test (1 day)** | test_schedules.scheduled_at = T−1 | Push + SMS (opt-in) | "Maria's test is tomorrow. Readiness: 70%. She's studied 4h this week." |
| **Major Readiness Drop** | Readiness drops ≥10% since previous session | Push | "Maria's readiness dropped to 58% (from 70%). Weak area: Photosynthesis. Check dashboard." |
| **Invite Received** | Teacher sends parent invite | Push + Email | "Mr. Chen (Lincoln HS) invited you to monitor Maria's AP Biology progress." |
| **Share Received** | Teacher or student shares content with parent | Push + In-app | "Mr. Chen shared the class study plan for Chapter 6 with you." |

#### Tier 2 — Weekly Digest (Low Frequency, High Value)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Weekly Progress Report** | Sunday 6pm (configurable) | Email | Structured summary: study hours, skills mastered, weak areas, readiness trend, recommended action |
| **Streak Achievement** | Child hits 7-day, 30-day, 100-day streak | Push + Email | "Maria hit a 30-day study streak! She's studied every day for a month." |
| **Readiness Milestone** | Child hits 25%, 50%, 75%, 90% | Email | "Maria reached 75% exam readiness for AP Biology. Keep up the momentum." |
| **Skill Mastery** | Child masters a skill (especially a previously weak one) | Email (weekly digest) | Included in weekly digest, not a standalone push |

#### Tier 3 — Child Progress (On-Demand Dashboard)

Parents view real-time data in their dashboard at any time. Push/email are reserved for actionable events — not every small update.

| Dashboard Section | What It Shows |
|------------------|--------------|
| **Readiness Score** | Current readiness %, trend graph (last 7 days), per-skill breakdown |
| **Weak Skills** | List of confirmed weak skills with status (drilling / improving / mastered) |
| **Study Activity** | Days active this week, time spent, sessions completed |
| **Streak** | Current streak count, last active date |
| **Upcoming Tests** | All scheduled tests with readiness score at time of test |
| **Compared to Class** | Optional: anonymous class average readiness (opt-in) |

#### Parent Notification Settings

- **Weekly digest**: On/Off + day + time
- **Test alerts**: On/Off (default on)
- **Critical readiness drops**: On/Off (default on, threshold configurable: 5%/10%/15%)
- **SMS alerts**: Off (opt-in, test-day only)
- **Streak milestones**: Toggle
- **School-hours suppression**: N/A (parents are not restricted)

---

### Teacher Notifications

Teachers operate in classrooms and meetings. They need aggregated class-level insights, not a constant stream of individual student pings. Push notifications are off by default — teachers use the dashboard as their primary notification surface.

#### Tier 1 — Critical (Dashboard + Email, No Push by Default)

| Notification | Trigger | Channel | Example Copy |
|-------------|---------|---------|-------------|
| **Upcoming Test (3 days)** | test_schedules.scheduled_at = T−3 | Dashboard badge + Email | "AP Bio Test in 3 days. Class readiness: 64% avg. 8/24 students below 50%." |
| **Upcoming Test (1 day)** | test_schedules.scheduled_at = T−1 | Dashboard badge | "Tomorrow: AP Bio Test. 6 students are below 55% readiness. See who." |
| **Student At-Risk** | Individual student readiness drops below 50% with test in ≤7 days | Dashboard alert | "Maria García — readiness: 42%, test in 6 days. Consider direct outreach." |
| **Invite Accepted** | Student or parent accepts teacher invite | In-app + Email | "Alex Kim accepted your invite to AP Biology." |
| **Share Received** | Student or parent shares content with teacher | In-app | "Maria uploaded new study materials for Chapter 4." |

#### Tier 2 — Weekly Insights (Email)

| Notification | Trigger | Channel | Content |
|-------------|---------|---------|---------|
| **Class Progress Digest** | Monday 8am (configurable) | Email | Class avg readiness trend, top 3 weak skills across class, at-risk students (readiness < 55%), most improved students |
| **Mastery Milestone (Class)** | ≥50% of class masters a skill | Email (digest) | "17/24 students mastered Mitosis this week." |
| **Student Joined** | New student accepts enrollment | In-app | "Jordan Lee joined AP Biology. Profile: 10th grade, readiness baseline: not set." |

#### Teacher Dashboard Notification Panel

The dashboard is the primary interface. Instead of push, teachers see a notification bell (in-app badge) that opens a structured feed:

```
[Bell icon with badge count]
  ├── 🚨 At-risk (2)
  │     ├── Maria G. — readiness 42%, test in 6 days
  │     └── James L. — inactive 5 days, test in 4 days
  ├── 📋 Test upcoming (1)
  │     └── AP Bio Chapter Test — tomorrow
  ├── ✅ Student joined (1)
  │     └── Jordan Lee joined AP Biology
  └── 📊 Weekly digest ready
        └── Class avg: 67% readiness (↑4% vs last week)
```

#### Teacher Notification Settings

- **Push notifications**: Off by default (toggle to enable)
- **Email digest**: Day + time (default Monday 8am)
- **At-risk threshold**: Configurable (default: readiness < 55%, test ≤7 days)
- **Test alerts**: On/Off
- **Student joins**: On/Off

---

### Admin Notifications

Admins monitor platform health, not learning outcomes. Their notifications are operational, not pedagogical.

#### Admin Notification Types

| Notification | Trigger | Channel | Content |
|-------------|---------|---------|---------|
| **User Report** | Student or teacher submits content/account report | Email + Dashboard | Reporter, reported user/content, category, timestamp |
| **Invite Activity** | Bulk invites sent or large invite batch fails | Dashboard | Batch stats (sent, accepted, failed) |
| **Platform Anomaly** | OCR processing failure rate spikes, course creation failures | Email + Dashboard | Failure count, affected courses, time window |
| **Subscription Event** | New trial started, plan upgrade, cancellation | Email | User, plan change, revenue impact |
| **Weekly Health Summary** | Monday 8am | Email | DAU/WAU, new users, active courses, readiness improvements, OCR queue depth |

---

## Notification Timing Strategy

### Optimal Send Windows (Evidence-Based)

```
STUDENTS (K-12 & Higher Ed)
─────────────────────────────────────────────────────────────────
06:00 ─────────────────────────────────────────────────────────
07:00  ← Morning commute window (higher ed / commuting students)
08:00  ★ Primary window: planning the day, high energy
09:00  ─── SCHOOL HOURS SUPPRESSED (weekdays) ───────────────
10:00  
11:00  ← Light window: lunch / break (higher ed)
12:00  
13:00  
14:00  
15:00  ─── SCHOOL HOURS END ─────────────────────────────────
16:00  ← After school window: homework time
17:00  
18:00  ★ Primary window: homework / study time
19:00  ★ Primary window: study time, peak engagement
20:00  ← Late study / wind-down
21:00  ─── QUIET HOURS BEGIN (default) ────────────────────

PARENTS
─────────────────────────────────────────────────────────────────
08:00  ★ Morning check window
12:00  ← Lunch check
18:00  ★ After-work window (primary)
21:00  ← Maximum, no later

TEACHERS
─────────────────────────────────────────────────────────────────
07:30  ★ Pre-class prep window (primary)
15:30  ← Post-school planning window
No push during school hours (9am–3pm)
```

### Frequency Caps

| Role | Daily Cap | Weekly Cap | Throttle Rule |
|------|-----------|------------|---------------|
| **Student** (high engagement) | 2 | 5 | Skip Tier 3 if Tier 1 sent same day |
| **Student** (moderate) | 1 | 3 | Skip friend activity if inactivity nudge already sent |
| **Student** (at-risk / declining) | 2 | 4 | Prioritize streak + readiness over social |
| **Parent** | 1 | 2 | Only critical events + weekly digest |
| **Teacher** | 0 push (default) | 1 email | Email digest only; dashboard on-demand |

### Throttling Priority Order

When a user's cap is reached, notifications are prioritized:

1. Test in ≤1 day (P0, always send)
2. Streak at risk (P1, always send)
3. Readiness drop ≥10% (P2)
4. Weak skill confirmed (P2)
5. Invite/share received (P3)
6. Friend milestones (P4)
7. Daily habit nudge (P5, lowest)

---

## Habit Formation Loop

This is the architecture FunSheep notifications are designed to create over time:

```
Week 1–2 (External Trigger Phase)
    Notification → App open → 1 question → In-app reward → Close

Week 3–4 (Association Phase)
    Notification → App open (user starts to anticipate) → Session → Streak builds

Week 5–8 (Internal Trigger Phase)
    [User thinks: "I should study before dinner"] → App open (no notification needed)
    Notification becomes backup, not primary driver

Beyond 2 months (Habit Phase)
    Streak becomes identity ("I'm a daily studier")
    Notifications shift to milestone celebration + social proof
```

The product should measure **internal trigger acquisition rate**: the % of daily sessions opened without a notification. Target: >40% of DAU sessions are notification-free by month 3.

---

## Streak Mechanics (Duolingo-Inspired, Adapted for Study Context)

### Streak Rules

- A **study day** = at least 1 question answered in a practice or assessment session
- Streak increments at midnight local time if the daily goal was met
- Streak resets to 0 if no activity for a full calendar day

### Streak Freeze ("Wool Freeze")

- Students can earn or purchase a **Wool Freeze** — protects the streak for 1 missed day
- Max: 3 Wool Freezes per month
- Displayed as a snowflake icon on the streak counter
- Notification: "Your Wool Freeze activated! Your 14-day streak is safe."

**Why this works:** Paradoxically, allowing one exemption increases long-term streak maintenance by reducing guilt and all-or-nothing thinking. Users who have safety nets maintain streaks longer than those who do not.

### Streak Milestones

| Streak | Reward | Notification |
|--------|--------|-------------|
| 3 days | 50 bonus XP | In-app only |
| 7 days | Streak badge + 150 XP | Push + In-app |
| 14 days | Special animation | Push + In-app |
| 30 days | "Dedicated Learner" badge + parent notified | Push + Email to parent |
| 60 days | "Study Machine" title | Push + In-app |
| 100 days | Special "Century" badge + shareable card | Push + Email (self) |

---

## Weekly Digest — Email Template (Parent)

```
Subject: Maria's weekly study update — [Date range]

──────────────────────────────────────────────
FunSheep Weekly Report
Maria García · AP Biology
──────────────────────────────────────────────

This Week
  📚 Sessions: 8           Study time: 3.5 hours
  🎯 Skills practiced: 6   Mastered: 2
  🔥 Streak: 12 days       XP earned: 420 FP

Readiness Score
  Overall: 72% (↑6% since last week)
  Target for upcoming test: 80%
  
  [Progress bar: ████████████░░░░ 72%]

Strong Skills ✅
  Cellular Respiration     92%
  DNA Replication          88%

Needs Work ⚠️
  Photosynthesis           54%
  Meiosis                  61%

Upcoming Test
  AP Bio Chapter Test      [Date] — in 8 days
  Readiness at test date (projected): 78%

Recommended Action
  15 targeted questions on Photosynthesis (≈ 5 min/day)
  would bring readiness to 85%+ by test day.

[View Full Dashboard]

──────────────────────────────────────────────
Unsubscribe | Notification preferences
```

---

## Implementation Phases

### Phase 1 — Foundation (MVP)

**Scope**: Core habit triggers + parent readiness alerts

1. **Notification delivery infrastructure**
   - Choose a notification service (OneSignal or Oban-based email/push queue)
   - Build `notifications` table: `user_role_id`, `type`, `channel`, `payload`, `status`, `sent_at`, `read_at`
   - Build `notification_preferences` table: per-role, per-type toggles + quiet hours
   - Implement frequency cap + priority queue logic

2. **Student streak system**
   - `streaks` table: `user_role_id`, `current_streak`, `longest_streak`, `last_active_date`, `freeze_count`
   - Streak increment job (midnight local time, per timezone)
   - Streak-at-risk detection (18h inactivity, streak > 0)
   - Streak freeze mechanic

3. **Student notifications (Tier 1 only)**
   - Streak-at-risk push
   - Test upcoming (T−3, T−1) push
   - Invite received push + in-app
   - Share received in-app

4. **Parent notifications (critical only)**
   - Readiness drop ≥10% push
   - Test upcoming (T−3, T−1) push + email

5. **Teacher dashboard notification panel**
   - At-risk student list (readiness < 55%, test ≤7 days)
   - Upcoming test badge
   - No push

**Exit criteria:** Streak system live, Tier 1 notifications sending, parent digest sending weekly, no push to teachers.

---

### Phase 2 — Personalization (Month 2–3)

1. **Optimal timing per user**
   - Track `last_active_hour` per user (rolling 14-day average)
   - Adjust notification send time to match personal engagement window

2. **Student Tier 2 notifications**
   - Readiness drop with weak skill named
   - Readiness milestones
   - Skill mastery in-app
   - Friend milestone push (requires friend system)

3. **Parent weekly email digest**
   - Structured template with readiness trend, skills, recommended action
   - Sunday 6pm local time (configurable)

4. **Teacher weekly class email digest**
   - Class avg readiness, at-risk students, top weak skills
   - Monday 8am (configurable)

5. **Notification preference UI**
   - Student: frequency slider, quiet hours, toggle types
   - Parent: digest day/time, threshold for readiness alerts
   - Teacher: enable/disable push, email day/time

**Exit criteria:** Personalized timing live, all Tier 2 notifications active, preference UI shipped.

---

### Phase 3 — Advanced (Month 4–6)

1. **Spaced repetition scheduling**
   - Track last correct answer timestamp per skill per student
   - Calculate optimal review window using Ebbinghaus curve (approximate: 1d, 3d, 7d, 14d, 30d)
   - Notification: "Time to review [Skill] — you nailed it 7 days ago"

2. **Hobby-personalized notification copy**
   - If student has hobby profile, use hobby context in notification text
   - "Your Biology question uses soccer analogies — ready to try it?"

3. **Variable reward tie-in**
   - Some notifications (not all) promise a mystery reward for completing the drill
   - "Complete today's question for a bonus — you won't know what until you try."

4. **SMS for parents (opt-in)**
   - Test-day only (T−1 and day-of)
   - Must be explicit opt-in with phone number verification
   - Regulatory compliance (TCPA, international carriers)

5. **A/B testing framework**
   - Test: urgency vs. encouragement tone for streak alerts
   - Test: specific skill named vs. generic readiness drop message
   - Test: morning vs. evening for habit nudges

6. **Notification analytics dashboard (admin)**
   - Open rates, click-through rates, opt-out rates per notification type
   - DAU correlation with notification delivery

**Exit criteria:** Spaced repetition notifications live, SMS opt-in available, A/B framework running.

---

## Database Schema

```sql
-- Core notification log
CREATE TABLE notifications (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id   UUID NOT NULL REFERENCES user_roles(id),
  type           TEXT NOT NULL,         -- "streak_at_risk", "test_upcoming", etc.
  channel        TEXT NOT NULL,         -- "push", "email", "in_app", "sms"
  priority       INTEGER NOT NULL,      -- 0 = critical, 5 = lowest
  payload        JSONB NOT NULL,        -- {title, body, data, metadata}
  status         TEXT NOT NULL DEFAULT 'pending',  -- pending, sent, failed, read
  scheduled_for  TIMESTAMPTZ NOT NULL,
  sent_at        TIMESTAMPTZ,
  read_at        TIMESTAMPTZ,
  inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Per-user preferences
CREATE TABLE notification_preferences (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id     UUID NOT NULL REFERENCES user_roles(id),
  channel          TEXT NOT NULL,       -- "push", "email", "sms", "in_app"
  notification_type TEXT,              -- NULL = applies to all types on this channel
  enabled          BOOLEAN NOT NULL DEFAULT true,
  quiet_start      TIME,               -- local time quiet hours start (default 21:00)
  quiet_end        TIME,               -- local time quiet hours end (default 08:00)
  frequency_tier   TEXT DEFAULT 'standard',  -- "off", "light", "standard", "all"
  custom_time      TIME,               -- for daily habit nudge, user-specified time
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_role_id, channel, notification_type)
);

-- Streak tracking
CREATE TABLE streaks (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id      UUID NOT NULL REFERENCES user_roles(id) UNIQUE,
  current_streak    INTEGER NOT NULL DEFAULT 0,
  longest_streak    INTEGER NOT NULL DEFAULT 0,
  last_active_date  DATE,
  freeze_count      INTEGER NOT NULL DEFAULT 0,  -- available freezes
  freeze_used_at    DATE,                         -- last date a freeze was consumed
  inserted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Push device tokens
CREATE TABLE push_tokens (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_role_id  UUID NOT NULL REFERENCES user_roles(id),
  token         TEXT NOT NULL,
  platform      TEXT NOT NULL,   -- "ios", "android", "web"
  active        BOOLEAN NOT NULL DEFAULT true,
  inserted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_role_id, token)
);
```

---

## Oban Workers

| Worker | Schedule | Purpose |
|--------|----------|---------|
| `StreakIncrementWorker` | Midnight per user timezone | Increment streak if daily goal met; reset if missed |
| `StreakAtRiskWorker` | Every 2 hours | Detect users with 18h inactivity + active streak; enqueue alert |
| `TestUpcomingWorker` | 8am daily | Find test_schedules at T−3 and T−1; enqueue student + parent alerts |
| `ReadinessDeltaWorker` | After each assessment session | Compute readiness delta; trigger alert if drop ≥5%/10% |
| `WeeklyParentDigestWorker` | Sunday 6pm per timezone | Compile weekly report; send email to opted-in parents |
| `WeeklyTeacherDigestWorker` | Monday 8am per timezone | Compile class report; send email to teachers |
| `SpacedRepetitionWorker` | Daily 9am | Find skills due for review per student; enqueue nudges |
| `NotificationDeliveryWorker` | Continuous | Pop from notification queue, enforce caps, send, update status |

---

## Success Metrics

| Metric | Phase 1 Target | Phase 2 Target | Measurement |
|--------|---------------|---------------|-------------|
| **DAU lift (notifications enabled vs. disabled)** | +20% | +40% | A/B test at onboarding opt-in |
| **Streak maintenance (avg days)** | 8 days | 14 days | `AVG(longest_streak)` per cohort |
| **Push opt-in rate** | >50% of students | >60% | tokens count / DAU |
| **Push opt-out rate** | <15% at 30 days | <10% at 60 days | Cumulative opt-outs per cohort |
| **Notification open rate** | >25% | >30% | sent vs. read |
| **Internal trigger rate** | N/A | >30% sessions notification-free | Sessions opened w/o prior notification in last 2h |
| **Parent weekly digest open rate** | >35% | >45% | Email open tracking |
| **Teacher dashboard engagement** | >50% weekly | >60% weekly | Dashboard logins |
| **Readiness improvement (notified students)** | +5% | +10% | Readiness delta, students with push vs. without |

---

## References & Research Basis

- Duolingo habit formation system: streak psychology, FOMO mechanics, variable reward schedules
- BJ Fogg — *Tiny Habits* (Behavior = Motivation × Ability × Prompt)
- Nir Eyal — *Hooked* (External trigger → internal trigger transition)
- Ebbinghaus forgetting curve → spaced repetition timing
- Kahneman — loss aversion (streaks hurt more to lose than they feel good to gain)
- Push notification benchmarks: 28% CTR (push), 2.6% CTR (email), 98% open (SMS)
- Duolingo internal data: users with push notifications maintain streaks 7–8% longer
- Users who accept personalized notifications engage 26% more often monthly
- Cross-channel quiet-hour coordination → 47% lower uninstall rate, 39% higher engagement

---

## Implementation Checklist

### Phase 1 — Foundation (MVP) ⚠️ Partially Done

**Notification infrastructure:**
- [ ] `notifications` table (pending — no migration found)
- [ ] `notification_preferences` table (pending — only user_role columns added, not a full table)
- [x] Digest preference fields on `user_roles`: `digest_frequency`, `alerts_skipped_days`, `alerts_readiness_drop`, `alerts_goal_achieved` (`20260422160200`)
- [ ] Frequency cap + priority queue logic

**Streak system:**
- [x] `streaks` table with `current_streak`, `longest_streak`, `streak_frozen_until` (in `20260418160000_create_gamification.exs`)
- [x] `FunSheep.Gamification.Streak` schema
- [ ] Streak increment job (midnight local time, per timezone)
- [ ] Streak-at-risk detection (18h inactivity when streak > 0)
- [ ] Streak freeze mechanic

**Student notifications (Tier 1):**
- [ ] Streak-at-risk push notification
- [ ] Test upcoming (T−3, T−1) push notification
- [ ] Invite received push + in-app notification
- [ ] Share received in-app notification

**Parent notifications:**
- [x] Parent weekly email digest (`parent_digest_scheduler.ex` + `notifications.ex` + `unsubscribe_token.ex`)
- [x] Digest content: activity minutes, readiness change, upcoming tests, conversation prompts
- [x] Unsubscribe token system for email opt-out
- [ ] Readiness drop ≥10% push notification
- [ ] Test upcoming (T−3, T−1) push + email

**Teacher notifications:**
- [ ] At-risk student dashboard panel (readiness < 55%, test ≤7 days)

### Phase 2 — Personalization ⬜ Not started

- [ ] Track `last_active_hour` per user (rolling 14-day average)
- [ ] Adjust notification send time to personal engagement window
- [ ] Student Tier 2 notifications (readiness drop with skill named, milestones, skill mastery)
- [ ] Parent weekly email digest with structured template
- [ ] Teacher weekly class email digest (avg readiness, at-risk, top weak skills)
- [ ] Notification preference UI (frequency slider, quiet hours, toggles per role)

### Phase 3 — Advanced ⬜ Not started

- [ ] Spaced repetition notifications (Ebbinghaus curve: 1d, 3d, 7d, 14d, 30d review windows)
- [ ] Hobby-personalized notification copy
- [ ] Variable reward tie-in (mystery reward for completing drill)
- [ ] SMS for parents (opt-in only, TCPA compliance)
- [ ] A/B testing framework for notification tone/timing
- [ ] Notification analytics dashboard (open rates, CTR, opt-out rates)
