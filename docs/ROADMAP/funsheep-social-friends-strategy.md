# FunSheep — Social Friends & Followers Strategy

> **Purpose**: Research, design, and phased implementation plan for the full social graph on FunSheep — covering follows, invites, course sharing, school discovery, and people search. This is a living strategy document; each Phase section is a self-contained implementation prompt.

---

## 0. Context

FunSheep is a Phoenix/LiveView test-prep platform. The existing social surface is:

| What exists | Location | Notes |
|-------------|----------|-------|
| Flock leaderboard (affinity-ranked peers) | `FunSheep.Gamification.build_flock/2` | Not a social graph — affinity scoring only |
| Shout Outs (weekly spotlight winners) | `FunSheep.Gamification.ShoutOut` | No follow relationship |
| Guardian invites (student ↔ parent/teacher) | `FunSheep.Accounts.StudentGuardian` | Hierarchical, not peer |
| Proof card sharing (shareable result snapshots) | `FunSheep.Engagement.ProofCard` | Token-based, one-way, no graph |
| Teacher referral credits | `FunSheep.Credits` | Earn-based, no peer follow |
| School membership | `user_roles.school_id` | Only used for affinity scoring |

**What's missing entirely**: peer-to-peer social graph. No follow relationship, no friend connections, no discovery beyond the Flock leaderboard, no viral invite-to-friend loop.

---

## 1. Research: How the Best Platforms Do It

### 1.1 Instagram — Asymmetric Follow + Discovery Engine

**Core mechanic**: You follow someone; they don't need to follow back. Mutual follows upgrade to "friends" in algorithm priority but are not displayed differently in the UI (until 2023 "Close Friends").

**What makes it viral:**
- **"X and Y follow [person]"** — social proof in discovery creates instant credibility
- **Suggested accounts** seeded by: phone contacts → mutual follows → topic overlap
- **Notification loop**: you follow → they get notified → they view your profile → they follow back (k-factor multiplier)
- **Profile as social proof**: follower count, post count, bio all visible before follow — the profile IS the pitch to follow

**Key pattern for FunSheep**: People follow accounts whose *content* (achievements, scores, streaks) is visible and impressive even before they're friends. Profile → public stats → follow decision.

---

### 1.2 Twitter/X — Follow Graph as Content Graph

**Core mechanic**: Follow to curate your feed. Follows are asymmetric. The "following" list IS your content source.

**What makes it viral:**
- **"Who to follow" sidebar** — always visible, updated constantly (friend-of-friend, topic-match)
- **Tweet engagement → profile visit → follow** — content quality drives follows
- **Trending + Lists** — discovery beyond your social graph
- **@mention** — creates cross-graph connections that lead to new follows

**Key pattern for FunSheep**: Following someone should *unlock content* you can't see otherwise — friend's quiz scores, their study schedule, their course recommendations. The follow is the paywall for richer data.

---

### 1.3 Snapchat — Mutual Friends + Streak Anxiety

**Core mechanic**: Symmetric "friends" (both must add). But follows are asymmetric via "subscribe."

**What makes it viral:**
- **Snapstreak**: daily mutual exchange requirement creates *anxiety to maintain*. The streak IS the relationship.
- **Best Friends**: top 3 contacts by interaction frequency — public status, intensely competitive
- **Quick Add**: "You have [N] mutual friends" — makes adding feel low-risk
- **"Added by" provenance**: every new friend has a source label (by search / by username / from phone / by snap code) — this transparency lowers hesitation
- **Score**: accumulated engagement metric, visible on profile — becomes social status

**Key pattern for FunSheep**: The **study streak IS the social streak**. A mutual follow where both parties study on the same day is a "Study Buddy Streak." Breaking it creates anxiety. Maintaining it creates bond.

---

### 1.4 LinkedIn — Degree Graph + Alumni Network

**Core mechanic**: Connection requests (symmetric, requires acceptance). Also asymmetric "follow" for influencers.

**What makes it viral:**
- **1st/2nd/3rd degree visibility** — "You both know [X]" in every profile header
- **School alumni pages**: "X people from [School] are on LinkedIn" — every new student is shown this
- **"People also viewed"** — search intent matched to lookalike profiles
- **Endorsements**: peer-validated skills create social proof that is *specific and credible*
- **Profile completion meter**: nudges to completeness which feeds the algorithm

