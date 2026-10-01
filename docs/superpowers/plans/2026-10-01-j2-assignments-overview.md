# J2 — Assignments overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school-wide, editable « Affectations » grid (classes × subjects) with each teacher's weekly load
against their statutory service, and each class's form master.

**Architecture:** A pure `Academics.AssignmentGrid` builds the grid, the loads and the "after the change" loads
from plain data. `Curriculum.assignment_overview/1` feeds it with a fixed number of queries;
`Curriculum.place_assignment/5` assigns or reassigns through the existing rules. The statutory service is a
`SchoolProfile` field with a per-membership override. A new `AssignmentsLive` renders the grid and side panels.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3 (attribute multitenancy), AshPostgres, Gettext (French msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"J2 — Assignments overview (spec)".

## Global Constraints

- Never write migrations by hand: `mix ash.codegen --dev`, then `mix ash.codegen j2_assignments_overview`;
  `mix ash.codegen --check` clean at the end. Do not migrate the shared dev DB from the worktree; migrate the
  test DB with `MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.migrate` (drop/create/migrate it if the squash leaves
  a stale version).
- Worktree `.claude/worktrees/j2`, branch `j2-assignments-overview`, `MIX_TEST_PARTITION=2` for `mix test`.
  Stage explicit paths only.
- `statutory_hours` 1..40 on both resources; school default 18; membership nil = the school's value.
- Load = sum of `weekly_hours` (nil counts 0) of the teacher's active-year assignments, a combined course
  counted once. Over = load > service.
- Cell kinds: `:assigned`, `:to_assign` (no assignment, `CoefficientRules.resolve/2` finds a cell),
  `:not_taught`. Columns: subjects with ≥ 1 assigned or to-assign cell, catalog order.
- Admin axis (Proviseur, Censeur) for the page and every write; others redirected to `/school/settings`.
- Strings through gettext; after `mix gettext.extract --merge`, fix new fuzzy entries (main: en 24, fr 17).
- `mix precommit` before the last commit.

## Review Focus

1. A teacher in a combined course across three classes — their load counts its hours once, not three times
   (test in Task 2).
2. Reassigning a cell to the teacher who already holds it, or assigning to someone already at their service —
   the "after" figure is right (no double count for the current holder) and the save still works (test in
   Task 2 / Task 4).
3. Removing an assignment that has marks — refused with the message, the cell unchanged (test in Task 4).
4. A class whose level is not on the coefficient grid (a free-typed level) — no « À affecter » noise; only its
   assigned cells show (test in Task 2).
5. A crafted `assign` event naming a teacher who is not an active member, or a class of another school —
   refused, nothing written (test in Task 3).

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/j2 -b j2-assignments-overview main
cd .claude/worktrees/j2 && mix deps.get
MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.migrate
MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/coefficient_grid_test.exs
```

Expected: 0 failures.

---

### Task 1: Statutory service (school default, per-teacher override)

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_profile.ex`, `lib/teacher_assistant/accounts/school_membership.ex`,
  `lib/teacher_assistant/accounts.ex`
- Test: `test/teacher_assistant/accounts/statutory_hours_test.exs`

**Interfaces:**
- Produces: `SchoolProfile.statutory_hours` (integer, default 18); `SchoolMembership.statutory_hours`
  (integer | nil); `SchoolMembership` update action `:set_statutory_hours` (admin axis);
  `Accounts.update_school_service(scope, string) :: {:ok, profile} | {:error, :invalid_hours | term}`;
  `Accounts.set_member_service(scope, membership, string | "") :: {:ok, m} | {:error, :invalid_hours | term}`;
  `Accounts.can_set_member_service?(scope) :: boolean`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.StatutoryHoursTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    m = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, m: m}
  end

  test "the school service defaults to 18 and accepts 1..40", %{scope: scope} do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.statutory_hours == 18
    assert {:ok, %{statutory_hours: 21}} = Accounts.update_school_service(scope, "21")
    assert {:error, :invalid_hours} = Accounts.update_school_service(scope, "0")
    assert {:error, :invalid_hours} = Accounts.update_school_service(scope, "x")
  end

  test "a member's own service overrides, empty clears", %{scope: scope, m: m} do
    assert m.statutory_hours == nil
    assert {:ok, %{statutory_hours: 12}} = Accounts.set_member_service(scope, m, "12")
    {:ok, m} = Accounts.set_member_service(scope, m, "12")
    assert {:ok, %{statutory_hours: nil}} = Accounts.set_member_service(scope, m, "")
    assert {:error, :invalid_hours} = Accounts.set_member_service(scope, m, "41")
  end

  test "a Censeur may set a member's service; a plain teacher may not", %{scope: scope, m: m} do
    censeur = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal]})
    assert Accounts.can_set_member_service?(censeur)
    assert {:ok, _} = Accounts.set_member_service(censeur, m, "15")

    teacher = TeacherFixtures.member_scope_fixture(scope)
    refute Accounts.can_set_member_service?(teacher)
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.set_member_service(teacher, m, "15")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/accounts/statutory_hours_test.exs`
Expected: FAIL — `update_school_service/2` undefined.

- [ ] **Step 3: Implement**

`SchoolProfile` attributes (after `default_lesson_minutes`):

```elixir
    # Spec J2: the teaching load a full-time teacher owes per week.
    attribute :statutory_hours, :integer,
      allow_nil?: false,
      default: 18,
      public?: true,
      constraints: [min: 1, max: 40]
