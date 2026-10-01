# J4 — Censeur timetable editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One school-wide timetable editor for the Proviseur and Censeur: class tabs, teacher clashes saved and
shown in red, move/swap fix suggestions, hours placed vs planned.

**Architecture:** A pure `Academics.TimetableConflicts` finds clashes and fix suggestions from plain slot maps.
`Timetabling` stops refusing clashes, gains `school_slots/1`, `move_slot/4` and `swap_slots/4` (one transaction
each). A new `TimetableEditorLive` at `/school/timetable` renders it; the old per-class page sends editors there
and stays read-only for form masters.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3 (attribute multitenancy), Gettext (French msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"J4 — Censeur timetable editor (spec)".

## Global Constraints

- No migration is expected (no new data). `mix ash.codegen --check` must stay clean.
- Worktree `.claude/worktrees/j4`, branch `j4-timetable-editor`, `MIX_TEST_PARTITION=2` for `mix test`. Stage
  explicit paths only.
- A clash: same teacher, same day and period, active year, two or more classes — unless every slot of that
  teacher at that time belongs to one combined course. Count = one per (teacher, day, period) clashing group.
- Suggestions only for a clashing cell holding a non-combined lesson: at most 2 moves, then at most 2 swaps,
  in day then period order.
- Still refused when placing: a course not of the class, an unknown period, a closed cell (J1).
- Editor: admin axis (Proviseur, Censeur); others redirected to `/school`.
- Strings through gettext; after `mix gettext.extract --merge`, fix new fuzzy entries (main: en 24, fr 17).
- `mix precommit` before the last commit.

## Review Focus

1. A combined course (MACO + ELEQ, one teacher) placed at a time when that teacher also has a third,
   unrelated class — exactly one clash, flagged on all three cells, counted once (test in Task 1).
2. A swap whose new position puts the other teacher into a clash elsewhere — never suggested (test in Task 1).
3. Applying a suggestion after the grid changed underneath (the target cell got filled) — refused, nothing
   half-written (test in Task 2).
4. A form master opening the class's « Emploi du temps » — still sees the read-only grid, not a redirect to a
   page they cannot open (test in Task 3).
5. A crafted `place`/`fix` event on a closed cell or another school's class — refused, nothing written (test in
   Task 3).

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/j4 -b j4-timetable-editor main
cd .claude/worktrees/j4 && mix deps.get
MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/timetables_slots_test.exs
```

Expected: 0 failures.

---

### Task 1: Clashes and fix suggestions (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/timetable_conflicts.ex`
- Test: `test/teacher_assistant/academics/timetable_conflicts_test.exs`

