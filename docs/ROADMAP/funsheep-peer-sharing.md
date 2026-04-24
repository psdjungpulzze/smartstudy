# FunSheep — Peer Sharing (Student↔Student and Parent↔Parent): Implementation Prompt

> **For the Claude session implementing this feature.** Read the whole document before coding. The trigger-moment and copy-strategy sections in §4 and §5 are the leverage of this feature — the plumbing exists already, so 80% of the work is *choosing the right moments* and *writing the right copy*. Both are load-bearing.

---

## 0. Project context

FunSheep is a Phoenix 1.7 / Elixir / LiveView test-prep product. Standard stack (same as sibling prompts). Read:

- `/home/pulzze/Documents/GitHub/personal/funsheep/CLAUDE.md` — especially **ABSOLUTE RULE: NO FAKE, MOCK, OR HARDCODED CONTENT**
- `.claude/rules/i/ui-design.md`, `.claude/rules/i/code-style.md`, `.claude/rules/i/visual-testing.md`, `.claude/rules/i/security.md`
- Sibling prompts in `~/s/`: `funsheep-parent-experience.md`, `funsheep-teacher-experience.md`, `funsheep-subscription-flows.md`

---

## 1. What already exists (do NOT rebuild)

| Concern | Where | Notes |
|---|---|---|
| Proof card schema | `FunSheep.Engagement.ProofCard` + `proof_cards` table | Card types: `readiness_jump`, `streak_milestone`, `weekly_rank`, `test_complete`, `session_receipt`. Has `share_token`, `metrics` JSON, `shared_at`. **Re-use; extend card types if needed.** |
| Proof card LiveView | `FunSheepWeb.ProofCardLive` | Renders a card by token. Public route: `/share/progress/:token`. |
| Share button | `FunSheepWeb.ShareButton` | Uses Web Share API (`navigator.share()`) on mobile → native share sheets; clipboard fallback on desktop. 4 styles: `:button | :icon | :compact | :fab`. **Re-use.** |
| Guardian / class invites | `FunSheep.Accounts.StudentGuardian`, `FunSheepWeb.GuardianInviteLive` | Email-based invite flow. **Re-use for parent referral.** |
| Gamification | `FunSheep.Gamification` | XP, streaks, achievements. **Re-use as trigger sources.** |
| Assessments / readiness | `FunSheep.Assessments` | Readiness snapshots, trends, percentile. **Re-use as trigger sources.** |

### What's missing

1. **Trigger engine** — nothing listens for "this just happened — is it share-worthy?" Share cards are user-pulled today, not event-pushed.
2. **Parent-side proof cards** — the existing types are all student-facing. No card renders "my kid went from 42% to 78% on algebra readiness in 6 weeks."
3. **Help-a-friend loop** — no "my friend should try this one" share path.
4. **Referral program** — no incentive structure tying a share to a new signup to a reward for the sharer.
5. **Channel-aware copy** — share text is generic. Sending the same string to a Korean mom's Kakao group and a teen's Snapchat story is a miss.
6. **Measurement** — no telemetry on share rates, share→install rates, or viral coefficients.

---

## 2. Strategic frame: peer sharing is the zero-CAC growth engine

Three sibling documents already exist in this directory. They describe how FunSheep acquires users (Parent: §1-onboarding, Teacher: §1-classroom, Subscription: Flow B parent-initiated and Flow C teacher-initiated). Those are *paid or direct* acquisition paths. This document is the *organic* acquisition path — and in EdTech specifically, it is the highest-leverage one:

- Duolingo's badge system introduction produced a **116% jump in referrals**. Achievements became social currency.
- Duolingo's gamification creates "dozens of referral moments daily" — streak milestones, league promotions, achievement badges — each designed for sharing.
- For Asian-immigrant parent networks, academic-product recommendations travel through **KakaoTalk / WeChat group chats faster than any paid channel**. One tiger-mom's endorsement in a 40-person school-parent Kakao group can produce double-digit signups in hours.

**The core thesis of this document:**

> Peer sharing in FunSheep should not feel like a referral program. It should feel like the two things sharers already want to do — *kids want to boast to friends, parents want to recommend what worked* — with FunSheep as the substrate. The referral reward is the cherry on top, not the bribe.

Duolingo's internal principle: *"the best mobile referrals do not feel like referrals at all — they feel like sharing something interesting with friends."* Adopt that principle.

### 2.1 Two distinct psychological engines

This document has to do two different products in parallel, because the sharers have **almost nothing in common**:

