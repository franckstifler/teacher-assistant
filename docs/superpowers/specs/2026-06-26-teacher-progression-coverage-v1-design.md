# Design Spec — Independent Teacher: Progression & Coverage (v1)

**Date:** 2026-06-26
**Status:** Approved design → ready for implementation planning
**Branch context:** `codex/hybrid-workspace-context` (old school-centric model being removed)
**Domain source of truth:** [`docs/domain/`](../../domain/README.md)

---

## 1. Background & framing

TeacherAssistant is being rebuilt from scratch as a **Cameroon education platform** for teachers
and schools, marketed around the **Competency-Based Approach (CBA / APC)**. Settled product
constraints:

- **Mobile-first web app** (responsive Phoenix LiveView; built for phones + intermittent connectivity).
- **Bilingual FR + EN** (both subsystems, switchable).
- **Phoenix / Ash / LiveView** stack retained; product & data model rethought.

**Sequencing decision:** build **teacher-first** — a complete, delightful independent-teacher
product — then layer the school workspace (roles, report cards, fees, access control, statistics)
on top in a later phase. Rationale: teachers are the atomic unit (teacher↔school is legally
many-to-many; >45,000-teacher shortage drives moonlighting), they already share the pivot document
on WhatsApp, and bottom-up adoption is the on-ramp to school sales. See
[`docs/domain/05-school-roles-and-fees.md`](../../domain/05-school-roles-and-fees.md) §3.

**This spec covers v1 only:** the independent teacher's **Progression & Coverage** loop.

## 2. Goal & non-goals

### Goal
A Cameroon secondary teacher, on their phone, in French or English, can:
1. set up their teaching context with no school involved,
2. build a **fiche de progression** (year plan) per subject × class,
3. log what they actually teach week to week (lightweight *cahier de textes*),
4. see their **taux de couverture du programme** (planned vs covered) at a glance.

This is a complete, self-contained loop that is useful to a single teacher with zero school setup.

### Non-goals (explicitly out of v1)
- PDF / photo / Excel **import** of existing fiches — the *next* increment (assisted extraction →
  teacher confirms). v1 ships a deterministic builder + templates instead.
- **Marks, grading, report cards** (a later teacher increment).
- **Lesson-plan editor** (fiche de préparation) — later.
- The entire **school layer**: workspaces beyond personal, roles/councils, invitations, fees,
  fee-based access control, official report cards, school statistics — Phase 2+.
- **National syllabus library** — later; in v1 the teacher authors their own fiche.
- **AI** features.
- **True offline-first sync** — v1 is online LiveView, designed forgiving for flaky networks;
  offline-first is a noted later phase, not built now.

## 3. Personas (v1)

- **Independent secondary teacher**, Francophone or Anglophone, primarily on a smartphone, with
  intermittent connectivity. Teaches one or more subject×class combinations, possibly across more
  than one school (but in v1 all data is personal/private — schools are not modeled).

## 4. The loop (user flow)

1. **Onboard** — choose language (FR/EN) and subsystem (Francophone/Anglophone). Confirm the
   academic year (the app ships the **official current-year calendar pre-filled** — terms,
   sequences, week ranges, integration weeks — fully editable).
2. **Declare what you teach** — add one or more **TeachingContext**s: subject + level/class
   (+ série if upper cycle) + weekly hours. Self-declared; no school.
3. **Build the fiche** — for each TeachingContext, lay out the **ProgressionPlan**: modules →
   lessons distributed across the 6 sequences / weeks, each row with planned hours/sessions and a
   row type. Reuse via duplicate-a-plan or save-as-template.
4. **Teach & log** — quick capture: pick a planned row, mark **done / partial**, record hours, and
   optionally homework + a note. This is the lightweight *cahier de textes*.
5. **See status** — dashboard with the current week & sequence, **% covered** per subject and
   overall, "next up," and a behind/ahead indicator.

## 5. Data model

Ash resources, all scoped to the teacher's `PersonalWorkspace` (owner-only policies). Reuse the
existing `User` / `PersonalWorkspace` / `Scope` spine on the branch.

```
User (locale: fr|en) ── owns ──> PersonalWorkspace
│
├─ AcademicYear            name, subsystem (default), start_date, end_date, active
│    └─ Term (1–3)         label, order
│         └─ Sequence (1–6) label, order, start_date, end_date, integration_week? (bool)
│
├─ TeachingContext         subject_ref, level/class label, série? , subsystem, weekly_hours
│                          (self-declared; the "what I teach" unit)
│
├─ ProgressionPlan         belongs_to TeachingContext + AcademicYear; status (draft|active);
│                          title; derived coverage metrics
│    └─ ProgressionEntry   sequence_ref, week_no?, planned_date_range?,
│                          module (title), lesson_title,
│                          planned_hours (or sessions), entry_type,
│                          position (ordering),
│                          OPTIONAL CBA fields: famille_de_situations, categories_action,
│                                               competence_visee
│
├─ TeachingLogEntry        date, →ProgressionEntry? (nullable), content_taught, hours,
│   (cahier de textes)     status (done|partial), homework?, note?
│
└─ ProgressionTemplate     a copyable/shareable ProgressionPlan snapshot (v1: duplicate + save-as)
```

