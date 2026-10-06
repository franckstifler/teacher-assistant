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
| J | Timetable and staff, split J1 S03/S02 → J2 T04 → J3 T02/T03 → J4 T01 → J5 T05 (see §J) | S03, S02, T04, T01, T03, T02, T05 | — | S…L |
| K | Platform, split with L and M into KLM1…KLM9 (see §K, L, M); R04 dropped 2026-10-02 | R05, S04, S06, R03 (staff part) | E | S…M |
| — | Marketing site | `Landing` mockup (not in the gap list) | — | M |
| L | School life, rest (see §K, L, M) | V05, L1–L3 | G | M |
| M | School registers and new year (see §K, L, M) | M1–M4 | — | M…L |
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

## I4 — Passage rules and end-of-year decisions (spec)

Status: implemented 2026-10-01 (branch `i4-passage`, plan `docs/superpowers/plans/2026-10-01-i4-passage.md`); no visual check done.

Mockup: `Paramètres école` → "Passage & redoublement" (fields `mp`, `rachat`, `excl`, `redMax`, `condExcl`,
`absExcl`). Gap: **N10**. Builds on I3's councils and I2's publication.

User decisions (2026-10-01): a **separate annual council** per class (an "Année" council next to the three
trimester councils); the engine uses the **mockup's rule set** — passing, rachat and exclusion averages, one
repeat per cycle, exclusion for conduct below 10 and for unjustified absences above a threshold — every
threshold editable. Design choices: the engine only **proposes**; the council confirms or overrides. Councils
are keyed like I2 publications, by `period_key` (`"trim:<term id>"` or `"annee"`).

### Data

1. `SchoolProfile` gains (admin axis, validated together): `passage_min` (decimal, default 10, required),
   `rachat_min` (decimal, default 9.5, nil = off), `exclusion_below` (decimal, default 7, nil = off),
   `one_repeat_per_cycle?` (boolean, default true), `exclusion_on_conduct?` (boolean, default true; fixed
   conduct minimum 10), `exclusion_absence_hours` (integer, default 60, nil = off). Rules among the set
   values: 0 ≤ exclusion_below < rachat_min ≤ passage_min ≤ 20; absence hours > 0.
2. `ClassCouncil` gains `period_key` (string, required; `"trim:<term id>"` or `"annee"`) and
   `academic_year_id`; `term_id` becomes optional (nil for the annual council); the uniqueness moves to
   (class, period_key). Existing trimester councils keep working (their key is `"trim:<term id>"`).
3. `CouncilDecision` gains `passage_decision` (`Ash.Type.Enum` `:admis | :admis_rachat | :redouble |
   :exclu`; nil = keep the proposal). Only meaningful on the annual council.
4. Migrations with `mix ash.codegen --dev`. `class_councils` is empty everywhere (checked on the dev database
   on 2026-10-01), so the new required `period_key` needs no backfill.

### Computation