| Dimension | Student | Parent |
|---|---|---|
| Motivation | Identity, belonging, status, helping a friend | Anxiety, status, genuine recommendation |
| Preferred channel | Snapchat, Instagram Stories, Discord, iMessage, TikTok | KakaoTalk, WeChat, WhatsApp, Facebook Groups, iMessage, email |
| Audience size | Close circle (76% of Gen Z prefer close-circle sharing) | 20–100+ parent group chats |
| Tone | Restrained, self-enhancing, authentic, meme-literate | Proud, solution-sharing, mildly competitive |
| Trigger sensitivity | High — wrong moment = cringe = churn | Moderate — wrong moment = ignored, not toxic |
| Anti-pattern | Leaderboards that shame, cheesy over-celebration, broadcast-style brags | Leaderboards by name, guilt framing, anything that looks like sponsored-post |

Design the student and parent surfaces **independently**. Sharing the same code path between them will produce a compromise that converts neither.

---

## 3. Design principles (non-negotiable)

1. **Share is a consequence of a real event, never a foregrounded ask.** No "refer a friend" banner at the top of the dashboard. Share CTAs appear in the flow of an achievement the user just earned.
2. **Timing > copy > incentive.** The right moment with mediocre copy and no reward beats the wrong moment with great copy and a $10 coupon.
3. **Add value to the recipient, not just the sender.** The share link should land the recipient somewhere useful — a practice challenge they can try, a proof card they can learn from, a parent resource — not a pure "sign up for FunSheep" page.
4. **Close-circle defaults, broadcast-optional.** Gen Z prefers DM-style sharing (iMessage / Snap direct / Discord DM) over broadcast feed posts. Default the share surface to close-circle; don't push broadcast.
5. **Honest evidence on every shared card.** Per `CLAUDE.md`: never inflate, never round suspiciously. If a streak is 4 days, show 4. If a readiness jump is 7 points, show 7.
6. **No leaderboards of named peers.** Per the parent-experience and teacher-experience docs, this is a FERPA / social-harm landmine. Percentile against an anonymised cohort is fine; named rankings against classmates are not.
7. **Student safety first.** A student's share link must never expose the student's email, last name, school, or exact age. Cards render display-name-only with optional emoji or mascot. Proof cards do not deep-link into the student's account — they are read-only public pages.
8. **Teachers do not appear in the sharing loop.** They neither receive the parent-side shares nor the student-side shares. Their attention bandwidth is elsewhere (see `funsheep-teacher-experience.md`).
9. **Frequency caps, not blanket suppression.** A student who just hit three milestones in a day should not get three share prompts. Soft-rate-limit per surface per day.
10. **Visual verification mandatory.** Particularly for share cards rendered as OG images — they must look clean at 1200×630 on every major social preview.

---

## 4. Student-to-Student sharing

### 4.1 Psychology (what actually motivates a 10-17-year-old to hit share)

From adolescent-development research (Springer *Social media: a digital social mirror*; PMC *Adolescent peer relations in social media context*; Gen-Z sharing studies):

1. **Identity construction.** Sharing is how teens *tell themselves and their friends who they are.* A "I'm the kind of person who practises math every day" share cements that identity.
2. **Self-enhancement through imaginary audience.** Adolescents feel watched. Positive impressions increase positive self-view.
3. **Peer belonging.** The single strongest drive — wanting to feel accepted by the group.
4. **Helping-impulse is real and under-leveraged.** In peer-tutoring studies, "I agree peer tutoring would help me stay focused" rose from 20% → 83% post-participation. Kids like helping each other when the mechanics are clean.
5. **Close-circle bias.** 76% of Gen Z prefer sharing life updates with a close circle, not broadcast.
6. **Authenticity over curation.** 80% trust relatable stories more than celebrity endorsements. Over-polished cards look like ads.
7. **Mental health fragility.** Same population has elevated anxiety and depression. Leaderboard-style shame is not a neutral "motivator" — it can cause real harm. Design away from zero-sum framings.

### 4.2 When — the trigger moments

Ship trigger-based share prompts for these events. Each is a real, evidence-backed moment; do not invent fake triggers.

| # | Trigger | Data source | Share-card type | Frequency |
|---|---|---|---|---|
| 1 | **Readiness jump** (≥10 points on any chapter or test scope in ≤14 days) | `readiness_scores` diff | `readiness_jump` (exists) | Max once per scope per month |
| 2 | **Streak milestone** (3, 7, 14, 30, 60, 100, 365 days) | `streak` | `streak_milestone` (exists) | Once per milestone |
| 3 | **Personal best** on a practice session (accuracy ≥ rolling 30-day avg + 10% AND ≥ 10 questions) | `study_sessions` | New type: `personal_best` | Max once per 7 days |
| 4 | **Topic mastery** (first time a chapter moves from <50% to ≥85% mastery) | `readiness_scores.chapter_scores` diff | New type: `topic_mastered` | Per chapter, first-time only |
| 5 | **Daily challenge win** (correctly solved) | `daily_challenge_attempts` | `session_receipt` (exists) | Max once per day |
| 6 | **Test day — readiness ready** (≥80% readiness on test scope within 48h of `test_date`) | `readiness_scores` + `test_schedules` | New type: `test_ready` | Once per test |
| 7 | **Comeback** (resumed a streak after a break of ≥ 3 days, now at ≥ 3 new days) | `streak` history | New type: `comeback` | Max once per 14 days |
| 8 | **Help-a-friend moment** (student encountered a question they found notable — manual CTA below a question result) | Student initiative | New type: `challenge_invite` | Unlimited (low rate in practice) |

