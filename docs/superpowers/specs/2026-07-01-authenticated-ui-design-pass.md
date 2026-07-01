# Authenticated UI Design Pass — applying & polishing "Tableau"

> Design spec. Written 2026-07-01. **Deliverable = spec first; no code changes until approved.**
> Scope: **all authenticated teacher pages.** Brand decision: **keep & apply the shipped
> "Tableau" identity** ([`docs/DESIGN.md`](../../DESIGN.md)) — not a rebrand.
> Cross-checked against the ui-ux-pro-max rule set (priorities 1–10).

## 0. Premise — we already have a brand

The app ships a mature identity (**Tableau**): OKLCH chalkboard-dark (default) + craie-light daisyUI
themes, Fraunces + IBM Plex Mono, `ta-leaf` / `ta-board` / `ta-eyebrow` / `ta-mark` primitives, a
signature **Coverage Ribbon**, global focus-visible rings, tabular-nums, and reduced-motion handling
(`assets/css/app.css`). The design-system engine, run blind on "education teacher gradebook",
independently proposed a dark-slate base with a green accent — i.e. it **re-derived Tableau's core**.
So this pass does **not** introduce new colors or fonts. It (a) fills gaps in navigation and shared
components, and (b) raises the three newest pages (roster / marks / summary) and the rest to one
consistent, denser, more accessible bar — inside Tableau.

## 1. Cross-cutting findings & fixes (do these first — they touch every page)

### 1.1 Navigation is under-built — the biggest gap `[nav-label-icon, persistent-nav, adaptive-navigation]`
`Layouts.app`'s `#main-nav` exposes only **Dashboard** and **Log**. Coverage, Import, the fiche
builder, and the entire v1.2 surface (**Roster / Marks / Results**) are reachable *only* through
in-page links or by typing a URL. A teacher who wants to enter marks has no top-level path; the
**roster** is reachable only as a redirect target when marks has no class group.

**Fix.** Make navigation reflect the teacher's real jobs. Because most destinations are
**per-class** (a `TeachingContext`), introduce a lightweight **class context switcher** + a stable
task nav:

- **Desktop (≥768px):** keep the top tab bar, expand to the top-level, class-independent
  destinations: **Dashboard · Log · Import**. Add a **class selector** (select or menu of the
  teacher's `TeachingContext`s) that, once a class is chosen, reveals its per-class actions
  (**Fiche · Coverage · Roster · Marks · Results**) as a secondary row or a contextual sub-nav.
- **Mobile (<768px):** a **bottom tab bar, ≤5 items** `[bottom-nav-limit]` — **Dashboard · Marks ·
  Coverage · Log** + a "More" overflow for Import/Roster. Respect the safe-area inset
  `[safe-area-awareness]`; reserve body padding so content isn't hidden behind it
  `[fixed-element-offset]`.
- Highlight the active destination `[nav-state-active]`; keep placement identical across pages
  `[navigation-consistency]`.

This is the one structural change; everything else is styling/component work. If a full class
switcher is too big for this pass, the **minimum** is: add **Roster** and **Coverage** entry points
to the dashboard per-context card (next to the existing Marks/Results) so every per-class page is
reachable without URL-typing.

### 1.2 Extract a shared component kit (DRY the repeated markup) `[consistency, visual-hierarchy]`
The same structures are hand-rolled on every page. Promote them to `core_components.ex` so pages get
consistent spacing, headings, and a11y for free:

- **`<.page_header eyebrow=… title=… >`** — the `ta-eyebrow` + `h1` block repeated verbatim in all
  9 pages (optional `:actions` slot for the right-aligned buttons, e.g. dashboard's year chip,
  fiche's Duplicate).
- **`<.stat label=… value=… >`** (tabular-nums via `ta-num`) — unifies the coverage big-number, the
  marks-summary 2×2 grid, and any future KPI. One elevation/rhythm.
- **`<.empty_state icon=… title=… >`** with a primary-action slot — unifies dashboard "No plan yet",
  fiche "No entries yet", coverage "Everything is covered", summary "No séquences yet".
- **`<.setup_gate icon=… title=… message=… >`** — the dashboard's icon-chip gate is the nicest gate
  in the app; make it the single gate component so roster/marks/summary redirects land on an equally
  strong screen instead of a bare flash.

### 1.3 Responsive density: cards on mobile, tables on desktop `[data-table, visual-hierarchy]`
DESIGN.md mandates "prefer tables for lists users scan/compare/act on; stacked cards on mobile."
Today roster, mark-entry, and summary are **card/list-only at every width**. Keep the mobile stack,
but at `md:` collapse them into real tables:

- **Mark entry:** `Student | Devoir 1 | Devoir 2 | Compo | … ` grid so a teacher grading a full class
  on a laptop sees everyone at once (mobile stays one-assessment-at-a-time).
- **Summary:** `Rang | Élève | Moyenne | Mention` table with tabular-nums; the mobile card list
  stays.
- Use `<caption>`/`<th scope>` for screen readers `[data-table]`; sortable where useful
  `[sortable-table]`.

### 1.4 Accessibility passes to apply everywhere `[form-labels, color-not-only, touch-target-size]`
- **Mark inputs need names.** Each `#mark-input-<id>` shows the student's name in an adjacent cell
  but the `<input>` itself has no programmatic label — add `aria-label={s.full_name}`; ensure ≥44px
  height `[touch-friendly-input]`.
- **Mentions/pass must not rely on color alone.** Render the mention **word** (Passable/Bien/…) and
  a pass/fail glyph next to any color `[color-not-only]`.
- Keep the existing global focus rings; verify **craie (light)** contrast independently for the
  muted `text-base-content/55–65` labels `[color-accessible-pairs]`.
- Number columns use `ta-num` (tabular figures) so marks/ranks/percentages align and don't jitter
  `[number-tabular]`.

## 2. Per-page specs

Each: **Current → Changes → Rules.** "Keep" means it already meets the bar.

### 2.1 App shell — `layouts.ex`
- **Current:** clean sticky top bar (logo, theme toggle, user, sign-out), thin 2-item nav, FR/EN
  switch, `max-w-6xl` main.
- **Changes:** implement §1.1 nav. Move the FR/EN switch into a small menu on mobile to free the
  bottom bar. Keep the top bar; add active-state styling to tabs. Ensure the sign-out (destructive)
  stays visually separated from nav `[destructive-nav-separation]`.
- **Rules:** nav-*, safe-area-awareness, persistent-nav.

### 2.2 Dashboard — `dashboard_live.ex`
- **Current:** strong. `page_header` + year chip, per-plan `ta-leaf` cards with Coverage Ribbon and
  Open plan / Marks / Results. Good setup-gate and empty state.
- **Changes:** adopt `<.page_header>`/`<.empty_state>`/`<.setup_gate>`. Add **Roster** + **Coverage**
  links to each card (§1.1 minimum). Add a one-line **at-a-glance strip** above the cards using
  `<.stat>` (e.g. classes count · overall coverage · séquence in progress) — monitoring, not
  decoration `[dashboards]`. Give each card a subtle "behind schedule" accent when coverage is low
  (Ribbon already supports `data-behind`).
- **Rules:** visual-hierarchy, consistency, empty-states.

### 2.3 Setup wizard — `setup_live.ex`
- **Current:** tidy single-column, two `ta-leaf` fieldsets, sensible defaults, one primary CTA.
- **Changes:** mostly keep. Add a **stepper/progress affordance** even if one screen ("Year →
  Class") for orientation `[multi-step-progress]`. Add helper text under Subsystem/Weekly-hours
  `[input-helper-text]`. Preserve input on validation error and surface the actual reason instead of
  a generic "Could not complete setup" `[error-clarity]` (today it swallows the reason).
- **Rules:** progressive-disclosure, error-clarity, input-helper-text.

### 2.4 Fiche builder — `fiche_live.ex`
- **Current:** entry list as `ta-leaf` rows, add-entry form, duplicate. Good empty state.
- **Changes:** `md:` table (`Module | Leçon | Type | Heures | ⋯`) with the add-entry form as a
  sticky bottom row or an inline "＋ add" affordance; keep mobile cards. Group the add-entry fields
  `[field-grouping]`. Show a running **planned-hours total** and how it compares to the year's
  teachable hours (ties into coverage). Right-align the delete in an overflow on mobile
  `[overflow-menu]`.
- **Rules:** data-table, field-grouping, number-tabular.

### 2.5 Coverage view — `coverage_live.ex`
- **Current:** big % number + Coverage Ribbon + "Not yet covered" list. Clean.
- **Changes:** wrap the big number in `<.stat>`; add per-**séquence** breakdown using the Ribbon's
  6-cell structure (the data already exists in `coverage.by_sequence`) so a teacher sees *where* the
  gap is, not just the total. Keep the uncovered list; add the covered/planned hours to each row.
  Empty ("Everything is covered") → `<.empty_state>`.
- **Rules:** dashboards, visual-hierarchy, chart empty/loading states.

### 2.6 Log (cahier de textes) — `log_live.ex`
- **Current:** single form: lesson select, date, hours, content, status, homework, note.
- **Changes:** the **hours** field renders blank (value prop ignored on a field-bound input) — fix so
  it shows the default `[forms]`. Add inline validation on blur `[inline-validation]`; success
  feedback on save beyond the flash `[success-feedback]`. Consider a **recent-entries** list beneath
  the form so logging feels like a ledger, not a lost-in-void submit. Use the correct mobile keyboard
  for hours (`inputmode="decimal"`) `[input-type-keyboard]`.
- **Rules:** forms, inline-validation, success-feedback.

### 2.7 Import — `import_live.ex`
- **Current:** upload → review → save, with a context gate, truncation notice, confidence eyebrow,
  editable rows. Genuinely good; the most complex flow.
- **Changes:** make the **stages a visible stepper** (Upload · Review · Save) `[multi-step-progress]`.
  The truncation notice already uses `alert-warning` — keep. Ensure the row grid becomes a table on
  desktop for easier review of many rows `[data-table]`, and virtualize/paginate beyond ~100 rows
  `[virtualize-lists]`. Confirm the raw-text disclosure is a real progressive-disclosure toggle
  `[progressive-disclosure]`.
- **Rules:** multi-step-progress, data-table, progressive-disclosure.

### 2.8 Roster — `roster_live.ex` (v1.2, least polished)
- **Current:** create-class form OR student form + delete rows.
- **Changes:** `md:` table (`Élève | Sexe | Matricule | ⋯`); mobile stacked cards. Show a
  **garçons/filles count** header (the data the domain already tracks). Group add-student fields
  `[field-grouping]`; `inputmode` for matricule. Delete → confirm + **undo** toast `[undo-support,
  confirmation-dialogs]`. Strong empty state ("No students yet — add your first"). Sex select needs a
  clear label and both options visible; consider a segmented control (♀/♂ with text) `[color-not-only]`.
- **Rules:** data-table, undo-support, field-grouping, touch-target-size.

### 2.9 Mark entry — `marks_live.ex` (v1.2, flagship of this pass)
- **Current:** séquence select → assessment select → per-student number inputs → save.
- **Changes:**
  - Turn the two selects + "new assessment" into a compact **toolbar** (séquence • assessment •
    ＋new) that stays put while scrolling the roster `[fixed-element-offset]`.
  - Add a **"12 of 30 entered"** progress line and a live **class average preview** as marks are
    typed (client-side, from `Academics.Marks`) — immediate feedback `[success-feedback]`.
  - Each score input: `aria-label` = student name, `inputmode="decimal"`, ≥44px, `min=0 max=20`,
    invalid-on-blur inline error `[inline-validation, touch-friendly-input]`.
  - Desktop `md:` grid (students × assessments) so a laptop shows the whole class; mobile keeps the
    one-assessment scroll list — the natural "I just graded this devoir" flow.
  - Blank = absent stays; show an explicit **"Abs"** affordance so blank isn't ambiguous.
- **Rules:** forms, inline-validation, number-tabular, touch-target-size.

### 2.10 Séquence summary — `marks_summary_live.ex` (v1.2)
- **Current:** 2×2 `ta-leaf` stats (class avg, pass rate, high/low, girls/boys) + per-student list
  with moyenne + rank.
- **Changes:**
  - Stats → `<.stat>` grid with `ta-num`; add **mention** distribution.
  - Per-student list → `md:` table `Rang | Élève | Moyenne | Mention`; each row shows the **mention
    word + color** (not color alone) and a tiny inline bar for the /20 `[color-not-only]`.
  - Garçons/filles split as a **two-segment bar** (not just two numbers) — one restrained data-viz
    moment, echoing the Coverage Ribbon `[chart-type, pattern-texture]`.
  - Add a **séquence switcher** matching the mark-entry toolbar for consistency.
  - Empty → `<.empty_state>` guiding to mark entry.
  - This is a **verification tool** (DESIGN.md §Report Cards): show missing marks explicitly, don't
    hide them.
- **Rules:** color-not-only, number-tabular, empty-data-state, chart-type.

## 3. Prioritization

- **P0 (structure & consistency — unlocks the rest):** §1.1 navigation, §1.2 component kit
  (`page_header`, `stat`, `empty_state`, `setup_gate`), §1.4 a11y fixes.
- **P1 (the v1.2 pages — newest, least polished):** 2.9 mark entry, 2.10 summary, 2.8 roster.
- **P2 (polish existing):** 2.2 dashboard strip, 2.5 coverage per-séquence, 2.4 fiche table, 2.7
  import stepper, 2.6 log fixes, 2.3 setup helper text.

## 4. Guardrails (unchanged from DESIGN.md)

Operational density over decoration; Fraunces display reserved for landing/section headers, not work
surfaces; ≤8px radii; stable DOM IDs for every form/row/gate (tests depend on them); both themes
verified; both languages fit at mobile widths; no color-only meaning. Every change lands behind the
existing LiveView test selectors — no test churn beyond added coverage.

## 5. Rollout

Ship P0 as a small foundational PR (component kit + nav), then one PR per v1.2 page (P1), then the P2
polish. Each PR keeps `mix precommit` green and adds LiveView assertions for new DOM.