### Key field notes
- **`entry_type`** enum: `lesson | integration | evaluation | revision | correction | remediation
  | holiday`. (From [`docs/domain/03`](../../domain/03-teacher-documents.md).)
- **CBA fields are optional.** CBA adoption is uneven in practice
  ([`docs/domain/02`](../../domain/02-cba-pedagogy.md) §1); we are "CBA-ready," not "CBA-mandatory."
  CBA-keen teachers fill them; others aren't blocked.
- **Reference data** (subjects, levels/classes, séries, subsystems) is **seeded from
  `docs/domain/` but editable** — not frozen enums. Teachers can add a subject/class we missed.
- **Coverage is derived, not stored as truth:** a `ProgressionEntry` is *covered* when linked
  `TeachingLogEntry` hours meet its `planned_hours` (or it's explicitly marked done).
  `taux de couverture` = Σ covered hours ÷ Σ planned hours, rolled up per **sequence → term →
  year** and per **TeachingContext → overall**.

### Academic-year grid
- Ships with the **official current academic-year calendar** as a default (3 terms × 2 sequences,
  week ranges, integration weeks) — see [`docs/domain/01`](../../domain/01-education-system.md) §6.
- **Fully editable** and re-creatable per year (the calendar is re-issued annually by ministerial
  decision — never hard-coded).

## 6. Screens (mobile-first LiveView)

All wrapped in `<Layouts.app>`; DaisyUI/Tailwind; stable DOM IDs for LiveView tests; calm,
dense, operational style per [`docs/DESIGN.md`](../../DESIGN.md).

1. **Setup wizard** — language → subsystem → confirm/edit academic year → add first
   TeachingContext. Short, skippable-where-safe, returns the user to where they were headed.
2. **Home / dashboard** — current week + sequence banner; per-TeachingContext coverage KPI cards
   (% covered, ahead/behind); "next up" lessons; quick link to log today.
3. **Fiche builder** — per TeachingContext: a sequence-by-sequence editable list of
   ProgressionEntry rows. Add/edit/reorder rows; set module, lesson, hours, type; flag integration
   weeks; optional CBA fields behind a "CBA details" disclosure. Duplicate plan / save as template.
4. **Teach / log (quick capture)** — pick a planned entry (defaulting to current sequence),
   mark done/partial, enter hours, optional homework + note. Optimized for a few taps on a phone.
5. **Coverage view** — per TeachingContext and overall: % covered by sequence/term, ahead/behind,
   and the list of not-yet-covered planned entries.

## 7. Cross-cutting requirements

- **Bilingual:** every UI string and data label has FR + EN; locale stored on `User`, switchable.
  Teacher-entered content stays in the teacher's language.
- **Empty / setup states:** no route crashes when academic year or teaching context is missing;
  guide the user to the relevant setup step instead (per [`docs/DESIGN.md`](../../DESIGN.md)).
- **Privacy/policy:** all v1 data is private to the owning teacher's personal workspace; Ash
  policies authorize owner-only. No tenant fallback to arbitrary records.
- **Mobile + flaky network:** quick, forgiving interactions; preserve form state on validation
  error; avoid multi-step actions that lose work if a request drops.
- **Testability:** every critical flow testable via LiveView selectors against stable IDs.

## 8. Success criteria (definition of done for v1)

- A new teacher can go from sign-up to an **active fiche de progression** for at least one
  subject×class in a single sitting on a phone, in FR or EN.
- They can **log taught content** against planned entries and see an **accurate taux de couverture**
  per sequence, term, and year.
- They can **reuse** a plan (duplicate / save-as-template) to set up a second subject×class fast.
- No screen crashes on missing setup; both languages render without overflow at mobile widths.
- Core flows covered by LiveView tests.

## 9. Future phases (context, not v1 scope)

- **v1.1** — assisted **import** of existing fiches (PDF/photo/Excel → editable draft rows).
- **v1.2** — **marks & report cards** for the independent teacher (/20, sequences, averages).
- **v1.3** — **lesson-plan (fiche de préparation)** editor scaffolded from a progression entry.
- **Phase 2 — the school layer:** school workspaces, roles & councils
  ([`docs/domain/05`](../../domain/05-school-roles-and-fees.md)), invitations, official report
  cards & statistics ([`docs/domain/04`](../../domain/04-grading-and-report-cards.md)),
  fee-based access control. Teacher↔school is many-to-many; the personal workspace is the on-ramp.
- Later — national **syllabus library**, **offline-first** sync, **AI**-assisted remarks/scaffolding.
