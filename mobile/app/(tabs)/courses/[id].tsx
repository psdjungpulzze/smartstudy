import { View, Text, FlatList, TouchableOpacity, ActivityIndicator } from "react-native";
import { useQuery } from "@tanstack/react-query";
import { useLocalSearchParams, useRouter } from "expo-router";
import { SafeAreaView } from "react-native-safe-area-context";
import { coursesApi } from "@/lib/api";

export default function CourseDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();

  const { data, isLoading } = useQuery({
    queryKey: ["course", id],
    queryFn: () => coursesApi.get(id),
  });

  if (isLoading) {
    return (
      <SafeAreaView className="flex-1 items-center justify-center bg-base-100">
        <ActivityIndicator size="large" color="#7c3aed" />
      </SafeAreaView>
    );
  }

  const course = data?.data;

  return (
    <SafeAreaView className="flex-1 bg-base-100">
      <FlatList
        data={course?.chapters ?? []}
        keyExtractor={(item) => item.id}
        contentContainerClassName="px-4 pt-2 pb-8"
        ListHeaderComponent={
          <View className="mb-6">
            <TouchableOpacity onPress={() => router.back()} className="mb-4">
              <Text className="text-primary">← Back</Text>
            </TouchableOpacity>
            <Text className="text-2xl font-bold text-white">{course?.name}</Text>
            {course?.description && (
              <Text className="mt-2 text-sm text-gray-400">
                {course.description}
              </Text>
            )}
            <TouchableOpacity
              onPress={() =>
                router.push({
                  pathname: "/(tabs)/practice",
                  params: { courseId: id },
                } as never)
              }
              className="mt-4 items-center rounded-xl bg-primary py-3"
            >
              <Text className="font-semibold text-white">Practice this course</Text>
            </TouchableOpacity>
            <Text className="mt-6 text-sm font-semibold uppercase tracking-wider text-gray-400">
              Chapters
            </Text>
          </View>
        }
        renderItem={({ item, index }) => (
          <View className="mb-2 flex-row items-center rounded-xl bg-base-200 p-4">
            <View className="mr-3 h-8 w-8 items-center justify-center rounded-full bg-primary/20">
              <Text className="text-xs font-bold text-primary">{index + 1}</Text>
            </View>
            <Text className="flex-1 text-sm text-white">{item.name}</Text>
          </View>
        )}
      />
    </SafeAreaView>
  );
}
