# Audit follow-ups — design (2026-11-10)

Source: the audit of main `65c5f3d` run on 2026-11-10 (four passes: features,
code, performance, security/ops) and the conversation that followed on mark
entry, roll call across back-to-back hours, the teacher's tabs and the
statistics teachers copy into their pedagogical documents. This document turns
those findings into increments to implement one after the other, each on its
own branch with its own tests, as usual. Memory of the audit itself:
`project-audit-2026-11-10` (findings not fixed yet).

## Intent

Three things at once:

1. **Close the holes that can hurt a real school now** — vulnerable
   dependencies, the two hot paths that will fold under a 1500-student school,
   and the gaps in operations (health check, impersonation attribution, error
   mail content).
2. **Remove friction teachers feel every day** — a roll call retaken for a
   second hour, a course list drawn in three tabs, figures copied by hand from
   eight course pages into a statistics form.
3. **Keep the product honest about data it holds on children** — a departure
   state instead of destroying history, and a written retention policy.

The larger product gaps (school papers, MINESEC statistics page, exports,
parent SMS, conseil de discipline, coverage, HOD screens) are listed at the end
as candidates for their own specs; this document builds only the pieces that
unblock them (the departure state, the per-sex aggregates).

## Goals, non-goals, anti-goals

Goals: every increment ships alone, keeps the 2,475 tests green, adds its
own, and is visible in the browser (phone first) before merge.

Non-goals: mobile money, payroll, parent portal, offline mode (user,
2026-11-10); half-class lessons (deferred 2026-11-09); the syllabus library.

Anti-goals: a figure on a teacher's statistics print that differs from the
bulletin; a second hour's roll call that silently copies a first hour the
teacher never took; an index or bulk write that changes what a refused row
does (all-or-nothing stays).

## Order of increments

| # | Increment | Size | Depends on |
|---|-----------|------|-----------|
| A1 | Dependencies, precommit flag, health endpoint | S | — |
| A2 | Roll call for back-to-back hours + bulk write | M | — |
| A3 | Head's dashboard and bulletin status without row loads | M | — |
| A4 | Teacher statistics (séquence / trimester / year, print) | M | — |
| A5 | Teacher tabs: Bulletins folded into Mes cours, « Ma classe » | M | A4 (links) |
| A6 | Operations: impersonation attribution, error mail, CSP, cookie | S | — |
| A7 | Departure state instead of destroy on withdraw | M | — |
| A8 | Smaller performance items (double load, websocket compress, T3 recompute, indexes) | S–M | A3 |
| A9 | Data retention policy and orphan photo sweep | S | A7 |

A1, A2, A3, A4, A6, A7 are independent and could run in parallel worktrees;
the table is the suggested order by value. A5 after A4 because the course row
in Mes cours links to the statistics.

---

## A1 — Dependencies, precommit flag, health endpoint

**Why.** `mix hex.audit` (2026-11-10): `ash_sql 0.8.5` retired for a query
cache bug with unpredictable rows (in a multi-tenant app this is a leak class),
`ecto 3.14.2` CVE-2026-118391 (query cache growth from `in ^ids`, which the
app uses widely), `assent 0.2.13` CVE-2026-117656 (Apple sign-in, unreachable:
only password and magic link are configured). `mix precommit` has
`--warning-as-errors` (singular, ignored) at `mix.exs:131`. No `/health`
although `docs/DEPLOY.md` speaks of health checks.

**What.**

- `mix deps.update ash_sql ecto assent` (ash_postgres allows ash_sql
  `>= 0.8.4`); full suite; `mix hex.audit` clean.
- `precommit` alias: fix the flag; add `hex.audit` to it so the audit gates
  every commit. If the fixed flag surfaces warnings, fix them in the same
  increment.
- `GET /health` in the router, outside every pipeline that needs a session:
  runs `SELECT 1` through the Repo, answers `200 {"status":"ok"}` or `503`.
  No authentication, no body beyond that, nothing about versions. Documented
  in `docs/DEPLOY.md` with the UptimeRobot / Hetzner check pointing at it.

**Tests.** A controller test for `/health` (200 with the DB up). The suite is
the test of the upgrade.

---

## A2 — Roll call for back-to-back hours, bulk write