**Key pattern for FunSheep**: School as the primary social unit. "X students from [School] are already studying on FunSheep" is the highest-converting onboarding CTA. Alumni/school-scoping is natural, privacy-preserving, and educationally relevant.

---

### 1.5 Duolingo — Closest Competitor (Social E-Learning)

**Core mechanic**: Follow friends (asymmetric). Friends appear in your weekly leaderboard as your reference group.

**What makes it viral:**
- **Leagues with promotion/demotion**: weekly competition with your friend group — stakes without being mean
- **Friend streak visibility**: see your friends' daily streaks on their profile → motivation + FOMO
- **"Invite a friend, you both get gems"**: symmetric incentive for referrals
- **Heart sharing**: limited resource that friends can replenish for each other → cooperation mechanic
- **Streak milestones push-notified to followers**: "@alex just hit a 30-day streak!" lands in notification tray even for non-daily users → re-engagement

**Key pattern for FunSheep**: Achievements need to be *broadcast* to followers. The moment a follower gets a push notification about a friend's achievement is the highest-leverage re-engagement moment in e-learning.

**Duolingo's biggest lesson**: The social graph is *secondary* to the leaderboard. Friends exist to give the leaderboard personal stakes. Without names you know, the leaderboard is abstract. With them, it's urgent.

---

### 1.6 What Works in EdTech Specifically

From Duolingo's growth research and published studies:

- **Badge introduction → 116% referral jump** (Duolingo, 2023). Achievements as social currency are the single most reliable viral mechanic in e-learning.
- **"Streak of shame" notifications** are Duolingo's #1 re-engagement driver — peer-aware accountability works better than generic reminders.
- **Friend leaderboard beats global leaderboard** for retention: seeing a familiar name 2 spots ahead is 3× more motivating than seeing a stranger at #1.
- **Asymmetric follow is safer than mutual friends** for minors: you can follow an aspirational student (a senior, a top scorer) without reciprocity, reducing social rejection risk.

---

## 2. FunSheep Social Model Design

### 2.1 Core Graph Model: Asymmetric Follow

**Decision**: Follow is asymmetric (like Instagram / Twitter / Duolingo), not mutual-required (like Facebook / Snapchat).

**Rationale**:
- K-12 students face rejection anxiety; not requiring reciprocity removes the social risk of following aspirational peers (seniors, top scorers)
- Asymmetric follow creates "aspirational following" — juniors following seniors, students following teachers — which is a natural educational dynamic
- Mutual follows ("friends") emerge organically when both parties choose to follow each other; show this state distinctively

**Follow states**:

```
A → B only:      A is "following" B; B is "in A's following list"
A → B + B → A:  "Mutual follow" = Friends; displayed with ♥ or special badge
A mutes B:       A still follows B, B's activity suppressed from A's feed
A blocks B:      Neither can view each other's profiles; block is private
```

**School-scoped by default**: Students can only be found and followed by users at the same school (or same course). Global search requires explicit opt-in. This is the key privacy control for minors.

---

### 2.2 The Five Features: Design Decisions

#### Feature 1: Who Invited Whom (Invitation Graph)

**Platform references**: LinkedIn "Connected via [name]", Snapchat "Added by username", Robinhood "Referred by [name]"

**FunSheep design**:
- Every social follow and account creation traces back to an invite source
- Profile card shows: "You invited [Name]" or "Invited by [Name]" as a subtle badge
- Invitation graph is visible to the inviter: "Your Flock Tree — [N] people you've brought to FunSheep"
- Invite chain = gamified: invite 5 people → badge "Shepherd"; 10 people → "Lead Shepherd"; 20+ → "Flock Builder"

**Viral mechanic**: The inviter has an intrinsic motivation to see the people they invited succeed — they will re-engage to check on their "flock."

---

#### Feature 2: Course & Test Shares (Study Buddy Connection)

**Platform references**: Spotify "Shared a playlist", Netflix Party, Google Classroom "Shared with you"

**FunSheep design**:
- When A shares a course or test with B, this creates a **Study Buddy relationship** for that course
- Study Buddy ≠ full follow; it's course-scoped social connection
- B's enrollment screen shows: "Studying together with [A's display name]"
- After B completes a quiz, B sees: "[A] got 82% on this — you got 79%!" (only if B consents to this comparison)
- Completing a shared course together → "Graduated Together" badge for both

