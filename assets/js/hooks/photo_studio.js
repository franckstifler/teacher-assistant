// Spec 2026-10-12 §7: crop / séance / upload queue for student photos.
// Output is always a 600×800 JPEG (q 0.85) named `<studentId>.jpg`.
const W = 600, H = 800, QUALITY = 0.85

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
    this.pending = new Map() // studentId -> File, until the server acks
    this.failed = new Set()
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
      this.renderPending()
    })
    this.handleEvent("photo:failed", ({student_id}) => {
      if (this.pending.has(student_id)) this.failed.add(student_id)
      this.renderPending()
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
  async submit(studentId, blob) {
    const file = new File([blob], `${studentId}.jpg`, {type: "image/jpeg"})
    this.pending.set(studentId, file)
    this.failed.delete(studentId)
    this.renderPending()
    this.upload("photo", [file])
  },

  retry() {
    for (const [id, file] of this.pending) {
      this.failed.delete(id)
      this.upload("photo", [file])
    }
    this.renderPending()
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
    this.$("crop-cancel").addEventListener("click", () => this.closeCrop())
    this.$("crop-ok").addEventListener("click", async () => {
      const {studentId, onDone} = this.crop
      const blob = await toJpeg(canvas)
      this.closeCrop()
      this.submit(studentId, blob)
      onDone?.()
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
}
