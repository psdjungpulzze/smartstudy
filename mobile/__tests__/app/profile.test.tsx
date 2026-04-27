import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import ProfileScreen from "@/app/(tabs)/profile";

const mockClearTokens = jest.fn().mockResolvedValue(undefined);
const mockUseAuthStore = jest.fn();

jest.mock("@/store/auth", () => ({
  useAuthStore: (selector: (s: unknown) => unknown) =>
    mockUseAuthStore(selector),
}));

const mockApiGet = jest.fn();

jest.mock("@/lib/api", () => ({
  api: { get: (...a: unknown[]) => mockApiGet(...a) },
}));

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

beforeEach(() => {
  jest.clearAllMocks();
  mockUseAuthStore.mockImplementation(
    (selector: (s: { clearTokens: jest.Mock }) => unknown) =>
      selector({ clearTokens: mockClearTokens })
  );
  mockApiGet.mockResolvedValue({
    data: {
      id: "u1",
      email: "student@example.com",
      name: "Alice Smith",
      role: "student",
    },
  });
});

describe("ProfileScreen", () => {
  it("renders the Profile heading", () => {
    const { getByText } = wrap(<ProfileScreen />);
    expect(getByText("Profile")).toBeTruthy();
  });

  it("renders user name after loading", async () => {
    const { findByText } = wrap(<ProfileScreen />);
    expect(await findByText("Alice Smith")).toBeTruthy();
  });

  it("renders user email", async () => {
    const { findByText } = wrap(<ProfileScreen />);
    expect(await findByText("student@example.com")).toBeTruthy();
  });

  it("renders user role badge", async () => {
    const { findByText } = wrap(<ProfileScreen />);
    expect(await findByText("student")).toBeTruthy();
  });

  it("renders avatar initial from name", async () => {
    const { findByText } = wrap(<ProfileScreen />);
    expect(await findByText("A")).toBeTruthy();
  });

  it("falls back to email initial when name is null", async () => {
    mockApiGet.mockResolvedValue({
      data: {
        id: "u2",
        email: "zach@example.com",
        name: null,
        role: "teacher",
      },
    });
    const { findByText } = wrap(<ProfileScreen />);
    // Avatar shows first letter of email
    expect(await findByText("Z")).toBeTruthy();
    // Falls back to 'Student' display name
    expect(await findByText("Student")).toBeTruthy();
  });

  it("renders Sign Out button", () => {
    const { getByText } = wrap(<ProfileScreen />);
    expect(getByText("Sign Out")).toBeTruthy();
  });

  it("calls clearTokens when Sign Out is pressed", async () => {
    const { getByText } = wrap(<ProfileScreen />);
    fireEvent.press(getByText("Sign Out"));
    await waitFor(() => {
      expect(mockClearTokens).toHaveBeenCalled();
    });
  });

  it("fetches user profile from /api/v1/users/me", async () => {
    wrap(<ProfileScreen />);
    await waitFor(() => {
      expect(mockApiGet).toHaveBeenCalledWith("/api/v1/users/me");
    });
  });
});
