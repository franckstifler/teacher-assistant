# J3 — Rooms and teacher unavailability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rooms (home and shared, with capacity) and per-teacher weekly unavailability, set by the censeur and
shown as problems in the J4 timetable editor, with suggestions that avoid them.

**Architecture:** Two new tenant resources: `Room` in `Organization` and `TeacherUnavailability` in `Timetabling`.
There are also three nullable room FKs: `ClassGroup.home_room_id`, `Subject.default_room_id` and
`TimetableSlot.room_id`, where nil means the home room. The pure `TimetableConflicts` gains room clashes,
unavailability, capacity warnings and room/availability-aware suggestions. `Timetabling` resolves the effective
room in `school_slots/1`, keeps the room with the lesson on move and swap, and fills the default room on place.
Two new pages: « Salles » and « Disponibilités ». The editor, the print view and « Mon emploi du temps » show
the room.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3 (attribute multitenancy, policies), AshPostgres, Gettext (French msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"J3 — Rooms and teacher unavailability (spec)".

## Global Constraints

- Worktree `.claude/worktrees/j3`, branch `j3-rooms-availability`, `MIX_TEST_PARTITION=3` for every `mix test`.
  Stage explicit paths only (never `git commit -a`): the user runs parallel sessions.
- Migrations only with `mix ash.codegen --dev` (then `mix ash.migrate`). Never hand-write migrations. The final
  `mix ash.codegen --check` must be clean.
- No bare `:atom` attributes. `RoomKind` is an `Ash.Type.Enum`.
- Every new FK uses the composite form `match_with: [workspace_id: :workspace_id], match_type: :full` like
  `TimetableSlot`'s references. Room FKs use `on_delete: :nilify`.
- Writes go through the admin axis (`{Checks.SchoolRole, any_of: :admin}`). `Room` reads: `:member`.
  `TeacherUnavailability` reads: `:admin` only.
- Problems are saved and shown, never refused. The only refusals stay as today: a closed cell, a course not of
  the class, an unknown period. `set_slot_room` adds one more: an inactive room or another school's room.
- Effective room = `slot.room_id || class.home_room_id || nil`. A nil effective room never clashes and is
  never checked for capacity.
- The capacity warning skips a class's own home room, sums the member classes for a combined lesson, and is
  not counted in « n conflits ».
- Count = teacher-clash groups + room-clash groups (one per room/day/period) + unavailable slots.
- French copy (msgids) fixed by the spec:
  - « Salle informatique est déjà occupée par 3e A. » → `"%{room} est déjà occupée par %{classes}."`
  - `"%{teacher} n'est pas disponible le %{day} à %{time}."`
  - `"%{size} élèves pour %{capacity} places en %{room}."`
  - « Salle de la classe (%{room}) » / « Salle de la classe »
  - « Disponibilités des enseignants », « Indisponible : %{days} », « Matin », « Après-midi »,
    « indisponible à ce créneau »
  - Room kinds: Salle de classe, Laboratoire, Salle informatique, Atelier, Terrain / salle de sport, Autre.
- Strings go through gettext. After `mix gettext.extract --merge`, fill and unflag every new fuzzy entry: the
  guard test fails otherwise.
- Run `mix precommit` before the last commit. It does not fail on warnings, so also check
  `mix compile --warnings-as-errors` yourself.

## Review Focus

1. A swap where one lesson is in the computer room and the other in the home room: after the swap each
   lesson keeps its own room. A swap is never suggested if it would put either lesson in an occupied room
   (tests in Tasks 2 and 3).
2. Placing the same course again on its own cell after the censeur picked a room by hand: the room is kept
   (test in Task 3).
3. Two classes sharing one home room (morning/afternoon shift) at different times: no clash. At the same time:
   one room clash (test in Task 2).
4. A combined course (MACO + ELEQ) placed in Labo SVT (capacity 40) with 25 + 30 students: one amber warning,
   not counted; no room clash between its own classes (test in Task 2).
5. A crafted `set_room` or `toggle` event with another school's room or teacher id: refused, nothing written
   (tests in Tasks 5 and 6).

---

### Task 0: Worktree

- [ ] **Step 1: Make sure the spec and this plan are committed on `main`, then create the worktree**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/j3 -b j3-rooms-availability main
cd .claude/worktrees/j3 && mix deps.get
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/timetable_conflicts_test.exs test/teacher_assistant_web/live/school/timetable_editor_live_test.exs
```

Expected: 0 failures.

---

### Task 1: Data — rooms, room FKs, unavailability

**Files:**
- Create: `lib/teacher_assistant/academics/room_kind.ex`, `lib/teacher_assistant/academics/room.ex`,
  `lib/teacher_assistant/academics/teacher_unavailability.ex`
- Modify: `lib/teacher_assistant/organization.ex` (register `Room`, functions below),
  `lib/teacher_assistant/timetabling.ex` (register `TeacherUnavailability`, functions below),
  `lib/teacher_assistant/academics/class_group.ex` (`home_room_id`, add to the `update` accept list),
  `lib/teacher_assistant/academics/subject.ex` (`default_room_id`, add to `create` and the default `update`
  accept lists), `lib/teacher_assistant/academics/timetable_slot.ex` (`room_id`; accepted by `:create`,
  `:update`, `:place`), `lib/teacher_assistant/enrollment.ex`
- Generated: migrations and snapshots from `mix ash.codegen --dev`
- Test: `test/teacher_assistant/organization/rooms_test.exs`,
  `test/teacher_assistant/academics/teacher_unavailability_test.exs`

**Interfaces:**
- Produces:
  - `RoomKind` values `[:classroom, :laboratory, :computer_room, :workshop, :sports, :other]`, plus `label/1`
    (gettext, copy in Global Constraints).
  - `Room`: `name` (string, required, trimmed, non-empty), `kind` (`RoomKind`, default `:classroom`),
    `capacity` (integer, nullable, `min: 1`), `active?` (boolean, default true). Identity `:unique_name` on
    `[:workspace_id, :name_key]`: add a `name_key` attribute set by a change to `String.downcase(String.trim(name))`.
    Actions: `:read`, `:create`, `:update` (accept `name, kind, capacity, active?`), `:destroy`.
  - `Organization.list_rooms(scope) :: [Room]` (sorted by name), `list_active_rooms(scope) :: [Room]`,
    `create_room(scope, attrs)`, `update_room(scope, room, attrs) :: {:ok, Room} | {:error, _}`,
    `delete_room(scope, room) :: :ok | {:error, :in_use} | {:error, _}`,
    `room_in_use?(scope, room) :: boolean` (any `TimetableSlot.room_id`, `ClassGroup.home_room_id` or
    `Subject.default_room_id` in any year).
  - `Enrollment.set_home_room(scope, class_group, room_id | nil) :: {:ok, ClassGroup} | {:error, _}`
  - `Enrollment.class_sizes(scope, year) :: %{class_group_id => non_neg_integer}`: enrollments per class in
    the year, from one grouped query or a count per class.
  - `TeacherUnavailability`: `academic_year_id`, `teacher_user_id` (FK `User`, simple reference — no
    `workspace_id` on users), `day` (`DayOfWeek`), `period_id` (composite FK). Identity
    `[:academic_year_id, :teacher_user_id, :day, :period_id]`. `YearOpen` validation with `path: []`. Read
    action `:for_year` (argument `academic_year_id`).
  - `Timetabling.unavailability(scope) :: MapSet.t({teacher_id, day, period_id})`: active year, empty when
    there is none.
  - `Timetabling.set_unavailable(scope, teacher_user_id, [{day, period_id}], blocked? :: boolean) :: :ok | {:error, _}`:
    in one transaction, creates the missing rows (`true`) or deletes the existing ones (`false`). Refused
    `{:error, :invalid}` when the user is not an active member of the school or a period is not one of the
    school's lesson periods.

- [ ] **Step 1: Write the failing tests**

`rooms_test.exs` (setup like `timetables_slots_test.exs`: a head, a school, an active year, a class):

```elixir
test "a room is created, listed by name, unique per school regardless of case", ctx
  # create "Labo SVT" (kind :laboratory, capacity 40), then "salle info" → list_rooms names == ["Labo SVT", "salle info"]
  # create "labo svt" → {:error, _}
test "capacity must be at least 1 and the name not blank", ctx
test "a teacher (non-admin member) can read rooms but not create one", ctx
  # Ash.Error.Forbidden on create_room with a teacher scope
test "delete_room is refused while a class, a subject or a slot uses the room, allowed once unused", ctx
  # set_home_room → {:error, :in_use}; set_home_room(nil) → :ok
test "a class's home room and a subject's default room are set and cleared", ctx
test "a room of another school cannot be a home room", ctx
  # composite FK → {:error, _}
test "class_sizes counts enrollments per class", ctx
```

`teacher_unavailability_test.exs`:

```elixir
test "set_unavailable blocks and unblocks cells; unavailability/1 returns them", ctx
  # block [{:monday, p1.id}, {:monday, p2.id}] → MapSet == {{t, :monday, p1}, {t, :monday, p2}}
  # block the same again → no duplicate; unblock [{:monday, p1.id}] → only p2 left
test "a plain teacher can neither read nor write unavailability", ctx
test "a non-member user id is refused with :invalid", ctx
test "a closed year refuses changes", ctx
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/organization/rooms_test.exs test/teacher_assistant/academics/teacher_unavailability_test.exs`
Expected: FAIL (modules undefined).

- [ ] **Step 3: Implement the resources, attributes and functions above, then run `mix ash.codegen --dev j3_rooms_availability && mix ash.migrate`**

`Room` copies `Holiday`'s shape: multitenancy, policies, `references` with `workspace` `on_delete: :delete`.
Add each room FK to the existing `references` block with `on_delete: :nilify`, `match_with`, `match_type: :full`
and `index?: true`. `TimetableSlot`'s `:place` keeps `upsert_fields [:teaching_context_id]`: Task 3 decides
the room. `set_unavailable` uses `Ash.transact`.

- [ ] **Step 4: Run the new tests plus the composite-FK, schema and tenancy tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/organization/rooms_test.exs test/teacher_assistant/academics/teacher_unavailability_test.exs test/teacher_assistant/composite_fk_test.exs test/teacher_assistant/schema_test.exs test/teacher_assistant/tenancy_isolation_test.exs`
Expected: PASS. If `tenancy_isolation_test` lists every tenant resource, add `Room` and `TeacherUnavailability` to it.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/room_kind.ex lib/teacher_assistant/academics/room.ex lib/teacher_assistant/academics/teacher_unavailability.ex lib/teacher_assistant/organization.ex lib/teacher_assistant/timetabling.ex lib/teacher_assistant/academics/class_group.ex lib/teacher_assistant/academics/subject.ex lib/teacher_assistant/academics/timetable_slot.ex lib/teacher_assistant/enrollment.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/organization/rooms_test.exs test/teacher_assistant/academics/teacher_unavailability_test.exs
git commit -m "feat(j3): rooms, room links on classes/subjects/slots, teacher unavailability"
```

---

### Task 2: Conflicts — rooms, unavailability, capacity (pure)

**Files:**
- Modify: `lib/teacher_assistant/academics/timetable_conflicts.ex`
- Test: `test/teacher_assistant/academics/timetable_conflicts_test.exs`

**Interfaces:**
- Consumes: slot maps now also carry `room_id` (effective), `home_room_id`, `class_size`. `unavailable` is a
  `MapSet` of `{teacher_id, day, period_id}`. `capacities` is `%{room_id => capacity | nil}`.
- Produces (existing `clashes/1` and `busy?/5` keep their meaning):
  - `room_clashes([slot]) :: %{{class_group_id, day, period_id} => [other_class_group_id]}`: same effective
    room (non-nil), same time, more than one unit (the same `unit/1` as teacher clashes).
  - `unavailable_cells([slot], unavailable) :: MapSet.t({class_group_id, day, period_id})`
  - `over_capacity([slot], capacities) :: %{{class_group_id, day, period_id} => %{size: n, capacity: c, room_id: id}}`:
    skips slots whose room is their own `home_room_id` and rooms with a nil capacity. A combined unit
    sums `class_size` over its slots in that room at that time and flags each of its cells.
  - `count([slot], unavailable \\ MapSet.new()) :: non_neg_integer`: teacher-clash groups + room-clash groups
    + unavailable slots.
  - `problem?(slots, unavailable, {class_group_id, day, period_id}) :: boolean`: teacher clash, room clash or
    unavailable.
  - `available?(unavailable, teacher_id, day, period_id) :: boolean`
  - `room_busy?([slot], room_id, day, period_id, ignore_ids) :: boolean`: false for a nil room.
  - `suggestions([slot], open_cells, class_group_id, cell, unavailable \\ MapSet.new())`: same shape as
    today. It now runs when `problem?` is true (not only on a teacher clash). Moves also require
    `available?` and `not room_busy?` for the lesson's own `room_id` at the target. Swaps also require
    each lesson to be available at its new time and its room free there (ignoring both slots). Each lesson
    keeps its own room. When `room_id` equals `home_room_id`, the room does not move with the lesson: the
    target cell's room is the same home room, so the check holds.

- [ ] **Step 1: Write the failing tests** (extend the `s/6` helper with `room`, `home`, `size` keys
  defaulting to nil, nil, 30)

```elixir
test "two classes in the same shared room at the same time: a room clash on both, counted once"
  # room "info" for 6a and 6b, different teachers → room_clashes keys both cells; count == 1
test "two classes sharing a home room at different times: no clash; same time: one clash"
test "a nil effective room never clashes"
test "a combined course in one room is not a room clash between its own classes"
test "a lesson at an unavailable time is a problem and counted"
  # unavailable = MapSet.new([{"t", :monday, "p1"}]) → unavailable_cells has {"6a", :monday, "p1"}; count(slots, unavailable) == 1
test "teacher clash + room clash + unavailable add up in count"
test "over capacity: shared room flagged with size and capacity, home room skipped, nil capacity skipped"
test "over capacity: a combined course sums its classes (25 + 30 > 40), flagged on both, not counted"
test "suggestions for an unavailable lesson: moves only to available times with the room free"
test "suggestions never swap a lesson into an occupied room or an unavailable time"
test "suggestions for a room clash exist; none for a problem-free cell"
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/timetable_conflicts_test.exs`
Expected: FAIL (undefined functions).

- [ ] **Step 3: Implement the functions above in `TimetableConflicts`** and update the moduledoc (spec J3
  rules 11–15). Reuse `unit/1` for room groups. The old tests must keep passing with the default arguments.

- [ ] **Step 4: Run the file again**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/timetable_conflicts.ex test/teacher_assistant/academics/timetable_conflicts_test.exs
git commit -m "feat(j3): room clashes, unavailability and capacity in timetable conflicts"
```

---

### Task 3: Timetabling — rooms on lessons

**Files:**
- Modify: `lib/teacher_assistant/timetabling.ex`, `lib/teacher_assistant/academics/timetable_slot.ex`
  (`place_one/4` passes `room_id`; the `:place_combined` placements carry it)
- Test: `test/teacher_assistant/academics/timetable_rooms_test.exs`, plus one case in
  `test/teacher_assistant/timetabling_reassign_test.exs`

**Interfaces:**
- Consumes: Task 1 (`Room`, FKs, `unavailability/1`, `Enrollment.class_sizes/2`) and Task 2 (slot keys).
- Produces:
  - `place_slot/3`, `place_combined_slot/4`: when the cell already holds the same `teaching_context_id`, return
    `{:ok, existing}` (combined: `{:ok, existing_slots}`) without writing. Otherwise upsert with
    `room_id = default_room_id(scope, tc)`: the subject's `default_room_id` when `tc.subject_id` is set and
    that room is active, else nil. Same room for every member of a combined course (from the first
    context with a subject). `:place`'s `upsert_fields` becomes `[:teaching_context_id, :room_id]`.
  - `swap_slots/4` exchanges `room_id` along with `teaching_context_id` (still one transaction). `move_slot/4`
    is unchanged: the row keeps its room.
  - `set_slot_room(scope, class_group, {day, period_id}, room_id | nil) :: :ok | {:error, :invalid}`: refused
    for an empty cell, an inactive room or an unknown room id (one `Ash.get` under the scope, which also
    stops other schools' rooms). For a combined lesson it sets every member class's slot in one
    transaction.
  - `school_slots/1` maps gain `room_id` (`slot.room_id || class.home_room_id`), `home_room_id` and
    `class_size` (from `Enrollment.class_sizes/2`, default 0). Load `:class_group` along with
    `:teaching_context`.
  - `room_capacities(scope) :: %{room_id => capacity | nil}`: every room, active or not.
  - `reassign_candidates(scope, tc, slots, unavailable \\ MapSet.new())`: also drops teachers unavailable at
    any of `tc`'s slots.
  - `class_timetable/2` and `teacher_timetable/2` slot views gain `room_name` (effective room's name or nil)
    and `room_id`.

- [ ] **Step 1: Write the failing tests** (setup: two classes, two courses with different teachers, a subject
  « Informatique » with default room « Salle info », a class home room « B12 »)

```elixir
test "placing a course whose subject has a default room puts the lesson there"
test "a deactivated default room is skipped (room_id nil)"
test "re-placing the same course on its cell keeps a hand-picked room"
  # set_slot_room(..., labo.id) then place_slot same tc → slot.room_id == labo.id
test "replacing the occupant with another course recomputes the room"
test "move keeps the room; swap exchanges the rooms with the courses"
test "set_slot_room sets, clears to the home room (nil), refuses an inactive or foreign room and an empty cell"
test "a combined course gets one room on every member class, by place and by set_slot_room"
test "school_slots resolves the effective room, home room and class size"
test "class_timetable shows the shared room's name, and the home room's when no room is set"
```

In `timetabling_reassign_test.exs`:

```elixir
test "a teacher unavailable at one of the lesson's slots is not offered"
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/timetable_rooms_test.exs test/teacher_assistant/timetabling_reassign_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the interface above**

- [ ] **Step 4: Run them plus every existing timetable test**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/timetable_rooms_test.exs test/teacher_assistant/timetabling_reassign_test.exs test/teacher_assistant/academics/timetables_slots_test.exs test/teacher_assistant/academics/timetables_combined_test.exs test/teacher_assistant/academics/timetable_editing_test.exs test/teacher_assistant/academics/timetables_reads_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/timetabling.ex lib/teacher_assistant/academics/timetable_slot.ex test/teacher_assistant/academics/timetable_rooms_test.exs test/teacher_assistant/timetabling_reassign_test.exs
git commit -m "feat(j3): default rooms on placement, rooms follow swaps, set_slot_room"
```

---

### Task 4: « Salles » page and the subjects' default room

**Files:**
- Create: `lib/teacher_assistant_web/live/school/rooms_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/settings/rooms", School.RoomsLive, :index`, next
  to holidays), `lib/teacher_assistant_web/live/school/settings_live.ex` (a `hub_card` `id="rooms-link"`,
  icon `hero-building-office`, title « Salles », text « Salles, laboratoires et salles de classe. », placed
  after `holidays-link` and shown to the admin axis; in the subjects table, a « Salle par défaut » select per
  subject saved with `Curriculum.update_subject/3`)
- Test: `test/teacher_assistant_web/live/school/rooms_live_test.exs`, plus a case in
  `test/teacher_assistant_web/live/school/settings_live_test.exs`

**Interfaces:**
- Consumes: the Task 1 `Organization` room functions and `Enrollment.set_home_room/3`.
- Produces: DOM ids for tests: `#rooms-table`, `#room-<id>`, `#new-room-form`, `#room-form-<id>`,
  `#deactivate-room-<id>`, `#delete-room-<id>` (only when `room_in_use?` is false), `#home-rooms`,
  `#home-room-<class_id>` (a form with a select `room_id`), `#subject-room-<subject_id>`.

Page (admin axis via `Timetabling.can_edit_timetable?/1`; others `push_navigate` to `/school`, like the editor).
Header eyebrow « Paramètres », title « Salles ». Room rows show the name, `RoomKind.label`, the capacity
(« — » when nil) and an « Inactive » badge. Add and edit use `<.input>` forms. « Salles des classes » lists the
active year's classes (`SchoolTemplates.class_sort_key/1`) with a select of active rooms (« — » = nil). An
option already used by another class is labelled `"%{room} (déjà : %{classes})"`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "a teacher is redirected"
test "add a room, edit its capacity, deactivate it"
test "delete is offered only for an unused room"
test "a class's home room is chosen and cleared; a shared home room shows « déjà : 6e A »"
test "a crafted home-room event with another school's room id changes nothing"
test "settings hub links to the rooms page"            # in settings_live_test
test "a subject's default room is saved from the subjects page"   # in settings_live_test
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/rooms_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the page, the route, the hub card and the subject select**

- [ ] **Step 4: Run the tests again**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/rooms_live.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/live/school/settings_live.ex test/teacher_assistant_web/live/school/rooms_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs
git commit -m "feat(j3): rooms settings page, class home rooms, subject default rooms"
```

---

### Task 5: « Disponibilités » page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/availability_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/timetable/availability", School.AvailabilityLive, :index`
  **before** any `/school/timetable/:x` route that could shadow it), `lib/teacher_assistant_web/spaces.ex`
  (`availability()` item, id `"availability"`, label « Disponibilités », icon `hero-clock`, placed right after
  `timetable_editor()` in the **censeur** space only)
- Test: `test/teacher_assistant_web/live/school/availability_live_test.exs`

**Interfaces:**
- Consumes: `Timetabling.unavailability/1`, `Timetabling.set_unavailable/4`, `Timetabling.teacher_timetable/2`,
  `Attendance.school_calendar/1`, `Attendance.list_periods/1`, `SchoolCalendar.open_cell?/3`,
  `Accounts.list_members/1`.
- Produces: DOM ids `#teacher-picker`, `#teacher-<user_id>` (with the summary text), `#avail-grid`,
  `#avail-<day>-<period_id>` (class `blocked` when unavailable; shows the class label when the teacher has a
  lesson there), `#avail-day-<day>`, `#avail-morning-<day>`, `#avail-afternoon-<day>`.

Behaviour:
- Admin axis only; others are redirected to `/school`.
- Teachers are active members with `:teacher` in their roles: those with blocked times first, then by name.
  `?teacher=<id>` selects one, defaulting to the first. An id that is not in the list falls back to the first.
- Clicking a cell toggles it.
- The day, morning and afternoon buttons apply to the open lesson periods of that day. Morning means
  `start_time < ~T[13:00:00]`, afternoon the rest. If every period in the group is blocked, the button
  unblocks them all; otherwise it blocks them all.
- Closed cells are greyed and do nothing.
- Summary per teacher: blocked days in day order. A whole day reads « lundi »; all the morning or all the
  afternoon periods read « mercredi matin » / « mercredi après-midi »; any other mix reads « jeudi (2 périodes) ».
  The parts are joined with « , » after « Indisponible : ». A teacher with nothing blocked shows nothing.
- The editor's header gets a link `#availability-link` to this page (done in Task 6).

- [ ] **Step 1: Write the failing tests**

```elixir
test "a teacher is redirected"
test "picking a teacher and toggling a cell blocks then unblocks it"
test "the day header blocks every open period of the day; again unblocks"
test "afternoon blocks only periods from 13:00; the summary reads « Indisponible : mercredi après-midi »"
test "a cell holding the teacher's lesson shows the class label and can still be blocked"
test "a crafted ?teacher= id from another school falls back to the first teacher, and a crafted toggle for it writes nothing"
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/availability_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the page, the route and the menu item**

- [ ] **Step 4: Run the tests plus the spaces tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/availability_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: PASS. If `spaces_test` pins the censeur items, add `"availability"` there.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/availability_live.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex test/teacher_assistant_web/live/school/availability_live_test.exs
git commit -m "feat(j3): teacher availability page for the censeur"
```

---

### Task 6: Editor — room and availability problems

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/timetable_editor_live.ex`
- Test: `test/teacher_assistant_web/live/school/timetable_editor_live_test.exs`

**Interfaces:**
- Consumes: Task 2's functions; Task 3's `school_slots/1` keys, `room_capacities/1`, `set_slot_room/4`,
  `reassign_candidates/4` and the slot views' `room_name`; `Organization.list_active_rooms/1`;
  `Timetabling.unavailability/1`.
- Produces: DOM ids `#availability-link`, `#room-select` (form, `phx-change="set_room"`, select name `room_id`,
  value `""` = home room), `#room-conflict-text`, `#unavailable-text`, `#capacity-text`; class
  `capacity-cell` (amber border) on a warned cell.

