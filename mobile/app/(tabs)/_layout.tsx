import { Tabs } from "expo-router";
import { useWindowDimensions } from "react-native";
import { TabletSidebar } from "@/components/TabletSidebar";

export default function TabsLayout() {
  const { width } = useWindowDimensions();
  const isTablet = width >= 768;

  if (isTablet) {
    return <TabletSidebar />;
  }

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: "#1e1b4b",
          borderTopColor: "#312e81",
        },
        tabBarActiveTintColor: "#7c3aed",
        tabBarInactiveTintColor: "#6b7280",
      }}
    >
      <Tabs.Screen
        name="index"
        options={{ title: "Home", tabBarLabel: "Home" }}
      />
      <Tabs.Screen
        name="courses"
        options={{ title: "Courses", tabBarLabel: "Courses" }}
      />
      <Tabs.Screen
        name="practice"
        options={{ title: "Practice", tabBarLabel: "Practice" }}
      />
      <Tabs.Screen
        name="profile"
        options={{ title: "Profile", tabBarLabel: "Profile" }}
      />
    </Tabs>
  );
}
