// Print pages (spec audit follow-ups A6): what used to be inline `onclick` /
// `onchange` handlers, now allowed by the Content-Security-Policy (`script-src 'self'`).
//   <button data-print>                       prints the page
//   <select data-submit-on-change>            submits its form when changed
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-print]").forEach((el) =>
    el.addEventListener("click", () => window.print()),
  )

  document.querySelectorAll("[data-submit-on-change]").forEach((el) =>
    el.addEventListener("change", () => el.form && el.form.submit()),
  )
})
