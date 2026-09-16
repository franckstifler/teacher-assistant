# v1.2 — Marks & Mark Register (independent teacher, Francophone)

> Design spec. Written 2026-07-01. Part of Phase 1 (independent teacher).
> Follows v1 (progression & coverage) and v1.1 (assisted fiche import).
> Domain source of truth: [`docs/domain/04-grading-and-report-cards.md`](../../domain/04-grading-and-report-cards.md).

## 1. Purpose & scope

Give the **independent (solo) teacher** a per-subject **mark register** for the subjects they
actually teach: enter a class roster once, record /20 marks per *devoir/composition* per séquence,
and see deterministic per-séquence and annual statistics **for their own subject**.

A solo teacher owns only their own subject(s). The official multi-subject **Bulletin de Notes** is
inherently a school-level artifact (professeur principal aggregates every subject, ranks against the
whole class, adds conduct and promotion decisions) and belongs to **Phase 2 (school layer)**.

### In scope
- A **class roster** shared across the subjects a teacher teaches to that class.
- **Free-form assessments** per séquence (configurable count + weight — the domain doc marks
  "devoirs per séquence" as school-dependent, not national).
- **/20 marks**, Francophone subsystem.
- Deterministic per-séquence and running-annual **statistics** for the teacher's own subject,
  including garçons/filles disaggregation.
- Mobile-first, bilingual (FR/EN) LiveView flows in the "Tableau" theme.

### Non-goals (deferred)
- Multi-subject official **Bulletin de Notes**, cross-subject *moyenne générale*, rank across all
  subjects (→ Phase 2 school layer).
- **Printed / exported *relevé de notes*** (a later increment; v1.2 ships on-screen summaries only).
- **Conduct/discipline**, mentions-as-distinction-rolls gated on behavior, promotion decisions.
- **Anglophone engine** (separate /20-or-/100, letter+remark, pass 50% — the domain doc requires a
  *separate* engine; model is built so it slots in later without rework).
- Any **AI** assistance (deterministic first, per product principle).

## 2. Data model

New Ash resources in the `TeacherAssistant.Academics` domain, following the v1 resource pattern
(AshPostgres, uuid_v7 primary keys, ownership policies, timestamps).

**Convention:** closed value sets use a dedicated `Ash.Type.Enum` module, never a bare `:atom`
attribute. This spec introduces `Sex` (`[:m, :f]`) and reuses/introduces a `Subsystem`
(`[:francophone, :anglophone]`) enum; attributes reference these modules.

### `ClassGroup`
Owns a roster. A teacher enters students once per class and reuses across subjects.
- `belongs_to :personal_workspace` (required), `belongs_to :academic_year` (required)
- `label` :string, required (e.g. "3e M2")
- `level` :string, required
- `serie` :string, nullable
- `subsystem` — `Subsystem` enum; only `:francophone` is used in v1.2 (Anglophone lands later)
- Identity: unique on `(personal_workspace_id, academic_year_id, label)`

`TeachingContext` gains an **optional** `belongs_to :class_group` (nullable) so existing v1 contexts
keep working. Setup flow can link an existing class group or create one.

### `Student`
- `belongs_to :class_group` (required)
- `full_name` :string, required
- `sex` — `Sex` enum (`[:m, :f]`), required (garçons/filles statistics are a required output)
- `matricule` :string, nullable
- `repeater?` :boolean, default false
- Ordered by `full_name` for display.

### `Assessment`
A devoir / composition within one subject for one séquence.
- `belongs_to :teaching_context` (required), `belongs_to :sequence` (required)
- `label` :string, required (e.g. "Devoir 1", "Composition")
- `weight` :decimal, default 1
- `max_score` :decimal, default 20
- `given_on` :date, nullable

### `Mark`
One student's score on one assessment.
- `belongs_to :assessment` (required), `belongs_to :student` (required)
- `score` :decimal, nullable (null = absent / not yet entered)
- Constraint: `0 ≤ score ≤ assessment.max_score`
- Identity: unique on `(assessment_id, student_id)`

All resources are workspace-scoped via ownership policies consistent with v1 (no tenant
fallthrough). `Mark` and `Assessment` authorize through the owning `TeachingContext`'s workspace;
`Student` through its `ClassGroup`'s workspace.

## 3. Calculations — `TeacherAssistant.Academics.Marks`

A pure, deterministic module, **unit-tested before any UI** (TDD). No stored aggregates — all
statistics are computed on read.

- **Moyenne séquentielle** (per student, per séquence, this subject):
  `Σ(score × weight) / Σ(weight)` over the student's **non-null** marks in that séquence, each
  score normalized to /20 via its assessment's `max_score`. Returns `nil` if the student has no
  marks entered in the séquence.
- **Class average** = mean of students' séquence moyennes, excluding nils.
- **Pass rate** = % of graded students with moyenne ≥ 10 (Francophone pass = 10/20, hard-coded ✅).
- **Highest / lowest** moyenne in the class for the séquence.
- **Rank within subject** per student; ties share a rank (ex-aequo).
- **Garçons / filles split** applied to each of the above (class average, pass rate, counts).
- **Moyenne annuelle** = **unweighted** mean of the séquence moyennes that exist so far (running;
  equals the true "mean of 6 séquences" once all six are graded). Explicitly **not** the French
  weighted `(T1 + 2·T2 + 2·T3)/5` formula.
- **Mention** label for a given average, display-only, bands hard-coded per domain doc:
  Passable 10–11.99 · Assez Bien 12–13.99 · Bien 14–15.99 · Très Bien 16–17.99 · Excellent ≥18.

## 4. UI / LiveView flows

"Tableau" theme, bilingual FR/EN, mobile-first. Every critical flow uses stable DOM IDs for
LiveView selector tests, and guards missing prerequisites by guiding to setup rather than crashing.

- **Roster management** (under a `ClassGroup`): list / add / edit / remove students
  (full_name, sex, matricule, repeater?). If no class group exists, guide to create one.
- **Mark entry — primary flow** (from a `TeachingContext`): pick séquence → pick or create an
  assessment → a single scrollable list of the class's students with one score field per row →
  save transactionally. Leaving a field blank records absent (null). This matches the real
  "I just graded this devoir" workflow and is comfortable on a phone.
- **Séquence summary — payoff** (read-only): per-student moyenne séquentielle + mention, class
  average, pass rate, highest/lowest, and garçons/filles split. Reachable from a dashboard tile.

## 5. Testing

- **Unit (first, TDD)** for `Academics.Marks`: weighting, `max_score` normalization, null/absent
  handling, pass-rate boundary at exactly 10, ranking with ties, gender split, running annual mean
  (partial vs all-six séquences).
- **LiveView**: roster CRUD; assessment create; mark-entry round-trip with transactional save;
  summary statistics render correctly; setup-gate redirects when class/roster/assessment missing.

## 6. Quality bar (inherits v1)

- No route crash because class, roster, or assessment data is missing — guide to setup instead.
- Data is workspace-scoped; no tenant fallback through arbitrary records.
- Deterministic calculations are correct and tested before any future AI layer.
- Both languages render without overflow at mobile widths.
- Every critical flow is testable via LiveView selectors against stable DOM IDs.