**Interfaces:**
- Produces (slot = `%{id, class_group_id, day, period_id, teacher_id, combined_course_id, teaching_context_id}`):
  - `TimetableConflicts.clashes([slot]) :: %{{class_group_id, day, period_id} => [other_class_group_id]}`
  - `TimetableConflicts.count([slot]) :: non_neg_integer`
  - `TimetableConflicts.busy?([slot], teacher_id, day, period_id, ignore_ids :: [slot_id]) :: boolean`
  - `TimetableConflicts.suggestions([slot], open_cells :: [{day, period_id}], class_group_id, {day, period_id})
     :: [%{kind: :move, to: {day, period_id}} | %{kind: :swap, to: {day, period_id}, with: slot}]`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.TimetableConflictsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.TimetableConflicts, as: C

  defp s(id, cg, day, p, teacher, combined \\ nil),
    do: %{id: id, class_group_id: cg, day: day, period_id: p, teacher_id: teacher, combined_course_id: combined, teaching_context_id: "tc-#{id}"}

  test "two classes, one teacher, one time: a clash on both cells, counted once" do
    slots = [s(1, "6a", :monday, "p1", "t"), s(2, "6b", :monday, "p1", "t")]
    assert C.clashes(slots) == %{{"6a", :monday, "p1"} => ["6b"], {"6b", :monday, "p1"} => ["6a"]}
    assert C.count(slots) == 1
  end

  test "a combined course is not a clash between its own classes" do
    slots = [s(1, "maco", :monday, "p1", "t", "cc"), s(2, "eleq", :monday, "p1", "t", "cc")]
    assert C.clashes(slots) == %{}
    assert C.count(slots) == 0
  end

  test "a combined course plus an unrelated class: one clash flagged on all three cells" do
    slots = [
      s(1, "maco", :monday, "p1", "t", "cc"),
      s(2, "eleq", :monday, "p1", "t", "cc"),
      s(3, "1c", :monday, "p1", "t")
    ]

    clashes = C.clashes(slots)
    assert clashes[{"1c", :monday, "p1"}] |> Enum.sort() == ["eleq", "maco"]
    assert clashes[{"maco", :monday, "p1"}] == ["1c"]
    assert clashes[{"eleq", :monday, "p1"}] == ["1c"]
    assert C.count(slots) == 1
  end

  test "different teachers at the same time are no clash" do
    assert C.count([s(1, "6a", :monday, "p1", "t"), s(2, "6b", :monday, "p1", "u")]) == 0
  end

  test "moves go to empty open cells where the teacher is free, at most two" do
    slots = [
      s(1, "6a", :monday, "p1", "t"),
      s(2, "6b", :monday, "p1", "t"),
      s(3, "6b", :monday, "p2", "t")
    ]

    open = [{:monday, "p1"}, {:monday, "p2"}, {:monday, "p3"}, {:tuesday, "p1"}, {:tuesday, "p2"}]
    moves = C.suggestions(slots, open, "6a", {:monday, "p1"}) |> Enum.filter(&(&1.kind == :move))
    # p2 is busy for t (6b), so the first two free cells are monday p3 and tuesday p1
    assert Enum.map(moves, & &1.to) == [{:monday, "p3"}, {:tuesday, "p1"}]
  end

  test "a swap is offered only when neither teacher ends up in a clash" do
    slots = [
      s(1, "6a", :monday, "p1", "t"),
      s(2, "6b", :monday, "p1", "t"),
      # 6a's other lesson, teacher u, at tuesday p1: t is free there, u is free at monday p1
      s(3, "6a", :tuesday, "p1", "u"),
      # 6a's lesson with teacher v at tuesday p2: v also teaches 6c at monday p1 → swap would clash v
      s(4, "6a", :tuesday, "p2", "v"),
      s(5, "6c", :monday, "p1", "v")
    ]

    open = [{:monday, "p1"}, {:tuesday, "p1"}, {:tuesday, "p2"}]
    swaps = C.suggestions(slots, open, "6a", {:monday, "p1"}) |> Enum.filter(&(&1.kind == :swap))
    assert Enum.map(swaps, & &1.to) == [{:tuesday, "p1"}]
    assert hd(swaps).with.id == 3
  end

  test "no suggestion for a combined lesson or a cell without a clash" do
    slots = [s(1, "maco", :monday, "p1", "t", "cc"), s(2, "eleq", :monday, "p1", "t", "cc"), s(3, "1c", :monday, "p1", "t")]
    assert C.suggestions(slots, [{:monday, "p2"}], "maco", {:monday, "p1"}) == []
    assert C.suggestions([s(9, "6a", :monday, "p1", "t")], [{:monday, "p2"}], "6a", {:monday, "p1"}) == []
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/timetable_conflicts_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule TeacherAssistant.Academics.TimetableConflicts do
  @moduledoc """
  Teacher clashes in a school timetable (spec J4, T01), pure. A clash is one teacher
  in two or more classes at the same day and period, unless every one of those slots
  belongs to the same combined course (« cours regroupé »). Suggestions fix a clash
  on a non-combined lesson: moves to an empty open cell of the class where the
  teacher is free, then swaps with another lesson of the class that leave neither
  teacher in a clash.
  """

  @max 2

  @doc "Clashing cells => the other classes the teacher has at that time."
  def clashes(slots) do
    slots
    |> clash_groups()
    |> Enum.flat_map(fn group ->
      Enum.map(group, fn slot ->
        others =
          group
          |> Enum.reject(&same_unit?(&1, slot))
          |> Enum.map(& &1.class_group_id)
          |> Enum.uniq()

        {{slot.class_group_id, slot.day, slot.period_id}, others}
      end)
    end)
    |> Map.new()
  end

  @doc "One per (teacher, day, period) that clashes."
  def count(slots), do: slots |> clash_groups() |> length()

  @doc "Whether the teacher has a lesson at that time, ignoring the given slot ids."
  def busy?(slots, teacher_id, day, period_id, ignore_ids \\ []) do
    Enum.any?(slots, fn s ->
      s.teacher_id == teacher_id and s.day == day and s.period_id == period_id and s.id not in ignore_ids
    end)
  end

  @doc "Fixes for the class's lesson at `cell`, when it clashes and is not combined."
  def suggestions(slots, open_cells, class_group_id, {day, period_id} = cell) do
    slot = Enum.find(slots, &(&1.class_group_id == class_group_id and &1.day == day and &1.period_id == period_id))

    cond do
      is_nil(slot) or not is_nil(slot.combined_course_id) -> []
      not Map.has_key?(clashes(slots), {class_group_id, day, period_id}) -> []
      true -> moves(slots, open_cells, slot, cell) ++ swaps(slots, open_cells, slot, cell)
    end
  end

  defp moves(slots, open_cells, slot, cell) do
    class_cells = slots |> Enum.filter(&(&1.class_group_id == slot.class_group_id)) |> MapSet.new(&{&1.day, &1.period_id})

    open_cells
    |> Enum.reject(&(&1 == cell or MapSet.member?(class_cells, &1)))
    |> Enum.reject(fn {d, p} -> busy?(slots, slot.teacher_id, d, p, [slot.id]) end)
    |> Enum.take(@max)
    |> Enum.map(&%{kind: :move, to: &1})
  end

  defp swaps(slots, open_cells, slot, {day, period_id}) do
    open = MapSet.new(open_cells)

    slots
    |> Enum.filter(fn o ->
      o.class_group_id == slot.class_group_id and o.id != slot.id and is_nil(o.combined_course_id) and
        o.teacher_id != slot.teacher_id and MapSet.member?(open, {o.day, o.period_id})
    end)
    |> Enum.sort_by(fn o -> Enum.find_index(open_cells, &(&1 == {o.day, o.period_id})) end)
    |> Enum.filter(fn o ->
      not busy?(slots, slot.teacher_id, o.day, o.period_id, [slot.id, o.id]) and
        not busy?(slots, o.teacher_id, day, period_id, [slot.id, o.id])
    end)
    |> Enum.take(@max)
    |> Enum.map(&%{kind: :swap, to: {&1.day, &1.period_id}, with: &1})
  end

  # Groups of slots (one teacher, one time) holding more than one unit.
  defp clash_groups(slots) do
    slots
    |> Enum.group_by(&{&1.teacher_id, &1.day, &1.period_id})
    |> Map.values()
    |> Enum.filter(fn group -> group |> Enum.map(&unit/1) |> Enum.uniq() |> length() > 1 end)
  end

  defp unit(%{combined_course_id: nil, class_group_id: cg}), do: {:class, cg}
  defp unit(%{combined_course_id: cc}), do: {:combined, cc}

  defp same_unit?(a, b), do: unit(a) == unit(b)
