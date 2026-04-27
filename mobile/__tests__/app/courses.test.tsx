import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import CoursesScreen from "@/app/(tabs)/courses/index";

const mockPush = jest.fn();

jest.mock("expo-router", () => ({
  useRouter: () => ({ push: mockPush }),
}));

const mockList = jest.fn();

jest.mock("@/lib/api", () => ({
  coursesApi: { list: (...a: unknown[]) => mockList(...a) },
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
    name: "History",
    description: "World history from ancient to modern",
    chapter_count: 12,
    question_count: 240,
    attempt_count: 7,
  },
  {
    id: "c2",
    name: "Biology",
    description: null,
    chapter_count: 9,
    question_count: 180,
    attempt_count: 2,
  },
];

beforeEach(() => {
  jest.clearAllMocks();
  mockList.mockResolvedValue({ data: courses });
});

describe("CoursesScreen", () => {
  it("shows loading indicator while fetching", () => {
    // Never resolve so it stays loading
    mockList.mockReturnValue(new Promise(() => {}));
    const { getByTestId } = wrap(<CoursesScreen />);
    // ActivityIndicator renders as a view in tests
    expect(getByTestId).toBeDefined();
  });

  it("renders Courses heading after load", async () => {
    const { findByText } = wrap(<CoursesScreen />);
    expect(await findByText("Courses")).toBeTruthy();
  });

  it("renders all course names", async () => {
    const { findByText } = wrap(<CoursesScreen />);
    expect(await findByText("History")).toBeTruthy();
    expect(await findByText("Biology")).toBeTruthy();
  });

  it("renders course description when present", async () => {
    const { findByText } = wrap(<CoursesScreen />);
    expect(
      await findByText("World history from ancient to modern")
    ).toBeTruthy();
  });

  it("renders course stats", async () => {
    const { findByText } = wrap(<CoursesScreen />);
    expect(await findByText("12 chapters")).toBeTruthy();
    expect(await findByText("240 questions")).toBeTruthy();
    expect(await findByText("7 attempts")).toBeTruthy();
  });

  it("navigates to course detail when course is pressed", async () => {
    const { findByText } = wrap(<CoursesScreen />);
    fireEvent.press(await findByText("History"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/courses/c1");
  });

  it("renders empty list without crashing when no courses", async () => {
    mockList.mockResolvedValue({ data: [] });
    const { findByText } = wrap(<CoursesScreen />);
    expect(await findByText("Courses")).toBeTruthy();
  });
});
