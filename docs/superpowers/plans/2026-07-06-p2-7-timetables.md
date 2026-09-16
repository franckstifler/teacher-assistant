# P2.7 Timetables (emploi du temps) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plan style note (per user request):** this plan intentionally contains **no code blocks**. Each task specifies exact file paths, function signatures, behaviors, and the test cases to write in prose. The implementer writes the actual Elixir/HEEx by following the existing patterns named in each task (the sibling resources, context functions, LiveViews, and print controller from P2.2/P2.3/P2.5/P2.6). Because tasks are prose-specified rather than transcription, dispatch implementers on a mid-tier model, not the cheapest.

**Goal:** Let the Censeur build each class's weekly timetable (day × period grid of the class's subject+teacher assignments) with real bell times, teacher-clash detection, and a placed/required hours tally, plus teacher self-views and A4 print.

**Architecture:** Three Ash resources (`Period` workspace-scoped bell schedule; `TimetableSlot` one cell = class × day × period → teaching_context; two enums) behind a `TeacherAssistant.Academics.Timetables` context module that owns seeding, placement with a server-side teacher-clash query, reads shaped for the grid, and the hours tally. LiveView surfaces (per-class editor, teacher self-view, periods config) and print routes reuse the P2.5 access model and the existing print-controller pattern.

**Tech Stack:** Elixir, Ash 3 + AshPostgres, Phoenix LiveView, gettext (FR source + EN translations).

## Global Constraints

- Enums are `Ash.Type.Enum` modules — never bare `:atom` attributes.
- Ash resources use the house header: `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`. Mirror an existing resource such as `lib/teacher_assistant/academics/enrollment.ex` or `teaching_context.ex`.
- Context functions call Ash with `authorize?: false`, return tagged tuples/plain values, and never leak raw Ash errors.
- Access derives from the P2.1/P2.5 helpers: `Permissions.admin?/1` (Head or Vice-Principal/Censeur) edits; `Permissions.admin_or_form_master?/2` grants a class's form master read access; every surface resolves the class via `Academics.fetch_owned_class_group/2`, gates the mount, and re-checks each mutating handler server-side; targets come from socket/conn-loaded collections, never raw client ids.
- Migrations are additive (`mix ash.codegen <name>` then `mix ecto.migrate`); commit the generated migration and resource snapshots.
- Every new gettext msgid gets a non-empty msgstr in BOTH `fr` and `en`.
- `mix precommit` runs the full suite; its alias flag is misspelled `--warning-as-errors` (a no-op) so warnings do not gate — confirm the suite passes. The `format` step rewrites files in place; commit any format-only diffs.
- Display a user by `.email` and a subject by the teaching context's `subject` (match the assignments-panel convention `tc.teacher.email` / `tc.subject`).
- Decimals/times: `start_time`/`end_time` are `:time`; render as `HH:MM`.

---

### Task 1: Enums + `Period` resource + default bell schedule

