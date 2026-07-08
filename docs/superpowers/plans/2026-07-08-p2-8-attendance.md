# P2.8 — Attendance & absences (cahier d'appel) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let subject teachers mark present/absent/late per timetable period, let the Surveillant Général oversee a daily class register and justify absences, and surface per-bulletin absence hours + retards on the bulletin conduct line — without touching the moyenne générale.

**Architecture:** One enum + one `AttendanceEntry` resource keyed by `(enrollment, date, period)`. A pure conduct helper turns absent entries into hours from P2.7 period durations; a new `Academics.Attendance` context wraps capture, justification, and per-période aggregation, reusing the P2.6 period abstraction (extended to a date range). Two LiveView surfaces (teacher roll-call, SG register) plus a display-only conduct section on the existing bulletin and its print.

**Tech Stack:** Elixir, Ash 3, AshPostgres, Phoenix LiveView, gettext (FR default + EN).

## Global Constraints

- Ash 3 house style on every resource: `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`; FK `on_delete` set inside the `postgres do ... references do ... end end` block.
- Enums are **`Ash.Type.Enum` modules — never bare `:atom` attributes**.
- Context functions call Ash with `authorize?: false`, return tagged tuples, never leak raw Ash errors.
- Double-gating on every web surface: a UI `:if` gate AND a server-side re-check in each mutating handler. Resolve the class via `Academics.fetch_owned_class_group/2` (filters id AND workspace_id). Targets (students, period, teaching context) come from socket/conn-loaded collections, never raw client ids. The status enum and date arrive through a whitelist — never `String.to_atom` / `String.to_existing_atom` on raw client input for the status; parse the date with `Date.from_iso8601/1`.
- Conduct is **display-only**: it does not enter the moyenne générale. The P2.3/P2.6 bulletin arithmetic (`Bulletins`, `class_results_for_period`) is not modified.
- Migrations via `mix ash.codegen <name>` then `mix ecto.migrate`; commit the generated migration and the `priv/resource_snapshots/` changes.
- Every new user-facing string is a gettext msgid with non-empty FR and EN msgstrs. `mix precommit` (full suite) must be green; its `format` step rewrites files in place — commit any format-only diffs. (The precommit alias flag `--warning-as-errors` is misspelled and a no-op, so warnings do not gate; confirm the suite passes regardless.)

---

### Task 1: AttendanceStatus enum + AttendanceEntry resource + migration

**Files:**
- Create: `lib/teacher_assistant/academics/attendance_status.ex` (mirror `lib/teacher_assistant/academics/period_kind.ex`)
- Create: `lib/teacher_assistant/academics/attendance_entry.ex` (mirror `lib/teacher_assistant/academics/timetable_slot.ex`)
- Modify: `lib/teacher_assistant/academics.ex` (register `resource AttendanceEntry` in the domain `resources do` block, alongside the other `resource` lines near lines 27–36)
- Test: `test/teacher_assistant/academics/attendance_entry_test.exs`

**Interfaces:**
- Consumes: `Enrollment`, `Period` (P2.7), `TeachingContext`, `ClassGroup`, `Workspace` resources.
- Produces: `TeacherAssistant.Academics.AttendanceStatus` enum with values `[:present, :absent, :late]`. `TeacherAssistant.Academics.AttendanceEntry` resource with attributes `date :date` (allow_nil? false), `status AttendanceStatus` (allow_nil? false), `justified :boolean` (default false, public), `justification_note :string` (allow_nil? true), `recorded_by_user_id :uuid`, `workspace_id :uuid` (allow_nil? false); belongs_to `enrollment` (allow_nil? false), `period` (allow_nil? false), `teaching_context` (allow_nil? true); identity `unique_mark [:enrollment_id, :date, :period_id]`; postgres `references` with `on_delete: :delete` for `enrollment` and `period`. Default `create`/`read`/`update`/`destroy` actions plus an `upsert`-capable create identified by `:unique_mark` (accepting `status`, `justified`, `justification_note`, `teaching_context_id`, `recorded_by_user_id`, `workspace_id`, and the three keys).

