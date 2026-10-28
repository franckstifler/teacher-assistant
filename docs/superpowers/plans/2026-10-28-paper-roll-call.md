# Paper Roll Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a class's roll call live on a printed weekly sheet that the surveillant types back in once a week, without the app reporting those lessons as missed before the sheet could come back.

**Architecture:** A per-class flag (`ClassGroup.paper_roll_call`, on by default), a per-lesson « cours non assuré » record (`LessonNotHeld`) and an entry source (`AttendanceEntry.source`). `SchoolLife` gains two lesson states (`:on_paper`, `:not_held`) computed by one pure module (`PaperRollCall`); every view, counter and notification reads them from there. A domain pair `Attendance.paper_week/3` / `save_paper_week/4` feeds both the print page and the entry LiveView.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ash 3 + AshPostgres, Oban, daisyUI/Tailwind v4, Gettext.

**Spec:** `docs/superpowers/specs/2026-10-28-paper-roll-call-design.md`

## Global Constraints

- Follow `AGENTS.md`: `<Layouts.app flash={@flash} ...>`, `<.input>`, `<.icon>`, daisyUI, no inline `<script>` (colocated hooks only), `mix precommit` at the end.
- Migrations only via `mix ash.codegen --dev` (one named codegen per task that changes data: `--name <name>`), then `mix ash.migrate`. **Never** `ecto.reset`/drop on dev; only `MIX_ENV=test`.
- Enums are `Ash.Type.Enum` modules, never bare `:atom` attributes.
- Every new user-visible string through `gettext`; after `mix gettext.extract --merge`, give every new or fuzzy entry its English text in `priv/gettext/en/LC_MESSAGES/default.po`, leave French `msgstr ""`, remove `fuzzy` flags (`test/teacher_assistant_web/gettext_fuzzy_test.exs` must pass).
- Work in a worktree (`.claude/worktrees/paper-roll-call`, branch `feat/paper-roll-call`); run tests with `MIX_TEST_PARTITION=_prc`. Stage explicit paths, never `git commit -a`.
- New LiveViews go in `@views.appel` and new controller actions in `@controllers` of `lib/teacher_assistant/modules.ex` (module `:appel`).
- Who may print, type in, mark « non assuré » or change the flag: `Discipline.can_manage_conduct?/1` (axis `:conduct` = head, vice_principal, discipline_master). The school-wide switch also allows `:admin`.
- Test clock: `Reference.today/0` = Monday `2025-09-15`, `Reference.now/0` = 13:00 school time. Week = Monday..Saturday (`DayOfWeek` includes `:saturday`).
- Copy fixed by the spec (FR msgids): « Appel sur feuille », « Feuille d'appel », « Semaine du %{from} au %{to} », « A = absent · R = retard », « Visa », « Appel fait », « Cours non assuré », « Enregistrer la semaine », « sur feuille · à saisir », « %{app} appels dans l'app · %{paper} sur feuille », « Saisir la feuille », « Imprimer la feuille », « Imprimer toutes les feuilles », « Renvoyé ».

## Review Focus

1. A week with a holiday or a closed day (and Wednesday afternoon off): those columns print greyed and cannot be typed in; the save ignores them. → Task 3 test « closed days have no columns ».
2. A crafted save that targets a lesson already taken in the app: it must leave the app entries untouched. → Task 3 test « app lessons are never overwritten ».
3. A student sent home for fees that day typed « A » on paper: recorded `:sent_home`, never absent. → Task 3 test « sent home wins over A ».
4. A combined-course lesson: one column per class, written with that class's own slot teaching context. → Task 3 test « combined lesson saves per class ».
5. A lesson marked « non assuré » and later taken in the app by the teacher: it shows as done, not « non assuré ». → Task 2 test « done beats not held ».

---

### Task 1: Data — class flag, entry source, « cours non assuré »