**Today.** `LessonGroups.number_hours/1` already numbers a lesson that follows
the same course back to back (« 2e heure » in Ma journée). But
`RollCall.open/4` → `put_students/4` starts every roll not yet taken from
« all present »; the second hour knows nothing of the first. The teacher
re-taps every absent and late student and saves twice. The save itself,
`Attendance.record_period/7` (`attendance.ex:374-396`), loops `Ash.create`
per student inside one transaction: ~3–4 queries per row (year-open check,
teacher expr policy, upsert), ~300 queries for a class of 80.

**Behaviour.**

1. **Save for the following hours at the first.** When the teacher validates
   the roll of hour *n* and the same lesson unit (solo context or combined
   course, same member classes) continues at hour *n+1* (and *n+2*…), the
   validation bar shows a checkbox « Aussi pour la 2e heure » (plural when
   more), **checked by default**. On « Valider l'appel », the entries are
   written for every checked period in one transaction. Ma journée then shows
   those lessons as done. The checkbox appears only for periods whose roll is
   not taken yet; a later hour already taken is never overwritten from an
   earlier one.
2. **Prefill the second hour from the first.** Opening hour *n+1* when its roll
   is not taken and hour *n* of the same unit on the same day is taken: the
   roll starts from hour *n*'s statuses and late minutes (a late at hour 1 is
   **present** at hour 2 — the student is in the room; only absences and
   « sent home » carry over). The panel says « Pré-rempli depuis la 1re
   heure » and `taken?` stays false until the teacher validates. Opening hour
   *n+1* when hour *n* was not taken behaves as today (all present).
3. **Change a few, validate.** Nothing else changes in the panel: the teacher
   toggles who left or arrived and validates.
4. **Data model unchanged.** One `AttendanceEntry` per student per period, as
   today, so the surveillant's day grid, the register, typed absence hours and
   the paper sheet are untouched.

**Where.**

- **Adjacent hours are found from the class's timetable, not the teacher's
  lessons**, so both pages share one computation: `RollCall.open/4` already
  resolves the `TimetableSlot` of (class, date, period) (`roll_call.ex:225`);
  it also reads the slots of the neighbouring periods of that class on that
  weekday and keeps those with the same teaching context (or the same
  combined course). The previous adjacent slot, when its roll is taken, is
  `roll.prefilled_from`; the following adjacent slots whose roll is not taken
  are `roll.following`. (Ma journée's `LessonGroups.hour` stays what it is: a
  label.) The prefill applies on both Ma journée and the surveillant's
  `AttendanceLive`; the checkbox « aussi pour la 2e heure » is shown on **Ma
  journée only** (the surveillant takes one period at a time by design).
- `RollCall.record/2` takes the chosen periods; `Attendance.record_period/7`
  and `record_combined_period/5` (`attendance.ex:252`) accept a list of
  periods and write them in one transaction.
- The per-row loop becomes `Ash.bulk_create(entries, AttendanceEntry, action,
  upsert?: true, upsert_identity: :unique_mark, return_errors?: true,
  stop_on_error?: true, transaction: :all)` — one `INSERT … ON CONFLICT` per
  period. `YearOpen` is today a validation (`year_open.ex:13`), which has no
  batch callback: it becomes a change with `batch_change/3` that resolves the
  year once per batch (its other call sites keep working since a change can
  validate too), or the year-open check moves to `record_period` before the
  batch. The teacher-ownership policy on `:record` moves to a pre-check on
  the teaching context (the context is the same for the whole batch) so no
  per-row filter query remains. All-or-nothing is kept: any refused row rolls
  the whole save back, with the same error mapping as today (`:forbidden`,
  `:unverified`, `:failed`).

**Tests.** `attendance_live_test` / a new `my_day_two_hours_test`: validating
hour 1 with the box checked writes hour 2; unchecked writes hour 1 only;
hour 2 already taken is not touched; opening hour 2 after hour 1 prefills
absences, not lates; `taken?` false until validated; a combined course across
two hours. `attendance_test`: bulk write refuses the batch when one row is
refused; query count of a save bounded (assert with `Ecto` telemetry or
`Repo` log capture, ≤ 10 queries for 80 students).

---

## A3 — Head's dashboard and bulletin status without row loads

**Today** (`dashboard_live.ex:550,570`, `entry_progress.ex:276`,
`academics/school_life.ex:292-372` behind the `Attendance.absences_to_justify`
delegate at `attendance.ex:95`, `report_cards.ex:784`): the head's home page loads
every mark of the séquence (~36k structs for 1500 students) to compute entry
percentages, loads every unjustified absence of the séquence with class,
student and guardian preloaded only to count them, and reads every published
`BulletinPublication` **with its snapshot** to get class ids.

