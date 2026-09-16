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

This is the one structural change; everything else is styling/component work.

**Decision (locked): full class-context switcher.** We build the switcher, not a stopgap. Because
it introduces app state (a "currently selected class"), treat it as its own design step:

- The switcher lists the teacher's `TeachingContext`s for the active academic year; selecting one
  sets a `current_context` in the session/scope and the shell surfaces that class's per-class actions.
- Persist the selection across navigation (scope assign), default to the most recently used class,
  and fall back to the setup gate when the teacher has no class yet.
- As a transitional courtesy while the switcher lands, the dashboard per-context cards also gain
  **Roster** + **Coverage** links (they're cheap and useful regardless).

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
**Decision (locked): adopt cards → tables at desktop.** DESIGN.md mandates "prefer tables for lists
users scan/compare/act on; stacked cards on mobile." Today roster, mark-entry, and summary are
**card/list-only at every width**. Keep the mobile stack, but at `md:` collapse them into real
tables:

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

## 3. Prioritization (confirmed sequencing: P0 → P1 → P2)

Ship in order; each phase builds on the previous. **P0 and P1 are both in-scope now** (foundation
first, then immediately the v1.2 pages that sit on it); P2 follows.

- **P0 (structure & consistency — unlocks the rest):** §1.1 **full class-context switcher**, §1.2
  component kit (`page_header`, `stat`, `empty_state`, `setup_gate`), §1.4 a11y fixes. Because the
  switcher adds `current_context` app state, it earns its own brainstorm before implementation.
- **P1 (the v1.2 pages — newest, least polished; built on P0):** 2.9 mark entry, 2.10 summary,
  2.8 roster — with the locked cards→tables treatment.
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

## 6. Definition of done (per phase)

- **P0 done when:** the four kit components exist in `core_components.ex` with tests; every
  authenticated page renders its header/empty/gate through them (no hand-rolled duplicates remain);
  the class-context switcher persists a selection across navigation and every per-class page is
  reachable from the shell without URL-typing; mark inputs carry `aria-label`s; craie + chalkboard
  both pass contrast on muted labels.
- **P1 done when:** roster, mark-entry, and summary render as tables at `md:` and cards below, all
  numeric columns use `ta-num`, mentions show word+icon+color (never color alone), and existing DOM
  IDs are preserved so the current LiveView tests still pass unchanged.
- **P2 done when:** each existing page adopts the kit and its listed change, with the log hours-field
  and setup error-reason fixes verified.

## Appendix A — shared component API (P0)

Concrete HEEx signatures so P0 is unambiguous (final names may adjust in P0 brainstorm):

```elixir
# section header used by every page
attr :eyebrow, :string, required: true      # ta-eyebrow text, e.g. gettext("Séquence 2 · résultats")
attr :title, :string, required: true        # h1
slot :actions                                # right-aligned controls (year chip, Duplicate, switcher)
def page_header(assigns)

# one KPI/stat cell (tabular-nums)
attr :label, :string, required: true         # ta-eyebrow micro-label
attr :value, :string, required: true         # pre-formatted; renders in ta-num
attr :suffix, :string, default: nil          # e.g. "/20", "%"
attr :tone, :atom, default: :neutral          # :neutral | :primary | :behind (color accent only, never sole meaning)
def stat(assigns)

# empty state with one primary action
attr :icon, :string, required: true          # hero-* name
attr :title, :string, required: true
attr :message, :string, default: nil
slot :action                                  # the single primary CTA
def empty_state(assigns)

# strong setup gate (promotes the dashboard's gate to a component)
attr :icon, :string, required: true
attr :eyebrow, :string, required: true
attr :title, :string, required: true
attr :message, :string, required: true
slot :action, required: true
def setup_gate(assigns)
```

## Appendix B — mention labels (FR/EN) and pass display

Bands from [`docs/domain/04`](../../domain/04-grading-and-report-cards.md) §7 — pin the copy so
`Academics.Marks.mention/1` atoms map to consistent strings:

| atom (from `Marks.mention/1`) | FR label | EN label | tone |
|---|---|---|---|
| `:excellent` (≥18) | Excellent | Excellent | primary |
| `:tres_bien` (16–17.99) | Très bien | Very good | primary |
| `:bien` (14–15.99) | Bien | Good | primary |
| `:assez_bien` (12–13.99) | Assez bien | Fairly good | primary |
| `:passable` (10–11.99) | Passable | Pass | secondary (chalk-yellow) |
| `nil` (< 10) | Insuffisant | Below pass | accent (coral) |

Display rules: pass ≥ 10/20 is hard-coded; every mention shows **word + icon** (`hero-check-circle`
for ≥10, `hero-x-circle` for <10) so color is never the sole signal `[color-not-only]`. Ungraded
(no marks entered) renders "—", not a mention. These labels flow through `gettext`.

> Terminology note: at the **subject × séquence** level, below-10 is *Insuffisant* (under the
> moyenne) — **not** *Non admis*. Admission/redoublement is an **annual, cross-subject** decision
> that belongs to the school-layer bulletin (Phase 2), not to a solo teacher's per-subject register.
> (The earlier preview mockup used "Non admis"; this spec is the source of truth — use *Insuffisant*.)
