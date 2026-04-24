// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/fun_sheep"
import topbar from "../vendor/topbar"

// ── Direct File Uploader ────────────────────────────────────────────────────
// Uploads files directly to storage (GCS in prod, this-app-in-dev) via
// pre-authorized resumable session URLs. The server never reads the file
// bytes, so 1,000-page PDFs of 500 MB upload fine.
//
// Per-file flow:
//   1. POST /api/uploads/sign  → { upload_url, object_key }
//   2. PUT <upload_url> in 8 MB chunks with Content-Range for progress + retry
//   3. POST /api/uploads/finalize → creates the UploadedMaterial row
//
// Reports aggregate progress back to LiveView via pushEvent("upload_progress").

const CONCURRENT_UPLOADS = 4  // per-file concurrency; chunks within a file are sequential
const CHUNK_SIZE = 8 * 1024 * 1024  // 8 MB — GCS requires chunks to be multiples of 256 KB
const IGNORED_PATTERN = /^(\._|\.DS_Store|Thumbs\.db|desktop\.ini|\.gitkeep)$/i

// Global upload state shared across all uploader instances
const uploadState = { completed: 0, failed: 0, total: 0, inFlight: 0 }

// Per-file queue for the in-progress file list UI
const fileQueue = []  // [{id, name, status: 'queued'|'uploading'|'done'|'failed'}]
let fileIdCounter = 0

function resetUploadState() {
  uploadState.completed = 0
  uploadState.failed = 0
  uploadState.total = 0
  uploadState.inFlight = 0
  fileQueue.length = 0
  renderFileQueue()
}

// Renders per-file upload rows into the phx-update="ignore" container.
// Uses textContent (not innerHTML) for file names to prevent XSS.
function renderFileQueue() {
  const el = document.getElementById("upload-file-queue")
  if (!el) return
  el.innerHTML = ""
  if (fileQueue.length === 0) return

  const list = document.createElement("div")
  list.className = "max-h-48 overflow-y-auto space-y-1.5 mb-4"

  for (const f of fileQueue) {
    const row = document.createElement("div")
    row.className = "flex items-center justify-between gap-2 px-3 py-2 bg-[#F5F5F7] rounded-xl"

    const name = document.createElement("span")
    name.className = "text-sm text-[#1C1C1E] truncate min-w-0 flex-1"
    name.textContent = f.name

    const badge = document.createElement("span")
    badge.className = "text-[10px] font-medium px-2 py-0.5 rounded-full shrink-0 whitespace-nowrap " + fileStatusClass(f.status)
    badge.textContent = fileStatusLabel(f.status)

    row.appendChild(name)
    row.appendChild(badge)
    list.appendChild(row)
  }

  el.appendChild(list)
}

function fileStatusClass(status) {
  switch (status) {
    case 'uploading': return 'bg-[#E8F0FE] text-[#007AFF]'
    case 'done':      return 'bg-[#E8F8EB] text-[#34C759]'
    case 'failed':    return 'bg-[#FFE5E3] text-[#FF3B30]'
    default:          return 'bg-[#F5F5F7] text-[#8E8E93]'  // queued
  }
}

function fileStatusLabel(status) {
  switch (status) {
    case 'uploading': return '↑ Uploading'
    case 'done':      return '✓ Done'
    case 'failed':    return '✗ Failed'
    default:          return 'Queued'
  }
}

function readMaterialKind(container) {
  const select = container.querySelector("[data-material-kind-select]")
  if (select && select.value) return select.value
  return container.dataset.defaultMaterialKind || "textbook"
}

function pushUploadState(hook) {
  hook.pushEvent("upload_progress", {
    completed: uploadState.completed,
    failed: uploadState.failed,
    total: uploadState.total,
    in_flight: uploadState.inFlight,
  })
}