**What.**

- `EntryProgress.grid/…`: never the rows. It needs three things per
  assessment today — the count of marks among the students taking the
  subject (`entry_progress.ex:303`), and `last_entry_at` = max `updated_at`
  (`:317`, shown on the Suivi page). So: one grouped query per séquence
  (`Ash.Query` with `group_by`-style aggregates through `Ash.aggregate`, or
  `count` + `max` aggregates on `Assessment` filtered on the students'
  enrollment being current) returning `{assessment_id, count, max_updated}`.
  Same numbers as today (tests compare against the current implementation
  on the demo seed before the swap).
- `SchoolLife.absences_to_justify/2` and `unjustified_hours/…`: `Ash.count`
  with the same filters; the flagged-students figure via a `count` with
  `distinct` on enrollment or one select of `enrollment_id` only. The nested
  loads stay only where rows are rendered (`/school/absences`,
  `/school/day`), and those two pages paginate or `stream/3` the rows (50 at
  a time, « Afficher plus »).
- `ReportCards.published_class_ids/2` and every status check
  (`current_publication`, `Councils.held?`, `prior_terms`): a `:current` read
  action selecting everything but `snapshot`; the snapshot is loaded only in
  `class_view` and the print. Within one `bulletins_live` load the fetched
  publication is passed down instead of re-read.

**Tests.** Existing dashboard, absences and bulletins tests keep passing; add
a query-count assertion on the dashboard mount for a seeded school (bounded,
e.g. ≤ 40) and a unit test that `published_class_ids` does not select
`snapshot`.

---

## A4 — Teacher statistics: séquence, trimester, year, printable

**Why.** Teachers fill a *fiche de statistiques* per séquence and per
trimester (effectif, garçons/filles, notés, moyenne, taux de réussite,
extrêmes, mentions) for the censeur, the HOD and the conseil d'enseignement.
Today `Teacher.MarksSummaryLive` gives these per séquence for one course, on
screen only; nothing for a trimester or the year, nothing across courses,
nothing to print. The figures exist in `Marks.summarize/4` and, for terms, in
the bulletin computation.

**Behaviour.**

1. **Period chips on Résultats.** The course's Résultats page gets, after the
   séquence chips, « Trim. 1 », « Trim. 2 », « Trim. 3 » and « Année ». A
   trimester or year view shows the same three figures, distribution, by-sex
   pass rate, mentions and ranking, computed **with the school's averaging
   rules exactly as the bulletin does** (reuse the per-subject term and
   annual averages of `ReportCards`, not a new formula). **When the period is
   published for that class, the figures are read from the published
   snapshot** (`ReportCards.current_publication`, `report_cards.ex:155`), so
   they equal the printed bulletin even after later corrections; an
   unpublished period is computed live and labelled « provisoire ». A period
   whose séquences have not all started shows « en cours » and computes on
   what exists.
2. **« Mes statistiques » page** at `/school/statistics/me` (menu entry in the
   teacher space under Enseignement; from the course row in Mes cours and from
   Résultats): one table, a row per course (combined course as one row, plus
   one sub-row per member class), columns: effectif, G, F, notés, moyenne,
   réussite %, réussite G %, réussite F %, min, max, and the mentions counts
   folded under a « + » on phones. A period selector (séquence / trimester /
   year) at the top, current séquence by default.
3. **Print.** « Imprimer » on that page → `GET /school/statistics/me/print
   ?period=…`, A4 portrait, the school's official header (as the relevé),
   title « Statistiques — <teacher> — <period> », the table, signature line.
   One page per ~25 rows. Builder's call on landscape when a teacher has many
   courses.
4. **Not in this increment.** CSV (no CSV anywhere yet; a separate decision),
   median/standard deviation (no Cameroonian formula attested; doc 04 §6),
   coverage rate (no cahier de textes), the HOD cross-teacher table (listed as
   a candidate below, same aggregates).