**Viral mechanic**: Sharing a course is a *cooperative* social action (not competitive like following). It spreads naturally because both parties benefit — lower FOMO anxiety, more sharing.

---

#### Feature 3: Follow + Followers (Core Social Graph)

**Platform references**: Instagram, Twitter, Duolingo followers/following

**FunSheep design**:

**Following tab on Flock page** (extend existing Flock LiveView):
- Filter: "Everyone" | "Following" | "Friends" (mutual)
- Following-filtered leaderboard shows exact positions relative to known people
- "Your friend [Name] is 3 positions above you this week" — competitive nudge

**What following unlocks** (the paywall model):
- See friend's current streak (not just your own)
- See friend's most recently earned badge
- See friend's weekly XP rank in the Flock
- Get notified when friend hits a milestone (push, Phase 3)

**Friend profile page** (new route: `/profile/:id`):
- Display name + avatar initial
- School (name only, not specific class)
- Courses they're enrolled in (only if they set to visible)
- Current streak / longest streak
- Badges earned (grid)
- Weekly XP (this week)
- "Follow" / "Following" / "Friends" CTA
- "Study Together" button (share a course)
- Mutual follows: "You both follow [N] other students"

**Mutual follow display**: When both A and B follow each other, show ♥ icon on profile card. In the Flock list, mutual follows appear with a subtle green ring. This makes "friends" status visible and desirable.

---

#### Feature 4: School Directory (Classmate Discovery)

**Platform references**: LinkedIn Alumni, Snapchat school groups, Facebook "People you may know from [School]"

**FunSheep design**:

**School tab** on Flock page (third tab after Leaderboard and Shout Outs):

```
[Leaderboard] [Shout Outs] [School] [Find Friends]
```

School directory shows **all active students at the same school**, sorted by:
1. Mutual follows first
2. Shared courses (most overlap at top)
3. Activity level (weekly XP, descending)

Each card shows:
- Avatar initial + display name
- Grade level
- N shared courses
- Follow/Following state
- If mutual: "Friends ♥"

**"3 students from [School] joined this week"** banner at top — creates FOMO.

**Inevitable design** (see §2.4): When a student first sets their school in onboarding, they are immediately shown the school directory with a prompt: *"X students from [School] are already here. Follow 3 to join their Flock."* This is a mandatory onboarding step (not skippable).

---

#### Feature 5: People Search (Making It Inevitable)

**Platform references**: Instagram search, Snapchat Quick Add, Twitter "Who to follow"

**FunSheep design**:

**Search surface** — a fourth tab on the Flock page:

```
[Leaderboard] [Shout Outs] [School] [Find Friends]
                                      ↑ this tab
```

**Find Friends tab** includes:
1. **Search bar** — search by display name within same school (not global)
2. **Quick Follows** — "People you might know" based on:
   - Shared courses (same enrollment)
   - Flock proximity (ranked within 10 positions of you)
   - Followed by someone you follow (friend-of-friend)
   - Recently joined same school
3. **Invite by link** — share a personal invite link (opens social_invite flow)

**"Inevitable" design tactics** — patterns that make discovery impossible to miss:
1. **Onboarding gate**: Step 4 of onboarding is "Follow 3 friends" — cannot proceed without following at least 1 (skip allowed after 3 attempts)
2. **Dashboard widget**: "People You Might Know" card (3 profiles) always present on dashboard when following-count < 5
3. **Post-assessment nudge**: After every test, show: "2 of your Flock also took this test. Follow them to see how they did."
4. **Flock click-through**: Clicking any name in the Flock leaderboard opens their profile → follow button
5. **Empty following leaderboard message**: "Follow classmates to see your friend leaderboard" — actionable empty state, not dead end
6. **Achievement notification**: "You just beat [anonymous Name]! Follow them to track your rivalry." (opt-in)

---

### 2.3 Viral Loop Architecture

**Loop 1: The School Network Effect (k-factor primary driver)**

```
Student A joins → sets school → sees "X students from [School]" →
follows 3 → they get notified → they view A's profile → 1.5 follow back →
A's Flock now has familiar names → studies more to stay competitive →
streak achievement → suggests sharing with [B, C not yet on platform] →
B joins → sees "Student A is already here" → cycle restarts
```
Estimated k-factor contribution: 0.4 per new student at a school where FunSheep exists.

**Loop 2: The Study Buddy Course Share Loop**