// Get a resumable upload URL for a file. Size/type go in the sign request
// so GCS can enforce them on the PUT side.
async function requestSignedUpload(file, folderName, batchId, userRoleId, csrfToken) {
  const resp = await fetch("/api/uploads/sign", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken,
    },
    body: JSON.stringify({
      batch_id: batchId,
      user_role_id: userRoleId,
      folder_name: folderName || "",
      file_name: file.name,
      file_type: file.type || "application/octet-stream",
      file_size: file.size,
    }),
  })
  if (!resp.ok) throw new Error(`sign failed: HTTP ${resp.status}`)
  return resp.json()
}

// PUT a file to the resumable session URL in 8 MB chunks. Returns when the
// final chunk gets a 200/201. Failed chunks trigger an abort — GCS sessions
// are retryable but we keep it simple here and fail the whole file; users
// can retry via the "retry failed" button.
async function putFileInChunks(uploadUrl, file, onProgress) {
  const total = file.size

  // Small files: one PUT, no Content-Range. GCS still accepts this against
  // a resumable session — it treats it as a single-chunk upload.
  if (total <= CHUNK_SIZE) {
    const resp = await fetch(uploadUrl, {
      method: "PUT",
      headers: {
        "content-type": file.type || "application/octet-stream",
      },
      body: file,
    })
    if (!resp.ok) throw new Error(`PUT failed: HTTP ${resp.status}`)
    if (onProgress) onProgress(total, total)
    return
  }

  // Chunked upload: each PUT says which byte range it carries. GCS responds
  // 308 (resume incomplete) for intermediate chunks and 200/201 for the last.
  let offset = 0
  while (offset < total) {
    const end = Math.min(offset + CHUNK_SIZE, total)
    const chunk = file.slice(offset, end)
    const contentRange = `bytes ${offset}-${end - 1}/${total}`

    const resp = await fetch(uploadUrl, {
      method: "PUT",
      headers: {
        "content-type": file.type || "application/octet-stream",
        "content-range": contentRange,
      },
      body: chunk,
    })

    // 308 = more chunks expected. 200/201 = upload complete.
    if (resp.status !== 308 && !resp.ok) {
      throw new Error(`chunk PUT failed: HTTP ${resp.status}`)
    }

    offset = end
    if (onProgress) onProgress(offset, total)
  }
}

async function finalizeUpload(objectKey, file, folderName, batchId, userRoleId, materialKind, csrfToken) {
  const resp = await fetch("/api/uploads/finalize", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken,
    },
    body: JSON.stringify({
      object_key: objectKey,
      batch_id: batchId,
      user_role_id: userRoleId,
      folder_name: folderName || "",
      file_name: file.name,
      file_type: file.type || "application/octet-stream",
      material_kind: materialKind || "textbook",
    }),
  })
  if (!resp.ok) throw new Error(`finalize failed: HTTP ${resp.status}`)
  return resp.json()
}