- [ ] **Step 1: Write the failing test.** In the test module, cover: creating an entry persists status/date/justified; the `:unique_mark` identity rejects (or upserts) a second entry for the same `(enrollment_id, date, period_id)`; deleting the enrollment cascades to delete its entries (assert the entry is gone); deleting the period cascades likewise; `justified` defaults to false; the status attribute rejects a value outside `[:present, :absent, :late]`. Build fixtures with the existing school/class/enrollment/period fixtures (follow how `timetable_slot_test.exs` assembles a class_group + period + teaching_context).

- [ ] **Step 2: Run the test to verify it fails.** Run `mix test test/teacher_assistant/academics/attendance_entry_test.exs`. Expected: FAIL (module/resource undefined).

- [ ] **Step 3: Implement the enum and resource.** Create the enum module mirroring `period_kind.ex`. Create `attendance_entry.ex` mirroring `timetable_slot.ex`'s house header, attributes, `belongs_to` blocks (with `source_attribute`), `identity :unique_mark`, and the `postgres do table ... references do ... end end` block with `on_delete: :delete`. Register the resource in `academics.ex`.

- [ ] **Step 4: Generate and run the migration.** Run `mix ash.codegen add_attendance_entry` then `mix ecto.migrate`. Confirm a migration and a new `priv/resource_snapshots/.../attendance_entry/*.json` appear.

- [ ] **Step 5: Run the test to verify it passes.** Run `mix test test/teacher_assistant/academics/attendance_entry_test.exs`. Expected: PASS.

- [ ] **Step 6: Commit.** `git add` the enum, resource, `academics.ex`, migration, snapshots, and test; commit `feat(school): AttendanceEntry resource + status enum (P2.8)`.

---

### Task 2: Pure conduct helper + period date range

**Files:**
- Create: `lib/teacher_assistant/academics/conduct.ex` (pure module, mirror the no-DB style of `lib/teacher_assistant/academics/bulletins.ex`)
- Modify: `lib/teacher_assistant/academics.ex` (add `period_date_range/1` near `resolve_period/2`, lines ~168–200)
- Test: `test/teacher_assistant/academics/conduct_test.exs`

**Interfaces:**
- Consumes: `Period` structs (with `start_time`/`end_time`), the P2.6 period tuple `{:sequence, %Sequence{}} | {:trimester, %Term{}} | {:annual, %AcademicYear{}}`, and loaded `Sequence` structs (with `start_date`/`end_date`).
- Produces:
  - `TeacherAssistant.Academics.Conduct.period_hours(%Period{})` → a `Decimal` number of hours = `(end_time − start_time)` in hours.
  - `TeacherAssistant.Academics.Conduct.totals(entries)` where `entries` is a list of maps each carrying `%{status, justified, period: %Period{}}` → `%{justified_hours: Decimal, unjustified_hours: Decimal, retards: integer}`: sum `period_hours` over `:absent` entries split by the `justified` flag; count `:late` entries as retards; ignore `:present`.
  - `TeacherAssistant.Academics.period_date_range(period_tuple)` → `{first_date, last_date}` (`Date`s): for `{:sequence, seq}` → `{seq.start_date, seq.end_date}`; for `{:trimester, term}` → min start / max end across `term.sequences` (already loaded by `list_terms/1`); for `{:annual, year}` → min start / max end across `list_sequences(year)`. Returns `nil` when there are no sequences.

- [ ] **Step 1: Write the failing test (conduct helper).** In `conduct_test.exs`, cover: `period_hours` of a 07:30–08:25 period is `Decimal` "0.9166…"-ish — assert against the exact `Decimal.div` result of minutes/60 (compute it the same way the implementation will, i.e. total minutes ÷ 60) so it is deterministic; a two-hour period is `2`. `totals/1` over a mix (one justified absent 1h, one unjustified absent 1h, two lates, one present) yields `justified_hours == 1`, `unjustified_hours == 1`, `retards == 2`; an empty list yields zeros. Build lightweight `%Period{}` structs inline (no DB needed).

- [ ] **Step 2: Run to verify it fails.** Run `mix test test/teacher_assistant/academics/conduct_test.exs`. Expected: FAIL (module undefined).

- [ ] **Step 3: Implement the pure helper.** Write `conduct.ex` with `period_hours/1` (minutes between the two `Time`s via `Time.diff/3` in `:minute`, then `Decimal.div(minutes, 60)`) and `totals/1` (reduce over entries). Keep it DB-free like `bulletins.ex`.