**Files:**
- Modify: `lib/teacher_assistant/academics/class_group.ex` (attribute, action `:set_paper_roll_call`, policy)
- Create: `lib/teacher_assistant/academics/attendance_source.ex` (`Ash.Type.Enum`, values `[:app, :paper]`)
- Modify: `lib/teacher_assistant/academics/attendance_entry.ex` (attribute `source`, default `:app`, accepted by `:record` and the combined write)
- Create: `lib/teacher_assistant/academics/lesson_not_held.ex`
- Modify: `lib/teacher_assistant/attendance.ex` (domain resource + functions), `lib/teacher_assistant/enrollment.ex` (define)
- Test: `test/teacher_assistant/academics/paper_roll_call_data_test.exs`

**Interfaces:**
- Produces:
  - `ClassGroup.paper_roll_call :: boolean`, `allow_nil? false`, `default true`, public.
  - `ClassGroup` update `:set_paper_roll_call` accepting `[:paper_roll_call]`; policy: `:admin` or `:conduct`; `YearOpen` applies.
  - `Enrollment.set_paper_roll_call(scope, %ClassGroup{}, boolean) :: {:ok, cg} | {:error, term}`.
  - `Attendance.set_paper_roll_call_all(scope, %AcademicYear{}, boolean) :: :ok | {:error, term}` (every class of the year, one transaction).
  - `AttendanceEntry.source :: AttendanceSource` (`:app | :paper`), default `:app`.
  - `LessonNotHeld` (domain `TeacherAssistant.Attendance`, attribute multitenancy on `workspace_id`): `class_group_id`, `period_id`, `date`, `marked_by_user_id` (set from actor), timestamps; identity `:one_per_lesson [:class_group_id, :date, :period_id]`; actions `:read` (default), `create :mark` (accepts `class_group_id, period_id, date`), `destroy`; read `:for_classes_range` (args `class_group_ids`, `first`, `last`); policy: read `:member`, writes `:conduct`; validation `YearOpen path: [:class_group]`; references with `match_with: [workspace_id: :workspace_id]` like `RollCallReminder`.

- [ ] **Step 1: Write the failing tests** — in `paper_roll_call_data_test.exs` (`DataCase, async: true`, inline school fixture as in `test/teacher_assistant/academics/school_life_test.exs:17-56`):
  - `"a new class is on paper by default"`: `assert cg.paper_roll_call == true`.
  - `"a surveillant switches one class off; a teacher may not"`: with `member_scope_fixture(scope, %{roles: [:discipline_master]})` → `{:ok, %{paper_roll_call: false}}`; with a `[:teacher]` scope → `assert_forbidden`.
  - `"the school-wide switch sets every class of the year"`: two classes, `set_paper_roll_call_all(scope, year, false)` → both reloaded `false`.
  - `"an entry is from the app unless said otherwise"`: `Attendance.record_period(...)` → entry `source == :app`.
  - `"a lesson is marked not held once"`: create `:mark` twice for the same class/date/period → second `{:error, _}`; a `[:teacher]` scope → forbidden.
- [ ] **Step 2: Run, verify they fail** — `MIX_TEST_PARTITION=_prc mix test test/teacher_assistant/academics/paper_roll_call_data_test.exs` → failures on missing attribute/functions.
- [ ] **Step 3: Implement the resources and domain functions** listed under Interfaces; `record_period/6` keeps its signature (source stays `:app`).
- [ ] **Step 4: Generate and run the migration** — `mix ash.codegen --dev --name paper_roll_call_data` then `mix ash.migrate`. Existing class rows get `true` (the column default).
- [ ] **Step 5: Run the tests** → PASS; also `mix test test/teacher_assistant/academics/attendance_test.exs` stays green.
- [ ] **Step 6: Commit** — `git add` the files above plus `priv/repo/migrations/*paper_roll_call_data*` and `priv/resource_snapshots/**`; `git commit -m "feat(attendance): paper roll-call flag, entry source, lessons not held"`.

### Task 2: Lesson states `:on_paper` and `:not_held`

**Files:**
- Create: `lib/teacher_assistant/academics/paper_roll_call.ex` (pure)
- Modify: `lib/teacher_assistant/academics/school_life.ex` (`cell/4` → state rules, `done_roll_calls`, new `class_lessons/5`, `roll_call_counts/1`)
- Modify: `lib/teacher_assistant/attendance.ex` (delegate `class_lessons/5`)
- Test: `test/teacher_assistant/academics/paper_roll_call_test.exs`, extend `test/teacher_assistant/academics/school_life_test.exs`

