# P2.7 — Timetables (emploi du temps)

**Status:** Approved design
**Date:** 2026-07-06
**Builds on:** P2.1 (school workspaces, roles, permissions), P2.2 (class assignments / TeachingContext), P2.5 (form-master scoped access)

## Purpose

Let the **Censeur** (Vice-Principal, who builds timetables per docs/domain/05) lay
out each class's weekly *emploi du temps* — placing the class's assigned subjects
(subject + teacher) into a day × period grid with real bell times, catching teacher
double-bookings, and tracking placed-vs-required hours. Teachers see their own
weekly timetable; form masters see their class's; everything prints on A4.

## Scope

In scope:
- A configurable per-school bell schedule (periods with clock times), seeded with a
  sensible Cameroonian default.
- A per-class weekly grid (Mon–Sat × periods) whose lesson cells reference the
  class's existing `TeachingContext` assignments.
- Teacher double-booking clash detection (server-side).
- A soft placed/required hours tally per subject.
- Per-class grid editor, teacher's own read-only timetable, and A4 print.

Out of scope (deferred / YAGNI):
- One timetable per class per academic year — no per-term variants.
- No rooms/salles (class owns its room in the Cameroonian model; teachers rotate).
- No auto-scheduling or optimization — manual placement only.
- No substitutions/absences/cover (that belongs to the conduct increment).
- Room-clash is not modeled; teacher-clash is the only conflict rule.

## 1. Data model

Two new `Ash.Type.Enum` modules and three resources (Ash 3 house style:
`use Ash.Resource, otp_app:, domain:, data_layer: AshPostgres.DataLayer,
authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`;
`uuid_v7_primary_key :id`; `timestamps()`).

**Enums**
- `TeacherAssistant.Academics.PeriodKind` — `[:lesson, :break]`.
- `TeacherAssistant.Academics.DayOfWeek` — `[:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]`.

**`Period`** — the school's bell schedule, workspace-scoped (one stable schedule
shared across academic years and classes; bell times rarely change year to year).
- `belongs_to :workspace` (`allow_nil? false`).
- `position` :integer (ordering), `label` :string ("P1"), `start_time` :time,
  `end_time` :time, `kind` `PeriodKind` (default `:lesson`).
- Identity `unique_period_position [:workspace_id, :position]`.
- `build_default_periods/1` seeds a standard grid (07:30 first period, ~55-minute
  lessons, a mid-morning break and a lunch break), which admins may edit.

**`TimetableSlot`** — one filled lesson cell.
- `belongs_to :class_group` (`allow_nil? false`), `belongs_to :teaching_context`
  (`allow_nil? false` — the subject+teacher bundle from P2.2),
  `belongs_to :period` (`allow_nil? false`), `day` `DayOfWeek` (`allow_nil? false`),
  denormalized `workspace_id` :uuid (for scoping/clash queries).
- Identity `unique_cell [:class_group_id, :day, :period_id]` → a class never
  double-books one cell.
- `references` with `on_delete: :delete` for `class_group` and `teaching_context`
  (removing an assignment or class removes its slots).

Days are fixed Mon–Sat (Saturday cells left empty when unused; no Sunday column).

## 2. Clash detection

`Timetables.place_slot(cg, %{day, period_id, teaching_context_id})`:
1. Resolve the `TeachingContext` (must belong to `cg`), read its `teacher_user_id`.
2. **Teacher-clash check:** query for any *other* `TimetableSlot` in the same
   `workspace_id` at the same `day` + `period_id` whose teaching_context has the
   same `teacher_user_id` (join/preload). If found → `{:error, {:teacher_clash,
   other_class_label}}` (the friendly message names the clashing class).
3. Otherwise **upsert** the (class, day, period) cell — replacing any current
   occupant — and return `{:ok, slot}`.

The clash check is a real server-side query re-run on every placement (never only a
UI guard). `clear_slot(cg, day, period_id)` deletes the cell if present (`:ok`).
The `unique_cell` identity is the structural guarantee against a class
double-booking its own cell; teacher-clash is the cross-class guarantee.

## 3. Hours reconciliation