- [ ] **Step 4: Run to verify it passes.** Run `mix test test/teacher_assistant/academics/conduct_test.exs`. Expected: PASS.

- [ ] **Step 5: Write the failing test (period_date_range).** Add a test (in `conduct_test.exs` or an academics test) that builds a year with two séquences per term and asserts `period_date_range/1` returns the séquence's own dates for `{:sequence, _}`, the term's min-start/max-end for `{:trimester, _}`, and the year's min-start/max-end for `{:annual, _}`.

- [ ] **Step 6: Run to verify it fails, then implement `period_date_range/1`** in `academics.ex` beside `resolve_period/2`, using `list_sequences/1` / the term's loaded `sequences`.

- [ ] **Step 7: Run to verify it passes.** Run `mix test test/teacher_assistant/academics/conduct_test.exs`. Expected: PASS.

- [ ] **Step 8: Commit.** `feat(school): pure conduct hours helper + period_date_range (P2.8)`.

---

### Task 3: Attendance context — record_period + period_roll (teacher-owns-slot)

**Files:**
- Create: `lib/teacher_assistant/academics/attendance.ex` (context module, mirror `lib/teacher_assistant/academics/timetables.ex`)
- Test: `test/teacher_assistant/academics/attendance_test.exs`

**Interfaces:**
- Consumes: `AttendanceEntry`, `Period`, `ClassGroup`, `TeachingContext`, `Enrollment`, `TimetableSlot`, `Academics.list_students/1`, `Timetables.class_timetable/1` (or a direct `TimetableSlot` query).
- Produces:
  - `TeacherAssistant.Academics.Attendance.slot_for(class_group, %Date{}, period_id)` → `{:ok, %TimetableSlot{}}` (loaded `teaching_context`) or `{:error, :no_slot}`: map the date to `DayOfWeek` via `Date.day_of_week/1` (1→`:monday` … 6→`:saturday`; 7/Sunday → `{:error, :no_slot}`) and read the `TimetableSlot` for `{class_group_id, day, period_id}`.
  - `Attendance.period_roll(class_group, %Period{}, %Date{})` → `%{students: [%{enrollment_id, student_name, status: nil | :present | :absent | :late}], teaching_context: %TeachingContext{} | nil}`: roster from `list_students/1`, statuses from existing entries for that `(date, period)`, `status: nil` when unmarked (**roll-call starts blank**).
  - `Attendance.record_period(class_group, %Period{}, teaching_context_or_nil, %Date{}, marks, recorded_by_user_id)` where `marks :: [{enrollment_id, status}]` → `{:ok, count}` or `{:error, term}`: validate each `enrollment_id` belongs to `class_group` and each `status` is one of the three atoms (reject otherwise); upsert one `AttendanceEntry` per mark on `:unique_mark`, setting `workspace_id` from the class group and `teaching_context_id` from the passed context. Marks omitted from the list are left as-is (no implicit present rows).

- [ ] **Step 1: Write the failing test.** Cover: `slot_for` returns the placed slot's teaching_context for a weekday matching a placed slot, `{:error, :no_slot}` for a day with no slot and for a Sunday date; `period_roll` returns every roster student with `status: nil` before any marking; after `record_period` with a subset of marks, `period_roll` reflects those statuses and leaves the rest `nil`; `record_period` upserts (re-recording the same enrollment/date/period updates rather than duplicating — assert one row); `record_period` rejects an `enrollment_id` from another class and rejects an invalid status atom. Use existing fixtures + `Timetables.place_slot/2` to create a slot.

- [ ] **Step 2: Run to verify it fails.** `mix test test/teacher_assistant/academics/attendance_test.exs`. Expected: FAIL.

