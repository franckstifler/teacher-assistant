# Mockups → code roadmap

**Source:** claude.ai/design project "Admin panel design proposal"
(`abc12b3e-a26c-41e5-a97c-f0a9be47fc8b`): `Écarts avec le code`, `Paramètres école`, `Espaces par rôle`,
`Enseignant`, `Proviseur`, `Onboarding`, `Landing`, `Admin Actuel`. The gap IDs (N01…, V01…) are the ones
listed in `Écarts avec le code`.

**Rule:** one increment = one spec section here, then one plan, one branch, and `mix precommit`. Each plan
starts by re-checking the "Existe" claims for its own gaps against `lib/`. Mockup values marked
"indicatives" (coefficients, fees, thresholds) are examples, not reference data.

## Order

| # | Increment | Gaps | Depends on | Size |
|---|---|---|---|---|
| D1 | Editable calendar and grade-entry milestones | S01, N01 (+ class council date) | — | S |
| D2a | Coefficients by level and série, bulletin groups | N08 | — | M |
| D2b | School evaluation rules (types, averages, rounding, absence, optional subjects) | N07 | D2a | M |
| D3 | Lock and trace marks | N04 → N02 → N03 | D1 (deadline), N04 before N03 | M×3 |
| E | Role-aware navigation and home | R01, R02 | authorization increment (done) | M |
| F | Censeur follow-up | N05, then N06 (P2) | D1, E | S (+M) |
| G | School life, day view | V02, V01, V03, then V04, V06 (P2) | E | S×3 |
| H | Pedagogy screens | P01, P02 (P2) | E | M |
| I | Report card cycle | N09, N13, N12, N11, N10 | D2a, D2b, D3 | S…L |
| J | Timetable and staff | S03, S02, T04, T01, T03, T02, T05 | — | S…L |
| K | Platform | R04, R05, S04, S06, R03 | E | S…L |
| — | Marketing site | `Landing` mockup (not in the gap list) | — | M |

Deferred by the gap list: P03, P04, S05.

## D1 — Editable calendar and grade-entry milestones (spec)

Mockup: `Paramètres école` → *Année & séquences*. This is a per-sequence table with start, end, grade-entry
deadline ("limite de saisie"), and a class-council date on the second sequence of each trimester. There is
also the rule "date limite = fin + 5 jours".

Existing code: `Sequence` has `start_date`/`end_date`, with a `sequences_dates_ordered_check` constraint.
`Term` has no dates. `Organization.build_default_calendar/2` generates six sequences, and
`SettingsLive` #annee lists them read-only with the text "modifiables prochainement".

Behaviour:
1. `Sequence.entry_deadline` (nullable date). `nil` means the default rule applies: `end_date + 5 days`
   (`Reference.entry_grace_days/0`). The loadable calculation `grade_entry_deadline` resolves it.
   A DB check keeps an explicit deadline on or after `end_date`.
2. `Term.class_council_date` (nullable date).
3. `Organization.update_calendar(scope, year, params)` saves every sequence and term of a year atomically
   (`Ash.transact`), after `CalendarRules.validate/3` accepts the whole proposed calendar:
   - start and end required and parseable;
   - `end >= start`;
   - every sequence inside `[year.start_date, year.end_date]`;
   - sequence n+1 starts after sequence n ends (gaps, i.e. holidays, are allowed);
   - an explicit deadline is `>= end`;
   - a council date is `>=` the end of its trimester's last sequence.
   If any rule fails, nothing is written, and errors are reported per row and per field.
4. Only calendar managers (admin axis) may save. Everyone else sees the calendar read-only, including the
   effective deadline and council date.
5. The teacher's marks page shows the effective grade-entry deadline of the selected sequence.

Out of scope: locking (N02, D3), a school-level setting for the grace days (it arrives with the D3 lock
toggles), holidays (S02).

## D2a — Coefficients by level and série, bulletin groups (spec)

Mockup: `Paramètres école` → *Matières & coefficients*. A grid subject × level (6e…Tle) with a série switch for
the 2nd cycle; an empty cell means "not taught at this level". Each subject belongs to a bulletin group
(G1 lettres, G2 sciences, G3 autres). Toggles: "Autoriser un coefficient propre à une classe", optional
subjects. The mockup's coefficient values are *indicatives* and are not seeded as reference data.

**Authority rule (applies to D2a and D2b):** the mockups decide what exists and how it looks;
`docs/domain/` decides the defaults. Where they disagree, the default follows the ministry and the mockup's
choice becomes an option.

Existing code: `Subject` has `default_coefficient`, `category` (unused in any computation) and `position`.
`TeachingContext` stores the subject as a name string and a non-null `coefficient` copied from
`Subject.default_coefficient` at assignment; `Curriculum.set_assignment_coefficient/3` edits it per class.
`Assessment.class_subjects/3` is the only place bulletins read the coefficient; trimester and annual results
reuse it. Bulletin rows come out in database order, with no grouping.

