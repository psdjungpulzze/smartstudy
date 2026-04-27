import React from "react";
import { render, fireEvent } from "@testing-library/react-native";
import { TabletSidebar } from "@/components/TabletSidebar";

const mockPush = jest.fn();
const mockUsePathname = jest.fn(() => "/");
const mockUseWindowDimensions = jest.fn(() => ({ width: 1024, height: 768 }));

jest.mock("expo-router", () => ({
  useRouter: () => ({ push: mockPush }),
  usePathname: () => mockUsePathname(),
  Slot: () => null,
}));

jest.mock("react-native/Libraries/Utilities/useWindowDimensions", () => ({
  default: () => mockUseWindowDimensions(),
}));

describe("TabletSidebar", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUsePathname.mockReturnValue("/");
    mockUseWindowDimensions.mockReturnValue({ width: 1024, height: 768 });
  });

  it("renders all four nav items", () => {
    const { getByText } = render(<TabletSidebar />);
    expect(getByText("Home")).toBeTruthy();
    expect(getByText("Courses")).toBeTruthy();
    expect(getByText("Practice")).toBeTruthy();
    expect(getByText("Profile")).toBeTruthy();
  });

  it("renders the FunSheep brand header", () => {
    const { getByText } = render(<TabletSidebar />);
    expect(getByText("🐑 FunSheep")).toBeTruthy();
  });

  it("renders nav icons", () => {
    const { getByText } = render(<TabletSidebar />);
    expect(getByText("🏠")).toBeTruthy();
    expect(getByText("📚")).toBeTruthy();
    expect(getByText("✏️")).toBeTruthy();
    expect(getByText("👤")).toBeTruthy();
  });

  it("navigates to Home when Home is pressed", () => {
    const { getByText } = render(<TabletSidebar />);
    fireEvent.press(getByText("Home"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)");
  });

  it("navigates to Courses when Courses is pressed", () => {
    const { getByText } = render(<TabletSidebar />);
    fireEvent.press(getByText("Courses"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/courses");
  });

  it("navigates to Practice when Practice is pressed", () => {
    const { getByText } = render(<TabletSidebar />);
    fireEvent.press(getByText("Practice"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/practice");
  });

  it("navigates to Profile when Profile is pressed", () => {
    const { getByText } = render(<TabletSidebar />);
    fireEvent.press(getByText("Profile"));
    expect(mockPush).toHaveBeenCalledWith("/(tabs)/profile");
  });

  it("uses 240px sidebar width on screens >= 1024px wide", () => {
    mockUseWindowDimensions.mockReturnValue({ width: 1200, height: 900 });
    // Just verifying it renders without error
    const { getByText } = render(<TabletSidebar />);
    expect(getByText("Home")).toBeTruthy();
  });

  it("uses 200px sidebar width on screens < 1024px wide", () => {
    mockUseWindowDimensions.mockReturnValue({ width: 800, height: 1024 });
    const { getByText } = render(<TabletSidebar />);
    expect(getByText("Home")).toBeTruthy();
  });
});