- [ ] **Step 3: Implement `slot_for`, `period_roll`, `record_period`** in `attendance.ex`, mirroring `timetables.ex` conventions (`authorize?: false`, tagged tuples, workspace scoping). Define a private day-of-week mapping (1..6 → the enum atoms, else `:no_slot`).

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): attendance capture — record_period + period_roll (P2.8)`.

---

### Task 4: Attendance context — class_register + justify_day

**Files:**
- Modify: `lib/teacher_assistant/academics/attendance.ex`
- Test: `test/teacher_assistant/academics/attendance_test.exs`

**Interfaces:**
- Produces:
  - `Attendance.class_register(class_group, %Date{})` → `%{periods: [%Period{}], students: [%{enrollment_id, student_name, cells: %{period_id => :present | :absent | :late | nil}}]}`: lesson periods from `Timetables.list_periods/1` (kind `:lesson`), roster from `list_students/1`, cells filled from that day's entries.
  - `Attendance.justify_day(%Enrollment{} | enrollment_id, %Date{}, note)` → `{:ok, count}`: set `justified: true` and `justification_note: note` on every `:absent` entry for that enrollment on that date; non-absent entries and other dates untouched.
  - `Attendance.unjustify_day(enrollment, %Date{})` → `{:ok, count}`: set `justified: false` and clear the note on that day's absent entries.

- [ ] **Step 1: Write the failing test.** Cover: `class_register` returns lesson periods (breaks excluded) and every roster student with a `cells` map keyed by period_id reflecting the day's marks (nil where unmarked); `justify_day` flips only that day's `:absent` entries to `justified: true` with the note, leaving `:late`/`:present` and other-day entries unchanged; `unjustify_day` reverses it. Seed via `record_period`.

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL.

- [ ] **Step 3: Implement `class_register`, `justify_day`, `unjustify_day`.**

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): SG register + day justification (P2.8)`.

---

### Task 5: Attendance context — student_conduct + class_conduct

**Files:**
- Modify: `lib/teacher_assistant/academics/attendance.ex`
- Test: `test/teacher_assistant/academics/attendance_test.exs`

**Interfaces:**
- Consumes: `Academics.period_date_range/1`, `Conduct.totals/1`, the P2.6 period tuple.
- Produces:
  - `Attendance.student_conduct(%Enrollment{} | enrollment_id, period_tuple)` → `%{justified_hours, unjustified_hours, retards}`: resolve the date range via `period_date_range/1`, read that enrollment's entries whose `date` falls in `[first, last]` (load each entry's `period`), delegate to `Conduct.totals/1`. When the range is `nil`, return zeros.
  - `Attendance.class_conduct(class_group, period_tuple)` → `%{enrollment_id => %{justified_hours, unjustified_hours, retards}}` for the whole roster in one read (batch the entries by enrollment, one query scoped to the class + date range).

- [ ] **Step 1: Write the failing test.** Cover: for a séquence period, `student_conduct` sums absence hours by justified flag and counts retards only within that séquence's dates (seed an entry outside the range and assert it is excluded); the trimester total covers both of its séquences; `class_conduct` returns the same per-student figures keyed by enrollment_id for a two-student class. Use real periods (with times) so hour math is exercised end-to-end.

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL.