**Where.** A `TeacherAssistant.Academics.TeacherStatistics` module returning
`%{course, class, period, headcount, boys, girls, graded, average, pass_rate,
pass_rate_by_sex, lowest, highest, mentions}` rows for a teacher and a period,
built on `Marks.summarize/4` for séquences and on the bulletin's term/annual
per-subject averages for trimesters and the year; `Teacher.StatisticsLive`;
`StatisticsPrintController` following `MarkSheetPrintController`. Policies:
a teacher sees their own courses only (the teaching-context ownership already
enforced in `Curriculum.fetch_assigned_teaching_context`); the head and the
censeur may open any teacher's page with `?teacher=` (same as
`ReportCards.can_publish?`).

**Tests.** Unit: a trimester figure on the statistics page equals the
subject average on the published bulletin for the same students (same
fixture). LiveView: chips, selector, a combined course as one row, another
teacher's page refused, the print renders every row.

---

## A5 — Teacher tabs: Bulletins folded into Mes cours, « Ma classe »

**Today** (`spaces.ex:364`): the teacher's phone tabs are Ma journée, Mes
cours, Bulletins, EDT, Plus. The teacher view of Bulletins
(`bulletins_live.ex` `mode: :teacher`) shows period tabs, the step timeline
(séquence deadlines with J-n, councils, publication), the teacher's courses
with per-séquence progress (a copy of Mes cours), and the classes already
published. The course list is thus drawn in three tabs.

**What.**

- Tabs become **Ma journée · Mes cours · EDT · Plus**, and when the teacher
  is a professeur principal **Ma journée · Mes cours · Ma classe · EDT ·
  Plus** (« Ma classe » = the class page of their form-master class; with
  several classes it opens the Classes list filtered to theirs). This is the
  tab bar of the *enseignant space*; a head who teaches keeps the proviseur
  bar in the proviseur space and gets this one when they switch to the
  enseignant space (`Spaces.keys_for/1` already yields both).
- **Mes cours** gains, above the course rows, the period timeline from the
  Bulletins teacher view (trimester pills, the steps with J-n and states),
  collapsed to its current step on phones with a tap to open. The course row
  keeps its séquence state and gains a small « Stats » link (A4).
- **Published bulletins** for a teacher: the Bulletins teacher page is
  removed; a teacher reaches a published class view from Ma classe (form
  master) or from the notification of publication (kind already exists),
  which links to `/school/bulletins?class=…` as today. The route stays, the
  menu entry for plain teachers goes to « Plus » only if they have at least
  one published class to read; the user may drop even that (open question).
- Proviseur and Censeur tabs are unchanged.

**Tests.** `spaces_test`: tab specs for a teacher, a form master, a head who
also teaches. `courses_live_test`: timeline rendered, current step first on
phone width. `bulletins_live_test`: teacher without `?class=` is redirected
to Mes cours; with a published `?class=` still readable.

---

## A6 — Operations: impersonation attribution, error mail, CSP, cookie

- **Impersonation attribution.** Writes made while impersonating carry the
  operator. `Scope.impersonation.operator.id` is stored as
  `operator_user_id` (nullable, no FK across tenants; the operator is a
  global user) next to **every actor-stamped column**: `MarkEvent`,
  `Payment.recorded_by_user_id` and `cancelled_by_user_id`,
  `SanctionEntry.issued_by_user_id` and `parents_notified_by_user_id`,
  `AttendanceEntry.recorded_by_user_id`, `AuditEvent`. One shared Ash change
  `StampOperator` sets it from the scope on those actions. The school's
  journal shows « par <membre> (opérateur X) ». Migration via
  `mix ash.codegen --dev`.
- **Operator error e-mail** (`accounts/emails.ex:49`): the body carries
  `kind`, `source`, time and the link to `/admin/errors/<id>`; the reason
  text stays in the tracker only (the Telegram text already does this).
- **CSP.** `put_secure_browser_headers` with `content-security-policy`:
  `default-src 'self'; img-src 'self' data: blob:; style-src 'self'
  'unsafe-inline'; script-src 'self'; connect-src 'self' wss:`. Colocated
  hooks are already compiled into app.js and `root.html.heex` carries only
  the external script tag, so no nonce is needed unless a page inlines a
  script (none found); `style-src 'unsafe-inline'` stays for LiveView's
  inline styles. Verified page by page in the browser (prints, QR images as
  `data:`, photo uploads as `blob:`).
- **Cookie.** `encryption_salt` on the session (`endpoint.ex`); existing
  sessions are invalidated once at deploy — announced in the release notes.
- **LiveDashboard RequestLogger** plug removed from the prod endpoint.

