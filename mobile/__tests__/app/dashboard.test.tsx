import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import DashboardScreen from "@/app/(tabs)/index";

const mockPush = jest.fn();

jest.mock("expo-router", () => ({
  useRouter: () => ({ push: mockPush }),
}));

const mockCoursesApiList = jest.fn();
const mockNotificationsApiList = jest.fn();
const mockNotificationsApiMarkRead = jest.fn();

jest.mock("@/lib/api", () => ({
  coursesApi: { list: (...a: unknown[]) => mockCoursesApiList(...a) },
  notificationsApi: {
    list: (...a: unknown[]) => mockNotificationsApiList(...a),
    markRead: (...a: unknown[]) => mockNotificationsApiMarkRead(...a),
  },
}));

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const courses = [
  {
    id: "c1",
    name: "Mathematics",
    description: "Core math",
    chapter_count: 8,
    question_count: 120,
    attempt_count: 3,
  },
  {
    id: "c2",
    name: "Physics",
    description: null,
    chapter_count: 5,
    question_count: 80,
    attempt_count: 1,
  },
];

const notifications = [
  {
    id: "n1",
    type: "info",
    title: "New course available",
    body: "Check out the new Mathematics course",
    action_url: null,
    inserted_at: "2024-01-01T00:00:00Z",
  },
  {
    id: "n2",
    type: "alert",
    title: "Test reminder",
    body: "Your exam is tomorrow",
    action_url: "/exam",
    inserted_at: "2024-01-02T00:00:00Z",
  },
];

beforeEach(() => {
  jest.clearAllMocks();
  mockCoursesApiList.mockResolvedValue({ data: courses });
  mockNotificationsApiList.mockResolvedValue({ data: notifications });
  mockNotificationsApiMarkRead.mockResolvedValue({ ok: true });
});

describe("DashboardScreen", () => {
  it("renders the Dashboard heading", () => {
    const { getByText } = wrap(<DashboardScreen />);
    expect(getByText("Dashboard")).toBeTruthy();
  });

  it("renders notifications section when notifications exist", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    expect(await findByText("New course available")).toBeTruthy();
    expect(await findByText("Check out the new Mathematics course")).toBeTruthy();
  });

  it("renders up to 3 notifications", async () => {
    const manyNotifs = Array.from({ length: 5 }, (_, i) => ({
      id: `n${i}`,
      type: "info",
      title: `Notification ${i}`,
      body: `Body ${i}`,
      action_url: null,
      inserted_at: "2024-01-01T00:00:00Z",
    }));
    mockNotificationsApiList.mockResolvedValue({ data: manyNotifs });
    const { findByText, queryByText } = wrap(<DashboardScreen />);
    expect(await findByText("Notification 0")).toBeTruthy();
    expect(await findByText("Notification 2")).toBeTruthy();
    await waitFor(() =>
      expect(queryByText("Notification 3")).toBeNull()
    );
  });

  it("hides notifications section when there are none", async () => {
    mockNotificationsApiList.mockResolvedValue({ data: [] });
    const { queryByText } = wrap(<DashboardScreen />);
    await waitFor(() =>
      expect(queryByText("Notifications")).toBeNull()
    );
  });

  it("marks notification as read when pressed", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    const notif = await findByText("New course available");
    fireEvent.press(notif);
    expect(mockNotificationsApiMarkRead).toHaveBeenCalledWith("n1");
  });

  it("renders recent courses", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    expect(await findByText("Mathematics")).toBeTruthy();
  });

  it("shows chapter and question counts for courses", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    expect(await findByText("8 chapters · 120 questions")).toBeTruthy();
  });

  it("navigates to course detail when a course is pressed", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    fireEvent.press(await findByText("Mathematics"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/courses/c1");
  });

  it("navigates to all courses when 'View all courses' is pressed", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    fireEvent.press(await findByText("View all courses →"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/courses");
  });

  it("navigates to practice when 'Start Practice' is pressed", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    fireEvent.press(await findByText("Start Practice"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/practice");
  });

  it("renders courses section label", async () => {
    const { findByText } = wrap(<DashboardScreen />);
    expect(await findByText("Your Courses")).toBeTruthy();
  });
});