```

and `:statutory_hours` at the end of the `update :update` accept list.

`SchoolMembership`: attribute

```elixir
    # Spec J2: this teacher's weekly service; nil = the school's.
    attribute :statutory_hours, :integer, public?: true, constraints: [min: 1, max: 40]
```

action (inside `actions do`):

```elixir
    update :set_statutory_hours do
      accept [:statutory_hours]
    end
```

policies: change `policy action_type([:create, :update, :destroy])` to
`policy action([:create, :update, :destroy, :deactivate])` (same body), and add

```elixir
    policy action(:set_statutory_hours) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
```

(check the resource's action names first: every create/update/destroy action other than
`:set_statutory_hours` must be listed in the head-only policy; ledger the list.)

`Accounts`:

```elixir
  # --- Statutory service (spec J2) ------------------------------------------------

  def update_school_service(%Scope{} = scope, value) do
    with {:ok, hours} <- parse_hours(value),
         {:ok, profile} <- fetch_school_profile(scope) do
      update_school_profile(profile, %{statutory_hours: hours}, scope: scope)
    end
  end

  def set_member_service(%Scope{} = scope, %SchoolMembership{} = m, value) do
    with {:ok, hours} <- parse_optional_hours(value) do
      m
      |> Ash.Changeset.for_update(:set_statutory_hours, %{statutory_hours: hours}, scope: scope)
      |> Ash.update()
    end
  end

  def can_set_member_service?(scope), do: Ash.can?({SchoolMembership, :set_statutory_hours}, scope)

  defp parse_optional_hours(value) when value in [nil, ""], do: {:ok, nil}
  defp parse_optional_hours(value), do: parse_hours(value)

  defp parse_hours(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n in 1..40 -> {:ok, n}
      _ -> {:error, :invalid_hours}
    end
  end

  defp parse_hours(_), do: {:error, :invalid_hours}
```

(If `Ash.can?` on an update action needs a record, use `Ash.can?({%SchoolMembership{}, :set_statutory_hours}, scope)`
— ledger it.)

- [ ] **Step 4: Migration and run**

Run: `mix ash.codegen --dev`, check the migration adds `school_profiles.statutory_hours` (not null, default 18)
and `school_memberships.statutory_hours`; `mix ash.codegen j2_assignments_overview`; migrate the test DB;
`MIX_TEST_PARTITION=2 mix test test/teacher_assistant/accounts/statutory_hours_test.exs` → 3 tests, 0 failures;
then `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/members_live_test.exs` → 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/accounts/school_membership.ex \
  lib/teacher_assistant/accounts.ex priv/repo/migrations priv/resource_snapshots \
  test/teacher_assistant/accounts/statutory_hours_test.exs
git commit -m "feat: statutory service, school default and per-teacher override"
```

---

### Task 2: The grid and the loads (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/assignment_grid.ex`
- Test: `test/teacher_assistant/academics/assignment_grid_test.exs`

**Interfaces:**
- Consumes: `CoefficientRules.resolve/2`.
- Produces:
  - `AssignmentGrid.build(%{classes: [cg], subjects: [subject], contexts: [tc], cells: map, school_hours: int, services: %{user_id => int | nil}})`
    → `%{classes, subjects, cells: %{{cg_id, subject_id} => cell}, loads: %{user_id => %{load, service, over?}}, to_assign: int, without_pp: int}`
  - cell: `%{kind: :assigned, tc: tc, teacher_id, over?: boolean, combined?: boolean}` | `%{kind: :to_assign}` | `%{kind: :not_taught}`
  - `AssignmentGrid.load_after(grid, teacher_id, hours, current_teacher_id) :: integer`
  - `AssignmentGrid.service(grid_input_or_grid, teacher_id) :: integer`
  (`tc` needs `class_group_id`, `subject_id`, `teacher_user_id`, `weekly_hours`, `combined_course_id`; `cg` needs
  `id`, `subsystem`, `level`, `serie`, `form_master_user_id`; `subject` needs `id`.)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.AssignmentGridTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.AssignmentGrid

  defp cg(id, level, pp \\ nil),
    do: %{id: id, subsystem: :francophone, level: level, serie: nil, form_master_user_id: pp}

  defp tc(id, cg, subject, teacher, hours, combined \\ nil),
    do: %{id: id, class_group_id: cg, subject_id: subject, teacher_user_id: teacher, weekly_hours: hours, combined_course_id: combined}

  setup do
    input = %{
      classes: [cg("6a", "6ème", "u1"), cg("6b", "6ème"), cg("x", "Libre")],
      subjects: [%{id: "maths"}, %{id: "svt"}, %{id: "eps"}],
      cells: %{{"maths", :francophone, "6ème", nil} => 1, {"svt", :francophone, "6ème", nil} => 1},
      contexts: [
        tc("t1", "6a", "maths", "u1", 5),
        tc("t2", "6a", "svt", "u2", 3, "cc"),
        tc("t3", "6b", "svt", "u2", 3, "cc"),
        tc("t4", "x", "eps", "u2", 2)
      ],
      school_hours: 18,
      services: %{"u2" => 4}
    }

    %{input: input}
  end

  test "cells: assigned, to assign from the coefficient grid, not taught", %{input: input} do
    g = AssignmentGrid.build(input)
    assert %{kind: :assigned, teacher_id: "u1"} = g.cells[{"6a", "maths"}]
    assert %{kind: :to_assign} = g.cells[{"6b", "maths"}]
    assert %{kind: :not_taught} = g.cells[{"6a", "eps"}]
    # a class off the grid only shows what is assigned
    assert %{kind: :not_taught} = g.cells[{"x", "maths"}]
    assert %{kind: :assigned} = g.cells[{"x", "eps"}]
    assert g.to_assign == 1
    assert g.without_pp == 2
    assert Enum.map(g.subjects, & &1.id) == ["maths", "svt", "eps"]
  end

  test "loads count a combined course once and use each teacher's own service", %{input: input} do
    g = AssignmentGrid.build(input)
    assert %{load: 5, service: 18, over?: false} = g.loads["u1"]
    # svt combined (3) once + eps (2) = 5 > own service 4
    assert %{load: 5, service: 4, over?: true} = g.loads["u2"]
    assert %{kind: :assigned, over?: true, combined?: true} = g.cells[{"6a", "svt"}]
  end

  test "load after a change does not double-count the current holder", %{input: input} do
    g = AssignmentGrid.build(input)
    assert AssignmentGrid.load_after(g, "u1", 5, "u1") == 5
    assert AssignmentGrid.load_after(g, "u2", 5, "u1") == 10
    assert AssignmentGrid.load_after(g, "u9", 4, nil) == 4
    assert AssignmentGrid.service(g, "u9") == 18
  end

  test "subjects with no assigned or to-assign cell are dropped", %{input: input} do
    g = AssignmentGrid.build(%{input | contexts: [], cells: %{{"maths", :francophone, "6ème", nil} => 1}})
    assert Enum.map(g.subjects, & &1.id) == ["maths"]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/assignment_grid_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule TeacherAssistant.Academics.AssignmentGrid do
  @moduledoc """
  The school's assignments overview (spec J2, T04), pure: which class × subject cells
  are assigned, still to assign (the coefficient grid says the subject is taught there)
  or not taught, and each teacher's weekly load against their statutory service. A
  combined course counts once in its teacher's load.
  """
  alias TeacherAssistant.Academics.CoefficientRules

  def build(%{classes: classes, subjects: subjects, contexts: contexts, cells: cells} = input) do
    by_cell = Map.new(contexts, &{{&1.class_group_id, &1.subject_id}, &1})
    loads = loads(contexts, input)

    all =
      for c <- classes, s <- subjects, into: %{} do
        {{c.id, s.id}, cell(Map.get(by_cell, {c.id, s.id}), c, s, cells, loads)}
      end

    kept = Enum.filter(subjects, fn s -> Enum.any?(classes, &(all[{&1.id, s.id}].kind != :not_taught)) end)
    kept_ids = MapSet.new(kept, & &1.id)

    %{
      classes: classes,
      subjects: kept,
      cells: Map.filter(all, fn {{_c, s}, _} -> MapSet.member?(kept_ids, s) end),
      loads: loads,
      school_hours: input.school_hours,
      services: input.services,
      to_assign: Enum.count(all, fn {_, cell} -> cell.kind == :to_assign end),
      without_pp: Enum.count(classes, &is_nil(&1.form_master_user_id))
    }
  end

  defp cell(%{} = tc, _c, _s, _cells, loads) do
    %{
      kind: :assigned,
      tc: tc,
      teacher_id: tc.teacher_user_id,
      over?: get_in(loads, [tc.teacher_user_id, :over?]) || false,
      combined?: not is_nil(tc.combined_course_id)
    }
  end

  defp cell(nil, c, s, cells, _loads) do
    key = %{subject_id: s.id, subsystem: c.subsystem, level: c.level, serie: c.serie}
    if CoefficientRules.resolve(cells, key), do: %{kind: :to_assign}, else: %{kind: :not_taught}
  end

  defp loads(contexts, input) do
    contexts
    |> Enum.group_by(& &1.teacher_user_id)
    |> Map.new(fn {teacher, tcs} ->
      load =
        tcs
        |> Enum.uniq_by(&(&1.combined_course_id || {:solo, &1.id}))
        |> Enum.map(&(&1.weekly_hours || 0))
        |> Enum.sum()

      service = service(input, teacher)
      {teacher, %{load: load, service: service, over?: load > service}}
    end)
  end

  @doc "A teacher's own service: their override, else the school's."
  def service(%{services: services, school_hours: school}, teacher_id),
    do: Map.get(services, teacher_id) || school

  @doc "The teacher's load if they took a cell of `hours` currently held by `current_id`."
  def load_after(grid, teacher_id, hours, current_id) do
    current = get_in(grid.loads, [teacher_id, :load]) || 0
    if teacher_id == current_id, do: current, else: current + (hours || 0)
  end
end
```

- [ ] **Step 4: Run it**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/assignment_grid_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/assignment_grid.ex test/teacher_assistant/academics/assignment_grid_test.exs
git commit -m "feat: pure assignments grid and teacher loads"
```

---

### Task 3: Overview query and placing an assignment

**Files:**
- Modify: `lib/teacher_assistant/curriculum.ex`
- Test: `test/teacher_assistant/academics/assignments_overview_test.exs`

**Interfaces:**
- Consumes: Task 1 service fields; Task 2 `AssignmentGrid.build/1`.
- Produces:
  - `Curriculum.assignment_overview(scope) :: grid` (Task 2 shape, plus `members: [membership with :user]`);
    an empty grid (no classes) without an active year
  - `Curriculum.place_assignment(scope, cg, subject, user_id, hours_string) :: {:ok, tc} | {:error, :not_assignable | :invalid_hours | :combined | term}`
    (creates when no assignment exists for class × subject, else reassigns and sets the hours; refuses a combined one)
  - `Curriculum.assignment_at(scope, cg, subject_id) :: tc | nil`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.AssignmentsOverviewTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    :ok =
      Curriculum.update_coefficient_grid(scope, %{
        "cells" => %{maths.id => %{Curriculum.cell_token({:francophone, "6ème", nil}) => "4"}},
        "groups" => %{}
      })

    other = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, head: head, cg: cg, maths: maths, other: other}
  end

  test "an unassigned grid subject is to assign; placing assigns, then reassigns with the hours", ctx do
    %{scope: scope, cg: cg, maths: maths, head: head, other: other} = ctx
    g = Curriculum.assignment_overview(scope)
    assert %{kind: :to_assign} = g.cells[{cg.id, maths.id}]

    assert {:ok, tc} = Curriculum.place_assignment(scope, cg, maths, head.id, "5")
    assert tc.weekly_hours == 5
    assert %{kind: :assigned, teacher_id: tid} = Curriculum.assignment_overview(scope).cells[{cg.id, maths.id}]
    assert tid == head.id
    assert Curriculum.assignment_overview(scope).loads[head.id].load >= 5

    assert {:ok, tc2} = Curriculum.place_assignment(scope, cg, maths, other.user_id, "3")
    assert tc2.id == tc.id
    assert tc2.teacher_user_id == other.user_id
    assert tc2.weekly_hours == 3
  end

  test "refuses a non-member, bad hours, or another school's class", ctx do
    %{scope: scope, cg: cg, maths: maths} = ctx
    stranger = TeacherFixtures.user_fixture()
    assert {:error, :not_assignable} = Curriculum.place_assignment(scope, cg, maths, stranger.id, "4")
    assert {:error, :invalid_hours} = Curriculum.place_assignment(scope, cg, maths, ctx.head.id, "0")

    %{scope: other_scope} = TeacherFixtures.setup_complete_school_fixture()
    assert {:error, _} = Curriculum.place_assignment(other_scope, cg, maths, ctx.head.id, "4")
    assert Curriculum.assignment_at(scope, cg, maths.id) == nil
  end

  test "a plain teacher cannot place", ctx do
    teacher = %{TeacherFixtures.member_scope_fixture(ctx.scope) | current_academic_year: ctx.scope.current_academic_year}
    assert {:error, %Ash.Error.Forbidden{}} = Curriculum.place_assignment(teacher, ctx.cg, ctx.maths, ctx.head.id, "4")
  end
