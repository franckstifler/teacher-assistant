// Manual-activation tabs (links): arrows, Home and End move focus; Enter follows the tab.
export const MemberProfileTabs = {
  mounted() {
    this.onKeydown = (event) => {
      const tabs = [...this.el.querySelectorAll('[role="tab"]')]
      const index = tabs.indexOf(event.target)
      if (index < 0) return
      let next
      switch (event.key) {
        case "ArrowRight": next = (index + 1) % tabs.length; break
        case "ArrowLeft": next = (index + tabs.length - 1) % tabs.length; break
        case "Home": next = 0; break
        case "End": next = tabs.length - 1; break
        default: return
      }
      event.preventDefault()
      tabs[next].focus()
    }
    this.el.addEventListener("keydown", this.onKeydown)
  },
  destroyed() { this.el.removeEventListener("keydown", this.onKeydown) },
}