```
A shares course with B (existing user) →
B sees "[A] is studying this with you" →
B enrolls → both get "Study Buddy XP" bonus (1.2× XP for 7 days) →
results show "[A] got X%, you got Y%" →
competitive pressure drives both to study more →
one of them beats an assignment → shares proof card →
C (not a user) sees proof card → joins → finds A and B already there
```

**Loop 3: The Achievement Broadcast Loop**

```
Student earns milestone (100% readiness / 30-day streak / Shout Out winner) →
System: "Share this milestone with your followers?" →
Followers get notified / see proof card →
Followers who are falling behind: "Your friend just hit 30 days — you're at 12" →
Re-engagement spike →
Non-users who see shared proof card: "What is FunSheep?" → join
```

**Loop 4: The Invite Chain / Flock Tree**

```
Teacher invites 10 students (Wool Credits mechanic) →
Each student gets "Invited by [Teacher]" tag →
3 of those students invite friends (General invite) →
Flock Tree visible to teacher: 10 direct + 7 indirect →
Teacher earns "Flock Builder" badge → shares on social media →
More students see → join
```

---

### 2.4 "Inevitable Discovery" Design Principle

The user specified: *"Make other users search — make them inevitable."* This is the critical design constraint. Discovery must be woven into every flow, not a standalone feature.

**The seven touchpoints where user discovery appears**:

| Touchpoint | Trigger | Discovery Action |
|------------|---------|-----------------|
| Onboarding Step 4 | School set | School directory, mandatory follow prompt |
| Dashboard (< 5 follows) | Every visit | "People You Might Know" widget, 3 profiles |
| Post-assessment | Test completed | "2 peers took this test — follow them" |
| Flock leaderboard | Any visit | Every name is clickable → profile → follow |
| Shout Out winner | Any visit | Winner card is clickable → profile → follow |
| Achievement earned | Milestone hit | "Share with followers" + "See who's close to this" |
| Empty following filter | Filtering Flock | "Follow classmates to unlock friend leaderboard" |

**Progressive disclosure**: early visits show school-based suggestions. After 5 follows, switch to course-based. After 10, show friend-of-friend. After 20, show aspirational (top scorers in any course).

---

## 3. Database Schema

### New Tables

```sql
-- Core follow graph (append-only intent; rows deleted on unfollow)
social_follows (
  id              uuid primary key default gen_random_uuid(),
  follower_id     uuid not null references user_roles(id) on delete cascade,
  following_id    uuid not null references user_roles(id) on delete cascade,
  status          text not null default 'active',   -- active | muted | blocked
  source          text not null,                    -- manual | suggested_school | suggested_course |
                                                    -- suggested_fof | invite_accepted | course_shared
  inserted_at     timestamp not null default now(),
  constraint social_follows_unique unique (follower_id, following_id),
  constraint social_follows_no_self check (follower_id != following_id)
)
-- Index: follower_id, following_id (bidirectional lookup for mutual check)
-- Derived: mutual follow = EXISTS row (A→B) AND EXISTS row (B→A)
```

```sql
-- Peer invites (student → student, with optional course/test context)
social_invites (
  id                        uuid primary key default gen_random_uuid(),
  inviter_id                uuid not null references user_roles(id),
  invitee_user_role_id      uuid references user_roles(id),         -- set when claimed
  invitee_email             text,                                    -- for non-users
  invite_token              text unique,                             -- nullable for existing-user invites
  invite_token_expires_at   timestamp,
  status                    text not null default 'pending',         -- pending|accepted|expired|declined
  context                   text not null default 'general',         -- general|course|test
  context_id                uuid,                                    -- course_id or test_schedule_id
  message                   text,                                    -- optional personal note
  accepted_at               timestamp,
  inserted_at               timestamp not null default now()
)
```

```sql
-- Explicit course/test shares between existing users
course_shares (
  id                  uuid primary key default gen_random_uuid(),
  sharer_id           uuid not null references user_roles(id),
  course_id           uuid references courses(id),
  test_schedule_id    uuid references test_schedules(id),
  message             text,
  share_token         text unique not null,
  expires_at          timestamp,
  inserted_at         timestamp not null default now(),
  constraint course_shares_has_content check (
    (course_id is not null) or (test_schedule_id is not null)
  )
)

-- Pivot: who received a share
course_share_recipients (
  id                  uuid primary key default gen_random_uuid(),
  course_share_id     uuid not null references course_shares(id),
  recipient_id        uuid references user_roles(id),  -- null for email-only
  recipient_email     text,
  sent_at             timestamp,
  viewed_at           timestamp,
  enrolled_at         timestamp,
  inserted_at         timestamp not null default now()
)
```

