import {
  api,
  coursesApi,
  practiceApi,
  notificationsApi,
} from "@/lib/api";

// Must be named with `mock` prefix so jest hoisting allows it in the factory
const mockGetState = jest.fn();

jest.mock("@/store/auth", () => ({
  useAuthStore: { getState: (...args: unknown[]) => mockGetState(...args) },
}));

const authState = (
  accessToken: string | null = "test-access",
  refreshToken: string | null = "test-refresh"
) => ({
  accessToken,
  refreshToken,
  setTokens: jest.fn().mockResolvedValue(undefined),
  clearTokens: jest.fn().mockResolvedValue(undefined),
});

const okJson = (body: unknown) => ({
  ok: true,
  status: 200,
  json: () => Promise.resolve(body),
});

const errJson = (status: number, body: unknown, statusText = "Error") => ({
  ok: false,
  status,
  statusText,
  json: () => Promise.resolve(body),
});

describe("api – request()", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetState.mockReturnValue(authState());
    global.fetch = jest.fn();
  });

  it("attaches Authorization header when accessToken is set", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(okJson({ data: "ok" }));
    await api.get("/api/v1/test");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/test"),
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer test-access",
        }),
      })
    );
  });

  it("omits Authorization header when no accessToken", async () => {
    mockGetState.mockReturnValue(authState(null, null));
    (global.fetch as jest.Mock).mockResolvedValue(okJson({ data: "public" }));
    await api.get("/api/v1/public");
    const [, opts] = (global.fetch as jest.Mock).mock.calls[0];
    expect(opts.headers.Authorization).toBeUndefined();
  });

  it("returns parsed JSON on success", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(okJson({ data: [1, 2] }));
    const result = await api.get<{ data: number[] }>("/api/v1/x");
    expect(result).toEqual({ data: [1, 2] });
  });

  it("attempts token refresh on 401 and retries original request", async () => {
    const mockSetTokens = jest.fn().mockResolvedValue(undefined);
    mockGetState.mockReturnValue({
      ...authState("old-access", "old-refresh"),
      setTokens: mockSetTokens,
    });

    (global.fetch as jest.Mock)
      .mockResolvedValueOnce({ ok: false, status: 401 })
      .mockResolvedValueOnce(
        okJson({ data: { access_token: "new-acc", refresh_token: "new-ref" } })
      )
      .mockResolvedValueOnce(okJson({ data: "retried" }));

    const result = await api.get("/api/v1/protected");
    expect(mockSetTokens).toHaveBeenCalledWith("new-acc", "new-ref");
    expect(result).toEqual({ data: "retried" });
  });

  it("clears tokens and throws when refresh request fails", async () => {
    const mockClearTokens = jest.fn().mockResolvedValue(undefined);
    mockGetState.mockReturnValue({
      ...authState("old", "ref"),
      clearTokens: mockClearTokens,
    });

    (global.fetch as jest.Mock)
      .mockResolvedValueOnce({ ok: false, status: 401 })
      .mockResolvedValueOnce({ ok: false, status: 400 });

    await expect(api.get("/api/v1/protected")).rejects.toMatchObject({
      name: "ApiError",
      message: "Session expired",
      status: 401,
    });
    expect(mockClearTokens).toHaveBeenCalled();
  });

  it("throws ApiError with server error message when response is not ok", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      errJson(404, { error: "Not found" })
    );
    await expect(api.get("/api/v1/missing")).rejects.toMatchObject({
      name: "ApiError",
      status: 404,
      message: "Not found",
    });
  });

  it("falls back to statusText when error body has no error field", async () => {
    (global.fetch as jest.Mock).mockResolvedValue(
      errJson(500, {}, "Internal Server Error")
    );
    await expect(api.get("/api/v1/broken")).rejects.toMatchObject({
      status: 500,
      message: "Internal Server Error",
    });
  });

  it("falls back to statusText when error body JSON parse fails", async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: false,
      status: 503,
      statusText: "Service Unavailable",
      json: () => Promise.reject(new Error("bad json")),
    });
    await expect(api.get("/api/v1/down")).rejects.toMatchObject({
      status: 503,
      message: "Service Unavailable",
    });
  });
});

