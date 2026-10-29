// Spec 2026-10-12 §7: crop / séance / upload queue for student photos.
// Output is always a 600×800 JPEG (q 0.85) named `<studentId>.jpg`.
const W = 600, H = 800, QUALITY = 0.85, MAX_IN_FLIGHT = 3

export const toJpeg = (canvas) =>
  new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", QUALITY))

// Draws `source` (ImageBitmap | HTMLVideoElement) cover-fit into a W×H canvas,
// scaled by `zoom` and shifted by `dx, dy` (output pixels).
export function drawCover(ctx, source, sw, sh, zoom = 1, dx = 0, dy = 0) {
  const scale = Math.max(W / sw, H / sh) * zoom
  const w = sw * scale, h = sh * scale
  ctx.fillStyle = "#000"
  ctx.fillRect(0, 0, W, H)
  ctx.drawImage(source, (W - w) / 2 + dx, (H - h) / 2 + dy, w, h)
}

export const PhotoStudio = {
  mounted() {
    this.pending = new Map() // studentId -> JPEG Blob, until the server acks
    this.failed = new Set()
    this.inFlight = new Set()
    this.$ = (role) => this.el.querySelector(`[data-role="${role}"]`)

    this.$("file").addEventListener("change", (e) => {
      const file = e.target.files[0]
      e.target.value = ""
      if (file) this.openCrop(file, this.targetId || this.el.dataset.studentId)
    })
    this.el.addEventListener("photo:pick", () => {
      this.targetId = this.el.dataset.studentId
      this.$("file").click()
    })

    this.onDragOver = (e) => { if (e.target.closest("[data-photo-drop]")) e.preventDefault() }
    this.onDrop = (e) => {
      const card = e.target.closest("[data-photo-drop]")
      const file = e.dataTransfer?.files?.[0]
      if (!card || !file) return
      e.preventDefault()
      this.openCrop(file, card.dataset.photoDrop)
    }
    document.addEventListener("dragover", this.onDragOver)
    document.addEventListener("drop", this.onDrop)

    this.setupCrop()
    this.handleEvent("photo:stored", ({student_id}) => {
      this.pending.delete(student_id)
      this.failed.delete(student_id)
      this.settle(student_id)
    })
    this.handleEvent("photo:failed", ({student_id}) => {
      if (this.pending.has(student_id)) this.failed.add(student_id)
      this.settle(student_id)
    })
    this.$("pending").addEventListener("click", () => this.retry())
    if (this.setupSession) this.setupSession()
  },

  reconnected() { this.retry() },

  destroyed() {
    document.removeEventListener("dragover", this.onDragOver)
    document.removeEventListener("drop", this.onDrop)
    this.stopCamera?.()
  },

  // --- queue -------------------------------------------------------------
  // At most MAX_IN_FLIGHT uploads at a time, under the server's max_entries,
  // so a fast séance never trips `too_many_files`; the rest wait their turn.
  async submit(studentId, blob) {
    this.pending.set(studentId, blob)
    this.failed.delete(studentId)
    this.pump()
  },

  pump() {
    for (const [id, blob] of this.pending) {
      if (this.inFlight.size >= MAX_IN_FLIGHT) break
      if (this.inFlight.has(id) || this.failed.has(id)) continue
      this.inFlight.add(id)
      // A fresh File each attempt: LiveView tags a File with its upload ref and
      // silently skips it once that ref is gone (consumed, or a new process after
      // a reconnect), so re-sending the same object would never upload.
      this.upload("photo", [new File([blob], `${id}.jpg`, {type: "image/jpeg"})])
    }
    this.renderPending()
  },

  settle(studentId) {
    this.inFlight.delete(studentId)
    this.pump()
  },

  retry() {
    this.inFlight.clear()
    this.failed.clear()
    this.pump()
  },

  renderPending() {
    const el = this.$("pending")
    const n = this.pending.size
    el.classList.toggle("hidden", n === 0)
    if (n === 0) return
    const label = this.failed.size > 0
      ? el.dataset.labelFailed
      : (n === 1 ? el.dataset.labelOne : el.dataset.labelMany.replace("__N__", n))
    el.textContent = label
    el.classList.toggle("bg-error", this.failed.size > 0)
  },

  // --- crop ----------------------------------------------------------------
  setupCrop() {
    const canvas = this.$("crop-canvas"), zoom = this.$("zoom")
    this.cropCtx = canvas.getContext("2d")
    this.crop = null
    const redraw = () => {
      const c = this.crop
      if (c) drawCover(this.cropCtx, c.bitmap, c.bitmap.width, c.bitmap.height, c.zoom, c.dx, c.dy)
    }
    zoom.addEventListener("input", () => { if (this.crop) { this.crop.zoom = +zoom.value; redraw() } })
    let last = null
    canvas.addEventListener("pointerdown", (e) => { last = [e.clientX, e.clientY]; canvas.setPointerCapture(e.pointerId) })
    canvas.addEventListener("pointermove", (e) => {
      if (!last || !this.crop) return
      const k = W / canvas.getBoundingClientRect().width // screen px -> output px
      this.crop.dx += (e.clientX - last[0]) * k
      this.crop.dy += (e.clientY - last[1]) * k
      last = [e.clientX, e.clientY]
      redraw()
    })
    canvas.addEventListener("pointerup", () => { last = null })
    this.$("crop-cancel").addEventListener("click", () => { this.afterCrop = null; this.closeCrop() })
    this.$("crop-ok").addEventListener("click", async () => {
      const {studentId, onDone} = this.crop
      const blob = await toJpeg(canvas)
      this.closeCrop()
      this.submit(studentId, blob)
      onDone?.()
      this.afterCrop?.()
      this.afterCrop = null
    })
    this.redrawCrop = redraw
  },

  async openCrop(file, studentId, onDone) {
    if (!studentId) return
    let bitmap
    try {
      bitmap = await createImageBitmap(file, {imageOrientation: "from-image"})
    } catch (_e) {
      this.pushEvent("photo_unreadable", {})
      return
    }
    this.crop = {bitmap, studentId, onDone, zoom: 1, dx: 0, dy: 0}
    this.$("zoom").value = 1
    this.$("crop").classList.replace("hidden", "flex")
    this.redrawCrop()
  },

  closeCrop() {
    this.crop?.bitmap.close?.()
    this.crop = null
    this.$("crop").classList.replace("flex", "hidden")
  },

  // --- séance --------------------------------------------------------------
  setupSession() {
    const $ = this.$
    this.el.addEventListener("photo:session-start", () => this.startSession())
    // One student's photo from the sheet: the séance camera, closed without a summary.
    this.el.addEventListener("photo:shoot", (e) => this.startSession([e.detail]))
    $("quit").addEventListener("click", () => this.endSession())
    $("summary-close").addEventListener("click", () => this.closeSession())
    $("skip").addEventListener("click", () => { this.skipped++; this.next() })
    $("flip").addEventListener("click", () => {
      this.facing = this.facing === "environment" ? "user" : "environment"
      this.startCamera()
    })
    $("shutter").addEventListener("click", () => this.shoot())
    $("retake").addEventListener("click", () => this.showLive())
    $("accept").addEventListener("click", async () => {
      const blob = await toJpeg($("still"))
      this.submit(this.current().id, blob)
      this.taken++
      this.next()
    })
    $("fallback").addEventListener("click", () => {
      this.targetId = this.current().id
      this.afterCrop = () => { this.taken++; this.next() }
      this.$("file").click()
    })
    this.facing = "environment"
  },

  current() { return this.queue[this.index] },

  async startSession(solo = null) {
    this.solo = solo !== null
    this.queue = solo || JSON.parse(this.el.dataset.queue || "[]")
    if (this.queue.length === 0) return
    this.index = 0; this.taken = 0; this.skipped = 0
    this.$("skip").classList.toggle("hidden", this.solo)
    this.$("session").classList.replace("hidden", "flex")
    this.$("summary").classList.replace("flex", "hidden")
    this.showStudent() // before the camera: its permission prompt can take a while
    try { this.wakeLock = await navigator.wakeLock?.request("screen") } catch (_e) { this.wakeLock = null }
    await this.startCamera()
  },

  async startCamera() {
    this.stopCamera()
    const video = this.$("video")
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {facingMode: this.facing, width: {ideal: 1280}, height: {ideal: 1280}}, audio: false,
      })
      video.srcObject = this.stream
      await video.play()
      this.$("camera-error").classList.add("hidden")
    } catch (_e) {
      this.$("camera-error").classList.remove("hidden")
    }
  },

  stopCamera() {
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
  },

  showStudent() {
    const s = this.current()
    this.$("name").textContent = s.name
    this.$("progress").textContent = this.solo ? "" : `${this.index + 1}/${this.queue.length}`
    this.showLive()
  },

  showLive() {
    for (const r of ["still", "retake", "accept"]) this.$(r).classList.add("hidden")
    for (const r of ["video", "shutter", "flip"]) this.$(r).classList.remove("hidden")
  },

  shoot() {
    const video = this.$("video")
    const vw = video.videoWidth, vh = video.videoHeight
    if (!vw) return
    // Capture exactly what the on-screen frame shows: map its largest centred 3:4
    // rectangle back through the video's object-cover scaling into video pixels.
    const vr = video.getBoundingClientRect(), fr = this.$("frame").getBoundingClientRect()
    const fw = Math.min(fr.width, fr.height * W / H), fh = fw * H / W
    const fx = fr.left + (fr.width - fw) / 2, fy = fr.top + (fr.height - fh) / 2
    const s = Math.max(vr.width / vw, vr.height / vh)
    const ox = (vr.width - vw * s) / 2, oy = (vr.height - vh * s) / 2
    const ctx = this.$("still").getContext("2d")
    ctx.drawImage(video, (fx - vr.left - ox) / s, (fy - vr.top - oy) / s, fw / s, fh / s, 0, 0, W, H)
    for (const r of ["video", "shutter", "flip"]) this.$(r).classList.add("hidden")
    for (const r of ["still", "retake", "accept"]) this.$(r).classList.remove("hidden")
  },

  next() {
    this.index++
    if (this.index >= this.queue.length) return this.endSession()
    this.showStudent()
  },

  endSession() {
    this.stopCamera()
    this.wakeLock?.release?.()
    if (this.solo) return this.closeSession()
    const el = this.$("summary-text")
    el.textContent = el.dataset.template.replace("__T__", this.taken).replace("__S__", this.skipped)
    this.$("summary").classList.replace("hidden", "flex")
  },

  closeSession() {
    this.$("session").classList.replace("flex", "hidden")
  },
}
