# FunSheep — Fun Animations Roadmap 🐑✨

> Vision: Every interaction should feel alive. The sheep is the heart of this app — it should react, celebrate, and commiserate with students at every step. This document maps out animations for every major page, ordered by impact.

---

## The Core Philosophy

Right now the UI is **clean but static**. The sheep mascot exists but mostly just sits there. The progress bars are bars. The numbers are numbers. The opportunity is huge: we can make FunSheep feel like a living, breathing study companion — not just another quiz app.

Think: Duolingo's owl, but woolier.

---

## 🏠 Dashboard — The Home Base

*What you saw: readiness progress bar (bare green fill, "0%" / "Golden Fleece 100%" labels), big "0 days left" counter, sheep mascot studying in top-right.*

### 1. Walking Sheep on the Readiness Progress Bar ⭐ HIGHEST IMPACT

**The idea**: A tiny sheep sits at the leading edge of the green readiness fill, walking in place as if trying to reach 100%. As readiness grows, it physically walks forward.

**Behaviors by readiness %:**
- `0–15%` — Sheep looks scared/worried, trembling ears, takes tiny hesitant steps
- `16–49%` — Normal walking pace, determined face
- `50–79%` — Slightly bouncy trot, ears up
- `80–99%` — Running! Legs cycle fast, a little sweat drop flies off
- `100%` — Sheep bursts into a happy jump and the bar turns golden (matching the "Golden Fleece" label)

**Tap to explain**: The sheep is not just decorative — it's tappable. Tapping it opens a "Why am I here?" bottom sheet that explains the student's readiness position and surfaces the top 3 weak topics with Practice CTAs. Full spec lives in `funsheep-readiness-by-topic.md` § 3.5.

**CSS approach:**
```css
@keyframes sheep-walk {
  0%   { transform: translateY(0px) rotate(0deg); }
  25%  { transform: translateY(-2px) rotate(-1deg); }
  75%  { transform: translateY(-2px) rotate(1deg); }
  100% { transform: translateY(0px) rotate(0deg); }
}

@keyframes sheep-run {
  0%   { transform: translateY(0px) scaleX(1); }
  50%  { transform: translateY(-3px) scaleX(1.05); }
  100% { transform: translateY(0px) scaleX(1); }
}
```

The sheep SVG is positioned absolutely at `left: calc({readiness}% - 12px)` on the bar track, and the walking animation speed is tied to readiness (slower when low, faster near 100%).

**Leg animation**: The 4 leg rectangles in the SVG get individual `animation-delay` offsets to create a realistic walking cycle.

---

### 2. "Days Left" Counter — Urgency Mode

**The idea**: The big "0 days left" number should FEEL urgent when it hits 0.

**Behaviors:**
- `≥ 7 days` — Static, calm, cool blue tint
- `3–6 days` — Number gently pulses (scale 1.0 → 1.05 → 1.0) in amber
- `1–2 days` — Fast heartbeat pulse, orange-red color
- `0 days (passed)` — The number trembles with a shiver animation, gray-out + a faint strikethrough

```css
@keyframes heartbeat {
  0%, 100% { transform: scale(1); }
  14%       { transform: scale(1.1); }
  28%       { transform: scale(1); }
  42%       { transform: scale(1.08); }
  70%       { transform: scale(1); }
}
```

---

### 3. Streak Flame — Real Fire 🔥

**The idea**: The `🔥 1` streak counter in the navbar uses an emoji — boring. Replace with an SVG flame that actually flickers.

The flame SVG has 2–3 layers with offset animation phases, creating a convincing flicker without JS.

**Bonus**: The flame grows taller as streak count increases (streak 1 = small flame, streak 30 = towering inferno).

---

### 4. FP/XP Counter Roll-Up

**The idea**: When Fleece Points change (after answering a question, after the daily goal is met), the counter doesn't just update — it rolls up like a slot machine odometer.

Each digit animates from old → new with a fast vertical scroll. The number briefly glows green on completion.

**When to trigger**: PubSub event → JS hook `FPCounterRollup` watches for DOM changes on the FP display element.

---

### 5. Daily Shear Card — Animated Shimmer

**The idea**: The purple Daily Shear gradient card has a slowly moving shimmer highlight traveling left-to-right every 3 seconds, making it feel premium and clickable.

```css
@keyframes card-shimmer {
  0%   { background-position: -200% center; }
  100% { background-position: 200% center; }
}
```

The scissors emoji `✂️` in the card also snips (rotates -30deg → 0deg) every time the shimmer passes over it.

---

### 6. Study Windows — Active Window Glow

**The idea**: The current active time window (morning / afternoon / evening) glows with a soft pulse. The inactive ones are clearly dimmed.