```sql
-- Privacy: blocks (symmetric access denial, stored as single directed row per direction)
user_blocks (
  id          uuid primary key default gen_random_uuid(),
  blocker_id  uuid not null references user_roles(id),
  blocked_id  uuid not null references user_roles(id),
  inserted_at timestamp not null default now(),
  constraint user_blocks_unique unique (blocker_id, blocked_id)
)
```

### Schema Notes

- **No `updated_at` on `social_follows`**: follows are created and deleted, never mutated. Muted state stored in `status` column.
- **`social_invites` vs `student_guardians`**: Guardian invites (student→parent/teacher) stay in `student_guardians`. Peer invites (student→student) go in `social_invites`. Different flows, different acceptance logic.
- **Invite token reuse**: `social_invites.invite_token` uses same 14-char format as guardian invites for consistency. Non-user invites get a token; existing-user invites get a direct notification instead.
- **`course_shares` is separate from `proof_cards`**: Proof cards share *results*. Course shares share *access to study together*. Distinct intent.
- **Block check on every query**: All social queries must include a block filter. Helper: `FunSheep.Social.blocked_user_ids(user_id)` → cached set of blocked/blocker ids.

---

## 4. Elixir Context Structure

```
lib/fun_sheep/
├── social.ex                            # Context: follows, invites, search, suggestions
├── social/
│   ├── follow.ex                        # Schema: social_follows
│   ├── invite.ex                        # Schema: social_invites
│   ├── course_share.ex                  # Schema: course_shares
│   ├── course_share_recipient.ex        # Schema: course_share_recipients
│   └── block.ex                         # Schema: user_blocks
```

**Key context functions:**

```elixir
defmodule FunSheep.Social do
  # Follow graph
  def follow(follower_id, following_id, source \\ :manual)
  def unfollow(follower_id, following_id)
  def mute(follower_id, following_id)
  def block(blocker_id, blocked_id)
  def unblock(blocker_id, blocked_id)

  def mutual?(user_a_id, user_b_id) :: boolean
  def following_ids(user_id) :: [uuid]
  def follower_ids(user_id) :: [uuid]
  def blocked_user_ids(user_id) :: [uuid]   # both directions
  def follow_state(viewer_id, subject_id) :: :following | :mutual | :none | :blocked

  # Social-enriched Flock
  def flock_with_social(user_id, opts \\ [])   # builds Flock with follow_state per entry

  # School directory
  def school_peers(user_id, opts \\ [])         # returns user_roles at same school, sorted
  def school_peer_count(school_id)

  # People you might know (suggestions)
  def suggested_follows(user_id, limit \\ 6) :: [SuggestedFollow.t()]
  # SuggestedFollow: %{user_role: UserRole, reason: :school | :course | :fof | :flock}

  # Search
  def search_peers(user_id, query, opts \\ [])  # school-scoped by default

  # Invites
  def create_invite(inviter_id, opts)            # opts: email/user_role_id, context, message
  def accept_invite(token)
  def decline_invite(token)
  def list_sent_invites(user_id)
  def list_received_invites(user_id)

  # Course shares
  def share_course(sharer_id, course_id, recipient_ids, opts \\ [])
  def share_test(sharer_id, test_schedule_id, recipient_ids, opts \\ [])
  def list_shared_with_me(user_id)              # courses/tests others shared with me
  def list_i_shared(user_id)                    # courses/tests I've shared

  # Flock tree (invite chain analytics)
  def flock_tree(user_id)                        # who I invited and who they invited
  def flock_tree_count(user_id)                  # total descendants
end
```

---

## 5. UI / LiveView Plan

### 5.1 Flock Page — Tab Extension

Current: `[Leaderboard] [Shout Outs]`

Extended: `[Leaderboard] [Shout Outs] [School] [Find Friends]`

**Leaderboard tab** — add sub-filter:
```
Show: [Everyone ▼]  →  Everyone | Following | Friends only
```

**School tab** — new:
- Header: "X students from [School Name]" 
- Each user card: avatar, display name, grade, N shared courses, follow button
- Sorted: Friends → Following → Shared courses → Active

