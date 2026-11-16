// Keeps the unsaved roll call on the phone. The taps live in the LiveView process
// until « Valider l'appel »; a locked phone, a dropped network or a reload ends that
// process and the page comes back with the saved roll. The server hands over the roll
// after each change (`roll-draft:save`) and asks to forget it once recorded or ignored
// (`roll-draft:clear`); on mount, reconnect or a switch to another roll, the hook hands
// back what it kept for that roll (`restore_draft`).
//
// Storage can be missing or full (private mode, old browsers): then nothing is kept,
// as before.
const PREFIX = "roll-draft:"
const MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000

const store = () => {
  try {
    return window.localStorage
  } catch (_error) {
    return null
  }
}

const read = (key) => {
  try {
    const raw = store()?.getItem(key)
    return raw ? JSON.parse(raw) : null
  } catch (_error) {
    return null
  }
}

const write = (key, draft) => {
  try {
    store()?.setItem(key, JSON.stringify({savedAt: Date.now(), draft}))
  } catch (_error) {}
}

const remove = (key) => {
  try {
    store()?.removeItem(key)
  } catch (_error) {}
}

// Drafts of rolls nobody came back to.
const prune = () => {
  const storage = store()
  if (!storage) return
  try {
    const keys = []
    for (let i = 0; i < storage.length; i++) keys.push(storage.key(i))
    keys
      .filter((key) => key && key.startsWith(PREFIX))
      .forEach((key) => {
        const entry = read(key)
        if (!entry || !(Date.now() - entry.savedAt < MAX_AGE_MS)) remove(key)
      })
  } catch (_error) {}
}

export const RollDraft = {
  mounted() {
    prune()
    this.handleEvent("roll-draft:save", ({key, draft}) => write(key, draft))
    this.handleEvent("roll-draft:clear", ({key}) => remove(key))
    this.restore()
  },

  // Ma journée swaps the roll inside the same panel.
  updated() {
    if (this.el.dataset.draftKey !== this.key) this.restore()
  },

  reconnected() {
    this.restore()
  },

  restore() {
    this.key = this.el.dataset.draftKey
    const entry = this.key && read(this.key)
    if (entry && entry.draft) this.pushEvent("restore_draft", {key: this.key, draft: entry.draft})
  },
}