end
```

(`setup_complete_school_fixture/0` returns `head_user` and `year`; `membership_fixture/1` returns the membership
with `user_id`. If `update_coefficient_grid/2` rejects an empty `"groups"`, drop that key — ledger it.)

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/assignments_overview_test.exs`
Expected: FAIL — `assignment_overview/1` undefined.

- [ ] **Step 3: Implement**

In `Curriculum` (alias `AssignmentGrid`; `require Ash.Query` exists):

```elixir
  # --- Assignments overview (spec J2) ----------------------------------------------

  @doc "The school's classes × subjects grid, teacher loads and members (active year)."
  def assignment_overview(%Scope{} = scope) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    members = Accounts.list_members(scope)

    {classes, contexts} =
      case TeacherAssistant.Organization.current_academic_year(scope) do
        nil ->
          {[], []}

        year ->
          {scope |> Enrollment.list_class_groups(year) |> Enum.sort_by(&SchoolTemplates.class_sort_key/1),
           TeachingContext
           |> Ash.Query.filter(academic_year_id == ^year.id)
           |> Ash.read!(scope: scope)}
      end

    %{
      classes: classes,
      subjects: list_subjects(scope),
      contexts: contexts,
      cells: coefficient_cells(scope),
      school_hours: profile.statutory_hours,
      services: Map.new(members, &{&1.user_id, &1.statutory_hours})
    }
    |> AssignmentGrid.build()
    |> Map.put(:members, members)
  end

  @doc "The class's assignment for a subject, or nil."
  def assignment_at(%Scope{} = scope, %ClassGroup{} = cg, subject_id) do
    scope |> list_assignments_for_class(cg) |> Enum.find(&(&1.subject_id == subject_id))
  end

  @doc """
  Puts `user_id` on the class × subject cell with `hours` a week: assigns when the
  cell is empty, else reassigns and updates the hours. A combined course is refused
  here (it is changed on the class page).
  """
  def place_assignment(%Scope{} = scope, %ClassGroup{} = cg, %Subject{} = subject, user_id, hours) do
    with {:ok, hours} <- parse_weekly_hours(hours),
         {:ok, teacher} <- member_user(scope, user_id) do
      case assignment_at(scope, cg, subject.id) do
        nil ->
          assign_teacher(scope, cg, teacher, %{subject: subject, weekly_hours: hours})

        %TeachingContext{combined_course_id: cc} when not is_nil(cc) ->
          {:error, :combined}

        tc ->
          with {:ok, tc} <- reassign_teacher(scope, tc, teacher) do
            tc |> Ash.Changeset.for_update(:update, %{weekly_hours: hours}, scope: scope) |> Ash.update()
          end
      end
    end
  end

  defp member_user(scope, user_id) when is_binary(user_id) do
    case Accounts.fetch_school_membership(scope, %User{id: user_id}) do
      {:ok, m} -> {:ok, m |> Ash.load!(:user, scope: scope) |> Map.fetch!(:user)}
      _ -> {:error, :not_assignable}
    end
  end

  defp member_user(_scope, _), do: {:error, :not_assignable}

  defp parse_weekly_hours(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n in 1..20 -> {:ok, n}
      _ -> {:error, :invalid_hours}
    end
  end

  defp parse_weekly_hours(_), do: {:error, :invalid_hours}
```