**Find Friends tab** — new:
- Search input (school-scoped)
- "Quick Follow" grid (6 suggestions with reason labels)
- "Invite a Friend" button → social_invite flow

### 5.2 User Profile Page (New Route)

Route: `/flock/:user_role_id`

LiveView: `FunSheepWeb.UserProfileLive`

```
┌─────────────────────────────────────┐
│  [Avatar initial]  Display Name     │
│  Grade 11 · Jefferson High School   │
│                                     │
│  [Follow ▾]  [Study Together ▾]     │
│                                     │
│  🔥 32-day streak  ⚡ 1,240 FP/wk   │
│  📚 5 courses      🏆 12 badges     │
│                                     │
│  Invited by: [Teacher Name] ↗       │
│  Mutual follows: 3 students         │
│                                     │
│  ──── Badges ────────────────────── │
│  [✨][🐣][🔥][🔥][🔥][⭐][💯]...   │
│                                     │
│  ──── Courses ──────────────────── │
│  AP Biology (shared ♥)             │
│  AP Chemistry                       │
│  SAT Math                           │
└─────────────────────────────────────┘
```

**Privacy rules enforced server-side**:
- `school_id` shown as school name only (never address)
- Courses visible only if they haven't opted out
- Badge grid visible to all school peers
- XP/streak visible only to followers

### 5.3 Dashboard Widget — "People You Might Know"

Shown on `DashboardLive` when `following_count < 5`:

```
┌──────────────────────────────────────────┐
│ People You Might Know                    │
│                                          │
│  [A] Alex K.   AP Bio · 4 shared  [+]  │
│  [B] Billie T. 11th grade · School [+]  │
│  [C] Chris M.  Flock neighbor      [+]  │
│                         [See all →]     │
└──────────────────────────────────────────┘
```

- Each suggestion has a reason label (shared course / same school / Flock neighbor)
- `[+]` button follows inline with optimistic UI update
- Dismissed suggestions don't reappear for 7 days

### 5.4 Invite Flow

New route: `/invite/send` (or modal from Flock / Dashboard)

**Step 1: Choose recipients**
- Search for school peers → select from list
- OR enter email address for non-users
- Optional personal message (80 char limit)

**Step 2: Choose context (optional)**
- "Just saying hi" (general)
- "Study this course with me" → select a course
- "Try this test" → select a test schedule

**Step 3: Send**
- Existing users: in-app notification
- Non-users: email with invite link → `/join/invite/:token`

**Invite landing page** (non-user):
- Displays: "[Display Name] invited you to study together on FunSheep"
- If course context: shows course title, subject, "[Display Name] is studying this course"
- CTA: "Join FunSheep and study together"
- After signup → auto-follow the inviter, auto-enroll in the shared course if applicable

### 5.5 Onboarding Integration (Step 4)

Insert after school selection in `StudentOnboardingLive`:

```
Step 4/5: Find your classmates

[3 suggested profiles with follow buttons]

"Follow at least 1 to continue"        [Skip →]
                                    (allowed after 3 attempts)
```

- Suggestions seeded immediately from school directory
- At least 1 follow triggered → fires `social_follows` insert with `source: :suggested_school`
- This is the first forced social action — sets the pattern

---

## 6. Privacy & Safety Controls

| Control | Default | User-adjustable | Parent-adjustable |
|---------|---------|-----------------|------------------|
| Who can follow me | Same school only | ✅ (open or off) | ✅ |
| Who can see my streak | Followers only | ✅ | ✅ |
| Who can see my courses | Followers only | ✅ | ✅ |
| Who can invite me | Same school only | ✅ | ✅ |
| Appear in school directory | Yes | ✅ | ✅ |
| Appear in "People you might know" | Yes | ✅ | ✅ |
| Show as Shout Out winner | Yes | ✅ | ✅ |

**Hard rules (not user-adjustable)**:
- Email never exposed via profile or invite landing page
- Last name never shown (display_name only)
- School address never shown
- Global search (across schools) requires admin enable
- Under-13 users: follow feature disabled by default, requires parent opt-in (COPPA)
- Block is always available to any user

---

## 7. Gamification Layer

### New Badges (Social-Triggered)

