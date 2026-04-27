import { View, Text, FlatList, TouchableOpacity, ActivityIndicator } from "react-native";
import { useQuery } from "@tanstack/react-query";
import { useRouter } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { coursesApi, type Course } from "@/lib/api";

export default function CoursesScreen() {
  const router = useRouter();
  const { data, isLoading } = useQuery({
    queryKey: ["courses"],
    queryFn: () => coursesApi.list(),
  });

  if (isLoading) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-base-100">
        <ActivityIndicator size="large" color="#7c3aed" />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView className="flex-1 bg-base-100">
      <FlatList
        data={data?.data ?? []}
        keyExtractor={(item) => item.id}
        contentContainerClassName="px-4 pt-2 pb-8"
        ListHeaderComponent={
          <Text className="mb-4 text-2xl font-bold text-white">Courses</Text>
        }
        renderItem={({ item }: { item: Course }) => (
          <TouchableOpacity
            onPress={() =>
              router.push(`/(tabs)/courses/${item.id}` as never)
            }
            className="mb-3 rounded-xl bg-base-200 p-4"
          >
            <Text className="text-base font-semibold text-white">
              {item.name}
            </Text>
            {item.description && (
              <Text className="mt-1 text-sm text-gray-400" numberOfLines={2}>
                {item.description}
              </Text>
            )}
            <View className="mt-3 flex-row gap-4">
              <Text className="text-xs text-gray-500">
                {item.chapter_count} chapters
              </Text>
              <Text className="text-xs text-gray-500">
                {item.question_count} questions
              </Text>
              <Text className="text-xs text-gray-500">
                {item.attempt_count} attempts
              </Text>
            </View>
          </TouchableOpacity>
        )}
      />
    </SafeAreaView>
  );
}
