import React from "react";
import { render } from "@testing-library/react-native";
import { SwipeCard } from "@/components/SwipeCard";
import type { Question } from "@/lib/api";

const shortAnswerQ: Question = {
  id: "q1",
  content: "What is the boiling point of water?",
  type: "short_answer",
  options: null,
  correct_answer: "100°C",
  explanation: "Water boils at 100°C at standard pressure.",
  chapter: "Chapter 1",
  difficulty: "easy",
};

const multipleChoiceQ: Question = {
  id: "q2",
  content: "Which planet is closest to the Sun?",
  type: "multiple_choice",
  options: { A: "Venus", B: "Mercury", C: "Mars", D: "Earth" },
  correct_answer: "B",
  explanation: "Mercury is the closest planet to the Sun.",
  chapter: "Chapter 2",
  difficulty: "medium",
};

const noExplanationQ: Question = {
  ...shortAnswerQ,
  id: "q3",
  explanation: null,
};

const defaultProps = {
  question: shortAnswerQ,
  onSwipeLeft: jest.fn(),
  onSwipeRight: jest.fn(),
  isTop: true,
};

describe("SwipeCard", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("renders the question content", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("What is the boiling point of water?")).toBeTruthy();
  });

  it("renders the correct answer", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("Answer: 100°C")).toBeTruthy();
  });

  it("renders explanation when present", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(
      getByText("Water boils at 100°C at standard pressure.")
    ).toBeTruthy();
  });

  it("does not render explanation when absent", () => {
    const { queryByText } = render(
      <SwipeCard {...defaultProps} question={noExplanationQ} />
    );
    expect(queryByText("Water boils at 100°C at standard pressure.")).toBeNull();
  });

  it("renders multiple choice option keys and values", () => {
    const { getByText } = render(
      <SwipeCard {...defaultProps} question={multipleChoiceQ} />
    );
    expect(getByText("A")).toBeTruthy();
    expect(getByText("Venus")).toBeTruthy();
    expect(getByText("B")).toBeTruthy();
    expect(getByText("Mercury")).toBeTruthy();
    expect(getByText("C")).toBeTruthy();
    expect(getByText("Mars")).toBeTruthy();
    expect(getByText("D")).toBeTruthy();
    expect(getByText("Earth")).toBeTruthy();
  });

  it("does not render option list for non-multiple-choice questions", () => {
    const { queryByText } = render(<SwipeCard {...defaultProps} />);
    expect(queryByText("A")).toBeNull();
  });

  it("shows CORRECT swipe label", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("CORRECT")).toBeTruthy();
  });

  it("shows SKIP swipe label", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("SKIP")).toBeTruthy();
  });

  it("renders the tap-to-reveal hint", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("Tap to reveal answer")).toBeTruthy();
  });

  it("renders swipe direction hints", () => {
    const { getByText } = render(<SwipeCard {...defaultProps} />);
    expect(getByText("← Swipe to skip")).toBeTruthy();
    expect(getByText("Swipe correct →")).toBeTruthy();
  });

  it("renders as non-top card without crashing", () => {
    const { getByText } = render(
      <SwipeCard {...defaultProps} isTop={false} />
    );
    expect(getByText("What is the boiling point of water?")).toBeTruthy();
  });
});
