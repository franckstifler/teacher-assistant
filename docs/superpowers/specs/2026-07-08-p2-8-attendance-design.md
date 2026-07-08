# P2.8 — Attendance & absences (cahier d'appel)

**Status:** Approved design
**Date:** 2026-07-08
**Builds on:** P2.1 (school workspaces, roles, permissions), P2.2 (students / enrollments / TeachingContext), P2.5 (form-master scoped access), P2.6 (bulletin period abstraction), P2.7 (timetable periods & slots)

## Purpose

Let a school run its daily *cahier d'appel*: subject teachers mark who is present /
absent / late in the periods they teach, the **Surveillant Général** (the
`:discipline_master` role) oversees a centralized daily register and manages
justifications, and the resulting **absence hours** (justified vs unjustified) and
**retards** flow onto each bulletin's conduct line — computed exactly from the P2.7
period durations and mapped to the P2.6 bulletin period by date. Conduct is
display-only; it does **not** enter the moyenne générale.

## Scope

In scope:
- A per-student, per-period, per-date attendance record (present / absent / late)
  with a justified flag on absences, tied to the P2.7 timetable periods.
- Two capture surfaces: a subject teacher's roll-call for a period they teach, and
  the SG/admin centralized daily class register.
- A per-student, per-date justification workflow (flip a whole day's absences to
  justified, with an optional note).
- Absence-hour totals (justified / unjustified) + retard counts per bulletin period
  (séquence / trimester / annual), rendered on the bulletin conduct section G.

Out of scope (deferred / YAGNI):
- Sanctions, note de conduite, avertissement / blâme / exclusion — **P2.9**.
- Conduct entering the moyenne générale (KB flags this as unsettled; keep it off).
- Parent notifications / SMS.
- Per-period (rather than per-day) justification.
- Attendance codes beyond P / A / R + the justified flag (AJ / AnJ are derived).

## 1. Data model

One `Ash.Type.Enum` and one resource (Ash 3 house style: `use Ash.Resource,
otp_app:, domain:, data_layer: AshPostgres.DataLayer, authorizers:
[Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`;
`uuid_v7_primary_key :id`; `timestamps()`).

**Enum**
- `TeacherAssistant.Academics.AttendanceStatus` — `[:present, :absent, :late]`
  (P / A / R). "Justified vs not" is a boolean on absent entries; AJ / AnJ are
  derived from `status == :absent` + `justified`.

**`AttendanceEntry`** — one student's mark for one period on one date.
- `belongs_to :enrollment` (`allow_nil? false` — the student×class×year record from
  P2.2), `belongs_to :period` (`allow_nil? false` — the P2.7 bell-schedule period),
  `belongs_to :teaching_context` (`allow_nil? true` — the subject taught that period,
  set from the timetable slot; nullable so an SG register entry for a period with no
  placed slot still records).
- `date` :date (`allow_nil? false`), `status` `AttendanceStatus` (`allow_nil? false`),
  `justified` :boolean (default `false`; meaningful only when `status == :absent`),
  `justification_note` :string (nullable), `recorded_by_user_id` :uuid, denormalized
  `workspace_id` :uuid (for scoping, set from the class group).
- Identity `unique_mark [:enrollment_id, :date, :period_id]` — one mark per student /
  period / date; re-submitting a roll-call upserts the existing cell.
