import Sortable from "../../vendor/sortable.js"

// Reads the DOM under #fiche-modules and builds the layout payload the server expects.
function readLayout(root) {
  return Array.from(root.querySelectorAll("[data-module-id]")).map((moduleEl) => ({
    module_id: moduleEl.getAttribute("data-module-id"),
    entry_ids: Array.from(moduleEl.querySelectorAll("[data-entry-id]")).map((e) =>
      e.getAttribute("data-entry-id")
    ),
  }))
}

const ModuleLayout = {
  mounted() {
    const root = this.el
    this.push = () => this.pushEvent("apply-layout", { layout: readLayout(root) })

    // Level 1: modules sortable by their header handle. Bound once to the
    // persistent root element, which survives LiveView re-renders.
    this.moduleSortable = new Sortable(root, {
      handle: "[data-module-handle]",
      animation: 150,
      onEnd: this.push,
    })

    // Level 2: lessons sortable within each module, shared group => cross-module drag.
    this.bindEntrySortables()

    // Keyboard fallback: focusable handles; Enter/Space grabs, Arrow moves, Enter/Space drops.
    this.grabbed = null
    this.onKeydown = (ev) => this.onKey(ev, root, this.push)
    root.addEventListener("keydown", this.onKeydown)
  },

  updated() {
    // The server may have re-rendered with new/removed modules or lessons
    // (add/delete/rename). New [data-entries] lists aren't drag-enabled yet
    // and morphdom may have replaced list nodes entirely, so tear down the
    // stale entry-level Sortable instances and rebuild them over the current
    // DOM. The module-level Sortable stays bound to the persistent root and
    // needs no rebinding.
    this.bindEntrySortables()
  },

  bindEntrySortables() {
    const root = this.el
    ;(this.entrySortables || []).forEach((s) => s.destroy())

    this.entrySortables = Array.from(root.querySelectorAll("[data-entries]")).map((listEl) =>
      new Sortable(listEl, {
        group: "lessons",
        handle: "[data-entry-handle]",
        animation: 150,
        onEnd: this.push,
      })
    )
  },

  onKey(ev, root, push) {
    const handle = ev.target.closest("[data-entry-handle],[data-module-handle]")
    if (!handle) return
    const item = handle.closest("[data-entry-id],[data-module-id]")

    if (ev.key === "Escape" && this.grabbed) {
      ev.preventDefault()
      this.grabbed = null
      this.announce(root, "cancelled")
      return
    }

    if (ev.key === "Enter" || ev.key === " ") {
      ev.preventDefault()
      this.grabbed = this.grabbed === item ? null : item
      this.announce(root, this.grabbed ? "grabbed" : "dropped")
      if (!this.grabbed) push()
      return
    }

    if (!this.grabbed || (ev.key !== "ArrowUp" && ev.key !== "ArrowDown")) return
    if (this.grabbed !== item) return
    ev.preventDefault()
    const sibling =
      ev.key === "ArrowUp" ? item.previousElementSibling : item.nextElementSibling
    if (!sibling) return
    if (ev.key === "ArrowUp") item.parentNode.insertBefore(item, sibling)
    else item.parentNode.insertBefore(sibling, item)
    handle.focus()
  },

  announce(root, msg) {
    let live = root.querySelector("[data-sr-live]")
    if (live) live.textContent = msg
  },

  destroyed() {
    this.moduleSortable && this.moduleSortable.destroy()
    ;(this.entrySortables || []).forEach((s) => s.destroy())
    this.el.removeEventListener("keydown", this.onKeydown)
  },
}

export default ModuleLayout