**Interfaces:**
- Consumes: Task 1 (`ClassGroup.paper_roll_call`, `LessonNotHeld`).
- Produces:
  - `PaperRollCall.week(date) :: {monday :: Date, saturday :: Date}`.
  - `PaperRollCall.waiting?(lesson_date, today) :: boolean` — true while `today` is before the Monday after `lesson_date`'s week.
  - `PaperRollCall.default_week(today) :: Date` — Monday of the current week; from Saturday on, the next Monday.
  - `PaperRollCall.state(base_status, paper?, not_held?, lesson_date, today)` — precedence: `:done` (base) > `:not_held` > `:on_paper` (when `base_status == :missed`, `paper?` and `waiting?`) > base.
  - Cell statuses everywhere become `:done | :not_held | :on_paper | :in_progress | :missed | :upcoming`.
  - `SchoolLife.class_lessons(scope, %ClassGroup{}, first :: Date, last :: Date, now) :: [cell]` — same cell map as `cell/4`, for one class over a range of lesson days (`SchoolCalendar.lesson_day?` and `open_cell?` filters, as `teacher_missed_this_week/4` does).
  - `roll_call_counts/1` returns `%{done, on_paper, expected, missed}` with `expected = done + on_paper + length(missed)`; `:not_held` lessons are in none of them.

- [ ] **Step 1: Write the failing pure tests** in `paper_roll_call_test.exs` (`ExUnit.Case, async: true`):
  - `week(~D[2025-09-17]) == {~D[2025-09-15], ~D[2025-09-20]}`.
  - `waiting?(~D[2025-09-15], ~D[2025-09-20])` true; `waiting?(~D[2025-09-15], ~D[2025-09-22])` false.
  - `default_week(~D[2025-09-17]) == ~D[2025-09-15]`; `default_week(~D[2025-09-20]) == ~D[2025-09-22]`.
  - `state(:missed, true, false, ~D[2025-09-15], ~D[2025-09-16]) == :on_paper`; same with `paper? false` → `:missed`; `state(:done, true, true, ...) == :done` (**« done beats not held »**); `state(:missed, true, true, ...) == :not_held`; `state(:upcoming, true, false, ...) == :upcoming`.
