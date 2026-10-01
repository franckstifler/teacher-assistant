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
| D2b-1 | Averaging rules: trimester/annual rule, rounding, tied ranks | N07 (part) | D2a | S |
| D2b-2 | Marks and absence: assessment types, default max, absent marker and rule, optional subjects | N07 (rest) | D2b-1 | M |
| D3 | Lock and trace marks | N04 → N02 → N03 | D1 (deadline), N04 before N03 | M×3 |
| E | Role-aware navigation and home | R01, R02 | authorization increment (done) | M |
| F | Censeur follow-up (N05 done) | N05, then N06 (P2) | D1, E | S (+M) |
| G | School life, day view | V02, V01, V03, then V04, V06 (P2) | E | S×3 |
| H | Pedagogy screens — **on hold** (2026-09-30: needs progression plans, which no screen creates since the teacher-personal pause) | P01, P02 (P2) | E | M |
| I | Report card cycle, split I1 N09 → I2 N13 → I3 N11 → I4 N10 → I5 N12 (see §I) | N09, N13, N11, N10, N12 | D2a, D2b-1, D2b-2, D3 | S…L |
| J | Timetable and staff | S03, S02, T04, T01, T03, T02, T05 | — | S…L |
| K | Platform | R04, R05, S04, S06, R03 | E | S…L |
| — | Marketing site | `Landing` mockup (not in the gap list) | — | M |
| L | School life, rest (see §L) | V05, L1–L3 | G | M |
| M | School registers and new year (see §M) | M1–M4 | — | M…L |
| V | Visual checks still owed (see §V) | — | — | S each |

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

## D2b-1 — Averaging rules: trimester/annual rule, rounding, tied ranks (spec)

Mockup: `Paramètres école` → *Évaluations & moyennes*, panel **Moyennes** (rows "Moyenne trimestrielle",
"Moyenne annuelle", "Arrondi", "Rang ex æquo"). The panel's other rows (note maximale, élève absent) and the
assessment-types panel are D2b-2.

Existing code: `Marks.subject_average/2` and `Bulletins.aggregate/2` compute unrounded averages; a trimester
is the mean of the séquences that have marks, the annual average the mean of the 6 séquences
(`Assessment.period_result/4`); ranks always share ties; `BulletinLive`/print show 2 decimals.

Behaviour:
1. **`SchoolProfile` settings** (per school; changing one also recomputes past years until increment I
   freezes issued bulletins): `trimester_average_rule` `:mean_of_sequences | :second_sequence_double`
   (default `:mean_of_sequences`); `annual_average_rule` `:mean_of_sequences | :mean_of_trimesters`
   (default `:mean_of_sequences`, the ministerial rule); `average_rounding` `:hundredth | :tenth | :quarter`
   (default `:hundredth`); `shared_ranks?` (default true). Each enum is an `Ash.Type.Enum`.
