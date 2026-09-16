# P2.3 — Official Bulletins & Statistics (Design)

**Date:** 2026-07-05
**Status:** Approved
**Depends on:** P2.2 school enrollment & shared classes (merged, `5ae03c3`)
**Feeds:** later increments (trimester/annual bulletins, conduct capture, promotion
decisions, form-master access, Anglophone engine, coefficient/threshold config)

## Goal

Produce the Francophone **séquentiel bulletin de notes** and the class-level
**Conseil-de-Classe statistics** for a school class: gather every subject's
per-séquence average across the class's teaching contexts, weight by each
subject's coefficient, and compute the moyenne générale, rank, mention, class
statistics, and distinction rolls — rendered on screen and printable to A4.

Decisions locked during brainstorming:

1. **Séquence period only** — one bulletin per séquence (relevé séquentiel).
   Trimester/annual bulletins are simple means over the same engine and are a
   deliberate follow-up, not in this increment.
2. **Coefficient on `TeachingContext`** — one new field (per subject × class),
   not a separate per-série reference table.
3. **Academic-only bulletin** — no conduct capture, no promotion decision. The
   printed form carries blank visa/decision/conduct lines for manual fill-in.
4. **Admin-only access** — Head / Vice-Principal, identical to P2.2's
   `Permissions.admin?`. Form-master-scoped access is deferred.
5. **Pure projection, nothing persisted** — a bulletin is computed live from
   marks + coefficients at render time, like `Marks.summarize`/`Coverage`.

## Section 1 — Data model

### TeachingContext (modified)

- Add `coefficient` — `:decimal`, `allow_nil?: false`, `default: Decimal.new(1)`,
  `public?: true`. Added to the `create` and `update` accept lists.
- Set by admins on the **class detail assignments panel** (P2.2 T9), alongside
  subject / teacher / weekly-hours.
- Additive migration; existing rows default to coefficient 1 (no backfill risk).

### No new resources

A class's subjects are already its `TeachingContext`s (school scope,
`class_group_id` set, `teacher_user_id` not nil). A séquence's marks already
hang off `Assessment` (which carries `weight` and `max_score`) via `Mark`. The
bulletin is a pure projection of `{students, per-subject assessments+marks,
coefficients}` at render time — nothing is persisted, so bulletins are always
live (edit a mark → the bulletin updates) with zero stale-snapshot risk. This
mirrors the existing `Academics.Marks` and `Academics.Coverage` modules.

### Missing-subject rule (confirmed default)

A subject with no marks yet for a student (nil per-subject average) is
**excluded from both the numerator (Σ note×coef) and the denominator (Σ coef)**
of that student's moyenne générale — the student is not penalized for an
ungraded/untaught subject — and the subject still appears on the bulletin with a
blank note. This matches how `Marks` already drops nil marks. Counting missing
as 0 is explicitly rejected (punitive, not the Cameroon norm).

## Section 2 — Aggregation engine

New pure module **`TeacherAssistant.Academics.Bulletins`** — no DB access,
mirroring `Marks`/`Coverage`. `Academics` (context layer) loads the data and
passes plain maps/lists; the module does the math and is unit-testable without
the database.

### Per student, one séquence — the bulletin projection

- **Per-subject rows**: subject label, coefficient, moyenne matière (/20 via the
  existing weighted per-subject formula), note×coef, rank-in-subject, and the
  class cote `[min–max]` for that subject.
- **Totals**: total des points = Σ(note×coef) over graded subjects; total des
  coefficients = Σ(coef) over graded subjects; **moyenne générale** = total
  points ÷ total coefs (nil when Σcoef = 0, guarded).
- **Mention**: via `Marks.mention/1` (bands 10 / 12 / 14 / 16 / 18, top =
  Excellent).
- **Rank-in-class** on the moyenne générale; ties share a rank (ex-aequo), same
  convention `Marks` uses.

### Per class — the Conseil-de-Classe roll-up

- Each student's moyenne générale + rank (sorted); class average (mean of
  moyennes générales), pass rate, plus forte / plus faible moyenne.
- Gender split (garçons / filles) on the class stats — required standard output
  per domain doc §6.
