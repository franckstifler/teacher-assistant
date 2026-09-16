# v1.3 — Fiche de préparation (lesson-plan editor) — Design

> Design spec. Written 2026-07-02. **Deliverable = spec first; no code until the plan is approved.**
> Phase 1, increment v1.3 of the from-scratch rethink (see [`docs/PRODUCT.md`](../../PRODUCT.md)).
> Domain basis: [`docs/domain/02-cba-pedagogy.md`](../../domain/02-cba-pedagogy.md) §3 and
> [`docs/domain/03-teacher-documents.md`](../../domain/03-teacher-documents.md) §4.
> Brand basis: the shipped "Tableau" identity + the P1/P2 component kit already in `core_components.ex`.

## 0. Premise

The teacher toolkit already ships year setup, the **fiche de progression** (year pacing plan, with
PDF import), the **cahier de textes** (teaching log), programme coverage, and the marks register.
v1.3 adds the next document down the chain
([`03`](../../domain/03-teacher-documents.md) "How the documents fit together"): the
**fiche de préparation** — the per-lesson plan — **scaffolded from a progression entry**. It is the
last per-lesson planning artifact needed to complete the independent-teacher product before the
school layer (Phase 2).

The fiche de préparation has two equally-weighted jobs (confirmed with the user):
1. **A private planning aid** — the teacher structures a lesson before class.
2. **An inspection-ready document** — printed / saved as PDF to submit to the chef de département or
   inspecteur pédagogique.

Guiding domain reality (doc 02 §1): CBA adoption is uneven; **support the APC structure without
forcing it**. Every CBA field is optional so a teacher can use the fiche PPO-style or freeform.

## 1. Scope

**In scope**
- Two new Ash resources: `LessonPlan` (the fiche) and `LessonStep` (an ordered déroulement row).
- A LiveView **editor** with **autosave-on-blur**, mobile cards → `md:` table for the steps.
- **Scaffolding** from a progression entry: header fields pre-filled; module / famille de
  situations / classe / effectif shown as a derived-at-render cartouche.
- A **print route** rendering a clean, paginated A4 fiche for browser Print → Save as PDF.
- Reachability from the fiche-de-progression builder; bilingual FR/EN; full test coverage.

**Out of scope (YAGNI — deferred)**
- One-click server-side PDF generation (ChromicPDF/headless Chrome); DOCX/HTML file export.
- CBA phase-model auto-presets (3-phase / 6–7-step pre-fill of steps).
- Multiple fiches per entry; sharing/collaboration; inspector visa/signature workflow.

## 2. Data model

Two new resources, following existing `Academics` patterns (`AshPostgres`, `policy always()`,
`uuid_v7_primary_key`, `timestamps()`), one migration. **No new enums** — nothing here needs a
constrained atom, so we stay clear of the bare-`:atom` anti-pattern (see
[`memory: feedback-ash-enums-not-atom`]; if an enum is ever added, define an `Ash.Type.Enum`).

### 2.1 `LessonPlan` — the fiche (1:1 with a progression entry)

`belongs_to :progression_entry` with a **unique index on `progression_entry_id`** (enforces 1:1).
All content fields optional (CBA-supportive, not mandatory):

| Attribute | Type | Notes |
|---|---|---|
| `lesson_date` | `:date`, nil-able | when the lesson is planned |
| `duration_minutes` | `:integer`, default 55 | APC lesson ≈ 50–55 min; seeded from `entry.planned_hours × 60` at create |
| `titre` | `:string`, nil-able | seeded from `entry.lesson_title` |
| `competence_attendue` | `:string` (long text), nil-able | seeded from `entry.competence_visee` |
| `situation_probleme` | `:string` (long text), nil-able | the ESV entry point / corpus |
| `objectifs` | `:string` (long text), nil-able | savoirs / savoir-faire / savoir-être, freeform |
| `supports` | `:string` (long text), nil-able | auxiliaire didactique / materials |
| `prerequis` | `:string` (long text), nil-able | PPO-friendly prior-knowledge field |

`has_many :lesson_steps`. Long-text fields use `:string` (Postgres `text`) — the codebase's
convention for multi-line content (cf. `progression_entry.competence_visee`, `teaching_log_entry.note`).

### 2.2 `LessonStep` — an ordered déroulement row

`belongs_to :lesson_plan` (`allow_nil? false`):