- [ ] **Step 2: Write the failing SchoolLife tests** (extend `school_life_test.exs`, its setup's slot is Monday period 1, clock Monday 13:00):
  - `"a paper class's untaken lesson is on paper, not missed, and not counted missed"`: `school_day(scope, monday, at(monday, ~T[13:00:00])).missed == []`, the cell status `:on_paper`, `roll_call_counts` → `%{on_paper: 1, missed: []}`.
  - `"the Monday after, it is missed again"`: `class_lessons(scope, cg, monday, monday, at(~D[2025-09-22], ~T[09:00:00]))` → status `:missed`.
  - `"a class off paper keeps today's rule"`: flag false → `:missed`.
  - `"a lesson marked not held is neither missed nor on paper"`: create `LessonNotHeld` → `:not_held`, counts exclude it.
- [ ] **Step 3: Run, verify they fail.**
- [ ] **Step 4: Implement** `PaperRollCall` and wire it in `SchoolLife`: `read_slots` already loads `class_group` (has the flag); read `LessonNotHeld :for_classes_range` alongside `done_roll_calls` and pass both into `cell/4`. `teacher_day/4` and `teacher_missed_this_week/4` go through the same `cell/4`, so the teacher views follow (spec §4).
- [ ] **Step 5: Run** both files plus `mix test test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant/workers/missed_roll_calls_test.exs` → PASS. Existing tests that expect `:missed` for a paper class: set their class to `paper_roll_call: false` in their setup (they test the app rule).
- [ ] **Step 6: Commit** — `git commit -m "feat(attendance): on-paper and not-held lesson states"`.

### Task 3: The paper week — read and save

**Files:**
- Create: `lib/teacher_assistant/academics/paper_week.ex` (read model + save, called through the domain)
- Modify: `lib/teacher_assistant/attendance.ex` (`paper_week/3`, `save_paper_week/4`; `record_period/7` with `opts \\ []` accepting `source:`)
- Test: `test/teacher_assistant/academics/paper_week_test.exs`

**Interfaces:**
- Consumes: Task 1 resources, Task 2 `PaperRollCall.week/1`, `class_lessons/5`, `FeeControl.sent_home_ids/3`, `Enrollment.list_roster/2` (order = `String.downcase(full_name)`, number = 1-based index).
- Produces:
  - `Attendance.paper_week(scope, %ClassGroup{}, monday :: Date) :: %{monday, saturday, students: [%{enrollment_id, number, student_name}], days: [%{date, label, closed: nil | String.t(), lessons: [lesson]}]}` where `lesson = %{date, period, teaching_context_id, code, subject, state, marks: %{enrollment_id => :absent | :late | :present | :sent_home}, sent_home: MapSet}` and `state :: :app | :paper | :not_held | :empty`. `:app` = entries exist with `source :app`; `:paper` = entries exist with `source :paper`; `:empty` = none. `code` = the subject's `code`, else the first 4 letters of the label upcased (same rule as `EntryProgress.column_code/2`; extract it to a shared public function rather than copy it). A closed day (`Attendance.day_off/2` or Wednesday afternoon via `SchoolCalendar.open_cell?/3`) has `closed: label` and only its open lessons.
  - `Attendance.save_paper_week(scope, %ClassGroup{}, monday, columns) :: {:ok, %{saved: n, not_held: n}} | {:error, :forbidden | :unverified | term}` with `columns :: [%{date, period_id, mode: :taken | :not_held | :skip, marks: %{enrollment_id => :absent | :late}}]`. One `Repo.transaction`. Per column: skip when `mode == :skip`, when the lesson is not in `paper_week` (closed, other week, no slot) or when its state is `:app`. `:taken` → `record_period(..., tc_of_slot, date, marks, source: :paper)` with every roster student: typed `:absent`/`:late` (no minutes), sent-home ids `:sent_home` regardless, others `:present`; deletes any `LessonNotHeld` for it. `:not_held` → only if no entries: create `LessonNotHeld`.

- [ ] **Step 1: Write the failing tests** (`DataCase, async: true`; setup = school_life fixture plus a second slot Tuesday, students « Awa », « Beti », « Chantal »; surveillant scope via `member_scope_fixture(scope, %{roles: [:discipline_master]})`):
  - `"the week lists the roster in class-list order with numbers"` → `Enum.map(students, &{&1.number, &1.student_name}) == [{1, "Awa"}, {2, "Beti"}, {3, "Chantal"}]`.
  - `"a typed column records absents, lates and everyone else present"` → after save of Monday `%{awa => :absent, beti => :late}`: entries Awa `:absent`, Beti `:late` (`late_minutes` nil), Chantal `:present`, all `source: :paper`, `recorded_by_user_id == surveillant.id`; that cell's state in `paper_week` is `:paper`.
  - `"an empty ticked column records everyone present"`.
  - `"app lessons are never overwritten"`: teacher records Monday in the app with all present; a save with `:taken` and Awa `:absent` for that lesson → Awa still `:present`, `source: :app`.
  - `"sent home wins over A"`: a send-out for Beti on Monday (as `test/teacher_assistant/academics/sent_home_not_absence_test.exs` creates one) → typed `:absent` saves `:sent_home`.
  - `"an unticked column writes nothing"`: `mode: :skip` with marks → no entries.
  - `"not held closes the lesson; ticking it later replaces that"`: `:not_held` → `LessonNotHeld` exists, no entries; then `:taken` → entries, no `LessonNotHeld`.
  - `"closed days have no columns"`: a holiday on the Tuesday → that day `closed` set, `lessons == []`; a crafted Tuesday column is ignored.
  - `"combined lesson saves per class"`: a combined course placed Monday (`Timetabling.place_combined_slot/4`) → each class's own week saves entries with its own `teaching_context_id`.
  - `"a teacher may not save a week"` → `{:error, :forbidden}`; unverified school → `{:error, :unverified}`.
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement** `paper_week/3` and `save_paper_week/4` as specified; authorization by `Discipline.can_manage_conduct?/1` and `Scope.school_verified?/1` up front, the Ash policies still apply to every write.
- [ ] **Step 4: Run** the file plus `attendance_test.exs` and `attendance_combined_test.exs` → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): read and save a class's paper week"`.

