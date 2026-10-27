// A tab strip that scrolls sideways on phones: bring the current tab into view,
// so « Résultats » or « Trimestre 1 » is not left hidden past the right edge.
// Only the strip scrolls, never the page.
const reveal = (strip) => {
  const tab = strip.querySelector('[aria-current="page"], .tab-active')
  if (!tab) return

  const box = strip.getBoundingClientRect()
  const rect = tab.getBoundingClientRect()
  if (rect.left >= box.left && rect.right <= box.right) return

  strip.scrollLeft += rect.left - box.left - (box.width - rect.width) / 2
}

export const ScrollActiveTab = {
  mounted() { reveal(this.el) },
  updated() { reveal(this.el) },
}