Notes for the implementer:
- `assign_teacher/4` accepts a `%Subject{}` (see `resolve_subject/2`).
- For another school's class, `assignment_at` reads under the caller's tenant and finds nothing, then
  `assign_teacher` fails on the class's tenant (the changeset's class_group_id belongs to another workspace) —
  check the error is `{:error, _}` and nothing is written; if instead it succeeds, add an
  `Enrollment.fetch_owned_class_group(scope, cg.id)` guard at the start of `place_assignment/5` (ledger it).
- `fetch_school_membership/2` may already load `:user`; if so drop the `Ash.load!`.

- [ ] **Step 4: Run it**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/assignments_overview_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/curriculum.ex test/teacher_assistant/academics/assignments_overview_test.exs
git commit -m "feat: assignments overview query and placing an assignment from the grid"
```

---

### Task 4: « Affectations » page and the members' service field

**Files:**
- Create: `lib/teacher_assistant_web/live/school/assignments_live.ex`
- Modify: `router.ex` (after `live "/school/settings/holidays", …`), `spaces.ex` (item after each `holidays()`),
  `live/school/settings_live.ex` (link after `#holidays-link`), `live/school/members_live.ex`
- Test: `test/teacher_assistant_web/live/school/assignments_live_test.exs`, `members_live_test.exs` (new test)

