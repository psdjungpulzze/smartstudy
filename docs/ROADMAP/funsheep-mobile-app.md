# FunSheep Mobile App — iOS & Android Strategy

**Status:** Planning  
**Category:** Platform Expansion  
**Scope:** iOS + Android native apps with a web-to-mobile sync workflow

---

## 1. Goal

Ship FunSheep on iOS and Android with feature parity to the web app, while keeping the ongoing cost of syncing UI/UX changes from web to mobile manageable.

---

## 2. Current State

| Dimension | Web (today) | Mobile (needed) |
|-----------|-------------|-----------------|
| UI framework | Phoenix LiveView + Tailwind + daisyUI | React Native + NativeWind (Tailwind-compatible) |
| API surface | LiveView WebSocket (HTML diffs) | REST JSON API |
| Auth | Interactor OAuth 2.0 (web redirect) | Interactor OAuth 2.0 with PKCE + deep link |
| Push notifications | Schema + Oban worker (delivery stubbed) | FCM (Android) + APNs (iOS) wired up |
| Offline | None | SQLite read cache + sync queue |
| Real-time | WebSocket HTML diffs (LiveView) | WebSocket or polling for score updates |
| Tablet | Responsive CSS breakpoints | `useWindowDimensions` + Tailwind `md:` / `lg:` |

**Key insight:** Phoenix LiveView renders HTML diffs on the server — native apps cannot consume those. A parallel REST API on the same Phoenix backend is the right path. The web tier stays untouched; mobile gets a `/api/v1/*` JSON surface sitting alongside it.

**Push notification head-start:** The schema (`push_tokens`, `notifications`) and Oban worker (`NotificationDeliveryWorker`) already exist. Only the FCM/APNs delivery implementation is missing.

---

## 3. Technology Choices

### 3a. Mobile Framework — React Native + Expo

**Choice: React Native (managed via Expo)**

Rationale:
- Single codebase covers iOS + Android (and web via Expo Web, which can reuse components)
- Expo managed workflow removes native build complexity until it's needed
- NativeWind v4 translates Tailwind class names to React Native styles — the same design tokens used on the web apply directly on mobile, making the sync workflow tractable
- Expo Router provides file-based routing (mirrors Phoenix router conventions)
- Large ecosystem, active community, strong App Store / Play Store track record
- Expo EAS Build + EAS Submit handles CI/CD to both stores

**Alternatives considered:**

| Option | Verdict |
|--------|---------|
| Flutter | High quality, but Dart is a second language to maintain; no Tailwind parity |
| Native Swift/Kotlin | Best performance, worst code-sharing; 2× engineering cost |
| Ionic/Capacitor (wraps web) | Tempting, but LiveView WebSocket rendering doesn't work in a WebView iframe model |
| PWA only | Fast to ship; iOS limitations (no push, no home-screen badges on older iOS) make it a supplement not a replacement |

### 3b. Styling — NativeWind v4

NativeWind v4 reads `tailwind.config.js` directly and compiles Tailwind utility classes into React Native `StyleSheet` objects at build time. This means:

- Colors defined in `tailwind.config.js` (the same file used for the web) apply to mobile automatically
- Responsive prefixes (`sm:`, `md:`, `lg:`) map to device breakpoints via `useWindowDimensions`
- Dark mode via `colorScheme` hook mirrors the web's dark/light theme switch
- Custom tokens (e.g., FunSheep's orange `primary`, purple `secondary`) defined once, consumed everywhere

### 3c. Navigation — Expo Router v4

File-based routing under `app/` mirrors Phoenix LiveView's route tree:

```
app/
  (auth)/
    login.tsx
    register.tsx
  (app)/
    dashboard.tsx
    courses/
      [id]/
        practice.tsx
        quick-test.tsx
        exam-simulation.tsx
        study-guide.tsx
    leaderboard.tsx
    profile.tsx
  (parent)/
    index.tsx
    settings.tsx
  (teacher)/
    index.tsx
```

### 3d. State Management — TanStack Query + Zustand

- **TanStack Query** for server-state (fetches, caches, invalidates REST API responses)
- **Zustand** for lightweight local state (active session, UI preferences, offline queue)
- This mirrors the web's Phoenix assigns model: server is the source of truth, client holds transient UI state

### 3e. API Layer — Phoenix JSON REST

New router scope added to the existing Phoenix app:

```
/api/v1/
  auth/token          POST   exchange OAuth code for JWT
  auth/refresh        POST   refresh access token
  courses/            GET    list + search
  courses/:id/        GET    course details, questions, schedule
  practice/           POST   record answer, get next card
  notifications/      GET    list + mark read
  notifications/tokens POST  register push token
  users/me            GET/PUT profile
  ...
```

API versioning via URL prefix (`/api/v1/`). Phoenix controllers return JSON; LiveView routes remain untouched. The same Ecto queries and context functions power both.

---

## 4. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    FunSheep Users                           │
├───────────────┬────────────────────┬────────────────────────┤
│  Web Browser  │    iOS App         │    Android App         │
│  (LiveView)   │  (React Native)    │  (React Native)        │
├───────────────┴────────────────────┴────────────────────────┤
│                 Phoenix Backend                             │
│  ┌──────────────────┐   ┌─────────────────────────┐        │
│  │  LiveView Routes  │   │  /api/v1/* JSON API     │        │
│  │  (web only)       │   │  (mobile + web clients) │        │
│  └──────────────────┘   └─────────────────────────┘        │
│  ┌──────────────────────────────────────────────────┐       │
│  │  Shared: Contexts, Ecto, Oban Workers            │       │
│  └──────────────────────────────────────────────────┘       │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐         │
│  │ Postgres │  │  Oban    │  │ Interactor OAuth  │         │
│  └──────────┘  └──────────┘  └───────────────────┘         │
└─────────────────────────────────────────────────────────────┘
                      ↕ FCM / APNs
               ┌──────────────────┐
               │  Push Delivery   │
               └──────────────────┘
```

---

## 5. Web → Mobile Sync Workflow

The biggest ongoing cost of having native apps is keeping them in sync when the web UI evolves. The strategy is layered: some changes propagate automatically, some require a monthly sync task.

### Layer 1 — Automatic (Zero Work)

Changes to these propagate to mobile without any mobile-side code change:

| What changes | Why it's automatic |
|--------------|--------------------|
| Colors, spacing, typography in `tailwind.config.js` | NativeWind reads the same config file |
| Dark/light theme token values | Same OKLCH variables, NativeWind compiles them |
| Business logic (Ecto contexts, Oban workers) | Shared Phoenix backend |
| API responses (new fields, better data) | Mobile app gets them via REST immediately |

### Layer 2 — Semi-Automatic (Low Effort, <1 Day)

Changes that need a small mobile touch but are mechanical:

| What changes | Mobile task |
|--------------|-------------|
| New daisyUI component variant added to web | Find NativeWind equivalent or clone the class list |
| Copy/text changes (labels, CTA text, etc.) | Update `i18n/en.json` in mobile repo |
| New API field exposed | Add field to TypeScript type; TanStack Query picks it up |
| Icon changed (Heroicons update) | Swap the icon name in the shared icon map |

### Layer 3 — Manual Port (Monthly Sync Sprint)

Layout-level or interaction-level changes that require real work:

| What changes | Mobile task | Estimated effort |
|--------------|-------------|-----------------|
| New screen added to web | Build equivalent React Native screen | 1–3 days |
| Navigation restructure | Update Expo Router file tree | 0.5–1 day |
| Complex new interaction (e.g., new swipe gesture) | Implement with React Native gesture handler | 1–2 days |
| New modal / bottom sheet | Build with Reanimated + Bottom Sheet | 0.5–1 day |
| Gamification animation added | Port with Lottie or Reanimated | 0.5–2 days |

### The Monthly Sync Sprint

After every significant web iteration (roughly monthly):

1. **Diff review:** Run `git log --since="1 month ago"` on web repo, filter for commits touching `lib/fun_sheep_web/`
2. **Triage:** Categorise each change as Layer 1 (skip), Layer 2 (quick), or Layer 3 (port)
3. **Port Layer 2 + 3 changes** — target 2–3 days per sprint
4. **Ship:** EAS Update (over-the-air JS update, no App Store review needed for most changes)

**OTA vs Store Release:**
- Expo EAS Update pushes JS/asset changes instantly (same day)
- Native module changes (new camera permission, new library with native code) require a store release

---

## 6. Tablet Support

Both iPad and Android tablets are first-class targets.

### Layout Strategy

```
Phone portrait  → single-column, bottom tab nav
Phone landscape → two-column or expanded single-column
Tablet portrait → two-column (sidebar + content)
Tablet landscape → three-column (sidebar + content + detail)
```

NativeWind breakpoints (via `useWindowDimensions`):

| Prefix | Min width | Target |
|--------|-----------|--------|
| (none) | 0px       | Phone portrait |
| `sm:`  | 640px     | Phone landscape |
| `md:`  | 768px     | Tablet portrait |
| `lg:`  | 1024px    | Tablet landscape |

### Tablet-Specific Patterns

- **Sidebar navigation:** Replace bottom tab bar with a collapsible sidebar (mirrors web's left nav)
- **Practice screen:** Show question + answer side-by-side in landscape on tablets
- **Exam simulation:** Full-width question panel with persistent timer sidebar
- **Study guide:** Two-column with outline on left, content on right (iPad → like a textbook)
- **Admin views:** Table-style layouts with sortable columns (not useful on phones)

### Safe Area & Notch

- `react-native-safe-area-context` handles notch, home indicator, and Dynamic Island across all devices
- Same concepts already in the web CSS (`env(safe-area-inset-*)`) — one-to-one conceptual mapping

---

## 7. Authentication

### Mobile OAuth PKCE Flow

1. App opens `interactor.com/oauth/authorize?response_type=code&code_challenge=...` in a `WebBrowser.openAuthSessionAsync` (Expo)
2. Interactor redirects to `funsheep://auth/callback?code=...` (deep link)
3. App exchanges code for tokens via `/api/v1/auth/token` (Phoenix controller)
4. JWT stored securely in `expo-secure-store` (Keychain on iOS, Keystore on Android)
5. Refresh tokens rotated via `/api/v1/auth/refresh`

### What to add to Phoenix

- `FunSheepWeb.API.AuthController` — handles `/api/v1/auth/token` and `/api/v1/auth/refresh`
- PKCE verification (code challenge/verifier) alongside the existing web OAuth flow
- Mobile app redirect URI registered in Interactor (`funsheep://auth/callback`)
- No new user model changes — same `user_roles` table

---

## 8. Push Notifications

The schema is already in place. What's needed:

### Backend (Phoenix)

1. **FCM setup:** Add Google service account for Firebase Cloud Messaging; add `fcmex` or `pigeon` library to `mix.exs`
2. **APNs setup:** Add Apple push certificate + private key; configure `pigeon` APNs adapter
3. **Wire up `NotificationDeliveryWorker`:** Replace the stub with actual FCM/APNs calls, pattern-match on `platform` field in `push_tokens`
4. **Token registration endpoint:** `POST /api/v1/notifications/tokens` — stores expo push token or raw FCM/APNs token

### Mobile (React Native)

1. `expo-notifications` — request permission, retrieve token, register with backend
2. Notification handlers — foreground (in-app banner), background (system notification), deep link on tap

### Notification Types Already Modelled

| Type | Trigger |
|------|---------|
| Streak at risk | `StreakAtRiskWorker` → `NotificationDeliveryWorker` |
| Test upcoming | `TestDateSyncWorker` → countdown alerts |
| Study digest | Weekly parent summary |
| New course ready | `CourseReadyEmailWorker` → also push |
| Flock activity | Social interactions |

---

## 9. Offline Support

Offline support is a differentiator for a study app (students study on the bus with no signal).

### What to cache offline

| Feature | Cache strategy |
|---------|---------------|
| Practice cards (questions + answers) | Fetch next 50 cards when online, store in SQLite |
| Course metadata (names, topics) | Cache on first load, TTL 24h |
| Study guides | Cache rendered markdown on open |
| User profile + streak | Cache indefinitely, sync on resume |

### Sync queue

- Answers recorded offline are queued in Zustand + persisted to SQLite
- On reconnect, flush queue to `/api/v1/practice` in order
- Conflict resolution: server wins for score, last-write wins for preferences

### Library

`expo-sqlite` + `drizzle-orm` (SQLite ORM, mirrors Ecto conventions) for the local database.

---

## 10. Implementation Phases

### Phase 0 — Foundation (Weeks 1–4)

Backend work before any mobile code starts.

- [ ] Add `FunSheepWeb.API` pipeline to `router.ex` (JSON, token auth plug)
- [ ] `AuthController` — PKCE token exchange + refresh
- [ ] `CoursesController` — list, show
- [ ] `PracticeController` — get next card, record answer
- [ ] `NotificationsController` — list, mark read, register push token
- [ ] `UsersController` — me (GET/PUT)
- [ ] Wire up `NotificationDeliveryWorker` with Pigeon (FCM + APNs)
- [ ] Add FCM service account + APNs certificate to environment secrets
- [ ] Register `funsheep://` deep link URI in Interactor OAuth config

**Deliverable:** Postman/Bruno collection of all endpoints with example responses

---

### Phase 1 — PWA Quick Win (Weeks 3–5, overlaps Phase 0)

While the API is being built, ship a Progressive Web App. This covers students who don't want to download an app.

- [ ] `assets/js/sw.js` — service worker (cache-first for assets, network-first for API)
- [ ] `priv/static/manifest.json` — PWA manifest (name, icon, theme color, `display: standalone`)
- [ ] `<link rel="manifest">` in `root.html.heex`
- [ ] iOS add-to-homescreen prompt (custom UI, Safari doesn't auto-prompt)
- [ ] Android install banner (Chrome handles automatically via manifest)
- [ ] Offline fallback page for no-connection state

**Deliverable:** FunSheep installable as a home-screen app on iPhone and Android

---

### Phase 2 — React Native MVP (Weeks 5–16)

Core study loop on native iOS and Android.

**Screens in scope for MVP:**

| Screen | Priority |
|--------|---------|
| Login (OAuth handoff) | P0 |
| Dashboard (today's plan, streak) | P0 |
| Course list | P0 |
| Practice (swipe cards) | P0 |
| Quick test | P0 |
| Results / score | P0 |
| Exam simulation | P1 |
| Study guide viewer | P1 |
| Leaderboard | P1 |
| Profile + settings | P1 |
| Parent dashboard | P2 |
| Teacher tools | P2 |
| Admin views | P3 |

**Technical milestones:**

- [ ] Expo project init, EAS Build configured for iOS + Android
- [ ] Expo Router file tree matching route structure above
- [ ] NativeWind v4 wired to `tailwind.config.js`
- [ ] Auth flow (OAuth PKCE → JWT storage in Keychain/Keystore)
- [ ] TanStack Query API client pointed at `/api/v1/`
- [ ] Bottom tab nav (phone) + sidebar nav (tablet)
- [ ] SwipeCard component with `react-native-gesture-handler` + `react-native-reanimated`
- [ ] Push notification registration on login
- [ ] Haptic feedback (`expo-haptics`) matching web's `navigator.vibrate(15)`
- [ ] Sound effects (`expo-av`) matching web's SoundPlayer
- [ ] TestFlight (iOS) + Play Store internal track (Android) beta build

**Deliverable:** Beta app on TestFlight + Play Store internal track

---

### Phase 3 — Store Launch (Weeks 17–20)

- [ ] App Store review preparation (screenshots, metadata, privacy policy)
- [ ] Play Store review preparation
- [ ] Crashlytics / Sentry integration
- [ ] Analytics (Posthog or Mixpanel) — same events as web
- [ ] In-app review prompts (`expo-store-review`)
- [ ] Deep link support for web → app handoff (universal links / app links)
- [ ] Subscription flow — RevenueCat for in-app purchases (wraps Apple IAP + Google Play Billing)

**Deliverable:** FunSheep v1.0 live on App Store and Google Play

---

### Phase 4 — Feature Parity (Weeks 21–32)

Port remaining web features to mobile:

- [ ] Social features (friends, leaderboard, shout-outs)
- [ ] Teacher tools (custom tests, course builder)
- [ ] Parent dashboard + weekly reports
- [ ] Gamification modals (confetti, level-ups)
- [ ] Animations (sheep mascot, celebration states)
- [ ] Offline study mode (SQLite cache + sync queue)
- [ ] Tablet-optimised layouts for all major screens

---

### Phase 5 — Ongoing Sync (Monthly)

See §5 for the web → mobile sync workflow. This becomes a recurring engineering ritual.

---

## 11. Repo Structure

**Option A: Monorepo (recommended)**

Keep mobile inside the existing funsheep repo:

```
funsheep/
  lib/             ← Phoenix backend (unchanged)
  assets/          ← Web assets (unchanged)
  mobile/          ← React Native / Expo app
    app/           ← Expo Router screens
    components/    ← Shared React Native components
    hooks/         ← Custom hooks
    api/           ← TanStack Query client + API types
    i18n/          ← Strings (en.json, etc.)
    store/         ← Zustand stores
    tailwind.config.js  ← Symlink → ../tailwind.config.js
  docs/
    ROADMAP/
```

The `tailwind.config.js` symlink is the technical centrepiece of the sync strategy — mobile reads the same config as web.

**Option B: Separate repo**

Easier to give contractors/agencies access without exposing the full backend. More friction for sync. Use only if team separation requires it.

---

## 12. Design Tokens & Component Parity Tracker

Maintain a lightweight tracker in `mobile/docs/component-parity.md`:

| Web component | Mobile equivalent | Status | Notes |
|--------------|-------------------|--------|-------|
| SwipeCard | `<SwipeCard>` | Done | gesture-handler |
| ProgressPanel | `<ProgressPanel>` | In progress | |
| GamificationModal | `<GamificationModal>` | Backlog | needs Lottie |
| ShareButton | `<ShareButton>` | Done | expo-sharing |
| SheepMascot | `<SheepMascot>` | Backlog | Lottie animation |
| BottomSheet | `<BottomSheet>` | Done | @gorhom/bottom-sheet |
| QuestionTypes | `<QuestionRenderer>` | In progress | |
| AdminSidebar | N/A (admin is web-only) | — | |

Update this table in every sync sprint.

---

## 13. Key Decisions & Trade-offs

| Decision | Choice | Trade-off |
|----------|--------|-----------|
| Cross-platform framework | React Native + Expo | Less performance than native Swift/Kotlin; far less engineering cost |
| Styling | NativeWind (Tailwind) | Occasional layout quirks vs CSS; strong sync benefit |
| API style | REST (not GraphQL) | Less flexible querying; simpler to add to Phoenix without a schema layer |
| IAP | RevenueCat | Extra SDK + 0.5% fee; eliminates store billing complexity |
| Push | Expo push service first, direct FCM/APNs later | Expo adds a relay hop; fine for MVP, replace with direct when volume warrants |
| Auth storage | expo-secure-store (Keychain) | Platform-specific; no alternative that's secure cross-platform |
| Offline DB | expo-sqlite + drizzle-orm | Adds SQLite; significant UX win for study app |

---

## 14. Open Questions

1. **Subscription model on mobile:** Apple and Google take 15–30% of IAP. Does FunSheep want to offer a "buy on web" flow that bypasses the stores? (Yes — link to web checkout from the app, which is allowed under the post-Epic rules.)
2. **Admin on mobile:** Probably not worth building for v1. Admins use desktops.
3. **Interactor OAuth mobile redirect URI:** Needs to be registered by the Interactor team. Confirm `funsheep://auth/callback` as the URI.
4. **EAS project ID:** Create an EAS project and store the ID in `mobile/app.json`.
5. **App Store developer account:** Confirm the Apple developer account to use (or create one: $99/year).
6. **Play Store developer account:** Confirm the Google Play console account ($25 one-time).
7. **Crashlytics vs Sentry:** Sentry is already used on the web; use the same for mobile for a single error dashboard.

---

## 15. Success Metrics

| Metric | Target |
|--------|--------|
| Time to MVP beta | ≤ 16 weeks from Phase 0 start |
| iOS App Store approval | First submission accepted |
| Android Play Store | No critical policy violations |
| Web-to-mobile sync lag | < 4 weeks for any UI change to appear in mobile |
| Push notification delivery rate | > 95% (FCM + APNs) |
| Crash-free sessions | > 99.5% in first month |
| Offline study coverage | Top 50 practice cards always available |

---

*Last updated: 2026-04-26*
