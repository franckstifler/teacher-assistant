# Roll call outside the timetable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher takes the roll call of one of their classes at any period of today (or an earlier day of the week), under their own subject, whatever the timetable says; the hour they vacated reads « non assuré · déplacé à … »; the surveillant's day and the counts show the lesson where it was really held; a teacher with no timetable gets « Faire l'appel » on their classes.

**Architecture:** « Moved » is a property of the roll-call entries: their teaching context differs from the class's slot context at that period (or there is no slot). `SchoolLife` groups the day's entries by context, derives `:done` / `:covered` for slots and appends moved cells; `PaperRollCall.state/5` gains `:covered`. `LessonNotHeld` gains `moved_to_period_id` and a teacher-side `:mark_moved`. `RollCall.open/5` gains `context: :mine` and refuses a key held by another context. `Attendance.record_moved_period/6` writes the entries and the marking in one transaction. Ma journée gets the button, the form, the « À la place de » select and the « Mes classes » list; `/school/day` the moved cells.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView 1.2, Ash 3.37 / AshPostgres (`mix ash.codegen --dev`), Gettext FR source + EN.

**Spec:** `docs/superpowers/specs/2026-11-12-roll-call-outside-timetable-design.md`.

## Global Constraints

- One roll call per class, period and day (`AttendanceEntry :unique_mark`) stays; a key held by another teaching context refuses every open except a conduct manager's, whose save keeps the entries' context.
- State precedence for a slot's cell: own `:done` > `:not_held` > `:covered` > the clock (`:in_progress` / `:missed` / `:upcoming`, then the paper rule).
- Period rule: today → `period.start_time <= now`; an earlier lesson day of the current week → any lesson period; before Monday → refused. « À la place de » offers own lessons of the **same day and same class/course** only.
- A moved lesson never gets « 2e heure » nor a prefill (`adjacent_slots/4` is slot-based; `offer_following?` false, `prefilled_from` nil).
- The colleague's slot is never written from another teacher's phone; `:mark_moved` is refused unless the actor owns the slot's context (or its combined course).
- Every new string through Gettext (FR msgid, EN filled, no fuzzy). All pages stay under the `:appel` module.
- Never write a migration by hand: `mix ash.codegen --dev lesson_moved_to_period`, read it, `mix ash.migrate` on dev.
- Branch `feat/roll-call-moved` in `.claude/worktrees/roll-call-moved`, `MIX_TEST_PARTITION=rcm`; explicit paths in commits; `mix precommit` green before merge. Test clock: Monday 2025-09-15 13:00 WAT (`config/test.exs:23`); default periods in `Reference.default_periods_preset/0` (Cours 1 07:30 … Cours 7 13:30, so « now » is inside Cours 7, position 9).

## Review Focus