**Tests.** Impersonated payment and mark show the operator id; e-mail body
has no `reason`; a request to `/school` carries the CSP header; CSP smoke
test on the five print routes (no console errors — browser check).

---

## A7 — Departure state instead of destroy on withdraw

**Today** (`enrollment.ex:731`): « Retirer » destroys the `Enrollment`;
composite FKs cascade attendance, conduct marks and fee adjustments
(`20260925140302_tenant_composite_fks.exs`). A student who leaves mid-year
loses their history; no exeat or transfer can ever be issued; the « delete a
mistaken student » path (2026-11-09) uses the same destroy.

**What.**

- **Departure is its own pair of fields, not a status.** `EnrollmentStatus`
  already records inscription vs réinscription (printed on bulletins and
  sheets) and must keep that fact. `Enrollment` gains `left_on` (date, nil
  while enrolled) and `departure_reason` (Ash enum `transfer | dropout |
  exclusion | other`, nil while enrolled). A new action `:leave` sets both
  (`left_on` defaults to today) plus an optional `departure_note` (short
  text). Policy: the `:admin` axis, as destroy today.
- **Destroy stays** only for the mistaken-student case: allowed while the
  enrollment has no attendance entry, no mark, no payment, no fee paper and
  no sanction. The existing `student_deletion_blocker/2`
  (`enrollment.ex:260-275`) checks marks and fee papers on the *student*;
  it is extended to attendance entries and sanctions and reused by the
  drawer, which offers « Supprimer (erreur de saisie) » only then and
  « Marquer parti » otherwise.
- **Period rule** (confirmed by the user, 2026-11-10): a departed student stays
  in every séquence and trimester **whose first day is before `left_on`**,
  with « parti le … » under the name on the bulletin, and is out of any
  period starting on or after `left_on`. So a student who leaves mid-séquence
  keeps that séquence's bulletin and counts in its averages and ranks. Roll
  calls and mark grids exclude the student from `left_on` itself (day
  granularity): `:current_on` on `Enrollment` compares `left_on` to the day
  for rosters and to the period's first day for results. Headcounts of a
  period follow the same rule. Élèves page: a « Partis » filter pill; the fee
  account closes with the balance as it stands (no automatic refund or
  arrears — the bursar handles it); passage decisions skip them.
- A departed student may **return**: a new enrollment in the same year is
  refused while a departed one exists; `:return` clears `left_on`,
  `departure_reason` and the note. Status is untouched.

**Where.** `Enrollment` (two attributes, `DepartureReason` enum),
`Enrollment.withdraw/2` → `leave/3`; every roster read (`list_roster`, `list_students`, `period_roll`,
`class_results_for_period`, `readiness`, `FeeControl`) gets the date rule in
one place: a `:current_on` read argument on `Enrollment` (default today) that
the roster helpers use. Migration via `mix ash.codegen --dev`.

**Tests.** Leave then: roll of a later day excludes, roll of an earlier day
includes; bulletin of the earlier séquence keeps the student and later
excludes; Élèves « Partis » pill; destroy refused with history; return
re-includes; another school cannot mark a departure (cross-workspace guard).

---

## A8 — Smaller performance items

Each is small and independent; group them in one branch after A3.

- **Double load on mount.** The six heaviest LiveViews (`Teacher.MarksLive`,
  `BulletinsLive`, `SequenceTrackingLive`, `DashboardLive`, `DayLive`,
  `StudentsLive`) skip their data loads when `not connected?(socket)` and
  render a skeleton; `handle_params` loads on the connected pass.
- **Websocket compression.** `socket "/live", …, websocket: [compress: true, …]`
  in `endpoint.ex`.
- **Marks grid.** `assign_pending` computed from the in-memory `loaded` map
  instead of re-reading the column after each save; the rows get
  `phx-update="ignore"`-free keyed comprehension already; measure the diff
  size of one save on a 100-student class before and after (LiveDebugger),
  and only move to `stream/3` if a save still ships more than ~2 KB.
- **T3 recompute.** `ReportCards.live_view/3` calls
  `Assessment.class_subjects_by_sequence` (`assessment.ex:1195`) once for the
  whole year and derives the trimesters and the annual summary from it; `grading_rules` and the school profile fetched once per
  call and passed down.
- **Indexes.** `typed_absences (workspace_id, sequence_id)` and
  `(workspace_id, term_id)`; `mark_events (workspace_id, assessment_id)` and
  `(workspace_id, student_id)`; `attendance_entries`, `payments`,
  `sanction_entries` on `(workspace_id, inserted_at)`. Via `mix ash.codegen
  --dev` from `custom_indexes`.
