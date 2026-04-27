import { View, Text, TouchableOpacity, useWindowDimensions } from "react-native";
import { usePathname, useRouter, Slot } from "expo-router";

const NAV_ITEMS = [
  { href: "/(tabs)", label: "Home", icon: "🏠" },
  { href: "/(tabs)/courses", label: "Courses", icon: "📚" },
  { href: "/(tabs)/practice", label: "Practice", icon: "✏️" },
  { href: "/(tabs)/profile", label: "Profile", icon: "👤" },
] as const;

export function TabletSidebar() {
  const router = useRouter();
  const pathname = usePathname();
  const { width } = useWindowDimensions();
  const sidebarWidth = width >= 1024 ? 240 : 200;

  return (
    <View className="flex-1 flex-row bg-base-100">
      <View
        style={{ width: sidebarWidth }}
        className="border-r border-base-200 bg-base-200 px-3 py-6"
      >
        <Text className="mb-8 px-3 text-xl font-bold text-white">🐑 FunSheep</Text>
        {NAV_ITEMS.map((item) => {
          const active = pathname.startsWith(item.href.replace("/(tabs)", ""));
          return (
            <TouchableOpacity
              key={item.href}
              onPress={() => router.push(item.href as never)}
              className={`mb-1 flex-row items-center gap-3 rounded-xl px-3 py-3 ${
                active ? "bg-primary/20" : ""
              }`}
            >
              <Text className="text-lg">{item.icon}</Text>
              <Text
                className={`font-medium ${active ? "text-primary" : "text-gray-300"}`}
              >
                {item.label}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>

      <View className="flex-1">
        <Slot />
      </View>
    </View>
  );
}
