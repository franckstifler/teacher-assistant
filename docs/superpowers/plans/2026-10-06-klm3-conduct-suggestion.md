# KLM3 — Suggested conduct mark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A « Conduite » page where the SG sees, for a class and a séquence, a conduct mark suggested by the
school's scale, adjusts it and validates the whole class in one go.

**Architecture:** A pure `Academics.ConductSuggestion.suggest/2` computes the mark and its itemised deductions
from a student's séquence facts and the KLM2 rules. `Discipline.conduct_sheet/3` gathers those facts for a
whole class with one read per kind (attendance totals, sanctions, current marks), and
`Discipline.set_conduct_marks/4` saves a class in one transaction. `ConductLive` (`/school/conduct`) renders
it. No new data: no migration.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3.33, Decimal, Gettext (French msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM3 — Suggested conduct mark (spec)".

## Global Constraints

- Worktree `.claude/worktrees/klm3`, branch `klm3-conduct-suggestion`, `MIX_TEST_PARTITION=3` for every
  `mix test`. Stage explicit paths only; never `git commit -a`.
- No migration: `mix ash.codegen --check` must stay clean.
- Suggestion, verbatim from the spec: `20 − hours × p_hour − retards × p_late − Σ sanction points`, clamped
  to 0..20, rounded **down** to the nearest 0.25. Only **unjustified** absence hours count; a late over the
  KLM2 threshold is already counted as absence hours by `Attendance.class_conduct/3`.
- The scale comes from `Attendance.school_life_rules/1` (`points_per_absence_hour`, `points_per_late`,
  `sanction_points[type]`).
- Sanctions count when their `date` is within the séquence's `start_date..end_date`.
- Page: `:conduct` axis (`Discipline.can_manage_conduct?/1`: head, vice_principal, discipline_master);
  others are sent to `/school` with the usual flash. Conduct marks are not under the D3 lock: a closed
  séquence still works.
- « Valider la classe » saves every row whose input holds a value, in **one transaction**: one bad value
  (outside 0..20 or not a number) saves nothing and names the student.
- Strings through gettext; after `mix gettext.extract --merge`, fill new `en` msgstr and clear new fuzzy flags
  (main has 0).
- `mix precommit` before the last commit.

## Review Focus

1. A student with no absence, late or sanction in the séquence — listed with a suggestion of 20 and no
   deductions (test in Task 2).
2. A sanction dated just outside the séquence — not counted in that séquence's suggestion (test in Task 2).
3. One bad value (« 25 » or « abc ») among the class's inputs — nothing saved, the error names that student
   (test in Task 2 and Task 3).
4. Validating the same class twice — the marks are replaced, never duplicated (test in Task 2).
5. A row edited away from its suggestion, then « Appliquer les propositions » — the input returns to the
   suggestion and « ajustée » disappears (test in Task 3).

---

### Task 0: Worktree

- [ ] **Step 1: Create the worktree and check the baseline**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm3 -b klm3-conduct-suggestion main
cd .claude/worktrees/klm3 && mix deps.get
MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/discipline_live_test.exs
```

Expected: 0 failures.

---

### Task 1: The suggestion (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/conduct_suggestion.ex`
- Test: `test/teacher_assistant/academics/conduct_suggestion_test.exs`

**Interfaces:**
- Consumes: `%Academics.SchoolLifeRules{}` (KLM2).
- Produces: `ConductSuggestion.suggest(facts, rules) :: %{mark: Decimal.t(), deductions: [deduction]}` where
  `facts` is `%{unjustified_hours: Decimal.t(), retards: non_neg_integer(), sanction_types: [SanctionType.t()]}`
  and `deduction` is `%{kind: :absences | :retards | {:sanction, SanctionType.t()}, count: number, points:
  Decimal.t()}` (only non-zero counts are listed; one entry per sanction type with its count).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.ConductSuggestionTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.{ConductSuggestion, SchoolLifeRules}

  @rules %SchoolLifeRules{}

  defp facts(attrs),
    do: Map.merge(%{unjustified_hours: Decimal.new(0), retards: 0, sanction_types: []}, attrs)

  test "a clean séquence keeps 20 with no deductions" do
    assert %{mark: mark, deductions: []} = ConductSuggestion.suggest(facts(%{}), @rules)
    assert Decimal.equal?(mark, 20)
  end

  test "the settings page's example: 6 h, 2 lates, 1 avertissement → 14.5" do
    %{mark: mark, deductions: deductions} =
      ConductSuggestion.suggest(
        facts(%{unjustified_hours: Decimal.new(6), retards: 2, sanction_types: [:avertissement]}),
        @rules
      )

    assert Decimal.equal?(mark, Decimal.new("14.5"))

    assert [
             %{kind: :absences, points: absences},
             %{kind: :retards, count: 2, points: lates},
             %{kind: {:sanction, :avertissement}, count: 1, points: warning}
           ] = deductions

    assert Decimal.equal?(absences, 3)
    assert Decimal.equal?(lates, Decimal.new("0.5"))
    assert Decimal.equal?(warning, 2)
  end

  test "rounds down to the nearest quarter" do
    # One 50-minute lesson: 5/6 h × 0.5 = 0.4166… → 19.5833… → 19.5
    hours = Decimal.div(Decimal.new(50), Decimal.new(60))

    %{mark: mark} = ConductSuggestion.suggest(facts(%{unjustified_hours: hours}), @rules)
    assert Decimal.equal?(mark, Decimal.new("19.5"))
  end

  test "groups sanctions by type and never goes below 0" do
    %{mark: mark, deductions: deductions} =
      ConductSuggestion.suggest(
        facts(%{sanction_types: [:blame, :exclusion_temporaire, :blame, :exclusion_temporaire]}),
        @rules
      )

    assert Decimal.equal?(mark, 0)
    assert %{count: 2} = Enum.find(deductions, &(&1.kind == {:sanction, :blame}))
  end

  test "follows the school's scale" do
    rules = %{@rules | points_per_late: Decimal.new(1), sanction_points: %{@rules.sanction_points | consigne: Decimal.new("0.5")}}

    %{mark: mark} =
      ConductSuggestion.suggest(facts(%{retards: 3, sanction_types: [:consigne]}), rules)

    assert Decimal.equal?(mark, Decimal.new("16.5"))
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/conduct_suggestion_test.exs`
Expected: FAIL — `TeacherAssistant.Academics.ConductSuggestion` is not available.

- [ ] **Step 3: Implement**

```elixir
defmodule TeacherAssistant.Academics.ConductSuggestion do
  @moduledoc """
  Spec KLM3 (V05): the conduct mark a student's séquence suggests under the
  school's scale (KLM2) — 20 minus the points of unjustified absence hours,
  lates and sanctions, kept within 0..20 and rounded down to the quarter —
  with the itemised deductions. Pure.
  """

  alias TeacherAssistant.Academics.{SanctionType, SchoolLifeRules}

  @max Decimal.new(20)
  @quarter Decimal.new("0.25")

  def suggest(facts, %SchoolLifeRules{} = rules) do
    deductions =
      [
        %{
          kind: :absences,
          count: facts.unjustified_hours,
          points: Decimal.mult(facts.unjustified_hours, rules.points_per_absence_hour)
        },
        %{
          kind: :retards,
          count: facts.retards,
          points: Decimal.mult(facts.retards, rules.points_per_late)
        }
        | sanction_deductions(facts.sanction_types, rules)
      ]
      |> Enum.reject(&zero_count?/1)

    total = Enum.reduce(deductions, Decimal.new(0), &Decimal.add(&1.points, &2))

    mark =
      @max
      |> Decimal.sub(total)
      |> Decimal.max(0)
      |> Decimal.min(@max)
      |> round_down_to_quarter()

    %{mark: mark, deductions: deductions}
  end

  # One deduction per sanction type, in the enum's order.
  defp sanction_deductions(types, rules) do
    counts = Enum.frequencies(types)

    for type <- SanctionType.values(), count = Map.get(counts, type), count do
      %{
        kind: {:sanction, type},
        count: count,
        points: Decimal.mult(count, rules.sanction_points[type])
      }
    end
  end

  defp zero_count?(%{count: %Decimal{} = count}), do: Decimal.equal?(count, 0)
  defp zero_count?(%{count: count}), do: count == 0

  defp round_down_to_quarter(value) do
    value
    |> Decimal.div(@quarter)
    |> Decimal.round(0, :floor)
    |> Decimal.mult(@quarter)
    |> Decimal.normalize()
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/conduct_suggestion_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/conduct_suggestion.ex test/teacher_assistant/academics/conduct_suggestion_test.exs
git commit -m "feat: suggested conduct mark from the school's scale"
```

---

### Task 2: The class sheet and the class save

**Files:**
- Modify: `lib/teacher_assistant/discipline.ex` (`conduct_sheet/3`, `set_conduct_marks/4`)
- Test: `test/teacher_assistant/discipline_conduct_sheet_test.exs`

**Interfaces:**
- Consumes: `ConductSuggestion.suggest/2` (Task 1); `Attendance.class_conduct(scope, cg, {:sequence, seq})`
  (`%{enrollment_id => %{unjustified_hours, justified_hours, retards}}`); `Attendance.school_life_rules/1`;
  `list_sanctions(scope, cg, {:sequence, seq})`; `conduct_marks_for_enrollments_sequences!/3`.
- Produces:
  - `Discipline.conduct_sheet(scope, %ClassGroup{}, %Sequence{}) :: [row]`, roster order (name), where
    `row = %{enrollment: %Enrollment{}, student: %Student{}, unjustified_hours: Decimal.t(), retards:
    integer, sanctions: [%SanctionEntry{}], current: Decimal.t() | nil, suggestion: %{mark: Decimal.t(),
    deductions: [deduction]}}`;
  - `Discipline.set_conduct_marks(scope, %ClassGroup{}, %Sequence{}, values :: %{enrollment_id => String.t()
    | Decimal.t() | number}) :: {:ok, count} | {:error, {:invalid_value, enrollment_id}} |
    {:error, :not_in_class} | {:error, %Ash.Error.Forbidden{}}` — blank values are skipped.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.DisciplineConductSheetTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Discipline, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  # 2025-09-15 is a Monday; lesson 1 runs 07:30–08:20 (50 minutes).
  @monday ~D[2025-09-15]

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    _ = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, other_cg} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, other_cg, %{full_name: "Zoé", sex: :f})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    [%{enrollment: zoe}] = Enrollment.list_roster(scope, other_cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{day: :monday, period_id: p1.id, teaching_context_id: tc.id})

    seq = Organization.current_sequence(scope, year, @monday)

    %{scope: scope, cg: cg, tc: tc, p1: p1, awa: awa, bob: bob, zoe: zoe, seq: seq, year: year}
  end

  test "each row carries the séquence's facts, the current mark and the suggestion", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [
        {ctx.awa.id, :absent},
        {ctx.bob.id, :late}
      ])

    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: @monday})

    # Outside the séquence: not counted.
    {:ok, _} =
      Discipline.add_sanction(ctx.scope, ctx.awa, %{
        type: :blame,
        date: Date.add(ctx.seq.end_date, 1)
      })

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)

    assert awa_row.student.full_name == "Awa"
    assert awa_row.current == nil
    assert [%{type: :avertissement}] = awa_row.sanctions
    # 20 − 5/6 × 0.5 − 2 = 17.583… → 17.5
    assert Decimal.equal?(awa_row.suggestion.mark, Decimal.new("17.5"))

    assert bob_row.retards == 1
    # 20 − 0.25
    assert Decimal.equal?(bob_row.suggestion.mark, Decimal.new("19.75"))
  end

  test "a clean student is listed at 20 with no deductions", ctx do
    rows = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)
    assert Enum.all?(rows, &(Decimal.equal?(&1.suggestion.mark, 20) and &1.suggestion.deductions == []))
  end

  test "the class is saved in one go; saving again replaces the marks", ctx do
    assert {:ok, 2} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "17,5",
               ctx.bob.id => "19.75"
             })

    assert {:ok, 1} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "16",
               ctx.bob.id => ""
             })

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)
    assert Decimal.equal?(awa_row.current, 16)
    assert Decimal.equal?(bob_row.current, Decimal.new("19.75"))
  end

  test "one bad value saves nothing and names the student", ctx do
    assert {:error, {:invalid_value, id}} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "15",
               ctx.bob.id => "25"
             })

    assert id == ctx.bob.id

    assert {:error, {:invalid_value, _}} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{ctx.awa.id => "abc"})

    assert Enum.all?(Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq), &is_nil(&1.current))
  end

  test "a student of another class is refused", ctx do
    assert {:error, :not_in_class} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{ctx.zoe.id => "15"})
  end

  test "a plain teacher may not save", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    teacher = %{teacher | current_academic_year: ctx.year}

    assert_forbidden(
      Discipline.set_conduct_marks(teacher, ctx.cg, ctx.seq, %{ctx.awa.id => "15"})
    )
  end
end
```

(If `list_roster/2` returns Bob before Awa, it doesn't: it sorts by lower-cased name. If the
`member_scope_fixture` scope already carries the year, drop the `%{teacher | …}` line.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/discipline_conduct_sheet_test.exs`
Expected: FAIL — `Discipline.conduct_sheet/3 is undefined`.

- [ ] **Step 3: Implement**

In `lib/teacher_assistant/discipline.ex`, add `ConductSuggestion` to the academics aliases
(`alias TeacherAssistant.Academics.ConductSuggestion`), then append before the private
`batch_conduct_values` helpers:

```elixir
  # --- Suggested conduct marks (spec KLM3) ---------------------------------------

  @doc """
  One row per student of `class_group` for `sequence`: unjustified absence
  hours and lates (a long late already counts as hours, KLM2), the séquence's
  sanctions, the current conduct mark and the suggestion. One read per kind.
  """
  def conduct_sheet(%Scope{} = scope, %ClassGroup{} = class_group, %Sequence{} = sequence) do
    period = {:sequence, sequence}
    rules = TeacherAssistant.Attendance.school_life_rules(scope)
    roster = TeacherAssistant.Enrollment.list_roster(scope, class_group)
    totals = TeacherAssistant.Attendance.class_conduct(scope, class_group, period)
    sanctions = scope |> list_sanctions(class_group, period) |> Enum.group_by(& &1.enrollment_id)

    current =
      roster
      |> Enum.map(& &1.enrollment.id)
      |> then(fn
        [] -> []
        ids -> conduct_marks_for_enrollments_sequences!(ids, [sequence.id], scope: scope)
      end)
      |> Map.new(&{&1.enrollment_id, &1.value})

    Enum.map(roster, fn %{student: student, enrollment: enrollment} ->
      %{unjustified_hours: hours, retards: retards} = Map.fetch!(totals, enrollment.id)
      entries = Map.get(sanctions, enrollment.id, [])

      %{
        enrollment: enrollment,
        student: student,
        unjustified_hours: hours,
        retards: retards,
        sanctions: entries,
        current: Map.get(current, enrollment.id),
        suggestion:
          ConductSuggestion.suggest(
            %{unjustified_hours: hours, retards: retards, sanction_types: Enum.map(entries, & &1.type)},
            rules
          )
      }
    end)
  end

  @doc """
  Saves the class's conduct marks for `sequence` from `values`
  (`enrollment_id => value`, comma or dot), skipping blanks, in one
  transaction: any bad value or foreign student saves nothing.
  """
  def set_conduct_marks(%Scope{} = scope, %ClassGroup{} = class_group, %Sequence{} = sequence, values) do
    roster =
      scope |> TeacherAssistant.Enrollment.list_roster(class_group) |> Map.new(&{&1.enrollment.id, &1.enrollment})

    with {:ok, marks} <- parse_class_marks(values, roster) do
      Ash.transact([ConductMark], fn ->
        Enum.reduce_while(marks, {:ok, 0}, fn {enrollment, value}, {:ok, n} ->
          case set_conduct_mark(scope, enrollment, sequence, value) do
            {:ok, _} -> {:cont, {:ok, n + 1}}
            {:error, error} -> {:halt, Ash.DataLayer.rollback(ConductMark, error)}
          end
        end)
      end)
      |> case do
        {:ok, {:ok, count}} -> {:ok, count}
        {:ok, count} when is_integer(count) -> {:ok, count}
        {:error, :invalid_value} -> {:error, :invalid_value}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp parse_class_marks(values, roster) do
    Enum.reduce_while(values, {:ok, []}, fn {id, raw}, {:ok, acc} ->
      case {Map.fetch(roster, id), parse_mark(raw)} do
        {:error, _} -> {:halt, {:error, :not_in_class}}
        {{:ok, _}, :blank} -> {:cont, {:ok, acc}}
        {{:ok, e}, {:ok, value}} -> {:cont, {:ok, [{e, value} | acc]}}
        {{:ok, _}, :error} -> {:halt, {:error, {:invalid_value, id}}}
      end
    end)
  end

  defp parse_mark(%Decimal{} = d), do: bounded(d)
  defp parse_mark(n) when is_number(n), do: bounded(Decimal.new(to_string(n)))

  defp parse_mark(raw) do
    case raw |> to_string() |> String.trim() |> String.replace(",", ".") do
      "" ->
        :blank

      text ->
        case Decimal.parse(text) do
          # NaN and ±Infinity carry an atom coefficient.
          {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> bounded(d)
          _ -> :error
        end
    end
  end

  defp bounded(d) do
    if Decimal.compare(d, 0) != :lt and Decimal.compare(d, 20) != :gt, do: {:ok, d}, else: :error
  end
```

Note on the return shape: `Ash.transact/2` wraps the function's result in `{:ok, _}`; the
`Enum.reduce_while` returns `{:ok, count}`, so success arrives as `{:ok, {:ok, count}}`. A rollback arrives as
`{:error, error}`. Check with the test which shape your Ash version gives and keep only the clauses it needs.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/discipline_conduct_sheet_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/discipline.ex test/teacher_assistant/discipline_conduct_sheet_test.exs
git commit -m "feat: class conduct sheet with suggestions; save a class's conduct marks"
```

---

### Task 3: The « Conduite » page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/conduct_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route in the `:school_workspace` live session)
- Modify: `lib/teacher_assistant_web/spaces.ex` (`conduct/0` item: Surveillant « Vie scolaire »; a « Vie
  scolaire » section for the Proviseur and Censeur)
- Test: `test/teacher_assistant_web/live/school/conduct_live_test.exs`, `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Consumes: `Discipline.conduct_sheet/3`, `Discipline.set_conduct_marks/4` (Task 2);
  `Discipline.can_manage_conduct?/1`; `Enrollment.list_class_groups/2`; `Organization.list_sequences/2`;
  `Academics.EntryProgress.default_sequence/2`; `Academics.Reference.today/0`.
- Produces: route `/school/conduct` (`School.ConductLive`, params `class`, `seq`), nav id `nav-school-conduct`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.ConductLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Attendance, Curriculum, Discipline, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  # The test clock is frozen at Monday 2025-09-15.
  @today ~D[2025-09-15]

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée C"})

    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{day: :monday, period_id: p1.id, teaching_context_id: tc.id})

    {:ok, _} = Discipline.add_sanction(scope, awa, %{type: :avertissement, date: @today})
    seq = Organization.current_sequence(scope, year, @today)

    %{
      conn: Plug.Conn.put_session(conn, :workspace_id, school.id),
      school: school,
      scope: scope,
      cg: cg,
      awa: awa,
      bob: bob,
      seq: seq
    }
  end

  defp path(ctx), do: ~p"/school/conduct?class=#{ctx.cg.id}&seq=#{ctx.seq.id}"

  test "shows each student's facts and suggestion, inputs pre-filled with it", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    awa_row = view |> element("#conduct-row-#{ctx.awa.id}") |> render()
    assert awa_row =~ "Avertissement"
    assert awa_row =~ "18"
    assert has_element?(view, "#conduct-input-#{ctx.awa.id}[value='18']")
    assert has_element?(view, "#conduct-input-#{ctx.bob.id}[value='20']")
  end

  test "an edited row is marked « ajustée »; applying the suggestions resets it", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16"}}) |> render_change()
    assert view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "ajustée"

    view |> element("#apply-suggestions") |> render_click()
    refute view |> element("#conduct-row-#{ctx.awa.id}") |> render() =~ "ajustée"
    assert has_element?(view, "#conduct-input-#{ctx.awa.id}[value='18']")
  end

  test "validating the class saves every row", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view
    |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16,5", ctx.bob.id => "20"}})
    |> render_submit()

    assert render(view) =~ "2 notes de conduite enregistrées"

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)
    assert Decimal.equal?(awa_row.current, Decimal.new("16.5"))
    assert Decimal.equal?(bob_row.current, 20)
  end

  test "a bad value names the student and saves nothing", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))

    view
    |> form("#conduct-form", %{"marks" => %{ctx.awa.id => "16", ctx.bob.id => "25"}})
    |> render_submit()

    assert view |> element("#conduct-error") |> render() =~ "Bob"
    assert Enum.all?(Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq), &is_nil(&1.current))
  end

  test "tapping a row shows its deductions", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, path(ctx))
    refute has_element?(view, "#deductions-#{ctx.awa.id}")
    view |> element("#conduct-name-#{ctx.awa.id}") |> render_click()
    assert view |> element("#deductions-#{ctx.awa.id}") |> render() =~ "Avertissement"
  end

  test "a plain teacher is sent back", %{school: school, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/conduct")
  end
end
```

In `spaces_test.exs`, the Surveillant list becomes
`["nav-school-day", "nav-school-absences", "nav-school-conduct", "nav-school-classes", "nav-school-students",
"nav-school-school-life"]` (keep its multi-line formatting), and add
`assert "nav-school-conduct" in item_ids(:proviseur, facts([:head]))` and the same for the Censeur.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/conduct_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: FAIL — no route `/school/conduct`.

- [ ] **Step 3: Route and menus**

Router, after `live "/school/absences", School.AbsencesLive, :index`:

```elixir
      live "/school/conduct", School.ConductLive, :index
```

`spaces.ex`:
- Surveillant « Vie scolaire »: insert `conduct()` after `absences(facts[:unjustified_absences])`;
- Proviseur and Censeur: add a section after their first section:

```elixir
        section(gettext("Vie scolaire"), [conduct()]),
```

- helper next to `absences/1`:

```elixir
  defp conduct,
    do: item("conduct", gettext("Conduite"), "hero-hand-thumb-up", ~p"/school/conduct")
```

(Check that the Proviseur test asserting `["nav-school-dashboard", "nav-school-sequences" | _]` still holds:
the new section comes after « Pilotage », so it does.)

- [ ] **Step 4: The page**

```elixir
defmodule TeacherAssistantWeb.School.ConductLive do
  @moduledoc """
  SG → Conduite (spec KLM3, V05): for a class and a séquence, each student's
  unjustified hours, lates and sanctions, the conduct mark the school's scale
  suggests, and an input pre-filled with the current mark (else the
  suggestion). « Valider la classe » saves the class in one go.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{EntryProgress, Reference, SanctionType}
  alias TeacherAssistantWeb.Authz

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Discipline.can_manage_conduct?(scope) do
      year = scope.current_academic_year

      {:ok,
       assign(socket,
         classes: Enrollment.list_class_groups(scope, year),
         sequences: Organization.list_sequences(scope, year),
         open: nil,
         error: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La vie scolaire est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    cg = Enum.find(socket.assigns.classes, &(&1.id == params["class"])) || List.first(socket.assigns.classes)

    seq =
      Enum.find(socket.assigns.sequences, &(&1.id == params["seq"])) ||
        EntryProgress.default_sequence(socket.assigns.sequences, Reference.today())

    {:noreply, socket |> assign(cg: cg, seq: seq, open: nil, error: nil) |> load()}
  end

  defp load(%{assigns: %{cg: cg, seq: seq}} = socket) when not is_nil(cg) and not is_nil(seq) do
    rows = Discipline.conduct_sheet(socket.assigns.current_scope, cg, seq)
    values = Map.new(rows, &{&1.enrollment.id, shown(&1.current || &1.suggestion.mark)})
    assign(socket, rows: rows, values: values)
  end

  defp load(socket), do: assign(socket, rows: [], values: %{})

  def handle_event("pick", %{"class" => class, "seq" => seq}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/school/conduct?class=#{class}&seq=#{seq}")}

  def handle_event("edit", %{"marks" => marks}, socket),
    do: {:noreply, assign(socket, values: Map.merge(socket.assigns.values, marks))}

  def handle_event("apply", _params, socket) do
    values = Map.new(socket.assigns.rows, &{&1.enrollment.id, shown(&1.suggestion.mark)})
    {:noreply, assign(socket, values: values)}
  end

  def handle_event("toggle", %{"id" => id}, socket),
    do: {:noreply, assign(socket, open: if(socket.assigns.open == id, do: nil, else: id))}

  def handle_event("validate", %{"marks" => marks}, socket) do
    %{current_scope: scope, cg: cg, seq: seq} = socket.assigns

    case Discipline.set_conduct_marks(scope, cg, seq, marks) do
      {:ok, count} ->
        {:noreply,
         socket
         |> load()
         |> assign(error: nil)
         |> put_flash(
           :info,
           ngettext(
             "%{count} note de conduite enregistrée",
             "%{count} notes de conduite enregistrées",
             count
           )
         )}

      {:error, {:invalid_value, id}} ->
        name = Enum.find_value(socket.assigns.rows, &(&1.enrollment.id == id && &1.student.full_name))

        {:noreply,
         assign(socket,
           values: Map.merge(socket.assigns.values, marks),
           error: gettext("%{name} : une note entre 0 et 20.", name: name)
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Notes de conduite non enregistrées."))}
    end
  end

  defp adjusted?(row, values),
    do: Map.get(values, row.enrollment.id) not in [shown(row.suggestion.mark), nil, ""]

  defp shown(nil), do: ""

  defp shown(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp deduction_label(%{kind: :absences, count: hours}),
    do: gettext("%{hours} h non justifiées", hours: shown(Decimal.round(hours, 2)))

  defp deduction_label(%{kind: :retards, count: n}),
    do: ngettext("%{count} retard", "%{count} retards", n)

  defp deduction_label(%{kind: {:sanction, type}, count: n}), do: "#{n} × #{SanctionType.label(type)}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="conduct" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Vie scolaire")} title={gettext("Conduite")} />

        <form id="conduct-pick" phx-change="pick" class="flex flex-wrap gap-2">
          <select name="class" class="select select-sm">
            <option :for={c <- @classes} value={c.id} selected={@cg && c.id == @cg.id}>{c.label}</option>
          </select>
          <select name="seq" class="select select-sm">
            <option :for={s <- @sequences} value={s.id} selected={@seq && s.id == @seq.id}>
              {gettext("Séquence %{n}", n: s.number)}
            </option>
          </select>
        </form>

        <p :if={@rows == []} class="text-sm text-base-content/70">{gettext("Aucun élève dans cette classe.")}</p>

        <.form :if={@rows != []} for={%{}} id="conduct-form" phx-change="edit" phx-submit="validate" class="flex flex-col gap-3">
          <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Élève")}</th>
                  <th class="text-right">{gettext("h non justifiées")}</th>
                  <th class="text-right">{gettext("Retards")}</th>
                  <th>{gettext("Sanctions")}</th>
                  <th class="text-right">{gettext("Proposée")}</th>
                  <th class="text-right">{gettext("Actuelle")}</th>
                  <th class="text-right">{gettext("Note")}</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @rows do %>
                  <tr id={"conduct-row-#{row.enrollment.id}"}>
                    <td>
                      <button
                        type="button"
                        id={"conduct-name-#{row.enrollment.id}"}
                        phx-click="toggle"
                        phx-value-id={row.enrollment.id}
                        class="font-semibold hover:text-primary"
                      >
                        {row.student.full_name}
                      </button>
                    </td>
                    <td class="ta-num text-right">{shown(Decimal.round(row.unjustified_hours, 1))}</td>
                    <td class="ta-num text-right">{row.retards}</td>
                    <td>
                      <span
                        :for={s <- row.sanctions}
                        class="badge badge-sm badge-ghost mr-1"
                      >
                        {SanctionType.label(s.type)}
                      </span>
                    </td>
                    <td class="ta-num text-right font-semibold">{shown(row.suggestion.mark)}</td>
                    <td class="ta-num text-right">{shown(row.current)}</td>
                    <td class="text-right">
                      <span :if={adjusted?(row, @values)} class="badge badge-warning badge-xs mr-1">
                        {gettext("ajustée")}
                      </span>
                      <input
                        id={"conduct-input-#{row.enrollment.id}"}
                        name={"marks[#{row.enrollment.id}]"}
                        value={@values[row.enrollment.id]}
                        inputmode="decimal"
                        class="input input-xs w-16 text-right"
                      />
                    </td>
                  </tr>
                  <tr :if={@open == row.enrollment.id} id={"deductions-#{row.enrollment.id}"}>
                    <td colspan="7" class="bg-base-200/60 text-xs">
                      <span :if={row.suggestion.deductions == []}>{gettext("Aucune déduction.")}</span>
                      <span :for={d <- row.suggestion.deductions} class="mr-3">
                        {deduction_label(d)} : −{shown(d.points)}
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <p :if={@error} id="conduct-error" class="text-sm text-error">{@error}</p>

          <div class="flex flex-wrap gap-2">
            <button type="button" id="apply-suggestions" phx-click="apply" class="btn btn-ghost btn-sm">
              {gettext("Appliquer les propositions")}
            </button>
            <button type="submit" id="validate-class" class="btn btn-primary btn-sm">
              {gettext("Valider la classe")}
            </button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

Note: the suggestion « 18 » in the page test is `20 − 2` (one avertissement, no absence recorded);
`shown/1` prints `Decimal.new(18)` as `18` and `Decimal.new("17.5")` as `17,5`.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/conduct_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/conduct_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/spaces.ex test/teacher_assistant_web/live/school/conduct_live_test.exs \
  test/teacher_assistant_web/spaces_test.exs
git commit -m "feat: « Conduite » page — suggested marks, adjust and validate a class"
```

---

### Task 4: Translations, status, full checks

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/{en,fr}/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (KLM3 status line)

- [ ] **Step 1: Translations**

```bash
mix gettext.extract --merge
git diff -U0 priv/gettext/en/LC_MESSAGES/default.po | grep -E '^\+(msgid|msgstr|#, fuzzy)'
```

Fill every new English `msgstr` (« Conduite » → "Conduct", « Proposée » → "Suggested", « Actuelle » →
"Current", « ajustée » → "adjusted", « Appliquer les propositions » → "Apply the suggestions", « Valider la
classe » → "Validate the class", « %{count} notes de conduite enregistrées » → "%{count} conduct marks
saved", « %{name} : une note entre 0 et 20. » → "%{name}: a mark between 0 and 20.", …); remove every new
`#, fuzzy` flag in both locales. `grep -c "#, fuzzy"` prints 0 for both.

- [ ] **Step 2: Roadmap status**

Under `## KLM3 — Suggested conduct mark (spec)` add:

```markdown
Status: implemented 2026-10-06 (branch `klm3-conduct-suggestion`, plan
`docs/superpowers/plans/2026-10-06-klm3-conduct-suggestion.md`); no visual check done.
```

- [ ] **Step 3: Full checks**

```bash
mix ash.codegen --check
MIX_TEST_PARTITION=3 mix precommit
```

Expected: both exit 0. Stage what `precommit` reformatted.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test
git commit -m "chore: KLM3 translations and status"
```