end
```

- [ ] **Step 4: Run it**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/timetable_conflicts_test.exs`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/timetable_conflicts.ex test/teacher_assistant/academics/timetable_conflicts_test.exs
git commit -m "feat: pure timetable clashes and fix suggestions"
```

---

### Task 2: Timetabling — clashes allowed, school slots, move and swap

**Files:**
- Modify: `lib/teacher_assistant/timetabling.ex`
- Modify tests: `test/teacher_assistant/academics/timetables_slots_test.exs`,
  `test/teacher_assistant/academics/timetables_combined_test.exs`
- Test (new): `test/teacher_assistant/academics/timetable_editing_test.exs`

**Interfaces:**
- Consumes: Task 1 slot shape.
- Produces:
  - `place_slot/3`, `place_combined_slot/4`: never `{:error, {:teacher_clash, _}}` any more.
  - `Timetabling.school_slots(scope) :: [slot]` (Task 1 shape) for the active year; `[]` without one.
  - `Timetabling.move_slot(scope, cg, {from_day, from_period_id}, {to_day, to_period_id}) :: :ok | {:error, :invalid | :occupied | :closed_cell | :combined | term}`
  - `Timetabling.swap_slots(scope, cg, cell_a, cell_b) :: :ok | {:error, :invalid | :combined | term}`

- [ ] **Step 1: Turn the clash tests around**

In `timetables_slots_test.exs`, the test asserting `{:error, {:teacher_clash, "6e A"}}` becomes "a teacher clash
is saved (spec J4)": assert `{:ok, %TimetableSlot{}}` for the second placement and that both cells now hold a
slot. In `timetables_combined_test.exs`, the two tests asserting `{:error, {:teacher_clash, …}}` become: the
placement returns `{:ok, _}` and `TimetableConflicts.count(Timetabling.school_slots(scope)) == 1`. Rename them
accordingly. (Keep every other assertion of those files.)

Create `test/teacher_assistant/academics/timetable_editing_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.TimetableEditingTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Timetabling}
  alias TeacherAssistant.Academics.TimetableConflicts
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    :ok = Attendance.build_default_periods(scope)
    [p1, p2, p3 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    other = TeacherFixtures.membership_fixture(scope)
    {:ok, other_user} = Ash.get(TeacherAssistant.Accounts.User, other.user_id, authorize?: false)
    {:ok, ma} = Curriculum.assign_teacher(scope, a, head, %{subject: "Maths"})
    {:ok, mb} = Curriculum.assign_teacher(scope, b, head, %{subject: "Maths"})
    {:ok, sa} = Curriculum.assign_teacher(scope, a, other_user, %{subject: "SVT"})
    %{scope: scope, a: a, b: b, ma: ma, mb: mb, sa: sa, p1: p1, p2: p2, p3: p3}
  end

  defp place(ctx, cg, tc, day, p),
    do: {:ok, _} = Timetabling.place_slot(ctx.scope, cg, %{day: day, period_id: p.id, teaching_context_id: tc.id})

  test "school slots carry teacher and combined course; a clash is counted", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.b, ctx.mb, :monday, ctx.p1)
    slots = Timetabling.school_slots(ctx.scope)
    assert length(slots) == 2
    assert Enum.all?(slots, &(&1.teacher_id && Map.has_key?(&1, :combined_course_id)))
    assert TimetableConflicts.count(slots) == 1
  end

  test "move_slot moves a lesson to an empty open cell and clears the clash", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.b, ctx.mb, :monday, ctx.p1)
    assert :ok = Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})
    assert TimetableConflicts.count(Timetabling.school_slots(ctx.scope)) == 0
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p2.id}]
  end

  test "move_slot refuses an occupied target, and nothing changes", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.a, ctx.sa, :monday, ctx.p2)
    assert {:error, :occupied} = Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})
    slots = Timetabling.class_timetable(ctx.scope, ctx.a).slots
    assert slots[{:monday, ctx.p1.id}].teaching_context_id == ctx.ma.id
    assert slots[{:monday, ctx.p2.id}].teaching_context_id == ctx.sa.id
  end

  test "swap_slots exchanges two lessons of a class", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.a, ctx.sa, :tuesday, ctx.p1)
    assert :ok = Timetabling.swap_slots(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:tuesday, ctx.p1.id})
    slots = Timetabling.class_timetable(ctx.scope, ctx.a).slots
    assert slots[{:monday, ctx.p1.id}].teaching_context_id == ctx.sa.id
    assert slots[{:tuesday, ctx.p1.id}].teaching_context_id == ctx.ma.id
  end

  test "move and swap refuse an empty source and a plain teacher", ctx do
    assert {:error, :invalid} = Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p3.id}, {:monday, ctx.p2.id})
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    teacher = %{TeacherFixtures.member_scope_fixture(ctx.scope) | current_academic_year: ctx.scope.current_academic_year}
    assert {:error, _} = Timetabling.move_slot(teacher, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end
end
```

(If `Ash.get(User, …, authorize?: false)` is not how the codebase loads a user, use the user returned by
`membership_fixture/1`'s `:user` option: `user = TeacherFixtures.user_fixture(); TeacherFixtures.membership_fixture(scope, %{user: user})`.)

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/timetables_slots_test.exs test/teacher_assistant/academics/timetables_combined_test.exs test/teacher_assistant/academics/timetable_editing_test.exs`
Expected: FAIL — clashes still refused; `school_slots/1` undefined.

- [ ] **Step 3: Implement**

In `Timetabling`:
- `place_slot/3`: drop the `teacher_clash` branch — after the `:open` check, call
  `upsert_slot(scope, cg, teaching_context_id, period_id, day)`; ignore any `:exempt_class_group_ids` key. Update
  the `@doc` (no more clash refusal: « a clash is saved and shown by the editor »).
- `place_combined_slot/4`: drop `validate_no_clash/5`; go straight to the `:place_combined` action. Update `@doc`.
- Delete `validate_no_clash/5` and `teacher_clash/6`; drop the `define :list_for_clash_check` code interface only
  if nothing else uses it (`grep -rn list_for_clash_check lib test`), and keep the read action.
- Add:

```elixir
  @doc "The active year's slots as plain maps for `TimetableConflicts` (spec J4)."
  def school_slots(%Scope{current_academic_year: nil}), do: []

  def school_slots(%Scope{current_academic_year: year} = scope) do
    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load(:teaching_context)
    |> Ash.read!(scope: scope)
    |> Enum.map(fn s ->
      %{
        id: s.id,
        class_group_id: s.class_group_id,
        day: s.day,
        period_id: s.period_id,
        teaching_context_id: s.teaching_context_id,
        teacher_id: s.teaching_context.teacher_user_id,
        combined_course_id: s.teaching_context.combined_course_id
      }
    end)
  end

  @doc """
  Moves the class's lesson at `from` to the empty, open cell `to` (spec J4). Refused
  for a combined lesson (changed on all its classes from the editor's chips).
  """
  def move_slot(%Scope{} = scope, %ClassGroup{} = cg, {fd, fp} = _from, {td, tp} = _to) do
    with {:ok, slot} <- single_slot(scope, cg, fd, fp),
         [] <- list_for_cell!(cg.id, td, tp, scope: scope),
         {:ok, %Period{} = period} <- Ash.get(Period, tp, scope: scope),
         :open <- open_or_closed(scope, td, period) do
      slot
      |> Ash.Changeset.for_update(:update, %{day: td, period_id: tp}, scope: scope)
      |> Ash.update()
      |> ok()
    else
      [_ | _] -> {:error, :occupied}
      :closed -> {:error, :closed_cell}
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  @doc "Exchanges the class's lessons at two cells, in one transaction (spec J4)."
  def swap_slots(%Scope{} = scope, %ClassGroup{} = cg, {ad, ap}, {bd, bp}) do
    with {:ok, a} <- single_slot(scope, cg, ad, ap),
         {:ok, b} <- single_slot(scope, cg, bd, bp) do
      Ash.transact([TimetableSlot], fn ->
        with {:ok, _} <- set_context(scope, a, b.teaching_context_id),
             {:ok, _} <- set_context(scope, b, a.teaching_context_id) do
          :ok
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:ok, {:error, _} = error} -> error
        {:error, _} = error -> error
      end
    end
  end

  defp set_context(scope, slot, tc_id),
    do: slot |> Ash.Changeset.for_update(:update, %{teaching_context_id: tc_id}, scope: scope) |> Ash.update()

  # The class's non-combined lesson at a cell.
  defp single_slot(scope, cg, day, period_id) do
    case list_for_cell!(cg.id, day, period_id, scope: scope) do
      [slot] ->
        slot = Ash.load!(slot, :teaching_context, scope: scope)
        if slot.teaching_context.combined_course_id, do: {:error, :combined}, else: {:ok, slot}

      _ ->
        {:error, :invalid}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error
```

Notes:
- `list_for_cell!` raises for a period id of another school? It filters inside the tenant, so it returns `[]` →
  `:invalid`. A malformed uuid raises `Ash.Error.Invalid` — wrap the callers' ids in the LiveView (Task 3).
- `Ash.transact/2` returns `{:ok, value}` or `{:error, error}` as in `Organization.update_calendar/3`; if the
  inner `{:error, _}` does not roll back, make the inner `with` raise via `Ash.update!` and return
  `{:error, error}` from a `rescue` — ledger the choice.
- `TimetableSlot`'s update policy is admin-axis, so a plain teacher gets `{:error, %Ash.Error.Forbidden{}}`.

- [ ] **Step 4: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics`
Expected: 0 failures. Then `grep -rn "teacher_clash" lib test` lists only `timetable_live.ex` (Task 3 removes it).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/timetabling.ex test/teacher_assistant/academics/timetables_slots_test.exs \
  test/teacher_assistant/academics/timetables_combined_test.exs test/teacher_assistant/academics/timetable_editing_test.exs
git commit -m "feat: timetable clashes are saved; school slots, move and swap"
```

---

### Task 3: The editor page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/timetable_editor_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/timetable_live.ex` (editors redirected; clash flash removed),
  `router.ex` (`live "/school/timetable", School.TimetableEditorLive, :index` — before
  `live "/school/timetable/me", …`), `spaces.ex` (item in the Proviseur « Pilotage » and Censeur « Suivi
  pédagogique » sections, after `classes()`)
- Test: `test/teacher_assistant_web/live/school/timetable_editor_live_test.exs`; update
  `test/teacher_assistant_web/live/school/timetable_live_test.exs`

**Interfaces:**
- Consumes: Task 1 `TimetableConflicts.clashes/1`, `count/1`, `busy?/5`, `suggestions/4`; Task 2
  `Timetabling.school_slots/1`, `move_slot/4`, `swap_slots/4`, `place_slot/3`, `place_combined_slot/4`,
  `clear_slot/4`, `clear_combined_slot/4`, `class_timetable/2`, `can_edit_timetable?/1`; J1
  `Attendance.school_calendar/1`, `SchoolCalendar.open_cell?/3`.
- Produces: route `/school/timetable?class=<id>`; DOM ids `#class-tab-<id>`, `#conflict-count`,
  `#editor-grid`, `#cell-<day>-<period_id>` (class `clash-cell` on a clash, `closed-cell` when closed),
  `#cell-panel`, `#conflict-text`, `#fix-<n>`, `#chip-<tc_id>`, `#clear-cell`, `#hours`, `#hours-<tc_id>`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/timetable_editor_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.TimetableEditorLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, actor: head} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    {:ok, ma} = Curriculum.assign_teacher(scope, a, head, %{subject: "Maths"})
    {:ok, mb} = Curriculum.assign_teacher(scope, b, head, %{subject: "Maths"})
    %{scope: scope, a: a, b: b, ma: ma, mb: mb, p1: p1, p2: p2}
  end

  test "tabs, a chip places a lesson, the hours update", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    assert has_element?(view, "#class-tab-#{ctx.b.id}")
    assert has_element?(view, "#conflict-count", "Aucun conflit")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
    assert has_element?(view, "#hours-#{ctx.ma.id}", "1/")
  end

  test "a clash is saved, shown in red, counted, and fixed by a move", %{conn: conn} = ctx do
    {:ok, _} = Timetabling.place_slot(ctx.scope, ctx.b, %{day: :monday, period_id: ctx.p1.id, teaching_context_id: ctx.mb.id})
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")

    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#chip-#{ctx.ma.id}") |> render_click()

    assert has_element?(view, "#cell-monday-#{ctx.p1.id}.clash-cell")
    assert has_element?(view, "#conflict-count", "1 conflit")
    assert has_element?(view, "#conflict-text", "6e R")

    view |> element("#fix-0") |> render_click()
    assert has_element?(view, "#conflict-count", "Aucun conflit")
  end

  test "clearing a cell", %{conn: conn} = ctx do
    {:ok, _} = Timetabling.place_slot(ctx.scope, ctx.a, %{day: :monday, period_id: ctx.p1.id, teaching_context_id: ctx.ma.id})
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    view |> element("#cell-monday-#{ctx.p1.id}") |> render_click()
    view |> element("#clear-cell") |> render_click()
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end

  test "crafted events on a closed cell or another school's class write nothing", %{conn: conn} = ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{ctx.a.id}")
    render_hook(view, "select", %{"day" => "saturday", "period" => ctx.p1.id})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    refute Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:saturday, ctx.p1.id}]

    render_hook(view, "select", %{"day" => "monday", "period" => "not-a-uuid"})
    render_hook(view, "place", %{"tc" => ctx.ma.id})
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots == %{}

    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, foreign} = Enrollment.create_class_group(other, Organization.current_academic_year(other), %{label: "X", level: "6ème"})
    {:ok, view, _} = live(conn, ~p"/school/timetable?class=#{foreign.id}")
    refute has_element?(view, "#class-tab-#{foreign.id}")
  end

  test "a plain teacher is redirected", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/timetable")
  end

  test "the old class page sends an editor to the editor", %{conn: conn} = ctx do
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/school/classes/#{ctx.a.id}/timetable")
    assert to == "/school/timetable?class=#{ctx.a.id}"
  end
