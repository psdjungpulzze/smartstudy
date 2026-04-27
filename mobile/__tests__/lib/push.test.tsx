import React from "react";
import { renderHook, act } from "@testing-library/react-native";
import { Platform } from "react-native";
import * as Notifications from "expo-notifications";
import * as Device from "expo-device";
import { usePushRegistration } from "@/lib/push";

// Must start with `mock` for jest hoisting
const mockUseAuthStore = jest.fn();

jest.mock("@/store/auth", () => ({
  useAuthStore: (selector: (s: { accessToken: string | null }) => unknown) =>
    mockUseAuthStore(selector),
}));

const mockRegisterToken = jest.fn().mockResolvedValue({ ok: true });

jest.mock("@/lib/api", () => ({
  notificationsApi: {
    registerToken: (...args: unknown[]) => mockRegisterToken(...args),
  },
}));

function withAccessToken(token: string | null) {
  mockUseAuthStore.mockImplementation(
    (selector: (s: { accessToken: string | null }) => unknown) =>
      selector({ accessToken: token })
  );
}

describe("usePushRegistration", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default: real device, permission granted, iOS
    (Device as { isDevice: boolean }).isDevice = true;
    Object.defineProperty(Platform, "OS", {
      value: "ios",
      configurable: true,
    });
    (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
      status: "granted",
    });
    (Notifications.getExpoPushTokenAsync as jest.Mock).mockResolvedValue({
      data: "ExponentPushToken[test]",
    });
  });

  it("registers push token when user is authenticated on a real device", async () => {
    withAccessToken("bearer-token");
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(mockRegisterToken).toHaveBeenCalledWith(
      "ExponentPushToken[test]",
      "ios"
    );
    unmount();
  });

  it("does nothing when user is not authenticated", async () => {
    withAccessToken(null);
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(mockRegisterToken).not.toHaveBeenCalled();
    unmount();
  });

  it("skips registration on simulator/emulator", async () => {
    withAccessToken("token");
    (Device as { isDevice: boolean }).isDevice = false;
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(mockRegisterToken).not.toHaveBeenCalled();
    unmount();
  });

  it("skips registration when permission is initially granted but then denied on request", async () => {
    withAccessToken("token");
    (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
      status: "undetermined",
    });
    (Notifications.requestPermissionsAsync as jest.Mock).mockResolvedValue({
      status: "denied",
    });
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(mockRegisterToken).not.toHaveBeenCalled();
    unmount();
  });

  it("requests permission when status is not already granted", async () => {
    withAccessToken("token");
    (Notifications.getPermissionsAsync as jest.Mock).mockResolvedValue({
      status: "undetermined",
    });
    (Notifications.requestPermissionsAsync as jest.Mock).mockResolvedValue({
      status: "granted",
    });
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(Notifications.requestPermissionsAsync).toHaveBeenCalled();
    expect(mockRegisterToken).toHaveBeenCalled();
    unmount();
  });

  it("creates Android notification channel on Android", async () => {
    withAccessToken("token");
    Object.defineProperty(Platform, "OS", { value: "android", configurable: true });
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(Notifications.setNotificationChannelAsync).toHaveBeenCalledWith(
      "default",
      expect.objectContaining({ name: "FunSheep" })
    );
    expect(mockRegisterToken).toHaveBeenCalledWith(
      "ExponentPushToken[test]",
      "android"
    );
    unmount();
  });

  it("uses 'web' platform for non-iOS/Android", async () => {
    withAccessToken("token");
    Object.defineProperty(Platform, "OS", { value: "web", configurable: true });
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    expect(mockRegisterToken).toHaveBeenCalledWith(
      "ExponentPushToken[test]",
      "web"
    );
    unmount();
  });

  it("swallows token registration errors silently", async () => {
    withAccessToken("token");
    mockRegisterToken.mockRejectedValue(new Error("Network error"));
    // Should not throw
    const { unmount } = renderHook(() => usePushRegistration());
    await act(async () => {
      await new Promise((r) => setTimeout(r, 50));
    });
    unmount();
  });
});