- Morning window at 9am: 🌅 icon has a warm golden glow
- Afternoon window at 2pm: ☀️ slowly rotates
- Evening window at 7pm: 🌙 has a cool silver shimmer

---

### 7. Empty State Sheep — Idle Breathing

**The idea**: When the student has no tests yet and sees the large empty-state sheep (`xl` size), it should breathe — the wool body gently scales up/down by ~2% on a 3s loop. Every ~15s it blinks (eyes close for 200ms).

This makes the first impression warm and alive instead of a static SVG dump.

---

## 🎯 Practice Mode — The Grind Loop

*What you saw: green progress bar at top, question card with MCQ options, chapter filter.*

### 8. Progress Bar Sheep — Footprints Edition ⭐

**The idea**: Same walking sheep as the dashboard bar, but in practice mode the sheep leaves tiny hoof-print dots behind it as it advances. The footprints fade out over ~2 seconds.

This gives students a physical sense of how far they've come. Each correct answer nudges the sheep forward — each question answered is a step.

**Extra touch**: At question 1/10, sheep looks fresh and clean. At question 8/10, a tiny sweat drop appears above its head. At 10/10, it breaks into a run and slides to a stop with a little dust cloud.

---

### 9. Question Card — Page-Turn Entrance

**The idea**: New questions don't just appear — they flip in like a textbook page being turned.

```css
@keyframes page-turn {
  0%   { transform: perspective(600px) rotateY(-90deg); opacity: 0; }
  100% { transform: perspective(600px) rotateY(0deg);   opacity: 1; }
}
```

Duration: 280ms. Feels snappy but satisfying.

---

### 10. Answer Option — Tap Ripple

**The idea**: When a student taps an MCQ option, a circular ripple expands from the tap point (like Material Design). The ripple color is green for correct, red for incorrect — but it expands BEFORE the correct/incorrect state is revealed, creating a satisfying tactile feel.

---

### 11. Correct Answer — Sheep Celebration Burst ⭐

**The idea**: When you get one right, the tiny sheep on the progress bar LEAPS up above the bar, does a front-flip, and lands back on the bar. Takes ~600ms total.

Simultaneously: 3–4 tiny confetti pieces (🎉 or colored squares) pop out from the correct answer option.

```css
@keyframes sheep-leap {
  0%   { transform: translateY(0px) rotate(0deg); }
  30%  { transform: translateY(-24px) rotate(-180deg); }
  60%  { transform: translateY(-12px) rotate(-330deg); }
  100% { transform: translateY(0px) rotate(-360deg); }
}
```

---

### 12. Wrong Answer — The "Aww" Reaction

**The idea**: 
- The wrong answer button shakes horizontally (reuses existing `wiggle` animation, ~0.4s)
- The sheep on the progress bar briefly covers its face with its front legs (state switch to a new "facepalm" pose for 1s)
- A small "X" icon pops in above the wrong option, shrinks, and fades

No judgment — it's playful, not discouraging.

---

### 13. Combo Streak Pop-Up

**The idea**: 3 correct in a row → a badge swoops in from the top: `"3x 🔥 STREAK!"` in bold green. It holds for 1.2s then slides back up.

5 correct in a row → the sheep on the bar does a little victory dance AND the badge is golden: `"5x ⚡ UNSTOPPABLE!"`

This layer of game-feel dramatically increases session length (Duolingo uses this to great effect).

---

### 14. AI Tutor Button — Gentle Pulse Reminder

**The idea**: If the student hasn't opened the AI Tutor after 3 wrong answers in a row, the Tutor button pulses once with a soft glow to remind them it exists.

`"Having trouble? Try the AI Tutor 👇"` tooltip pops up for 3s.

---

### 15. Practice Complete — Confetti Rain + Score Count-Up ⭐

**The idea**: 
1. Score counts from 0% → actual score over 1.2s (easeOutCubic)
2. 50+ tiny colored dots rain from the top of the screen if score ≥ 70%
3. The trophy icon slams in from above, bounces 2x, settles
4. Each stat (Correct / Incorrect / Improved) animates in with staggered 100ms delays

If score < 50%: No confetti. Sheep is in the "sheared" state. Copy: "Shake it off — that's what practice is for 🐑"

---

## 📊 Readiness Dashboard — The Progress Board

*What you saw: circular arc gauge showing 17%, chapter bars all at 0%.*

### 16. Circular Gauge — Sweep-In Animation ⭐

**The idea**: On page load, the red arc doesn't just appear at 17% — it sweeps from 0° → 17% over 800ms. The number inside counts up simultaneously.

**Color responds to readiness:**
- `< 40%` — Red arc (urgent)
- `40–70%` — Amber arc (getting there)
- `70–90%` — Blue arc (solid)
- `90–100%` — Green arc → glows gold at 100% (Golden Fleece!)