Behaviour (spec rule 19):
- `load/1` adds `unavailable`, `room_clashes`, `unavailable_cells`, `over_capacity` (from `room_capacities`)
  and `rooms` (active, for the select and for names).
- A cell is red (`clash-cell`) when `problem?` is true.
- The count is `count(slots, unavailable)`. The class tab dot appears when any cell of the class has a problem.
- The cell shows `room_name` in small text when the effective room is not the class's home room.
- The panel shows one line per problem, using the copy in Global Constraints. The day is lowercase and the
  time is `hm(period.start_time)`. A room clash lists the other classes joined with « , ». The capacity line is
  amber.
- The room select appears only on an occupied cell. Its first option is
  « Salle de la classe (B12) » / « Salle de la classe »; then the active rooms.
- `fixes` are computed whenever the cell has a problem. `reassign` fixes are offered only for a teacher clash
  or an unavailable lesson.
- The chips' red state and tooltip also cover « %{teacher} est indisponible à ce créneau ».
- `set_room` with an id that is not in `@rooms` → flash « Modification non enregistrée. », nothing written.

- [ ] **Step 1: Write the failing tests** (in the existing file's setup, add rooms and a second teacher where needed)

```elixir
test "two classes in the computer room at the same time: red, counted, and the panel names the other class"
test "a lesson placed at the teacher's unavailable time: red, counted, « n'est pas disponible le lundi à 07:30 »"
test "a class larger than a shared room: amber capacity line, count unchanged"
test "the room select moves the lesson to a shared room and back to the home room"
test "a move fix for an unavailable lesson lands on an available time"
test "a crafted set_room with another school's room id changes nothing"
test "the header links to the availability page"
```

- [ ] **Step 2: Run them and check they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/timetable_editor_live_test.exs`
Expected: the new tests FAIL, the old ones PASS.

- [ ] **Step 3: Implement the editor changes**

- [ ] **Step 4: Run the file again**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/timetable_editor_live.ex test/teacher_assistant_web/live/school/timetable_editor_live_test.exs
git commit -m "feat(j3): editor shows room clashes, unavailability and capacity; room select"
```

---

### Task 7: Room on print and « Mon emploi du temps », translations, precommit

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/timetable_print_html/show.html.heex`,
  `lib/teacher_assistant_web/live/school/my_timetable_live.ex`, `priv/gettext/**`
- Test: `test/teacher_assistant_web/live/school/my_timetable_live_test.exs`, the print controller test (find it
  with `grep -rln timetable/print test`)

**Interfaces:**
- Consumes: `room_name` in Task 3's slot views.

- [ ] **Step 1: Write the failing tests**

```elixir
test "« Mon emploi du temps » shows the room under the subject"   # my_timetable_live_test
test "the class print shows the room name"                       # print test
```

- [ ] **Step 2: Run them and check they fail**

- [ ] **Step 3: Render `room_name` (`<span :if={slot.room_name} class="room">`) in both places**

- [ ] **Step 4: Translations**

Run: `mix gettext.extract --merge`. Then give every new or fuzzy entry an English msgstr in `en` (and a French
one in `fr` where the msgid differs) and remove the `fuzzy` flags. Run the gettext guard test (search the tests
for `fuzzy`).
Expected: PASS.

- [ ] **Step 5: Full checks**

Run: `mix compile --warnings-as-errors && mix ash.codegen --check && MIX_TEST_PARTITION=3 mix precommit`
Expected: no warnings, no pending codegen, 0 test failures.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/controllers/timetable_print_html/show.html.heex lib/teacher_assistant_web/live/school/my_timetable_live.ex priv/gettext test/teacher_assistant_web
git commit -m "feat(j3): room on the class print and the teacher's timetable; translations"
```

- [ ] **Step 7: Update the spec's status line** in the roadmap's J3 section to « Status: implemented
  2026-10-19 (branch `j3-rooms-availability`, plan `docs/superpowers/plans/2026-10-19-j3-rooms-availability.md`); no visual
  check done. », then commit that file alone.
