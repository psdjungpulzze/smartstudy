import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { Alert } from "react-native";
import LoginScreen from "@/app/(auth)/login";

const mockSetTokens = jest.fn().mockResolvedValue(undefined);
const mockUseAuthStore = jest.fn();

jest.mock("@/store/auth", () => ({
  useAuthStore: (selector: (s: unknown) => unknown) =>
    mockUseAuthStore(selector),
}));

jest.mock("@/lib/api", () => ({
  api: { get: jest.fn() },
}));

beforeEach(() => {
  jest.clearAllMocks();
  mockUseAuthStore.mockImplementation(
    (selector: (s: { setTokens: jest.Mock }) => unknown) =>
      selector({ setTokens: mockSetTokens })
  );
  jest.spyOn(Alert, "alert").mockImplementation(() => {});
  global.fetch = jest.fn();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("LoginScreen", () => {
  it("renders the sheep emoji logo", () => {
    const { getByText } = render(<LoginScreen />);
    expect(getByText("🐑")).toBeTruthy();
  });

  it("renders the app name", () => {
    const { getByText } = render(<LoginScreen />);
    expect(getByText("FunSheep")).toBeTruthy();
  });

  it("renders the tagline", () => {
    const { getByText } = render(<LoginScreen />);
    expect(getByText("Study smarter, not harder")).toBeTruthy();
  });

  it("renders the sign-in button", () => {
    const { getByText } = render(<LoginScreen />);
    expect(getByText("Sign in with FunSheep")).toBeTruthy();
  });

  it("shows alert when authorize URL request fails", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({ ok: false, status: 500 });
    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));
    await waitFor(() => {
      expect(Alert.alert).toHaveBeenCalledWith(
        "Sign-in failed",
        expect.any(String)
      );
    });
  });

  it("calls openAuthSessionAsync after getting authorize URL", async () => {
    const WebBrowser = require("expo-web-browser");
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({ data: { url: "https://auth.example.com/login" } }),
    });
    WebBrowser.openAuthSessionAsync.mockResolvedValue({ type: "cancel" });

    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));

    await waitFor(() => {
      expect(WebBrowser.openAuthSessionAsync).toHaveBeenCalledWith(
        "https://auth.example.com/login",
        "funsheep://auth/callback"
      );
    });
  });

  it("does nothing further when browser session is cancelled", async () => {
    const WebBrowser = require("expo-web-browser");
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: { url: "https://auth.example.com" } }),
    });
    WebBrowser.openAuthSessionAsync.mockResolvedValue({ type: "cancel" });

    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));

    await waitFor(() => {
      expect(WebBrowser.openAuthSessionAsync).toHaveBeenCalled();
    });
    expect(mockSetTokens).not.toHaveBeenCalled();
  });

  it("completes OAuth flow and stores tokens", async () => {
    const WebBrowser = require("expo-web-browser");
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({ data: { url: "https://auth.example.com" } }),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({
            data: { access_token: "acc-abc", refresh_token: "ref-xyz" },
          }),
      });
    WebBrowser.openAuthSessionAsync.mockResolvedValue({
      type: "success",
      url: "funsheep://auth/callback?code=authcode123",
    });

    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));

    await waitFor(() => {
      expect(mockSetTokens).toHaveBeenCalledWith("acc-abc", "ref-xyz");
    });
  });

  it("shows alert when token exchange fails", async () => {
    const WebBrowser = require("expo-web-browser");
    (global.fetch as jest.Mock)
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({ data: { url: "https://auth.example.com" } }),
      })
      .mockResolvedValueOnce({ ok: false, status: 400 });
    WebBrowser.openAuthSessionAsync.mockResolvedValue({
      type: "success",
      url: "funsheep://auth/callback?code=bad-code",
    });

    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));

    await waitFor(() => {
      expect(Alert.alert).toHaveBeenCalledWith(
        "Sign-in failed",
        expect.any(String)
      );
    });
  });

  it("shows alert when callback URL has no code param", async () => {
    const WebBrowser = require("expo-web-browser");
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: () =>
        Promise.resolve({ data: { url: "https://auth.example.com" } }),
    });
    WebBrowser.openAuthSessionAsync.mockResolvedValue({
      type: "success",
      url: "funsheep://auth/callback",
    });

    const { getByText } = render(<LoginScreen />);
    fireEvent.press(getByText("Sign in with FunSheep"));

    await waitFor(() => {
      expect(Alert.alert).toHaveBeenCalledWith(
        "Sign-in failed",
        expect.any(String)
      );
    });
  });
});