- [ ] **Step 3: Implement `student_conduct` and `class_conduct`.**

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): per-période conduct aggregation (P2.8)`.

---

### Task 6: Permission helpers + routes

**Files:**
- Modify: `lib/teacher_assistant/accounts/permissions.ex` (add near `admin?/1`, lines ~26–45)
- Modify: `lib/teacher_assistant_web/router.ex` (add the roll-call and register live routes in the `:school_workspace` session block near lines 94–108)
- Test: `test/teacher_assistant/accounts/permissions_test.exs`

**Interfaces:**
- Consumes: `Scope` with `current_workspace_type` / `current_roles`, `ClassGroup`.
- Produces:
  - `Permissions.discipline_master?(%Scope{})` → true when the scope is a school scope whose roles include `:discipline_master` (mirror `bursar?/1` at lines 21–24).
  - `Permissions.conduct_manager?(%Scope{})` → `admin?(scope) or discipline_master?(scope)`.
  - Routes: `live "/school/classes/:id/attendance/:period_id", School.AttendanceLive, :show` and `live "/school/classes/:id/register", School.RegisterLive, :show`.

- [ ] **Step 1: Write the failing test.** In `permissions_test.exs`, assert `discipline_master?` is true for a `:discipline_master` school scope and false for a personal scope / a plain teacher; `conduct_manager?` is true for a head, a vice-principal, and a discipline master, false for a plain teacher and a personal scope. Follow the existing `bursar?`/`admin?` test setup.

- [ ] **Step 2: Run to verify it fails.** `mix test test/teacher_assistant/accounts/permissions_test.exs`. Expected: FAIL.

- [ ] **Step 3: Implement the two helpers and add the two routes.** (Routes point at LiveViews built in Tasks 7–8; adding them now keeps the router change with the permission change.)

- [ ] **Step 4: Run to verify it passes** (permissions test). Expected: PASS. Router will compile once the LiveView modules exist — build them next; do not run the full suite here.

- [ ] **Step 5: Commit.** `feat(school): conduct_manager permissions + attendance routes (P2.8)`.

---

### Task 7: Teacher roll-call LiveView + timetable link

**Files:**
- Create: `lib/teacher_assistant_web/live/school/attendance_live.ex` (mirror `lib/teacher_assistant_web/live/school/timetable_live.ex`)
- Modify: `lib/teacher_assistant_web/live/school/my_timetable_live.ex` (add a "Faire l'appel" link per lesson cell → the roll-call route with `?date=<today>`)
- Test: `test/teacher_assistant_web/live/school/attendance_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.slot_for/3`, `Attendance.period_roll/3`, `Attendance.record_period/6`, `fetch_owned_class_group/2`, `Permissions.conduct_manager?/1`, the current scope/user.
- Behaviour: mount resolves the class (workspace-scoped) and the `Period` by `period_id` from the class's periods; resolves the date from `?date=` (default today, parsed with `Date.from_iso8601/1`, fallback today). **Access:** allow when the current user owns the resolved slot's teaching_context (`slot_for/3` → `teaching_context.teacher_user_id == current_user.id`) OR `conduct_manager?/1`; otherwise redirect to `/school` with a flash. Render the roster with a blank three-way status control per student. A "save"/per-row event calls `record_period/6` with the resolved (server-side) `class_group`, `period`, `teaching_context` (from the slot, never the client), date, and `recorded_by_user_id` = current user; re-check access in the handler. Targets come from the socket-loaded roster, never raw client ids; the status is whitelisted to the three atoms.

- [ ] **Step 1: Write the failing test.** Cover: the teacher who owns the slot sees the roster and can mark a student (status persists — assert via `period_roll`/DB); a teacher who does NOT own the slot is redirected; a conduct manager (discipline master) can mark any period; a forged `enrollment_id` (not in the class) or an out-of-range status is rejected without persisting; a non-member / cross-school class redirects. Follow `timetable_live_test.exs` for LiveView + school-scope setup.

- [ ] **Step 2: Run to verify it fails.** `mix test test/teacher_assistant_web/live/school/attendance_live_test.exs`. Expected: FAIL.

- [ ] **Step 3: Implement `AttendanceLive`** (mount gate + render + mark handler with server-side re-check) and add the "Faire l'appel" links in `my_timetable_live.ex`.

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): teacher roll-call LiveView (P2.8)`.

---

### Task 8: SG daily register LiveView + class-page link

**Files:**
- Create: `lib/teacher_assistant_web/live/school/register_live.ex` (mirror `attendance_live.ex` + the grid style of `timetable_live.ex`)
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (add a "Cahier d'appel" / register link, gated to `conduct_manager?` or the class form master via `admin_or_form_master?/2`)
- Test: `test/teacher_assistant_web/live/school/register_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.class_register/2`, `Attendance.justify_day/3`, `Attendance.unjustify_day/2`, `Attendance.student_conduct/2` (current séquence via `current_sequence/2`), `fetch_owned_class_group/2`, `Permissions.conduct_manager?/1` + `admin_or_form_master?/2`.
- Behaviour: mount resolves the class and a date from `?date=` (default today). **Access:** `conduct_manager?` edits/justifies; the class form master gets read-only (no justify, no edit); anyone else redirects. Render the periods × students grid, a date picker (navigating reloads via `?date=`), a per-student "Justifier" action (with an optional note) that calls `justify_day/3`, and a per-student conduct strip (justified/unjustified hours, retards) for the current séquence via `student_conduct/2`. Every mutating handler re-checks `conduct_manager?` server-side and resolves the enrollment from the socket-loaded roster.

- [ ] **Step 1: Write the failing test.** Cover: a conduct manager sees the day grid and can justify a student's day (assert the entries flip via `student_conduct`/DB); the date picker reloads a different day's grid; a form master sees the grid read-only and a forged justify event is rejected (no change); a plain teacher / cross-school user redirects. 

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL.