end
```

In `timetable_live_test.exs`: the tests that edit as an admin (« admin selecting an assignment… », « admin
clearing a cell… », « placing a combined assignment… », « placing a clashing teacher flashes… », « the grid shows
lesson days only and greys Wednesday afternoon (spec J1) ») and « admin loads the grid… » now get a
`live_redirect` to the editor: delete them from this file (the editor tests and Task 2 cover the behaviour) and
move the J1 grey-cell test to the editor test file, adapted to `#cell-wednesday-<id>.closed-cell` on
`/school/timetable?class=…`. Keep « a form master sees the grid read-only… », « a non-member is redirected… »,
« cross-school class id… » unchanged. Ledger the deletions.

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/timetable_editor_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: The LiveView**

`lib/teacher_assistant_web/live/school/timetable_editor_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.TimetableEditorLive do
  @moduledoc """
  Censorat → Emploi du temps (spec J4, T01): the whole school's timetable, one tab per
  class. A teacher clash is saved and shown in red with fix suggestions (move to a free
  cell, swap with another lesson of the class); hours placed against hours planned per
  subject. Combined courses (« regroupé ») are placed and cleared on all their classes.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.{CombinedCourse, DayOfWeek, SchoolCalendar, SchoolTemplates, TimetableConflicts}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         true <- Timetabling.can_edit_timetable?(scope),
         %{} = year <- Organization.current_academic_year(scope) do
      classes = scope |> Enrollment.list_class_groups(year) |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)
      calendar = Attendance.school_calendar(scope)

      {:ok,
       assign(socket,
         year: year,
         classes: classes,
         calendar: calendar,
         periods: Attendance.list_periods(scope),
         cg: nil,
         selected: nil
       )}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    cg = Enum.find(socket.assigns.classes, &(&1.id == params["class"])) || List.first(socket.assigns.classes)
    {:noreply, socket |> assign(cg: cg, selected: nil) |> load()}
  end

  defp load(%{assigns: %{cg: nil}} = socket),
    do: assign(socket, slots: [], clashes: %{}, count: 0, grid: %{}, tally: [], assignments: [])

  defp load(socket) do
    %{current_scope: scope, cg: cg} = socket.assigns
    slots = Timetabling.school_slots(scope)
    timetable = Timetabling.class_timetable(scope, cg)

    assign(socket,
      slots: slots,
      clashes: TimetableConflicts.clashes(slots),
      count: TimetableConflicts.count(slots),
      grid: timetable.slots,
      tally: timetable.tally,
      assignments: Curriculum.list_assignments_for_class(scope, cg)
    )
  end

  # --- events -------------------------------------------------------------------------

  def handle_event("tab", %{"class" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/timetable?class=#{id}")}

  def handle_event("select", %{"day" => day, "period" => period_id}, socket) do
    with d when not is_nil(d) <- day_atom(day, socket),
         %{} = period <- Enum.find(socket.assigns.periods, &(&1.id == period_id and &1.kind == :lesson)),
         true <- SchoolCalendar.open_cell?(socket.assigns.calendar, d, period) do
      {:noreply, assign(socket, selected: {d, period.id})}
    else
      _ -> {:noreply, assign(socket, selected: nil)}
    end
  end

  def handle_event("place", %{"tc" => tc_id}, socket) do
    with {day, period_id} <- socket.assigns.selected,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == tc_id)) do
      scope = socket.assigns.current_scope

      result =
        case tc.combined_course do
          %CombinedCourse{} = course -> Timetabling.place_combined_slot(scope, course, day, period_id)
          _ -> Timetabling.place_slot(scope, socket.assigns.cg, %{day: day, period_id: period_id, teaching_context_id: tc.id})
        end

      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear", _params, socket) do
    with {day, period_id} <- socket.assigns.selected,
         %{teaching_context_id: tc_id} <- socket.assigns.grid[{day, period_id}] do
      scope = socket.assigns.current_scope

      result =
        case Enum.find(socket.assigns.assignments, &(&1.id == tc_id)) do
          %{combined_course: %CombinedCourse{} = course} -> Timetabling.clear_combined_slot(scope, course, day, period_id)
          _ -> Timetabling.clear_slot(scope, socket.assigns.cg, day, period_id)
        end

      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("fix", %{"n" => n}, socket) do
    with {day, period_id} = cell <- socket.assigns.selected,
         {i, ""} <- Integer.parse(n),
         %{} = fix <- Enum.at(suggestions(socket.assigns, cell), i) do
      scope = socket.assigns.current_scope

      result =
        case fix do
          %{kind: :move, to: to} -> Timetabling.move_slot(scope, socket.assigns.cg, {day, period_id}, to)
          %{kind: :swap, to: to} -> Timetabling.swap_slots(scope, socket.assigns.cg, {day, period_id}, to)
        end

      socket = if result == :ok, do: assign(socket, selected: fix.to), else: socket
      after_write(result, socket)
    else
      _ -> {:noreply, socket}
    end
  end

  defp after_write(result, socket) when result == :ok or elem(result, 0) == :ok,
    do: {:noreply, load(socket)}

  defp after_write({:error, %Ash.Error.Forbidden{}}, socket), do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, reason}, socket),
    do: {:noreply, socket |> put_flash(:error, error_text(reason)) |> load()}

  defp error_text(:closed_cell), do: gettext("Ce créneau est fermé (jour sans cours ou mercredi après-midi).")
  defp error_text(:occupied), do: gettext("Le créneau visé n'est plus libre.")
  defp error_text(_), do: gettext("Modification non enregistrée.")

  # --- helpers ----------------------------------------------------------------------------

  # A lesson day of the calendar named by the event, or nil (never String.to_atom).
  defp day_atom(day, socket),
    do: Enum.find(socket.assigns.calendar.lesson_days, &(Atom.to_string(&1) == day))

  defp lesson_periods(periods), do: Enum.filter(periods, &(&1.kind == :lesson))

  defp open_cells(%{calendar: cal, periods: periods}) do
    for day <- cal.lesson_days, p <- lesson_periods(periods), SchoolCalendar.open_cell?(cal, day, p), do: {day, p.id}
  end

  defp suggestions(assigns, cell),
    do: TimetableConflicts.suggestions(assigns.slots, open_cells(assigns), assigns.cg.id, cell)

  defp clash?(clashes, cg, day, period_id), do: Map.has_key?(clashes, {cg.id, day, period_id})

  defp class_has_clash?(clashes, cg), do: Enum.any?(clashes, fn {{id, _, _}, _} -> id == cg.id end)

  defp label_of(classes, id), do: Enum.find_value(classes, "?", &(&1.id == id && &1.label))

  defp period_of(periods, id), do: Enum.find(periods, &(&1.id == id))

  defp hm(t), do: Calendar.strftime(t, "%H:%M")

  defp fix_label(%{kind: :move, to: {d, p}}, periods),
    do: gettext("Déplacer au %{day} %{period} (créneau libre)", day: String.downcase(DayOfWeek.label(d)), period: period_of(periods, p).label)

  defp fix_label(%{kind: :swap, to: {d, p}, with: o}, periods, assignments) do
    subject = Enum.find_value(assignments, "?", &(&1.id == o.teaching_context_id && &1.subject))
    gettext("Échanger avec %{subject} du %{day} %{period}", subject: subject, day: String.downcase(DayOfWeek.label(d)), period: period_of(periods, p).label)
  end

  # Teacher of `tc` already teaching elsewhere at the selected cell (another class, not its own combined course).
  defp busy_elsewhere(assigns, tc) do
    with {day, period_id} <- assigns.selected do
      Enum.find_value(assigns.slots, fn s ->
        s.teacher_id == tc.teacher_user_id and s.day == day and s.period_id == period_id and
          s.class_group_id != assigns.cg.id and
          (is_nil(tc.combined_course_id) or s.combined_course_id != tc.combined_course_id) &&
          label_of(assigns.classes, s.class_group_id)
      end)
    end
  end

  defp placed(tally, tc_id), do: Enum.find(tally, &(&1.teaching_context_id == tc_id))

  defp tally_class(:under), do: "text-warning"
  defp tally_class(:exact), do: "text-success"
  defp tally_class(:over), do: "text-error"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="timetable-editor" class="space-y-5">
        <.page_header
          eyebrow={gettext("Censorat · semaine type")}
          title={if @cg, do: gettext("Emploi du temps · %{class}", class: @cg.label), else: gettext("Emploi du temps")}
        >
          <:actions>
            <span id="conflict-count" class={["text-sm font-semibold", if(@count > 0, do: "text-error", else: "text-success")]}>
              {if @count > 0,
                do: ngettext("%{count} conflit à résoudre", "%{count} conflits à résoudre", @count),
                else: gettext("Aucun conflit")}
            </span>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap gap-1.5">
          <button :for={c <- @classes} id={"class-tab-#{c.id}"} type="button" phx-click="tab" phx-value-class={c.id}
            class={["btn btn-xs", if(@cg && c.id == @cg.id, do: "btn-primary", else: "btn-ghost")]}>
            {c.label}
            <span :if={class_has_clash?(@clashes, c)} class="size-1.5 rounded-full bg-error"></span>
          </button>
        </div>

        <div :if={@cg} class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_320px]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="editor-grid" class="table table-sm">
              <thead>
                <tr>
                  <th></th>
                  <th :for={d <- @calendar.lesson_days}>{DayOfWeek.label(d)}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={p <- @periods}>
                  <%= if p.kind == :break do %>
                    <td colspan={length(@calendar.lesson_days) + 1} class="py-0.5 text-center text-xs italic text-base-content/50">{p.label}</td>
                  <% else %>
                    <td class="whitespace-nowrap text-xs">
                      <span class="font-semibold">{p.label}</span>
                      <span class="block text-base-content/60">{hm(p.start_time)}</span>
                    </td>
                    <td :for={d <- @calendar.lesson_days} class="p-1">
                      <% slot = @grid[{d, p.id}] %>
                      <%= cond do %>
                        <% not SchoolCalendar.open_cell?(@calendar, d, p) -> %>
                          <div id={"cell-#{d}-#{p.id}"} class="closed-cell h-11 rounded bg-base-200/60"></div>
                        <% true -> %>
                          <button id={"cell-#{d}-#{p.id}"} type="button" phx-click="select" phx-value-day={d} phx-value-period={p.id}
                            class={[
                              "h-11 w-full rounded px-1.5 text-left text-xs",
                              clash?(@clashes, @cg, d, p.id) && "clash-cell border border-error bg-error/30",
                              !clash?(@clashes, @cg, d, p.id) && slot && "bg-primary/15",
                              !slot && "border border-dashed border-base-300 text-base-content/50",
                              @selected == {d, p.id} && "ring-2 ring-base-content"
                            ]}>
                            <%= if slot do %>
                              <span class="block truncate font-semibold">{slot.subject}</span>
                              <span class="block truncate text-base-content/70">{slot.teacher_email}</span>
                            <% else %>
                              {gettext("Libre")}
                            <% end %>
                          </button>
                      <% end %>
                    </td>
                  <% end %>
                </tr>
              </tbody>
            </table>
          </div>

          <aside class="space-y-4">
            <div :if={@selected} id="cell-panel" class="ta-panel space-y-3 p-4">
              <% {d, pid} = @selected %>
              <% p = period_of(@periods, pid) %>
              <% slot = @grid[@selected] %>
              <h2 class="font-semibold">
                {DayOfWeek.label(d)} · {p.label} {hm(p.start_time)}–{hm(p.end_time)} · {@cg.label}
              </h2>
              <p class="text-sm">
                {if slot, do: "#{slot.subject} — #{slot.teacher_email}", else: gettext("Créneau libre")}
              </p>

              <%= if slot && clash?(@clashes, @cg, d, pid) do %>
                <p id="conflict-text" class="text-sm text-error">
                  {gettext("Conflit : %{teacher} a aussi cours en %{classes} à ce créneau.",
                    teacher: slot.teacher_email,
                    classes: @clashes[{@cg.id, d, pid}] |> Enum.map(&label_of(@classes, &1)) |> Enum.join(", "))}
                </p>
                <% fixes = suggestions(assigns, @selected) %>
                <p :if={fixes == []} class="text-sm text-base-content/70">{gettext("Aucune solution automatique")}</p>
                <button :for={{fix, i} <- Enum.with_index(fixes)} id={"fix-#{i}"} type="button" phx-click="fix" phx-value-n={i}
                  class="btn btn-outline btn-sm w-full justify-start">
                  {if fix.kind == :move, do: fix_label(fix, @periods), else: fix_label(fix, @periods, @assignments)}
                </button>
              <% end %>

              <div class="flex flex-wrap gap-1.5">
                <% busy_for = fn tc -> busy_elsewhere(assigns, tc) end %>
                <button :for={tc <- @assignments} id={"chip-#{tc.id}"} type="button" phx-click="place" phx-value-tc={tc.id}
                  title={(c = busy_for.(tc)) && gettext("%{teacher} a déjà cours en %{class}", teacher: tc.teacher.email, class: c)}
                  class={["badge badge-outline cursor-pointer py-3", busy_for.(tc) && "badge-error", slot && slot.teaching_context_id == tc.id && "badge-primary"]}>
                  {tc.subject} · {(t = placed(@tally, tc.id)) && t.placed}/{tc.weekly_hours} h
                  <span :if={tc.combined_course_id} class="text-[0.6rem]">{gettext("regroupé")}</span>
                </button>
              </div>
              <button :if={slot} id="clear-cell" type="button" phx-click="clear" class="btn btn-ghost btn-sm text-error">
                {gettext("Vider le créneau")}
              </button>
            </div>

            <div id="hours" class="ta-panel space-y-1 p-4">
              <h2 class="ta-eyebrow">{gettext("Heures par matière")}</h2>
              <div :for={t <- @tally} id={"hours-#{t.teaching_context_id}"} class="flex justify-between text-sm">
                <span>{t.subject}</span>
                <span class={["ta-num", tally_class(t.status)]}>{t.placed}/{t.required} h</span>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

Notes for the implementer (fix these while making the tests pass; ledger what you change):
- `period_id` compared with `&1.id == period_id` never raises on a malformed id (string compare), so
  `"not-a-uuid"` simply selects nothing.
- `Curriculum.list_assignments_for_class/2` must return assignments with `:teacher` and `:combined_course`
  loaded (`TimetableLive` relies on both today); check the read action's `prepare` and load them if missing.
- `page_header` must accept an `:actions` slot; if it does not, put the count in a separate `<div>` under the
  header.
- Function components in `<% %>` blocks (`busy_for`, `fixes`) are fine but may trigger change-tracking
  warnings; move them into helpers if `mix compile --warnings-as-errors` complains.

- [ ] **Step 4: Old page, route, menus**

`TimetableLive.mount/3`: right after `true <- Enrollment.class_manager?(scope, cg)`, if
`Timetabling.can_edit_timetable?(scope)` return `{:ok, push_navigate(socket, to: ~p"/school/timetable?class=#{cg.id}")}`;
otherwise keep the read-only page. Remove the two `{:error, {:teacher_clash, …}}` clauses and `flash_clash/2`
(place_slot no longer returns them; non-editors cannot reach the editing events anyway).

Router: add `live "/school/timetable", School.TimetableEditorLive, :index` in the same live_session as
`/school/timetable/me`, **before** it.

`spaces.ex`:

```elixir
  defp timetable_editor,
    do: item("timetable-editor", gettext("Emploi du temps"), "hero-table-cells", ~p"/school/timetable")