| Attribute | Type | Notes |
|---|---|---|
| `position` | `:integer`, `allow_nil? false` | 1-based order within the fiche |
| `etape` | `:string`, nil-able | phase label, free text (e.g. "Découverte") |
| `duration_minutes` | `:integer`, nil-able | minutes for this step |
| `contenus` | `:string` (long text), nil-able | content |
| `supports` | `:string` (long text), nil-able | materials for this step |
| `activites` | `:string` (long text), nil-able | learning activities |

Body table maps to the real Cameroon APC layout `Étape · Durée · Contenus · Supports · Activités`
(doc 02 §3, doc 03 §4). Activities kept as one column (not split enseignant/apprenant) — YAGNI.

### 2.3 Derived-at-render (NOT stored on the fiche)

Read live from the entry and its context so the fiche always reflects the current plan:
`module` (`entry.module`), `famille_de_situations` (`entry.famille_de_situations`),
`categories_action` (`entry.categories_action`), `classe` (`ctx.level`),
`effectif` (count of `Academics.list_students(class_group)` when the context has a class group),
`annee` (`year.name`), `discipline` (`ctx.subject`).

## 3. Context API (`Academics`)

New functions, mirroring the existing ownership idiom (resolve to the workspace via the entry's
progression plan, reusing `fetch_owned_plan/2`):

- `fetch_owned_entry_with_context(entry_id, ws)` → `{:ok, %{entry, plan, ctx, class_group, year}}`
  or `:error`. Loads the entry, verifies its progression plan is owned, and gathers the derived
  cartouche data (context, class group, active year). One read path for both the editor and print.
- `ensure_lesson_plan(entry, ctx)` → `{:ok, lesson_plan}`. Returns the entry's fiche, creating an
  empty one (with seeded header fields) if none exists. Idempotent (1:1).
- `get_lesson_plan_for_entry(entry_id)` → `LessonPlan | nil` (for the "already prepared" indicator).
- `update_lesson_plan(lesson_plan, attrs)` → `{:ok, lesson_plan}` (per-field autosave).
- `list_lesson_steps(lesson_plan)` → steps ordered by `position`.
- `add_lesson_step(lesson_plan, attrs \\ %{})` → appends a step at `max(position)+1`.
- `update_lesson_step(step, attrs)` → `{:ok, step}` (per-field autosave).
- `delete_lesson_step(step)` → `:ok`.
- `move_lesson_step(step, :up | :down)` → swaps `position` with the adjacent step; no-op at the ends.

**IDOR:** every entry point resolves through `fetch_owned_entry_with_context/2`; a foreign or
unknown entry id yields `:error` → the LiveView/controller redirects (exactly as `coverage_live`
and `fiche_live` do today). Step mutations verify the step's `lesson_plan` belongs to an owned entry.

## 4. Editor — `LessonPlanLive`

Route: `live "/teacher/entries/:entry_id/fiche", Teacher.LessonPlanLive, :edit`.

Mount resolves ownership, `ensure_lesson_plan/2`, and assigns the derived cartouche. Consistent with
the P1/P2 design system: Tableau kit, mobile-first, `ta-num`, stable DOM ids.

- **Header** — `<.page_header>` titled by the lesson. A read-only **cartouche** strip of derived
  facts (Discipline · Classe · Effectif · Module · Famille de situations · Année) rendered with the
  `<.stat>`/eyebrow vocabulary. Then an editable header form: `lesson_date`, `duration_minutes`
  (`inputmode="numeric"`), `titre`, `competence_attendue`, `situation_probleme`, `objectifs`,
  `supports`, `prerequis`. Each field **autosaves on blur** (`phx-blur` → `update_lesson_plan/2`).
- **Déroulement (steps)** — mobile = stacked `ta-leaf` cards; `md:` = APC table
  `Étape | Durée | Contenus | Supports | Activités`. Each row: edit-in-place fields autosaving on
  blur, **move up / move down** controls (position-based; no drag-drop JS — avoids the
  `drag-threshold` / `gesture-conflict` pitfalls), and delete-with-confirm. `＋ Add step` appends a
  blank row.
- **Running-duration check** — a subtle line summing step minutes vs header `duration_minutes`
  ("45 / 55 min"), echoing the fiche hours-total pattern. Informational, never blocking.
- **Saved indicator** — a small "Enregistré · à l'instant" affordance updates on each autosave
  (satisfies `submit-feedback` / `success-feedback`); no Save button, no unsaved-changes trap.
