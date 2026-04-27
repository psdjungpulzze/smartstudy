// FunSheep Service Worker — offline-first for assets, network-first for API/LiveView
const CACHE_VERSION = "v1";
const ASSET_CACHE = `funsheep-assets-${CACHE_VERSION}`;
const OFFLINE_URL = "/offline";

// Asset patterns to cache on install
const PRECACHE_PATTERNS = ["/", OFFLINE_URL];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(ASSET_CACHE)
      .then((cache) => cache.addAll(PRECACHE_PATTERNS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k.startsWith("funsheep-") && k !== ASSET_CACHE)
            .map((k) => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Never intercept WebSocket connections (LiveView), API calls, or cross-origin
  if (
    url.origin !== self.location.origin ||
    url.pathname.startsWith("/live") ||
    url.pathname.startsWith("/api/") ||
    url.pathname.startsWith("/auth/") ||
    request.method !== "GET"
  ) {
    return;
  }

  // Cache-first for digested assets (already content-addressed, can cache forever)
  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(
      caches.match(request).then(
        (cached) =>
          cached ||
          fetch(request).then((response) => {
            if (response.ok) {
              const clone = response.clone();
              caches.open(ASSET_CACHE).then((cache) => cache.put(request, clone));
            }
            return response;
          })
      )
    );
    return;
  }

  // Network-first for HTML pages — fall back to offline page on failure
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response.ok && request.headers.get("accept")?.includes("text/html")) {
          const clone = response.clone();
          caches.open(ASSET_CACHE).then((cache) => cache.put(request, clone));
        }
        return response;
      })
      .catch(() =>
        caches
          .match(request)
          .then((cached) => cached || caches.match(OFFLINE_URL))
      )
  );
});