- [ ] **Step 3: Implement `RegisterLive`** and add the gated link in `class_live.ex`.

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): SG daily register LiveView (P2.8)`.

---

### Task 9: Bulletin conduct section (screen + print)

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex` (add conduct section G to the individual bulletin, using the already-selected period)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex` and its template dir `lib/teacher_assistant_web/controllers/bulletin_print_html/` (render the same conduct figures on the single + whole-class print)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (load conduct data for the resolved period)
- Test: `test/teacher_assistant_web/live/school/bulletin_live_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: `Attendance.student_conduct/2` (screen, one student) and `Attendance.class_conduct/2` (whole-class print, keyed by enrollment_id), the period tuple already resolved by these surfaces.
- Behaviour: render a **Conduite** section showing Absences justifiées (h), Absences non justifiées (h), Retards for the selected period. It is display-only — the moyenne générale and the existing bulletin figures are unchanged. Hours render via the app's Decimal formatting helper used elsewhere in the bulletin.

- [ ] **Step 1: Write the failing test.** Bulletin LiveView: seed a student with a justified absent, an unjustified absent, and a late within the selected séquence; assert the conduct section shows the right hours + retard count, and assert the student's `moyenne générale` value is unchanged from a no-attendance baseline. Print controller: assert the conduct figures appear in the rendered single bulletin. Follow the existing bulletin/print tests.

- [ ] **Step 2: Run to verify it fails.** Expected: FAIL.

- [ ] **Step 3: Implement the conduct section** on the LiveView and the print HTML + controller data load.

- [ ] **Step 4: Run to verify it passes.** Expected: PASS.

- [ ] **Step 5: Commit.** `feat(school): bulletin conduct section — absences + retards (P2.8)`.

---

### Task 10: i18n + final gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/fr/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po`
- Possibly touch any P2.8 template with a missed literal string.

- [ ] **Step 1: Extract.** Run `mix gettext.extract && mix gettext.merge priv/gettext`. Confirm the new P2.8 msgids appear (status labels Present/Absent/Late, "Cahier d'appel", "Faire l'appel", "Justifier", "Absences justifiées", "Absences non justifiées", "Retards", "Conduite", the register/date-picker labels, access flash messages).

- [ ] **Step 2: Fill FR and EN msgstrs** for every new msgid — non-empty on both sides (FR is the default locale; verify the on-screen French matches what the roll-call/register render). Grep the P2.8 templates for any bare literal not wrapped in gettext and wrap it, then re-extract.

- [ ] **Step 3: Run the full gate.** Run `mix precommit`. Expected: green (format may rewrite files — restage). If the known `user_fixture` email-collision flake trips (`users_unique_email_index`), re-run to confirm it passes clean.

- [ ] **Step 4: Commit.** `chore(i18n): FR/EN + string normalization for P2.8 attendance`.

---

## Self-Review

**Spec coverage:**
- §1 data model → Task 1 (enum + resource + identity + cascade). ✓
- §2 hours & date mapping → Task 2 (`Conduct` + `period_date_range`). ✓
- §3 context API → Tasks 3 (`period_roll`/`record_period`/`slot_for`), 4 (`class_register`/`justify_day`/`unjustify_day`), 5 (`student_conduct`/`class_conduct`). ✓
- §4 access → Task 6 (`discipline_master?`/`conduct_manager?`), enforced in Tasks 7/8 (teacher-owns-slot, conduct-manager, form-master read-only). ✓
- §5 UI → Task 7 (roll-call + timetable link), Task 8 (register + class link), Task 9 (bulletin conduct section, screen + print). ✓
- §6 testing → every task is TDD; i18n/gate in Task 10. ✓
- Scope boundaries (conduct off average; sanctions deferred; blank roll-call) → asserted in Tasks 3 (blank) and 9 (moyenne unchanged); no sanctions resource anywhere. ✓

**Placeholder scan:** No TBD/TODO; each task names exact files, interfaces with signatures, and concrete test behaviours. ✓

**Type consistency:** `record_period/6`, `period_roll/3`, `slot_for/3`, `class_register/2`, `justify_day/3`, `unjustify_day/2`, `student_conduct/2`, `class_conduct/2`, `period_date_range/1`, `Conduct.totals/1`, `Conduct.period_hours/1`, `discipline_master?/1`, `conduct_manager?/1` are used consistently across the tasks that define and consume them. ✓