**Files:**
- Create: `lib/teacher_assistant/academics/period_kind.ex`, `lib/teacher_assistant/academics/day_of_week.ex`, `lib/teacher_assistant/academics/period.ex`, `lib/teacher_assistant/academics/timetables.ex`
- Modify: `lib/teacher_assistant/academics.ex` (register the `Period` resource in the domain's `resources do … end` block, alongside the existing resource entries), `lib/teacher_assistant/academics/reference.ex` (add a `default_periods_preset/0` beside the existing `default_calendar_preset/0`)
- Test: `test/teacher_assistant/academics/timetables_periods_test.exs` (create)
- Generated: a `*_p2_7_period.exs` migration + `priv/resource_snapshots/repo/periods/*.json`

**Interfaces:**
- Produces:
  - `PeriodKind` enum values `[:lesson, :break]`; `DayOfWeek` enum values `[:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]`.
  - `Period` resource, table `"periods"`, attributes `position :integer`, `label :string`, `start_time :time`, `end_time :time`, `kind PeriodKind` (default `:lesson`), `belongs_to :workspace` (`allow_nil? false`, source `workspace_id`), identity `unique_period_position [:workspace_id, :position]`; create/update accept lists cover `position, label, start_time, end_time, kind, workspace_id` (workspace_id create-only).
  - `TeacherAssistant.Academics.Timetables.list_periods(workspace) -> [%Period{}]` sorted by `position`.
  - `TeacherAssistant.Academics.Timetables.build_default_periods(workspace) -> :ok` — idempotent: seeds `Reference.default_periods_preset/0` only when the workspace has no periods yet; a no-op otherwise.
  - `Reference.default_periods_preset/0` returns an ordered list of period maps (`%{position, label, start_time, end_time, kind}`) modeling a standard Cameroonian day: first lesson at 07:30, ~55-minute lessons, a mid-morning `:break` (récréation) and a lunch `:break`, running to roughly mid-afternoon (about 8 lessons + 2 breaks). Use `~T[HH:MM:00]` sigils.

- [ ] **Step 1: Write the failing test.** In the new test file (`use TeacherAssistant.DataCase, async: true`), create a school workspace via `TeacherAssistant.Accounts.Schools.create_school/2` with a `TeacherFixtures.user_fixture/0`. Assert: (a) `build_default_periods(workspace)` returns `:ok` and `list_periods/1` then returns a non-empty list sorted by `position`, whose first entry starts at `~T[07:30:00]` and which contains at least one `:break` and several `:lesson` periods; (b) calling `build_default_periods/1` a second time does NOT duplicate — `list_periods/1` length is unchanged (idempotence); (c) `list_periods/1` for a fresh second workspace with no seeding is `[]`.

- [ ] **Step 2: Run it and confirm failure** (`mix test test/teacher_assistant/academics/timetables_periods_test.exs`) — fails because the modules/functions do not exist.

- [ ] **Step 3: Add the two enum modules** following the one-line-per-value style of `lib/teacher_assistant/academics/sex.ex` / `subsystem.ex`.

- [ ] **Step 4: Add the `Period` resource** mirroring `enrollment.ex` structure (postgres table + repo, actions defaults with accept lists, `policy always`, attributes, `belongs_to :workspace`, identity). Register it in the `Academics` domain resource list.

- [ ] **Step 5: Add `Reference.default_periods_preset/0`** returning the ordered period maps described in Interfaces.

- [ ] **Step 6: Create `Timetables` module** with `list_periods/1` (Ash query filter on `workspace_id`, sort `position`, `authorize?: false`) and `build_default_periods/1` (guard on `list_periods/1 == []`, then create each preset row with `workspace_id`; return `:ok`).

- [ ] **Step 7: Generate + run the migration** (`mix ash.codegen p2_7_period` then `mix ecto.migrate`); confirm it only adds the `periods` table.

- [ ] **Step 8: Run the test to green**, then **commit** (`feat(school): Period bell schedule + default preset (P2.7)`) including migration + snapshots.

---

### Task 2: `TimetableSlot` resource + `place_slot`/`clear_slot` with teacher-clash

**Files:**
- Create: `lib/teacher_assistant/academics/timetable_slot.ex`
- Modify: `lib/teacher_assistant/academics.ex` (register `TimetableSlot`), `lib/teacher_assistant/academics/timetables.ex` (add placement functions)
- Test: `test/teacher_assistant/academics/timetables_slots_test.exs` (create)
- Generated: a `*_p2_7_timetable_slot.exs` migration + snapshots

**Interfaces:**
- Consumes: `Period` (Task 1); existing `ClassGroup`, `TeachingContext` (has `teacher_user_id`, `subject`, `class_group_id`, `weekly_hours`), `Academics.Assignments.list_for_class/1`.
- Produces:
  - `TimetableSlot` resource, table `"timetable_slots"`, `belongs_to :class_group/:teaching_context/:period` (all `allow_nil? false`), `day DayOfWeek` (`allow_nil? false`), `workspace_id :uuid` (`allow_nil? false`, denormalized), identity `unique_cell [:class_group_id, :day, :period_id]`, `references` with `on_delete: :delete` for `class_group` and `teaching_context`. Create/update accept lists cover `class_group_id, teaching_context_id, period_id, day, workspace_id`.
  - `Timetables.place_slot(class_group, %{day: atom, period_id: uuid, teaching_context_id: uuid}) -> {:ok, %TimetableSlot{}} | {:error, {:teacher_clash, class_label}} | {:error, :invalid}`. Behavior: resolve the `TeachingContext` and verify it belongs to `class_group` (else `{:error, :invalid}`); read its `teacher_user_id`; run the teacher-clash query (below); if clash, return `{:error, {:teacher_clash, other_class_label}}`; otherwise upsert the `(class_group_id, day, period_id)` cell (replace any current occupant) with the class's `workspace_id`, returning `{:ok, slot}`.
  - Teacher-clash query: any `TimetableSlot` with the same `workspace_id`, `day`, `period_id`, a DIFFERENT `class_group_id`, whose `teaching_context.teacher_user_id` equals the placed teacher — excluding the cell being replaced. `class_label` in the error is the clashing slot's class group `label`.
  - `Timetables.clear_slot(class_group, day, period_id) -> :ok` (deletes the cell if present; `:ok` regardless).

- [ ] **Step 1: Write the failing tests.** Setup (DataCase): a school, active year, `build_default_calendar` not needed; create two class groups `cgA`/`cgB`; assign the SAME teacher (the head) to "Maths" in both via `Assignments.assign/3`; seed periods via `Timetables.build_default_periods/1`; pick a lesson period `p`. Assert: (a) `place_slot(cgA, %{day: :monday, period_id: p.id, teaching_context_id: tcA.id})` returns `{:ok, slot}`; (b) placing the SAME teacher in `cgB` at `:monday`+`p` returns `{:error, {:teacher_clash, cgA_label}}` and no slot is created for cgB; (c) placing a DIFFERENT teacher/subject in cgB at the same cell succeeds; (d) placing a second subject into cgA's already-filled `:monday`+`p` cell REPLACES it (still one slot for that cell, teaching_context updated) and does NOT self-clash; (e) a `teaching_context` belonging to another class is rejected `{:error, :invalid}`; (f) `clear_slot(cgA, :monday, p.id)` returns `:ok` and the cell is gone; clearing an empty cell is still `:ok`.

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Add the `TimetableSlot` resource** (mirror `enrollment.ex`, including the `references` block for `on_delete: :delete` like enrollment's student reference). Register in the domain.

- [ ] **Step 4: Generate + run the migration** (`mix ash.codegen p2_7_timetable_slot`, `mix ecto.migrate`); confirm the unique index on `(class_group_id, day, period_id)` and the two `on_delete: :delete` FKs.

- [ ] **Step 5: Implement `place_slot/2` and `clear_slot/3`** in `Timetables`. Use a read to find an existing cell (for replace vs create) and a separate scoped read for the clash check (filter `workspace_id`, `day`, `period_id`, `class_group_id != cg.id`, load `teaching_context`, then match `teacher_user_id`). Resolve the friendly `class_label` by loading the clashing slot's `class_group`. Wrap the resolve-context validation and upsert so a bad `teaching_context_id` yields `{:error, :invalid}`.

- [ ] **Step 6: Run the tests to green**, then **commit** (`feat(school): timetable slot + place/clear with teacher-clash (P2.7)`).

---

### Task 3: Read side — `class_timetable/1` (grid + hours tally) + `teacher_timetable/2`

**Files:**
- Modify: `lib/teacher_assistant/academics/timetables.ex`
- Test: `test/teacher_assistant/academics/timetables_reads_test.exs` (create)

**Interfaces:**
- Consumes: `Period`, `TimetableSlot`, `Assignments.list_for_class/1`, `TeachingContext.weekly_hours`.
- Produces:
  - `Timetables.class_timetable(class_group) -> %{slots: %{{day, period_id} => slot_view}, tally: [tally_row]}` where `slot_view` carries `%{teaching_context_id, subject, teacher_email, day, period_id}` (subject/teacher preloaded), and `tally_row` is `%{teaching_context_id, subject, placed, required, status}` with `placed` = count of that context's slots, `required` = `weekly_hours`, `status` in `[:under, :exact, :over]`. One tally row per class assignment (`Assignments.list_for_class/1`), including assignments with zero placed (`placed: 0`).
  - `Timetables.teacher_timetable(workspace, user) -> %{{day, period_id} => slot_view}` for all slots in the workspace whose `teaching_context.teacher_user_id == user.id`; `slot_view` additionally carries the `class_label` so a teacher sees which class each cell is.

- [ ] **Step 1: Write the failing tests.** Setup: school, class `cg`, assign "Maths" (weekly_hours 5) and "EPS" (weekly_hours 2) to the head; seed periods; place Maths in 3 distinct cells and EPS in 2. Assert on `class_timetable/1`: `slots` has 5 entries keyed by `{day, period_id}`; the Maths tally row is `placed: 3, required: 5, status: :under`; the EPS row is `placed: 2, required: 2, status: :exact`; an assignment with no placements appears with `placed: 0, status: :under`; a slot_view exposes the subject and teacher email. For `teacher_timetable/2`: with the head teaching in two different classes, the returned map includes cells from BOTH classes, each carrying the right `class_label`; a teacher with no slots gets `%{}`.

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Implement `class_timetable/1`** — one scoped read of the class's slots (preload `teaching_context` for subject/teacher), fold into the `{day, period_id} => slot_view` map; build the tally by grouping placements per `teaching_context_id` and joining against `Assignments.list_for_class/1` for `required`/`subject`; derive `status` by comparing `placed` to `required`.

- [ ] **Step 4: Implement `teacher_timetable/2`** — scoped read filtering slots by `workspace_id` and `teaching_context.teacher_user_id == user.id`, preload `class_group` + `teaching_context`, fold into the keyed map with `class_label`.

- [ ] **Step 5: Run to green**, then **commit** (`feat(school): timetable reads — class grid, hours tally, teacher view (P2.7)`).

---

### Task 4: Periods configuration page `/school/periods` (admin)

**Files:**
- Create: `lib/teacher_assistant_web/live/school/periods_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add `live "/school/periods", School.PeriodsLive, :index` in the `:school_workspace` live session), `lib/teacher_assistant_web/live/school/settings_live.ex` (add an admin-only link to `/school/periods`)
- Test: `test/teacher_assistant_web/live/school/periods_live_test.exs` (create)

**Interfaces:**
- Consumes: `Timetables.list_periods/1`, `Timetables.build_default_periods/1`; `Permissions.admin?/1`. Add `Timetables.update_period(period, attrs) -> {:ok, %Period{}} | {:error, term}` and `Timetables.delete_period(period) -> :ok | {:error, :has_slots}` to the context (delete blocked when any `TimetableSlot` references the period — mirror the P2.2 assignment "has data" pattern).
- Produces: an admin page listing periods (position, label, times, kind), an inline edit form per period (`phx-change`/`phx-submit`), a "seed default schedule" button shown when there are no periods, and a delete action that surfaces a friendly error when slots reference the period.

- [ ] **Step 1: Write the failing tests** (ConnCase, `register_and_log_in_user`, put `workspace_id` in session). Assert: (a) an admin sees the page; when no periods exist, clicking the seed button (`build_default_periods`) populates the list; (b) editing a period's `start_time`/`label` persists via `Timetables.list_periods/1`; (c) deleting a period with a referencing `TimetableSlot` shows the friendly "has slots" message and the period remains; (d) a non-admin member is redirected (mount gate), and a forged update/delete/seed event makes no change.

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Add `update_period/2` and `delete_period/1`** to `Timetables` (`delete_period` first checks for referencing slots → `{:error, :has_slots}`).

- [ ] **Step 4: Build `PeriodsLive`** — admin-gated mount (non-admin → redirect `/school`); assign `periods`; handlers `seed` / `update_period` / `delete_period`, each re-checking `admin?` server-side and resolving the target period from the socket-loaded list; reload after each. Follow `settings_live.ex` / `class_live.ex` conventions and the component kit (`page_header`, `empty_state`, inputs).

- [ ] **Step 5: Wire the route and the settings link** (admin-only `:if`).

- [ ] **Step 6: Run to green**, then **commit** (`feat(school): periods configuration page (P2.7)`).

---

### Task 5: Per-class timetable grid editor `/school/classes/:id/timetable`

**Files:**
- Create: `lib/teacher_assistant_web/live/school/timetable_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add `live "/school/classes/:id/timetable", School.TimetableLive, :show`), `lib/teacher_assistant_web/live/school/class_live.ex` (add an "Emploi du temps" link in the class-detail action bar, visible to `@manage?` i.e. admin or form master)
- Test: `test/teacher_assistant_web/live/school/timetable_live_test.exs` (create)

**Interfaces:**
- Consumes: `class_timetable/1`, `place_slot/2`, `clear_slot/3`, `list_periods/1`, `Assignments.list_for_class/1`, `Permissions.admin_or_form_master?/2`, `fetch_owned_class_group/2`, `DayOfWeek` values.
- Produces: a grid (rows = periods in order, break rows rendered as full-width non-editable labels; columns = Mon–Sat) where each lesson cell for an admin is a `<select>` of the class's assignments (option label `"{subject} — {teacher_email}"`, value = `teaching_context_id`) with a blank/clear option, `phx-change="place"` carrying `day` + `period_id`; the hours tally is rendered beside/below the grid. A form master sees the same grid read-only (cells as text, no selects).

- [ ] **Step 1: Write the failing tests.** Assert: (a) admin loads the grid; the period rows and Mon–Sat headers render; (b) selecting an assignment in a cell (`render_change` on that cell's form with `teaching_context_id`) persists a slot (`class_timetable/1` shows it) and the tally updates; (c) clearing a cell removes it; (d) a placement that would double-book the teacher (pre-seed a clashing slot in another class for the same teacher/day/period) flashes the clash message and creates no slot; (e) a form master of the class sees the grid but NO cell selects, and a forged `place` event is rejected; (f) a non-member and a cross-school class id are redirected (mount `false -> /school`, `_ -> /school/classes`, mirroring P2.5).

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Build `TimetableLive`** — mount gates on `admin_or_form_master?` for the fetched class (assign `admin?` for edit-vs-read branching); assign `periods`, `assignments`, and the `class_timetable/1` result; `handle_event("place", %{"day","period_id","teaching_context_id"})` re-checks admin, resolves the assignment from the socket-loaded list, calls `place_slot/2`, flashes the friendly clash message on `{:error, {:teacher_clash, label}}`, and reloads; `handle_event("clear", %{"day","period_id"})` similarly. Render the grid + tally; break rows non-editable; cells read-only for a form master.

- [ ] **Step 4: Add the class-detail link + route.**

- [ ] **Step 5: Run to green**, then **commit** (`feat(school): per-class timetable grid editor (P2.7)`).

---

### Task 6: Teacher self-view `/school/timetable/me`

**Files:**
- Create: `lib/teacher_assistant_web/live/school/my_timetable_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add `live "/school/timetable/me", School.MyTimetableLive, :index`), the school nav (wherever the school shell renders its nav links — locate via the existing `/school/classes` nav entry) to add an "Mon emploi du temps" link for members.
- Test: `test/teacher_assistant_web/live/school/my_timetable_live_test.exs` (create)

**Interfaces:**
- Consumes: `Timetables.teacher_timetable/2`, `Timetables.list_periods/1`, `Permissions.member?/1`, `scope.current_user`.
- Produces: a read-only Mon–Sat grid of the current user's slots across all their classes; each filled cell shows `class_label` + `subject`.

- [ ] **Step 1: Write the failing tests.** Assert: (a) a teacher assigned in a class with placed slots sees those cells (class + subject) in the grid; (b) a member who teaches nothing sees an empty grid (and a friendly empty state); (c) a non-school scope is redirected (mount guard like the other school LiveViews).

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Build `MyTimetableLive`** — mount requires a school scope; assign `periods` and `teacher_timetable(workspace, current_user)`; render the read-only grid. Reuse the grid rendering approach from Task 5 (extract a shared grid function-component only if it is genuinely reused without contortion; otherwise keep the two renders separate — do not over-abstract).

- [ ] **Step 4: Add the route + nav link.**

- [ ] **Step 5: Run to green**, then **commit** (`feat(school): teacher self timetable view (P2.7)`).

---

### Task 7: Timetable print (per-class + teacher) A4

**Files:**
- Create: `lib/teacher_assistant_web/controllers/timetable_print_controller.ex`, `lib/teacher_assistant_web/controllers/timetable_print_html.ex`, `lib/teacher_assistant_web/controllers/timetable_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (add, next to the existing bulletin print routes in the first browser scope: `get "/school/classes/:id/timetable/print", TimetablePrintController, :class` and `get "/school/timetable/me/print", TimetablePrintController, :me`), add "Imprimer" links on the Task 5 and Task 6 pages.
- Test: `test/teacher_assistant_web/controllers/timetable_print_controller_test.exs` (create)

**Interfaces:**
- Consumes: `Timetables.class_timetable/1` (or a slots read), `list_periods/1`, `teacher_timetable/2`; `Workspaces.scope_for/3`, `Permissions.admin_or_form_master?/2`, `fetch_owned_class_group/2`. Mirror `bulletin_print_controller.ex` exactly (session-resolved user, `put_layout(false)` + `put_root_layout(false)`, `:school` guard, redirect `/school` on any failure).
- Produces: an A4 timetable HTML — header with school name, class label (or teacher email) + année + the day's bell times; a periods × Mon–Sat grid of subject (+ teacher for the class print). `:class` is gated by `admin_or_form_master?` for the class; `:me` renders the current user's own grid.

- [ ] **Step 1: Write the failing tests.** Assert: (a) the class timetable print returns 200 and the body contains the school name, the class label, and a placed subject; (b) a non-admin non-form-master member is redirected from the class print; (c) `/school/timetable/me/print` returns 200 for a teacher and shows one of their subjects.

- [ ] **Step 2: Run and confirm failure.**

- [ ] **Step 3: Build the controller + HTML module + template** mirroring the bulletin print files; render the grid with real bell times (`start_time`–`end_time`) per period row.

- [ ] **Step 4: Wire routes + the two "Imprimer" links.**

- [ ] **Step 5: Run to green**, then **commit** (`feat(school): A4 timetable print — class + teacher (P2.7)`).

---

### Task 8: gettext extract + FR/EN + final gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/fr/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po` (+ any format-only rewrites the gate produces)

**Interfaces:**
- Consumes: all msgids added in Tasks 4–7.

- [ ] **Step 1: Extract + merge** (`mix gettext.extract --merge`).

- [ ] **Step 2: Fill every new msgid in BOTH locales.** New strings include the six day names (Lundi…Samedi and their EN Monday…Saturday), "Emploi du temps" (EN "Timetable"), "Période" (EN "Period"), "Récréation" (EN "Break"), "Mon emploi du temps" (EN "My timetable"), the teacher-clash message (e.g. FR "Cet enseignant a déjà cours dans %{class} à cette période." / EN "This teacher already has a class in %{class} at this period."), the "has slots" delete error, the seed-default button, the hours-tally labels, and print headers. FR msgstr mirrors the French source; EN msgstr is the English translation. Fill any other newly-empty msgid the extract surfaces from P2.7 work; do not touch pre-existing unrelated fuzzy/empty entries. Verify no new P2.7 msgid is empty in either locale with a grep over the day names / "emploi du temps" / "Période".

- [ ] **Step 3: Run the full gate** (`mix precommit`). It must format + compile + run the whole suite green. If it fails ONLY with a `users_unique_email_index` collision, re-run `mix test --seed 0` to confirm the known fixture flake; report both. Commit any format-only rewrites the `format` step produced.

- [ ] **Step 4: Commit** (`chore(i18n): extract + FR/EN for P2.7 timetables`), including `priv/gettext` and any swept `lib`/`test` format changes.

---

## Self-Review

**Spec coverage:**
- Data model — enums + `Period` (T1), `TimetableSlot` (T2) ✓
- Clash detection (teacher, server-side, scoped, replace-in-place safe) — T2 ✓
- Hours reconciliation tally — T3 ✓
- Context API (`list_periods`, `build_default_periods`, `class_timetable`, `place_slot`, `clear_slot`, `teacher_timetable`) — T1/T2/T3; plus `update_period`/`delete_period` for the config page — T4 ✓
- Per-class grid editor + form-master read + class-detail link — T5 ✓
- Teacher self-view + nav — T6 ✓
- Periods config page + settings link — T4 ✓
- Print (class + teacher) with bell times — T7 ✓
- Access model (admin edits, form-master read, teacher self, workspace-scoped, re-checked) — T4/T5/T6/T7 ✓
- Scope boundaries (one timetable/year, no rooms, no auto-schedule, no substitutions) — respected; nothing in the plan adds them ✓
- i18n + gate — T8 ✓

**Placeholder scan:** No TBD/TODO. Per the user's explicit instruction this plan carries no code blocks; each task instead names the exact sibling file to mirror, the exact signatures/shapes to produce, and the concrete test cases to assert — actionable without inline code.

**Type consistency:** `Timetables.place_slot/2`, `clear_slot/3`, `class_timetable/1`, `teacher_timetable/2`, `list_periods/1`, `build_default_periods/1`, `update_period/2`, `delete_period/1` are introduced in T1–T4 and consumed with matching arities in T4–T7. The `slot_view` shape (`teaching_context_id`, `subject`, `teacher_email`, `day`, `period_id`, and `class_label` on the teacher/print views) and `tally_row` shape (`teaching_context_id`, `subject`, `placed`, `required`, `status`) are defined in T3 and consumed by T5/T6/T7. Enum atoms (`:lesson`/`:break`, `:monday`…`:saturday`) are consistent across resources, reads, and views.

**Decomposition note:** T2 (placement + clash) and T3 (reads + tally) are split so a reviewer can gate the clash logic independently of the read shaping. T5/T6 share a grid rendering; the plan says extract a shared component only if it reuses cleanly, else keep separate — avoiding premature abstraction.