1. A conduct manager (surveillant) takes a roll call from `/school/classes/:id/attendance/:period` at a period where a teacher's moved entries exist: not refused, and the entries keep the teacher's context (not nil) — Task 3 tests it.
2. A paper class (`paper_roll_call: true`): a moved lesson taken on the phone shows as done, and the vacated slot marked déplacé never becomes « sur feuille » or overdue for the paper job — Task 2 tests the state table with `paper?: true`.
3. The `?slot=` open of my own slot when **my own** earlier entries exist at that key (I took it, then reopen): still opens (entries' context == mine) — Task 3 tests it.
4. A teacher of a combined course moving it: every member class written under that class's member context, « À la place de » lists the course's lessons, the vacated slots of every member class are marked — Task 3 and Task 4 test a two-class course.
5. Yesterday's roll call entered today (earlier day of the week): accepted at any lesson period, no « À la place de » offered unless that day's own lessons are still open, and `/school/day` for that date shows it — Task 4 tests the date param.

---

### Task 1: `LessonNotHeld.moved_to_period_id` and `:mark_moved`

**Files:**
- Modify: `lib/teacher_assistant/academics/lesson_not_held.ex` (relationship, actions, policies)
- Create: `lib/teacher_assistant/academics/lesson_not_held/owns_slot.ex` (`Ash.Policy.SimpleCheck`, also usable as the validation)
- Modify: `lib/teacher_assistant/attendance.ex` (`mark_moved/5`, `unmark_moved/4`, `list_not_held/4` returning the motive)
- Create (generated): migration + snapshot
- Test: `test/teacher_assistant/academics/lesson_not_held_test.exs` (new)

**Interfaces:**
- `belongs_to :moved_to_period, Period` (`allow_nil? true`, `public? true`; reference `on_delete: :nilify`).
- `create :mark_moved` — `accept [:class_group_id, :period_id, :date, :moved_to_period_id]`, `change set_attribute(:marked_by_user_id, actor(:id))`, `validate attribute_does_not_equal(:moved_to_period_id, nil)`, a validation that `moved_to_period_id != period_id` (message « Le cours ne peut pas être déplacé sur son propre créneau. »), `upsert? true, upsert_identity: :one_per_lesson, upsert_fields: [:moved_to_period_id, :marked_by_user_id]` (re-marking updates the motive).
- `OwnsSlot.match?/3`: true when `TimetableSlot` exists for `class_group_id`, `day_of_week(date)`, `period_id` whose `teaching_context.teacher_user_id == actor.id` **or** whose `teaching_context.combined_course.teacher_user_id == actor.id` (read with `authorize?: false`, tenant from the changeset).
- Policies: `policy action(:mark_moved) do forbid_unless member; authorize_if conduct; authorize_if OwnsSlot end`; `policy action_type(:destroy) do forbid_unless member; authorize_if conduct; authorize_if expr(marked_by_user_id == ^actor(:id) and date == ^Reference.today()) end` (date compared as a pinned value computed in the context function — keep the expr simple: `Attendance.unmark_moved/4` checks `date == today` before calling destroy for a non-conduct actor; builder's call, state it).
- `Attendance.mark_moved(scope, %ClassGroup{}, %Period{} = vacated, %Date{}, %Period{} = held) :: {:ok, LessonNotHeld} | {:error, term}`; `unmark_moved(scope, cg, period, date) :: :ok | {:error, term}`; `SchoolLife.lesson_marks/5` loads `moved_to_period` so `not_held` becomes `%{{cg, period, date} => %{moved_to: %Period{} | nil}}` (today a MapSet).

- [ ] **Step 1: Write the failing tests**

```elixir
# setup: school, year, periods, cg "6e A", teacher T with Maths slot at p1 Monday, teacher U with Anglais slot at p2 Monday, conduct manager S
test "the slot's teacher marks it moved to another period"             # mark_moved(scope_T, cg, p1, monday, p3) → {:ok, %{moved_to_period_id: p3.id}}
test "another teacher is refused; a conduct manager is allowed"          # scope_U on p1 → forbidden; scope_S → ok
test "a slot cannot be moved onto itself"                                # p1 → p1 → {:error, _} with the message
test "re-marking updates the motive"                                     # p1→p3 then p1→p4: one row, moved_to p4
test "the marker un-marks the same day, not the next"                    # unmark_moved today ok; clock +1 day → {:error, _}
test "the teacher of a combined course marks a member class's slot"
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=rcm mix test test/teacher_assistant/academics/lesson_not_held_test.exs` — FAIL (`mark_moved/5` undefined).
- [ ] **Step 3: Implement**; `mix ash.codegen --dev lesson_moved_to_period`; `mix ash.migrate`.
- [ ] **Step 4: Run** the file + `test/teacher_assistant/academics/paper_week_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(attendance): a slot's teacher marks it « déplacé à … »`.

---

### Task 2: Moved and covered lessons in the day computations

**Files:**
- Modify: `lib/teacher_assistant/academics/paper_roll_call.ex:50-56` (`state/5` → `:covered`)
- Modify: `lib/teacher_assistant/academics/school_life.ex` (`done_roll_calls/4` :548, `class_done_roll_calls/4` :537, `cell/4` :228, `teacher_day/4` :146, `school_day/3` :39, `teacher_missed_this_week/4` :157, `roll_call_counts/1` :69, `lesson_marks/5` :511; new `moved_cells/4`)
- Modify: `lib/teacher_assistant/academics/lesson_groups.ex` (`put_status/…` :68, `@status_order` :17 gains `:covered` after `:not_held`; group keeps `moved?`)
- Modify: `lib/teacher_assistant_web/components/lesson_components.ex:84` (`status_tag`: « Déplacé », « Pris par %{name} », « Non assuré · déplacé à %{time} »)
- Test: `test/teacher_assistant/academics/school_life_test.exs`, `test/teacher_assistant/academics/paper_roll_call_test.exs`, `test/teacher_assistant/academics/lesson_groups_test.exs`

**Interfaces:**
- `done_roll_calls/4` returns `%{{cg_id, period_id, date} => %{context_id: id | nil, absent: n, teacher: %User{} | nil, subject: String | nil}}` (one roll per key by the identity; context loaded through `teaching_context: [:teacher, :catalog_subject]`).
- `cell/4`: `done` at the key with `context_id in [nil, slot.teaching_context_id]` → `:done` as today; with another context → status `:covered`, `covered_by: %{teacher, subject}`; `not_held` at the key → `moved_to: %Period{} | nil` on the cell. `PaperRollCall.state(status, paper?, not_held?, date, today)`: `:done` first, then `not_held? → :not_held`, then `:covered → :covered`, then today's rules.
- `moved_cells(scope, date, done, slots_by_key)`: one cell per `done` entry whose `context_id` is not nil and differs from the slot's context at that key (or no slot): `%{slot_id: nil, moved?: true, status: :done, date, period, class_group, teacher, teaching_context_id, combined_course_id, subject, code, absent, covers: %{teacher, subject} | nil}`; `teacher_day/4` keeps those whose `teacher.id == user.id`; `school_day/3` appends all of them (rows gain a class with no slot when needed; `periods` unchanged).
- `roll_call_counts/1`: `done` counts `:done` cells including moved; `:covered` and `:not_held` in none; `missed` unchanged.
- `teacher_missed_this_week/4`: `:covered` is not missed.

- [ ] **Step 1: Write the failing tests**

```elixir
# paper_roll_call_test: state table rows for :covered (own done beats it; not held beats it; paper? makes no difference)
# school_life_test (setup: T Maths p1, U Anglais p2 on cg; conduct manager S)
test "a roll call recorded under another context makes the slot covered and adds a moved cell"
  # record_period(scope_T, cg, p2, tc_T, monday, marks) → school_day cell(cg,p2).status == :covered, covered_by.teacher == T;
  # moved cell present (moved?: true, teacher T, subject Maths); teacher_day(U) cell p2 :covered; teacher_day(T) has the moved cell at p2
test "the swap: both teachers end up done, both vacated slots read déplacé, counts 2/0"
  # T records at p2, marks p1 → p2; U records at p1 (context U), marks p2 → p1; roll_call_counts == %{done: 2, missed: [], ...};
  # teacher_day(T) p1 :not_held moved_to p2; teacher_day(U) p2 :not_held moved_to p1
test "a covered slot is not missed this week and is not in the surveillant's missed list"
test "a teacher with no slot sees only their moved cell"               # new teacher V with assignment, no slot; record at p3 → teacher_day(V) == [moved cell]
test "a conduct manager's roll call (nil context) is the slot's own done"
# lesson_groups_test: a moved cell groups alone with moved?: true; status order places :covered after :not_held
```

- [ ] **Step 2: Run** the three files — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN for the three tags.
- [ ] **Step 4: Run** the three files + `test/teacher_assistant_web/live/school/school_life_live_test.exs` + `test/teacher_assistant/workers/missed_roll_calls_test.exs` — PASS (existing behaviour unchanged).
- [ ] **Step 5: Commit** `feat(attendance): moved and covered lessons in the teacher's and the school's day`.

---

### Task 3: Opening and recording a moved roll call

**Files:**
- Modify: `lib/teacher_assistant/attendance.ex` (`record_moved_period/6`, `held_by_other_context/4`, `record_combined_period/5` :330 member contexts off-slot, `own_lessons_for_moved_from/4`)
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex` (`open/5` :25 opts `context: :mine`, `date` rule, refusal; `resolve_teaching_context/3` :356 → `:mine` path; `record/2` :101 routing; `put_adjacent/2` :201 skipped when `roll.moved?`; `set_moved_from/2`)
- Test: `test/teacher_assistant/academics/attendance_test.exs`, `test/teacher_assistant_web/live/school/attendance_live_test.exs:297-370`

**Interfaces:**
- `Attendance.held_by_other_context(scope, %ClassGroup{}, %Period{}, %Date{}) :: nil | %{teacher: %User{}, subject: String}` — the entries' context at the key when it is neither nil nor one of the actor's own contexts (solo or member of their combined course).
- `Attendance.own_lessons_for_moved_from(scope, unit, %Date{}) :: [%{period: %Period{}, class_group: %ClassGroup{}, label: "14:00 · Mathématiques"}]` — the actor's slots of that weekday for the unit's class(es), minus done (own context) and already not-held ones; `unit` is `%ClassGroup{}` + context or `%CombinedCourse{}`.
- `Attendance.record_moved_period(scope, class_or_course, %Period{} = held, %Date{}, marks, moved_from: %Period{} | nil) :: {:ok, count} | {:error, :held_by_other | :forbidden | :record_failed | term}` — `Repo.transaction`: refuse when `held_by_other_context` (unless `Discipline.can_manage_conduct?`); `record_period(scope, cg, held, my_context, date, marks)` or `record_combined_period/5`; then `mark_moved` for each class of the unit when `moved_from` is given; any error rolls back.
- `record_combined_period/5`: a member class whose slot at the period is missing or belongs to another context uses the course's member context for that class (`owner?` from `course.teacher_user_id == actor.id`).
- `RollCall.open(scope, cg_or_course_param, period_id, date, opts)`: `opts[:context] == :mine` → teaching context = my assignment on the class (`Curriculum.list_assignments_for_user/3`) or my course; `roll.moved? = (slot == nil or slot.teaching_context_id != my context id)`; date rule (Global Constraints) → `{:error, :not_started}` / `{:error, :too_old}`; `held_by_other_context` → `{:error, {:held_by, %{teacher, subject}}}` for every open (slot or mine) unless conduct manager; when `moved?`: `offer_following?: false`, `moved_from_options: own_lessons_for_moved_from/3`, `moved_from: default (first option, else nil)`. `RollCall.set_moved_from(roll, period_id | "")`. `record/2`: `roll.moved?` → `record_moved_period/6`, else today's path. Error texts: « Un appel a déjà été fait pour %{class} à %{time} (%{teacher}, %{subject}). », « Ce créneau n'a pas encore commencé. », « Cette journée n'est plus modifiable depuis le téléphone. ».

- [ ] **Step 1: Write the failing tests**

```elixir
# attendance_test (setup has cg, tc, slot Monday at `period`; add colleague U with slot at other_period)
test "record_moved_period writes under my context at a colleague's period and marks my vacated slot in one transaction"
  # entries.teaching_context_id == tc.id; LessonNotHeld(cg, period, monday).moved_to == other_period
test "a refused marking rolls the entries back"                           # moved_from a period I do not own → {:error, _}, no entries
test "a key held by another context is refused, not for a conduct manager"   # held_by_other_context; conduct scope → {:ok, _} and context kept
test "a combined course is written for every member class off-timetable"
# attendance_live_test (assignment-based describe): the slot owner's ?slot open is refused when a colleague's entries hold the key; my own earlier entries reopen
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** both files + `test/teacher_assistant/academics/attendance_combined_test.exs` + `test/teacher_assistant_web/live/school/attendance_combined_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(roll-call): open and record a lesson held outside its timetable slot`.

---

### Task 4: Ma journée — « Autre cours maintenant », « Mes classes », « À la place de »

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/my_day_live.ex` (header actions, `#other-lesson-form`, `handle_params/3` :74 for `class`/`period`/`date`, events `"other_lesson"`, `"moved_from"`, `"unmark_moved"`, `#my-classes`, the `@lessons != []` branch :158 lifted, timeline tags, « Annuler » on a déplacé row)
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex` (`roll_panel/1` :401 gains the `#moved-from` select when `roll.moved?`)
- Test: `test/teacher_assistant_web/live/school/school_life_live_test.exs`

**Interfaces:**
- Header: `<.link id="other-lesson" patch={~p"/school/today?other=1"}>` « Autre cours maintenant »; with `?other=1` the panel `#other-lesson-form` renders: `<form phx-submit="other_lesson">` with `#other-class` (options from `@courses`: value `cg id` or `course:<id>`, label `course.title`), `#other-period` (today's lesson periods open that weekday; `disabled` when `start_time > now` on today; selected: the one under way, else the last started), `#other-date` (today + earlier lesson days of the week, label « lun. 15 sept. »); submit → `push_patch` to `/school/today?class=…&period=…&date=…`.
- `handle_params` with `class`+`period`: `RollCall.open(scope, class, period, date, context: :mine)`; `{:error, {:held_by, who}}` / `:not_started` / `:too_old` → flash error with the texts of Task 3 and `patch /school/today`.
- Panel: eyebrow « Cours déplacé · %{period} » (« Appel · %{date} » on an earlier day), `#moved-from` `<select phx-change="moved_from">` with « Aucun (cours supplémentaire) » + `roll.moved_from_options`, shown only when `roll.moved?` and options exist; `#record-roll` as today.
- After `"record"` on a moved roll: `load_day/1` (the moved lesson appears at its period with `status_tag` « Déplacé », the vacated one « Non assuré · déplacé à %{time} » with `<button id="unmark-<key>" phx-click="unmark_moved">` « Annuler » when `marked_by == me and date == today`), flash « Appel enregistré ».
- `#my-classes` « Mes classes »: when `@lessons == []` and `@day_off == nil`, one row per `@courses` with `#my-class-call-<id>` « Faire l'appel » → `/school/today?class=…&period=<current or last started>&date=today`; the roll panel, `#todo` and `#missed-this-week` render outside the `@lessons != []` branch.
- Subtitle: moved lessons count in « %{count} cours aujourd'hui ».

- [ ] **Step 1: Write the failing tests**

```elixir
test "« Autre cours maintenant » lists my classes and today's periods, future ones disabled"   # clock 13:00 WAT: Cours 6 (11:55) enabled and preselected (last started), Cours 7 (13:30) disabled
test "a moved roll call is saved with its vacated slot and shows both in the timeline"      # ?class=cg&period=p_free&date=today; #moved-from defaults to my p1 lesson; record → #slot-<cg>-<p_free> "Déplacé", #slot-<cg>-<p1> "déplacé à"
test "« Annuler » removes the déplacé marking the same day"
test "a teacher without timetable sees Mes classes and takes a roll call"                     # new teacher, assignment only; #my-classes; click → panel; record → timeline shows the lesson
test "a key held by a colleague is refused with their name"
test "yesterday's roll call is accepted at any period without a vacated slot offer"          # date=2025-09-12 (Friday) — if the fixture week starts Monday 15, use the week's Monday clock shift: set school_clock_now to Wednesday 17 and date 16
test "a combined course moves as one"                                                        # course: param; both classes written
```

- [ ] **Step 2: Run** `school_life_live_test.exs` — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** the file + `test/teacher_assistant_web/live/dead_render_test.exs` + `test/teacher_assistant_web/spaces_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(my-day): « Autre cours maintenant », « À la place de », « Mes classes »`.

---

### Task 5: The surveillant's day

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/day_live.ex` (`grid_cell/1` :704, `cell_title` :768, `period_rows/2` :620, `"remind"` :59, counts header)
- Test: `test/teacher_assistant_web/live/school/school_life_live_test.exs:315` (Aujourd'hui), `test/teacher_assistant/workers/missed_roll_calls_test.exs`

**Interfaces:**
- A moved cell: « ↷ » before the absent figure, `title` « Cours déplacé · %{subject} · %{teacher} » plus « · à la place de %{subject} · %{teacher} » when `covers`; the link goes to `/school/classes/:cg/attendance/:period?date=` as other cells. A `:covered` cell for a class row: shown as the moved cell (one cell per class × period; the moved cell replaces the covered one in the grid). A `:not_held` cell with `moved_to`: title « Non assuré · déplacé à %{time} ». « Relancer » list excludes moved and covered cells. A class row with no slot that weekday appears when it has a moved cell.
- `MissedRollCalls`: unchanged code; test that a vacated slot marked déplacé is not reminded while an unmarked one still is.

- [ ] **Step 1: Write the failing tests** — Aujourd'hui: the moved cell with « ↷ » and both titles; the vacated slot title; « Relancer » skips them; `missed_roll_calls_test`: the two cases above.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN.
- [ ] **Step 4: Run** both files — PASS.
- [ ] **Step 5: Commit** `feat(day): moved lessons and their motives on the surveillant's day`.

---

### Task 6: Verify and merge

- [ ] Browser check on the demo school (worktree server on 4010, phone width): as prof@demo.test tap « Autre cours maintenant », pick 5e A at the current period, see « À la place de » default, validate, check the timeline (« Déplacé » and « Non assuré · déplacé à »), « Annuler », then as censeur@demo.test (who teaches Maths) try the same key → refusal with the name; as sg@demo.test open `/school/day` and hover the moved cell; screenshots of the panel and the grid. Also a teacher account with an assignment and no slot (create one on the demo seed or clear a teacher's slots in the timetable editor) → « Mes classes ».
- [ ] `MIX_TEST_PARTITION=rcm mix precommit` → exit 0 (refresh Gettext references if the check fails on line numbers); fast-forward merge into main; `mix ash.migrate` on the dev DB from main; update memory `project-roll-call-outside-timetable` (merged commit, rulings, deferred minors).
