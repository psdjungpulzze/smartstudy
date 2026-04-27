import { useEffect } from "react";
import * as Notifications from "expo-notifications";
import * as Device from "expo-device";
import { Platform } from "react-native";
import Constants from "expo-constants";
import { notificationsApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
  }),
});

async function registerForPushNotifications(): Promise<string | null> {
  if (!Device.isDevice) {
    // Push notifications don't work in simulators
    return null;
  }

  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;

  if (existingStatus !== "granted") {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }

  if (finalStatus !== "granted") {
    return null;
  }

  // Android requires a notification channel
  if (Platform.OS === "android") {
    await Notifications.setNotificationChannelAsync("default", {
      name: "FunSheep",
      importance: Notifications.AndroidImportance.MAX,
      vibrationPattern: [0, 250, 250, 250],
    });
  }

  const projectId =
    Constants.expoConfig?.extra?.eas?.projectId ??
    Constants.easConfig?.projectId;

  const token = await Notifications.getExpoPushTokenAsync({ projectId });
  return token.data; // e.g. "ExponentPushToken[xxx]"
}

export function usePushRegistration() {
  const accessToken = useAuthStore((s) => s.accessToken);

  useEffect(() => {
    if (!accessToken) return;

    registerForPushNotifications().then((expoToken) => {
      if (!expoToken) return;
      const platform =
        Platform.OS === "ios" ? "ios" : Platform.OS === "android" ? "android" : "web";
      notificationsApi.registerToken(expoToken, platform).catch(() => {
        // Non-fatal — token registration is best-effort
      });
    });
  }, [accessToken]);
}
