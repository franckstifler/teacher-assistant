// Marks a form `data-dirty` while its values differ from what was last saved,
// which reveals its <.save_bar>. The baseline is taken at mount and again when the
// server acknowledges a submit without field errors (LiveView removes the
// `phx-submit-loading` class on the ack, even when the save changed no markup).
// The bar's "Annuler" is a plain reset: it restores the values the server rendered.
const snapshot = (form) => {
  const pairs = []
  for (const [name, value] of new FormData(form)) {
    if (name === "_csrf_token" || name.startsWith("_unused_")) continue
    pairs.push(`${name}=${value instanceof File ? value.name : value}`)
  }
  return pairs.sort().join("&")
}

const hasErrors = (form) =>
  form.querySelector(".input-error, .select-error, .textarea-error") !== null

export const DirtyForm = {
  mounted() {
    this.baseline = snapshot(this.el)
    this.check = () => this.toggle(snapshot(this.el) !== this.baseline)
    this.onReset = () => requestAnimationFrame(this.check)
    this.el.addEventListener("input", this.check)
    this.el.addEventListener("change", this.check)
    this.el.addEventListener("reset", this.onReset)

    this.observer = new MutationObserver(() => {
      const loading = this.el.classList.contains("phx-submit-loading")
      if (this.wasLoading && !loading && !hasErrors(this.el)) this.baseline = snapshot(this.el)
      this.wasLoading = loading
      this.check()
    })
    this.observer.observe(this.el, {attributes: true, attributeFilter: ["class"]})
    this.toggle(false)
  },

  updated() {
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
