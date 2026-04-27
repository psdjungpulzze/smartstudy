import React from "react";
import { render, act } from "@testing-library/react-native";
import RootLayout from "@/app/_layout";

// Must start with `mock` for jest hoisting
const mockReplace = jest.fn();
const mockUseSegments = jest.fn(() => [] as string[]);
const mockUseAuthStore = jest.fn();
const mockLoadTokens = jest.fn().mockResolvedValue(undefined);

jest.mock("expo-router", () => ({
  Stack: Object.assign(
    ({ children }: { children?: React.ReactNode }) => children ?? null,
    { Screen: () => null }
  ),
  useRouter: () => ({ replace: mockReplace }),
  useSegments: () => mockUseSegments(),
}));

jest.mock("@/store/auth", () => ({
  useAuthStore: (selector?: (s: unknown) => unknown) =>
    mockUseAuthStore(selector),
}));

jest.mock("@/lib/push", () => ({
  usePushRegistration: jest.fn(),
}));

jest.mock("@tanstack/react-query", () => ({
  QueryClient: jest.fn().mockImplementation(() => ({
    defaultOptions: {},
    getQueryCache: jest.fn(() => ({ clear: jest.fn() })),
    clear: jest.fn(),
  })),
  QueryClientProvider: ({ children }: { children?: React.ReactNode }) =>
    children ?? null,
}));

function setupAuth(opts: {
  accessToken: string | null;
  isLoading: boolean;
}) {
  mockUseAuthStore.mockImplementation(
    (selector?: (s: unknown) => unknown) => {
      const state = {
        accessToken: opts.accessToken,
        isLoading: opts.isLoading,
        loadTokens: mockLoadTokens,
      };
      return selector ? selector(state) : state;
    }
  );
}

describe("RootLayout – AuthGuard", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockLoadTokens.mockResolvedValue(undefined);
  });

  it("does not redirect while tokens are loading", async () => {
    setupAuth({ accessToken: null, isLoading: true });
    mockUseSegments.mockReturnValue([]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("redirects unauthenticated user to login when outside (auth)", async () => {
    setupAuth({ accessToken: null, isLoading: false });
    mockUseSegments.mockReturnValue(["(tabs)"]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockReplace).toHaveBeenCalledWith("/(auth)/login");
  });

  it("does not redirect unauthenticated user already on (auth)", async () => {
    setupAuth({ accessToken: null, isLoading: false });
    mockUseSegments.mockReturnValue(["(auth)"]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("redirects authenticated user from (auth) to (tabs)", async () => {
    setupAuth({ accessToken: "some-token", isLoading: false });
    mockUseSegments.mockReturnValue(["(auth)"]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockReplace).toHaveBeenCalledWith("/(tabs)");
  });

  it("does not redirect authenticated user already on (tabs)", async () => {
    setupAuth({ accessToken: "some-token", isLoading: false });
    mockUseSegments.mockReturnValue(["(tabs)"]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockReplace).not.toHaveBeenCalled();
  });

  it("calls loadTokens on mount", async () => {
    setupAuth({ accessToken: null, isLoading: true });
    mockUseSegments.mockReturnValue([]);
    render(<RootLayout />);
    await act(async () => {});
    expect(mockLoadTokens).toHaveBeenCalled();
  });
});
