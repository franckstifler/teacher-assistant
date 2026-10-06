# KLM2 — Settings « Assiduité & discipline » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school-life settings page (late threshold, justification deadline, absence alert in hours, conduct
scale, sanction types in use), optional minutes on a late at roll call, and the absence screens reading those
settings.

**Architecture:** New `SchoolProfile` fields written by one `:update_school_life` action (admin or `:conduct`),
read everywhere through a pure struct `Academics.SchoolLifeRules` built by `Attendance.school_life_rules/1`.
`AttendanceEntry` gains `late_minutes`; `Conduct.totals/2` turns a long late into an absence; `SchoolLife`
computes the V04 alert in hours and a « Délai dépassé » flag. One new LiveView,
`SchoolLifeSettingsLive` (`/school/settings/school-life`).

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3.33 (attribute multitenancy, policies, embedded resources),
AshPostgres, Gettext (French msgids), Decimal.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM2 — Settings « Assiduité & discipline » (spec)".

## Global Constraints

- Worktree `.claude/worktrees/klm2`, branch `klm2-school-life-settings`, `MIX_TEST_PARTITION=3` for every
  `mix test`. Stage explicit paths only; never `git commit -a`.
- Never write migrations by hand: `mix ash.codegen --dev` while iterating, one named
  `mix ash.codegen klm2_school_life_settings` in Task 5; `mix ash.codegen --check` clean at the end. Read the
  generated migration: new columns only, no drops.
- Field values, verbatim from the spec:
  - `late_as_absence_minutes` integer 1..240, nullable (nil = a late is never an absence);
  - `justification_deadline_days` integer 1..60, nullable (nil = any time), counted in lesson days (J1);
  - `absence_alert_hours` integer 1..200, default 10;
  - `conduct_points_per_absence_hour` decimal 0..5, default 0.5;
  - `conduct_points_per_late` decimal 0..5, default 0.25;
  - `sanction_points`: consigne 1, avertissement 2, blâme 4, exclusion temporaire 6, exclusion définitive 0
    (each 0..20);
  - `sanction_types_in_use`: list of `SanctionType`, default all;
  - `AttendanceEntry.late_minutes` integer 1..240, nullable, only with `status: :late`.
- A late whose `late_minutes` **exceeds** (`>`) the threshold counts as an absence of that period's hours,
  justified or not as the entry is, and not as a late. A late without minutes stays a late.
- V04: flagged when the student's **unjustified absence hours in the current séquence** are `>=`
  `absence_alert_hours`. `SchoolLife.repeated_absence_threshold/0` is removed.
- « Délai dépassé »: an unjustified absence whose date is more than N lesson days before today (holidays and
  closed days not counted). Flag only; justifying still works.
- Settings editable by admins and `:conduct` (SG); others are sent to `/school/settings` (as `PassageLive`).
- Strings through gettext; after `mix gettext.extract --merge`, fill new `en` msgstr and clear new fuzzy flags
  in both locales (main has 0 fuzzy).
- `mix precommit` before the last commit (it reformats files; re-stage them).

## Review Focus

1. The SG saves the page with every field blank except the alert — minutes and deadline become nil (« jamais »,
   « à tout moment »), nothing else changes (test in Task 1).
2. A late changed back to « Absent » or « Présent » after minutes were typed — the stored minutes are cleared,
   never left on a non-late entry (test in Task 2).
3. A 20-minute late with a 15-minute threshold on a justified day — counted as justified absence hours, not
   unjustified and not as a late (test in Task 2).
4. An absence on the Friday before a holiday week with a 3-lesson-day deadline — the holiday days are not
   counted, so it is not yet « Délai dépassé » on the Monday after the holidays (test in Task 3).
5. A crafted `add_sanction` event with a type switched off — refused, nothing written; existing sanctions of
   that type still show (test in Task 4).

---

### Task 0: Worktree

- [ ] **Step 1: Create the worktree and check the baseline**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm2 -b klm2-school-life-settings main
cd .claude/worktrees/klm2 && mix deps.get
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/school_life_test.exs
```

Expected: 0 failures. (If the partition-3 test database is missing migrations, run
`MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate` first.)

---

### Task 1: Settings data — profile fields, rules struct, read and save

**Files:**
- Create: `lib/teacher_assistant/accounts/sanction_points.ex`
- Create: `lib/teacher_assistant/academics/school_life_rules.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes, `:update_school_life`, policy)
- Modify: `lib/teacher_assistant/attendance.ex` (`school_life_rules/1`, `update_school_life_rules/2`,
  `can_edit_school_life?/1`)
- Test: `test/teacher_assistant/academics/school_life_rules_test.exs`

