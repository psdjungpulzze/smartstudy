import "@testing-library/jest-native/extend-expect";
import React from "react";

// ── expo-secure-store ──────────────────────────────────────────────────────────
jest.mock("expo-secure-store", () => ({
  setItemAsync: jest.fn().mockResolvedValue(null),
  deleteItemAsync: jest.fn().mockResolvedValue(null),
  getItemAsync: jest.fn().mockResolvedValue(null),
}));

// ── expo-notifications ────────────────────────────────────────────────────────
jest.mock("expo-notifications", () => ({
  setNotificationHandler: jest.fn(),
  getPermissionsAsync: jest.fn().mockResolvedValue({ status: "granted" }),
  requestPermissionsAsync: jest.fn().mockResolvedValue({ status: "granted" }),
  setNotificationChannelAsync: jest.fn().mockResolvedValue(null),
  getExpoPushTokenAsync: jest
    .fn()
    .mockResolvedValue({ data: "ExponentPushToken[test-token]" }),
  AndroidImportance: { MAX: 5 },
}));

// ── expo-device ───────────────────────────────────────────────────────────────
// __esModule: true ensures import * as Device returns the SAME object as require(),
// so tests can directly mutate Device.isDevice across module boundaries.
jest.mock("expo-device", () => ({
  __esModule: true,
  isDevice: true,
}));

// ── expo-web-browser ──────────────────────────────────────────────────────────
jest.mock("expo-web-browser", () => ({
  openAuthSessionAsync: jest.fn().mockResolvedValue({ type: "cancel" }),
  maybeCompleteAuthSession: jest.fn(),
}));

// ── expo-linking ──────────────────────────────────────────────────────────────
jest.mock("expo-linking", () => ({
  createURL: jest.fn().mockReturnValue("funsheep://auth/callback"),
}));

// ── expo-crypto ───────────────────────────────────────────────────────────────
jest.mock("expo-crypto", () => ({
  digestStringAsync: jest.fn().mockResolvedValue("bW9jay1oYXNoLXZhbHVl"),
  CryptoDigestAlgorithm: { SHA256: "SHA-256" },
  CryptoEncoding: { BASE64: "base64" },
}));

// ── expo-constants ────────────────────────────────────────────────────────────
jest.mock("expo-constants", () => ({
  __esModule: true,
  default: {
    expoConfig: {
      extra: {
        apiBaseUrl: "https://test.funsheep.com",
        eas: { projectId: "test-project-id" },
      },
    },
    easConfig: { projectId: "test-project-id" },
  },
}));

// ── expo-router ───────────────────────────────────────────────────────────────
jest.mock("expo-router", () => {
  const { View } = require("react-native");
  const mockStack = ({ children }: { children?: React.ReactNode }) =>
    children ?? null;
  mockStack.Screen = () => null;
  const mockTabs = ({ children }: { children?: React.ReactNode }) =>
    children ?? null;
  mockTabs.Screen = () => null;
  return {
    useRouter: jest.fn(() => ({
      push: jest.fn(),
      replace: jest.fn(),
      back: jest.fn(),
    })),
    useSegments: jest.fn(() => []),
    useLocalSearchParams: jest.fn(() => ({})),
    usePathname: jest.fn(() => "/"),
    Stack: mockStack,
    Tabs: mockTabs,
    Slot: () => null,
    Link: ({ children }: { children?: React.ReactNode }) => children ?? null,
  };
});

// ── react-native-gesture-handler ──────────────────────────────────────────────
jest.mock("react-native-gesture-handler", () => {
  const { View } = require("react-native");
  return {
    GestureHandlerRootView: View,
    GestureDetector: ({ children }: { children?: React.ReactNode }) =>
      children ?? null,
    Gesture: {
      Pan: () => ({
        enabled: jest.fn().mockReturnThis(),
        onUpdate: jest.fn().mockReturnThis(),
        onEnd: jest.fn().mockReturnThis(),
      }),
      Tap: () => ({
        onEnd: jest.fn().mockReturnThis(),
      }),
      Simultaneous: jest.fn((...args: unknown[]) => args[0]),
    },
  };
});

// ── react-native-reanimated ───────────────────────────────────────────────────
jest.mock("react-native-reanimated", () =>
  require("react-native-reanimated/mock")
);

// ── react-native-safe-area-context ────────────────────────────────────────────
jest.mock("react-native-safe-area-context", () => {
  const { View } = require("react-native");
  return {
    SafeAreaProvider: View,
    SafeAreaView: View,
    useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
  };
});