function createDirectUploader(hook, files, folderMap, batchId, userRoleId, csrfToken, materialKind) {
  uploadState.total += files.length
  uploadState.inFlight += files.length

  // Register each file in the per-file queue immediately (before any uploads start)
  const queueItems = files.map(f => ({ id: ++fileIdCounter, name: f.name, status: 'queued' }))
  fileQueue.push(...queueItems)
  renderFileQueue()

  let queue = files.map((f, i) => [f, queueItems[i]])
  let active = 0
  let cancelled = false

  async function uploadOne(file, queueItem) {
    queueItem.status = 'uploading'
    renderFileQueue()
    try {
      const folderName = folderMap[file.name] || ""
      const { upload_url, object_key } =
        await requestSignedUpload(file, folderName, batchId, userRoleId, csrfToken)

      if (cancelled) return

      try {
        await putFileInChunks(upload_url, file, () => {
          // Per-chunk tick: no-op; aggregate progress is per-file.
        })
      } catch (putErr) {
        // GCS returns CORS headers on the OPTIONS preflight but not on the
        // actual PUT response, so browsers throw TypeError even when the
        // upload landed. Re-throw plain Errors (4xx/5xx from GCS) so genuine
        // failures are still counted; swallow TypeErrors and let
        // finalizeUpload confirm via object_info whether the file made it.
        if (!(putErr instanceof TypeError)) throw putErr
      }

      if (cancelled) return

      await finalizeUpload(object_key, file, folderName, batchId, userRoleId, materialKind, csrfToken)

      uploadState.completed++
      queueItem.status = 'done'
    } catch (err) {
      uploadState.failed++
      queueItem.status = 'failed'
      console.error(`Upload failed: ${file.name}`, err)
    } finally {
      uploadState.inFlight--
      renderFileQueue()
      pushUploadState(hook)

      // Once all uploads finish, briefly show the final Done/Failed states then
      // clear the queue — the server will refresh the materials list at this point.
      if (uploadState.inFlight === 0 && uploadState.total > 0) {
        setTimeout(() => { fileQueue.length = 0; renderFileQueue() }, 2000)
      }
    }
  }

  function pump() {
    if (cancelled) return
    while (active < CONCURRENT_UPLOADS && queue.length > 0) {
      const [file, queueItem] = queue.shift()
      active++
      uploadOne(file, queueItem).finally(() => {
        active--
        pump()
      })
    }
  }

  pump()

  return {
    cancel: () => {
      cancelled = true
      queue.forEach(([_, qi]) => { qi.status = 'failed' })
      uploadState.inFlight -= queue.length
      queue = []
      renderFileQueue()
    },
  }
}

// ── SwipeCard Hook ──────────────────────────────────────────────────────────
// Tinder-style swipe gesture handler for question cards.
// Detects horizontal swipes (right = know, left = don't know) and vertical
// swipes (up = skip). Falls back to button taps for accessibility.
// Communicates swipe direction back to LiveView via pushEvent.

const SWIPE_THRESHOLD = 80    // px to commit a horizontal swipe
const SKIP_THRESHOLD = 120    // px to commit a vertical swipe (up)
const ROTATION_FACTOR = 0.08  // degrees per px of horizontal drag

