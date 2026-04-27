import { View, Text, TouchableOpacity, ScrollView } from "react-native";
import { useQuery } from "@tanstack/react-query";
import { SafeAreaView } from "react-native-safe-area-context";
import { useAuthStore } from "@/store/auth";
import { api } from "@/lib/api";

interface UserProfile {
  id: string;
  email: string;
  name: string | null;
  role: string;
}

export default function ProfileScreen() {
  const clearTokens = useAuthStore((s) => s.clearTokens);

  const { data } = useQuery({
    queryKey: ["me"],
    queryFn: () => api.get<{ data: UserProfile }>("/api/v1/users/me"),
  });

  const user = data?.data;

  return (
    <SafeAreaView className="flex-1 bg-base-100">
      <ScrollView className="flex-1 px-4 pt-2">
        <Text className="mb-6 text-2xl font-bold text-white">Profile</Text>

        {user && (
          <View className="mb-6 rounded-xl bg-base-200 p-5">
            <View className="mb-4 h-16 w-16 items-center justify-center rounded-full bg-primary">
              <Text className="text-2xl font-bold text-white">
                {(user.name ?? user.email)[0].toUpperCase()}
              </Text>
            </View>
            <Text className="text-lg font-semibold text-white">
              {user.name ?? "Student"}
            </Text>
            <Text className="mt-1 text-sm text-gray-400">{user.email}</Text>
            <View className="mt-2 self-start rounded-full bg-primary/20 px-3 py-1">
              <Text className="text-xs capitalize text-primary">{user.role}</Text>
            </View>
          </View>
        )}

        <TouchableOpacity
          onPress={clearTokens}
          className="items-center rounded-xl bg-red-900/40 py-4"
        >
          <Text className="font-semibold text-red-400">Sign Out</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}