| Badge ID | Icon | Trigger | XP Bonus |
|----------|------|---------|----------|
| `first_follow` | 🐑 | Followed your first peer | +50 FP |
| `first_follower` | 🐏 | Got your first follower | +50 FP |
| `study_buddy` | 🤝 | Completed a shared course together | +100 FP |
| `flock_starter` | 🌱 | 5 followers | +100 FP |
| `shepherd` | 🐕 | Invited 5 people who joined | +200 FP |
| `lead_shepherd` | 🏅 | Invited 10 people who joined | +500 FP |
| `flock_builder` | 🌟 | Invited 20 people who joined | +1000 FP |
| `mutual_10` | ♥ | 10 mutual follows (friends) | +200 FP |

### Study Buddy Streak

When two mutual follows (friends) both study on the same day:
- Both get "Study Buddy Day" marker on their streak calendar
- 7 consecutive Study Buddy Days → +200 FP each
- "Graduated Together" badge when both complete the same course

### Invitation Tree Display

New section on Dashboard or Leaderboard: **"Your Flock Tree"**

```
You
├── [Name A]  (direct invite)  → 2 more they invited
├── [Name B]  (course share)   → 1 more
└── [Name C]  (direct invite)  → 0 more

Your tree: 3 direct, 3 indirect = 6 total sheep in your flock
```

Milestone labels:
- 1–4 direct: "Shepherd's First Flock"
- 5–9 direct: "Growing Shepherd"
- 10–19 direct: "Lead Shepherd"
- 20+ direct: "Flock Builder"

---

## 8. Analytics & Viral Coefficient Tracking

Track these metrics from day 1 to measure social health:

| Metric | Target | How Measured |
|--------|--------|--------------|
| k-factor (viral coefficient) | > 1.0 | invites_sent × acceptance_rate |
| Follow rate (% of new users who follow ≥1) | > 70% | Follows in first 24h |
| Mutual follow rate (% of follows that become mutual) | > 40% | social_follows self-join |
| Invite acceptance rate | > 30% | social_invites status = accepted |
| Course share enrollment rate | > 50% | course_share_recipients.enrolled_at not null |
| Study buddy streak formation rate | > 20% of mutual follows | XP events on same day |
| DAU lift from social features | > 15% | A/B test cohorts |

---

## 9. Phased Implementation Plan

### Phase 1: Social Graph Foundation (Week 1–6)

**Goal**: Follow/unfollow works end-to-end. School directory visible. Basic profile page.

**Database**:
- [ ] Migration: `social_follows`
- [ ] Migration: `user_blocks`

**Context (`FunSheep.Social`)**:
- [ ] `follow/3`, `unfollow/2`, `block/2`, `unblock/2`
- [ ] `following_ids/1`, `follower_ids/1`, `blocked_user_ids/1`
- [ ] `follow_state/2` (for UI rendering)
- [ ] `school_peers/2`, `school_peer_count/1`
- [ ] `flock_with_social/2` (extend existing Flock)

**UI**:
- [ ] Leaderboard tab: "Everyone / Following / Friends" filter
- [ ] School tab on Flock page (school directory)
- [ ] User profile page (`/flock/:id`) with follow button
- [ ] Clicking any name in Flock → goes to profile

**Tests**:
- [ ] `FunSheep.SocialTest` — context unit tests
- [ ] `FunSheepWeb.Live.UserProfileLiveTest` — LiveView tests
- [ ] Block filter on all social queries

---

### Phase 2: Discovery & Invitations (Week 7–12)

**Goal**: People search works. Invite flow sends and accepts. "Inevitable" discovery widgets live.

**Database**:
- [ ] Migration: `social_invites`

**Context**:
- [ ] `suggested_follows/2` — school → course → flock proximity → fof
- [ ] `search_peers/3` — school-scoped search
- [ ] `create_invite/2`, `accept_invite/1`, `decline_invite/1`
- [ ] `list_sent_invites/1`, `list_received_invites/1`

**UI**:
- [ ] "Find Friends" tab on Flock page (search + suggestions)
- [ ] Dashboard "People You Might Know" widget
- [ ] Post-assessment peer nudge ("2 peers took this — follow them")
- [ ] Onboarding Step 4: "Follow your classmates"
- [ ] Invite flow (`/invite/send`)
- [ ] Invite landing page (`/join/invite/:token`)

**Tests**:
- [ ] `FunSheep.Social.InviteTest`
- [ ] `FunSheepWeb.Live.FindFriendsLiveTest`
- [ ] `FunSheepWeb.Live.StudentOnboardingLiveTest` — step 4

---