- `references` with `on_delete: :delete` for `enrollment` and `period` (removing a
  student's enrollment or a period removes its marks).

The enrollment already carries the academic year, so an entry's bulletin period is
resolved purely by its `date` against the séquence date ranges (below) — no year
column is duplicated on the entry.

## 2. Absence hours & bulletin-period mapping

Each `:absent` entry contributes its period's **duration** (`period.end_time −
period.start_time`, as a Decimal number of hours) to the absence-hour totals;
`justified` splits that between justified and unjustified hours. Each `:late` entry
contributes one to the **retards** count (retards are a count, not hours).

An entry counts toward a bulletin period by **date**. Séquences already carry
`start_date` / `end_date` (P2.7). For a séquence period the range is that séquence's;
for a trimester it is the union of its séquences' ranges; for annual, all séquences of
the year. This reuses the P2.6 period abstraction (`resolve_period/2`) extended to
yield a date filter, so attendance and bulletins agree on what "this trimester" means.
Entries whose date falls outside every séquence range (e.g. a holiday) are ignored by
the totals.

## 3. Context API

New module `TeacherAssistant.Academics.Attendance` (all Ash calls `authorize?: false`,
tagged tuples, workspace-scoped; never leak raw Ash errors):

- `period_roll(class_group, period, date)` → the class's students with their current
  status for that period on that date (shape for the roll-call grid; students with no
  entry default to unmarked / present per the UI).
- `record_period(class_group, period, teaching_context, date, marks, recorded_by)` →
  upserts the period's marks, where `marks` is a list of `{enrollment_id, status}`;
  returns `{:ok, count}` or a tagged error. Used by both the teacher roll-call and the
  SG register.
- `class_register(class_group, date)` → the day's full grid (periods × students with
  status) for the SG / form-master view.
- `justify_day(enrollment, date, note)` → sets `justified: true` (and the note) on
  every absent entry for that student on that date; `unjustify_day(enrollment, date)`
  → clears it. Returns `{:ok, count}`.
- `student_conduct(enrollment, period)` → `%{justified_hours, unjustified_hours,
  retards}` for one student over a bulletin period.
- `class_conduct(class_group, period)` → the same totals keyed by enrollment for the
  whole roster (so the bulletin can render every student in one pass).

Absence-hour arithmetic lives in a small pure helper (mirroring `Bulletins` /
`Marks`) so hour computation and date→période mapping are unit-testable without the
database.

## 4. Access

New permission helpers on `Accounts.Permissions`: `discipline_master?/1` (the school's
`:discipline_master` / SG) and `conduct_manager?/1` = `admin?/1 or
discipline_master?/1`. Every surface resolves the class via workspace-scoped
`fetch_owned_class_group`, gates the mount, and re-checks each mutating handler;
targets (students, period, teaching context) come from socket/conn-loaded
collections, never raw client ids; the date and status enum come through a whitelist,
never `String.to_atom` on raw input.

- **Teacher roll-call:** a teacher may `record_period` only for a period they teach —
  the server resolves the P2.7 timetable slot for `{class, day-of-`date`, period}` and
  confirms its `teaching_context.teacher_user_id` is the current user (a conduct
  manager may record any period). The client never supplies the teaching context.
- **SG register + justification:** `conduct_manager?` (SG or admin) — full register
  for any class in the workspace, plus `justify_day` / `unjustify_day`.
- **Form master:** read-only register for their own class (P2.5
  `admin_or_form_master?` pattern) — no marking, no justifying.

## 5. UI

- **Teacher roll-call** `/school/classes/:id/attendance/:period_id?date=YYYY-MM-DD`
  (default today) — the class roster with a present / absent / late control per
  student, saving via `record_period`. Reached from the teacher's own timetable
  (`/school/timetable/me`): each lesson cell gains a "Faire l'appel" link for today.
  Gated to the teacher who owns that slot (or a conduct manager); a forged period /
  student is rejected server-side.
- **SG daily register** `/school/classes/:id/register?date=YYYY-MM-DD` — the day's
  periods × students grid, a date picker, conduct-manager edit / form-master read, and
  a per-student "Justifier" action (with optional note) calling `justify_day`. A
  per-student conduct strip (justified / unjustified hours, retards) for the current
  séquence sits alongside. Linked from the class-detail page for conduct managers and
  the form master.
- **Bulletin conduct line** — the individual bulletin (P2.6 `bulletin_live`) and its
  print gain a **conduct section G**: absences justifiées (h) · absences non
  justifiées (h) · retards, for the selected period, via `student_conduct/2` (or the
  `class_conduct/2` map for the whole-class print). Display-only; the moyenne générale
  is untouched.

## 6. Testing

- **Pure helper:** hours computed from period durations; date→séquence mapping across
  séquence / trimester / annual; a holiday-date entry excluded; justified vs
  unjustified split; retards counted from `:late`.
- **Context (`Attendance`):** `record_period` inserts then upserts (re-marking a cell
  replaces, no duplicate); `period_roll` reflects current marks; `justify_day` flips
  every absent entry that day (and leaves other days alone); `student_conduct` /
  `class_conduct` aggregate over a bulletin period; a teaching context / student from
  another class is rejected.
- **LiveView (teacher roll-call):** the grid saves marks; a teacher recording a period
  they do **not** teach is rejected (forged `period_id`); a conduct manager may record
  any period; a non-member / cross-school class is redirected.
- **LiveView (SG register):** the day grid renders; the date picker reloads; a
  conduct manager edits and justifies a day; a form master sees a read-only register
  (no edit, no justify) and a forged justify event is rejected.
- **Bulletin:** the conduct section renders justified / unjustified hours + retards for
  a student over a séquence and over a trimester; the moyenne générale is unchanged by
  attendance data.
- **Print:** the bulletin print includes the conduct section.
- **i18n / gate:** gettext extract + non-empty FR/EN msgstrs for every new msgid
  ("Cahier d'appel", "Faire l'appel", status labels, "Justifier", "Absences
  justifiées / non justifiées", "Retards", "Conduite", etc.); `mix precommit` (full
  suite) green. Note: the precommit alias flag is misspelled `--warning-as-errors` (a
  no-op), so warnings do not gate — confirm the suite passes; the `format` step
  rewrites files in place, so commit any format-only diffs.

## Notes / risks

- The teacher-owns-slot resolution is the access centerpiece: map the `date` to a
  `DayOfWeek`, look up the P2.7 `TimetableSlot` for `{class_group, day, period}`, and
  compare its `teaching_context.teacher_user_id` to the current user — never trust a
  client-supplied teaching context. A period the teacher does not teach yields a
  redirect / rejection.
- Denormalizing `workspace_id` onto `AttendanceEntry` keeps conduct aggregation a
  single scoped read; set it from the class group on create.
- `student_conduct` must agree with the P2.6 period resolution so "trimester" absence
  hours cover exactly the trimester's séquences — extend `resolve_period/2` to a date
  range rather than re-deriving séquence dates independently.
- Conduct stays **off** the moyenne générale (KB unsettled); the bulletin arithmetic
  from P2.3 / P2.6 is not touched. Sanctions and note de conduite are deferred to P2.9.
- The roll-call defaults unmarked students to present so a teacher marks only the
  exceptions (absent / late); the register makes the full state explicit for the SG.