Behaviour:
1. **`SubjectCoefficient`** (Curriculum domain, tenant-scoped): `subject_id` (required, deleted with its
   subject), `subsystem`, `level`, `serie` (nullable, blank for 1st-cycle levels), `coefficient` (decimal > 0).
   Unique on (subject, subsystem, level, série) with a blank série as its own value. A missing row is an
   empty cell: the subject is not taught at that level. Read: members; write: admin axis.
2. **`Subject.category` is replaced by `bulletin_group`** (`:g1_lettres | :g2_sciences | :g3_autres`,
   default `:g3_autres`). `position` orders
   subjects within a group. `default_coefficient` only pre-fills a cell when it is switched on.
   Creating a subject switches on its cell at every level of the school's subsystem(s), valued at
   `default_coefficient` (1st-cycle levels with a blank série; streamed 2nd-cycle levels once per série used
   by the active year's classes, plus blank). The admin then empties the cells where it is not taught, so a
   new subject is assignable at once.
3. **`TeachingContext.subject_id`** (required), set at assignment from the chosen `Subject`. The `subject`
   string stays as the display label.
   `coefficient` becomes nullable and means the class override.
4. **Calculations on `TeachingContext`:** relationship `grid_coefficient` = the cell for the context's
   subject, subsystem and level (copied from its class at assignment; no path edits a class's level or
   série), preferring the context's série cell and falling back to the level's blank-série cell. A blank-série
   cell of a streamed level therefore applies to every série without a cell of its own.
   `effective_coefficient = coefficient || grid_coefficient.coefficient || subject.default_coefficient`;
   `taught_here? = grid_coefficient exists`.
5. **School profile settings:** `class_coefficients_allowed?` (default true) and
   `bulletin_group_subtotals?` (default false).
6. **Grid editing** on its own Settings page, `/school/settings/coefficients`, linked from the subjects block: rows are active subjects grouped G1→G3 then
   by position, each with a group selector; columns are the school subsystem's levels (a subsystem switch
   when the school has classes in both); streamed 2nd-cycle levels are edited per série, the switch listing
   the séries used by the active year's classes; the default view edits the blank-série ("toutes séries")
   cells, a série view edits that série's cells and shows the inherited value when empty. A cell overridden
   in at least one class gets the amber border; the footer shows the total per column.
   `Curriculum.update_coefficient_grid(scope, params)` parses the whole form, validates it with a pure
   `CoefficientRules` module (positive decimal, `,` accepted; a cell cannot be cleared while classes use it,
   the error naming them; valid group), then writes every cell and group change in one `Ash.transact`.
   Errors are per cell; if any rule fails, nothing is written. A forbidden row rolls back every write.
7. **Toggles:** turning class coefficients off is refused while overrides exist ("N classes ont un
   coefficient propre : réinitialisez-les d'abord", with the list); overrides are never silently ignored or
   deleted.
8. **Class page:** the assignment form offers only subjects taught at the class's level and série. Each
   subject shows its effective coefficient; with overrides allowed an admin edits it (sets the override,
   amber, "modèle : n") or resets it ("Revenir au modèle"); otherwise it is read-only. An assignment whose
   cell is empty (the class's level or série changed after assignment) shows "Non enseignée à ce niveau
   selon la grille" and falls back to the subject default.
9. **Bulletins:** `class_subjects/3` uses `effective_coefficient`, `bulletin_group` and `position`.
   `Bulletins.aggregate/2` sorts rows by group, position, label, and returns per-student group subtotals
   (points, coefficients, group average over graded subjects). Moyenne générale, ranks, distinctions and
   statistics are unchanged. `BulletinLive` and the print template show rows under group headings (empty
   groups hidden) and, when `bulletin_group_subtotals?` is on, a "Total groupe" row per group. The
   coefficient column shows the effective coefficient.
10. **No data backfill.** No real school data exists yet (dev has no teaching contexts, no production),
    so the schema changes are generated with `mix ash.codegen` only: `subject_id` is required from the
    start, and dev/test databases are reset. A school starts with an empty grid and fills it in Settings.

Review focus: an unparseable or non-positive coefficient (per-cell error, nothing written); clearing a used
cell; a crafted save from a teacher (`Forbidden`, full rollback); turning overrides off while some exist; a
class whose série has no grid column (fallback, never a crash); a class assignment made before any grid
cell exists (falls back to the subject default, flagged).

Out of scope (D2b): optional subjects and what a missing mark means (today a subject with no marks is left
out of the coefficient total, which already covers an optional subject nobody grades); school assessment
types; trimester/annual rules; rounding; tied-rank toggle.
