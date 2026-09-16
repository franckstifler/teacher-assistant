# P2.6 — Trimester + annual bulletins

**Status:** Approved design
**Date:** 2026-07-06
**Builds on:** P2.3 (séquentiel bulletins & statistics), P2.5 (form-master scoped access)

## Purpose

Extend the séquence-only bulletins from P2.3 to the two aggregated periods a
Cameroonian school actually reports on: the **bulletin trimestriel** (the
official conseil-de-classe document, one per trimester) and the **moyenne
annuelle** (end-of-year). Users select a *period* — a séquence, a trimestre, or
the année — on the existing results and bulletin surfaces, and everything
recomputes for that window. No new access model: the P2.5 form-master scoping
carries over unchanged (access is per-class, independent of period).

## Methodology (authoritative — docs/domain/04-grading-and-report-cards.md)

A *period* is one of:
- `{:sequence, seq}` — one séquence (1–6).
- `{:trimester, term}` — one trimestre (1–3), which owns 2 séquences.
- `{:annual, year}` — the whole année (6 séquences).

Per **subject**, the period average is:
- Séquentiel: today's `Marks.subject_average` over that séquence's assessments (unchanged).
- Trimestriel: **mean of the term's séquence subject-averages that exist** (1 or 2).
- Annuel: **mean of the subject's séquence averages that exist across the year**
  (`Σ ÷ n`). This is the verbatim ministerial "moyenne annuelle = mean of the 6
  séquences", made tolerant of not-yet-graded séquences so in-progress years render.

Per **student**, the moyenne générale for any period = coefficient-weighted mean
over that period's subject averages (identical formula to P2.3):
`Σ(subject_avg × coef) / Σ(coef)` over subjects whose period average is non-nil.
A subject with no average in the period is excluded from **both** the numerator
and Σcoef (never counted as 0), exactly as in P2.3.

**Class-level**, over the period's aggregated per-student moyennes:
- Rank (ex-aequo via shared rank), effectif, graded_count, class_average,
  pass_rate, highest, lowest, by_sex split — same as P2.3.
- Distinctions: Félicitations ≥16 / Encouragements ≥14 / Tableau d'honneur ≥12,
  each gated on **all** of the student's graded subjects being ≥10, mutually
  exclusive (highest applicable). Same thresholds, uniform across all period types.

Partial-period tolerance: if a trimester has only one séquence graded, the
trimester average is that one value; annual means whatever séquence averages
exist. This lets the trimester/année options render mid-year.

## 1. Engine architecture

Refactor `TeacherAssistant.Academics.Bulletins` to separate *how a subject
average is obtained* from *how the class is aggregated and ranked*:

- Extract a shared `aggregate(students, subject_rows)` where each `subject_row`
  already carries `context_id`, `label`, `coefficient`, and a per-student
  `averages` map (`student_id => %Decimal{} | nil`), plus any component values
  for the breakdown. `aggregate` produces the existing return shape:
  `%{per_student, effectif, graded_count, class_average, pass_rate, highest,
  lowest, by_sex, distinctions}`, with `per_student[id]` holding `subjects`
  (each with `average`, `note_x_coef`, `class_min`, `class_max`, `subject_rank`,
  and — new — optional `components`), `total_points`, `total_coef`,
  `moyenne_generale`, `mention`, `rank`.
- `compile/2` (séquentiel) keeps computing subject averages from
  `assessments_by_id` + `marks` via `Marks.subject_average`, builds
  `subject_rows`, and calls `aggregate`. Behavior-preserving: the 6 existing
  engine tests must stay green untouched.
- New `compile_period/2` takes subjects whose per-student average is already the
  mean of séquence averages (with the component séquence/trimester averages
  attached), builds `subject_rows`, and calls the **same** `aggregate`. This
  guarantees séquentiel and périodique rank/mention arithmetic are identical and
  live in one place.

The `components` field on a subject row is a small map carrying the constituent
averages for the individual-bulletin breakdown, e.g. for a trimester
`%{sequences: [%{number: 1, average: d}, %{number: 2, average: d}]}` and for the
annual `%{trimesters: [%{position: 1, average: d}, ...]}`. It is `nil` for the
séquentiel path.

## 2. Data loading