- **Empty state** — `<.empty_state>` ("Aucune étape — ajoutez la première phase") when no steps.
- **Print** — a `#fiche-print-link` opens the print route (§5) in a new tab, with a one-line hint
  ("Utilisez Imprimer → Enregistrer en PDF de votre navigateur").

**Stable DOM ids** (tests pin these): `#lesson-plan`, `#fiche-header-form`, `#lesson-steps`,
`#step-row-<id>`, `#step-add`, `#step-delete-<id>`, `#step-up-<id>`, `#step-down-<id>`,
`#fiche-print-link`, `#fiche-saved-indicator`, `#fiche-duration-check`.

## 5. Print route

Route: `get "/teacher/entries/:entry_id/fiche/print", Teacher.FichePrintController, :show`.

A **plain controller + HEEx template** (not a LiveView — the print view is static, renders
identically when the browser generates the PDF, and needs no socket/JS). Same
`fetch_owned_entry_with_context/2` ownership check → foreign id redirects to `/teacher`.

- **Layout:** a minimal print layout (NOT `Layouts.app`) — white background, black text, no nav.
  The school-fiche cartouche header (Discipline · Classe · Effectif · Module · Durée · Date ·
  Compétence attendue · Situation problème · Supports · Prérequis when present), then the
  déroulement table `Étape · Durée · Contenus · Supports · Activités`.
- **Print CSS** (`@media print` block in the print template):
  `@page { size: A4; margin: 15mm }`; `thead { display: table-header-group }` so the table header
  repeats on every page; `tr { break-inside: avoid }`; neutral serif body stack for the formal
  register (Fraunces stays reserved for the app's screen headers per the guardrail).
- **From the editor:** opened in a new tab; the teacher uses browser **Print → Save as PDF**.

## 6. Reachability & i18n

- **Fiche-de-progression builder** (`fiche_live.ex`): each lesson entry row gains a **"Préparer /
  Prepare"** action → `/teacher/entries/:entry_id/fiche`, plus a small check indicator on entries
  that already have a fiche (`get_lesson_plan_for_entry/1`). Non-lesson entry types (évaluation,
  révision, etc.) still get the action — a teacher may prepare any of them; no gating.
- **i18n:** all labels via `gettext`; FR filled during extraction (the P0/P1 discipline —
  `mix gettext.extract --merge` + FR msgstr, run once at the end of implementation). CBA vocabulary
  uses the controlled bilingual terms from
  [`glossary-fr-en.md`](../../domain/glossary-fr-en.md): fiche de préparation = lesson plan,
  déroulement = lesson flow/procedure, étapes de la leçon = lesson steps/phases, compétence
  attendue, famille de situations, situation problème.

## 7. Testing (TDD)

- **Resource / context tests:** create-from-entry prefill (titre ← lesson_title, competence ←
  competence_visee, duration seeded from planned_hours); `ensure_lesson_plan/2` idempotency (1:1);
  steps CRUD; `move_lesson_step/2` ordering incl. no-op at the ends; derived effectif; **IDOR**
  (foreign entry → `:error`; step mutation on a foreign fiche rejected).
- **Editor LiveView tests:** renders derived cartouche + prefilled header; autosave-on-blur persists
  a field (`render_blur`); add / edit / reorder (up-down) / delete steps; running-duration line;
  empty state; unknown/foreign entry redirects.
- **Print route tests:** renders header + all steps; uses the print layout (asserts **no**
  `#main-nav`); IDOR redirect.
- `mix precommit` green throughout (compile `--warnings-as-errors`, format, test).

## 8. Definition of done

- From any lesson entry in the fiche-de-progression builder, a teacher opens a fiche, fills the CBA
  header + déroulement steps, edits with **autosave-on-blur** (no Save button, no data-loss trap),
  and the entry shows a "prepared" indicator.
- The print route produces a clean, **paginated A4 fiche** the teacher saves as PDF from the browser.
- All CBA header fields **optional** (usable PPO-style / freeform); **bilingual FR/EN**; mobile cards
  → `md:` table; every new DOM id stable and covered by tests; `mix precommit` green.

## 9. Guardrails (unchanged from DESIGN.md / prior phases)

Operational density over decoration; Fraunces reserved for headers (print uses neutral serif); ≤8px
radii; stable DOM ids; both themes and both languages verified at mobile widths; no color-only
meaning; deterministic before AI (this feature is entirely deterministic — no AI). Every change
lands behind LiveView test selectors — no test churn beyond added coverage.