**Extra**: A tiny sheep silhouette walks along the outside edge of the arc circle as it sweeps, like a sheep running around a track.

---

### 17. Chapter Bars — Staggered Cascade

**The idea**: Each chapter readiness bar fills from 0 to its actual value, but they stagger in sequence — bar 1 fills, then 200ms later bar 2 starts, then bar 3, etc.

This transforms a static list into a satisfying "loading" sequence that makes the student feel like the system is doing smart work.

**Mastery color coding**: Bars visually pulse once when fully filled — green if mastered, amber if needs work.

---

### 18. Sheep Climbs the Gauge

**The idea**: A tiny sheep is positioned outside the circular gauge. As the gauge sweeps, the sheep appears to climb upward along the arc's leading edge — like it's climbing a curved hill. When it reaches the arc's tip, it plants a tiny flag 🚩.

This is the most delightful animation in the whole app. It ties the sheep to the readiness concept directly — the student IS the sheep, climbing toward Golden Fleece.

---

## 📝 Assessment — The Real Test

### 19. Assessment Start — Dramatic Entrance

**The idea**: When a student taps "START" on the assessment, there's a brief 500ms transition:
- The card zooms in slightly (scale 1.0 → 1.02 → 1.0)
- The button label morphs: "START" → "🐑 Let's go!" → first question appears

Signals: this is different from casual practice. This matters.

---

### 20. Answer Submit — Community Stats Pop-In

**The idea**: After answering, the community stat `"X% of students got this right"` doesn't just appear — it slides in from the right with a 200ms delay after the correct/incorrect feedback, so it lands as a second beat of information rather than visual noise.

---

### 21. Results Screen — Trophy Slam ⭐

**The idea**:
1. Screen starts blank
2. Trophy slams down from above with a heavy bounce (overshoot easing)
3. Score counts up 0 → final over 1.5s
4. Score delta badge (`▲ +5 pts`) swoops in from the left
5. Topic rows cascade in from bottom, one every 120ms

If score ≥ 80%: Confetti. Sheep is golden_fleece state.
If score < 50%: Sheep is sheared state, sits sadly. Copy: "Every attempt teaches the sheep something new 🐑"

---

## 🏆 Flock / Leaderboard

*What you saw: #1 green card, sheep mascot icon next to FP score, "How Flock Works" explainer.*

### 22. Sheep Parade — Rank Animations

**The idea**: Each student in the leaderboard has a tiny sheep icon (already shown in the UI). Give those sheep personality:
- `#1` — Sheep wears a tiny crown 👑, does a slow royal nod animation
- `#2–3` — Sheep holds a silver/bronze medal, slight bounce
- `You (not #1)` — Sheep looks determined, subtle forward-leaning animation

---

### 23. Rank Position Change — Swoosh

**The idea**: When the leaderboard updates (weekly or after FP gained), rows slide to their new positions with a smooth animation. If you moved UP, your card has a brief upward arrow flash. If DOWN, a downward arrow.

---

### 24. Weekly Reset Countdown

**The idea**: A small countdown below the leaderboard: `"Resets in 2d 14h 33m"`. The clock ticks in real-time (LiveView :tick event or JS). As reset approaches < 1 hour, it pulses red.

---

## 🌐 Global / Nav — Always-On Delight

### 25. Sheep Logo — Idle Personality

**The idea**: The tiny sheep logo in the top-left navbar (`priv/static/images/logo.svg`) comes to life with a random idle animation every ~20–30 seconds:
- Blinks (eyes close 200ms)
- Ear flick (right ear twitches once)
- Head tilt (slight rotate -5deg → 0deg)
- Wool shimmer (brief white highlight across wool puff)

This is the highest-delight-per-effort animation in the whole list. Students will notice the sheep is "alive" and it becomes a beloved mascot.

---

### 26. Level-Up Full Screen — Wool Grows

**The idea**: When a student's wool level increases (streak milestone), a full-screen celebration plays:
1. Background dims
2. Large sheep rises from the bottom of the screen
3. Wool visibly grows fluffier (the wool puff circles scale up with a spring animation)
4. Text: `"WOOL LEVEL 3! 🐑"` scales in from nothing
5. XP number cascades up

Duration: ~2 seconds. Can't be skipped (but it's short enough that students won't mind).

---

### 27. Bottom Nav — Sheep Scurries Between Tabs

**The idea**: When switching tabs on the bottom nav (Learn / Courses / Practice / Flocks), a tiny sheep character scurries along the bottom bar from the old tab icon to the new one.

The sheep runs at a speed proportional to the distance (Practice → Flocks is far, so it sprints. Learn → Courses is short, it just trots).

This is a signature interaction that no other app does. It directly connects the mascot to navigation and makes switching tabs actually fun.

---

## ✂️ Daily Shear — The Challenge Mode

### 28. Scissors Open/Close on "GO" Tap