`Academics.class_results_for_period(cg, period)`:
- `{:sequence, seq}` → delegates to today's `class_results/2` (unchanged path).
- `{:trimester, term}` → loads the term's séquences, computes per-séquence subject
  averages once per (subject, student), means the present ones per subject per
  student, attaches `components.sequences`, feeds `compile_period`.
- `{:annual, year}` → loads all séquences, computes per-séquence subject averages,
  means the present ones per subject per student for the subject average; attaches
  `components.trimesters` = each trimester's subject average (mean of that term's
  present séquences) for the annual breakdown; feeds `compile_period`.

Returns `nil` when the class has no teaching subjects (same contract as
`class_results/2`).

A small period-resolution helper `Academics.resolve_period(year, param)` maps the
URL param (`"seq:<id>"` / `"trim:<id>"` / `"annee"`) to a `period` tuple, or nil
if it does not resolve within the given year (used by every surface to reject
cross-year / bad ids).

## 3. UI

The results page (`results_live`) and bulletin page (`bulletin_live`) replace the
séquence `<select>` with a **period selector** — an `<select>` with optgroups:
"Séquences" (1–6), "Trimestres" (1–3), "Année". The selection is carried in the
URL as `period=seq:<id> | trim:<id> | annee` (replacing `seq=`).

- **Results table:** unchanged shape — one moyenne / rank / mention per student,
  period-agnostic (selection C). The stats strip, gender split, and distinction
  rolls recompute for the selected period.
- **Individual bulletin:** the per-subject table gains component columns
  (selection C):
  - trimester → `Séq 1 | Séq 2 | Moy. trim.` (+ existing Coef, Note×Coef, class range)
  - annual → `Trim 1 | Trim 2 | Trim 3 | Moy. ann.`
  - séquence → unchanged single Note/20 column.
- Form-master scoped access (P2.5) is untouched: mount/handlers still gate on
  `admin_or_form_master?` for the resolved class; the period only changes what is
  computed, never who may see it.

## 4. Print

Both print routes (`show` single, `class` whole-class) take `period=` instead of
`seq=`. `with_class/4` resolves the period via `resolve_period/2` (redirect to
`/school` if it does not resolve), and the cartouche header shows "Séquence N" /
"Trimestre N" / "Année scolaire" accordingly. Single and whole-class bulletins
render the same component-column breakdown as the on-screen bulletin. The
visa/décision block is unchanged — promotion/redouble decisions stay out of scope
(YAGNI); the "Décision" line remains blank for the head to fill.

## 5. Testing

- **Engine (pure):** `aggregate` extraction is behavior-preserving — the 6
  existing séquentiel tests stay green with no edits. New `compile_period` tests:
  trimester subject average = mean of two séquence averages; annual = mean of
  present séquence averages; partial period (one séquence graded) tolerated;
  a subject ungraded in the period excluded from Σcoef; rank + mention match a
  hand-computed multi-student case; component values attached correctly.
- **Loader:** `class_results_for_period/2` for each period kind; a partially-graded
  trimester; `nil` when no subjects; `resolve_period/2` accepts valid ids and
  rejects cross-year / malformed params.
- **LiveView:** period selector switches séquence→trimester→annual and the table
  recomputes; the individual bulletin shows component columns for trimester and
  annual and the single column for séquence; a form master of the class reaches a
  trimester bulletin (P2.5 regression).
- **Print:** trimester print shows the "Trimestre N" header and the breakdown
  columns; whole-class annual print includes every student with the annual
  columns.
- **i18n / gate:** gettext extract + non-empty FR/EN msgstrs for every new msgid
  ("Trimestre", "Année", "Moyenne trimestrielle", "Moyenne annuelle", "Période",
  component column headers, etc.); `mix precommit` green (note: the precommit
  alias flag is misspelled `--warning-as-errors`, so warnings do not gate — run
  the full suite and confirm it passes).

## Notes / risks

- The main risk is the `Bulletins` engine refactor touching reviewed P2.3
  arithmetic. Mitigation: extract `aggregate` behavior-preservingly and keep the 6
  existing engine tests unchanged as the regression net; the séquentiel path must
  produce byte-identical results before and after.
- URL param change from `seq=` to `period=` touches results_live, bulletin_live,
  and both print routes plus their links — update all call sites together; the
  bulletin links from the results table must pass the current period through.
- `resolve_period/2` is the single choke point that rejects cross-year and
  malformed period params, mirroring how the class is workspace-scoped — keep the
  redirects consistent with P2.5.
