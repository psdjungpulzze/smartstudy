// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/fun_sheep"
import topbar from "../vendor/topbar"

// ── Direct File Uploader ────────────────────────────────────────────────────
// Uploads files via parallel HTTP POST requests instead of LiveView WebSocket.
// Communicates progress back to LiveView via pushEvent.

const CONCURRENT_UPLOADS = 6
const IGNORED_PATTERN = /^(\._|\.DS_Store|Thumbs\.db|desktop\.ini|\.gitkeep)$/i

// Global upload state shared across all uploader instances
const uploadState = { completed: 0, failed: 0, total: 0, inFlight: 0 }

function resetUploadState() {
  uploadState.completed = 0
  uploadState.failed = 0
  uploadState.total = 0
  uploadState.inFlight = 0
}

function pushUploadState(hook) {
  hook.pushEvent("upload_progress", {
    completed: uploadState.completed,
    failed: uploadState.failed,
    total: uploadState.total,
    in_flight: uploadState.inFlight,
  })
}

function createDirectUploader(hook, files, folderMap, batchId, userRoleId, csrfToken) {
  uploadState.total += files.length
  uploadState.inFlight += files.length
  let queue = [...files]
  let active = 0
  let cancelled = false

  function uploadNext() {
    if (cancelled || queue.length === 0) return
    if (active >= CONCURRENT_UPLOADS) return

    const file = queue.shift()
    active++

    const formData = new FormData()
    formData.append("file", file)
    formData.append("batch_id", batchId)
    formData.append("user_role_id", userRoleId)
    formData.append("folder_name", folderMap[file.name] || "")

    fetch("/api/upload", {
      method: "POST",
      headers: { "x-csrf-token": csrfToken },
      body: formData,
    })
      .then(resp => {
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
        return resp.json()
      })
      .then(() => {
        uploadState.completed++
        uploadState.inFlight--
        pushUploadState(hook)
      })
      .catch(err => {
        uploadState.failed++
        uploadState.inFlight--
        console.error(`Upload failed: ${file.name}`, err)
        pushUploadState(hook)
      })
      .finally(() => {
        active--
        uploadNext()
      })

    // Start more concurrent uploads
    uploadNext()
  }

  // Kick off initial batch
  for (let i = 0; i < CONCURRENT_UPLOADS && i < files.length; i++) {
    uploadNext()
  }

  return { cancel: () => { cancelled = true; uploadState.inFlight -= queue.length; queue = [] } }
}