describe("api – HTTP methods", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetState.mockReturnValue(authState());
    (global.fetch as jest.Mock) = jest
      .fn()
      .mockResolvedValue(okJson({ ok: true }));
  });

  it("api.post sends POST with serialised body", async () => {
    await api.post("/path", { a: 1 });
    expect(global.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ method: "POST", body: JSON.stringify({ a: 1 }) })
    );
  });

  it("api.put sends PUT with serialised body", async () => {
    await api.put("/path", { b: 2 });
    expect(global.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ method: "PUT" })
    );
  });

  it("api.delete sends DELETE request", async () => {
    await api.delete("/path");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ method: "DELETE" })
    );
  });
});

describe("coursesApi", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetState.mockReturnValue(authState());
    (global.fetch as jest.Mock) = jest
      .fn()
      .mockResolvedValue(okJson({ data: [] }));
  });

  it("list() calls GET /api/v1/courses", async () => {
    await coursesApi.list();
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/courses"),
      expect.any(Object)
    );
  });

  it("get(id) calls GET /api/v1/courses/:id", async () => {
    await coursesApi.get("abc");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/courses/abc"),
      expect.any(Object)
    );
  });
});

describe("practiceApi", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetState.mockReturnValue(authState());
    (global.fetch as jest.Mock) = jest
      .fn()
      .mockResolvedValue(okJson({ data: [] }));
  });

  it("questions() passes default limit=20", async () => {
    await practiceApi.questions("course-1");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("limit=20"),
      expect.any(Object)
    );
  });

  it("questions() passes custom limit and chapterId", async () => {
    await practiceApi.questions("course-1", 5, "ch-99");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("limit=5"),
      expect.any(Object)
    );
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("chapter_id=ch-99"),
      expect.any(Object)
    );
  });

  it("questions() omits chapter_id when not provided", async () => {
    await practiceApi.questions("course-1", 10);
    expect(global.fetch).not.toHaveBeenCalledWith(
      expect.stringContaining("chapter_id"),
      expect.any(Object)
    );
  });

  it("recordAnswers() posts to /api/v1/practice/answers", async () => {
    const answers = [
      { question_id: "q1", answer: "A", is_correct: true, time_ms: 500 },
    ];
    await practiceApi.recordAnswers("course-1", answers);
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/practice/answers"),
      expect.objectContaining({ method: "POST" })
    );
  });
});

describe("notificationsApi", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetState.mockReturnValue(authState());
    (global.fetch as jest.Mock) = jest
      .fn()
      .mockResolvedValue(okJson({ data: [] }));
  });

  it("list() calls GET /api/v1/notifications", async () => {
    await notificationsApi.list();
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/notifications"),
      expect.any(Object)
    );
  });

  it("markRead(id) posts to /api/v1/notifications/:id/read", async () => {
    await notificationsApi.markRead("n-123");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/notifications/n-123/read"),
      expect.objectContaining({ method: "POST" })
    );
  });

  it("markAllRead() posts to /api/v1/notifications/read-all", async () => {
    await notificationsApi.markAllRead();
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/notifications/read-all"),
      expect.objectContaining({ method: "POST" })
    );
  });

  it("registerToken() posts token and platform", async () => {
    await notificationsApi.registerToken("ExponentPushToken[x]", "ios");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/notifications/push_tokens"),
      expect.objectContaining({ method: "POST" })
    );
  });

  it("registerToken() works for android platform", async () => {
    await notificationsApi.registerToken("ExponentPushToken[y]", "android");
    expect(global.fetch).toHaveBeenCalledWith(
      expect.stringContaining("/api/v1/notifications/push_tokens"),
      expect.objectContaining({ method: "POST" })
    );
  });
});