`class_timetable/1` returns, alongside the grid slots, a per-`TeachingContext`
tally: `placed` (count of that context's slots) vs `required` (`weekly_hours`),
with a derived `status` (`:under | :exact | :over`). The UI renders "Maths 4/5"
with an under/over signal, mirroring the coverage (planned-vs-covered) pattern.
This is a display signal only — it never blocks saving an incomplete grid.

## 4. Context API

New module `TeacherAssistant.Academics.Timetables` (all Ash calls `authorize?: false`,
tagged tuples, workspace-scoped; never leak raw Ash errors):
- `list_periods(workspace)` → `[%Period{}]` sorted by position.
- `build_default_periods(workspace)` → seeds the default schedule (idempotent: a
  no-op when periods already exist); returns `:ok`.
- `class_timetable(class_group)` → `%{slots: [...], tally: [...]}` shaped for the
  grid (slots keyed by `{day, period_id}`) and the hours tally.
- `place_slot(class_group, %{day, period_id, teaching_context_id})` →
  `{:ok, %TimetableSlot{}} | {:error, {:teacher_clash, class_label}} | {:error, term}`.
- `clear_slot(class_group, day, period_id)` → `:ok`.
- `teacher_timetable(workspace, user)` → that user's slots across all their classes,
  shaped for a read-only weekly grid.

## 5. UI & access

Access follows P2.1/P2.5 exactly: `Permissions.admin?/1` (Head or **Censeur** /
Vice-Principal) edits; the class's **form master** gets read-only via
`Permissions.admin_or_form_master?/2`; a class's assigned teachers (and any teacher
for their own grid) get read-only self-views. Every surface resolves the class via
workspace-scoped `fetch_owned_class_group`, gates the mount, and re-checks each
mutating handler; targets come from socket-loaded collections, never raw client ids.

- **Per-class grid editor** `/school/classes/:id/timetable` — rows = periods (break
  rows rendered as spanning labels, not editable), columns = Mon–Sat. Each lesson
  cell is a `<select>` of the class's assignments (*subject — teacher*, from
  `Assignments.list_for_class/1`) to place, plus a clear action; a teacher-clash
  placement flashes the friendly message and leaves the cell unchanged. The
  per-subject hours tally sits alongside the grid. Admin edits; form master
  read-only (no selects, cells rendered as text). Linked from the class-detail page
  (admin + form master).
- **Teacher's own timetable** `/school/timetable/me` — the logged-in teacher's
  read-only Mon–Sat grid across all their classes (each cell shows class + subject),
  reached from school nav. Any school member sees their own (empty if they teach
  nothing).
- **Periods configuration** — an admin-only page `/school/periods` to seed the
  default schedule and edit period labels/times/kind, linked from `/school/settings`.
  Admin-gated in UI and re-checked server-side.
- **Print** — A4 per-class timetable and the teacher's own timetable via the
  existing print-controller pattern (`put_layout(false)` + root layout false,
  scope resolved from session), with the school name, class/teacher, année, and
  real bell times in the header. Print access mirrors the on-screen access
  (admin_or_form_master for the class grid; the teacher for their own).

## 6. Testing

- **Context (`Timetables`):** `build_default_periods` seeds the expected grid and is
  idempotent; `place_slot` upserts a cell, replaces an occupant, and rejects a
  teacher-clash across classes with the clashing class label; a `teaching_context`
  from another class is rejected; `clear_slot` empties a cell; the hours tally
  computes placed/required/status; `teacher_timetable` aggregates a teacher's slots
  across classes.
- **LiveView (per-class editor):** grid renders periods × days; placing via the cell
  select persists and re-tallies; a clash shows the friendly message and no state
  change; a form master sees a read-only grid (no selects) and a forged place event
  is rejected; a non-member / cross-school class is redirected.
- **LiveView (teacher self-view):** shows the teacher's own slots; empty for a
  teacher with none.
- **Print:** per-class timetable renders the grid with bell times and the class name.
- **i18n / gate:** gettext extract + non-empty FR/EN msgstrs for every new msgid
  (day names, "Emploi du temps", "Période", "Récréation", clash message, tally
  labels, etc.); `mix precommit` (full suite) green. Note: the precommit alias flag
  is misspelled `--warning-as-errors` (a no-op), so warnings do not gate — confirm
  the suite passes; the `format` step rewrites files in place, so commit any
  format-only diffs.

## Notes / risks

- The teacher-clash query is the correctness centerpiece: it must scope to
  `workspace_id` + `day` + `period_id` and match on the *teacher* behind the
  teaching context (join `teaching_context.teacher_user_id`), excluding the cell
  being (re)placed. Cover replace-in-place (same cell, no false self-clash) in tests.
- Denormalizing `workspace_id` onto `TimetableSlot` keeps the clash query a single
  scoped read without walking `class_group → workspace` each time; set it from the
  class group on create.
- Period edits after slots exist do not orphan slots (slots reference `period_id`);
  deleting a period should be blocked or cascade — default to blocking a delete when
  slots reference it (surface a friendly error), consistent with the assignment
  "has data" pattern in P2.2.