### Task 4: The printed sheet

**Files:**
- Create: `lib/teacher_assistant_web/controllers/roll_sheet_print_controller.ex`, `roll_sheet_print_html.ex`, `roll_sheet_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (in the `[:browser, :school]` scope next to `TimetablePrintController`), `lib/teacher_assistant/modules.ex`
- Test: `test/teacher_assistant_web/controllers/roll_sheet_print_controller_test.exs`

**Interfaces:**
- Consumes: Task 3 `Attendance.paper_week/3`, Task 2 `PaperRollCall.default_week/1`.
- Produces: routes `GET /school/classes/:id/roll-sheet/print?week=YYYY-MM-DD` (`:class`) and `GET /school/roll-sheets/print?week=YYYY-MM-DD` (`:all`, every class of the year with `paper_roll_call`, in `Enrollment.list_class_groups/2` order, one `.sheet` per class). Missing or invalid `week` → `default_week(Reference.today())`; any date → its Monday.

- [ ] **Step 1: Write the failing tests** (pattern: `timetable_print_controller_test.exs`):
  - `"prints the class sheet for the week"`: as a surveillant, `get(conn, ~p"/school/classes/#{cg.id}/roll-sheet/print?week=2025-09-17")` → 200, body contains « Feuille d'appel », « 6e A », « Semaine du lundi 15 au samedi 20 septembre 2025 », « A = absent · R = retard », « Visa », each student's « 1 », « Awa », the Monday subject code.
  - `"a holiday prints as a greyed band with its label"`.
  - `"all paper classes print, one page each"`: two paper classes and one off → body has two `class="sheet"`.
  - `"a teacher is sent away"` → redirect to `/school`.
  - `"without the appel module it is refused"` (as in `modules_test.exs`).
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement** the controller like `TimetablePrintController` (`plug SchoolAccess`, `put_layout(false)`, `put_root_layout(false)`), access `Discipline.can_manage_conduct?/1`; the template is a full document with `@page { size: A4 landscape; margin: 10mm; }`, `.sheet + .sheet { break-before: page; }`, rotated subject headers, a day header row (`DayOfWeek.label/1` + day number), 3 blank rows after the students, a « Visa » row with one cell per lesson, closed days as one greyed cell spanning the rows with the holiday label. Add `{W.RollSheetPrintController, :class} => :appel` and `:all` to `@controllers`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): printable weekly roll-call sheet"`.

### Task 5: The entry screen

**Files:**
- Create: `lib/teacher_assistant_web/live/school/roll_sheet_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/classes/:id/roll-sheet", School.RollSheetLive, :show` in the school live_session), `lib/teacher_assistant/modules.ex` (`@views.appel`)
- Modify: `lib/teacher_assistant_web/live/school/register_live.ex` (actions « Saisir la feuille », « Imprimer la feuille » for conduct managers on a paper class)
- Test: `test/teacher_assistant_web/live/school/roll_sheet_live_test.exs`

**Interfaces:**
- Consumes: Task 3 `paper_week/3`, `save_paper_week/4`; Task 2 `default_week/1`.
- Produces: page `?week=YYYY-MM-DD` (default as in Task 4), previous/next week links; DOM ids `#roll-sheet`, `#cell-<enrollment_id>-<date>-<period_id>` (button, `phx-click="cycle"` with `phx-value-*`), `#done-<date>-<period_id>` (checkbox, `phx-click="toggle_done"`), `#not-held-<date>-<period_id>` (`phx-click="toggle_not_held"`), `#save-week` (`phx-click="save"`), `#unticked-warning`. Socket state: `columns` map `{date, period_id} => %{mode, marks}` built from `paper_week` (`:paper` → `:taken` with its saved A/R; `:not_held` → `:not_held`; `:empty` → `:skip`; `:app` → not editable).