2. **`GradingRules`**: a pure struct built from the profile (`Assessment.grading_rules/1`) and passed to
   `Marks` and `Bulletins` as an optional last argument (absent = today's behaviour).
3. **Rounding, at every stage** (half-up; `:quarter` = nearest 0.25): a subject's séquence average is
   rounded; note×coef uses the rounded value; the moyenne générale is Σ(rounded note × coef) ÷ Σcoef, then
   rounded. Group subtotals and class statistics are computed from those rounded figures, so a printed
   bulletin adds up by hand. Display stays at 2 decimals.
4. **Period rules**, per subject, over its rounded séquence averages, then rounded: `:second_sequence_double`
   = (S1 + 2·S2) ÷ 3, a missing séquence skipped with its weight; `:mean_of_trimesters` = mean of the
   subject's trimester averages (each by the trimester rule), missing trimesters skipped. The annual
   bulletin's per-trimester breakdown uses the trimester rule.
5. **Ranks** (class and per subject) are on the rounded average. With `shared_ranks?` off, ties are broken by
   the unrounded average (computed from rounded subject averages, before the final rounding), then by student
   name; students passed to `Marks`/`Bulletins` therefore carry a `name`.
6. **`Marks.summarize`** (teacher per-subject summary) applies the same rounding and rank rule.
7. **Page** `/school/settings/evaluations` ("Évaluations & moyennes"), linked from Settings, for those who
   may edit the school profile: pill buttons per rule and a tied-ranks toggle, saved on click with a flash;
   the official default is marked "règle officielle". `Assessment.update_grading_rules(scope, params)` maps
   string values against the allowed options (no `String.to_atom`), returns `{:error, :invalid_rule}` without
   writing on an unknown value, and relies on the profile update policy (a teacher gets `Forbidden`).

Review focus: a crafted event with an unknown value; a teacher's event; the ×2 rule with one séquence
unmarked; the trimesters rule with a whole trimester missing; ties created only by rounding with shared ranks
off.

Out of scope (D2b-2): assessment types and default weights, the default maximum mark, the absent marker and
absent rule, optional subjects.

## D2b-2 — Marks and absence: assessment types, default max, absent marker and rule, optional subjects (spec)

Mockup: `Paramètres école` → *Évaluations & moyennes* (panel "Types d'évaluation et poids par défaut"; rows
"Note maximale", "Élève absent à une évaluation") and *Matières & coefficients* ("Matières optionnelles").

Existing code: a teacher creates an assessment by label only (weight 1, max 20, no UI for either). `Mark` has
only a nullable `score`; the marks page writes `nil` for every blank ("Blank = absent"), and `nil` is left out
of averages, so "absent", "not entered" and "does not take the subject" are indistinguishable. Every student of
a class takes every subject assigned to it.

**Default decided with the user (domain doc silent):** an unjustified absence from an assessment counts as 0
(common Cameroon practice), not the mockup's "Non noté".

Behaviour:
1. **`Mark.status`** (`:graded | :absent | :excused`, default `:graded`); `score` is required when graded and
   nil otherwise (check constraint). A blank field means *no mark row* ("not entered"): saving a blank deletes
   an existing mark. The marks page accepts a number, `abs`/`a` (absent, unjustified), `abj` (excused,
   justified) or blank; anything else is rejected and nothing in the batch is saved. Fields show `abs`/`abj`;
   the hint reads "Vide = non saisi · abs = absent · abj = absence justifiée".
2. **`SchoolProfile.absence_rule`** `:zero | :excluded | :makeup` (default `:zero`) and
   **`SchoolProfile.default_max_score`** (default 20, > 0). `GradingRules` gains `absence`.
3. **Computation** (`Marks.subject_average`): graded marks count; `:absent` counts as 0 under `:zero`, is left
   out under `:excluded` and `:makeup`; `:excused` is always left out. Under `:makeup`, both absent and excused
   marks flag the student's subject average `makeup_pending` ("Rattrapage attendu") until the teacher replaces
   the marker with the make-up score on the same assessment.
4. **`AssessmentType`** (school catalog, admin-edited: `name`, `default_weight` > 0, `position`), seeded at
   school creation with Interrogation écrite 0.5, Devoir surveillé 1, Travaux pratiques 0.5.
   `Assessment.assessment_type_id` (nullable). The teacher picks a type when creating an assessment: the label
   is pre-filled ("Devoir surveillé 2"), the max score defaults to `default_max_score`, and the type's weight is
   **copied** onto the assessment (changing a type later affects only new assessments). A type used by
   assessments cannot be deleted, only renamed or re-weighted. Combined-course assessments get the same fields.
5. **Optional subjects:** `Subject.optional?`, set on the coefficients grid ("Facultative"; switching it off is
   refused while exemptions exist, naming the classes). `SubjectExemption` (teaching context × student) records
   who does **not** take an optional subject, so a later-enrolled student takes every subject by default;
   exemptions are refused on non-optional subjects and for students outside the context's class. The class page
   shows, per optional subject, an "Élèves concernés (n/N)" checklist (class managers and admins). An exempted
   student is not listed on that subject's marks page, has no bulletin row for it, and is not counted in its
   class statistics. This replaces the mockup's school-wide "Matières optionnelles" toggle.
6. **Évaluations & moyennes page** completes the mockup: the types panel (with its example line), "Note
   maximale", and the absence rule as pills (Zéro · pratique courante / Non noté / Rattrapage obligatoire).
7. **Bulletin, results, print:** a subject average with a pending make-up shows "R" with the legend
   "R : rattrapage attendu"; the class results page shows the count of pending make-ups. Marks pages list
   pending make-ups under the `:makeup` rule.

Review focus: a crafted mark value ("abx") rejects the whole batch; an exemption on a non-optional subject or
for a student from another class; a type weight or max score ≤ 0; a teacher saving types or rules; switching
the rule from `:zero` to `:makeup` leaves no stale zeros (the computation is live).

Out of scope: medical exemption from a non-optional subject (e.g. EPS) — possible later by marking the subject
optional; linking `abs`/`abj` to the attendance register (attendance justification stays separate).

## E — Role-aware navigation and home (spec)

Mockup: `Espaces par rôle` ("Voir en tant que" Enseignant / Censeur / Surveillant général / Animateur
pédagogique) and `Proviseur`. Gaps: **R01** navigation adapted to each role; **R02** "Choix Censorat /
Enseignant en haut du menu, sans changer d'école". Only the Enseignant space could be read from the mockup
(home "Ma journée · appel"; menu Aujourd'hui / Enseignement / Démarches); the other spaces were drafted from
the existing screens and the roles' axes, and approved as defaults by the user, to be revisited.

Existing code: one "School" menu for everyone (Dashboard, Mes cours, Classes, Mon emploi du temps; Members
for the head, Settings for admins), gated by two capabilities; `/school` sends "plain teachers" to Mes cours.
`Scope.current_roles` holds the member's roles (`SchoolRole`: head, vice_principal, discipline_master, bursar,
hod, teacher, guidance_counsellor, librarian). The Members page already renders read-only for non-heads.

**Scope rule:** E changes what each person sees in the menu and where they land — never permissions. Every
screen keeps its own policy checks; a link hidden from a menu stays forbidden if typed directly. Menus link
only to screens that exist; later increments add their screens to the right space.

Behaviour:
1. **`TeacherAssistantWeb.Spaces`** (pure): each space is data — `key`, label, home path, menu sections of
   `{label, icon, path}`. `spaces_for(scope)` returns the member's spaces in priority order from
   `current_roles` and whether they have teaching assignments:
   - **Proviseur** (head) — home Tableau de bord; Pilotage: Tableau de bord, Classes, Membres; Paramètres:
     Établissement & année, Matières & coefficients, Évaluations & moyennes, Périodes.
   - **Censeur** (vice_principal) — home Tableau de bord; Suivi pédagogique: Tableau de bord, Classes,
     Membres (read-only); Paramètres: Établissement & année, Matières & coefficients, Évaluations & moyennes.
   - **Surveillant général** (discipline_master) — home Classes; Vie scolaire: Classes.
   - **Intendant** (bursar) — home Classes; Intendance: Classes.
   - **Enseignant** (anyone with teaching assignments) — home Mes cours; Enseignement: Mes cours, Mon emploi
     du temps. The per-course menu (Liste, Notes, Résultats) stays.
   - **École** (fallback: a member with none of the above, e.g. hod/counsellor/librarian who do not teach) —
     home Classes; Classes, Mon emploi du temps.
   Priority (and default): Proviseur > Censeur > Surveillant général > Intendant > Enseignant > École.
2. **Current space (R02)** is kept in the session. `GET /school/space/:key` stores it only when it is one of
   the member's spaces (otherwise ignored) and redirects to its home. An `:assign_space` on_mount resolves
   the current space; a missing or no-longer-allowed stored space falls back to the highest one.
3. **Layout**: the school menu is rendered from the current space's sections. A member with more than one
   space sees a switcher at the top of the menu (e.g. "Censeur | Enseignant"); the school switcher stays.
4. **Home**: `/school` sends each member to their current space's home; Proviseur and Censeur land on the
   dashboard itself. This replaces the "plain teacher → Mes cours" special case.

Review focus: a forged `/school/space/<key>` for a space the member does not have; a stored space whose role
was since removed; a member with no role-specific space and no teaching (École); a hidden screen typed
directly stays forbidden; the per-course menu still appears inside a course.

Out of scope: new screens (Ma journée · appel → G; censeur follow-up → F; cahier de textes, coverage → H;
corrections de notes, signaler une absence → D3/J; animateur pédagogique observations → J).


## D3 — Lock and trace marks (spec)

Status: implemented 2026-09-30 (branch `d3-lock-trace-marks`, plan
`docs/superpowers/plans/2026-09-30-d3-lock-and-trace-marks.md`).

Mockup: `Espaces par rôle`: Enseignant → Saisie des notes (column "Interro 1 · verrouillée") and Démarches →
Corrections de notes; Censeur → Corrections de notes (filters En attente / Traitées / Journal). Gaps, in build
order: **N04** audit log, **N02** lock after the deadline, **N03** correction requests.

Existing code: every mark write goes through `Mark` (`:upsert_all`, plus default create/update/destroy);
`Assessment` belongs to a `Sequence`; `Sequence.grade_entry_deadline` = `entry_deadline` or
`end_date + Reference.entry_grace_days/0` (fixed 5). A mark changes without any trace.

User decisions (2026-09-30): no "reopen a course" in D3 (deferred); after the lock nobody edits the grid
directly, admins included — only an approved correction changes a locked mark; one school setting, the grace
days N in "fin + N jours" (default 5), locking always on; the teacher learns the decision in the app only
(status + menu badge), no e-mail.

### D3a — Marks journal (N04)

1. A `MarkEvent` row is written in the same transaction as every mark change: author (user, or none for the
   system), time, action (`saisie`, `correction_demandee`, `correction_approuvee`, `correction_refusee`),
   assessment, student, value before, value after (score or `abs`/`abj`/blank), and the correction request
   when there is one. A save that changes nothing writes nothing.
2. The journal cannot be edited or deleted through any action.
3. Readable by admins (Censeur/Proviseur); the Censeur's "Journal" tab lists it newest first, grouped per save
   for display ("Devoir 1 · 4e B · 7 notes"), columns Horodatage / Auteur / Action / Détail.
4. The lock itself is computed (point 5), so "Verrouillage" is shown as a derived line per sequence at its
   deadline, not stored.

### D3b — Lock after the deadline (N02)

5. An assessment is locked when today (school's local date) is after its sequence's `grade_entry_deadline`.
   `Mark` refuses create, update, destroy and `:upsert_all` on a locked assessment for every actor (policy or
   validation in the resource, not only in the UI). Assessments of a locked sequence cannot be created,
   edited or deleted either.
6. The marks page shows locked columns read-only, labelled "verrouillée", with a link to "Nouvelle demande".
7. `SchoolProfile` gets `entry_grace_days` (integer, 0–30, default 5), edited on Paramètres → Évaluations;
   `grade_entry_deadline` uses it instead of the fixed `Reference` value.

### D3c — Correction requests (N03)

8. `MarkCorrection`: assessment, student, requested value, current value at request time, motive
   (`Erreur de saisie`, `Copie mal corrigée`, `Réclamation de l'élève`, `Note de rattrapage` — an enum),
   requester, status `pending | approved | refused`, decider, decided at. Only for a locked assessment; only
   its course's teacher may request; one pending request per mark.
9. Teacher, Démarches → Corrections de notes: list of their requests (Date, Élève, Classe, Avant → après,
   Statut) and a "Nouvelle demande" form (classe, élève, nouvelle note 0–20 or abs/abj, motif) —
   "Envoyer au censeur". Menu badge = requests decided since last visit.
10. Censeur (admin axis), Corrections de notes: En attente / Traitées lists, a detail with note actuelle,
    note demandée, motif, the student's resulting sequence average; "Approuver la correction" / "Refuser".
    Approving writes the mark (bypassing the lock, only through this action) and journals it; if the mark
    changed since the request, approval is refused and the request must be redone. Menu badge = pending count.
11. Both spaces get the "Corrections de notes" item (Enseignant: Démarches; Censeur/Proviseur: Paramètres or a
    new Suivi section).

Out of scope: reopening a course, e-mail/SMS notification (N06/R03), a lock on/off switch, bulletin
publication (N13).

### D3 — deferred minors (final review, 2026-09-30)

To pick up later; none blocks use.

- [ ] Lock fails open: `Mark.AssessmentOpen` / `Assessment.SequenceOpen` treat any read error as
  "open". Today every such error is NotFound, but a future read-policy tightening would silently
  disable the lock. Return `:ok` only for NotFound, refuse otherwise.
- [ ] Test clock: `Reference.today/0` reads `:school_clock_now` at runtime in prod code. Restrict it to
  the test build (`compile_env`) or warn when set outside test.
- [ ] Marks page left open past the deadline: `@locked?` is computed only at mount / séquence switch,
  so the save shows a generic error instead of "Séquence verrouillée".
- [ ] Locked banner "Nouvelle demande" link: shown to admins, who cannot request; on a combined course
  it passes only the first class's assessment, so other classes' students are not offered.
- [ ] `MarkCorrection.Request` does not check the student is enrolled in the assessment's class (a
  crafted request, once approved, creates a mark for a non-enrolled student of the school).
- [ ] Journal: add indexes `mark_events (workspace_id, inserted_at)` and `(mark_correction_id)`; the
  200-row limit can split a save's batch (wrong "N notes"); a combined save is labelled with the
  first assessment only.
- [ ] Menu badge on `/school/corrections` shows the pre-visit count until the next navigation
  (computed in `on_mount` before the page marks decisions seen).
- [ ] Correction form reloads the class's students on every change event (cache by assessment).
- [ ] Error handling: "stale" is detected by message substring (`CorrectionReviewLive.decide`); the
  teacher's form shows one message for "not locked" / "unchanged" / "already pending".
- [ ] `MarkCorrection.Decide` dereferences `context.actor.id`: an actor-less internal call would crash.
- [ ] Gettext: ~150 pre-existing empty EN `msgstr` entries (not D3) remain untranslated.

## F — Censeur follow-up: sequence entry tracking (spec)

Status: N05 implemented 2026-09-30 (branch `f-sequence-tracking`, plan
`docs/superpowers/plans/2026-09-30-f-sequence-entry-tracking.md`); N06 deferred. Visual check against the
mockup done 2026-10-01 (branch `visual-f-g-i1`); the S1…S6 tabs are kept although the mockup has none.

Mockup: `Espaces par rôle` → Censeur → "Suivi des séquences" (excerpt with layout, palette and data logic
saved in `docs/superpowers/mockups/f-censeur-suivi-sequences.html`). Gap: **N05**. N06 (reminders) deferred.

User decisions (2026-09-30): the "À relancer" list is shown as information, without "Relancer" buttons
(N06 later); the grid is the **Censeur's** home, the Proviseur keeps the dashboard and gets the grid as a
menu item; the screen **matches the mockup layout** (KPI tiles, sequence tabs, legend, grid, side panel).

1. Page `/school/sequences`, admin axis only (Censeur, Proviseur); others are redirected to `/school`.
2. Sequence tabs S1…S6 of the current year; default = the sequence whose dates contain today, else the last
   one that has started, else S1. `?seq=<id>` selects.
3. Grid rows = the year's classes; columns = the school's subjects taught in at least one class; a cell =
   one course (teaching context). No course → dashed empty cell ("Non enseignée").
4. Cell % = marks entered ÷ (students taking the subject × the course's assessments in that sequence),
   rounded down so 100 % means complete. Students taking = the class's active enrollments minus that
   course's subject exemptions. A mark row of any status (graded, abs, abj) counts as entered; a blank does
   not. A course with no assessment in the sequence is 0 % ("Rien saisi"). Colors: 100 % primary, 0 % error,
   otherwise amber, as in the mockup.
5. Selecting a cell shows the side panel: "Classe · Matière", teacher, "Notes saisies x / y",
   "Évaluations" (names), "Dernière saisie" (date of the latest mark change, "—" if none).
6. KPI tiles: Saisie globale (mean of course %, "toutes classes, toutes disciplines"), Classes complètes
   (classes whose every course is 100 %, "prêtes pour le conseil"), Enseignants à relancer (teachers with at
   least one 0 % course, "aucune note saisie"), Conseils de classe (the sequence's term `class_council_date`,
   "—" if unset).
7. "À relancer" panel: one line per late teacher, "Matière · classes · rien saisi". No buttons.
8. The data is computed with a fixed number of queries per page load, whatever the number of classes
   (no per-course query — see R05).
9. Spaces: Censeur home = `/school/sequences`, first item "Suivi des séquences" in its menu; Proviseur gets
   the same item; `/school` no longer sends the Censeur to the dashboard.

Out of scope: sending reminders and their log (N06), per-teacher view, export.

## G — School life, day view (spec)

Status: spec approved 2026-09-30, implemented 2026-09-30. Visual check done 2026-10-01 (branch
`visual-f-g-i1`): Ma journée now shows the selected slot's roll call beside the list, as in the mockup.

Mockup: `Espaces par rôle` → Enseignant → "Ma journée · appel", Surveillant général → "Aujourd'hui" and
"Absences" (excerpt with markup, palette, sample data and data logic saved in
`docs/superpowers/mockups/g-school-life-day-view.html`). Gaps: **V02, V01, V03, V04, V06**.

User decisions (2026-09-30): all five gaps in one increment; the SG gets **two screens** ("Aujourd'hui" home
and "Absences"); "Ma journée" is the teacher's **home** and also lists **this week's missed roll calls**.
Design choices: a roll call is "done" when attendance entries exist for (class, period, date) — computed,
no roll-call session resource; missed roll calls are information only, no "Relancer" button (reminders
come with notifications, N06/R03, as in F); V04 uses a fixed threshold, no settings screen.

### Data (V02, V06)

1. `AttendanceEntry` gains `justification_reason` — an `Ash.Type.Enum`
   `:maladie | :famille | :convocation | :autre` (FR "Maladie", "Raison familiale", "Convocation",
   "Autre motif") — plus `justified_by_user_id` and `justified_at` (utc datetime). Justifying requires a
   reason; the note stays optional. Unjustifying clears reason, author and time. Entries justified before
   this change have no reason and read "Motif non précisé".
2. `Attendance.justify_day/…` (and the existing per-class register form) take the reason; same authorization
   as today (conduct axis).
3. `SanctionEntry` gains `parents_notified_on` (date) and `parents_notified_by_user_id`, set by a new update
   action `:mark_parents_notified` (conduct axis; sets today's school date and the actor). No "un-notify".
4. Migrations generated with `mix ash.codegen --dev`.

### Computation

5. `Reference.now/1` gives the school-local time (WAT, UTC+1) with the same frozen-clock hook as
   `Reference.today/1`; all "today", "in progress" and "past" decisions use it.
6. A plain module (like `EntryProgress`) computes, with a fixed number of queries per call:
   - `school_day(scope, date, now)`: rows = classes having at least one slot on that weekday, columns = the
     school's lesson periods. A cell is `nil` (no slot) or has a status:
     `:done` (entries exist for that class, period and date; carries the number of `:absent` entries),
     `:in_progress` (no entries, start ≤ now < end), `:missed` (no entries, end ≤ now), `:upcoming`
     (start > now). A done cell stays done whatever the time. Combined-course slots count per class.
     Also returns the list of missed roll calls (class, period, teacher, subject).
   - `teacher_day(scope, user, date, now)`: the user's slots that weekday, sorted by period, with the same
     statuses, class, subject and absent count.
   - `teacher_missed_this_week(scope, user, today, now)`: the user's slots from Monday of this week up to
     now (today's ended periods excluded — they appear in `teacher_day`), no entries, never before the
     active year's start date.
7. No holiday data exists yet (S02): a weekday with no slot gives an empty day ("Pas de cours aujourd'hui").
8. Repeated absences (V04): a student is flagged when they have **3 or more distinct days** with an
   unjustified `:absent` entry in the current sequence. The threshold is a module constant.

### Screens

9. **Enseignant → "Ma journée"** (`/school/today`), first menu item and the enseignant space's home when the
   person teaches ("Mes cours" stays in the menu). Today's slots: period code and time, class, subject,
   status tag ("Fait · n abs.", "En cours", "Non fait", "À venir"); every slot except upcoming ones links
   to the existing roll call `/school/classes/:id/attendance/:period_id`. Below: "Appels manquants cette
   semaine", one line per missed slot linking to the roll call with `?date=`. Empty day → "Pas de cours
   aujourd'hui". Non-teachers are redirected to their space home.
10. **Surveillant → "Aujourd'hui"** (`/school/day`), the surveillant space's home and first menu item:
    - grid classes × lesson periods, legend Fait / Non fait / En cours; done cells show the absent count,
      missed cells "—", in-progress "…", upcoming "·", no slot blank; hovering/title gives the detail;
    - "Absences à justifier": today's students with unjustified absences (name, class, periods and hours);
      "Justifier" opens the four reasons, one tap justifies the student's day; justified rows show
      "Justifiée · motif"; students flagged by V04 carry an "Absences répétées" badge and come first;
    - "Appels non faits": today's missed roll calls, "Classe · période heure" and "Enseignant · matière",
      no button;
    - "Sanctions récentes": the latest 5 sanctions of the school, with "parents à notifier" or
      "notifiés le …", linking to the class discipline page.
11. **Surveillant → "Absences"** (`/school/absences`): one row per student-day of the current
    sequence with at least one `:absent` entry; columns Date, Élève, Classe, Créneaux, Statut ("Non
    justifiée" / "Justifiée · motif"); filters Non justifiées (default) / Justifiées / Toutes. V04-flagged
    students' rows come first with the badge. Selecting a row shows a side panel: student, class, date,
    periods missed, status, "Absences non justifiées" (days in the sequence), the reason chips if not
    justified, and "Absences répétées : convocation des parents recommandée." when flagged.
12. **V06 on the class discipline page**: each sanction shows "Parents notifiés le …" or a
    "Marquer les parents notifiés" button (conduct axis).
13. Access: both SG screens require the conduct axis (Proviseur, Censeur, SG); others are redirected. Menu
    items only in the surveillant space; Ma journée needs a teaching assignment in the active year.
14. All strings go through gettext (FR and EN).

Out of scope: reminders to teachers (N06/R03), SMS to parents, holidays (S02), a school-wide sanctions
page, conduct mark proposal (V05), configurable V04 threshold.

## I — Report card cycle (split)

Decided 2026-10-01. One spec, plan and branch per sub-increment, in this order:

| # | Content | Gaps | Size |
|---|---|---|---|
| I1 | Appreciation bands and distinction / work-warning thresholds in settings; shown on the bulletin | N09 | S–M |
| I2 | Publish bulletins per class and period; publishing freezes them; Censeur "Bulletins" screen; teacher read-only | N13 | M |
| I3 | Class council per class × term: decision and appreciation per student, printable minutes, carried to the bulletin | N11 | L |
| I4 | Passage rules in settings; annual decisions (admis, redouble, rachat, exclu) proposed at the end-of-year council | N10 | M |
| I5 | Bulletin template (francophone / anglophone / bilingual), elements shown, full official header, anglophone grades | N12 | M |

The template comes last so it is designed once, with council decisions and appreciations available.

## I1 — Appreciations and distinctions (spec)

Status: implemented 2026-10-01 (branch `i1-appreciations`, plan `docs/superpowers/plans/2026-10-01-i1-appreciations-distinctions.md`). Visual check done 2026-10-01
(branch `visual-f-g-i1`): one sticky "Modifications non enregistrées" save bar, as in the mockup.

Mockup: `Paramètres école` → "Appréciations & distinctions" (excerpt in
`docs/superpowers/mockups/i1-appreciations-distinctions.html`). Gap: **N09**.

User decisions (2026-10-01): bands are **fully editable** as in the mockup (free-text labels, split/remove
bands) — this overrides `docs/domain/04` §9, which marked the 10/12/14/16/18 bands as safe to hard-code;
honour distinctions have **two gates**, both school toggles. Design choice: the bands live on
`SchoolProfile` as an embedded list, beside the D2b grading rules.

### Data

1. `SchoolProfile.appreciation_bands`: embedded array of `%{from, label}` (`from` decimal). Rules: at least
   one band; the first `from` is 0; `from` strictly increasing, all in 0..20; labels non-empty (trimmed).
   A band covers `from` ≤ average < next `from`; the last band includes 20. Saving replaces the whole list
   atomically.
2. No saved list (nil or empty) = the default bands, labels through gettext (FR/EN): 0 Très insuffisant,
   5 Insuffisant, 8 Médiocre, 10 Passable, 12 Assez bien, 14 Bien, 16 Très bien, 18 Excellent. Saved labels
   are shown as typed, in every locale.
3. `SchoolProfile` thresholds (decimal, nullable = that distinction or warning is off), defaults:
   `felicitations_min` 16, `encouragements_min` 14, `tableau_honneur_min` 12, `avertissement_travail_below`
   8, `blame_travail_below` 6. Validation among the set ones: Félicitations ≥ Encouragements ≥ Tableau
   d'honneur; Blâme travail < Avertissement travail; Avertissement travail ≤ Tableau d'honneur.
4. Toggles: `distinctions_require_all_passed?` (default true — every graded subject ≥ 10, today's rule) and
   `distinctions_require_conduct?` (default false — note de conduite of the period ≥ 12; a student with no
   conduct mark for the period is not blocked).
5. Saved through the profile's update action (admin axis), with a domain function per form like D2b's
   `update_*`; migrations with `mix ash.codegen --dev`.

### Computation

6. `GradingRules` carries the bands and the distinction rules; `Assessment.grading_rules/1` fills them from
   the profile, so `Bulletins` and `Marks` stay pure.
7. `Marks.mention/1` (fixed atoms) is replaced by an appreciation lookup on the rules' bands returning the
   label; nil average → no appreciation. The private `mention_label/1` and `mention_badge` labels go.
8. `Bulletins.distinctions` uses the configured thresholds and gates. Honour rolls: the highest applicable
   one wins (Félicitations > Encouragements > Tableau d'honneur), gates applied. Work warnings, no gate:
   average < `blame_travail_below` → Blâme travail, else average < `avertissement_travail_below` →
   Avertissement travail. Each student gets one `distinction` (or nil); the class summary lists the five
   groups. Applies to the period shown (séquence, trimestre, année), as today. The conduct gate needs the
   period's note de conduite per student, loaded once per class.

### Screens

9. `/school/settings/appreciations` ("Appréciations & distinctions"), `EvaluationsLive` pattern, gate
   `Accounts.can_edit_profile?` (Proviseur, Censeur); others go back to `/school/settings`.
   - Band editor: one row per band — "De" (read-only, previous bound), "À (exclu)" input (the last row reads
     20, not editable), label input, × to remove (not on the only band); "+ Scinder la dernière tranche"
     splits the last band in two at its midpoint; colored bar of the bands; "Tester une note" input shows
     the matching label; "Enregistrer" saves the list, errors shown inline; "Rétablir le barème par défaut".
   - Distinctions card "Distinctions et sanctions de travail": five rows name · ≥ or < · value (empty =
     off), the two toggles; saved with flash "Réglage enregistré." / errors inline.
   - Linked from the settings page (beside coefficients and evaluations) and in the Proviseur's and
     Censeur's "Paramètres" menu sections.
10. Bulletin (`BulletinLive` and print): an "Appréciation" column per subject row; under the moyenne
    générale, the overall appreciation and the distinction or work warning when there is one.
11. Class results: the distinctions block lists the five groups (warnings in amber/red); the per-student
    appreciation uses the school's bands.
12. Teacher marks summary: appreciation distribution by the school's bands, in band order.
13. All strings through gettext (FR and EN).

Out of scope: anglophone A–F grades (I5), freezing bulletins (I2), council decisions and appreciations (I3),
per-level or per-série scales.

## I2 — Publish and freeze report cards (spec)

Status: implemented 2026-10-01 (branch `i2-publish-report-cards`, plan `docs/superpowers/plans/2026-10-01-i2-publish-report-cards.md`); no visual check done.

Mockup: `Espaces par rôle` → Censeur → "Bulletins" (generic list + detail markup and the screen's logic in
`docs/superpowers/mockups/i2-bulletins-publication.html`). Gap: **N13**.

User decisions (2026-10-01): only **trimester and annual** report cards are published (séquence bulletins
stay live); a publication can be **withdrawn with a mandatory reason**; teachers read the **published**
report cards of the **classes they teach** (whole card); publishing is allowed **anytime**, with a
confirmation when mark entry is incomplete. Design choice: publishing stores a **snapshot** of what the
screens show, so nothing later (marks, coefficients, averaging rules, appreciation bands, roster, code)
changes a published card.

### Data

1. `BulletinPublication` (school-scoped, attribute multitenancy): `class_group`, `academic_year`, `term`
   (nil for annual), `period_kind` (`Ash.Type.Enum` `:trimester | :annual`), `status` (`Ash.Type.Enum`
   `:published | :withdrawn`), `published_at`, `published_by_user_id`, `withdrawn_at`,
   `withdrawn_by_user_id`, `withdrawal_reason`, `snapshot` (stored as an exact Erlang term, so decimals and
   atoms round-trip), `snapshot_version` (integer, 1).
2. At most one `:published` row per (class, period kind, term or year) — a partial unique identity. A
   withdrawal sets the row to `:withdrawn` (reason required, trimmed, non-empty) and keeps it as history;
   republishing creates a new row with a fresh snapshot.
3. Publish and withdraw: admin axis (Proviseur, Censeur). Reading rows: school members (access to the
   *content* is decided by the screens, point 9).
4. The snapshot holds exactly what the report card, class results and print render: the
   `Bulletins.aggregate` result (subject rows, groups, totals, moyenne, rank, appreciations, distinctions,
   class statistics), the roster (student id, name, matricule, sex, repeater, enrollment id), conduct and
   discipline per enrollment for the period, the group-subtotals flag, the period label, and the form
   master's name. Plain maps only — no Ash records.

### Computation

5. One entry point `ReportCards.class_view(scope, class_group, period)` returns `{:published,
   publication, view}` or `{:draft, view}`; `view` is the same map whether live or from the snapshot.
   Séquence periods are always `{:draft, view}` (live). The report card, class results and print screens
   use it instead of calling the calculators directly.
6. `ReportCards.publish(scope, class_group, period)` builds the live view and stores it;
   `ReportCards.withdraw(scope, publication, reason)`; `ReportCards.history(scope, class_group, period)`
   (newest first).
7. The period's mark-entry rate for a class: entered ÷ expected over the term's séquences (the year: all
   séquences), computed with F's `EntryProgress` rules (exemptions, any mark status counts).

### Screens

8. **"Bulletins"** (`/school/bulletins`), menu item for the Proviseur and Censeur: class picker, period tabs
   Trimestre 1–3 and Année; status ("Brouillon" or "Publié le … par …"); mark-entry rate; table Rang,
   Élève, Moyenne générale, Appréciation, Distinction, and a print icon per row (that student's report card
   alone). Selecting a row shows the **side panel** (mockup): the student's subject averages with
   coefficients, moyenne générale, rank / effectif, absences (hours), appreciation and distinction, the
   status badge, and buttons "Ouvrir le bulletin" and "Imprimer"; the first student is selected by default.
   "Imprimer toute la classe" sits next to "Publier les bulletins de la classe" — below 100 % entry it first asks « Saisie incomplète : n %. Publier quand même
   ? »; on a published period "Dépublier" opens a required reason field; the history of the class and
   period ("Publié le … par …", "Retiré le … par … : motif") is listed below.
9. **Access:** drafts (live term/annual figures) stay as today — admin axis or the class's form master.
   Published report cards are also open, read-only, to teachers who have a course in the class (solo or
   combined). Teachers get a "Bulletins" item in the enseignant space listing only those classes and only
   published periods; a draft period shows "Pas encore publiés". Report card, results and print enforce
   the same rule.
10. Printing goes through the existing print routes (one student, whole class) for the selected period:
    a published period prints from the snapshot, a draft from live figures. Report card and print of a
    published period show "Publié le …". A printed **draft** trimester or
    annual card carries a "BROUILLON" watermark.
11. All strings through gettext (FR and EN).

Out of scope: council decisions and requiring a council before publishing (I3); the "Publication par"
setting and sending report cards to parents (I5, notifications); publishing séquence report cards.

## I3 — Class councils (spec)

Status: implemented 2026-10-01 (branch `i3-class-councils`, plan `docs/superpowers/plans/2026-10-01-i3-class-councils.md`); no visual check done.

Mockup: `Espaces par rôle` → Censeur → "Conseils de classe" (logic in
`docs/superpowers/mockups/i3-conseils-de-classe.html`; list + detail markup in
`i2-bulletins-publication.html`). Gap: **N11** (trimester councils; the annual council and passage are I4).

User decisions (2026-10-01): only the **Censeur and Proviseur** record councils; per student the council
keeps a **work distinction** (pre-filled from I1, changeable), an optional **conduct warning** and a
**free-text appreciation**; **publishing a trimester requires the class's council to be held** and a
published term locks its council. Design choice: one `ClassCouncil` per class × term and one
`CouncilDecision` row per student, created only when the council changes something.

### Data

1. `ClassCouncil` (attribute multitenancy): `class_group`, `term`, `status` (`Ash.Type.Enum`
   `:open | :held`), `held_on` (date; defaults to the term's `class_council_date`), `chair` (text),
   `attendees` (text), `observations` (text), `held_at`, `held_by_user_id`. One per (class, term). Created
   by the first save (header, a decision, or marking it held); before that the page shows the defaults.
2. `CouncilDecision`: `class_council`, `student`, `distinction_choice` (`Ash.Type.Enum`: the five I1
   `Distinction` values plus `:none`; nil = keep the I1 proposal), `conduct_warning` (`Ash.Type.Enum`
   `:avertissement_conduite | :blame_conduite`, nil = none), `appreciation` (text, trimmed, ≤ 300
   characters). One per (council, student).
3. Writes (council fields, decisions, hold, reopen): admin axis only. Reads: school members (screens decide
   what is shown). While the class's trimester is published (I2), every write is refused with
   "Conseil verrouillé : bulletins publiés" — withdrawing the publication unlocks it.
4. Migrations with `mix ash.codegen --dev`.

### Computation

5. A student's council outcome: `distinction` = the decision's choice (`:none` → nil) or, with no choice,
   the I1 proposal for the trimester; `conduct_warning`; `appreciation`. Students with no decision row get
   the proposal and empty fields.
6. The I2 report-card view gains `council: %{held?, held_on, outcomes: %{student_id => outcome}}` for
   trimester periods (nil for séquence and annual), so a publication freezes the council.
7. I2 `publish` for a trimester requires the class's council for that term to be `:held`; otherwise
   `{:error, :council_not_held}` and the Bulletins screen disables "Publier" with "Conseil de classe non
   tenu". Annual publishing is unchanged until I4.

### Screens

8. **"Conseils de classe"** (`/school/councils?term=<id>`), menu item for the Proviseur and Censeur: term
   tabs (default: the trimester covering today); one row per class — council date, mark-entry rate for the
   term (I2 `entry_rate`), status "Saisie incomplète" (rate < 100), "Prêt" (100, not held), "Tenu",
   "Publié"; header "n / N classes prêtes". A row opens the class's council.
9. **Council page** (`/school/councils/:class_id?term=<id>`):
   - header form: date, président, présents, observations générales (saved on submit);
   - class statistics for the term: effectif, moyenne de la classe, taux de réussite, garçons / filles;
   - student table, by rank: rang, élève, moyenne, proposed distinction (I1), decision select (Proposition
     · the five distinctions · Aucune), conduct warning select (Aucun · Avertissement de conduite · Blâme de
     conduite), appreciation input; each row saves on change, with a short "Enregistré" mark;
   - "Marquer le conseil tenu" (confirmation « Saisie incomplète : n %. Marquer tenu quand même ? » below
     100 %), "Rouvrir le conseil" while held and not published; when published, everything is read-only
     with "Conseil verrouillé : bulletins publiés";
   - "Imprimer le procès-verbal".
10. **Procès-verbal** (A4 print, `/school/councils/:class_id/print?term=<id>`): school, class, term, date,
    président, présents, the class statistics, observations générales, the lists of Félicitations,
    Encouragements, Tableau d'honneur, Avertissement / Blâme travail and conduct warnings, then one line
    per student (rang, élève, moyenne, décision, avertissement de conduite, appréciation); signature lines
    "Le président du conseil" and "Le professeur principal". An open council prints "PROJET".
11. **Report card** (screen and print), trimester only: the distinction shown is the council outcome; the
    conduct warning when any; "Appréciation du conseil de classe" filled with the council's text (the
    print's blank ruled line otherwise).
12. Access: council screens and the procès-verbal require the admin axis; others are redirected. Strings
    through gettext (FR and EN).

Out of scope: the annual council and passage decisions (I4); the form master preparing decisions; sending
the procès-verbal; electronic signatures.

## Holes found on 2026-10-01 (not yet specified)

Found by comparing the app's routes with every claude.ai/design screen and with `Écarts avec le code`.
Each needs a spec before a plan.

### L — School life, rest

- **V05** — suggested conduct mark (SG → *Conduite*): computed from unjustified absence hours, lates and
  sanctions, adjusted then confirmed by the SG. In the gap list but in no increment until now.
- **L1** — school-wide sanctions page (SG → *Sanctions*): list with a parents column, three-tap entry
  (student, type, reason), detail panel with "Marquer les parents notifiés". Today sanctions live only on
  each class's discipline page; G left this page out.
- **L2** — settings *Assiduité & discipline* (`Paramètres école` → *Vie scolaire*): late counted as an
  absence beyond N minutes, justification deadline, parent alert after N unjustified hours, conduct scale
  (points per absence hour, per late, per sanction), sanctions in use. G hard-codes the repeated-absence
  threshold (3 days); V05 needs the scale.
- **L3** — school-wide student list (Censeur and SG → *École → Élèves*), searchable by name or
  `matricule` (the field exists). The app has only per-class rosters.

### M — School registers and new year

No mockup and no code for:
- **M1** — starting the next school year: carrying classes over, moving students up after the passage
  decisions (N10/I4), archiving the old year.
- **M2** — parents and guardians: contacts on the student, used by V06 and later R03. Today "parents
  notifiés" records only the date.
- **M3** — a student profile page (identity, guardian, class history).
- **M4** — settings fields shown in `Paramètres école` but in no gap: maximum class size and class naming
  rule (*Niveaux, séries & classes*), short school name (*Établissement*), statutory teaching hours and
  "one form master per class" (*Affectations*, next to T04).

### Screens in the app with no current mockup

`Espaces par rôle` has no Proviseur and no Intendant space (`Proviseur.dc.html` is in the older paper
style). No mockup covers: the Proviseur dashboard, fees and payments, the class page and its tabs
(results, register, discipline, timetable placement, bulletins and print), CSV enrolment import, members
and invitations, periods, combined courses, subject exemptions. Ask for mockups before redesigning these.

### V — Visual checks still owed

Screens with a mockup that have never been compared with it: *Saisie des notes* (course and séquence
tabs, Enter to the next student, row average), *Mes classes* (the app's "Mes cours"), the teacher's
*Emploi du temps*, both *Corrections* screens (D3), and the I2 *Bulletins* screen. Dev data for this:
`mix run priv/repo/demo_school_seeds.exs`.
