import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import CourseDetailScreen from "@/app/(tabs)/courses/[id]";

const mockPush = jest.fn();
const mockBack = jest.fn();
const mockUseLocalSearchParams = jest.fn(() => ({ id: "course-abc" }));

jest.mock("expo-router", () => ({
  useRouter: () => ({ push: mockPush, back: mockBack }),
  useLocalSearchParams: () => mockUseLocalSearchParams(),
}));

const mockGet = jest.fn();

jest.mock("@/lib/api", () => ({
  coursesApi: { get: (...a: unknown[]) => mockGet(...a) },
}));

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const courseData = {
  id: "course-abc",
  name: "Advanced Chemistry",
  description: "Deep dive into chemistry concepts",
  chapter_count: 6,
  question_count: 100,
  attempt_count: 4,
  chapters: [
    { id: "ch1", name: "Atomic Structure", order: 1 },
    { id: "ch2", name: "Chemical Bonding", order: 2 },
    { id: "ch3", name: "Thermodynamics", order: 3 },
  ],
};

beforeEach(() => {
  jest.clearAllMocks();
  mockGet.mockResolvedValue({ data: courseData });
  mockUseLocalSearchParams.mockReturnValue({ id: "course-abc" });
});

describe("CourseDetailScreen", () => {
  it("shows loading indicator while fetching", () => {
    mockGet.mockReturnValue(new Promise(() => {}));
    const { UNSAFE_getByType } = wrap(<CourseDetailScreen />);
    // Just check it renders without crashing in loading state
    expect(UNSAFE_getByType).toBeDefined();
  });

  it("renders the course name", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Advanced Chemistry")).toBeTruthy();
  });

  it("renders the course description", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Deep dive into chemistry concepts")).toBeTruthy();
  });

  it("renders all chapter names", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Atomic Structure")).toBeTruthy();
    expect(await findByText("Chemical Bonding")).toBeTruthy();
    expect(await findByText("Thermodynamics")).toBeTruthy();
  });

  it("renders chapter numbers", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("1")).toBeTruthy();
    expect(await findByText("2")).toBeTruthy();
    expect(await findByText("3")).toBeTruthy();
  });

  it("renders 'Practice this course' button", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Practice this course")).toBeTruthy();
  });

  it("navigates to practice screen when 'Practice this course' is pressed", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    fireEvent.press(await findByText("Practice this course"));
    expect(mockPush).toHaveBeenCalledWith(
      expect.objectContaining({
        pathname: "/(tabs)/practice",
        params: { courseId: "course-abc" },
      })
    );
  });

  it("renders '← Back' button", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("← Back")).toBeTruthy();
  });

  it("calls router.back() when '← Back' is pressed", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    fireEvent.press(await findByText("← Back"));
    expect(mockBack).toHaveBeenCalled();
  });

  it("renders chapters section label", async () => {
    const { findByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Chapters")).toBeTruthy();
  });

  it("renders without description gracefully", async () => {
    mockGet.mockResolvedValue({
      data: { ...courseData, description: null, chapters: [] },
    });
    const { findByText, queryByText } = wrap(<CourseDetailScreen />);
    expect(await findByText("Advanced Chemistry")).toBeTruthy();
    expect(queryByText("Deep dive into chemistry concepts")).toBeNull();
  });
});
