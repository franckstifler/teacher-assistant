// Spec 2026-10-29: « Photos examen » — previews and the zip of the exam pictures.
import {drawExamCard, examCardJpeg} from "../exam_photos/draw"
import {storedZip} from "../exam_photos/zip"

const PREVIEW_SCALE = 0.5

// A preview canvas, at half size: redrawn only when what it shows changed (a code edit).
export const ExamCard = {
  mounted() { this.draw() },
  updated() { if (this.el.dataset.card !== this.drawn) this.draw() },
  draw() {
    this.drawn = this.el.dataset.card
    drawExamCard(this.el, JSON.parse(this.drawn), PREVIEW_SCALE).catch(() => {})
  },
}

export const ExamPhotos = {
  mounted() {
    this.handleEvent("exam-photos:build", (payload) => this.build(payload))
  },

  async build({zip_name, items}) {
    if (this.busy) return
    this.busy = true
    const progress = this.el.querySelector('[data-role="progress"]')
    progress.classList.remove("hidden")
    const canvas = document.createElement("canvas")
    const files = []
    let failed = 0

    try {
      for (const [i, item] of items.entries()) {
        progress.textContent = progress.dataset.label
          .replace("__N__", i + 1).replace("__T__", items.length)
        try {
          await drawExamCard(canvas, item)
          const jpeg = await examCardJpeg(canvas)
          files.push({name: `${item.folder}/${item.file}`, data: new Uint8Array(await jpeg.arrayBuffer())})
        } catch (_e) {
          failed++
        }
      }

      if (files.length > 0) download(storedZip(files), zip_name)
      if (failed > 0) this.pushEvent("export_failed", {count: failed})
    } finally {
      progress.classList.add("hidden")
      this.busy = false
    }
  },
}

function download(blob, name) {
  const a = document.createElement("a")
  a.href = URL.createObjectURL(blob)
  a.download = name
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 60_000)
}