**Trigger implementation**:
- New module `FunSheep.Engagement.ShareTriggers` — one function per trigger type, pure-functional: given the just-happened event and recent context, returns `{:suggest, card_type, metrics}` or `:skip`.
- `ShareTriggers.evaluate/1` is called from the places where events already happen — `StudySessions.finalize/1`, `Gamification.award_streak/1`, `Assessments.calculate_readiness/2`. No polling.
- Suggestions are buffered per user per day and deduplicated — if three triggers fire in one session, only the highest-intensity one surfaces. Tie-break: the trigger with the largest numeric delta.

### 4.3 What — share-card formats (the artefact that goes out)

The **shared thing** determines the share rate. Ship two layers:

#### 4.3.1 Proof cards (existing + extended)

Public read-only page at `/share/progress/:token`. Extend the existing `ProofCard` with:

- Rich OG image at 1200×630 (the link preview in Snapchat / iMessage / Discord)
- Mobile-first single-screen layout for direct viewing
- A subtle, age-neutral "Try FunSheep" CTA at the bottom (not a giant "SIGN UP NOW" button — per design principle #1)
- Optional "🦁 challenge me" inline button if `card_type == :personal_best` or `:topic_mastered` (links to a public practice session seeded with real questions from the same topic — §4.6)

Design the OG images to be **sharer-flattering, not brand-flattering**. The student's name (display_name only), their number, and a clean visual. FunSheep logo is small.

#### 4.3.2 Ephemeral formats for specific platforms

Kids don't post a URL to Snap; they post an image. Generate **platform-optimised artefacts**:

- **Snap / IG Story format** (9:16, 1080×1920) — stickery, with the metric centred, no URL (URLs don't render on Stories anyway; code them to use the share-text field with a shortlink)
- **iMessage / Discord format** — horizontal card with OG preview (1200×630)
- **TikTok format** — not an image; a suggested video script and a downloadable 6-second MP4 render of the metric with animated numbers (defer to Phase 2 — ship images first)

Implementation: server-side render OG images via a headless browser (the `Playwright` service may already be used in the interactor workspace — check before bringing in `chromic_pdf` or `wkhtmltopdf`). Cache images by `share_token`.

### 4.4 How — channels

The existing `ShareButton` uses the Web Share API, which surfaces native share sheets on mobile (iOS/Android). This is already correct for most kids — they'll see Snap, iMessage, Instagram, Discord, TikTok in the native sheet.

Extensions:

- **Desktop fallback**: the existing clipboard-copy is fine. Add a small "Copy image" button beside "Copy link" for kids who want to paste the card artwork into a Discord message.
- **Copy-link toast**: when the clipboard path is used, show a friendly toast — "Link copied 📋 — paste into Snap, Discord, or wherever."
- **Pre-composed DM**: for iOS, pre-fill the share *text* so when a kid picks "iMessage" the message body is ready. Text length ≤ 60 chars (anything longer gets truncated by iMessage preview).

### 4.5 Copy strategy for the student share

Kids under 18 smell "corporate voice" instantly. The copy must read like a peer wrote it. Guardrails:

- **Never exceed 2 emoji** in any single share string
- **No exclamation stacking** ("!!!")
- **First person, present tense**: "just hit 30 days straight 🦁" not "I achieved a 30-day streak"
- **Pair with a challenge** when it fits: "beat this: [topic]"
- **Never announce the brand in the share text** — the OG preview carries that. The share text is the *kid's voice*.

Sample strings per trigger (ship as a pool; A/B test):

Streak 7: "one full week streak 🦁 who's next"
Streak 30: "thirty days in. practising more than i ever did for any real class fr"
Personal best: "just locked in my best score on [topic] — come beat me"
Topic mastered: "i get fractions now. wild. [link]"
Readiness jump: "went from 52 → 74 on algebra readiness in two weeks. ok i'm competing"
Test ready: "[test name] tomorrow. i am ready."
Comeback: "back on the streak after a week off. redemption arc."
Challenge-invite (manual): "this question got me. try it — [link]"

Show the student 2-3 pre-composed options in the share modal; let them edit freely. **Do not auto-send.**

### 4.6 The help-a-friend loop (this is the feature that differentiates)

Most EdTech share flows are just "brag." The *help-a-friend* format is underused and aligns with the helping-impulse finding. Build:

**"Challenge a friend"** — visible on:
- Any question result screen (✅ correct or ❌ wrong)
- Any topic-mastered card
- Any personal-best card

Flow:
1. Student taps "Challenge a friend on this"
2. FunSheep generates a public practice link that serves **3-5 real questions from the same topic** at a difficulty near the original
3. The recipient lands on a no-login-required practice page, can try the questions, sees their score vs. the sender's score at the end, and is offered a gentle "Make FunSheep yours" CTA (not forced)
4. Sender gets a notification when a friend tries it — "Your friend Mia just tried your challenge on Fractions and scored 4/5"
5. If the friend signs up and becomes active, credit the sender toward a referral reward (§6)

**Why this is the most powerful share type**:
- The recipient gets **a real product moment** (trying actual questions), not a marketing landing page
- The sender gets **social proof** when the friend responds
- It converts the share from "me flexing" to "me helping my friend try this cool thing"
- It creates a reply loop — friend sends a challenge back

**Implementation**:
- New schema `challenge_invites` (id, sender_student_id, source_question_id or topic_id, question_ids jsonb snapshot, recipient_identifier nullable, attempts jsonb, created_at, expires_at)
- Snapshot question IDs at invite creation so the challenge stays stable if the question bank changes
- Expiry 14 days
- Public challenge page at `/challenge/:token` — no auth required, stores attempt as anonymous guest if the recipient isn't signed in
- Rate-limit by sender (max 10 active challenges)

### 4.7 Student anti-patterns (things that will backfire immediately)

- **Named-classmate leaderboards**. Will cause bullying, parent complaints, and district-level blocks. Never ship.
- **Streaks that shame on break.** Duolingo's guilt-tripping owl is a *controversial* choice; for younger students it crosses into harm. Keep streak-break messaging *neutral* ("pick it back up whenever" not "you're disappointing me").
- **Auto-share.** Never share without explicit tap. Any dark pattern will cost trust.
- **Over-celebration for teens.** Confetti + mascots = great for 8-year-olds, embarrassing for 14-year-olds. Detect age (grade) and scale celebration accordingly — restrained by default for grade ≥ 8.
- **Forcing real names or classmates.** Display-name only; no contact-list scraping.
- **Broadcast prompts ("share to your feed!").** Default to close-circle; broadcast is a secondary option at best.

---

## 5. Parent-to-Parent sharing

### 5.1 Psychology (what motivates a parent — especially a high-investment / tiger mom — to recommend)

From parenting-network research (WeChat/Kakao parent groups; Peanut / Facebook mom group studies; tiger-mom literature referenced in `funsheep-parent-experience.md`):

1. **Academic anxiety is the driver.** Parents in high-investment networks share products that promise to reduce their anxiety about their child's performance.
2. **"My kid is my report card."** Sharing a product that produced measurable progress is a **proxy for displaying parental competence.** This is not cynical — it's how the social dynamic actually works.
3. **Status display is present but not the whole story.** Kakao / WeChat school-parent groups famously have brownnosing-and-bragging dynamics. A small fraction of parents will over-share to signal status. A much larger majority will genuinely recommend something that worked.
4. **Solution-sharing is the native format.** "This helped my kid" > "My kid is a genius" — the latter invites eye-rolling, the former invites DMs asking for details.
5. **Trust via specifics.** Parents trust recommendations with specifics: the test my kid took, the score change, the time invested, the month. Vague "it's great!" converts worse.
6. **Network shape is everything.** Asian-immigrant parent networks tend to run on **group chat** (Kakao, WeChat, LINE, WhatsApp family/school groups) — a single share into the right group can touch 40+ parents. Western networks run more on **Facebook groups** (broader, weaker-tie) and **iMessage group texts** (narrow, strong-tie).
7. **School-parent groups are the highest-intent audience.** A share into "Room 204 Parent Group" targets parents whose kids have the exact same teacher, curriculum, and upcoming tests. Convert-by-relevance is maximum here.

### 5.2 When — parent trigger moments

| # | Trigger | Data source | Share-card type |
|---|---|---|---|
| 1 | **Kid hit target score** on a scheduled test | `readiness_scores` vs `test_schedules.target_score` | `child_test_ready` (new, parent-flavour) |
| 2 | **4-week readiness-improvement milestone** (kid's readiness trend has risen ≥ 15 points over rolling 4 weeks) | `readiness_scores` history | `child_progress_milestone` (new) |
| 3 | **Kid's first goal achieved** (a `study_goal` in `:active` transitioned to `:achieved`) | `study_goals` (from Parent-experience Phase 3) | `goal_achieved` (new) |
| 4 | **End-of-term report** (kid completed a full term / significant date) | Scheduled via Oban | `term_report` (new) |
| 5 | **Right after subscription activation** — parent just said yes, satisfaction peak | Webhook from checkout | `just_upgraded` (new, lower-intensity — see §5.3) |
| 6 | **Parent-initiated** — any time from the parent dashboard, the parent chooses to generate a shareable card from their child's progress | Manual | Any of the above |

**Do not** trigger #5 aggressively — a parent who just paid wants to tell their kid, not their WeChat group. Offer it as a soft, dismissible suggestion ("Your friends might find this helpful — share a quick note?"), not a blocker.

**Do** invest most effort in trigger #2. This is the most common and most effective moment — the kid is visibly improving, the parent feels vindicated, the recommendation is genuine.

### 5.3 What — parent share-card formats

Parent cards are **evidence-first**, not mascot-first. The visual language differs from student cards:

- Clean, professional typography (parents share into professional-ish contexts — workgroup chats often cross personal/work)
- **Numbers front-and-centre** with time-range context ("Mastery: 47% → 82% in 6 weeks")
- Minimal mascot; FunSheep logo small and bottom-right
- Subtle, respectful "See what FunSheep can do" CTA with referral-coded link

Offered in three lengths to match channel norms:
- **Short card** (for iMessage / WhatsApp 1:1) — image + one-line caption
- **Medium card** (for Kakao/WeChat group chats) — image + 2-3 line personal note field (editable by parent before send) + link
- **Long form** (for Facebook group posts) — image + multi-paragraph personal story template + link

### 5.4 How — channels

Web Share API works for iMessage / WhatsApp / Kakao / LINE on mobile. On desktop, parents often compose group messages in browsers — provide:

- **"Copy for Kakao" / "Copy for WeChat" / "Copy for WhatsApp" / "Copy for Facebook"** buttons that copy channel-optimised text + link formats. Each channel has different preview behaviour; test in dev.
- **Email** template (for parents who prefer forwarding)
- **QR code** generation — useful for in-person moments (pickup line conversations, PTA meetings) where a parent wants another parent to just scan

### 5.5 Copy strategy for parent shares

Parent copy has to thread a needle: sound genuine (not marketing), share real evidence (not brag), and make the next parent's decision easy.

#### 5.5.1 Tone variants by channel

| Channel | Tone | Length | Emoji |
|---|---|---|---|
| Korean Kakao parent group | Warm, humble-proud, specific | 2-3 lines | Minimal — 1 at most |
| Chinese WeChat parent group | Direct, evidence-first, respectful | 2-4 lines | 0-1 |
| WhatsApp parent group (mixed Western/Asian) | Friendly, specific, no hype | 2-3 lines | 1-2 |
| US Facebook parent group | Conversational, slightly longer story | 3-6 lines | 1-2 |
| iMessage 1:1 | Casual, intimate | 1 line | 0-1 |
| Email | Formal, contextual | 1 short paragraph | 0 |

#### 5.5.2 Message templates (editable before send — parent sees suggestion + can modify)

**Korean tone (translation-ready):**
> "아이가 [test name] 대비하는데 FunSheep 써봤는데 6주만에 47% → 82% 올랐어요. 참고하세요~ [link]"

(English for the implementer: *"My kid used FunSheep to prep for [test name] — readiness went from 47% to 82% in 6 weeks. Sharing in case it helps~"*)

Ship both localized strings (Korean, Chinese Simplified) and English equivalents; the translations should be done by a native speaker, not AI — an awkward translation in a Kakao group will mark the product as inauthentic instantly. Flag this as a pre-launch task.

**English / Western Asian-American tone:**
> "Sharing in case anyone else is prepping for [test name] — [kid name]'s readiness went from 47% → 82% in 6 weeks on FunSheep. 20 min/day. Worth a look. [link]"

**WhatsApp group casual:**
> "Anyone else on [test]? We've been using FunSheep and [kid name]'s readiness is up 35 points in 6 weeks. Happy to share details [link]"

**Facebook long-form:**
> "Hey moms — wanted to share something that worked for us. [Kid name] was at about 47% readiness for the [test] and was really frustrated. We tried FunSheep (an AI test-prep thing, free tier first) and they actually got into it — now at 82% six weeks later. About 20 minutes a day. Not sponsored, just genuinely helped. Link if anyone wants to try: [link]"

#### 5.5.3 Critical copy rules

- **Always include real numbers from the parent's actual child.** Never a generic "helps kids improve." Pull from the proof card's `metrics` field.
- **Always include the specific test name** if there is one. Generic EdTech shares don't convert; specific prep shares do.
- **Never imply tutoring, certification, or credentials we don't have.**
- **Never imply a ranking or percentile against named classmates.**
- **Always show the parent the message before it goes out** and let them edit every word. Pre-composed ≠ auto-sent.
- **Never shame the parent into sharing** ("Good moms share this with friends"). Purely voluntary, clearly low-pressure.
- **Localization is non-negotiable for Kakao/WeChat.** A machine-translated Korean share will kill credibility — native-speaker review required before launch.

### 5.6 Tiger-mom network amplifiers (the high-leverage lever)

A tiger mom in a school-parent Kakao group who says "this worked for us" has conversion power that exceeds any paid channel FunSheep will ever buy. Two specific mechanisms to design for:

#### 5.6.1 School-parent group unlock

If a parent shares into what is clearly a school-parent group (detected by: ≥3 parents in the same group signing up via that share token within 72 hours, OR the sharer manually tags the share as "school group"), the product can:

- Offer the original sharer a **bonus referral reward** ("we notice you helped several parents in your community — here's 6 months free")
- Offer the **incoming parents a slight bonus** ("welcomed by {{sharer's kid's display name}}'s parent — 2 free weeks")
- Create a lightweight **group presence** — a shared "parent circle" where these connected parents can see group-level aggregate stats (no named leaderboards, just "your circle has a 14-day avg practice of X"). Opt-in only.

This is the Kakao / WeChat virality pattern formalized. Be careful with FERPA implications — never expose individual students in the group view.

#### 5.6.2 "What worked" prompt at conversion satisfaction

At the 4-week mark after conversion (long enough for real progress, short enough that satisfaction is still fresh), email the parent a "your kid's first month on FunSheep" summary with real numbers. The email's final CTA is a low-key:

> Know another parent prepping for [test name]? This summary is shareable — just tap.

No pressure. No reward (at this stage). Just a clean, evidence-filled artifact that a proud parent may forward to one group. A single genuine "here's what worked for us" forward beats any 10% discount banner.

### 5.7 Parent anti-patterns

- **Auto-posting to the parent's Facebook/Kakao on their behalf.** Ever. This is OAuth-integration territory and privacy poison.
- **Scraping the parent's contact list** to suggest recipients.
- **Referral leaderboards among parents** ("Mrs. Chen has referred 14 parents!"). Creeps out the community, triggers drop-off in status-sensitive networks.
- **Discount-or-dark-pattern framing** ("Share now or pay full price!"). Destroys trust.
- **Using the child's data in ways the parent didn't explicitly approve.** Share cards render only data the parent chose to include.

---

## 6. The referral program (the connecting tissue)

Now that student shares and parent shares exist as real events, tie them together with a clean, honest reward structure. This is where shares become signups.

### 6.1 Attribution

Every share generates a URL with an embedded referral token tied to the sharing `user_role_id` and the `proof_card` / `challenge_invite` / parent share event. Track:

- **Click** — someone opened the link
- **Signup-attributed** — a new account created with that token within 30 days
- **Active-attributed** — the new user completed at least 5 practice sessions
- **Converted-attributed** — the new user (or their parent) became a paid subscriber

Attribution window: 30 days from click → signup; lifetime from signup → conversion.

### 6.2 Reward structure

Keep it simple — three tiers, both sides get value.

| Event | Sharer reward | New user reward |
|---|---|---|
| Friend signs up via student share and becomes active | 1 month free *for the new user* (not the sharer — reduces incentive gaming) | 2 weeks free |
| Parent shares → new parent signs up + adds their child + child becomes active | 1 month free for the referring parent's child | 2 weeks free for the new family |
| Parent shares → new parent converts to paid | 3 months free for the referring parent's child | (paid already — reward was the product experience) |

**Why "free for the new user" on the kid side**: giving kids rewards for referrals trains gaming behaviour and fake invites. Giving the *recipient* the reward keeps the share genuine — the kid is helping a friend get a perk.

**Why caps**: max 6 months of free time accrued from referrals in any 12-month window per user — prevents degenerate farming.

### 6.3 Reward delivery

- Rewards fire automatically when the attribution event triggers (Oban worker monitors)
- In-app notification plus email
- Reward is applied as a subscription credit via `FunSheep.Billing` / Interactor Billing — reuse the existing billing system, do not build a new credits table

### 6.4 Fraud / gaming resistance

- One referral reward per unique device + email combination
- Block self-referrals (same household detected by shared surname + household IP — soft signal; false positives ok)
- Rate-limit to N successful referrals per week to slow farms
- Log all reward issuances for admin audit

---

## 7. Data model additions

### 7.1 Extend `proof_cards.card_type`

Add to the existing enum:

```
@card_types ~w(
  readiness_jump streak_milestone weekly_rank test_complete session_receipt
  personal_best topic_mastered test_ready comeback
  child_test_ready child_progress_milestone goal_achieved term_report just_upgraded
)
```

First line = existing (preserve); second = new student types; third = new parent types.

### 7.2 New `challenge_invites` schema

```
challenge_invites
  id (uuid)
  sender_user_role_id -> user_roles.id
  source_question_id -> questions.id (nullable — challenge from a specific question)
  topic_id :: uuid (nullable — challenge on a topic)
  question_ids :: array of uuid (snapshot of 3-5 questions at invite creation)
  token :: string (unique, URL-safe)
  sender_score :: integer (nullable — sender's score that seeded the challenge)
  attempts :: jsonb (anonymous attempts: [{token, score, completed_at}, ...])
  expires_at :: utc_datetime (14 days from creation)
  shared_at :: utc_datetime (first time share modal was confirmed)
  inserted_at, updated_at
```

Route: `/challenge/:token` — public, no auth. Attempt stored in `attempts` JSON with a session cookie as anonymous identifier.

### 7.3 New `referrals` schema

```
referrals
  id (uuid)
  referrer_user_role_id -> user_roles.id
  referred_user_role_id -> user_roles.id (nullable until signup)
  source_type :: enum(:proof_card, :challenge_invite, :parent_share)
  source_id :: uuid (id of the proof_card, challenge_invite, or share event)
  token :: string (unique — the referral code in the URL)
  clicked_at :: utc_datetime (nullable — first click)
  signed_up_at :: utc_datetime (nullable)
  became_active_at :: utc_datetime (nullable)
  converted_at :: utc_datetime (nullable — paid)
  reward_status :: enum(:pending, :awarded, :denied, :capped)
  awarded_credit_months :: integer (nullable)
  inserted_at, updated_at
```

Indexes: `(referrer_user_role_id)`, `(token)` unique, `(referred_user_role_id)`.

### 7.4 Trigger-suggestion buffer

```
share_suggestions
  id (uuid)
  user_role_id -> user_roles.id
  card_type :: string
  source_metrics :: jsonb  (evidence — e.g., {from: 52, to: 74, scope: "algebra"})
  triggered_at :: utc_datetime
  surfaced_at :: utc_datetime (nullable)
  dismissed_at :: utc_datetime (nullable)
  shared_at :: utc_datetime (nullable)   -- reference to the proof_card once created
  score :: float  (trigger strength — 0..1, used for dedup when multiple fire same day)
  inserted_at, updated_at
```

Worker: `FunSheep.Workers.ShareSuggestionSurfaceWorker` runs every 15 min, picks at most 1 pending suggestion per user to surface, respecting frequency caps.

### 7.5 Telemetry events (no schema — just events)

- `share.trigger_evaluated` `{user_role_id, card_type, decision}`
- `share.suggestion_surfaced` `{suggestion_id, card_type}`
- `share.suggestion_dismissed` `{suggestion_id}`
- `share.card_created` `{proof_card_id, card_type, user_role_id}`
- `share.link_clicked` `{referral_token}`
- `share.signup_attributed` `{referrer_id, referred_id, source_type}`
- `share.reward_awarded` `{referral_id, months_credited}`

Feed into existing telemetry stack.

---

## 8. UI surfaces (new or modified LiveViews)

### 8.1 Student

- **Post-event share suggestion overlay** — modal that appears after a triggering event (session finalize, streak award) with the proposed card, 2-3 pre-composed captions, and two buttons: "Share" (opens native share sheet) / "Maybe later" (dismiss)
- **Dashboard "moments" shelf** — small horizontal scroll of recent share-worthy events from the last 7 days that the student didn't share — one more chance, then expire. Dismissible per-card.
- **Question-result "Challenge a friend"** — inline button under the correct/wrong indicator on any question completion, not just the ones that fire a milestone trigger (manual CTA)

### 8.2 Parent

- **Dashboard "share this" card** — appears after a qualifying progress milestone (§5.2 triggers) — dismissible, time-bound
- **One-click "Copy for {{channel}}" menu** — Kakao / WeChat / WhatsApp / Facebook / iMessage / Email
- **"Your impact" section** (lower-priority, secondary) — shows the parent which of their shares led to active or converted new users, as a warm acknowledgement. Never a gamified leaderboard.

### 8.3 Public

- **`/share/progress/:token`** — exists, extend with richer OG, challenge-me inline button for applicable card types
- **`/challenge/:token`** — new — public practice session with 3-5 real questions; anonymous guest attempt tracked; end-of-challenge result vs sender's score; gentle signup CTA

---

## 9. Measurement

Core funnel (student and parent tracked separately):

```
Trigger fires
  → Suggestion surfaced        (surface rate)
  → Share modal opened          (open rate)
  → Card created (share taken)  (share rate)
  → Link click                  (click-through rate)
  → Signup                      (signup conversion)
  → Active                      (activation)
  → Paid (parent only)          (monetisation)
```

Track **viral coefficient (K)** monthly: average new active users per active user via shares. K > 1 = self-sustaining growth. K = 0.2 in year 1 is an excellent EdTech result.

### Sensitive-metric guardrails

Do not A/B-test manipulative variants (fake urgency, artificially inflated numbers, shame framing). A/B testing is for genuine copy / timing variants only.

---

## 10. Ethical guardrails

These are non-negotiable; revert anything that violates them:

1. **Every shared number is real.** No inflation. No rounding tricks.
2. **Students under 13** — proof cards are redacted to initials or display-name only; challenge invites do not expose email; parent must consent once at onboarding to the child sharing proof cards at all (per COPPA — school consent or parent consent).
3. **No named-peer leaderboards.** Cohort percentile bands fine; "Emma beat Sarah" never.
4. **No dark-pattern referral rewards** (fake scarcity, countdown timers, social-proof fabrication).
5. **No guilt framing on either side.** "Don't let your friend miss this" = not ok.
6. **Never auto-post.** Always requires an explicit tap at share time, and the message is always editable before send.
7. **Never share without the user seeing the outgoing content.** Preview-then-send, every time.
8. **Sender controls removal.** A share card can be revoked by the sender at any time — makes the `/share/progress/:token` 410 Gone page.
9. **Reward fairness.** Referral reward goes to the *recipient* for student shares, preventing gamified fake-friend spam.
10. **Localization quality.** Korean, Chinese, and other non-English share copy must be reviewed by a native speaker before launch. Machine-translated copy going into a Kakao mom group is a trust-destroying event.

---

## 11. Phased delivery

1. **Phase 1 — Trigger engine + student share suggestions (student-only)**
   - `ShareTriggers` module with all 8 triggers (§4.2)
   - `share_suggestions` schema + surfacing worker
   - Share suggestion overlay on student dashboard
   - Extend proof card with new types (`personal_best`, `topic_mastered`, `test_ready`, `comeback`)
   - OG image rendering for proof cards
2. **Phase 2 — Help-a-friend (challenge invites)**
   - `challenge_invites` schema + public `/challenge/:token` page
   - Challenge CTA on question results
   - Signup funnel from challenge page
3. **Phase 3 — Referral attribution + reward engine**
   - `referrals` schema + tokens on every share URL
   - Attribution tracking (click / signup / active / converted)
   - Automated reward issuance via `FunSheep.Billing` (credit months)
   - Fraud / cap enforcement
4. **Phase 4 — Parent share surfaces**
   - Parent-flavour card types (`child_progress_milestone`, etc.)
   - Parent dashboard share cards
   - Channel-specific copy ("Copy for Kakao / WeChat / WhatsApp / FB")
   - QR code export
5. **Phase 5 — Parent network amplifiers**
   - 4-week post-conversion "what worked" email
   - School-parent group unlock (detection + bonus rewards)
   - Opt-in parent-circle group view
6. **Phase 6 — Localization + launch copy review**
   - Native-speaker review of Korean / Chinese / other locale copy
   - Per-locale tone variants wired into share modal
   - Channel-preview testing (Kakao, WeChat, WhatsApp, Snap, iMessage all render the OG cleanly)

Each phase ships as a separate PR. Coverage ≥ 80%, `mix credo --strict` clean, visual verification per `.claude/rules/i/visual-testing.md`.

---

## 12. What you must NOT do

- Do **not** build a parallel share or referral system — extend the existing `ProofCard` + `ShareButton` infrastructure
- Do **not** ship machine-translated Korean/Chinese copy — wait for native-speaker review
- Do **not** fabricate, round up, or embellish any number on a share card
- Do **not** expose student email, full name, school, or exact age on public share pages
- Do **not** auto-post to any social network via OAuth — not in scope, not desired
- Do **not** build named-peer leaderboards in any form
- Do **not** add referral rewards that scale unboundedly with referrals — cap per-user per year
- Do **not** send notifications encouraging a user to share who just dismissed a share prompt in the same session
- Do **not** show share prompts during a student's active practice session — always after completion
- Do **not** `mix compile` while the dev server is running (live reloader handles it)
- Do **not** start a test server on port 4040; use `./scripts/i/visual-test.sh start`

---

## 13. Questions to ask before starting

If any of the following are unclear after reading the code, ask the user before writing implementation:

1. Which grade bands is FunSheep currently shipping to? (Affects age-appropriate celebration tone, COPPA consent flow, and whether TikTok-style video cards should be prioritised.)
2. Is there an existing localization framework (gettext) seeded with Korean / Chinese, or will this feature introduce locale handling for the first time?
3. Who is the designated native-speaker reviewer for Korean and Chinese share copy? Can we schedule a review before shipping Phase 6?
4. Is the interactor-workspace Playwright service available for server-side OG-image rendering, or should we bring in a new dependency (`chromic_pdf` / similar)?
5. Is there a referral reward cap we should align with product marketing's plans (6 months free per year is the suggested default; PM may want tighter)?
6. Should school-parent group detection (§5.6.1) extend to admin-facing alerts ("this parent's share is going viral"), or stay behind the scenes?
7. Are there any contractual or compliance constraints around referral payments / credit that billing's legal team needs to bless?
8. Do we have analytics infrastructure already wired (telemetry events to a warehouse), or does this feature need to introduce it?

Answer these, then begin Phase 1.