### Phase 3: Course Sharing & Study Buddies (Week 13–18)

**Goal**: Course shares create study buddy relationships. XP bonuses for studying together.

**Database**:
- [ ] Migration: `course_shares`, `course_share_recipients`

**Context**:
- [ ] `share_course/4`, `share_test/4`
- [ ] `list_shared_with_me/1`, `list_i_shared/1`
- [ ] Study buddy XP bonus worker (Oban)
- [ ] Study buddy streak detection (extend `Gamification.record_activity/2`)

**UI**:
- [ ] "Study Together" button on profile page
- [ ] Course share modal (select recipients + message)
- [ ] "Studying with [Name]" banner on enrolled course card
- [ ] "Your friend got X%, you got Y%" post-quiz comparison (opt-in)

**Gamification**:
- [ ] `study_buddy` badge
- [ ] Study buddy streak (7-day shared study)
- [ ] "Graduated Together" badge

**Tests**:
- [ ] `FunSheep.Social.CourseShareTest`
- [ ] Study buddy XP worker tests

---

### Phase 4: Viral Amplification (Week 19–24)

**Goal**: Invite tree visible. Social achievements broadcast. Push notifications for social events.

**Context**:
- [ ] `flock_tree/1`, `flock_tree_count/1` — invitation chain
- [ ] Social notification events (extend `FunSheep.Notifications`)

**UI**:
- [ ] "Your Flock Tree" section on dashboard
- [ ] Invitation-chain badge display on profile
- [ ] Achievement milestone share prompt to followers
- [ ] "[Name] just hit 30 days!" feed entry in Following filter

**Gamification**:
- [ ] Shepherd / Lead Shepherd / Flock Builder badges
- [ ] Mutual follow count badge (`mutual_10`)
- [ ] First follow / first follower badges

**Tests**:
- [ ] Flock tree context tests
- [ ] Notification delivery tests

---

## 10. What to Re-use (Do NOT Rebuild)

| Existing component | Re-use for |
|-------------------|-----------|
| `StudentGuardian` invite flow | Pattern reference only — do NOT reuse code; peer invites have different logic |
| `ProofCard.share_token` | Token generation pattern — replicate in `social_invites` |
| `ShareButton` component | Use for course share and invite link copy |
| `Gamification.XpEvent` | Add `social_follow`, `study_buddy` sources |
| `Accounts.get_user_role!/1` | Profile page data loading |
| Flock leaderboard cards | Extend with follow state; don't rewrite card UI |
| School affinity scoring | Reference logic for suggested_follows ordering |

---

## 11. Existing Peer-Sharing Alignment

This document extends `funsheep-peer-sharing.md` (the proof card / result sharing spec). That document covers:
- Sharing academic results (proof cards) with non-users
- Parent-to-parent referral sharing via KakaoTalk, WeChat
- Channel-aware copy strategy

This document covers the orthogonal concern:
- Building the peer social graph between existing users
- Discovery and follow mechanics
- Shared study relationships

Both are needed. Neither replaces the other. Build this document's features first (social graph) so that `funsheep-peer-sharing.md`'s proof card shares can travel through a real social graph rather than just a share link to the void.

---

## 12. Roadmap Entry

Add to `docs/ROADMAP.md` (Social & Growth section):

```
| [PLANNED] | Social Friends & Followers (follow graph, school directory, invites, course sharing) | [funsheep-social-friends-strategy.md](ROADMAP/funsheep-social-friends-strategy.md) |
```

---

*Last updated: 2026-04-24. Status: Planning.*

---

## Implementation Checklist

> All phase tasks above already use `- [ ]` checkboxes. This section summarizes overall phase status for quick reference.

### Phase 1 — Social Graph Foundation ⬜ Not started (0%)

No implementation exists. No `social_follows` migration, no `FunSheep.Social` context, no follow/unfollow logic. All tasks in §9 Phase 1 are pending.

### Phase 2 — Discovery & Invitations ⬜ Not started (0%)

Depends on Phase 1. No `social_invites` migration, no suggested-follows logic, no "Find Friends" tab.

### Phase 3 — Course Sharing & Study Buddies ⬜ Not started (0%)

Depends on Phase 1. No `course_shares` migration, no study buddy XP bonuses, no sharing UI.

### Phase 4 — Viral Amplification ⬜ Not started (0%)

Depends on Phases 1–3. No flock tree logic, no social achievement broadcasts.
