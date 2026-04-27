import React from "react";
import { render } from "@testing-library/react-native";
import TabsLayout from "@/app/(tabs)/_layout";

const mockUseWindowDimensions = jest.fn(() => ({ width: 375, height: 812 }));

jest.mock("react-native/Libraries/Utilities/useWindowDimensions", () => ({
  default: () => mockUseWindowDimensions(),
}));

jest.mock("@/components/TabletSidebar", () => ({
  TabletSidebar: () => null,
}));

jest.mock("expo-router", () => {
  const mockTabs = ({ children }: { children?: React.ReactNode }) =>
    children ?? null;
  mockTabs.Screen = () => null;
  return { Tabs: mockTabs };
});

describe("TabsLayout", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("renders Tabs navigation on phone-width screens", () => {
    mockUseWindowDimensions.mockReturnValue({ width: 375, height: 812 });
    expect(() => render(<TabsLayout />)).not.toThrow();
  });

  it("renders TabletSidebar on tablet-width screens (>= 768px)", () => {
    mockUseWindowDimensions.mockReturnValue({ width: 800, height: 1024 });
    const { TabletSidebar } = require("@/components/TabletSidebar");
    expect(() => render(<TabsLayout />)).not.toThrow();
  });
});
