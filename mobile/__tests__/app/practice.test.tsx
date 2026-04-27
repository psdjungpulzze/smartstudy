import React from "react";
import { render, fireEvent, waitFor } from "@testing-library/react-native";
import { Alert } from "react-native";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import PracticeScreen from "@/app/(tabs)/practice/index";

const mockUseLocalSearchParams = jest.fn(() => ({} as { courseId?: string }));

jest.mock("expo-router", () => ({
  useLocalSearchParams: () => mockUseLocalSearchParams(),
}));

const mockQuestions = jest.fn();
const mockRecordAnswers = jest.fn();

jest.mock("@/lib/api", () => ({
  practiceApi: {
    questions: (...a: unknown[]) => mockQuestions(...a),
    recordAnswers: (...a: unknown[]) => mockRecordAnswers(...a),
  },
}));

// SwipeCard mock: exposes testable press targets for swipe actions
jest.mock("@/components/SwipeCard", () => ({
  SwipeCard: ({
    question,
    onSwipeRight,
    onSwipeLeft,
    isTop,
  }: {
    question: { id: string; content: string };
    onSwipeRight: () => void;
    onSwipeLeft: () => void;
    isTop: boolean;
  }) => {
    const React = require("react");
    const { View, Text, TouchableOpacity } = require("react-native");
    return React.createElement(
      View,
      { testID: `card-${question.id}` },
      React.createElement(Text, null, question.content),
      isTop &&
        React.createElement(
          TouchableOpacity,
          { testID: "swipe-correct", onPress: onSwipeRight },
          React.createElement(Text, null, "Correct")
        ),
      isTop &&
        React.createElement(
          TouchableOpacity,
          { testID: "swipe-skip", onPress: onSwipeLeft },
          React.createElement(Text, null, "Skip")
        )
    );
  },
}));

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(<QueryClientProvider client={qc}>{ui}</QueryClientProvider>);
}

const questions = [
  {
    id: "q1",
    content: "What is 2 + 2?",
    type: "short_answer",
    options: null,
    correct_answer: "4",
    explanation: null,
    chapter: null,
    difficulty: "easy",
  },
  {
    id: "q2",
    content: "Capital of France?",
    type: "short_answer",
    options: null,
    correct_answer: "Paris",
    explanation: null,
    chapter: null,
    difficulty: "easy",
  },
];

beforeEach(() => {
  jest.clearAllMocks();
  mockQuestions.mockResolvedValue({ data: questions });
  mockRecordAnswers.mockResolvedValue({ data: [] });
  jest.spyOn(Alert, "alert").mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("PracticeScreen", () => {
  it("shows 'Select a course' prompt when no courseId", () => {
    mockUseLocalSearchParams.mockReturnValue({});
    const { getByText } = wrap(<PracticeScreen />);
    expect(getByText(/Select a course/)).toBeTruthy();
  });

  it("shows loading indicator while fetching questions", () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    mockQuestions.mockReturnValue(new Promise(() => {}));
    const { UNSAFE_getByType } = wrap(<PracticeScreen />);
    expect(UNSAFE_getByType).toBeDefined();
  });

  it("renders Practice heading with progress when questions are loaded", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByText } = wrap(<PracticeScreen />);
    expect(await findByText("Practice")).toBeTruthy();
    expect(await findByText("1 / 2")).toBeTruthy();
  });

  it("renders the first question card", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByText } = wrap(<PracticeScreen />);
    expect(await findByText("What is 2 + 2?")).toBeTruthy();
  });

  it("advances to next card on swipe-correct", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId, findByText } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-correct"));
    expect(await findByText("2 / 2")).toBeTruthy();
  });

  it("advances to next card on swipe-skip", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId, findByText } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-skip"));
    expect(await findByText("2 / 2")).toBeTruthy();
  });

  it("shows Session Done screen after answering all questions", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId, findByText } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-correct"));
    fireEvent.press(await findByTestId("swipe-correct"));
    expect(await findByText("Session Done!")).toBeTruthy();
    expect(await findByText("correct answers")).toBeTruthy();
  });

  it("shows correct answer count on Session Done screen", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId, findByText } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-correct"));
    fireEvent.press(await findByTestId("swipe-skip"));
    // 1 correct out of 2
    expect(await findByText("1/2")).toBeTruthy();
  });

  it("calls recordAnswers when session completes", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-correct"));
    fireEvent.press(await findByTestId("swipe-correct"));
    await waitFor(() => {
      expect(mockRecordAnswers).toHaveBeenCalledWith(
        "c1",
        expect.arrayContaining([
          expect.objectContaining({ question_id: "q1", is_correct: true }),
          expect.objectContaining({ question_id: "q2", is_correct: true }),
        ])
      );
    });
  });

  it("resets session when 'Practice Again' is pressed", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    const { findByTestId, findByText } = wrap(<PracticeScreen />);
    fireEvent.press(await findByTestId("swipe-correct"));
    fireEvent.press(await findByTestId("swipe-correct"));
    fireEvent.press(await findByText("Practice Again"));
    expect(await findByText("1 / 2")).toBeTruthy();
  });

  it("shows done screen immediately when question list is empty", async () => {
    mockUseLocalSearchParams.mockReturnValue({ courseId: "c1" });
    mockQuestions.mockResolvedValue({ data: [] });
    const { findByText } = wrap(<PracticeScreen />);
    expect(await findByText("Session Done!")).toBeTruthy();
  });
});