// Custom hooks
const Hooks = {
  ...colocatedHooks,

  // ── Stripe Card Setup (Payment Method Collection) ──────────────────────
  // Mounts Stripe Elements for secure credit card input. Uses a SetupIntent
  // client_secret from data-client-secret to confirm the card setup, then
  // pushes the payment_method_id back to the LiveView via pushEvent.
  StripeCardSetup: {
    mounted() {
      this.initStripe()
    },

    updated() {
      // Re-initialize if client_secret changes
      const newSecret = this.el.dataset.clientSecret
      if (newSecret && newSecret !== this._lastSecret) {
        this.initStripe()
      }
    },

    destroyed() {
      if (this._card) this._card.destroy()
    },

    initStripe() {
      const clientSecret = this.el.dataset.clientSecret
      if (!clientSecret) return

      this._lastSecret = clientSecret

      // Load Stripe.js if not already loaded
      if (!window.Stripe) {
        const script = document.createElement("script")
        script.src = "https://js.stripe.com/v3/"
        script.onload = () => this._mountCard(clientSecret)
        document.head.appendChild(script)
      } else {
        this._mountCard(clientSecret)
      }
    },

    _mountCard(clientSecret) {
      const stripeKey = document.querySelector("meta[name='stripe-key']")?.content
      // In mock/dev mode, show a simulated card form
      if (!stripeKey || stripeKey === "mock") {
        this._mountMockCard(clientSecret)
        return
      }

      const stripe = window.Stripe(stripeKey)
      const elements = stripe.elements()
      const card = elements.create("card", {
        style: {
          base: {
            fontSize: "16px",
            color: "#1C1C1E",
            fontFamily: "system-ui, -apple-system, sans-serif",
            "::placeholder": { color: "#8E8E93" },
          },
          invalid: { color: "#FF3B30" },
        },
      })

      const el = this.el.querySelector("#card-element")
      el.innerHTML = ""
      card.mount(el)
      this._card = card

      const errorEl = this.el.querySelector("#card-errors")

      card.on("change", (e) => {
        if (e.error) {
          errorEl.textContent = e.error.message
          errorEl.classList.remove("hidden")
        } else {
          errorEl.classList.add("hidden")
        }
      })

      const submitBtn = document.getElementById("submit-card-btn")
      if (submitBtn) {
        submitBtn.addEventListener("click", async () => {
          submitBtn.disabled = true
          submitBtn.textContent = "Saving..."

          const { setupIntent, error } = await stripe.confirmCardSetup(clientSecret, {
            payment_method: { card },
          })

          if (error) {
            errorEl.textContent = error.message
            errorEl.classList.remove("hidden")
            submitBtn.disabled = false
            submitBtn.textContent = "Save Card"
          } else {
            this.pushEvent("card_setup_complete", {
              payment_method_id: setupIntent.payment_method,
            })
          }
        })
      }
    },

    // Mock card form for development without a real Stripe key
    _mountMockCard(_clientSecret) {
      const el = this.el.querySelector("#card-element")
      el.innerHTML = `
        <div class="space-y-3">
          <div>
            <label class="block text-xs text-gray-500 mb-1">Card Number</label>
            <input type="text" value="4242 4242 4242 4242" readonly
              class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm text-gray-900" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs text-gray-500 mb-1">Expiry</label>
              <input type="text" value="12/27" readonly
                class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm text-gray-900" />
            </div>
            <div>
              <label class="block text-xs text-gray-500 mb-1">CVC</label>
              <input type="text" value="***" readonly
                class="w-full px-3 py-2 bg-white border border-gray-200 rounded-lg text-sm text-gray-900" />
            </div>
          </div>
          <p class="text-xs text-amber-600">Mock mode — no real charge will be made</p>
        </div>
      `

      const submitBtn = document.getElementById("submit-card-btn")
      if (submitBtn) {
        submitBtn.addEventListener("click", () => {
          submitBtn.disabled = true
          submitBtn.textContent = "Saving..."
          setTimeout(() => {
            this.pushEvent("card_setup_complete", {
              payment_method_id: "pm_mock_" + Math.random().toString(36).slice(2, 10),
            })
          }, 800)
        })
      }
    },
  },

  // ── Native Share (Web Share API with clipboard fallback) ──────────────
  // Uses navigator.share() on mobile (iOS Safari, Android Chrome) for native
  // share sheets. Falls back to clipboard copy + toast on desktop browsers.
  NativeShare: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.preventDefault()
        const title = this.el.dataset.shareTitle || document.title
        const text = this.el.dataset.shareText || ""
        const url = this.el.dataset.shareUrl || window.location.href

        if (navigator.share) {
          navigator.share({ title, text, url })
            .then(() => this.pushEvent("share_completed", { method: "native" }))
            .catch((err) => {
              // User cancelled — not an error
              if (err.name !== "AbortError") {
                console.error("Share failed:", err)
              }
            })
        } else {
          // Clipboard fallback for desktop
          const shareText = text ? `${text}\n${url}` : url
          navigator.clipboard.writeText(shareText)
            .then(() => {
              this.pushEvent("share_completed", { method: "clipboard" })
              this._showToast("Link copied!")
            })
            .catch(() => {
              // Final fallback: select + copy
              const ta = document.createElement("textarea")
              ta.value = shareText
              ta.style.position = "fixed"
              ta.style.opacity = "0"
              document.body.appendChild(ta)
              ta.select()
              document.execCommand("copy")
              document.body.removeChild(ta)
              this.pushEvent("share_completed", { method: "clipboard" })
              this._showToast("Link copied!")
            })
        }
      })
    },

    _showToast(message) {
      const toast = document.createElement("div")
      toast.textContent = message
      toast.className = "fixed bottom-24 left-1/2 -translate-x-1/2 bg-gray-900 text-white text-sm font-medium px-4 py-2 rounded-full shadow-lg z-[100] transition-opacity duration-300"
      document.body.appendChild(toast)
      setTimeout(() => { toast.style.opacity = "0" }, 1500)
      setTimeout(() => { toast.remove() }, 2000)
    }
  },

  // Auto-scrolls a container to the bottom when its content changes.
  // Used by the AI Tutor chat panel to keep latest messages visible.
  ScrollBottom: {
    mounted() {
      this._scroll()
      this._observer = new MutationObserver(() => this._scroll())
      const msgs = this.el.querySelector("#tutor-messages")
      if (msgs) {
        this._observer.observe(msgs, { childList: true, subtree: true })
      }
    },
    updated() {
      this._scroll()
    },
    destroyed() {
      if (this._observer) this._observer.disconnect()
    },
    _scroll() {
      const msgs = this.el.querySelector("#tutor-messages")
      if (msgs) {
        msgs.scrollTop = msgs.scrollHeight
      }
    }
  },

  // Manages direct HTTP file uploads from the course creation form.
  // Reads batch_id and user_role_id from data attributes on the hook element.
  DirectUploader: {
    mounted() {
      this.uploaders = []
      this.handleEvent("reset_uploads", () => {
        this.uploaders.forEach(u => u.cancel())
        this.uploaders = []
        resetUploadState()
      })
    },

    destroyed() {
      this.uploaders.forEach(u => u.cancel())
    },
  },

  // File picker button (individual files)
  FilePicker: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.preventDefault()
        const input = document.createElement("input")
        input.type = "file"
        input.multiple = true
        input.accept = ".pdf,.jpg,.jpeg,.png,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.txt,.csv"

        input.addEventListener("change", () => {
          this._startUpload(Array.from(input.files), {})
        })
        input.click()
      })
    },

    _startUpload(files, folderMap) {
      const container = this.el.closest("[data-batch-id]")
      if (!container) return
      const batchId = container.dataset.batchId
      const userRoleId = container.dataset.userRoleId
      const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")

      // Filter hidden files
      const validFiles = files.filter(f => !f.name.startsWith(".") && !IGNORED_PATTERN.test(f.name))
      if (validFiles.length === 0) return

      const uploader = createDirectUploader(this, validFiles, folderMap, batchId, userRoleId, csrf)
      // Store on parent DirectUploader hook if available
      const uploaderEl = document.querySelector("[phx-hook='DirectUploader']")
      if (uploaderEl && uploaderEl._liveHook) {
        uploaderEl._liveHook.uploaders.push(uploader)
      }
    }
  },

  // Folder picker button
  FolderPicker: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        e.preventDefault()
        const input = document.createElement("input")
        input.type = "file"
        input.multiple = true
        input.setAttribute("webkitdirectory", "")
        input.setAttribute("directory", "")

        input.addEventListener("change", () => {
          const validFiles = []
          const folderMap = {}
          for (const file of input.files) {
            if (file.name.startsWith(".") || IGNORED_PATTERN.test(file.name)) continue
            validFiles.push(file)
            const relPath = file.webkitRelativePath || ""
            if (relPath) {
              folderMap[file.name] = relPath.split("/")[0]
            }
          }
          if (validFiles.length === 0) return

          const container = this.el.closest("[data-batch-id]")
          if (!container) return
          const batchId = container.dataset.batchId
          const userRoleId = container.dataset.userRoleId
          const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")

          // Send folder metadata to LiveView
          this.pushEvent("folder_metadata", { folders: folderMap })

          const uploader = createDirectUploader(this, validFiles, folderMap, batchId, userRoleId, csrf)
          const uploaderEl = document.querySelector("[phx-hook='DirectUploader']")
          if (uploaderEl && uploaderEl._liveHook) {
            uploaderEl._liveHook.uploaders.push(uploader)
          }
        })

        input.click()
      })
    }
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
