import * as SecureStore from "expo-secure-store";
import { useAuthStore } from "@/store/auth";

const mockSetItemAsync = SecureStore.setItemAsync as jest.Mock;
const mockDeleteItemAsync = SecureStore.deleteItemAsync as jest.Mock;
const mockGetItemAsync = SecureStore.getItemAsync as jest.Mock;

const ACCESS_KEY = "funsheep_access_token";
const REFRESH_KEY = "funsheep_refresh_token";

describe("useAuthStore", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useAuthStore.setState({
      accessToken: null,
      refreshToken: null,
      isLoading: true,
    });
  });

  it("has correct initial state", () => {
    const { accessToken, refreshToken, isLoading } = useAuthStore.getState();
    expect(accessToken).toBeNull();
    expect(refreshToken).toBeNull();
    expect(isLoading).toBe(true);
  });

  describe("setTokens", () => {
    it("persists tokens in SecureStore", async () => {
      mockSetItemAsync.mockResolvedValue(null);
      await useAuthStore.getState().setTokens("acc123", "ref456");
      expect(mockSetItemAsync).toHaveBeenCalledWith(ACCESS_KEY, "acc123");
      expect(mockSetItemAsync).toHaveBeenCalledWith(REFRESH_KEY, "ref456");
    });

    it("updates in-memory state after persisting", async () => {
      mockSetItemAsync.mockResolvedValue(null);
      await useAuthStore.getState().setTokens("acc123", "ref456");
      const { accessToken, refreshToken } = useAuthStore.getState();
      expect(accessToken).toBe("acc123");
      expect(refreshToken).toBe("ref456");
    });
  });

  describe("clearTokens", () => {
    it("removes tokens from SecureStore", async () => {
      mockDeleteItemAsync.mockResolvedValue(null);
      useAuthStore.setState({ accessToken: "old-acc", refreshToken: "old-ref" });
      await useAuthStore.getState().clearTokens();
      expect(mockDeleteItemAsync).toHaveBeenCalledWith(ACCESS_KEY);
      expect(mockDeleteItemAsync).toHaveBeenCalledWith(REFRESH_KEY);
    });

    it("nulls out in-memory tokens", async () => {
      mockDeleteItemAsync.mockResolvedValue(null);
      useAuthStore.setState({ accessToken: "old-acc", refreshToken: "old-ref" });
      await useAuthStore.getState().clearTokens();
      const { accessToken, refreshToken } = useAuthStore.getState();
      expect(accessToken).toBeNull();
      expect(refreshToken).toBeNull();
    });
  });

  describe("loadTokens", () => {
    it("hydrates state from SecureStore", async () => {
      mockGetItemAsync.mockImplementation((key: string) => {
        if (key === ACCESS_KEY) return Promise.resolve("stored-acc");
        if (key === REFRESH_KEY) return Promise.resolve("stored-ref");
        return Promise.resolve(null);
      });
      await useAuthStore.getState().loadTokens();
      const { accessToken, refreshToken, isLoading } = useAuthStore.getState();
      expect(accessToken).toBe("stored-acc");
      expect(refreshToken).toBe("stored-ref");
      expect(isLoading).toBe(false);
    });

    it("handles missing stored tokens gracefully", async () => {
      mockGetItemAsync.mockResolvedValue(null);
      await useAuthStore.getState().loadTokens();
      const { accessToken, refreshToken, isLoading } = useAuthStore.getState();
      expect(accessToken).toBeNull();
      expect(refreshToken).toBeNull();
      expect(isLoading).toBe(false);
    });

    it("sets isLoading to false even when only access token is present", async () => {
      mockGetItemAsync.mockImplementation((key: string) => {
        if (key === ACCESS_KEY) return Promise.resolve("acc");
        return Promise.resolve(null);
      });
      await useAuthStore.getState().loadTokens();
      expect(useAuthStore.getState().isLoading).toBe(false);
    });
  });
});