- **Photos.** The photo URL carries a short hash of the file's mtime or
  content; the controller answers `304` on a matching `If-None-Match` and
  sets `max-age` to a week. Ownership check unchanged.

**Tests.** Mount tests of the six LiveViews still pass (the dead render shows
the skeleton, the connected render the data); snapshot test of the T3 view
unchanged before and after the single-pass computation.

---

## A9 — Data retention policy and orphan photo sweep

- A section « Données personnelles » in `docs/PRODUCT.md` and the privacy
  page stating: student records are kept while the school is active; a
  departed student's record is anonymised (name → « Élève parti », guardians
  removed, photo deleted) **three years** after `left_on` or after the last
  enrolment year's end — a weekly Oban job `AnonymiseDepartedStudents`
  (user's call on the delay; three years is the proposed default).
- A weekly Oban job `SweepOrphanPhotos` deletes files under `UPLOADS_DIR`
  with no matching `Student`/`Workspace` row, logging counts to the operator
  digest.
- User account deletion: a member with no membership left may delete their
  account from « Mon compte » (tokens revoked, e-mail/phone cleared, name
  replaced); a member of a school must be removed by the head first.

**Tests.** Anonymisation only after the delay; sweep leaves referenced files;
account deletion refused with a membership.

---

## Candidates for their own spec (not built here)

Ordered by value to a Cameroonian school, from the feature pass:

1. Certificat de scolarité + register of issued papers (+ exeat, which
   needs A7).
2. MINESEC statistics page (II.1.1, II.1.2; reuses A4's per-sex aggregates).
3. CSV / XLSX export of rosters, marks, fees (and the CarteScolaire template).
4. Parent notification channel (SMS or WhatsApp Business API).
5. Conseil de discipline flow.
6. Minimal cahier de textes per course → coverage rate for councils; revive
   or delete the dead `ProgressionPlan` / `LessonPlan` / `TeachingLogEntry`.
7. HOD screens (conseil d'enseignement table on A4's aggregates); give
   `guidance_counsellor` and `librarian` a purpose or remove them.
8. 240 EN entries identical to their FR msgid — a translation pass.
9. **Roll call outside the timetable** (user, 2026-11-12). Two cases share one
   mechanism: a teacher who teaches a class at another period than the timetable
   says (swap, make-up, replacement), and a teacher who has assignments but no
   timetable at all — today the roll-call page accepts them (`RollCall.open/5`
   falls back to the teacher's own assignment when the period has no slot), but
   Ma journée lists timetable lessons only and the class's « Cahier d'appel » tab is
   for conduct managers, so they have no way in. Minimal shape: an « Autre cours
   maintenant » action on Ma journée (pick one of my classes, today's period),
   recorded under **my** teaching context whatever the timetable holds at that
   period, and the displaced slot marked « cours non assuré » in the same save so
   the surveillant's day stays honest; a teacher without timetable sees their
   classes listed on Ma journée with that action instead of lessons. Not a
   replacement module (the censeur assigning substitutes in advance).

## Calls made in this document (to check while reading)

- A2: the « aussi pour la 2e heure » box is checked by default and exists
  on Ma journée only; lates do not carry over to the second hour; adjacent
  hours come from the class's timetable slots, so the surveillant's page
  gets the prefill too; `YearOpen` becomes a change.
- A3: entry progress keeps `last_entry_at` through a `max` aggregate.
- A4: no CSV in this increment; a published period's statistics come from
  the snapshot, an unpublished one is computed live and marked
  « provisoire »; head and censeur may open a teacher's statistics; median /
  standard deviation left out.
- A5: Bulletins leaves the teacher tab bar; « Ma classe » appears only for
  form masters; the Bulletins teacher page is removed, not hidden.
- A6: `operator_user_id` is a plain column, not a FK, on every actor-stamped
  column; no CSP nonce.
- A7: departure is `left_on` + `departure_reason`, the inscription /
  réinscription status is untouched; destroy is kept for enrollments without
  history (guard extended to attendance and sanctions); the fee balance of a
  departed student is left as is. The mid-period rule (a student who leaves
  mid-séquence keeps that séquence's bulletin) was confirmed by the user.
- A9: three years before anonymisation.