```

added after `classes()` in the Proviseur « Pilotage » and Censeur « Suivi pédagogique » sections.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/timetable_editor_live_test.exs test/teacher_assistant_web/live/school/timetable_live_test.exs test/teacher_assistant_web/live/school/my_timetable_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: 0 failures (update any `spaces_test` menu list; ledger it).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/timetable_editor_live.ex lib/teacher_assistant_web/live/school/timetable_live.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex \
  test/teacher_assistant_web/live/school/timetable_editor_live_test.exs test/teacher_assistant_web/live/school/timetable_live_test.exs
git commit -m "feat: school timetable editor with clashes, fixes and hours"
```

---

### Task 4: Translations, status, full checks

- [ ] **Step 1:** `mix gettext.extract --merge`; translate every new msgid in `en` (« Emploi du temps · %{class} » →
  "Timetable · %{class}", « Censorat · semaine type » → "Vice-principal · typical week", « Aucun conflit » → "No
  clash", plural « %{count} conflit à résoudre » → "%{count} clash to resolve" / "%{count} clashes to resolve",
  « Conflit : %{teacher} a aussi cours en %{classes} à ce créneau. » → "Clash: %{teacher} also teaches %{classes}
  at this time.", « Déplacer au %{day} %{period} (créneau libre) » → "Move to %{day} %{period} (free slot)",
  « Échanger avec %{subject} du %{day} %{period} » → "Swap with %{subject} on %{day} %{period}", « Aucune solution
  automatique » → "No automatic fix", « Créneau libre » → "Free slot", « Vider le créneau » → "Clear the slot",
  « Heures par matière » → "Hours per subject", « Le créneau visé n'est plus libre. » → "The target slot is no
  longer free.", « %{teacher} a déjà cours en %{class} » → "%{teacher} already teaches %{class}" …); clear new
  fuzzy flags; counts not above main's (en 24, fr 17).
- [ ] **Step 2:** In the spec's J4 section add before "Mockup:":
  `Status: implemented 2026-10-01 (branch \`j4-timetable-editor\`, plan \`docs/superpowers/plans/2026-10-01-j4-timetable-editor.md\`); no visual check done.`
- [ ] **Step 3:** `MIX_TEST_PARTITION=2 mix precommit`, `mix ash.codegen --check`, `mix compile --warnings-as-errors --force`.
- [ ] **Step 4: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git status --short   # stage formatter-rewritten branch files explicitly
git commit -m "chore: J4 translations and status"
```