const SwipeCardHook = {
  mounted() {
    this._startX = 0
    this._startY = 0
    this._currentX = 0
    this._currentY = 0
    this._dragging = false
    this._card = this.el

    // Touch events
    this._card.addEventListener("touchstart", (e) => this._onStart(e.touches[0].clientX, e.touches[0].clientY), { passive: true })
    this._card.addEventListener("touchmove", (e) => {
      if (this._dragging) e.preventDefault()
      this._onMove(e.touches[0].clientX, e.touches[0].clientY)
    }, { passive: false })
    this._card.addEventListener("touchend", () => this._onEnd())
    this._card.addEventListener("touchcancel", () => this._onEnd())

    // Mouse events (for desktop testing, won't affect desktop layout)
    this._card.addEventListener("mousedown", (e) => { this._onStart(e.clientX, e.clientY); this._mouseDown = true })
    document.addEventListener("mousemove", this._mouseMoveHandler = (e) => {
      if (this._mouseDown) this._onMove(e.clientX, e.clientY)
    })
    document.addEventListener("mouseup", this._mouseUpHandler = () => {
      if (this._mouseDown) { this._mouseDown = false; this._onEnd() }
    })
  },

  destroyed() {
    document.removeEventListener("mousemove", this._mouseMoveHandler)
    document.removeEventListener("mouseup", this._mouseUpHandler)
  },

  _onStart(x, y) {
    this._startX = x
    this._startY = y
    this._currentX = 0
    this._currentY = 0
    this._dragging = true
    this._card.style.transition = "none"
  },

  _onMove(x, y) {
    if (!this._dragging) return
    this._currentX = x - this._startX
    this._currentY = y - this._startY

    const rotate = this._currentX * ROTATION_FACTOR
    this._card.style.transform = `translate(${this._currentX}px, ${Math.min(this._currentY, 0)}px) rotate(${rotate}deg)`

    // Visual feedback overlays
    const rightOverlay = this._card.querySelector("[data-swipe-right]")
    const leftOverlay = this._card.querySelector("[data-swipe-left]")
    const upOverlay = this._card.querySelector("[data-swipe-up]")

    const hOpacity = Math.min(Math.abs(this._currentX) / SWIPE_THRESHOLD, 1)
    const vOpacity = Math.min(Math.abs(Math.min(this._currentY, 0)) / SKIP_THRESHOLD, 1)

    if (rightOverlay) rightOverlay.style.opacity = this._currentX > 20 ? hOpacity : 0
    if (leftOverlay) leftOverlay.style.opacity = this._currentX < -20 ? hOpacity : 0
    if (upOverlay) upOverlay.style.opacity = this._currentY < -20 ? vOpacity : 0
  },

  _onEnd() {
    if (!this._dragging) return
    this._dragging = false

    const dx = this._currentX
    const dy = this._currentY

    if (dx > SWIPE_THRESHOLD) {
      this._flyOut("right")
    } else if (dx < -SWIPE_THRESHOLD) {
      this._flyOut("left")
    } else if (dy < -SKIP_THRESHOLD) {
      this._flyOut("up")
    } else {
      // Spring back
      this._card.style.transition = "transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275)"
      this._card.style.transform = "translate(0, 0) rotate(0deg)"
      this._resetOverlays()
    }
  },

  _flyOut(direction) {
    const offscreen = window.innerWidth + 100
    let tx, ty, rot
    switch (direction) {
      case "right": tx = offscreen; ty = 0; rot = 20; break
      case "left": tx = -offscreen; ty = 0; rot = -20; break
      case "up": tx = 0; ty = -(window.innerHeight + 100); rot = 0; break
    }

    this._card.style.transition = "transform 0.35s ease-out, opacity 0.35s ease-out"
    this._card.style.transform = `translate(${tx}px, ${ty}px) rotate(${rot}deg)`
    this._card.style.opacity = "0"

    // Haptic feedback
    if (navigator.vibrate) navigator.vibrate(15)

    setTimeout(() => {
      this.pushEvent("swipe", { direction })
    }, 200)
  },

  _resetOverlays() {
    const overlays = this._card.querySelectorAll("[data-swipe-right], [data-swipe-left], [data-swipe-up]")
    overlays.forEach(el => { el.style.opacity = "0" })
  },
}

// Custom hooks
const Hooks = {
  ...colocatedHooks,

  SwipeCard: SwipeCardHook,

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
          // Clipboard fallback for desktop — use textarea method directly
          // as navigator.clipboard.writeText can silently fail on Linux
          this._copyViaTextarea(url)
          this.pushEvent("share_completed", { method: "clipboard" })
          this._showToast("Link copied!")
        }
      })
    },

    _copyViaTextarea(text) {
      const ta = document.createElement("textarea")
      ta.value = text
      ta.style.position = "fixed"
      ta.style.left = "-9999px"
      ta.style.opacity = "0"
      document.body.appendChild(ta)
      ta.focus()
      ta.select()
      document.execCommand("copy")
      document.body.removeChild(ta)
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

  // Scrolls element into view when it appears in the DOM.
  ScrollIntoView: {
    mounted() {
      this.el.scrollIntoView({ behavior: "smooth", block: "start" })
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
      fileQueue.length = 0
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
      const materialKind = readMaterialKind(container)
      const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")

      // Filter hidden files
      const validFiles = files.filter(f => !f.name.startsWith(".") && !IGNORED_PATTERN.test(f.name))
      if (validFiles.length === 0) return

      const uploader = createDirectUploader(this, validFiles, folderMap, batchId, userRoleId, csrf, materialKind)
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
          const materialKind = readMaterialKind(container)
          const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")

          // Send folder metadata to LiveView
          this.pushEvent("folder_metadata", { folders: folderMap })

          const uploader = createDirectUploader(this, validFiles, folderMap, batchId, userRoleId, csrf, materialKind)
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
