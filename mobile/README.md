# FunSheep Mobile

React Native (Expo) app for iOS and Android.

## Prerequisites

- Node 20+
- Expo CLI: `npm install -g expo-cli`
- iOS: Xcode + Simulator
- Android: Android Studio + Emulator

## Setup

```bash
cd mobile
npm install
```

## Development

```bash
# Start Metro
npm start

# iOS Simulator
npm run ios

# Android Emulator
npm run android
```

## Environment

The API base URL defaults to `https://funsheep.com`. To point at a local dev server:

```bash
EXPO_PUBLIC_API_URL=http://localhost:4000 npm start
```

Update `app.json` → `extra.apiBaseUrl` for a build-time override.

## Auth Flow

1. Login screen calls `GET /api/v1/auth/authorize_url` to get the Interactor OAuth URL
2. Opens in `expo-web-browser` in-app browser (PKCE S256)
3. Deep link `funsheep://auth/callback` returns code
4. Exchanges code for tokens via `POST /api/v1/auth/token`
5. Tokens stored in `expo-secure-store` (Keychain/Keystore)

## Architecture

```
mobile/
  app/           # Expo Router file-based navigation
    (auth)/      # Login screen (no auth required)
    (tabs)/      # Bottom tabs (phone) / sidebar (tablet)
  components/    # Shared UI components
  lib/api.ts     # Typed API client + token refresh
  store/auth.ts  # Zustand auth store (SecureStore backed)
  global.css     # NativeWind / Tailwind styles
```

## Web → Mobile Design Sync

Colors are defined in `tailwind.config.js` mirroring the daisyUI theme from
`assets/css/app.css`. Monthly sprint process: review web UI changes and update
the Tailwind config and component styles as needed.