- [ ] **Step 1: Write the failing tests** (pattern: `school_life_live_test.exs` with `conn_with_roles/3`):
  - `"a surveillant types a week in"`: open `~p"/school/classes/#{cg.id}/roll-sheet?week=2025-09-15"`, click Awa's Monday cell once (→ « A »), click Beti's twice (→ « R »), tick `#done-…`, click `#save-week` → flash « Feuille enregistrée. », entries as in Task 3.
  - `"a cell cycles empty → A → R → empty"` (render text of the cell).
  - `"a sent-home student's cell is locked « Renvoyé »"` → the cell has `disabled` and text « Renvoyé ».
  - `"an app lesson is green, read-only, and links to its roll call"` → no `#cell-…` buttons in that column, a link to `/school/classes/#{cg.id}/attendance/#{period.id}?date=2025-09-15`.
  - `"a column with A but no tick warns before saving"` → `#unticked-warning` lists « Lundi 15 · Maths ».
  - `"« cours non assuré » saves the lesson as not held"`.
  - `"a teacher cannot open it"` → redirect with « Access denied. ».
  - `"the register page offers the sheet for a paper class only"` → `register_live` shows the two links when `paper_roll_call`, not otherwise.
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement** the LiveView: `<Layouts.app flash={@flash} current_scope={@current_scope}>`, `ClassShell` with tab `:register` active, the grid with a sticky first column (as the review pass did for matrix tables), cells as `<button>` (keyboard: Tab, Enter/Space cycles natively); add a colocated hook `.RollSheetKeys` for arrow-key moves and « a » / « r » / Backspace on the focused cell (it pushes `"cycle_to"` with the target value). Save calls `save_paper_week/4` with the `columns` state; errors map: `:forbidden` → `Authz.put_not_allowed/1`, others → « Feuille non enregistrée. ».
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): type a paper roll-call sheet in"`.

### Task 6: Views, counters and the two switches

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/day_live.ex` (legend, `cell_class`, `cell_text`, `legend_label`, `cell_title`, `tally/1`, `summary_text`; header action « Imprimer toutes les feuilles » → `/school/roll-sheets/print`; per class row, a link « Saisir la feuille » when the class is on paper)
- Modify: `lib/teacher_assistant_web/live/school/my_day_live.ex` (`dot_class`, `status_tag`, hero branches for `:on_paper`, `:not_held`)
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex` (`#kpi-calls` sub-line)
- Modify: `lib/teacher_assistant_web/live/school/register_live.ex` (toggle « Appel sur feuille » for conduct managers, `phx-click="toggle_paper"`)
- Modify: `lib/teacher_assistant_web/live/school/school_life_settings_live.ex` (section « Appel sur feuille » with two buttons « Toutes les classes » / « Aucune classe » → `set_paper_roll_call_all/3`)
- Test: extend `school_life_live_test.exs`, `dashboard_live_test.exs`, `register_live_test.exs`, `school_life_settings_live_test.exs`

**Interfaces:**
- Consumes: Task 2 statuses and `roll_call_counts/1` shape; Task 1 setters.

- [ ] **Step 1: Write the failing tests:**
  - Day page: a paper class's past lesson shows « sur feuille · à saisir » in the grey style and is not in `#missed-roll-calls`; « Relancer » is still offered on it; legend lists « Sur feuille » and « Non assuré ».
  - Dashboard: `#kpi-calls` reads « 0 appels dans l'app · 1 sur feuille » for that day.
  - Ma journée: the teacher of a paper class sees no red « non fait » for it.
  - Register: a surveillant switches « Appel sur feuille » off → `paper_roll_call == false`; a teacher sees no toggle.
  - Settings: « Aucune classe » sets every class off; flash « Réglage enregistré. ».
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement.** `:on_paper` uses the neutral `base-200`/`base-content/70` tone, `:not_held` a muted dashed style; `remind_roll_call` must accept `:on_paper` cells (today it only searches `day.missed`: search both).
- [ ] **Step 4: Run** the four test files plus `spaces_test.exs` → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): show paper lessons and switch paper roll call"`.

