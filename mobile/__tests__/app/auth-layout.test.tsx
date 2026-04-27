import React from "react";
import { render } from "@testing-library/react-native";
import AuthLayout from "@/app/(auth)/_layout";

jest.mock("expo-router", () => ({
  Stack: Object.assign(
    ({ children }: { children?: React.ReactNode }) => children ?? null,
    { Screen: () => null }
  ),
}));

describe("AuthLayout", () => {
  it("renders without crashing", () => {
    expect(() => render(<AuthLayout />)).not.toThrow();
  });
});
