import { View, Text, ScrollView, TouchableOpacity } from "react-native";
import { useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { notificationsApi, coursesApi, type Notification } from "@/lib/api";

export default function DashboardScreen() {
  const router = useRouter();

  const { data: courses } = useQuery({
    queryKey: ["courses"],
    queryFn: () => coursesApi.list(),
  });

  const { data: notifications } = useQuery({
    queryKey: ["notifications"],
    queryFn: () => notificationsApi.list(),
  });

  const unread = notifications?.data ?? [];
  const recentCourses = courses?.data?.slice(0, 3) ?? [];

  return (
    <SafeAreaView className="flex-1 bg-base-100">
      <ScrollView className="flex-1 px-4 pt-2">
        <Text className="mb-4 text-2xl font-bold text-white">Dashboard</Text>

        {unread.length > 0 && (
          <View className="mb-6">
            <Text className="mb-2 text-sm font-semibold uppercase tracking-wider text-gray-400">
              Notifications
            </Text>
            {unread.slice(0, 3).map((n: Notification) => (
              <TouchableOpacity
                key={n.id}
                onPress={() => notificationsApi.markRead(n.id)}
                className="mb-2 rounded-xl bg-base-200 p-4"
              >
                <Text className="font-semibold text-white">{n.title}</Text>
                <Text className="mt-1 text-sm text-gray-400">{n.body}</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}

        <View className="mb-6">
          <Text className="mb-2 text-sm font-semibold uppercase tracking-wider text-gray-400">
            Your Courses
          </Text>
          {recentCourses.map((c) => (
            <TouchableOpacity
              key={c.id}
              onPress={() =>
                router.push(`/(tabs)/courses/${c.id}` as never)
              }
              className="mb-3 rounded-xl bg-base-200 p-4"
            >
              <Text className="font-semibold text-white">{c.name}</Text>
              <Text className="mt-1 text-xs text-gray-400">
                {c.chapter_count} chapters · {c.question_count} questions
              </Text>
            </TouchableOpacity>
          ))}

          <TouchableOpacity
            onPress={() => router.push("/(tabs)/courses" as never)}
            className="mt-1 items-center py-2"
          >
            <Text className="text-sm text-primary">View all courses →</Text>
          </TouchableOpacity>
        </View>

        <TouchableOpacity
          onPress={() => router.push("/(tabs)/practice" as never)}
          className="mb-6 items-center rounded-xl bg-primary py-5"
        >
          <Text className="text-lg font-bold text-white">Start Practice</Text>
          <Text className="mt-1 text-xs text-purple-200">
            Swipe through questions
          </Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}