### Task 7: Monday notice for sheets not typed in

**Files:**
- Create: `lib/teacher_assistant/workers/paper_sheets_overdue.ex`
- Modify: `lib/teacher_assistant/accounts/notification_kind.ex` (add `:paper_sheets_overdue`), `lib/teacher_assistant_web/notification_text.ex` (title + detail clauses), `config/config.exs` (cron `{"30 5 * * 1", TeacherAssistant.Workers.PaperSheetsOverdue}` = 06:30 school time)
- Test: `test/teacher_assistant/workers/paper_sheets_overdue_test.exs`

**Interfaces:**
- Consumes: Task 2 `class_lessons/5` (status `:missed` on a paper class = overdue sheet).
- Produces: one notification per run to heads and discipline masters (same recipients as `MissedRollCalls`), params `%{count, list}` where `list` = « 6e A (sem. du 15 sept.), 4e B (sem. du 8 sept.) » (oldest week first), link = the entry screen of the first class and week. Range: from the current term's start (`Organization` term containing today, else the year start) to the last Saturday. Nothing sent when nothing is overdue, on a non-verified school or without `:appel` (reuse `MissedRollCalls.run/2`).

- [ ] **Step 1: Write the failing tests** (pattern: `missed_roll_calls_test.exs`, `async: false`, clock set to Monday `2025-09-22 06:30`): a paper class with an untaken Monday-15 lesson → one `:paper_sheets_overdue` notice to the SG with `"list"` containing « 6e A »; after `save_paper_week` for that week → none; a class off paper → none (it is in `MissedRollCalls`' domain instead); `NotificationText.title/1` renders « 1 feuille d'appel non saisie ».
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement** the worker, the kind (run `mix ash.codegen --dev --name paper_sheets_overdue_kind`; if it generates nothing, there is no migration), the text clauses and the cron line.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(attendance): Monday notice for paper sheets not typed in"`.

### Task 8: Bulletin checklist warning

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`publish_checklist/4` adds `%{key: :paper_roll_calls, ok?: boolean, data: %{count: n}}`)
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex` (`check_text/1` clause)
- Test: extend `test/teacher_assistant/report_cards_test.exs` and `test/teacher_assistant_web/live/school/bulletins_live_test.exs`

**Interfaces:**
- Consumes: Task 2 `class_lessons/5`; `Organization.period_date_range/2`.
- Produces: the item is present only for a paper class; `count` = lessons of the period up to today whose status is `:on_paper` or `:missed`. It never blocks `publish/3`.

- [ ] **Step 1: Write the failing tests:** a paper class with one untaken lesson in séquence 1 → item `ok?: false, data: %{count: 1}`, and `publish/3` still succeeds; after typing the week in → `ok?: true`; a class off paper → no `:paper_roll_calls` item; the LiveView shows « 1 cours sans appel saisi (feuille d'appel) » with the `!` marker.
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat(bulletins): warn when paper roll calls are not typed in"`.

### Task 9: Translations, full suite, browser check

- [ ] **Step 1:** `mix gettext.extract --merge`; fill every new/fuzzy English entry, French empty, no `fuzzy` flags; `MIX_TEST_PARTITION=_prc mix test test/teacher_assistant_web/gettext_fuzzy_test.exs` → PASS.
- [ ] **Step 2:** `MIX_TEST_PARTITION=_prc mix precommit` → 0 failures; `mix compile --force 2>&1 | grep -A3 warning` shows nothing in files this plan touched.
- [ ] **Step 3: Browser check** on the demo school (server from the worktree on port 4010: `PORT=4010 ELIXIR_ERL_OPTIONS="-live_debugger 'disabled?' true" mix phx.server` in the background; `mix ash.migrate` first; sign in as `censeur@demo.test` or `sg@demo.test`): print one sheet and all sheets (A4 landscape preview), type a week in at desktop and 375px width, check « Journée », the dashboard KPI and a teacher's « Ma journée ». Fix what looks wrong, re-run the affected tests.
- [ ] **Step 4: Commit** translations and fixes — `git commit -m "chore(gettext): paper roll call strings"`.
