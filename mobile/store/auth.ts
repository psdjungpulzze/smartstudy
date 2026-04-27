import * as SecureStore from "expo-secure-store";
import { create } from "zustand";

const ACCESS_KEY = "funsheep_access_token";
const REFRESH_KEY = "funsheep_refresh_token";

interface AuthState {
  accessToken: string | null;
  refreshToken: string | null;
  isLoading: boolean;
  setTokens: (access: string, refresh: string) => Promise<void>;
  clearTokens: () => Promise<void>;
  loadTokens: () => Promise<void>;
}

export const useAuthStore = create<AuthState>((set) => ({
  accessToken: null,
  refreshToken: null,
  isLoading: true,

  setTokens: async (access, refresh) => {
    await SecureStore.setItemAsync(ACCESS_KEY, access);
    await SecureStore.setItemAsync(REFRESH_KEY, refresh);
    set({ accessToken: access, refreshToken: refresh });
  },

  clearTokens: async () => {
    await SecureStore.deleteItemAsync(ACCESS_KEY);
    await SecureStore.deleteItemAsync(REFRESH_KEY);
    set({ accessToken: null, refreshToken: null });
  },

  loadTokens: async () => {
    const access = await SecureStore.getItemAsync(ACCESS_KEY);
    const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
    set({ accessToken: access, refreshToken: refresh, isLoading: false });
  },
}));