**The idea**: The `✂️` emoji in the Daily Shear card is replaced with an SVG scissors icon that animates open and shut when you hover/tap the GO button. As the page transitions, the scissors swipe across the screen horizontally as if shearing the current view.

---

### 29. Question Timer Ring

**The idea**: In the Daily Shear (timed challenge), each question has a circular timer ring around the question card border. It depletes clockwise in the question time limit. 

Color: Green → Amber → Red as time runs out.

Under 5 seconds: Ring pulses + subtle shake on the card.

---

## 📚 Study Guides — The Reading Mode

### 30. Chapter Section Reveal

**The idea**: As the student scrolls through a study guide, each section header fades in and slides up slightly on scroll (`IntersectionObserver`). This creates a "revealing" feel rather than a wall of text appearing all at once.

The shepherd sheep mascot (already exists as a state) bobs gently in the corner while reading.

---

## 🔧 Implementation Priorities

### Tier 1 — Do These First (Max Impact, Medium Effort)

| # | Animation | Why |
|---|-----------|-----|
| 1 | Walking sheep on readiness progress bar (dashboard) | Core brand moment — this is THE thing |
| 2 | Practice progress bar walking sheep with footprints | Same mechanic, high daily usage |
| 3 | Correct answer sheep leap + confetti | Rewards loop, drives engagement |
| 4 | Assessment results trophy slam + score count-up | Emotional peak of the learning loop |
| 5 | Sheep logo idle blinking/ear-flick | Always-on delight, very low effort |
| 6 | Bottom nav sheep scurry between tabs | Signature interaction, uniquely FunSheep |

### Tier 2 — High Payoff, Plan for Next Sprint

| # | Animation | Why |
|---|-----------|-----|
| 7 | Circular gauge sweep-in (readiness page) | Very visible, good first impression |
| 8 | Days left counter urgency (heartbeat/tremble) | Motivational mechanic |
| 9 | Combo streak pop-up badge | Session length driver |
| 10 | Level-up full screen wool growth | Milestone moment |
| 11 | Leaderboard rank change swoosh | Social/competitive layer |
| 12 | Chapter bars staggered cascade | Makes data feel alive |

### Tier 3 — Polish Layer

| # | Animation | Why |
|---|-----------|-----|
| 13 | Question page-turn entrance | Textbook metaphor |
| 14 | Sheep climbs the readiness gauge | Delightful, unique |
| 15 | Daily Shear scissors swipe transition | Thematic |
| 16 | Study guide scroll reveal | Reading UX |
| 17 | FP counter roll-up odometer | Gamification polish |
| 18 | Weekly leaderboard countdown | Creates urgency |

---

## Technical Notes

### CSS-First Approach
Most animations should be pure CSS keyframes — zero JS, no library dependency. The existing `app.css` already has `@keyframes` for `wiggle`, `shiver`, `float`, `glow`, and `bounce`. New animations extend that file.

### LiveView JS Hooks for Complex Animations
- `SheepProgressBar` hook: reads `data-readiness` attribute, positions sheep SVG, switches animation class by readiness band
- `CountUp` hook: watches for DOM change on counter elements, runs the number roll-up
- `ConfettiBurst` hook: spawns and cleans up confetti particles on `phx-hook` trigger
- `NavSheepRunner` hook: listens for tab click events, animates the nav sheep

### Performance Rules
- All animations use `transform` and `opacity` only — no `left`/`top`/`width` changes (avoids layout thrash)
- `will-change: transform` on animated sheep SVGs
- `prefers-reduced-motion` media query wraps ALL keyframe animations — students with motion sensitivity see instant state changes instead
- Animations auto-disable if frame rate drops below 50fps (via `requestAnimationFrame` budget check in hooks)

### Mobile-First
All tap ripples use `touchstart` not `click` (already handled by SwipeCard hook pattern). The bottom-nav sheep uses `pointer: coarse` detection to only run on touch devices.

---

## The One-Line Brief for Each Page

| Page | Animation TL;DR |
|------|-----------------|
| Dashboard | Sheep walks the readiness bar. Days counter panics when late. Flame flickers. |
| Practice Mode | Sheep + footprints on progress. Cards flip in. Sheep leaps on correct. Combo badges. |
| Readiness Dashboard | Gauge sweeps in. Sheep climbs the arc edge. Bars cascade in. |
| Assessment | Dramatic start zoom. Trophy slams. Score counts up. |
| Daily Shear | Scissors snip. Timer ring depletes. |
| Leaderboard | Crowned #1 sheep nods. Ranks swoosh on change. Reset countdown ticks. |
| Study Guides | Sections scroll-reveal. Shepherd sheep bobs. |
| Global Navbar | Sheep blinks/twitches every 25s. Scurries between tabs. Level-up fullscreen. |
