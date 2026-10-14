// Marks a form `data-dirty` while its values differ from what was last saved,
// which reveals its <.save_bar>. The saved values are recorded at mount and
// again when the server acknowledges a submit without field errors (LiveView
// removes `phx-submit-loading` on the ack, even when the save changed no markup).
//
// "Annuler" (the bar's reset button) restores those recorded values itself: a
// native reset would bring back the `value` attributes of the last render, and
// with phx-change validation that render already holds what the user typed.
const fields = (form) =>
  Array.from(form.elements).filter(
    (el) => el.name && el.type !== "hidden" && el.type !== "file" && !el.disabled
  )

const read = (el) => {
  if (el.type === "checkbox" || el.type === "radio") return el.checked
  if (el.multiple) return Array.from(el.selectedOptions, (o) => o.value).join("\u0000")
  return el.value
}

const write = (el, value) => {
  if (el.type === "checkbox" || el.type === "radio") el.checked = value
  else if (el.multiple) {
    const values = value.split("\u0000")
    for (const option of el.options) option.selected = values.includes(option.value)
  } else el.value = value
}

// keyed by name (and value, for radios and checkboxes, so `roles[]`-style lists
// keep one entry per box) — LiveView may replace the elements
const key = (el) =>
  el.type === "radio" || el.type === "checkbox" ? `${el.name}=${el.value}` : el.name

// field errors, or a server message marked `data-save-error`, keep the bar up
const hasErrors = (form) =>
  form.querySelector(".input-error, .select-error, .textarea-error, [data-save-error]") !== null

export const DirtyForm = {
  mounted() {
    this.record()
    this.check = () => this.toggle(this.changed())
    this.onReset = (event) => {
      event.preventDefault()
      this.restore()
    }
    this.el.addEventListener("input", this.check)
    this.el.addEventListener("change", this.check)
    this.el.addEventListener("reset", this.onReset)

    this.observer = new MutationObserver(() => {
      const loading = this.el.classList.contains("phx-submit-loading")
      if (this.wasLoading && !loading && !hasErrors(this.el)) this.record()
      this.wasLoading = loading
      this.check()
    })
    this.observer.observe(this.el, {attributes: true, attributeFilter: ["class"]})
    this.toggle(false)
  },

  updated() {
    this.check()
  },

  record() {
    this.saved = new Map(fields(this.el).map((el) => [key(el), read(el)]))
  },

  changed() {
    return fields(this.el).some((el) => this.saved.has(key(el)) && this.saved.get(key(el)) !== read(el))
  },

  restore() {
    let last = null
    for (const el of fields(this.el)) {
      if (!this.saved.has(key(el))) continue
      const value = this.saved.get(key(el))
      if (read(el) === value) continue
      write(el, value)
      last = el
    }
    // one input event lets phx-change re-validate the restored form
    if (last) last.dispatchEvent(new Event("input", {bubbles: true}))
    this.check()
  },

  toggle(dirty) {
    if (dirty) this.el.setAttribute("data-dirty", "")
    else this.el.removeAttribute("data-dirty")
  },

  destroyed() {
    this.observer.disconnect()
  },
}
