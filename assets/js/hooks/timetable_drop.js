// « Reste à placer » (timetable editor): drag a subject from the sidebar onto a
// free cell of the grid. Items carry `data-tc`, free cells `data-drop-day` and
// `data-drop-period`; the drop pushes `drop_place`. Tapping a cell still opens
// the placement panel, so phones lose nothing.
export const TimetableDrop = {
  mounted() {
    this.dragging = null
    this.over = null

    this.el.addEventListener("dragstart", (e) => {
      const item = e.target.closest("[data-tc]")
      if (!item) return
      this.dragging = item.dataset.tc
      e.dataTransfer.setData("text/plain", item.dataset.tc)
      e.dataTransfer.effectAllowed = "copy"
      item.classList.add("ta-dragging")
    })

    this.el.addEventListener("dragend", (e) => {
      const item = e.target.closest("[data-tc]")
      if (item) item.classList.remove("ta-dragging")
      this.dragging = null
      this.clear()
    })

    this.el.addEventListener("dragover", (e) => {
      const cell = e.target.closest("[data-drop-day]")
      if (!cell || !this.dragging) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "copy"
      if (this.over !== cell) {
        this.clear()
        this.over = cell
        cell.classList.add("ta-drop-over")
      }
    })

    this.el.addEventListener("dragleave", (e) => {
      const cell = e.target.closest("[data-drop-day]")
      if (cell && cell === this.over && !cell.contains(e.relatedTarget)) this.clear()
    })

    this.el.addEventListener("drop", (e) => {
      const cell = e.target.closest("[data-drop-day]")
      const tc = this.dragging || e.dataTransfer.getData("text/plain")
      this.clear()
      if (!cell || !tc) return
      e.preventDefault()
      this.pushEvent("drop_place", {
        tc,
        day: cell.dataset.dropDay,
        period: cell.dataset.dropPeriod,
      })
    })
  },

  clear() {
    if (this.over) this.over.classList.remove("ta-drop-over")
    this.over = null
  },
}
