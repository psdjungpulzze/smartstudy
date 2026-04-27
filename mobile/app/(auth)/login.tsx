import { useCallback, useState } from "react";
import {
  View,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  Alert,
} from "react-native";
import * as WebBrowser from "expo-web-browser";
import * as Linking from "expo-linking";
import * as Crypto from "expo-crypto";
import Constants from "expo-constants";
import { useAuthStore } from "@/store/auth";
import { api } from "@/lib/api";

WebBrowser.maybeCompleteAuthSession();

const BASE_URL =
  (Constants.expoConfig?.extra?.apiBaseUrl as string) ?? "https://funsheep.com";

async function generatePKCE() {
  const verifier = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    Math.random().toString(36).slice(2),
    { encoding: Crypto.CryptoEncoding.BASE64 }
  );
  const challenge = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    verifier,
    { encoding: Crypto.CryptoEncoding.BASE64 }
  );
  return { verifier, challenge };
}

export default function LoginScreen() {
  const [loading, setLoading] = useState(false);
  const setTokens = useAuthStore((s) => s.setTokens);

  const handleLogin = useCallback(async () => {
    setLoading(true);
    try {
      const { verifier, challenge } = await generatePKCE();
      const redirectUri = Linking.createURL("/auth/callback");

      const urlRes = await fetch(`${BASE_URL}/api/v1/auth/authorize_url`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          redirect_uri: redirectUri,
          code_challenge: challenge,
          code_challenge_method: "S256",
        }),
      });

      if (!urlRes.ok) throw new Error("Failed to get authorize URL");
      const { data } = await urlRes.json();

      const result = await WebBrowser.openAuthSessionAsync(
        data.url,
        redirectUri
      );

      if (result.type !== "success") return;

      const url = new URL(result.url);
      const code = url.searchParams.get("code");
      if (!code) throw new Error("No code returned");

      const tokenRes = await fetch(`${BASE_URL}/api/v1/auth/token`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          code,
          code_verifier: verifier,
          redirect_uri: redirectUri,
        }),
      });

      if (!tokenRes.ok) throw new Error("Token exchange failed");
      const tokenBody = await tokenRes.json();
      await setTokens(
        tokenBody.data.access_token,
        tokenBody.data.refresh_token
      );
    } catch (e) {
      Alert.alert("Sign-in failed", (e as Error).message);
    } finally {
      setLoading(false);
    }
  }, [setTokens]);

  return (
    <View className="flex-1 items-center justify-center bg-base-100 px-8">
      <View className="mb-12 items-center">
        <Text className="text-5xl font-bold text-primary">🐑</Text>
        <Text className="mt-3 text-3xl font-bold text-white">FunSheep</Text>
        <Text className="mt-1 text-base text-gray-400">
          Study smarter, not harder
        </Text>
      </View>

      <TouchableOpacity
        onPress={handleLogin}
        disabled={loading}
        className="w-full items-center rounded-xl bg-primary py-4"
      >
        {loading ? (
          <ActivityIndicator color="white" />
        ) : (
          <Text className="text-base font-semibold text-white">
            Sign in with FunSheep
          </Text>
        )}
      </TouchableOpacity>
    </View>
  );
}
