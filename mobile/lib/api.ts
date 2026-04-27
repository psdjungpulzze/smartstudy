import Constants from "expo-constants";
import { useAuthStore } from "@/store/auth";

const BASE_URL =
  (Constants.expoConfig?.extra?.apiBaseUrl as string) ?? "https://funsheep.com";

class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const { accessToken, refreshToken, setTokens, clearTokens } =
    useAuthStore.getState();

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };

  if (accessToken) {
    headers["Authorization"] = `Bearer ${accessToken}`;
  }

  let response = await fetch(`${BASE_URL}${path}`, { ...options, headers });

  // Attempt one token refresh on 401
  if (response.status === 401 && refreshToken) {
    const refreshed = await fetch(`${BASE_URL}/api/v1/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });

    if (refreshed.ok) {
      const body = await refreshed.json();
      await setTokens(body.data.access_token, body.data.refresh_token);
      headers["Authorization"] = `Bearer ${body.data.access_token}`;
      response = await fetch(`${BASE_URL}${path}`, { ...options, headers });
    } else {
      await clearTokens();
      throw new ApiError(401, "Session expired");
    }
  }

  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new ApiError(response.status, body.error ?? response.statusText);
  }

  return response.json() as Promise<T>;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) =>
    request<T>(path, {
      method: "POST",
      body: JSON.stringify(body),
    }),
  put: <T>(path: string, body: unknown) =>
    request<T>(path, {
      method: "PUT",
      body: JSON.stringify(body),
    }),
  delete: <T>(path: string) => request<T>(path, { method: "DELETE" }),
};

// ── Typed helpers ────────────────────────────────────────────────────────────

export interface Course {
  id: string;
  name: string;
  description: string | null;
  chapter_count: number;
  question_count: number;
  attempt_count: number;
}

export interface Chapter {
  id: string;
  name: string;
  order: number;
}

export interface Question {
  id: string;
  content: string;
  type: string;
  options: Record<string, string> | null;
  correct_answer: string;
  explanation: string | null;
  chapter: string | null;
  difficulty: string | null;
}

export interface Notification {
  id: string;
  type: string;
  title: string;
  body: string;
  action_url: string | null;
  inserted_at: string;
}

export const coursesApi = {
  list: () => api.get<{ data: Course[] }>("/api/v1/courses"),
  get: (id: string) =>
    api.get<{ data: Course & { chapters: Chapter[] } }>(`/api/v1/courses/${id}`),
};

export const practiceApi = {
  questions: (courseId: string, limit = 20, chapterId?: string) => {
    const params = new URLSearchParams({ limit: String(limit) });
    if (chapterId) params.set("chapter_id", chapterId);
    return api.get<{ data: Question[] }>(
      `/api/v1/courses/${courseId}/practice/questions?${params}`
    );
  },
  recordAnswers: (
    courseId: string,
    answers: Array<{
      question_id: string;
      answer: string;
      is_correct: boolean;
      time_ms: number;
    }>
  ) =>
    api.post<{ data: Array<{ question_id: string; recorded: boolean }> }>(
      "/api/v1/practice/answers",
      { course_id: courseId, answers }
    ),
};

export const notificationsApi = {
  list: () => api.get<{ data: Notification[] }>("/api/v1/notifications"),
  markRead: (id: string) =>
    api.post<{ ok: boolean }>(`/api/v1/notifications/${id}/read`, {}),
  markAllRead: () =>
    api.post<{ ok: boolean }>("/api/v1/notifications/read-all", {}),
  registerToken: (token: string, platform: "ios" | "android" | "web") =>
    api.post<{ ok: boolean }>("/api/v1/notifications/push_tokens", {
      token,
      platform,
    }),
};