5. Pure `PassageRules.propose(%{average, repeater?, conduct, unjustified_hours}, rules)` →
   `{decision, reason}` or nil (no average):
   - **Exclu** when the average < `exclusion_below` (« Moyenne < 7 »), or `exclusion_on_conduct?` and conduct
     < 10 (« Conduite < 10 »; no conduct mark = not applied), or unjustified hours ≥
     `exclusion_absence_hours` (« 60 h d'absences non justifiées »);
   - else **Admis** when the average ≥ `passage_min`;
   - else **Admis par rachat** when `rachat_min` is set and the average ≥ it;
   - else **Redouble**, or **Exclu** (« Déjà redoublant ») when the student is a repeater this year and
     `one_repeat_per_cycle?` is on.
   Reasons are gettext strings with the threshold values.
6. The annual council's outcome per student adds `passage` (the decision or, without one, the proposal) and
   `passage_reason` (the proposal's reason when the proposal stands). Inputs: the annual average (I2), the
   enrollment's `repeater`, the annual note de conduite and unjustified absence hours (existing
   discipline/attendance functions, read once per class).
7. Annual report-card views carry the annual council like trimester views do (`council` entry); annual
   publishing requires the class's annual council to be held (`{:error, :council_not_held}`).

### Screens

8. **"Passage & redoublement"** settings page (`/school/settings/passage`, EvaluationsLive pattern, admin
   axis), linked from Settings and the Proviseur/Censeur "Paramètres" menus: the three averages, the two
   toggles and the absence hours, with inline validation errors.
9. **Conseils de classe**: the term tabs gain "Année"; the list's rate is over all séquences.
10. **Annual council page** (`/school/councils/:class_id?period=annee`; trimester pages keep `?term=`):
    the I3 page with annual figures plus a "Passage" column — the proposal with its reason, and a select
    (Proposition · Admis · Admis par rachat · Redouble · Exclu). Hold, reopen, lock as in I3.
11. **Procès-verbal** of the annual council adds the passage decision per student and the counts (Admis,
    Admis par rachat, Redouble, Exclu).
12. **Annual report card** (screen and print): the "Décision" line shows the passage decision; frozen at
    publication.
13. Strings through gettext (FR and EN).

Out of scope: moving students to next year's classes and repeat history across years (M1); orientation;
per-level thresholds.

## I5 — Report card template (spec)

Status: implemented 2026-10-01 (branch `i5-bulletin-template`, plan `docs/superpowers/plans/2026-10-01-i5-bulletin-template.md`); no visual check done.

Mockup: `Paramètres école` → "Modèle de bulletin" (fields `modele`, `aff`) and the "grades anglophones (A–F)"
toggle under "Appréciations". Gap: **N12**. Builds on I1 (bands, distinctions), I2 (snapshots), I3 and I4
(council outcomes).

User decisions (2026-10-01): the card's language **follows the class** (francophone class → French card,
anglophone class → English card), with a school setting to make every card bilingual; anglophone classes get
an **editable letter-grade scale**; the **official header** is built from the school profile, no signature
or stamp (S04, K); the **mockup's eight elements plus the QR** can be hidden; publishing **freezes the look
too**; the QR page only says « authentique, publié le … » with the student's name. Design choices: the
template applies to the **printed card** only (screens keep the reader's language and show everything);
"Publication par" stays as in I2 (Proviseur and Censeur); sending cards to parents is R03.

### Data

1. `SchoolProfile` gains (admin axis):
   - `bulletin_language` (`Ash.Type.Enum` `:by_class | :bilingual`, default `:by_class`).
   - `bulletin_elements` (array of `Ash.Type.Enum` `BulletinElement`: `:rank`, `:class_average`,
     `:min_max`, `:subject_appreciation`, `:effectif`, `:absences`, `:conduct`, `:pp_signature`,
     `:qr_code`), default all but `:qr_code`. Unknown or duplicate values are rejected.
   - `grade_scale`: embedded array of `%{from, letter, remark}`, default A 16 Excellent, B 14 Very good,
     C 12 Good, D 10 Pass, E 8 Weak, F 0 Fail. Same rules as the I1 bands: at least one band; the first
     `from` is 0; `from` strictly increasing within 0..20; letter and remark non-empty (trimmed). A band
     covers `from` ≤ mark < next `from`; the last includes 20. Saved as a whole.
2. No new header fields: the header is derived from the profile (item 6).
3. Migration with `mix ash.codegen --dev`. Existing profiles get the defaults.
4. New dependency `eqrcode` (pure-Elixir QR encoder, inline SVG).

### Template

5. Pure `BulletinTemplate.resolve(profile, class_group)` → `%{language, elements, grade_scale, header}`:
   `language` is `:bilingual` when `bulletin_language` is `:bilingual`, else `:fr` for a francophone class
   and `:en` for an anglophone one. `BulletinTemplate.grade(scale, mark)` → `{letter, remark}` or nil.
6. `header`, resolved once: République du Cameroun · Paix – Travail – Patrie and Republic of Cameroon ·
   Peace – Work – Fatherland (per language; both when bilingual); Ministère des Enseignements secondaires /
   Ministry of Secondary Education; Délégation régionale des Enseignements secondaires du `<région>` and,
   when the profile has a département, the département delegation; then the school's name, address, phone,
   authorisation number (`registration_number`), motto and logo. Missing optional fields are left out.
7. Publishing stores the resolved template in the snapshot (`snapshot_version` 3, key `template`). A
   published v3 card renders from its stored template, whatever the settings say later. A draft, and a v1
   or v2 publication (no template), renders with `resolve/2` on the current settings.

### Printed card

8. Labels go through one helper: French or English card → that locale (`Gettext.with_locale`); bilingual →
   « French / English ». The card's `<html lang>` follows the language (`fr`, `en`, `fr` for bilingual).
9. Subject column: a francophone class keeps the I1 appreciation; an anglophone class prints **Grade** and
   **Remark** from the grade scale (the general average gets a grade too). Distinctions, conduct warnings
   and passage decisions keep their own labels, in the card's language.
10. Hidden elements leave no empty column: `:rank` hides the rank; `:class_average` hides the class average (new on the card: the
    class's general average, printed after the student's, from the same view);
    `:min_max` hides « Cote classe »; `:subject_appreciation` hides the appreciation or grade/remark
    columns; `:effectif` hides the class size (cartouche and after the rank); `:absences` hides the
    attendance line; `:conduct` hides the discipline line (conduct mark, consignes, sanctions);
    `:pp_signature` hides the PP visa slot; `:qr_code` hides the QR. Colspans follow the visible columns.
    Subjects, coefficients, marks, totals, the general average, distinctions, the council's appreciation and
    decision, and the head's visa always print.
11. The QR prints only on **published** cards with `:qr_code` on, beside the visas.

### Verification page

12. QR target: `/verify/bulletin/:token`, `token` = `Phoenix.Token.sign(endpoint, "bulletin-verify",
    {publication_id, student_id})`, no expiry; the same at every reprint. Rotating `secret_key_base`
    invalidates printed codes (accepted).
13. Public LiveView or controller page, no login, minimal layout, browser language:
    - published publication containing the student → « ✓ Bulletin authentique », student name, school,
      class, period, « Publié le … »;
    - withdrawn → « Ce bulletin a été retiré le … » (no reason);
    - bad or tampered token, unknown publication, student not in the snapshot → « Lien de vérification
      invalide ».
    No marks. The read bypasses policies (`authorize?: false`) with the tenant taken from the publication
    row — the only such read outside authentication.

### Settings screen

14. **"Modèle de bulletin"** (`/school/settings/bulletin`, PassageLive pattern, admin axis; others
    redirected), linked from Settings and the Proviseur/Censeur "Paramètres" menus: language (Suivre la
    classe / Bilingue), the nine element checkboxes, the grade-scale editor (I1 band editor pattern), and
    a header preview built by `resolve/2`.
15. Strings through gettext (FR and EN).

Out of scope: digitised signature and stamp, editable delegation text (S04, K); sending cards to parents
(R03); publication by role setting; template on the screen views; séquence cards' publication.

## J — Timetable and staff (split)

Decided 2026-10-01. One spec, plan and branch per sub-increment, in this order:

| # | Content | Gaps | Size |
|---|---|---|---|
| J1 | School calendar: lesson days, Wednesday afternoon off, period overlap check, default lesson length; holidays per year | S03, S02 | S–M |
| J2 | Assignments overview: school grid teachers × classes, weekly hours vs statutory service, one form master per class | T04 | S |
| J3 | Rooms (capacity, laboratory) and teacher unavailability | T02, T03 | M |
| J4 | Censeur timetable editor: class tabs, conflicts shown (not refused), move/swap suggestions, hours placed vs planned, room and unavailability checks | T01 | L |
| J5 | Teacher absences and replacements: declaration, cover per slot (colleague, étude, cancelled), hours owed | T05 | L |

J1 first because every later piece needs to know which days have lessons; J3 before J4 so the editor checks
rooms and unavailability from the start; J5 last because it reads the finished timetable.

**Postponed 2026-10-01:** J3 (rooms, teacher unavailability) is done later, at the user's request. J4 and J5 may
go ahead without it: J4's editor then checks only teacher clashes and hours, and gains the room and
unavailability checks when J3 lands; J5 suggests free colleagues from the timetable alone, refined by
unavailability later.

## J1 — School calendar (spec)

Status: implemented 2026-10-01 (branch `j1-school-calendar`, plan `docs/superpowers/plans/2026-10-01-j1-school-calendar.md`); no visual check done.

Mockup: `Paramètres école` → "Horaires" (fields `jours`, `mer`, `duree`) and "Congés" (list `conges`). Gaps:
**S03, S02**.

User decisions (2026-10-01): lesson days are weekday chips plus **one toggle « Mercredi après-midi libre »**
(the afternoon = every period starting at or after 13:00); holidays are a **per-year list, prefilled** with the
national holidays; closing a day or half-day that has placed lessons is **refused until those lessons are
removed**; the default lesson length is **50 min**, and the generated default schedule moves to 50-minute
lessons with breaks at 10:00–10:15 and 13:00–13:30 (layout C: the 15 minutes 12:45–13:00 have no period). Out of J1: the roll-call grace period (« Délai pour faire l'appel »).

Existing code: `Period` (position, label, start/end time, kind lesson/break) with a "Périodes" page that can
generate the default schedule, edit and delete (no add); `DayOfWeek` Monday–Saturday; `TimetableSlot`
(class × day × period); `Academics.SchoolLife` computes the day views of G from the slots of a weekday.

### Data

1. `SchoolProfile` gains (admin axis):
   - `lesson_days`: array of `DayOfWeek`, default all six (Monday–Saturday — today's behaviour, so existing
     schools see no change); at least one day.
   - `wednesday_afternoon_off?`: boolean, default false.
   - `default_lesson_minutes`: integer 1..240, default 50.
2. Saving the lesson days or the Wednesday toggle is refused when timetable slots sit on a day being removed
   or, with the toggle on, on a Wednesday period starting at or after 13:00: « 12 cours sont placés le
   samedi : retirez-les de l'emploi du temps d'abord. » Nothing is written.
3. `Period` validation: `end_time > start_time`, and no overlap with another period of the school
   (`start < other.end and other.start < end`): « Cours 2 (08:20–09:10) chevauche Cours 1 (07:30–08:25). »
4. `Reference.default_periods_preset/0` moves to 50-minute lessons: Cours 1 07:30–08:20, Cours 2 08:20–09:10,
   Cours 3 09:10–10:00, Récréation 10:00–10:15, Cours 4 10:15–11:05, Cours 5 11:05–11:55, Cours 6
   11:55–12:45, Pause 13:00–13:30, Cours 7 13:30–14:20, Cours 8 14:20–15:10, Cours 9 15:10–16:00 (nine
   lessons; nothing between 12:45 and 13:00). Existing schools keep their periods.
5. New `Holiday` resource (tenant, admin axis to write, members read): `academic_year_id`, `label`
   (non-empty), `start_date`, `end_date`; `end_date >= start_date`; both inside the year's dates.
6. Prefill: creating an academic year adds the national holidays falling inside it; a « Préremplir » action
   adds them later without duplicates (same label and start date). The list: Noël (25 Dec), Jour de l'an
   (1 Jan), Fête de la Jeunesse (11 Feb), Vendredi saint and Ascension (computed from Easter), Fête du
   Travail (1 May), Fête nationale (20 May). Breaks, Tabaski, Ramadan and exam periods are typed by the
   school.
7. Migrations with `mix ash.codegen --dev`.

### Calendar

8. One pure module answers, from the profile and the year's holidays:
   - `lesson_day?(date)`: false when the weekday is not a lesson day or the date is in a holiday;
   - `holiday_on(date)`: the holiday or nil;
   - `open_cell?(day, period)`: false for a Wednesday period starting at or after 13:00 when the toggle is
     on; true otherwise (for a lesson day).
   Easter is computed with the anonymous Gregorian algorithm.

### Effects

9. Timetables (class editor and teacher view): columns are the lesson days only; closed cells are greyed and
   cannot be filled; `Timetabling.place_slot` and `place_combined_slot` refuse a closed cell or a non-lesson
   day with `{:error, :closed_cell}`.
10. Day views (G): on a holiday or a non-lesson day, « Aujourd'hui » (SG) and « Ma journée » (teacher) show
    « Jour férié : <label> » or « Pas de cours aujourd'hui » and expect no roll call; « Appels manquants cette
    semaine » skips holidays, non-lesson days and closed cells.
11. Unchanged: the roll-call page, séquence dates and mark-entry deadlines, absence and sanction lists.

### Screens

12. **« Horaires »** (the existing « Périodes » page, renamed; same route): lesson-day chips, the Wednesday
    toggle, the default lesson length, then the periods with an « Ajouter une période » row whose end time
    is pre-filled as start + default length; overlap and closing errors inline. Access unchanged: admin
    axis only (others are redirected, as today).
13. **« Congés & jours fériés »** (`/school/settings/holidays`, admin axis, linked from Settings and the
    Proviseur/Censeur "Paramètres" menus): the active year's holidays (label, dates, number of days),
    add / edit / delete, « Préremplir les jours fériés nationaux ».
14. Strings through gettext (FR and EN).

Out of scope: the roll-call grace period; per-class lesson days; holidays per class or level; moving
séquence dates or deadlines around holidays.

## J2 — Assignments overview (spec)

Status: implemented 2026-10-01 (branch `j2-assignments-overview`, plan `docs/superpowers/plans/2026-10-01-j2-assignments-overview.md`); no visual check done.

Mockup: `Paramètres école` → "Affectations enseignants" (grid classes × subjects, side panel with each
teacher's load after the change, « Retirer l'affectation », load bars; fields `service`, `pp`, `combine`). Gap:
**T04**.

User decisions (2026-10-01): the grid is **editable**, as in the mockup; the statutory service is a **school
default with a per-teacher override**; « Un professeur principal par classe » means **showing each class's PP,
setting it from the grid and flagging classes without one** (no setting; a teacher may be PP of several classes).
Design choices: changes go through the existing assignment rules; combined courses are shown but changed only
on the class page; out of J2: the « Enseignants » list with entry rates and reminders (N06), and which subjects
a teacher can teach.

Existing code: `TeachingContext` (class × subject × teacher, `weekly_hours` default 4, `coefficient` nil = the
D2a grid, optional `combined_course_id`); `Curriculum.assign_teacher/4`, `reassign_teacher/3`,
`remove_assignment/2` (refused with `:has_data` when marks or a progression exist); the D2a coefficient grid
(`Curriculum.coefficient_cells/1`, `CoefficientRules.resolve/2`); `ClassGroup.form_master_user_id` with
`Enrollment.set_form_master/3`.

### Data

1. `SchoolProfile.statutory_hours`: integer 1..40, default 18 (admin axis).
2. `SchoolMembership.statutory_hours`: integer 1..40, nullable; nil = the school's value (admin axis).
3. Migrations with `mix ash.codegen --dev`.

### Computation

4. A teacher's **weekly load** = the sum of `weekly_hours` of their active-year assignments, a combined course
   counted once (one delivery for several classes). **Over** when the load is above their own service
   (membership value, else the school's).
5. A grid cell (active-year class × subject) is:
   - **assigned** — a `TeachingContext` exists: its teacher, `over?` from rule 4, `combined?`;
   - **to assign** — none exists and the coefficient grid resolves the subject for the class's subsystem,
     level and série (`CoefficientRules.resolve/2`);
   - **not taught** — neither.
   Columns are the subjects with at least one assigned or to-assign cell, in the catalog order; rows are the
   active year's classes in the usual class order.
6. Counts: cells to assign; classes without a form master.

### Screen

7. **« Affectations »** (`/school/settings/assignments`, admin axis, others redirected; linked from Settings
   and the Proviseur/Censeur « Paramètres » menus):
   - header: « n enseignements à affecter » (red) or « Tous les enseignements sont affectés »; « n classes sans
     professeur principal » (amber) when any;
   - grid: per row the class label and its PP (or « Sans professeur principal », amber), then one cell per
     subject — assigned: the teacher's name (amber when over; a « regroupé » tag for a combined course);
     to assign: « À affecter » (red); not taught: dashed, not clickable; horizontal scroll on narrow screens;
   - side panel for a selected assigned or to-assign cell: « classe · matière », hours per week (an input,
     default 4 for a new assignment), current teacher, the list of active members — those already teaching the
     subject first — each with « x h / s h » (current) or « x h / s h après » (after the change), red when over;
     choosing one assigns or reassigns; « Retirer l'affectation » removes (refused with « Impossible : des notes
     ou une progression existent. »). A combined-course cell's panel is read-only with a link to the class page;
   - PP panel for a selected class: the members, choose one or « Aucun » (`Enrollment.set_form_master/3`);
   - « Charge des enseignants »: every teacher with an assignment, a bar of load against their service,
     heaviest first, red when over;
   - « Service statutaire » (h / semaine) on this page, saved with the school profile.
8. Members page: a « Service (h/sem.) » field per teaching member, empty = the school's value.
9. Strings through gettext (FR and EN).

Out of scope: the « Enseignants » list (entry rates, « Relancer », N06); teacher subject qualifications;
editing coefficients or combined courses from the grid.

## J4 — Censeur timetable editor (spec)

Status: implemented 2026-10-01 (branch `j4-timetable-editor`, plan `docs/superpowers/plans/2026-10-01-j4-timetable-editor.md`); no visual check done.

Mockup: `Espaces par rôle` → Censeur → « Emploi du temps » (class tabs, cells red on a teacher clash, side
panel with « Conflit : … », « Déplacer au … » / « Échanger avec … », subject chips « MATH · 3/5 h », hours per
subject, school-wide conflict count). Gap: **T01**. J3 (rooms, unavailability) is postponed: no room or
unavailability check here.

User decisions (2026-10-01): a teacher clash is **saved and shown in red**, no longer refused; the new editor
**replaces** the per-class timetable page. Combined courses (« cours regroupés », e.g. 4e Année MACO and 4e
Année ELEQ taking Informatique together with one teacher) keep working as today and are never a clash between
their own classes.

Existing code: `TimetableSlot` (class × day × period, one per cell), `Timetabling.place_slot/3` (refuses a
clash today, refuses a closed cell since J1), `place_combined_slot/4`, `clear_slot/4`,
`clear_combined_slot/4`, `class_timetable/2` (slots + hours tally against `weekly_hours`); the per-class page
`/school/classes/:id/timetable` (`TimetableLive`); J1's `SchoolCalendar.open_cell?/3`.

### Rules

1. `place_slot/3` and `place_combined_slot/4` no longer refuse a teacher clash. Still refused: a course not of
   the class, an unknown period, a closed cell (`{:error, :closed_cell}`).
2. A **clash**: the same teacher in two or more classes at the same day and period of the active year, unless
   all those slots belong to one combined course. A pure `Academics.TimetableConflicts` returns the clashing
   cells (`{class_group_id, day, period_id}` ⇒ the other classes) and the school's clash count (one per
   teacher × day × period).
3. **Fix suggestions** for a clashing cell holding a non-combined lesson, at most 2 moves then 2 swaps:
   - move: an empty open cell of the same class where the teacher has no lesson;
   - swap: another non-combined lesson of the same class whose teacher is free at the clashing cell, while the
     clashing teacher is free at that lesson's cell, and the swap creates no new clash.
   `Timetabling.move_slot/…` and `swap_slots/…` apply a fix in one transaction.
4. **Hours**: per course of the class, slots placed against `weekly_hours` — `:missing` (amber), `:ok` (green),
   `:over` (red) — the existing tally.
5. A teacher with a clash sees both lessons in « Ma journée » and « Mon emploi du temps »; roll calls stay per
   class. Nothing else changes.

### Screen

6. **« Emploi du temps »** (`/school/timetable`, `?class=<id>` selects the tab; admin axis, others redirected;
   in the Proviseur and Censeur menus). `/school/classes/:id/timetable` redirects to
   `/school/timetable?class=:id`; the class page's link points there. Printing is unchanged.
7. Header « Emploi du temps · <classe> » and « n conflits à résoudre » (red) or « Aucun conflit »; class tabs
   (active year, usual order), a red dot on a class with a clash.
8. Grid: lesson days × periods (breaks as thin rows); a cell shows subject and teacher, red border and fill
   when it clashes, « Libre » dashed when empty, greyed when closed (J1); the selected cell outlined; horizontal
   scroll on narrow screens.
9. Side panel for the selected open cell: day · period · time · class; current subject and teacher or
   « Créneau libre »; on a clash « Conflit : <enseignant> a aussi cours en <classes> à ce créneau. » then the
   fix buttons or « Aucune solution automatique »; subject chips « <matière> · placées/prévues h », red with a
   title « <enseignant> a déjà cours en <classe> » when that teacher is busy then; choosing a chip places or
   replaces; « Vider le créneau ». A combined course is tagged « regroupé »; placing or clearing it changes all
   its classes; no fix is offered for it.
10. « Heures par matière » for the tab's class, coloured as in rule 4.
11. Strings through gettext (FR and EN).

Out of scope: rooms and teacher unavailability (J3); automatic timetable generation; teacher absences (J5);
editing combined courses from the editor.

## K, L, M — Platform, school life rest, registers and new year (split)

Decided 2026-10-02. **R04 (teacher solo mode and joining a school) is dropped**: nothing teacher-solo for now.
R03 is reduced to **staff in-app notifications** (no parent messages until an SMS provider is chosen). One
spec section below per sub-increment; one plan, branch and `mix precommit` each, in this order:

| # | Content | Gaps | Size |
|---|---|---|---|
| KLM1 | Students and guardians: guardian records, birth date and place, student profile, school-wide student list | M2, M3, L3 | M |
| KLM2 | Settings « Assiduité & discipline », late minutes, alert in hours | L2 | S–M |
| KLM3 | Suggested conduct mark | V05 | M |
| KLM4 | School-wide sanctions page | L1 | S–M |
| KLM5 | Class size, class naming rule, enrolment counts in one query | M4, R05 | S |
| KLM6 | Official header, signature and stamp | S04 | S |
| KLM7 | Rights matrix (read only) | S06 | S |
| KLM8 | Staff in-app notifications, correction notices, entry reminders | R03 (part), N06 | M |
| KLM9 | Next school year and closed years | M1 | L |

KLM1 first: guardians feed the sanctions page (KLM4) and later parent messages. KLM2 before KLM3 (the conduct
scale). KLM9 last: it reads the class size and naming rule (KLM5) and closes years for every year-bound
resource built before it.

## KLM1 — Students and guardians (spec)

Status: implemented 2026-10-02 (branch `klm1-students-guardians`, plan
`docs/superpowers/plans/2026-10-02-klm1-students-guardians.md`); no visual check done. The import is the
existing semicolon paste with positional columns (rule 9), not a CSV with named headers.

Gaps: **M2** (parents and guardians), **M3** (student profile), **L3** (school-wide student list, Censeur and
SG → *École → Élèves*). No mockup for M2/M3.

User decisions (2026-10-02): a guardian is a **separate record shared by siblings**, one **main contact** per
student; guardians have **no login**; the student gains **optional date and place of birth**; no photo.

Existing code: `Academics.Student` (`full_name`, `sex`, `matricule`; reads `:owned`, `:by_matricule`,
`:search_by_name`) in the Enrollment domain; `Enrollment` (student × class × year, `status`, `repeater`); CSV
import `/school/classes/:id/import`; per-enrolment bulletin route; no student page, no school-wide list.

### Data

1. `Student` gains `birth_date` (date, nullable, not in the future) and `birth_place` (string, nullable).
2. **`Guardian`** (Enrollment domain, tenant-scoped like `Student`): `full_name` (required), `relationship`
   (enum `:pere | :mere | :tuteur | :autre`, an `Ash.Type.Enum`), `phone` (required), `phone_2`, `email`,
   `language` (enum `:fr | :en`, default `:fr`).
3. **`StudentGuardian`** join: `student`, `guardian`, `primary?` (boolean). Identity on `[student_id,
   guardian_id]`; at most one `primary?` per student (partial unique index). The first guardian linked to a
   student becomes primary; making another primary unsets the previous one in the same action; unlinking the
   primary promotes none (the profile then shows « Aucun contact principal »).
4. Linking looks up an existing guardian of the school by phone first (normalised: digits only, leading `237`
   dropped) and offers « Lier <nom> » instead of creating a duplicate. A guardian with no linked student left
   is deleted with the last unlink.
5. Policies: read on the member axis for admins, the SG (`:conduct`) and the student's teachers and form
   master; create/update/link/unlink for admins and `:conduct`.

### Screens

6. **« Élèves »** (`/school/students`; admin or `:conduct`; in the Proviseur, Censeur and Surveillant menus,
   under *École*): students enrolled in the active year, search by name or matricule (one field), class filter;
   columns name, matricule, class, sex, main contact and phone (`tel:` link); usual class order then name;
   paginated (50). A row opens the profile.
7. **Student profile** (`/school/students/:id`; same readers as rule 5):
   - *Identité*: name, sex, matricule, date and place of birth; « Modifier » for admins and `:conduct`.
   - *Parents et tuteurs*: each guardian with relationship, phones, e-mail, language, « Contact principal »
     badge; add (with the phone lookup of rule 4), set as main contact, edit, unlink.
   - *Scolarité*: one row per enrolment, newest first: year, class, « Redoublant », passage decision when
     decided (I4), link to that year's bulletin.
   - *Cette année*: justified and unjustified absence hours, lates, sanctions, conduct marks per séquence,
     links to the class's register and discipline pages.
8. Class roster rows (`ClassLive`) link to the profile.
9. CSV import gains optional columns `date_naissance` (JJ/MM/AAAA), `lieu_naissance`, `parent_nom`,
   `parent_telephone`; a parent with an existing phone is linked, not duplicated, and becomes main contact.
10. I5's bulletin template gains an element « Date et lieu de naissance » (on by default), printed « Né(e) le
    … à … » when known.
11. Strings through gettext (FR and EN).

Out of scope: guardian accounts and logins, student photo, parent messages (R03), moving a student between
classes.

## KLM2 — Settings « Assiduité & discipline » (spec)

Status: implemented 2026-10-06 (branch `klm2-school-life-settings`, plan
`docs/superpowers/plans/2026-10-06-klm2-school-life-settings.md`); no visual check done.

Mockup: `Paramètres école` → *Vie scolaire* → « Assiduité & discipline ». Gap: **L2**.

User decisions (2026-10-02): a late can carry **optional minutes**; the repeated-absence alert is in **hours**
(replaces G's 3 days); empty justification deadline = **any time**.

Existing code: `AttendanceEntry` (`status :present | :absent | :late`, `justified`, `justification_reason`,
`justified_at`); `Conduct.totals/1` (absence hours from period length, lates counted); G's
`SchoolLife.repeated_absence_threshold/0` = 3 distinct days in the current séquence; `SanctionType`
(`:avertissement, :blame, :exclusion_temporaire, :exclusion_definitive, :consigne`);
`SchoolProfile.exclusion_absence_hours`.

### Data

1. `SchoolProfile` gains (editable by admins and `:conduct`, through one action `:update_school_life`):
   - `late_as_absence_minutes`: integer 1..240, nullable (nil = a late is never an absence);
   - `justification_deadline_days`: integer 1..60, nullable (nil = any time), in lesson days (J1 calendar);
   - `absence_alert_hours`: integer 1..200, default 10;
   - `conduct_points_per_absence_hour`: decimal 0..5, default 0.5;
   - `conduct_points_per_late`: decimal 0..5, default 0.25;
   - `sanction_points`: embedded resource with one decimal 0..20 per sanction type — consigne 1,
     avertissement 2, blâme 4, exclusion temporaire 6, exclusion définitive 0 (it ends schooling);
   - `sanction_types_in_use`: list of `SanctionType`, default all.
2. `AttendanceEntry` gains `late_minutes`: integer 1..240, nullable, only with `status: :late` (cleared when
   the status changes).

### Computation

3. `Conduct.totals/2` takes the school's `late_as_absence_minutes`: a late whose `late_minutes` exceeds it
   counts as an **unjustified absence** of that period's hours (or justified, when justified), not as a late. A
   late without minutes stays a late. Every caller (bulletin, register, V05) passes the profile value.
4. V04: a student is flagged when their **unjustified absence hours in the current séquence** reach
   `absence_alert_hours`; `repeated_absence_threshold/0` is removed. Labels change from « n jours » to « n h ».
5. With a deadline, an unjustified absence is **« Délai dépassé »** once more than N lesson days have passed
   since its date (holidays and closed days not counted). It is a flag only: the SG can still justify.

### Screens

6. **« Assiduité & discipline »** (`/school/settings/school-life`; in the Proviseur and Censeur *Paramètres*
   menus and the Surveillant menu): three blocks — *Retards et absences* (late threshold, justification
   deadline, alert hours), *Barème de conduite* (points per absence hour, per late, per sanction type, with a
   worked example « 6 h non justifiées, 2 retards, 1 avertissement → 14,5/20 » recomputed live), *Sanctions
   utilisées* (one switch per type). Empty fields read « jamais » / « à tout moment ».
7. Roll call (`RollCall`, used by the attendance page and « Ma journée »): choosing « Retard » shows an optional
   « min » field next to the student.
8. Absences page (`/school/absences`): « Délai dépassé » tag on late unjustified absences; flagged students
   show « n h ».
9. Sanction entry forms (class discipline page, and KLM4) offer only the types in use; existing records keep
   their type.
10. Strings through gettext (FR and EN).

Out of scope: blocking justification after the deadline, parent alerts (R03), using `exclusion_absence_hours`
for anything new.

## KLM3 — Suggested conduct mark (spec)

Status: implemented 2026-10-06 (branch `klm3-conduct-suggestion`, plan
`docs/superpowers/plans/2026-10-06-klm3-conduct-suggestion.md`); no visual check done.

Mockup: `Espaces par rôle` → SG → « Conduite ». Gap: **V05**.

User decisions (2026-10-02): the scale is **points per sanction type** (KLM2); the mark starts at 20 per
séquence, only unjustified absences cost points.

Existing code: `ConductMark` (one per enrolment × séquence, `value` 0..20, `:set` upserts, `:conduct` axis);
`Discipline.set_conduct_mark/4`, `class_discipline/3`; `Attendance.class_conduct/…`; sanctions per enrolment
in a date range.

### Computation

1. Pure `Academics.ConductSuggestion.suggest/2` (no database): given a student's séquence facts
   (`unjustified_hours`, `retards`, sanction types) and the scale, returns `20 − hours × p_hour − retards ×
   p_late − Σ sanction points`, clamped to 0..20, rounded **down** to the nearest 0.25, plus the itemised
   deductions.
2. `Discipline.conduct_sheet/3` (scope, class, séquence) loads for every enrolment of the class: the séquence's
   attendance totals (KLM2 rule 3), its sanctions (by `date` within the séquence dates), the current
   `ConductMark` and the suggestion — one query per kind, not per student.

### Screen

3. **« Conduite »** (`/school/conduct`; `:conduct` axis, admins read; in the Surveillant menu, and the
   Proviseur and Censeur *Vie scolaire*): class picker (usual order) and séquence picker (default: current
   séquence). Table: student, h non justifiées, retards, sanctions (chips with their points), **proposée**,
   actuelle, and an input pre-filled with the current mark, else the suggestion. A row whose input differs
   from the suggestion shows « ajustée ». A row's deductions open on tap.
4. « Valider la classe » saves every row with an input value through `set_conduct_mark` in one transaction,
   then shows « n notes de conduite enregistrées ». « Appliquer les propositions » refills every input with
   its suggestion.
5. A closed séquence keeps working (conduct marks are not under the D3 lock); a closed year (KLM9) is read
   only.
6. Strings through gettext (FR and EN).

Out of scope: per-trimester entry (trimester and year conduct stay means of séquences), automatic saving of
suggestions.

## KLM4 — School-wide sanctions page (spec)

Status: implemented 2026-10-06 (branch `klm4-7-sanctions-classes-header-roles`, plan
`docs/superpowers/plans/2026-10-06-klm4-7-sanctions-classes-header-roles.md`); no visual check done.

Mockup: `Espaces par rôle` → SG → « Sanctions ». Gap: **L1** (V06 parents-notified tracking already exists).

Existing code: `SanctionEntry` (`type`, `date`, `reason`, `duration_days`, `parents_notified_on`,
`parents_notified_by_user_id`), actions `:mark_parents_notified`, reads `:recent`, `:parents_to_notify`;
`Discipline.add_sanction/…`, `delete_sanction`; per-class discipline page.

### Screen

1. **« Sanctions »** (`/school/sanctions`; `:conduct` axis, admins read; Surveillant menu, rail badge = parents
   to notify): active year's sanctions, newest first, paginated (50); filters class, type, « À notifier ».
   Columns: student, class, type, date, reason, parents (« notifiés le … » or « À notifier »).
2. **Quick entry** at the top: student search (same search as KLM1's list), type chips (types in use, KLM2),
   duration in days for an exclusion temporaire, optional reason, date (default today) → « Enregistrer »,
   through `add_sanction`.
3. **Detail panel** for the selected row: student (link to the profile), class, type, date, duration, reason,
   issued by; main guardian's name and phone(s) as `tel:` links, « Aucun contact » with a link to the profile
   otherwise; « Marquer les parents notifiés » (existing action); « Supprimer » with confirmation.
4. The class discipline page is unchanged.
5. Strings through gettext (FR and EN).

Out of scope: messages to parents (R03), printing a sanction notice.

## KLM5 — Class size, naming rule, enrolment counts (spec)

Status: implemented 2026-10-06 (branch `klm4-7-sanctions-classes-header-roles`, plan
`docs/superpowers/plans/2026-10-06-klm4-7-sanctions-classes-header-roles.md`); no visual check done.

Gaps: **M4** (the two fields not yet built: maximum class size, class naming rule — the short school name
already exists, and J2 built statutory hours and one form master per class) and **R05** (dashboard counts).

User decision (2026-10-02): the maximum class size is a **warning, never a block**.

Existing code: `SchoolProfile.short_name`, `statutory_hours`; `ClassGroup` (`label`, level, série, per year);
`DashboardLive` counts with one roster query per class (`dashboard_live.ex:179`).

1. `SchoolProfile` gains `max_class_size` (integer 1..200, nullable = no limit) and `class_suffix` (enum
   `:letters | :numbers`, default `:letters`), admin axis, in the *Classes* block of the settings page.
2. `ClassGroup` gains an aggregate `enrollment_count` (enrolments of the class). The dashboard, the class list
   and the class page load it instead of reading rosters; the dashboard total is one query.
3. Over the limit, the class list and class page show « 68 / 60 » in the warning colour; enrolment and CSV
   import still succeed and show « La classe dépasse l'effectif maximum (60) ».
4. The add-class form proposes the next free label for the chosen level from the suffix rule (« 6e C » after
   6e A and 6e B; « 6e 3 » with numbers). The label stays editable.
5. Strings through gettext (FR and EN).

## KLM6 — Official header, signature and stamp (spec)

Status: implemented 2026-10-06 (branch `klm4-7-sanctions-classes-header-roles`, plan
`docs/superpowers/plans/2026-10-06-klm4-7-sanctions-classes-header-roles.md`); no visual check done.

Mockup: `Paramètres école` → *Établissement*. Gap: **S04**.

Existing code: `BulletinTemplate.official_lines/1` (fixed: République du Cameroun, Paix – Travail – Patrie,
ministry, regional and departmental delegation from the profile), `school_lines/1`; logo upload
(`settings_live.ex`, `SchoolLogoController`); I5 template elements with on/off switches.

1. `SchoolProfile` gains `official_header_lines` (list of strings, max 6, each ≤ 120 characters; nil = today's
   generated lines) and `signature_path`, `stamp_path` (stored like `logo_path`). Head axis.
2. `official_lines/1` returns the saved lines when set, else today's generated ones.
3. *Établissement* settings: « En-tête officiel » — the lines pre-filled with the generated ones, edit, reset
   to default; « Signature du chef d'établissement » and « Cachet » — upload (PNG or JPEG, ≤ 1 MB), preview,
   remove. Served by the logo controller (`/school/logo?kind=signature|stamp`), members only.
4. I5 template gains « Signature » and « Cachet » elements (on by default, shown only when an image exists),
   printed in the head's signature block; the template preview shows them.
5. Strings through gettext (FR and EN).

Out of scope: signatures of other roles, signing council minutes.

## KLM7 — Rights matrix, read only (spec)

Status: implemented 2026-10-06 (branch `klm4-7-sanctions-classes-header-roles`, plan
`docs/superpowers/plans/2026-10-06-klm4-7-sanctions-classes-header-roles.md`); no visual check done.

Mockup: `Paramètres école` → *Rôles*. Gap: **S06**.

Existing code: `SchoolRole` (eight roles) and `SchoolRole.axis/1` (`:member`, `:admin`, `:head`, `:conduct`,
`:fees`), used by every policy as `{Checks.SchoolRole, any_of: axis}`; row-level rules (form master, a
teacher's own courses).

1. `SchoolRole.rights/0`: one list of `%{key, label, axis, note_by_role}` in plain words (saisir les notes de
   ses cours, valider les corrections, gérer la discipline et la conduite, frais et paiements, paramètres de
   l'école, membres et invitations, emploi du temps, bulletins et conseils de classe, affectations). `note_by_role`
   carries row-level nuances (« ses cours », « sa classe » for a form master).
2. A test asserts every `axis` in `rights/0` is one of `axis/1`'s axes and that each right's axis matches the
   axis used by a named policy (one representative action per right).
3. **« Rôles et droits »** (`/school/settings/roles`; admin axis; *Paramètres* menus): table rights × roles,
   ✓ or the note; a line « Les droits suivent le rôle ; ils ne sont pas modifiables pour l'instant. »
4. Strings through gettext (FR and EN).

Out of scope: editing rights.

## KLM8 — Staff in-app notifications (spec)

Status: implemented 2026-10-06 (branch `klm8-notifications`, plan
`docs/superpowers/plans/2026-10-06-klm8-staff-notifications.md`); no visual check done.

Gaps: **R03** (staff part only) and **N06** (reminders to teachers late with marks).

User decisions (2026-10-02): **in-app only, staff only**; parent messages and SMS wait for a provider; no
per-school message templates.

Existing code: D3 `MarkCorrection` request / approve / refuse; F's sequence tracking `/school/sequences`
(`EntryProgress.grid`); rail badges (`Spaces.counts/2`); no notification resource.

### Data

1. **`Notification`** (Accounts domain, tenant-scoped): `recipient_user_id`, `kind` (enum
   `:correction_requested | :correction_decided | :entry_reminder`), `params` (map of short strings for the
   text), `link` (path), `read_at`, timestamps. Read and mark-read by the recipient only; created only through
   `Notifications.deliver/2` (`authorize?: false` inside, like `Mark.Journal.record!/2`).
2. `Notifications.deliver(kind, recipients, params, link)` inserts one row per recipient and broadcasts on
   `"notifications:<user_id>"`. It is the single place a future e-mail or SMS channel plugs into.
3. **`EntryReminder`** log: course, séquence, sent by, `inserted_at`; at most one per course × séquence × day
   (identity on a date column).

### Triggers

4. A correction request notifies every member holding `:head` or `:vice_principal`; a decision notifies the
   requesting teacher, with the decision.
5. « Relancer » on a lagging course of the sequence tracking grid (and « Relancer tous les retards » for the
   séquence) records an `EntryReminder` and notifies the course's teacher(s): « Saisie en retard : <matière> ·
   <classe> · <séquence> ». The grid cell shows « relancé le … ». A second reminder the same day is refused
   quietly.

### Screens

6. A bell in the app header with the unread count (live through PubSub); its menu shows the 8 newest; « Tout
   voir » opens **`/school/notifications`** (all members): list newest first, unread in bold, « Tout marquer
   comme lu »; opening one marks it read and follows its link.
7. Strings through gettext (FR and EN); the text is built at display time from `kind` and `params`, so it
   follows the reader's language.

Out of scope: parent messages, e-mail and SMS delivery, message templates, notification preferences.

## KLM9 — Next school year and closed years (spec)

Gap: **M1**. No mockup.

User decisions (2026-10-02): carry over **classes, courses and teacher assignments** (with form masters) as an
editable starting point, **not** the timetable; the old year becomes **closed, read only**, with no reopening.

User decisions (2026-10-06): one branch, tasks grouped **9a** (closed years and the lock) → **9b** (starting
the next year) → **9c** (viewing past years); a student's decision is the annual council's choice **or else
the engine's proposal**; **payments stay open** on a closed year (arrears), fee tranches and adjustments are
locked; teachers' **planning is locked** with the rest.

Existing code: `AcademicYear` (`name`, `start_date`, `end_date`, `active`; `:activate` deactivates the
others; one active year per school = `scope.current_academic_year`); `ClassGroup` per year
(`form_master_user_id`); `TeachingContext` (course) and `CombinedCourse` per year; `Enrollment`
(`status :inscription | :reinscription`, `repeater`); passage decisions on `CouncilDecision.passage_decision`
(`:admis, :admis_rachat, :redouble, :exclu`) with the engine's proposal from `PassageRules.propose/2`
(`Councils.outcomes/3`); `Reference.default_calendar_preset/2` (3 trimesters × 2 séquences); D3's
`Mark.AssessmentOpen` / `Assessment.SequenceOpen` validations; nothing copies a year. Most class pages read
the calendar of `scope.current_academic_year`, not of the class's own year.

### 9a — Closed years and the lock

1. `AcademicYear` gains `status` (enum `:open | :closed`, default `:open`). A closed year cannot be
   activated, updated or destroyed (no reopening).
2. **`YearOpen`** validation (pattern of D3's `AssessmentOpen`): each year-bound resource declares the path to
   its year (e.g. `path: [:class_group]`, `path: [:sequence, :term]`); on create, update and destroy it reads
   the first step's foreign key from the changeset (or the record), loads that record's year and refuses a
   closed one with « L'année <nom> est clôturée. ». A record moved between two parents (an enrolment changing
   class) is checked against both. Generic actions are covered through the create, update and destroy actions
   they call.
3. Covered: every resource of the year, directly or indirectly — terms and séquences, classes, enrolments,
   courses, combined courses, subject exemptions, assessments, marks, mark corrections (request and
   decisions), entry reminders, attendance, sanctions, conduct marks, councils and decisions, bulletin
   publications, holidays, timetable slots, fee tranches and fee adjustments, progression plans, modules,
   entries, lesson plans, lesson steps and teaching-log entries.
4. Not covered: **`Payment`** (arrears are cashed after the year), `MarkCorrection :mark_seen` (a read
   receipt), `MarkEvent` (the journal) and everything school-wide (students, guardians, subject catalog and
   coefficient grid, periods, school profile, memberships, notifications).
5. A test lists every resource whose data belongs to a year and fails when one of its create, update or
   destroy actions lacks `YearOpen` (exceptions of rule 4 named in the test).
6. *Paramètres → Année* loses the free « créer une année » and « activer » controls: a new year is started
   only through rule 10. The setup wizard still creates the very first year.

### 9b — Starting the next year

7. `TeacherAssistant.Academics.NewYear` builds a **plan** from the open year (pure, used by the screen and the
   action). Per class: new label (default: the same), **admis target** and projected size. Default admis
   target: the class of the next level (level order, as in `level_rank`) with the same série and the same
   suffix — the label's last word when it is letters or a number (« 6ème A » → A, « 3e 2 » → 2; KLM5's
   `class_suffix`), no suffix otherwise; none when no such class exists (last level, or no next level in the
   school) — the admin then picks a class or « Ne pas réinscrire ».
8. **Placement** from each student's decision = the annual council's choice, else the engine's proposal:
   - `:admis` and `:admis_rachat` → the class's admis target; not re-enrolled when the target is « Ne pas
     réinscrire »;
   - `:redouble` → the copy of the same class;
   - `:exclu`, or no decision (no proposal either) → not re-enrolled.
   Each not re-enrolled student keeps a reason for the summary. Projected size of a new class = its repeaters +
   the admis of the classes targeting it, shown against `max_class_size` (warning only).
9. Generic action `AcademicYear.start_next_year` (head and vice_principal; `Organization.start_next_year/2`),
   **in one transaction**, in this order: creates the new year (inactive) with the default calendar and the
   prefilled national holidays; recreates each class (label, level, série, form master), its courses
   (subject, coefficient, weekly hours, teacher) and the combined courses joining them; creates the enrolments
   (`status: :reinscription`, `repeater: true` for repeaters); then closes the old year and activates the new
   one. The old year is read under a row lock: a second run fails (« déjà clôturée »). Any failure rolls
   everything back.
10. Not carried over: timetable, holidays (beyond the national prefill), subject exemptions, fee tranches and
    adjustments, councils, bulletins. A course whose teacher left the school is copied as is.
11. **« Préparer l'année suivante »** (`/school/settings/new-year`; head and vice_principal; link from
    *Paramètres → Année*), four steps, the plan held in the LiveView (no draft saved):
    1. *Vérification*: classes whose annual council is not closed, students whose decision is only a proposal
       (count per class), courses of teachers who left the school, a warning when today is before the year's
       end date. Never blocking.
    2. *Nouvelle année*: name (« 2025-2026 » → « 2026-2027 »; empty when the name has another form), start and
       end dates (default: the old ones + 1 year).
    3. *Classes*: one row per class — new label (editable), admis target (select), projected size against
       `max_class_size` (warning colour above it).
    4. *Confirmation*: classes created, students re-enrolled, of which repeaters, not re-enrolled (by reason);
       « Démarrer l'année 2026-2027 », then a redirect to `/school/classes` (the new year).

### 9c — Viewing past years

12. *Paramètres → Année* lists the years: the open one with « Préparer l'année suivante », each closed one with
    « Consulter » → **`/school/years/:id`** (admins): its classes, each linking to its results page and to
    its printed bulletins.
13. The results page, the student bulletin page and the bulletin print controllers read the calendar
    (séquences, terms) of the **class's own year**; `ReportCards` access rules (teacher of the class, form
    master) are checked against that year too. On a closed year they show « Année <nom> · clôturée » and no
    edit or publish controls; a published bulletin keeps showing its snapshot.
14. The student profile (KLM1) links each past enrolment to its bulletin.
15. Strings through gettext (FR and EN).

Out of scope: copying the timetable, holidays, fee tranches or planning; moving single students during the
wizard; reopening a closed year; a general year switcher (register, discipline, fees, class and council pages
stay current-year pages, protected by the lock); archiving files.

## Holes found on 2026-10-01 (not yet specified)

Found by comparing the app's routes with every claude.ai/design screen and with `Écarts avec le code`.
Each needs a spec before a plan.

### L — School life, rest

Specified 2026-10-02 in §K, L, M (KLM1–KLM4).

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

Specified 2026-10-02 in §K, L, M (KLM1, KLM5, KLM9).

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
