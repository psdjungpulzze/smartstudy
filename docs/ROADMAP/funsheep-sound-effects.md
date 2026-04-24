# FunSheep Sound Effects

**Status**: Planned  
**Priority**: Medium  
**Effort**: Small (Phase 1) → Medium (Phase 2+)

---

## Problem

The practice and assessment flows give purely visual feedback when a student answers a question. There is no audio response whatsoever. Audio reinforcement — especially playful, brand-consistent sounds — has been shown to improve engagement and emotional memory anchoring in learning contexts. The sheep brand identity also creates a natural opportunity: a sheep's "baa" when you get something wrong is memorable, on-brand, and slightly self-deprecating in a way students will enjoy.

---

## Goal

Add contextual sound effects tied to key learning moments, starting with the wrong-answer sheep sound, and expanding to a full sound vocabulary that reinforces the FunSheep identity and student motivation loop.

---

## Phase 1 — Wrong Answer Sheep Sound (Scope: Minimal)

### What it is

Play a short sheep "baa" sound when a student submits a wrong answer in any practice or assessment mode. The user (Peter) will supply the audio file.

### Screens in scope

| Screen | LiveView | Event |
|--------|----------|-------|
| Practice | `practice_live.ex` | `handle_event("submit_answer")` → `is_correct == false` |
| Quick Test | `quick_test_live.ex` | `handle_event("submit_answer")` → `is_correct == false` |
| Quick Practice | `quick_practice_live.ex` | `handle_event("submit_answer")` → `is_correct == false` |

Assessment mode (proctored test) should be **excluded** from Phase 1 — sounds during a test feel disruptive.

### Technical approach

#### 1. Audio file placement

```
priv/static/sounds/
└── sheep_wrong.mp3        # Primary (broad browser support)
└── sheep_wrong.ogg        # Fallback (open format)
```

The user supplies the source audio. We convert to both MP3 and OGG for cross-browser support. Files are served as regular static assets via Phoenix's static plug — no special configuration needed.

#### 2. JS hook — `SoundPlayer`

Create a lightweight `SoundPlayer` hook in `assets/js/app.js`. The hook:

- Mounts on a hidden `<div>` placed once in the practice layout
- Pre-loads the sound file on `mounted()` using the Web Audio API (or `new Audio()` as a simpler fallback — see trade-off below)
- Listens for a `play_sound` event pushed from the LiveView
- Plays the corresponding sound file

```javascript
// assets/js/app.js — add to Hooks object
SoundPlayer: {
  mounted() {
    this.sounds = {}
    this.handleEvent("play_sound", ({ name }) => this.play(name))
  },
  play(name) {
    if (!this.sounds[name]) {
      const ext = this.supportsOgg() ? "ogg" : "mp3"
      this.sounds[name] = new Audio(`/sounds/${name}.${ext}`)
      this.sounds[name].volume = 0.6
    }
    // Clone so overlapping plays don't cancel each other
    this.sounds[name].cloneNode().play().catch(() => {})
  },
  supportsOgg() {
    const a = document.createElement("audio")
    return a.canPlayType("audio/ogg; codecs=vorbis") !== ""
  }
}
```

The `.catch(() => {})` silently swallows `NotAllowedError` from browsers that block autoplay before user interaction — the sound simply doesn't play rather than throwing a console error.

#### 3. LiveView — push the event

In each in-scope LiveView, after `is_correct` is determined, push a sound event to the client:

```elixir
# practice_live.ex — inside handle_event("submit_answer", ...)
is_correct = check_answer(question, answer)

socket =
  if is_correct do
    socket
  else
    push_event(socket, "play_sound", %{name: "sheep_wrong"})
  end
```

This is a one-liner change per LiveView. `push_event/3` is already used elsewhere in the codebase (e.g., `DirectUploader` hook in app.js uses `handleEvent`).

#### 4. Template mount point

Add a single hidden div with the hook to the practice layout (or root layout if sounds will be global):

```heex
<div id="sound-player" phx-hook="SoundPlayer" class="hidden"></div>
```

Place it once near the bottom of `app.html.heex` so it persists across LiveView navigations.

### What we are NOT doing in Phase 1

- No audio library dependency (Howler.js, etc.) — native `Audio` API is sufficient for 2-3 short clips
- No volume controls or settings UI
- No correct-answer sound yet
- No mobile vibration
- No sound in assessment/test mode

### Audio library trade-off note