**Interfaces:**
- Produces:
  - `%Academics.SchoolLifeRules{late_as_absence_minutes: integer | nil, justification_deadline_days: integer
    | nil, absence_alert_hours: integer, points_per_absence_hour: Decimal, points_per_late: Decimal,
    sanction_points: %{SanctionType.t() => Decimal}, sanction_types_in_use: [SanctionType.t()]}`;
  - `SchoolLifeRules.from_profile(profile) :: %SchoolLifeRules{}`;
  - `SchoolLifeRules.example_mark(rules) :: Decimal` — the mark for « 6 h non justifiées, 2 retards,
    1 avertissement », clamped to 0..20;
  - `Attendance.school_life_rules(scope) :: %SchoolLifeRules{}`;
  - `Attendance.update_school_life_rules(scope, params :: %{String.t() => term}) :: {:ok, profile} |
    {:error, :invalid_number | :no_sanction_type | Ash.Error.t()}`;
  - `Attendance.can_edit_school_life?(scope) :: boolean`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.SchoolLifeRulesTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.SchoolLifeRules

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    %{scope: scope}
  end

  @blank %{
    "late_as_absence_minutes" => "",
    "justification_deadline_days" => "",
    "absence_alert_hours" => "10",
    "conduct_points_per_absence_hour" => "0,5",
    "conduct_points_per_late" => "0.25",
    "sanction_points" => %{
      "consigne" => "1",
      "avertissement" => "2",
      "blame" => "4",
      "exclusion_temporaire" => "6",
      "exclusion_definitive" => "0"
    },
    "sanction_types_in_use" => ~w(consigne avertissement blame exclusion_temporaire exclusion_definitive)
  }

  test "defaults", %{scope: scope} do
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == nil
    assert rules.justification_deadline_days == nil
    assert rules.absence_alert_hours == 10
    assert Decimal.equal?(rules.points_per_absence_hour, Decimal.new("0.5"))
    assert Decimal.equal?(rules.points_per_late, Decimal.new("0.25"))
    assert Decimal.equal?(rules.sanction_points[:blame], Decimal.new(4))
    assert Decimal.equal?(rules.sanction_points[:exclusion_definitive], Decimal.new(0))
    assert Enum.sort(rules.sanction_types_in_use) == Enum.sort(TeacherAssistant.Academics.SanctionType.values())
    # 20 − 6 × 0.5 − 2 × 0.25 − 2
    assert Decimal.equal?(SchoolLifeRules.example_mark(rules), Decimal.new("14.5"))
  end

  test "the SG saves the settings; blank optional fields mean never / any time", %{scope: scope} do
    sg = member_scope_fixture(scope, %{roles: [:discipline_master]})
    assert Attendance.can_edit_school_life?(sg)

    params =
      @blank
      |> Map.merge(%{
        "late_as_absence_minutes" => "15",
        "justification_deadline_days" => "2",
        "absence_alert_hours" => "8",
        "conduct_points_per_late" => "0,5"
      })
      |> put_in(["sanction_points", "blame"], "5")
      |> Map.put("sanction_types_in_use", ~w(consigne avertissement blame))

    assert {:ok, _} = Attendance.update_school_life_rules(sg, params)
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == 15
    assert rules.justification_deadline_days == 2
    assert rules.absence_alert_hours == 8
    assert Decimal.equal?(rules.points_per_late, Decimal.new("0.5"))
    assert Decimal.equal?(rules.sanction_points[:blame], Decimal.new(5))
    # Kept in the enum's own order.
    assert rules.sanction_types_in_use == [:avertissement, :blame, :consigne]

    assert {:ok, _} = Attendance.update_school_life_rules(sg, @blank)
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == nil
    assert rules.justification_deadline_days == nil
  end

  test "bad input is refused", %{scope: scope} do
    assert {:error, :invalid_number} =
             Attendance.update_school_life_rules(scope, %{@blank | "absence_alert_hours" => "dix"})

    assert {:error, :invalid_number} =
             Attendance.update_school_life_rules(scope, %{@blank | "absence_alert_hours" => ""})

    assert {:error, :no_sanction_type} =
             Attendance.update_school_life_rules(scope, Map.delete(@blank, "sanction_types_in_use"))

    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.update_school_life_rules(scope, %{@blank | "late_as_absence_minutes" => "500"})

    assert Attendance.school_life_rules(scope).absence_alert_hours == 10
  end

  test "a plain teacher may not change them", %{scope: scope} do
    teacher = member_scope_fixture(scope, %{roles: [:teacher]})
    refute Attendance.can_edit_school_life?(teacher)
    assert_forbidden(Attendance.update_school_life_rules(teacher, @blank))
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/school_life_rules_test.exs`
Expected: FAIL — `Attendance.school_life_rules/1 is undefined`.

- [ ] **Step 3: The embedded sanction points**

```elixir
# lib/teacher_assistant/accounts/sanction_points.ex
defmodule TeacherAssistant.Accounts.SanctionPoints do
  @moduledoc """
  Spec KLM2: the conduct points a sanction of each type costs, embedded in
  `SchoolProfile.sanction_points` (nil there = these defaults).
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    for {type, default} <- [
          consigne: "1",
          avertissement: "2",
          blame: "4",
          exclusion_temporaire: "6",
          exclusion_definitive: "0"
        ] do
      attribute type, :decimal,
        allow_nil?: false,
        default: Decimal.new(default),
        public?: true,
        constraints: [min: 0, max: 20]
    end
  end
end
```

(If Spark refuses the `for` comprehension inside `attributes`, write the five `attribute` calls out by hand.)

- [ ] **Step 4: Profile fields and the action**

In `lib/teacher_assistant/accounts/school_profile.ex`, `attributes do`, after `statutory_hours`:

```elixir
    # Spec KLM2: attendance and discipline settings (« Assiduité & discipline »).
    attribute :late_as_absence_minutes, :integer, public?: true, constraints: [min: 1, max: 240]
    attribute :justification_deadline_days, :integer, public?: true, constraints: [min: 1, max: 60]

    attribute :absence_alert_hours, :integer,
      allow_nil?: false,
      default: 10,
      public?: true,
      constraints: [min: 1, max: 200]

    attribute :conduct_points_per_absence_hour, :decimal,
      allow_nil?: false,
      default: Decimal.new("0.5"),
      public?: true,
      constraints: [min: 0, max: 5]

    attribute :conduct_points_per_late, :decimal,
      allow_nil?: false,
      default: Decimal.new("0.25"),
      public?: true,
      constraints: [min: 0, max: 5]

    # nil = `SanctionPoints` defaults.
    attribute :sanction_points, TeacherAssistant.Accounts.SanctionPoints, public?: true

    # nil = every sanction type.
    attribute :sanction_types_in_use, {:array, TeacherAssistant.Academics.SanctionType},
      public?: true
```

`actions do`, after `update :update`:

```elixir
    # Spec KLM2: the SG edits these too, so not through the admin-only `:update`.
    update :update_school_life do
      accept [
        :late_as_absence_minutes,
        :justification_deadline_days,
        :absence_alert_hours,
        :conduct_points_per_absence_hour,
        :conduct_points_per_late,
        :sanction_points,
        :sanction_types_in_use
      ]
    end
```

`policies do`, after `policy action(:update)`:

```elixir
    policy action(:update_school_life) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
```

- [ ] **Step 5: The rules struct**

```elixir
# lib/teacher_assistant/academics/school_life_rules.ex
defmodule TeacherAssistant.Academics.SchoolLifeRules do
  @moduledoc """
  A school's attendance and discipline settings (spec KLM2) as a pure struct,
  built from the school profile by `TeacherAssistant.Attendance.school_life_rules/1`.
  """

  alias TeacherAssistant.Academics.SanctionType

  @default_points %{
    consigne: Decimal.new(1),
    avertissement: Decimal.new(2),
    blame: Decimal.new(4),
    exclusion_temporaire: Decimal.new(6),
    exclusion_definitive: Decimal.new(0)
  }

  defstruct late_as_absence_minutes: nil,
            justification_deadline_days: nil,
            absence_alert_hours: 10,
            points_per_absence_hour: Decimal.new("0.5"),
            points_per_late: Decimal.new("0.25"),
            sanction_points: @default_points,
            sanction_types_in_use: SanctionType.values()

  def from_profile(profile) do
    %__MODULE__{
      late_as_absence_minutes: profile.late_as_absence_minutes,
      justification_deadline_days: profile.justification_deadline_days,
      absence_alert_hours: profile.absence_alert_hours,
      points_per_absence_hour: profile.conduct_points_per_absence_hour,
      points_per_late: profile.conduct_points_per_late,
      sanction_points: points(profile.sanction_points),
      sanction_types_in_use: profile.sanction_types_in_use || SanctionType.values()
    }
  end

  defp points(nil), do: @default_points
  defp points(%{} = embedded), do: Map.new(SanctionType.values(), &{&1, Map.fetch!(embedded, &1)})

  @doc "The settings page's worked example: 6 unjustified hours, 2 lates, 1 avertissement."
  def example_mark(%__MODULE__{} = rules) do
    Decimal.new(20)
    |> Decimal.sub(Decimal.mult(6, rules.points_per_absence_hour))
    |> Decimal.sub(Decimal.mult(2, rules.points_per_late))
    |> Decimal.sub(rules.sanction_points[:avertissement])
    |> Decimal.max(0)
    |> Decimal.min(20)
  end
end
```

- [ ] **Step 6: Read and save in `Attendance`**

Add `SchoolLifeRules` and `SanctionType` to the `alias TeacherAssistant.Academics.{…}` list of
`lib/teacher_assistant/attendance.ex`, then append a section:

```elixir
  # --- School-life settings (spec KLM2) ------------------------------------------

  @doc "The school's attendance and discipline settings."
  def school_life_rules(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    SchoolLifeRules.from_profile(profile)
  end

  @doc "Whether the scope may change them (admins and the SG)."
  def can_edit_school_life?(%Scope{} = scope) do
    case TeacherAssistant.Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> Ash.can?({profile, :update_school_life}, scope)
      _ -> false
    end
  end

  @doc """
  Saves the settings from the page's string params. Blank minutes or deadline
  switch that rule off; the alert hours are required; decimals take a comma or
  a dot; at least one sanction type stays in use.
  """
  def update_school_life_rules(%Scope{} = scope, %{} = params) do
    with {:ok, late} <- parse_integer(params["late_as_absence_minutes"], :optional),
         {:ok, deadline} <- parse_integer(params["justification_deadline_days"], :optional),
         {:ok, alert} <- parse_integer(params["absence_alert_hours"], :required),
         {:ok, per_hour} <- parse_decimal(params["conduct_points_per_absence_hour"]),
         {:ok, per_late} <- parse_decimal(params["conduct_points_per_late"]),
         {:ok, points} <- parse_points(params["sanction_points"] || %{}),
         {:ok, types} <- parse_types(params["sanction_types_in_use"]),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      profile
      |> Ash.Changeset.for_update(
        :update_school_life,
        %{
          late_as_absence_minutes: late,
          justification_deadline_days: deadline,
          absence_alert_hours: alert,
          conduct_points_per_absence_hour: per_hour,
          conduct_points_per_late: per_late,
          sanction_points: points,
          sanction_types_in_use: types
        },
        scope: scope
      )
      |> Ash.update()
    end
  end

  defp parse_integer(value, mode) do
    case {String.trim(to_string(value || "")), mode} do
      {"", :optional} ->
        {:ok, nil}

      {"", :required} ->
        {:error, :invalid_number}

      {text, _} ->
        case Integer.parse(text) do
          {n, ""} -> {:ok, n}
          _ -> {:error, :invalid_number}
        end
    end
  end

  defp parse_decimal(value) do
    case value |> to_string() |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      # NaN and ±Infinity carry an atom coefficient.
      {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> {:ok, d}
      _ -> {:error, :invalid_number}
    end
  end

  defp parse_points(%{} = params) do
    Enum.reduce_while(SanctionType.values(), {:ok, %{}}, fn type, {:ok, acc} ->
      case parse_decimal(Map.get(params, Atom.to_string(type), "")) do
        {:ok, d} -> {:cont, {:ok, Map.put(acc, type, d)}}
        error -> {:halt, error}
      end
    end)
  end

  defp parse_types(values) when is_list(values) do
    by_string = Map.new(SanctionType.values(), &{Atom.to_string(&1), &1})

    case values |> Enum.map(&Map.get(by_string, &1)) |> Enum.reject(&is_nil/1) do
      [] -> {:error, :no_sanction_type}
      types -> {:ok, Enum.filter(SanctionType.values(), &(&1 in types))}
    end
  end

  defp parse_types(_), do: {:error, :no_sanction_type}
```

Note: `parse_types` keeps the enum's own order (`:avertissement, :blame, :exclusion_temporaire,
:exclusion_definitive, :consigne`).

- [ ] **Step 7: Dev migration and tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/school_life_rules_test.exs
```

Expected: the dev migration only adds seven nullable / defaulted columns to `school_profiles`; tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/accounts/sanction_points.ex lib/teacher_assistant/academics/school_life_rules.ex \
  lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/attendance.ex \
  priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/school_life_rules_test.exs
git commit -m "feat: school-life settings on the school profile"
```

---

### Task 2: Minutes on a late, and a long late counted as an absence

**Files:**
- Create: `lib/teacher_assistant/academics/attendance_entry/changes/clear_late_minutes.ex`
- Modify: `lib/teacher_assistant/academics/attendance_entry.ex` (attribute, accepts, change, roll output,
  `create_group_entries`)
- Modify: `lib/teacher_assistant/academics/conduct.ex` (`totals/2`)
- Modify: `lib/teacher_assistant/attendance.ex` (marks with minutes; `student_conduct/3`, `class_conduct/3`
  pass the threshold)
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex` (minutes state, event, input)
- Modify: `lib/teacher_assistant_web/live/school/attendance_live.ex`, `lib/teacher_assistant_web/live/school/my_day_live.ex`
  (`"minutes"` event)
- Test: `test/teacher_assistant/academics/conduct_test.exs` (add), `test/teacher_assistant/academics/attendance_late_minutes_test.exs`,
  `test/teacher_assistant_web/live/school/attendance_live_test.exs` (add)

**Interfaces:**
- Consumes: `Attendance.school_life_rules/1` (Task 1).
- Produces:
  - `AttendanceEntry.late_minutes :: integer | nil`;
  - `Conduct.totals(entries, late_as_absence_minutes \\ nil)` — entries are maps with `status`, `justified`,
    `period`, and optionally `late_minutes`;
  - `Attendance.record_period/6` and `record_combined_period/5` accept marks `{enrollment_id, status}` or
    `{enrollment_id, status, late_minutes}`;
  - `period_roll` students carry `late_minutes`;
  - `RollCall.set_minutes(roll, %{enrollment_id => String.t()}) :: roll`.

- [ ] **Step 1: Write the failing tests**

Append to `describe "totals/1"` in `conduct_test.exs` (rename the describe to `"totals/2"`):

```elixir
    test "a late beyond the threshold counts as an absence of the period's hours" do
      hour = %Period{start_time: ~T[08:00:00], end_time: ~T[09:00:00]}

      entries = [
        %{status: :late, justified: false, period: hour, late_minutes: 20},
        %{status: :late, justified: true, period: hour, late_minutes: 20},
        %{status: :late, justified: false, period: hour, late_minutes: 15},
        %{status: :late, justified: false, period: hour, late_minutes: nil}
      ]

      totals = Conduct.totals(entries, 15)
      assert Decimal.equal?(totals.unjustified_hours, Decimal.new(1))
      assert Decimal.equal?(totals.justified_hours, Decimal.new(1))
      assert totals.retards == 2

      assert Conduct.totals(entries).retards == 4
    end
```

```elixir
# test/teacher_assistant/academics/attendance_late_minutes_test.exs
defmodule TeacherAssistant.Academics.AttendanceLateMinutesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

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
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{day: :monday, period_id: p1.id, teaching_context_id: tc.id})

    %{scope: scope, cg: cg, tc: tc, e: e, p1: p1, year: year}
  end

  test "a late keeps its minutes; changing the status clears them", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    %{students: [%{status: :late, late_minutes: 20}]} =
      Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)

    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent, 20}])

    %{students: [%{status: :absent, late_minutes: nil}]} =
      Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)
  end

  test "the school's threshold turns a long late into absence hours in the totals", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    period = {:annual, ctx.year}
    assert Attendance.student_conduct(ctx.scope, ctx.e, period).retards == 1

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{late_as_absence_minutes: 15}, scope: ctx.scope)
      |> Ash.update()

    totals = Attendance.student_conduct(ctx.scope, ctx.e, period)
    assert totals.retards == 0
    assert Decimal.gt?(totals.unjustified_hours, 0)
    assert Decimal.gt?(Attendance.class_conduct(ctx.scope, ctx.cg, period)[ctx.e.id].unjustified_hours, 0)
  end
end
```

Append to `attendance_live_test.exs`:

```elixir
  test "a late can carry minutes, saved with the roll call", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, view, _} = live(conn, att_path(cg, period, date))
    refute has_element?(view, "#late-minutes-#{enrollment.id}")

    view |> element("#att-#{enrollment.id}-late") |> render_click()
    assert has_element?(view, "#late-minutes-#{enrollment.id}")

    view
    |> form("#late-minutes-form-#{enrollment.id}", %{"minutes" => %{enrollment.id => "25"}})
    |> render_change()

    view |> element("#record-roll") |> render_click()

    %{students: [%{status: :late, late_minutes: 25}]} =
      Attendance.period_roll(scope, cg, period, date)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/conduct_test.exs test/teacher_assistant/academics/attendance_late_minutes_test.exs test/teacher_assistant_web/live/school/attendance_live_test.exs`
Expected: FAIL — `Conduct.totals/2` undefined; `{id, :late, 20}` refused by `validate_marks`.

- [ ] **Step 3: The attribute and the clearing change**

```elixir
# lib/teacher_assistant/academics/attendance_entry/changes/clear_late_minutes.ex
defmodule TeacherAssistant.Academics.AttendanceEntry.Changes.ClearLateMinutes do
  @moduledoc "Spec KLM2: minutes belong to a late only; any other status clears them."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :status) == :late,
      do: changeset,
      else: Ash.Changeset.force_change_attribute(changeset, :late_minutes, nil)
  end
end
```

In `attendance_entry.ex`:
- attributes: `attribute :late_minutes, :integer, public?: true, constraints: [min: 1, max: 240]`;
- add `:late_minutes` to the default `create:` accept list and to `create :record`'s `accept`;
- add `change TeacherAssistant.Academics.AttendanceEntry.Changes.ClearLateMinutes` to `create :record` (the
  upsert writes every accepted field, so a status change rewrites `late_minutes` to nil);
- in `defp period_roll/4`, read entries into a map `enrollment_id => entry` instead of `=> status`, and add
  `late_minutes: entry && entry.late_minutes` beside `status: entry && entry.status`;
- in `defp create_group_entries/5`, match `%{enrollment_id: enrollment_id, status: status} = mark` and pass
  `late_minutes: Map.get(mark, :late_minutes)` in the `:record` params.

- [ ] **Step 4: `Conduct.totals/2`**

Replace `totals/1` in `lib/teacher_assistant/academics/conduct.ex`:

```elixir
  @doc """
  Reduces `%{status, justified, period}` entries (optionally `late_minutes`)
  into `%{justified_hours, unjustified_hours, retards}`. With
  `late_as_absence_minutes`, a late of more minutes counts as an absence of
  that period (spec KLM2); a late without minutes stays a late.
  """
  def totals(entries, late_as_absence_minutes \\ nil) do
    zero = Decimal.new(0)

    Enum.reduce(
      entries,
      %{justified_hours: zero, unjustified_hours: zero, retards: 0},
      fn entry, acc ->
        case kind(entry, late_as_absence_minutes) do
          :absent ->
            key = if entry.justified, do: :justified_hours, else: :unjustified_hours
            Map.update!(acc, key, &Decimal.add(&1, period_hours(entry.period)))

          :late ->
            Map.update!(acc, :retards, &(&1 + 1))

          :ignore ->
            acc
        end
      end
    )
  end

  defp kind(%{status: :absent}, _threshold), do: :absent

  defp kind(%{status: :late} = entry, threshold) do
    minutes = Map.get(entry, :late_minutes)

    if is_integer(threshold) and is_integer(minutes) and minutes > threshold,
      do: :absent,
      else: :late
  end

  defp kind(_entry, _threshold), do: :ignore
```

- [ ] **Step 5: Marks with minutes in `Attendance`**

- Add a normaliser and use it in `record_period/6`, `record_combined_period/5` and `validate_marks/2`:

```elixir
  # A mark is `{enrollment_id, status}` or `{enrollment_id, status, late_minutes}`.
  defp mark_parts({enrollment_id, status}), do: {enrollment_id, status, nil}
  defp mark_parts({enrollment_id, status, minutes}), do: {enrollment_id, status, minutes}
```

  - `validate_marks/2`: `Enum.reduce_while(marks, :ok, fn mark, :ok -> {enrollment_id, status, _} = mark_parts(mark); …`
  - `record_period/6`: `Enum.map(marks, fn mark -> {enrollment_id, status, minutes} = mark_parts(mark); …` and add
    `late_minutes: minutes` to the `:record` params;
  - `record_combined_period/5`: filter with `fn mark -> {enrollment_id, _, _} = mark_parts(mark); …`; in
    `run_record_combined_period/5` build `%{enrollment_id: id, status: status, late_minutes: minutes}`.
- `student_conduct/3` and `class_conduct/3`: read `threshold = school_life_rules(scope).late_as_absence_minutes`
  once, map entries with `late_minutes: &1.late_minutes` and call `Conduct.totals(entries, threshold)`.
- Update the `@doc` of `record_period/6` and `record_combined_period/5` to name the three-element mark.

- [ ] **Step 6: Roll call minutes**

In `roll_call.ex`:
- `put_students/3`: keep `minutes: Map.new(students, &{&1.enrollment_id, Map.get(&1, :late_minutes)})`;
- `set/3`: when the new status is not `:late`, also `put_in(roll, [:minutes, enrollment_id], nil)`;
- new public function:

```elixir
  @doc "Sets late minutes from the row inputs (`%{enrollment_id => \"25\"}`); blanks and bad values clear them."
  def set_minutes(roll, %{} = params) do
    Enum.reduce(params, roll, fn {enrollment_id, value}, roll ->
      if Map.has_key?(roll.marks, enrollment_id) do
        put_in(roll, [:minutes, enrollment_id], parse_minutes(value))
      else
        roll
      end
    end)
  end

  defp parse_minutes(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {n, ""} when n in 1..240 -> n
      _ -> nil
    end
  end
```

- `record/2`: build marks as
  `{id, status, if(status == :late, do: roll.minutes[id])}` with
  `status = Map.fetch!(roll.marks, id)`;
- in `roster/1`, after the status buttons `div`, when the row is late:

```heex
        <form
          :if={@roll.marks[student.enrollment_id] == :late}
          id={"late-minutes-form-#{student.enrollment_id}"}
          phx-change="minutes"
          class="flex items-center gap-1"
        >
          <input
            id={"late-minutes-#{student.enrollment_id}"}
            type="number"
            min="1"
            max="240"
            inputmode="numeric"
            name={"minutes[#{student.enrollment_id}]"}
            value={@roll.minutes[student.enrollment_id]}
            placeholder={gettext("min")}
            aria-label={gettext("Minutes de retard")}
            class="input input-xs w-16 text-right"
          />
          <span class="text-[0.72rem] text-base-content/70">{gettext("min")}</span>
        </form>
```

In both `attendance_live.ex` and `my_day_live.ex`, beside `handle_event("set", …)`:

```elixir
  def handle_event("minutes", %{"minutes" => minutes}, socket),
    do: {:noreply, update(socket, :roll, &(&1 && RollCall.set_minutes(&1, minutes)))}
```

- [ ] **Step 7: Run the tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/conduct_test.exs test/teacher_assistant/academics/attendance_late_minutes_test.exs test/teacher_assistant_web/live/school/attendance_live_test.exs test/teacher_assistant_web/live/school/attendance_combined_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant/academics/attendance_test.exs test/teacher_assistant/academics/attendance_entry_test.exs
```

Expected: the dev migration adds `attendance_entries.late_minutes`; all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/academics/attendance_entry.ex lib/teacher_assistant/academics/attendance_entry \
  lib/teacher_assistant/academics/conduct.ex lib/teacher_assistant/attendance.ex \
  lib/teacher_assistant_web/live/school/roll_call.ex lib/teacher_assistant_web/live/school/attendance_live.ex \
  lib/teacher_assistant_web/live/school/my_day_live.ex priv/repo/migrations priv/resource_snapshots \
  test/teacher_assistant/academics/conduct_test.exs test/teacher_assistant/academics/attendance_late_minutes_test.exs \
  test/teacher_assistant_web/live/school/attendance_live_test.exs
git commit -m "feat: minutes on a late; a long late counts as an absence"
```

---

### Task 3: Alert in hours and « Délai dépassé »

**Files:**
- Modify: `lib/teacher_assistant/academics/school_life.ex` (`absence_days/4`, hours, `overdue?/4`)
- Modify: `lib/teacher_assistant_web/live/school/absences_live.ex` (hours label, overdue tag)
- Modify: `lib/teacher_assistant_web/live/school/school_life_components.ex` (`overdue_badge/1`)
- Test: `test/teacher_assistant/academics/school_life_test.exs` (update V04 test, add two),
  `test/teacher_assistant_web/live/school/school_life_live_test.exs` (add)

**Interfaces:**
- Consumes: `Attendance.school_life_rules/1`, `Conduct.totals/2` (Tasks 1–2); `Attendance.school_calendar/1`,
  `SchoolCalendar.lesson_day?/2` (J1).
- Produces: `absence_days` rows gain `unjustified_hours :: Decimal` and `overdue? :: boolean` and lose
  `unjustified_days`; `SchoolLife.overdue?(date, today, deadline_days | nil, calendar) :: boolean`.

- [ ] **Step 1: Write the failing tests**

In `school_life_test.exs`, replace the test « absence days carry the reason and the repeated-absence flag »:

```elixir
  test "absence rows carry the reason, the séquence's unjustified hours and the alert", ctx do
    days = [~D[2025-09-15], ~D[2025-09-22], ~D[2025-09-29]]

    for d <- days,
        do:
          {:ok, _} =
            Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, d, [{ctx.e.id, :absent}])

    today = ~D[2025-09-30]

    # 3 × 50 min = 2.5 h, under the default 10 h alert.
    assert [%{flagged?: false, justified?: false, unjustified_hours: hours} | _] =
             Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert Decimal.equal?(hours, Decimal.new("2.5"))

    set_school_life(ctx.scope, %{absence_alert_hours: 2})
    assert [%{flagged?: true} | _] = Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert {:error, :invalid_reason} = Attendance.justify_day(ctx.scope, ctx.e, @monday, nil)
    assert {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, @monday, :maladie)

    rows = Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert %{justified?: true, reason: :maladie, flagged?: false} =
             Enum.find(rows, &(&1.date == @monday))
  end

  test "an unjustified absence is late for justification after N lesson days", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent}])

    row = fn today ->
      ctx.scope |> Attendance.absence_days(~D[2025-09-08], today, today) |> hd()
    end

    refute row.(~D[2025-09-25]).overdue?

    set_school_life(ctx.scope, %{justification_deadline_days: 2})
    refute row.(~D[2025-09-17]).overdue?
    assert row.(~D[2025-09-18]).overdue?

    {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, @monday, :famille)
    refute row.(~D[2025-09-18]).overdue?
  end

  test "overdue?/4 skips holidays and days without lessons" do
    alias TeacherAssistant.Academics.{SchoolCalendar, SchoolLife}

    cal =
      SchoolCalendar.new(nil, false, [
        %{label: "Congé", start_date: ~D[2025-10-27], end_date: ~D[2025-10-31]}
      ])

    # Friday 24 Oct, deadline 3. Lessons run Monday–Saturday by default; the
    # holiday week and the Sundays don't count: 25 Oct, 1 Nov, 3 Nov = 3 days.
    refute SchoolLife.overdue?(~D[2025-10-24], ~D[2025-11-03], 3, cal)
    assert SchoolLife.overdue?(~D[2025-10-24], ~D[2025-11-04], 3, cal)
    refute SchoolLife.overdue?(~D[2025-10-24], ~D[2026-01-01], nil, cal)
  end

  defp set_school_life(scope, attrs) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, attrs, scope: scope)
      |> Ash.update()
  end
```


Add to `school_life_live_test.exs` (its setup records Awa absent at lesson 1 on the frozen today, Monday
2025-09-15, and binds `scope`, `cg`, `e`, `p1`):

```elixir
  test "Absences shows the séquence's hours and « Délai dépassé »", %{conn: conn} = ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{justification_deadline_days: 1},
        scope: ctx.scope
      )
      |> Ash.update()

    # Thursday 11 Sept: Fri 12, Sat 13 and Mon 15 are 3 lesson days later.
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, nil, ~D[2025-09-11], [{ctx.e.id, :absent}])

    {:ok, view, _} = live(conn, ~p"/school/absences")
    assert view |> element("#row-#{ctx.e.id}-2025-09-11") |> render() =~ "Délai dépassé"
    refute view |> element("#row-#{ctx.e.id}-2025-09-15") |> render() =~ "Délai dépassé"

    view |> element("#row-#{ctx.e.id}-2025-09-15") |> render_click()
    assert view |> element("#unjustified-hours") |> render() =~ " h"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/school_life_test.exs`
Expected: FAIL — rows have no `unjustified_hours` / `overdue?`; `SchoolLife.overdue?/4` undefined.

- [ ] **Step 3: `SchoolLife`**

In `lib/teacher_assistant/academics/school_life.ex`:
- remove `repeated_absence_threshold/0` and its `@doc`;
- add `Conduct` to the academics alias list;
- in `absence_days/4`:

```elixir
  def absence_days(%Scope{} = scope, %Date{} = first, %Date{} = last, %Date{} = today) do
    rules = Attendance.school_life_rules(scope)
    calendar = Attendance.school_calendar(scope)
    alert = Decimal.new(rules.absence_alert_hours)
    unjustified = unjustified_hours(scope, today, rules)
    zero = Decimal.new(0)
    # … existing query and grouping unchanged …
      hours = Map.get(unjustified, enrollment_id, zero)
      justified? = Enum.all?(entries, & &1.justified)
      %{
        # … existing keys, minus unjustified_days …
        justified?: justified?,
        unjustified_hours: hours,
        flagged?: Decimal.compare(hours, alert) != :lt,
        overdue?:
          not justified? and overdue?(date, today, rules.justification_deadline_days, calendar)
      }
```

- replace `unjustified_days/2` with:

```elixir
  # enrollment_id => unjustified absence hours in the current séquence (a long
  # late counts, spec KLM2).
  defp unjustified_hours(scope, today, rules) do
    case current_sequence_range(scope, today) do
      nil ->
        %{}

      {first, last} ->
        AttendanceEntry
        |> Ash.Query.filter(
          status in [:absent, :late] and justified == false and date >= ^first and date <= ^last
        )
        |> Ash.Query.load(:period)
        |> Ash.read!(scope: scope)
        |> Enum.group_by(& &1.enrollment_id)
        |> Map.new(fn {id, entries} ->
          {id, Conduct.totals(entries, rules.late_as_absence_minutes).unjustified_hours}
        end)
    end
  end

  @doc """
  Whether an absence on `date` is past the justification deadline on `today`:
  more than `deadline` lesson days (holidays and days without lessons skipped)
  since it. A nil deadline means any time.
  """
  def overdue?(_date, _today, nil, _calendar), do: false

  def overdue?(%Date{} = date, %Date{} = today, deadline, %SchoolCalendar{} = calendar) do
    Date.compare(today, date) == :gt and
      date
      |> Date.add(1)
      |> Date.range(today)
      |> Enum.count(&SchoolCalendar.lesson_day?(calendar, &1)) > deadline
  end
```

(`Conduct.totals/2` reads `status`, `justified`, `period` and `late_minutes` straight off the
`AttendanceEntry` structs.)

- [ ] **Step 4: The screens**

`school_life_components.ex`, after `repeated_badge/1`:

```elixir
  attr :row, :map, required: true

  def overdue_badge(assigns) do
    ~H"""
    <span
      :if={@row.overdue?}
      class="ta-num rounded-full bg-warning/20 px-1.5 py-px text-[0.62rem] font-semibold text-warning"
    >
      {gettext("Délai dépassé")}
    </span>
    """
  end
```

`absences_live.ex`:
- in the row's status cell, after the « Non justifiée » text, `<.overdue_badge row={row} />`;
- in the panel, after `<.absence_status row={@selected} />`, `<.overdue_badge row={@selected} />`;
- replace the `#unjustified-days` span with

```heex
              <span id="unjustified-hours" class="ta-num font-semibold">
                {hours_label(@selected.unjustified_hours)}
              </span>
```

  and add

```elixir
  defp hours_label(%Decimal{} = hours),
    do: "#{hours |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)} h"
```

  The label beside it becomes `gettext("Absences non justifiées (séquence)")`.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant_web/live/school/day_live_test.exs`
Expected: PASS (ignore a missing `day_live_test.exs`; the day view is covered by `school_life_live_test.exs`).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/school_life.ex lib/teacher_assistant_web/live/school/absences_live.ex \
  lib/teacher_assistant_web/live/school/school_life_components.ex \
  test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs
git commit -m "feat: absence alert in hours and justification deadline flag"
```

---

### Task 4: The settings page and sanction types in use

**Files:**
- Create: `lib/teacher_assistant_web/live/school/school_life_settings_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route, `:school_workspace` live session)
- Modify: `lib/teacher_assistant_web/spaces.ex` (`school_life_settings/0` item)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (link `#school-life-link` after
  `#passage-link`)
- Modify: `lib/teacher_assistant_web/live/school/discipline_live.ex` (types in use)
- Test: `test/teacher_assistant_web/live/school/school_life_settings_live_test.exs`,
  `test/teacher_assistant_web/live/school/discipline_live_test.exs` (add), `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Consumes: Task 1 functions (`school_life_rules/1`, `update_school_life_rules/2`, `can_edit_school_life?/1`,
  `SchoolLifeRules.example_mark/1`).
- Produces: route `/school/settings/school-life` (`School.SchoolLifeSettingsLive`), nav id
  `nav-school-school-life`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.SchoolLifeSettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  defp conn_for(workspace, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, workspace.id)
  end

  test "settings links to the page, which shows the defaults and the example", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#school-life-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")
    assert has_element?(view, "#school-life-form input[name='school_life[absence_alert_hours]'][value='10']")
    assert has_element?(view, "#school-life-form input[name='school_life[late_as_absence_minutes]'][value='']")
    assert view |> element("#conduct-example") |> render() =~ "14,5"
  end

  test "the SG saves; the example follows the form", %{workspace: ws, scope: scope} do
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    {:ok, view, _} = live(conn_for(ws, sg.current_user), ~p"/school/settings/school-life")

    view
    |> form("#school-life-form", %{school_life: %{conduct_points_per_absence_hour: "1"}})
    |> render_change()

    # 20 − 6 − 0.5 − 2
    assert view |> element("#conduct-example") |> render() =~ "11,5"

    view
    |> form("#school-life-form", %{school_life: %{late_as_absence_minutes: "15", absence_alert_hours: "8"}})
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    assert Attendance.school_life_rules(scope).late_as_absence_minutes == 15
    assert Attendance.school_life_rules(scope).absence_alert_hours == 8
  end

  test "an unchecked type is saved as not in use; none checked is refused", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/school-life")

    view
    |> form("#school-life-form", %{school_life: %{sanction_types_in_use: ["avertissement", "blame"]}})
    |> render_submit()

    assert Enum.sort(Attendance.school_life_rules(scope).sanction_types_in_use) == [:avertissement, :blame]

    view
    |> form("#school-life-form", %{school_life: %{sanction_types_in_use: []}})
    |> render_submit()

    assert has_element?(view, "#school-life-error")
  end

  test "a plain teacher is sent back to settings", %{workspace: ws, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn_for(ws, teacher.current_user), ~p"/school/settings/school-life")
  end
end
```

(The checkbox group posts `school_life[sanction_types_in_use][]`; with all boxes unchecked, a hidden input
`school_life[sanction_types_in_use][]` with value `""` keeps the key present so the save sees an empty list —
`parse_types/1` drops the blank and returns `:no_sanction_type`. If `form/3` refuses the empty list in the test,
submit `%{school_life: %{sanction_types_in_use: [""]}}` instead.)

Add to `discipline_live_test.exs`:

```elixir
  test "a type not in use is not offered and a crafted one is refused", %{
    conn: conn,
    cg: cg,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, _} =
      TeacherAssistant.Discipline.add_sanction(scope, enrollment, %{type: :consigne, date: ~D[2025-09-10]})

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{sanction_types_in_use: [:avertissement, :blame]},
        scope: scope
      )
      |> Ash.update()

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/discipline")
    refute has_element?(view, "#discipline-type-select option[value='consigne']")
    assert has_element?(view, "#discipline-type-select option[value='blame']")

    # The existing consigne still shows in the log.
    assert render(view) =~ "Consigne"

    before = length(TeacherAssistant.Discipline.list_sanctions(scope, enrollment, {:annual, scope.current_academic_year}))

    render_submit(view, "add_sanction", %{
      "enrollment_id" => enrollment.id,
      "type" => "consigne",
      "date" => "2025-09-12"
    })

    assert length(TeacherAssistant.Discipline.list_sanctions(scope, enrollment, {:annual, scope.current_academic_year})) == before
  end
```

(Use the period tuple and setup names `discipline_live_test.exs` already uses — read its first 60 lines; the
existing « a conduct manager adds a sanction » test shows the exact `add_sanction` params, copy them and change
the type.)

In `spaces_test.exs`, the Surveillant list becomes
`["nav-school-day", "nav-school-absences", "nav-school-classes", "nav-school-students", "nav-school-school-life"]`,
and add `assert "nav-school-school-life" in item_ids(:proviseur, facts([:head]))` and the same for the Censeur.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/school_life_settings_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: FAIL — no route `/school/settings/school-life`.

- [ ] **Step 3: Route, menu, settings link**

Router, after `live "/school/settings/passage", …`:

```elixir
      live "/school/settings/school-life", School.SchoolLifeSettingsLive, :index
```

`spaces.ex`: add `school_life_settings()` after `passage()` in the Proviseur and Censeur « Paramètres »
sections and after `students()` in the Surveillant « Vie scolaire » section; helper next to `passage/0`:

```elixir
  defp school_life_settings,
    do:
      item(
        "school-life",
        gettext("Assiduité & discipline"),
        "hero-scale",
        ~p"/school/settings/school-life"
      )
```

`settings_live.ex`, after the `#passage-link` link:

```heex
          <.link
            id="school-life-link"
            navigate={~p"/school/settings/school-life"}
            class="link link-primary text-sm"
          >
            {gettext("Assiduité & discipline")}
          </.link>
```

- [ ] **Step 4: The page**

```elixir
defmodule TeacherAssistantWeb.School.SchoolLifeSettingsLive do
  @moduledoc """
  Settings → Assiduité & discipline (spec KLM2, mockup `Paramètres école` → Vie
  scolaire): when a late counts as an absence, the justification deadline, the
  absence alert, the conduct scale with a live worked example, and the sanction
  types in use. Admins and the SG.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.{SanctionType, SchoolLifeRules}
  alias TeacherAssistantWeb.Authz

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Attendance.can_edit_school_life?(scope) do
      rules = Attendance.school_life_rules(scope)
      {:ok, assign(socket, rules: rules, example: SchoolLifeRules.example_mark(rules), error: nil)}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def handle_event("preview", %{"school_life" => params}, socket) do
    {:noreply, assign(socket, example: preview(socket.assigns.rules, params))}
  end

  def handle_event("save", %{"school_life" => params}, socket) do
    scope = socket.assigns.current_scope

    case Attendance.update_school_life_rules(scope, params) do
      {:ok, _} ->
        rules = Attendance.school_life_rules(scope)

        {:noreply,
         socket
         |> assign(rules: rules, example: SchoolLifeRules.example_mark(rules), error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_number} ->
        {:noreply, assign(socket, error: gettext("Utilisez des nombres, par exemple 0,5."))}

      {:error, :no_sanction_type} ->
        {:noreply, assign(socket, error: gettext("Gardez au moins un type de sanction."))}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
        {:noreply, assign(socket, error: message)}

      {:error, _} ->
        {:noreply, assign(socket, error: gettext("Réglage non enregistré."))}
    end
  end

  # The example recomputed from what is typed; unreadable values keep the saved ones.
  defp preview(rules, params) do
    number = fn key, saved ->
      case params |> Map.get(key, "") |> to_string() |> String.replace(",", ".") |> Decimal.parse() do
        {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> d
        _ -> saved
      end
    end

    points = Map.get(params, "sanction_points", %{})

    SchoolLifeRules.example_mark(%{
      rules
      | points_per_absence_hour: number.("conduct_points_per_absence_hour", rules.points_per_absence_hour),
        points_per_late: number.("conduct_points_per_late", rules.points_per_late),
        sanction_points:
          Map.update!(rules.sanction_points, :avertissement, fn saved ->
            case points |> Map.get("avertissement", "") |> to_string() |> String.replace(",", ".") |> Decimal.parse() do
              {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> d
              _ -> saved
            end
          end)
    })
  end

  defp shown(nil), do: ""
  defp shown(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")
  defp shown(n) when is_integer(n), do: Integer.to_string(n)

  def render(assigns) do
    assigns = assign(assigns, types: SanctionType.values())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-life-settings" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Assiduité & discipline")} />

        <.form
          for={%{}}
          as={:school_life}
          id="school-life-form"
          phx-change="preview"
          phx-submit="save"
          class="space-y-6"
        >
          <fieldset class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Retards et absences")}</legend>
            <.input
              name="school_life[late_as_absence_minutes]"
              value={shown(@rules.late_as_absence_minutes)}
              label={gettext("Un retard compte comme une absence au-delà de (minutes)")}
              placeholder={gettext("jamais")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="school_life[justification_deadline_days]"
              value={shown(@rules.justification_deadline_days)}
              label={gettext("Délai de justification (jours de cours)")}
              placeholder={gettext("à tout moment")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
            <.input
              name="school_life[absence_alert_hours]"
              value={shown(@rules.absence_alert_hours)}
              label={gettext("Alerte après (heures d'absence non justifiée dans la séquence)")}
              inputmode="numeric"
              class="input input-sm w-24 text-right"
            />
          </fieldset>

          <fieldset class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Barème de conduite")}</legend>
            <p class="text-xs text-base-content/60">
              {gettext("Chaque élève part de 20/20 par séquence ; chaque fait retire des points.")}
            </p>
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                name="school_life[conduct_points_per_absence_hour]"
                value={shown(@rules.points_per_absence_hour)}
                label={gettext("Par heure d'absence non justifiée")}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
              <.input
                name="school_life[conduct_points_per_late]"
                value={shown(@rules.points_per_late)}
                label={gettext("Par retard")}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
              <.input
                :for={t <- @types}
                name={"school_life[sanction_points][#{t}]"}
                value={shown(@rules.sanction_points[t])}
                label={SanctionType.label(t)}
                inputmode="decimal"
                class="input input-sm w-24 text-right"
              />
            </div>
            <p id="conduct-example" class="rounded-box bg-base-200 px-3 py-2 text-sm">
              {gettext("Exemple : 6 h non justifiées, 2 retards, 1 avertissement → %{mark}/20",
                mark: shown(@example)
              )}
            </p>
          </fieldset>

          <fieldset class="space-y-2 rounded-box border border-base-300 bg-base-100 p-4">
            <legend class="ta-eyebrow px-1">{gettext("Sanctions utilisées")}</legend>
            <input type="hidden" name="school_life[sanction_types_in_use][]" value="" />
            <label :for={t <- @types} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-primary"
                name="school_life[sanction_types_in_use][]"
                value={t}
                checked={t in @rules.sanction_types_in_use}
              />
              {SanctionType.label(t)}
            </label>
          </fieldset>

          <p :if={@error} id="school-life-error" class="text-sm text-error">{@error}</p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

Note: `example_mark/1` takes the struct; `preview/2` updates the struct with `%{rules | …}` so it stays a
`%SchoolLifeRules{}`.

- [ ] **Step 5: Sanction types in use on the class discipline page**

In `discipline_live.ex`:
- remove `@sanction_types` and `@type_strings`;
- in `mount`, `sanction_types: Attendance.school_life_rules(scope).sanction_types_in_use` (alias
  `TeacherAssistant.Attendance`);
- in `handle_event("add_sanction", …)`, map the type string only against `socket.assigns.sanction_types`:

```elixir
    type = Enum.find(socket.assigns.sanction_types, &(Atom.to_string(&1) == params["type"]))
```

  and treat `nil` like today's unknown type (no write, error flash
  `gettext("Ce type de sanction n'est pas utilisé.")`).

- [ ] **Step 6: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/school_life_settings_live_test.exs test/teacher_assistant_web/live/school/discipline_live_test.exs test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/school_life_settings_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school/settings_live.ex \
  lib/teacher_assistant_web/live/school/discipline_live.ex \
  test/teacher_assistant_web/live/school/school_life_settings_live_test.exs \
  test/teacher_assistant_web/live/school/discipline_live_test.exs test/teacher_assistant_web/spaces_test.exs
git commit -m "feat: « Assiduité & discipline » settings page; sanction types in use"
```

---

### Task 5: Named migration, translations, status, full checks

**Files:**
- Modify: `priv/repo/migrations/*`, `priv/resource_snapshots/*`
- Modify: `priv/gettext/default.pot`, `priv/gettext/{en,fr}/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (KLM2 status line)

- [ ] **Step 1: Named migration**

```bash
mix ash.codegen klm2_school_life_settings
MIX_TEST_PARTITION=3 MIX_ENV=test mix ecto.drop && MIX_TEST_PARTITION=3 MIX_ENV=test mix ecto.create
MIX_TEST_PARTITION=3 MIX_ENV=test mix ash.migrate
mix ash.codegen --check
```

Expected: one `*_klm2_school_life_settings.exs` replaces the dev migrations; it adds the seven
`school_profiles` columns and `attendance_entries.late_minutes`, nothing else; `--check` exits 0.

- [ ] **Step 2: Translations**

```bash
mix gettext.extract --merge
git diff -U0 priv/gettext/en/LC_MESSAGES/default.po | grep -E '^\+(msgid|msgstr|#, fuzzy)'
```

Fill every new English `msgstr` (« Assiduité & discipline » → "Attendance & discipline", « Délai dépassé » →
"Deadline passed", « Retards et absences » → "Lates and absences", « Barème de conduite » → "Conduct scale",
« Sanctions utilisées » → "Sanctions in use", « jamais » → "never", « à tout moment » → "any time", « min » →
"min", « Minutes de retard » → "Minutes late", …); remove every new `#, fuzzy` flag in both locales (French
`msgstr` stay empty). `grep -c "#, fuzzy"` must print 0 for both files.

- [ ] **Step 3: Roadmap status**

Under `## KLM2 — Settings « Assiduité & discipline » (spec)` add:

```markdown
Status: implemented 2026-10-06 (branch `klm2-school-life-settings`, plan
`docs/superpowers/plans/2026-10-06-klm2-school-life-settings.md`); no visual check done.
```

- [ ] **Step 4: Full checks**

```bash
MIX_TEST_PARTITION=3 mix precommit
```

Expected: exit 0, all tests pass. Stage what `precommit` reformatted.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations priv/resource_snapshots priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test
git commit -m "chore: KLM2 migration, translations and status"
```