- **Distinction rolls** — Tableau d'honneur / Encouragements / Félicitations —
  with **hard-coded default thresholds 12 / 14 / 16**, each gated on *all
  subjects ≥ 10*. Domain doc §7 says thresholds are per-école configurable; the
  config UI is deferred. Conduct gating is out of scope (no conduct model yet).

### Shared subject-average path (no drift)

The per-subject weighted average currently lives in `Marks.student_average/2`.
Extract it into a shared private path so the bulletin and the existing
per-subject summary compute a subject average identically — one formula, no
risk of two implementations drifting. The existing `Marks` public API and its
tests stay green.

## Section 3 — Bulletin UI & print

### Class results view — `/school/classes/:id/results`

Admin-gated LiveView with a **séquence switcher** (same pattern as the existing
`MarksSummaryLive`). Shows:

- Class stats strip: class average, pass rate, highest/lowest, effectif with
  G/F split.
- Distinction rolls (the three lists).
- A **ranked student table**: moyenne générale, rank, mention — each row links
  to that student's bulletin.

This is the Head's "how did the class do this séquence" screen (Conseil de
Classe support).

### Individual bulletin — `/school/classes/:id/students/:enrollment_id/bulletin?seq=…`

Admin-gated on-screen render of the full academic bulletin: identity header,
per-subject table, totals, moyenne générale, rank/effectif, mention.

### Print — `/school/classes/:id/students/:enrollment_id/bulletin/print`

Dedicated print route reusing the `fiche_print_controller` A4 pattern:
bilingual national header (République du Cameroun – Paix – Travail – Patrie),
school cartouche (workspace name as établissement), academic table, totals, and
blank visa / decision / conduct lines for manual fill-in.

A **"Imprimer toute la classe"** action on the results view concatenates every
enrolled student's bulletin into one print job (one A4 page each), so a Head
prints a whole class at once.

### Navigation

The class detail page (`/school/classes/:id`) gains a **"Résultats & bulletins"**
link into the results view. No new top-level nav item.

All strings FR/EN via gettext.

## Section 4 — Edge cases, errors, testing

### Edge cases (handled in the pure engine)

- No séquences / no active year → results and bulletin pages show an empty
  state pointing to setup; never crash.
- Class with no coefficients set → all default to 1, moyenne générale becomes
  the unweighted mean; graceful.
- Student with zero graded subjects → moyenne générale nil (Σcoef = 0 guard);
  renders with a blank average and is **excluded from ranking and class stats**
  (not ranked 0), matching existing ungraded-student handling.
- Ex-aequo → tied moyennes share a rank.
- Cross-class / cross-school id in the URL → `fetch_owned_class_group` +
  enrollment-belongs-to-class checks reject it (redirect), same ownership
  discipline as P2.2.

### Testing

- **Engine unit tests (no DB)**: coefficient weighting; nil-subject exclusion;
  moyenne générale; rank + ex-aequo; class stats + gender split; distinction
  thresholds; degenerate all-nil / no-coefficient cases.
- **Context tests**: the loader assembles the right subjects/marks/coefficients
  for a class+séquence, workspace-scoped.
- **LiveView tests**: results view (stats, ranked table, séquence switch,
  admin-gate + forged-event rejection, cross-school redirect); individual
  bulletin render.
- **Print controller tests**: bulletin print returns 200 with school name,
  per-subject rows, moyenne générale; whole-class print includes every enrolled
  student.
- **Regression**: full suite stays green (we touch `Marks` to extract the shared
  subject-average path).

### Execution

Subagent-driven development on branch `feat/p2-3-bulletins`, ~8 tasks:
coefficient field → engine → loader/context API → results view → individual
bulletin → bulletin print → whole-class print → gettext. Fresh implementer +
task review per task, final whole-branch review, ledger at
`.superpowers/sdd/progress.md`.

## Out of scope (later increments)

- Trimester (bulletin trimestriel) and annual (moyenne annuelle) bulletins.
- Conduct/discipline capture (absences, retards, sanctions, note de conduite)
  and whether it enters the average.
- Promotion decision workflow (Admis / Redouble / Exclu) and the annual
  décision du conseil de classe.
- Form-master (professeur principal) assignment to a class and form-master-scoped
  bulletin access.
- Anglophone in-school grading engine (letters/remarks, /20-vs-/100) — a
  separate engine per domain doc §5.
- Per-école configuration of coefficients (per-série templates) and distinction
  thresholds; conduct model selection.