**Interfaces:**
- Consumes: Task 1 `Accounts.update_school_service/2`, `set_member_service/3`, `can_set_member_service?/1`;
  Task 2 `AssignmentGrid.load_after/4`, `service/2`; Task 3 `Curriculum.assignment_overview/1`,
  `place_assignment/5`, `assignment_at/3`; existing `Curriculum.remove_assignment/2`, `can_manage_assignments?/1`,
  `Enrollment.set_form_master/3`.
- Produces: route `/school/settings/assignments`; ids `#assignments-grid`, `#cell-<cg>-<subject>`,
  `#pp-<cg>`, `#assign-panel`, `#pick-<user_id>`, `#hours-input`, `#remove-assignment`, `#pp-panel`,
  `#pp-pick-<user_id>`, `#pp-none`, `#loads`, `#load-<user_id>`, `#service-form`, `#assignments-link`,
  `#to-assign-count`, `#panel-error`; members page `#service-<membership_id>`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/assignments_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.AssignmentsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Curriculum, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    :ok =
      Curriculum.update_coefficient_grid(scope, %{
        "cells" => %{maths.id => %{Curriculum.cell_token({:francophone, "6ème", nil}) => "4"}},
        "groups" => %{}
      })

    other = TeacherFixtures.membership_fixture(scope)
    %{scope: scope, cg: cg, maths: maths, other: other}
  end

  test "settings links to the grid; an unassigned grid subject reads À affecter", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#assignments-link")
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    assert has_element?(view, "#cell-#{ctx.cg.id}-#{ctx.maths.id}", "À affecter")
    assert has_element?(view, "#pp-#{ctx.cg.id}", "Sans professeur principal")
  end

  test "assigns from the panel with its hours, then removes", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#cell-#{ctx.cg.id}-#{ctx.maths.id}") |> render_click()
    view |> form("#hours-form", %{hours: "5"}) |> render_change()
    view |> element("#pick-#{ctx.other.user_id}") |> render_click()

    tc = Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id)
    assert tc.teacher_user_id == ctx.other.user_id
    assert tc.weekly_hours == 5
    assert has_element?(view, "#load-#{ctx.other.user_id}")

    view |> element("#remove-assignment") |> render_click()
    assert Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id) == nil
  end

  test "removing an assignment with marks is refused", %{conn: conn} = ctx do
    {:ok, tc} = Curriculum.place_assignment(ctx.scope, ctx.cg, ctx.maths, ctx.other.user_id, "4")
    [seq | _] = Organization.list_sequences(ctx.scope, ctx.scope.current_academic_year)

    {:ok, _} =
      TeacherAssistant.Assessment.create_assessment(ctx.scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#cell-#{ctx.cg.id}-#{ctx.maths.id}") |> render_click()
    view |> element("#remove-assignment") |> render_click()
    assert has_element?(view, "#panel-error", "des notes ou une progression existent")
    assert Curriculum.assignment_at(ctx.scope, ctx.cg, ctx.maths.id)
  end

  test "sets the form master from the grid", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> element("#pp-#{ctx.cg.id}") |> render_click()
    view |> element("#pp-pick-#{ctx.other.user_id}") |> render_click()
    {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
    assert cg.form_master_user_id == ctx.other.user_id
  end

  test "saves the school's statutory service", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/assignments")
    view |> form("#service-form", %{service: "20"}) |> render_submit()
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)
    assert profile.statutory_hours == 20
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/assignments")
  end
end
```

(If `register_and_log_in_user`'s school already holds a class « 6e Z » or the label clashes, pick another.)

Add to `members_live_test.exs` (its setup builds a head's school):

```elixir
  test "the head sets a teacher's own weekly service (spec J2)", %{conn: conn, scope: scope} do
    m = TeacherAssistant.TeacherFixtures.membership_fixture(scope)
    {:ok, view, _} = live(conn, ~p"/school/members")
    view |> form("#service-#{m.id}", %{service: "12"}) |> render_submit()
    assert Enum.find(TeacherAssistant.Accounts.list_members(scope), &(&1.id == m.id)).statutory_hours == 12
  end
```

(Use the file's own setup names and members route; if the scope key differs, adapt.)

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/assignments_live_test.exs test/teacher_assistant_web/live/school/members_live_test.exs`
Expected: FAIL — no route / no `#service-…` form.

- [ ] **Step 3: The LiveView**

`lib/teacher_assistant_web/live/school/assignments_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.AssignmentsLive do
  @moduledoc """
  Settings → Affectations (spec J2, T04): the school's classes × subjects grid with
  each class's form master, a side panel to assign, reassign or remove (showing each
  teacher's load after the change), the teachers' loads, and the statutory service.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum, Enrollment}
  alias TeacherAssistant.Academics.AssignmentGrid

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Curriculum.can_manage_assignments?(scope) do
      {:ok, socket |> assign(selected: nil, pp_for: nil, hours: "4", panel_error: nil) |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket) do
    grid = Curriculum.assignment_overview(socket.assigns.current_scope)
    users = Map.new(grid.members, &{&1.user_id, &1.user})
    assign(socket, grid: grid, users: users)
  end

  # --- events ---------------------------------------------------------------

  def handle_event("select", %{"class" => cg_id, "subject" => s_id}, socket) do
    cell = socket.assigns.grid.cells[{cg_id, s_id}]

    if cell && cell.kind in [:assigned, :to_assign] do
      hours = if cell.kind == :assigned, do: to_string(cell.tc.weekly_hours || 4), else: "4"
      {:noreply, assign(socket, selected: {cg_id, s_id}, pp_for: nil, hours: hours, panel_error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hours", %{"hours" => hours}, socket),
    do: {:noreply, assign(socket, hours: hours)}

  def handle_event("pick", %{"user" => user_id}, socket) do
    with {cg_id, s_id} <- socket.assigns.selected,
         %{} = cg <- Enum.find(socket.assigns.grid.classes, &(&1.id == cg_id)),
         %{} = subject <- Enum.find(socket.assigns.grid.subjects, &(&1.id == s_id)) do
      socket.assigns.current_scope
      |> Curriculum.place_assignment(cg, subject, user_id, socket.assigns.hours)
      |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove", _params, socket) do
    with {cg_id, s_id} <- socket.assigns.selected,
         %{kind: :assigned, tc: tc} <- socket.assigns.grid.cells[{cg_id, s_id}] do
      case Curriculum.remove_assignment(socket.assigns.current_scope, tc) do
        :ok -> {:noreply, socket |> assign(selected: nil) |> load()}
        other -> after_write(other, socket)
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pp", %{"class" => cg_id}, socket),
    do: {:noreply, assign(socket, pp_for: cg_id, selected: nil, panel_error: nil)}

  def handle_event("pp_pick", %{"user" => user_id}, socket) do
    with cg_id when is_binary(cg_id) <- socket.assigns.pp_for,
         %{} = cg <- Enum.find(socket.assigns.grid.classes, &(&1.id == cg_id)) do
      user_id = if user_id == "", do: nil, else: user_id

      socket.assigns.current_scope
      |> Enrollment.set_form_master(cg, user_id)
      |> after_write(socket)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("service", %{"service" => value}, socket) do
    case Accounts.update_school_service(socket.assigns.current_scope, value) do
      {:ok, _} -> {:noreply, socket |> load() |> put_flash(:info, gettext("Réglage enregistré."))}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Indiquez un nombre d'heures entre 1 et 40."))}
    end
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, selected: nil, pp_for: nil, panel_error: nil)}

  defp after_write({:ok, _}, socket), do: {:noreply, socket |> assign(panel_error: nil) |> load()}
  defp after_write({:error, %Ash.Error.Forbidden{}}, socket), do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_write({:error, reason}, socket),
    do: {:noreply, assign(socket, panel_error: error_text(reason))}

  defp error_text(:has_data), do: gettext("Impossible : des notes ou une progression existent.")
  defp error_text(:invalid_hours), do: gettext("Indiquez des heures entre 1 et 20.")
  defp error_text(:not_assignable), do: gettext("Cette personne n'est pas membre de l'école.")
  defp error_text(:combined), do: gettext("Cours regroupé : modifiez-le depuis la fiche de la classe.")
  defp error_text(_), do: gettext("Modification non enregistrée.")

  # --- view helpers -----------------------------------------------------------

  defp name(users, id) do
    case users[id] do
      nil -> "—"
      u -> u.name || to_string(u.email)
    end
  end

  defp load_of(grid, id), do: get_in(grid.loads, [id, :load]) || 0

  # Members for the panel: those teaching the subject somewhere first.
  defp candidates(grid, subject_id) do
    teaching =
      grid.cells
      |> Enum.filter(fn {{_c, s}, cell} -> s == subject_id and cell.kind == :assigned end)
      |> MapSet.new(fn {_, cell} -> cell.teacher_id end)

    Enum.sort_by(grid.members, &{not MapSet.member?(teaching, &1.user_id), String.downcase(to_string(&1.user.email))})
  end

  defp hours_int(hours) do
    case Integer.parse(hours || "") do
      {n, _} -> n
      _ -> 0
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="assignments" class="space-y-6">
        <.page_header eyebrow={gettext("Organisation")} title={gettext("Affectations")}
          subtitle={gettext("Qui enseigne quoi, dans quelle classe — avec la charge horaire de chaque enseignant.")} />

        <div class="flex flex-wrap gap-3 text-sm">
          <span id="to-assign-count" class={if @grid.to_assign > 0, do: "text-error font-semibold", else: "text-success"}>
            {if @grid.to_assign > 0,
              do: ngettext("%{count} enseignement à affecter", "%{count} enseignements à affecter", @grid.to_assign),
              else: gettext("Tous les enseignements sont affectés")}
          </span>
          <span :if={@grid.without_pp > 0} class="text-warning font-semibold">
            {ngettext("%{count} classe sans professeur principal", "%{count} classes sans professeur principal", @grid.without_pp)}
          </span>
        </div>

        <div class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_320px]">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table id="assignments-grid" class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Classe")}</th>
                  <th>{gettext("Prof. principal")}</th>
                  <th :for={s <- @grid.subjects} class="whitespace-nowrap">{s.name}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={c <- @grid.classes}>
                  <td class="font-semibold whitespace-nowrap">{c.label}</td>
                  <td>
                    <button id={"pp-#{c.id}"} type="button" phx-click="pp" phx-value-class={c.id}
                      class={["text-left text-xs", is_nil(c.form_master_user_id) && "text-warning"]}>
                      {if c.form_master_user_id, do: name(@users, c.form_master_user_id), else: gettext("Sans professeur principal")}
                    </button>
                  </td>
                  <td :for={s <- @grid.subjects} class="p-1">
                    <% cell = @grid.cells[{c.id, s.id}] %>
                    <%= case cell.kind do %>
                      <% :not_taught -> %>
                        <div id={"cell-#{c.id}-#{s.id}"} class="h-9 rounded border border-dashed border-base-300" title={gettext("Non enseignée")}></div>
                      <% :to_assign -> %>
                        <button id={"cell-#{c.id}-#{s.id}"} type="button" phx-click="select" phx-value-class={c.id} phx-value-subject={s.id}
                          class={["h-9 w-full rounded bg-error/30 px-2 text-xs", @selected == {c.id, s.id} && "ring-2 ring-base-content"]}>
                          {gettext("À affecter")}
                        </button>
                      <% :assigned -> %>
                        <button id={"cell-#{c.id}-#{s.id}"} type="button" phx-click="select" phx-value-class={c.id} phx-value-subject={s.id}
                          class={["h-9 w-full truncate rounded px-2 text-xs", if(cell.over?, do: "bg-warning/30", else: "bg-primary/15"), @selected == {c.id, s.id} && "ring-2 ring-base-content"]}>
                          {name(@users, cell.teacher_id)}
                          <span :if={cell.combined?} class="badge badge-ghost badge-xs">{gettext("regroupé")}</span>
                        </button>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside class="space-y-4">
            <%= if @selected do %>
              <% {cg_id, s_id} = @selected %>
              <% cell = @grid.cells[{cg_id, s_id}] %>
              <% cls = Enum.find(@grid.classes, &(&1.id == cg_id)) %>
              <% subj = Enum.find(@grid.subjects, &(&1.id == s_id)) %>
              <% current = if cell.kind == :assigned, do: cell.teacher_id %>
              <div id="assign-panel" class="ta-panel space-y-3 p-4">
                <div class="flex items-start justify-between gap-2">
                  <h2 class="font-semibold">{cls.label} · {subj.name}</h2>
                  <button type="button" phx-click="close" class="btn btn-ghost btn-xs" aria-label={gettext("Fermer")}>
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <%= if cell.kind == :assigned and cell.combined? do %>
                  <p class="text-sm">{gettext("Cours regroupé : modifiez-le depuis la fiche de la classe.")}</p>
                  <.link navigate={~p"/school/classes/#{cg_id}"} class="link link-primary text-sm">{gettext("Ouvrir la classe")}</.link>
                <% else %>
                  <p class="text-sm text-base-content/70">
                    {if current, do: gettext("Affecté à %{name}", name: name(@users, current)), else: gettext("Non affecté")}
                  </p>
                  <.form for={%{}} id="hours-form" phx-change="hours">
                    <.input name="hours" value={@hours} inputmode="numeric" label={gettext("Heures / semaine")} class="input input-sm w-20 text-right" />
                  </.form>
                  <ul class="space-y-1">
                    <li :for={m <- candidates(@grid, s_id)}>
                      <% after_load = AssignmentGrid.load_after(@grid, m.user_id, hours_int(@hours), current) %>
                      <% service = AssignmentGrid.service(@grid, m.user_id) %>
                      <button id={"pick-#{m.user_id}"} type="button" phx-click="pick" phx-value-user={m.user_id}
                        class={["flex w-full justify-between rounded border px-2 py-1 text-left text-sm", m.user_id == current && "border-primary bg-primary/10"]}>
                        <span class="truncate">{name(@users, m.user_id)}</span>
                        <span class={["ta-num text-xs", after_load > service && "text-error"]}>
                          {if m.user_id == current,
                            do: gettext("%{load} h / %{service} h", load: after_load, service: service),
                            else: gettext("%{load} h / %{service} h après", load: after_load, service: service)}
                        </span>
                      </button>
                    </li>
                  </ul>
                  <button :if={current} id="remove-assignment" type="button" phx-click="remove" class="btn btn-ghost btn-sm text-error">
                    {gettext("Retirer l'affectation")}
                  </button>
                <% end %>
                <p :if={@panel_error} id="panel-error" class="text-sm text-error">{@panel_error}</p>
              </div>
            <% end %>

            <%= if @pp_for do %>
              <% cls = Enum.find(@grid.classes, &(&1.id == @pp_for)) %>
              <div id="pp-panel" class="ta-panel space-y-3 p-4">
                <h2 class="font-semibold">{gettext("Professeur principal · %{class}", class: cls.label)}</h2>
                <ul class="space-y-1">
                  <li :for={m <- @grid.members}>
                    <button id={"pp-pick-#{m.user_id}"} type="button" phx-click="pp_pick" phx-value-user={m.user_id}
                      class={["w-full rounded border px-2 py-1 text-left text-sm", cls.form_master_user_id == m.user_id && "border-primary bg-primary/10"]}>
                      {name(@users, m.user_id)}
                    </button>
                  </li>
                </ul>
                <button id="pp-none" type="button" phx-click="pp_pick" phx-value-user="" class="btn btn-ghost btn-sm">{gettext("Aucun")}</button>
                <p :if={@panel_error} id="panel-error" class="text-sm text-error">{@panel_error}</p>
              </div>
            <% end %>

            <div id="loads" class="ta-panel space-y-2 p-4">
              <h2 class="ta-eyebrow">{gettext("Charge des enseignants")}</h2>
              <div :for={{id, l} <- Enum.sort_by(@grid.loads, fn {_, l} -> -l.load end)} id={"load-#{id}"} class="space-y-1">
                <div class="flex justify-between text-sm">
                  <span class="truncate">{name(@users, id)}</span>
                  <span class={["ta-num", l.over? && "text-error"]}>{l.load} h / {l.service} h</span>
                </div>
                <div class="h-1.5 rounded bg-base-200">
                  <div class={["h-1.5 rounded", if(l.over?, do: "bg-error", else: "bg-primary")]}
                    style={"width: #{min(100, round(l.load / max(l.service, 1) * 100))}%"}></div>
                </div>
              </div>
            </div>

            <.form for={%{}} id="service-form" phx-submit="service" class="ta-panel flex items-end gap-2 p-4">
              <.input name="service" value={@grid.school_hours} inputmode="numeric" label={gettext("Service statutaire (h / semaine)")} class="input input-sm w-20 text-right" />
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            </.form>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

Notes: the `Users`' display name field — check `User` for `:name`; if absent use the email only (ledger).
`<% … = … %>` assignments inside a LiveView template disable change tracking for that block; acceptable here
(small page), or move them into helpers if `mix compile` warns.

- [ ] **Step 4: Members page**

In `MembersLive`: assign `can_set_service?: Accounts.can_set_member_service?(scope)` in mount; add a
« Service (h/sem.) » column with, per member row:

```heex
<td>
  <.form :if={@can_set_service?} for={%{}} id={"service-#{m.id}"} phx-submit="set_service" phx-value-id={m.id}>
    <input name="service" value={m.statutory_hours} placeholder={gettext("École")} inputmode="numeric"
      class="input input-bordered input-xs w-16 text-right" />
  </.form>
  <span :if={!@can_set_service?}>{m.statutory_hours || "—"}</span>
</td>
```

(`phx-value-id` on a form is sent with submit as `"id"`; if not, add `<input type="hidden" name="id" value={m.id} />`.)

```elixir
  def handle_event("set_service", %{"id" => id, "service" => value}, socket) do
    scope = socket.assigns.scope

    with %{} = m <- find_membership(scope, id),
         {:ok, _} <- Accounts.set_member_service(scope, m, value) do
      {:noreply, socket |> reload_members() |> put_flash(:info, gettext("Réglage enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, :invalid_hours} -> {:noreply, put_flash(socket, :error, gettext("Indiquez un nombre d'heures entre 1 et 40."))}
      _ -> {:noreply, socket}
    end
  end
```

- [ ] **Step 5: Route and links**

Router after `live "/school/settings/holidays", …`: `live "/school/settings/assignments", School.AssignmentsLive, :index`.
`spaces.ex`: `defp assignments` item (« Affectations », `hero-squares-2x2`, `~p"/school/settings/assignments"`)
after each `holidays()` call. `settings_live.ex`: `#assignments-link` after `#holidays-link`.

- [ ] **Step 6: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/assignments_live_test.exs test/teacher_assistant_web/live/school/members_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/assignments_live.ex lib/teacher_assistant_web/live/school/members_live.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/assignments_live_test.exs test/teacher_assistant_web/live/school/members_live_test.exs
git commit -m "feat: Affectations page (grid, panels, loads, service) and per-teacher service on members"
```

---

### Task 5: Translations, status, full checks

- [ ] **Step 1:** `mix gettext.extract --merge`; translate every new msgid in `en` (« Affectations » → "Teaching
  assignments", « À affecter » → "To assign", « Sans professeur principal » → "No form master", « Charge des
  enseignants » → "Teaching loads", « Service statutaire (h / semaine) » → "Statutory service (h / week)",
  « %{load} h / %{service} h après » → "%{load} h / %{service} h after", « regroupé » → "combined", plural
  forms for the two `ngettext` counts, …); clear new fuzzy flags; counts not above main's (en 24, fr 17).
- [ ] **Step 2:** In the spec's J2 section add before "Mockup:":
  `Status: implemented 2026-10-01 (branch \`j2-assignments-overview\`, plan \`docs/superpowers/plans/2026-10-01-j2-assignments-overview.md\`); no visual check done.`
- [ ] **Step 3:** `MIX_TEST_PARTITION=2 mix precommit`, `mix ash.codegen --check`, `mix compile --warnings-as-errors --force`.
- [ ] **Step 4: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git status --short   # stage formatter-rewritten branch files explicitly
git commit -m "chore: J2 translations and status"
```