**Native `Audio` API** (Phase 1 choice):
- Zero dependencies, works in all modern browsers
- `cloneNode()` trick handles rapid replays without queue issues
- Sufficient for ≤5 short, non-overlapping effects

**Howler.js** (Phase 2+ if needed):
- Sprite support (one file, multiple clips)
- Built-in mobile unlock handling
- Global mute/volume
- Worth adding only when sound vocabulary grows beyond ~5 effects

---

## Phase 2 — Sound Vocabulary Expansion

Once the infrastructure from Phase 1 is in place, adding new sounds is a 2-step operation: drop the file in `priv/static/sounds/` and add a `push_event` call. No hook changes needed.

### Planned sounds

| Sound | Trigger | File name | Notes |
|-------|---------|-----------|-------|
| Sheep baa (wrong) | Wrong answer | `sheep_wrong` | Phase 1 |
| Correct chime | Correct answer | `correct` | Short, upbeat, non-annoying |
| Streak bell | 3-answer streak | `streak` | Triggered in gamification flow |
| Level-up fanfare | XP level-up | `level_up` | Triggered by `Gamification.award_xp` broadcast |
| Course complete | 100% readiness | `course_complete` | Triggered from readiness check |

### Trigger points for Phase 2 sounds

```
Correct answer  → practice_live.ex line ~158 (is_correct == true)
Streak          → Gamification context, when streak count hits multiple of 3
Level-up        → Gamification.award_xp broadcast (already uses PubSub)
Course complete → readiness calculation crosses 100% threshold
```

---

## Phase 3 — User Settings

Some students find sounds distracting. Add a simple toggle.

### Design

- **Location**: Profile/Settings page → "Learning Preferences" section
- **Storage**: `user_preferences` JSONB column (or separate boolean column on user schema)
- **Default**: Sounds ON
- **Persistence**: Server-side preference, not `localStorage`, so it follows the student across devices

### UI

Small toggle row:

```
[🔊] Sound effects     [toggle ON]
```

The toggle writes to the server. The `SoundPlayer` hook reads a `data-sounds-enabled` attribute injected into the mount point div by the LiveView, so no separate API call is needed on each play:

```heex
<div id="sound-player"
     phx-hook="SoundPlayer"
     data-sounds-enabled={@current_user.preferences["sounds_enabled"] != false}
     class="hidden">
</div>
```

---

## Phase 4 — Mobile Considerations

iOS and Android browsers block audio until after a user gesture. Phase 1's `.catch(() => {})` silently swallows the first blocked play, but repeated misses are frustrating.

**Solution**: On first user interaction (phx-click on any answer option), call `AudioContext.resume()` to unlock the audio context. This is a one-time unlock per session and requires no user-visible UI.

```javascript
// Unlock audio context on first interaction
document.addEventListener("click", () => {
  if (window._audioContext) window._audioContext.resume()
}, { once: true })
```

This can be added in Phase 1 as a defensive measure even before Phase 4 becomes a priority.

---

## Files to create/modify

| File | Change |
|------|--------|
| `priv/static/sounds/sheep_wrong.mp3` | New — user-supplied audio file |
| `priv/static/sounds/sheep_wrong.ogg` | New — converted fallback |
| `assets/js/app.js` | Add `SoundPlayer` hook to `Hooks` object |
| `lib/fun_sheep_web/components/layouts/app.html.heex` | Add `<div id="sound-player" ...>` |
| `lib/fun_sheep_web/live/practice_live.ex` | Add `push_event` on wrong answer |
| `lib/fun_sheep_web/live/quick_test_live.ex` | Add `push_event` on wrong answer |
| `lib/fun_sheep_web/live/quick_practice_live.ex` | Add `push_event` on wrong answer |

---

## Open questions

1. **File format**: Will the supplied sheep sound be MP3, WAV, or another format? We'll convert to MP3 + OGG regardless.
2. **Volume**: Is 60% volume the right default? Should it be lower for a classroom setting?
3. **Assessment exclusion confirmed?** Should timed/proctored tests also be silent, or is a subtle sound OK there too?
4. **Correct-answer sound**: Is Phase 2 correct-answer sound in scope soon, or keep it sheep-only for now?

---

## Success metric

Students in practice mode who answer incorrectly hear the sheep sound within 150ms of feedback rendering. No errors in the browser console on any supported browser (Chrome, Firefox, Safari, mobile Safari, Chrome Android).
