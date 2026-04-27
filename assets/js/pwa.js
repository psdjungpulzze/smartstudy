// PWA service worker registration + install prompt

let deferredInstallPrompt = null;

// Register service worker
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js", { scope: "/" })
      .catch((err) => console.warn("[PWA] SW registration failed:", err));
  });
}

// Capture the beforeinstallprompt event so we can trigger it from our own UI
window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  deferredInstallPrompt = e;
  // Dispatch a custom event so LiveView hooks can react
  window.dispatchEvent(new CustomEvent("pwa:installable"));
});

window.addEventListener("appinstalled", () => {
  deferredInstallPrompt = null;
  window.dispatchEvent(new CustomEvent("pwa:installed"));
});

// Called by the install button in the UI
window.triggerPWAInstall = async () => {
  if (!deferredInstallPrompt) return false;
  deferredInstallPrompt.prompt();
  const { outcome } = await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  return outcome === "accepted";
};

export { deferredInstallPrompt };
