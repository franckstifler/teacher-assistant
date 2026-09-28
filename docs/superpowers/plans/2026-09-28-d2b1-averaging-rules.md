# D2b-1 — Averaging rules (trimester/annual rule, rounding, tied ranks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school chooses its trimester rule, annual rule, rounding and tied-rank behaviour on an "Évaluations & moyennes" page. Every average, rank and statistic on bulletins and the teacher's marks summary follows those rules.

**Architecture:** Four `SchoolProfile` fields become a pure `GradingRules` struct (`Assessment.grading_rules/1`). `GradingRules` owns the rounding, weighted period means and ranking. `Marks` and `Bulletins` take it as an optional last argument whose default reproduces today's unrounded, shared-rank behaviour. `Assessment.period_result/4` computes trimester and annual subject averages through it. A small LiveView saves the settings.

**Tech Stack:** Elixir 1.20, Ash 3.33 / AshPostgres 2.13, Phoenix LiveView 1.x, daisyUI, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` § D2b-1

## Plan rulings

- **The struct default is `rounding: :none`,** an internal value that is never stored. Pure `Marks`/`Bulletins` callers that pass no rules, and their existing tests, keep today's exact figures. The stored default, `:hundredth`, applies to every real computation through `Assessment.grading_rules/1`.
- **One ranking function** (`GradingRules.ranks/2`) replaces the two duplicate `rank_map`/`assign_ranks` implementations in `Bulletins` and `Marks`.
- **Students passed to `Marks`/`Bulletins` carry an optional `:name`**, used for the tie-break. Missing means `""`.

## Global Constraints

- Migrations: iterate with `mix ash.codegen --dev`, then finish with `mix ash.codegen averaging_rules` (Task 6). `mix ash.codegen --check` must be clean. No real data exists, so reset dev and test databases with `mix ash.reset && MIX_ENV=test mix ash.reset`. If the named codegen appears to hang, run it again with `printf 'n\n' |` piped in (it can prompt).
- Rounding is half-up. `:quarter` means the nearest 0.25. Display stays at 2 decimals.
- Defaults: trimester `:mean_of_sequences`, annual `:mean_of_sequences` (ministerial rule), rounding `:hundredth`, `shared_ranks?` true.
- Never `String.to_atom` on input. Map strings against each enum's `values/0`.
- UI copy is French gettext msgids. Every new msgid gets an English msgstr in `priv/gettext/en/LC_MESSAGES/default.po`, after `mix gettext.extract --merge`. Un-fuzzy any fuzzy entry that matches a new msgid.
- LiveView templates start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`. No inline `<script>`.
- Run only each task's own test files. `mix precommit` runs once, in Task 6, plus `mix compile --warnings-as-errors`.
- Existing tests that compute bulletins through `Assessment` now see averages rounded to 2 decimals. If one asserts an unrounded repeating decimal, update the expectation to the rounded value. Don't change the code.

## Review Focus

1. **A crafted `set_rule` event with an unknown field or value.** It's refused, nothing is written, and there's no crash. Tested in Task 2 (domain) and Task 5 (page).
2. **The ×2 trimester rule with S1 unmarked.** The trimester equals S2 exactly, not 2·S2 ÷ 3. Tested in Task 4.
3. **The trimesters annual rule with a whole trimester unmarked.** The annual average is the mean of the other two trimesters. Tested in Task 4.
4. **Two students tied only after rounding, with shared ranks off.** The unrounded average decides; a true tie falls back to name. Tested in Task 1 and Task 3.
5. **Quarter rounding at the half:** 13.125 → 13.25, 13.12 → 13.00, 13.375 → 13.50. Tested in Task 1.

---

### Task 1: `GradingRules`: rounding, period means, ranking

**Files:**
- Create: `lib/teacher_assistant/academics/grading_rules.ex`
- Test: `test/teacher_assistant/academics/grading_rules_test.exs`

**Interfaces:**
- Produces:
  - `%GradingRules{trimester: :mean_of_sequences | :second_sequence_double, annual: :mean_of_sequences | :mean_of_trimesters, rounding: :none | :hundredth | :tenth | :quarter, shared_ranks?: boolean}`. The defaults are `:mean_of_sequences`, `:mean_of_sequences`, `:none`, `true`.
  - `round_average(Decimal.t() | nil, rules) :: Decimal.t() | nil`
  - `trimester_average([{position_in_term, Decimal.t() | nil}], rules) :: Decimal.t() | nil` (rounded)
  - `annual_average([{term_position, [{position_in_term, Decimal.t() | nil}]}], rules) :: Decimal.t() | nil` (rounded)
  - `ranks([%{id, average: Decimal.t() | nil, precise: Decimal.t() | nil, name: String.t()}], rules) :: %{id => pos_integer}`. Entries with a nil `average` get no rank.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.GradingRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.GradingRules

  defp d(x), do: Decimal.new(x)
  defp rules(attrs), do: struct(GradingRules, attrs)

  test "rounding modes are half-up; :none leaves the value untouched" do
    assert GradingRules.round_average(d("13.125"), rules(rounding: :hundredth)) == d("13.13")
    assert GradingRules.round_average(d("13.25"), rules(rounding: :tenth)) == d("13.3")
    assert Decimal.equal?(GradingRules.round_average(d("13.125"), rules(rounding: :quarter)), d("13.25"))
    assert Decimal.equal?(GradingRules.round_average(d("13.12"), rules(rounding: :quarter)), d("13"))
    assert Decimal.equal?(GradingRules.round_average(d("13.375"), rules(rounding: :quarter)), d("13.5"))
    assert GradingRules.round_average(d("13.1234"), %GradingRules{}) == d("13.1234")
    assert GradingRules.round_average(nil, rules(rounding: :tenth)) == nil
  end

  test "trimester: plain mean, or the second séquence counted twice" do
    plain = rules(rounding: :hundredth)
    double = rules(trimester: :second_sequence_double, rounding: :hundredth)
    assert Decimal.equal?(GradingRules.trimester_average([{1, d(12)}, {2, d(15)}], plain), d("13.5"))
    assert Decimal.equal?(GradingRules.trimester_average([{1, d(12)}, {2, d(15)}], double), d(14))
  end

  test "a missing séquence is skipped with its weight" do
    double = rules(trimester: :second_sequence_double)
    assert Decimal.equal?(GradingRules.trimester_average([{1, nil}, {2, d(15)}], double), d(15))
    assert Decimal.equal?(GradingRules.trimester_average([{1, d(12)}, {2, nil}], double), d(12))
    assert GradingRules.trimester_average([{1, nil}, {2, nil}], double) == nil
  end

  test "annual: mean of the séquences, or mean of the trimesters; missing ones skipped" do
    terms = [
      {1, [{1, d(10)}, {2, nil}]},
      {2, [{1, d(14)}, {2, d(16)}]},
      {3, [{1, nil}, {2, nil}]}
    ]

    # séquences: (10 + 14 + 16) / 3 = 13.333… → 13.33
    assert Decimal.equal?(GradingRules.annual_average(terms, rules(rounding: :hundredth)), d("13.33"))

    # trimesters: T1 = 10, T2 = 15, T3 absent → 12.5
    by_terms = rules(annual: :mean_of_trimesters, rounding: :hundredth)
    assert Decimal.equal?(GradingRules.annual_average(terms, by_terms), d("12.5"))
  end

  test "shared ranks: equal averages share a rank" do
    entries = [
      %{id: "a", average: d(15), precise: d("15.004"), name: "Zoé"},
      %{id: "b", average: d(15), precise: d("14.996"), name: "Awa"},
      %{id: "c", average: d(12), precise: d(12), name: "Bob"},
      %{id: "x", average: nil, precise: nil, name: "Nul"}
    ]

    assert GradingRules.ranks(entries, %GradingRules{}) == %{"a" => 1, "b" => 1, "c" => 3}
  end

  test "without shared ranks, the unrounded average then the name break ties" do
    entries = [
      %{id: "a", average: d(15), precise: d("14.996"), name: "Awa"},
      %{id: "b", average: d(15), precise: d("15.004"), name: "Zoé"},
      %{id: "c", average: d(12), precise: d(12), name: "Mia"},
      %{id: "d", average: d(12), precise: d(12), name: "Bob"}
    ]

    assert GradingRules.ranks(entries, rules(shared_ranks?: false)) ==
             %{"b" => 1, "a" => 2, "d" => 3, "c" => 4}
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/grading_rules_test.exs`
Expected: FAIL (`GradingRules` undefined).

- [ ] **Step 3: Implement** `lib/teacher_assistant/academics/grading_rules.ex`:

```elixir
defmodule TeacherAssistant.Academics.GradingRules do
  @moduledoc """
  A school's averaging rules (spec D2b-1), as a pure struct: rounding, the trimester
  and annual rules, and whether tied students share a rank. Built from the school
  profile by `TeacherAssistant.Assessment.grading_rules/1`. The struct default
  (`rounding: :none`) reproduces the historical unrounded computation for callers
  that pass no rules.
  """

  defstruct trimester: :mean_of_sequences,
            annual: :mean_of_sequences,
            rounding: :none,
            shared_ranks?: true

  @four Decimal.new(4)

  def round_average(nil, _rules), do: nil
  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :none}), do: avg
  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :hundredth}), do: Decimal.round(avg, 2, :half_up)
  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :tenth}), do: Decimal.round(avg, 1, :half_up)

  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :quarter}) do
    avg |> Decimal.mult(@four) |> Decimal.round(0, :half_up) |> Decimal.div(@four)
  end

  @doc "A subject's trimester average from its `{position_in_term, séquence average}` pairs."
  def trimester_average(sequence_averages, %__MODULE__{} = rules) do
    sequence_averages
    |> Enum.map(fn {position, avg} -> {avg, sequence_weight(position, rules)} end)
    |> weighted_mean()
    |> round_average(rules)
  end

  @doc "A subject's annual average from `{term_position, [{position_in_term, avg}]}` entries."
  def annual_average(terms, %__MODULE__{annual: :mean_of_sequences} = rules) do
    terms
    |> Enum.flat_map(fn {_term, seqs} -> Enum.map(seqs, fn {_pos, avg} -> {avg, 1} end) end)
    |> weighted_mean()
    |> round_average(rules)
  end

  def annual_average(terms, %__MODULE__{annual: :mean_of_trimesters} = rules) do
    terms
    |> Enum.map(fn {_term, seqs} -> {trimester_average(seqs, rules), 1} end)
    |> weighted_mean()
    |> round_average(rules)
  end

  defp sequence_weight(2, %__MODULE__{trimester: :second_sequence_double}), do: 2
  defp sequence_weight(_position, _rules), do: 1

  # Mean of the present values with their weights; nil values drop out with their weight.
  defp weighted_mean(pairs) do
    present = Enum.reject(pairs, fn {avg, _w} -> is_nil(avg) end)
    total_weight = present |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total_weight == 0 do
      nil
    else
      present
      |> Enum.reduce(Decimal.new(0), fn {avg, w}, acc -> Decimal.add(acc, Decimal.mult(avg, w)) end)
      |> Decimal.div(Decimal.new(total_weight))
    end
  end

  @doc """
  Ranks by (rounded) `average`, best first. With `shared_ranks?`, equal averages share a
  rank (ex æquo); otherwise ties are broken by the unrounded `precise` average, then by
  `name`, so every graded entry gets its own rank.
  """
  def ranks(entries, %__MODULE__{shared_ranks?: shared?}) do
    ordered =
      entries
      |> Enum.reject(&is_nil(&1.average))
      |> Enum.sort(&ranks_before?(&1, &2, shared?))

    {ranks, _} =
      ordered
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, nil}, fn {entry, position}, {acc, prev} ->
        rank =
          case prev do
            {prev_avg, prev_rank} when shared? ->
              if Decimal.equal?(prev_avg, entry.average), do: prev_rank, else: position

            _ ->
              position
          end

        {Map.put(acc, entry.id, rank), {entry.average, rank}}
      end)

    ranks
  end

  defp ranks_before?(a, b, shared?) do
    case Decimal.compare(a.average, b.average) do
      :gt -> true
      :lt -> false
      :eq when shared? -> true
      :eq -> precise_before?(a, b)
    end
  end

  defp precise_before?(a, b) do
    case Decimal.compare(a.precise || a.average, b.precise || b.average) do
      :gt -> true
      :lt -> false
      :eq -> Map.get(a, :name, "") <= Map.get(b, :name, "")
    end
  end
end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/grading_rules_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/grading_rules.ex test/teacher_assistant/academics/grading_rules_test.exs
git commit -m "feat: grading rules: rounding, period means and ranking

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: School settings and `update_grading_rules/2`

**Files:**
- Create: `lib/teacher_assistant/academics/trimester_average_rule.ex`, `annual_average_rule.ex`, `average_rounding.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes, `update` accept list)
- Modify: `lib/teacher_assistant/assessment.ex` (`grading_rules/1`, `update_grading_rules/2`)
- Test: `test/teacher_assistant/academics/grading_settings_test.exs`

**Interfaces:**
- Consumes: `GradingRules` (Task 1).
- Produces:
  - `SchoolProfile.trimester_average_rule`, `annual_average_rule`, `average_rounding`, `shared_ranks?`.
  - Enums, each with `label/1`: `Academics.TrimesterAverageRule` (`:mean_of_sequences | :second_sequence_double`), `Academics.AnnualAverageRule` (`:mean_of_sequences | :mean_of_trimesters`), `Academics.AverageRounding` (`:hundredth | :tenth | :quarter`).
  - `Assessment.grading_rules(scope) :: %GradingRules{}`
  - `Assessment.update_grading_rules(scope, %{"trimester_average_rule" | "annual_average_rule" | "average_rounding" | "shared_ranks?" => String.t()}) :: {:ok, profile} | {:error, :invalid_rule} | {:error, term}`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.GradingSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.GradingRules
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "defaults are the official rules, rounded to the hundredth, shared ranks", %{scope: scope} do
    assert Assessment.grading_rules(scope) == %GradingRules{
             trimester: :mean_of_sequences,
             annual: :mean_of_sequences,
             rounding: :hundredth,
             shared_ranks?: true
           }
  end

  test "an admin changes the rules", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_grading_rules(scope, %{
               "trimester_average_rule" => "second_sequence_double",
               "annual_average_rule" => "mean_of_trimesters",
               "average_rounding" => "quarter",
               "shared_ranks?" => "false"
             })

    assert %GradingRules{
             trimester: :second_sequence_double,
             annual: :mean_of_trimesters,
             rounding: :quarter,
             shared_ranks?: false
           } = Assessment.grading_rules(scope)
  end

  test "an unknown field or value is refused and nothing changes", %{scope: scope} do
    assert {:error, :invalid_rule} =
             Assessment.update_grading_rules(scope, %{"average_rounding" => "thousandth"})

    assert {:error, :invalid_rule} = Assessment.update_grading_rules(scope, %{"name" => "Hacked"})
    assert {:ok, %{average_rounding: :hundredth}} = Accounts.fetch_school_profile(scope)
  end

  test "a teacher cannot change the rules", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert_forbidden(Assessment.update_grading_rules(teacher, %{"average_rounding" => "tenth"}))
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/grading_settings_test.exs`
Expected: FAIL (`grading_rules/1` undefined).

- [ ] **Step 3: Implement.**

`lib/teacher_assistant/academics/trimester_average_rule.ex`:

```elixir
defmodule TeacherAssistant.Academics.TrimesterAverageRule do
  use Ash.Type.Enum, values: [:mean_of_sequences, :second_sequence_double]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:mean_of_sequences), do: gettext("Moyenne des 2 séquences")
  def label(:second_sequence_double), do: gettext("Pondérée (2e séquence ×2)")
end
```

`lib/teacher_assistant/academics/annual_average_rule.ex`:

```elixir
defmodule TeacherAssistant.Academics.AnnualAverageRule do
  use Ash.Type.Enum, values: [:mean_of_sequences, :mean_of_trimesters]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:mean_of_sequences), do: gettext("Moyenne des 6 séquences")
  def label(:mean_of_trimesters), do: gettext("Moyenne des 3 trimestres")
end
```

`lib/teacher_assistant/academics/average_rounding.ex`:

```elixir
defmodule TeacherAssistant.Academics.AverageRounding do
  use Ash.Type.Enum, values: [:hundredth, :tenth, :quarter]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:hundredth), do: gettext("2 décimales")
  def label(:tenth), do: gettext("1 décimale")
  def label(:quarter), do: gettext("Au quart de point")
end
```

`school_profile.ex`: after the D2a attributes (`bulletin_group_subtotals?`), add:

```elixir
    attribute :trimester_average_rule, TeacherAssistant.Academics.TrimesterAverageRule,
      allow_nil?: false,
      default: :mean_of_sequences,
      public?: true

    attribute :annual_average_rule, TeacherAssistant.Academics.AnnualAverageRule,
      allow_nil?: false,
      default: :mean_of_sequences,
      public?: true

    attribute :average_rounding, TeacherAssistant.Academics.AverageRounding,
      allow_nil?: false,
      default: :hundredth,
      public?: true

    attribute :shared_ranks?, :boolean, allow_nil?: false, default: true, public?: true
```

and append `:trimester_average_rule, :annual_average_rule, :average_rounding, :shared_ranks?` to the `update :update` accept list.

`assessment.ex`: add `AnnualAverageRule`, `AverageRounding`, `GradingRules` and `TrimesterAverageRule` to its `TeacherAssistant.Academics` alias list (create the alias if needed). Then add, before the "Class results / bulletins" section:

```elixir
  # --- Grading rules (spec D2b-1) -----------------------------------------------

  @doc "The school's averaging rules, from its profile."
  def grading_rules(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    %GradingRules{
      trimester: profile.trimester_average_rule,
      annual: profile.annual_average_rule,
      rounding: profile.average_rounding,
      shared_ranks?: profile.shared_ranks?
    }
  end

  @rule_fields %{
    "trimester_average_rule" => {:trimester_average_rule, TrimesterAverageRule},
    "annual_average_rule" => {:annual_average_rule, AnnualAverageRule},
    "average_rounding" => {:average_rounding, AverageRounding}
  }

  @doc """
  Saves averaging rules from string params. Every key must be a known rule and every
  value one of its options (matched, never converted with `String.to_atom`); otherwise
  `{:error, :invalid_rule}` and nothing is written. Authorization is the school
  profile's update policy.
  """
  def update_grading_rules(%Scope{} = scope, %{} = params) do
    with {:ok, attrs} <- parse_rule_params(params),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end

  defp parse_rule_params(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case parse_rule(key, value) do
        {:ok, field, parsed} -> {:cont, {:ok, Map.put(acc, field, parsed)}}
        :error -> {:halt, {:error, :invalid_rule}}
      end
    end)
  end

  defp parse_rule("shared_ranks?", "true"), do: {:ok, :shared_ranks?, true}
  defp parse_rule("shared_ranks?", "false"), do: {:ok, :shared_ranks?, false}

  defp parse_rule(key, value) do
    with {field, enum} <- Map.get(@rule_fields, key),
         %{} = by_string <- Map.new(enum.values(), &{Atom.to_string(&1), &1}),
         {:ok, parsed} <- Map.fetch(by_string, value) do
      {:ok, field, parsed}
    else
      _ -> :error
    end
  end
```

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/grading_settings_test.exs`
Expected: PASS (4 tests). If the teacher test gets a wrapped `Invalid` instead of `Forbidden`, unwrap it with `Ash.Error.to_error_class/1`. Do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/grading_settings_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: school averaging-rule settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `Marks` and `Bulletins` apply rounding and the rank rule

**Files:**
- Modify: `lib/teacher_assistant/academics/marks.ex` (`summarize/3` → `summarize/4`; remove `assign_ranks/1`)
- Modify: `lib/teacher_assistant/academics/bulletins.ex` (`compile/2` → `compile/3`, `aggregate/2` → `aggregate/3`; remove `rank_map/1`)
- Test: append to `test/teacher_assistant/academics/bulletins_test.exs`; create `test/teacher_assistant/academics/marks_rules_test.exs`

**Interfaces:**
- Consumes: `GradingRules.round_average/2`, `ranks/2` (Task 1).
- Produces:
  - `Marks.summarize(students, assessments, marks, rules \\ %GradingRules{})`: each student's average is rounded, and ranks come from `GradingRules.ranks/2` with `precise` = the unrounded average.
  - `Bulletins.compile(students, subjects, rules \\ %GradingRules{})`, `Bulletins.aggregate(students, subject_inputs, rules \\ %GradingRules{})`:
    - every per-student subject average is rounded before use;
    - `note_x_coef`, totals and group subtotals are computed from rounded figures;
    - `moyenne_generale` = round(Σ points ÷ Σ coef);
    - class ranks use `precise` = the unrounded quotient;
    - per-subject ranks use the rounded subject average as both `average` and `precise`;
    - group averages are rounded;
    - class statistics come from rounded moyennes.
  - Students may carry `:name` (the tie-break).

- [ ] **Step 1: Write the failing tests.** Append to `bulletins_test.exs`:

```elixir
  alias TeacherAssistant.Academics.GradingRules

  test "with rules, subject averages are rounded first and the bulletin adds up" do
    students = [%{id: "s1", sex: :m, name: "Awa"}]
    # Maths: 12.345/20 → 12.35 ; EPS 10
    subjects = [
      subject("maths", "Maths", "3", [{"s1", "12.345"}]),
      subject("eps", "EPS", "1", [{"s1", "10"}])
    ]

    rules = %GradingRules{rounding: :hundredth}
    d = Bulletins.compile(students, subjects, rules).per_student["s1"]
    maths = Enum.find(d.subjects, &(&1.label == "Maths"))
    assert Decimal.equal?(maths.average, Decimal.new("12.35"))
    assert Decimal.equal?(maths.note_x_coef, Decimal.new("37.05"))
    # (37.05 + 10) / 4 = 11.7625 → 11.76
    assert Decimal.equal?(d.moyenne_generale, Decimal.new("11.76"))
  end

  test "ties created by rounding: shared, or broken by the unrounded average" do
    students = [%{id: "a", sex: :f, name: "Awa"}, %{id: "b", sex: :m, name: "Bob"}]
    # a: 13.12 → quarter 13.00 ; b: 12.9 → quarter 13.00 ; unrounded a > b
    subjects = [subject("m", "Maths", "1", [{"a", "13.12"}, {"b", "12.9"}])]

    shared = Bulletins.compile(students, subjects, %GradingRules{rounding: :quarter})
    assert shared.per_student["a"].rank == 1 and shared.per_student["b"].rank == 1

    strict =
      Bulletins.compile(students, subjects, %GradingRules{rounding: :quarter, shared_ranks?: false})

    assert strict.per_student["a"].rank == 1 and strict.per_student["b"].rank == 2
  end
```

`test/teacher_assistant/academics/marks_rules_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.MarksRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{GradingRules, Marks}

  test "the subject summary rounds averages and follows the rank rule" do
    students = [%{id: "a", sex: :f, name: "Awa"}, %{id: "b", sex: :m, name: "Bob"}]
    assessments = [%{id: "x", weight: Decimal.new(1), max_score: Decimal.new(20)}]

    marks = [
      %{assessment_id: "x", student_id: "a", score: Decimal.new("13.12")},
      %{assessment_id: "x", student_id: "b", score: Decimal.new("12.9")}
    ]

    rules = %GradingRules{rounding: :quarter, shared_ranks?: false}
    s = Marks.summarize(students, assessments, marks, rules)
    assert Decimal.equal?(s.per_student["a"].average, Decimal.new(13))
    assert s.per_student["a"].rank == 1 and s.per_student["b"].rank == 2
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/marks_rules_test.exs`
Expected: the 3 new tests FAIL (no arity-3/4 functions).

- [ ] **Step 3: Implement.**

`marks.ex`: alias `TeacherAssistant.Academics.GradingRules`. Replace `summarize/3` with:

```elixir
  def summarize(students, assessments, marks, rules \\ %GradingRules{}) do
    weights = Map.new(assessments, fn a -> {a.id, a} end)
    marks_by_student = Enum.group_by(marks, & &1.student_id)

    precise =
      Map.new(students, fn s ->
        {s.id, subject_average(Map.get(marks_by_student, s.id, []), weights)}
      end)

    ranks =
      students
      |> Enum.map(fn s ->
        %{
          id: s.id,
          average: GradingRules.round_average(precise[s.id], rules),
          precise: precise[s.id],
          name: Map.get(s, :name, "")
        }
      end)
      |> GradingRules.ranks(rules)

    per_student =
      Map.new(students, fn s ->
        avg = GradingRules.round_average(precise[s.id], rules)
        {s.id, %{average: avg, mention: mention(avg), rank: ranks[s.id]}}
      end)

    graded = graded_averages(students, per_student)

    %{
      per_student: per_student,
      class_average: mean(graded),
      pass_rate: pass_rate(graded),
      highest: max_of(graded),
      lowest: min_of(graded),
      graded_count: length(graded),
      by_sex: %{
        m: sex_stats(students, per_student, :m),
        f: sex_stats(students, per_student, :f)
      }
    }
  end
```

and delete `assign_ranks/1`.

`bulletins.ex`: alias `GradingRules` too.
- `def compile(students, subjects, rules \\ %GradingRules{})`, ending with `aggregate(students, inputs, rules)`.
- `def aggregate(students, subject_inputs, rules \\ %GradingRules{})`.
- In `aggregate/3`:
  - Round every input's averages first:

    ```elixir
    subject_inputs =
      Enum.map(subject_inputs, fn subj ->
        %{subj | per_student_avg: Map.new(subj.per_student_avg, fn {id, avg} -> {id, GradingRules.round_average(avg, rules)} end)}
      end)
    ```

  - Replace `ranks: rank_map(subj.per_student_avg)` with `ranks: subject_ranks(subj.per_student_avg, students, rules)`.
  - Compute `precise = if zero coef, do: nil, else: Decimal.div(total_points, total_coef)` and `moy = GradingRules.round_average(precise, rules)`, and keep `precise` in the per-student core map under `:precise_moyenne`.
  - Replace the class ranking with:

    ```elixir
    class_ranks =
      students
      |> Enum.map(fn s ->
        d = per_student_core[s.id]
        %{id: s.id, average: d.moyenne_generale, precise: d.precise_moyenne, name: Map.get(s, :name, "")}
      end)
      |> GradingRules.ranks(rules)
    ```

  - Drop `:precise_moyenne` when building `per_student`: `Map.new(per_student_core, fn {id, d} -> {id, d |> Map.delete(:precise_moyenne) |> Map.put(:rank, class_ranks[id])} end)`.
  - `group_subtotals(rows)` becomes `group_subtotals(rows, rules)`, with its `average` wrapped in `GradingRules.round_average(…, rules)`.
- Add:

```elixir
  defp subject_ranks(avg_map, students, rules) do
    students
    |> Enum.map(fn s ->
      avg = avg_map[s.id]
      %{id: s.id, average: avg, precise: avg, name: Map.get(s, :name, "")}
    end)
    |> GradingRules.ranks(rules)
  end
```

- Delete `rank_map/1`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/marks_rules_test.exs test/teacher_assistant/academics/marks_test.exs`
Expected: PASS. The existing tests call the default arities and keep their exact values. If `marks_test.exs` doesn't exist, drop it from the command.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/marks.ex lib/teacher_assistant/academics/bulletins.ex test/teacher_assistant/academics
git commit -m "feat: marks and bulletins apply rounding and the rank rule

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Period rules and wiring the school's rules everywhere

**Files:**
- Modify: `lib/teacher_assistant/assessment.ex` (`class_results/3`, `period_result/4`, `build_components/4`; remove `mean_present/1` if unused)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex:134`, `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex:56` (pass rules, names)
- Test: append to `test/teacher_assistant/academics/period_results_test.exs`

**Interfaces:**
- Consumes: `grading_rules/1`, `update_grading_rules/2` (Task 2); `GradingRules.trimester_average/2`, `annual_average/2`, `round_average/2` (Task 1); `Bulletins.compile/3`, `aggregate/3`, `Marks.summarize/4` (Task 3).
- Produces: `class_results/3` and `class_results_for_period/3` compute with `grading_rules(scope)`. Students carry `name: s.full_name`.

- [ ] **Step 1: Write the failing tests** (append to `PeriodResultsTest`; its setup provides `grade.(seq, score)`, `scope`, `year`, `cg`, `student`, `sequences`):

```elixir
  test "the ×2 trimester rule counts the second séquence twice, and alone when S1 is unmarked", ctx do
    %{year: year, cg: cg, sequences: [s1, s2 | _], student: st, grade: grade, scope: scope} = ctx
    {:ok, _} = Assessment.update_grading_rules(scope, %{"trimester_average_rule" => "second_sequence_double"})
    [term1 | _] = Organization.list_terms(scope, year)

    grade.(s2, 15)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 15)

    grade.(s1, 12)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    # (12 + 2·15) / 3 = 14
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 14)
  end

  test "the trimesters annual rule skips an unmarked trimester instead of counting it as zero", ctx do
    %{year: year, cg: cg, sequences: [s1, s2, s3, s4 | _], student: st, grade: grade, scope: scope} = ctx
    {:ok, _} = Assessment.update_grading_rules(scope, %{"annual_average_rule" => "mean_of_trimesters"})
    grade.(s1, 10)
    grade.(s2, 12)
    grade.(s3, 16)
    grade.(s4, 13)

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # T1 = 11, T2 = 14.5, T3 unmarked → (11 + 14.5) / 2 = 12.75
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.75"))
  end

  test "the two annual rules differ when a trimester has fewer marked séquences", ctx do
    %{year: year, cg: cg, sequences: [s1, _s2, s3, s4 | _], student: st, grade: grade, scope: scope} = ctx
    grade.(s1, 10)
    grade.(s3, 16)
    grade.(s4, 13)

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # séquences: (10 + 16 + 13) / 3 = 13
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 13)

    {:ok, _} = Assessment.update_grading_rules(scope, %{"annual_average_rule" => "mean_of_trimesters"})
    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # trimesters: T1 = 10, T2 = 14.5 → 12.25
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.25"))
  end

  test "school rounding applies to period results", ctx do
    %{year: year, cg: cg, sequences: [s1, s2 | _], student: st, grade: grade, scope: scope} = ctx
    grade.(s1, 12)
    grade.(s2, "13.3")
    [term1 | _] = Organization.list_terms(scope, year)

    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    # (12 + 13.3) / 2 = 12.65 at the default hundredth
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.65"))

    {:ok, _} = Assessment.update_grading_rules(scope, %{"average_rounding" => "quarter"})
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.75"))
  end
```

(`grade` builds `Decimal.new(score)`, so a string score like `"13.3"` works.)

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/period_results_test.exs`
Expected: the ×2 test, the two annual-rule tests and the quarter part of the rounding test FAIL, because the rules aren't applied yet.

- [ ] **Step 3: Implement** in `assessment.ex`.

`class_results/3`: compute `rules = grading_rules(scope)`, map students to `%{id: s.id, sex: s.sex, name: s.full_name}`, and call `Bulletins.compile(students, subjects, rules)`.

`period_result/4`: at the top, `rules = grading_rules(scope)`. Students get `name: s.full_name`. Round each séquence subject average where it's computed: `{s.id, GradingRules.round_average(Marks.subject_average(sm, subj.assessments_by_id), rules)}`. Replace the `per_student_avg` computation with:

```elixir
          per_student_avg =
            Map.new(students, fn s ->
              {s.id, period_average(component_kind, per_seq, cid, s.id, rules)}
            end)
```

and `components` with `build_components(component_kind, per_seq, cid, s.id, rules)`. End with `Bulletins.aggregate(students, subject_inputs, rules)`. Add:

```elixir
  # A subject's period average for one student under the school's rules.
  # :sequences = one trimester; :trimesters = the whole year.
  defp period_average(:sequences, per_seq, cid, sid, rules),
    do: GradingRules.trimester_average(sequence_pairs(per_seq, cid, sid), rules)

  defp period_average(:trimesters, per_seq, cid, sid, rules),
    do: GradingRules.annual_average(term_pairs(per_seq, cid, sid), rules)

  # [{position_in_term, avg}] for the séquences of `per_seq`, in order.
  defp sequence_pairs(per_seq, cid, sid) do
    Enum.map(per_seq, fn {seq, m} ->
      {seq.position_in_term, m[cid] && m[cid].per_student_avg[sid]}
    end)
  end

  # [{term_position, [{position_in_term, avg}]}], by term.
  defp term_pairs(per_seq, cid, sid) do
    per_seq
    |> Enum.group_by(fn {seq, _m} -> seq.term.position end)
    |> Enum.sort_by(fn {position, _} -> position end)
    |> Enum.map(fn {position, term_seqs} -> {position, sequence_pairs(term_seqs, cid, sid)} end)
  end
```

Update `build_components`:

```elixir
  defp build_components(:sequences, per_seq, cid, sid, _rules) do
    %{
      sequences:
        Enum.map(per_seq, fn {seq, m} ->
          %{number: seq.number, average: m[cid] && m[cid].per_student_avg[sid]}
        end)
    }
  end

  defp build_components(:trimesters, per_seq, cid, sid, rules) do
    %{
      trimesters:
        per_seq
        |> term_pairs(cid, sid)
        |> Enum.map(fn {position, pairs} ->
          %{position: position, average: GradingRules.trimester_average(pairs, rules)}
        end)
    }
  end
```

Delete `sequence_values/3` and `mean_present/1` if nothing else uses them (`grep` first).

`marks_live.ex:134` and `marks_summary_live.ex:56`: map students to `%{id: s.id, sex: s.sex, name: s.full_name}` and pass `Assessment.grading_rules(scope)` (or `TeacherAssistant.Assessment.grading_rules(socket.assigns.current_scope)`) as the 4th argument of `Marks.summarize`. `marks_live` builds the list in a private helper: fetch the scope from the socket assigns there. If `s.full_name` isn't loaded on those student structs, check how `students` is assigned and use the field it has.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/period_results_test.exs test/teacher_assistant/academics/bulletin_data_test.exs test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/live/teacher/`
Expected: PASS. Per the Global Constraints, update any expectation that asserted an unrounded repeating decimal.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/assessment.ex lib/teacher_assistant_web/live/teacher test
git commit -m "feat: trimester and annual rules, rounding and ranks follow the school settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The "Évaluations & moyennes" page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/evaluations_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`:school_workspace` session)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (link next to `#coefficients-link`)
- Test: `test/teacher_assistant_web/live/school/evaluations_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: `grading_rules/1`, `update_grading_rules/2` (Task 2); the enum `label/1`s (Task 2); `Accounts.can_edit_profile?/2`.
- Produces: route `/school/settings/evaluations`. DOM: `#evaluations-link` (Settings); buttons `#rule-<field>-<value>` with `phx-click="set_rule"` and `phx-value-field`/`phx-value-value`; `#toggle-shared-ranks`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.EvaluationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée E"})

    scope = school_scope(user, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
    year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope, year: year, user: user}
  end

  test "settings links to the page, which shows the official defaults", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#evaluations-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#rule-annual_average_rule-mean_of_sequences.btn-primary")
    assert render(view) =~ "règle officielle"
  end

  test "choosing quarter rounding changes a class bulletin", ctx do
    %{conn: conn, scope: scope, year: year, user: user} = ctx
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, user, %{subject: "Maths", coefficient: Decimal.new(1)})
    {:ok, a} = Assessment.create_assessment(scope, tc, seq, %{label: "D", weight: Decimal.new(1), max_score: Decimal.new(20)})
    [%{student: st, enrollment: enr}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: st.id, score: Decimal.new("13.2")}])

    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> element("#rule-average_rounding-quarter") |> render_click()
    assert render(view) =~ "Réglage enregistré."

    {:ok, _, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "13.25"
    refute html =~ "13.20"
  end

  test "the tied-ranks toggle saves", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> element("#toggle-shared-ranks") |> render_click()
    refute Assessment.grading_rules(scope).shared_ranks?
  end

  test "a crafted unknown value is refused", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    render_hook(view, "set_rule", %{"field" => "average_rounding", "value" => "thousandth"})
    assert render(view) =~ "Réglage non enregistré."
    assert Assessment.grading_rules(scope).rounding == :hundredth
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/evaluations_live_test.exs`
Expected: FAIL (no route).

- [ ] **Step 3: Implement.**

Router, after the D2a coefficients route: `live "/school/settings/evaluations", School.EvaluationsLive, :index`.

`settings_live.ex`, right after the `#coefficients-link` `<.link>`:

```heex
          <.link
            id="evaluations-link"
            navigate={~p"/school/settings/evaluations"}
            class="link link-primary text-sm"
          >
            {gettext("Évaluations & moyennes")}
          </.link>
```

`lib/teacher_assistant_web/live/school/evaluations_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.EvaluationsLive do
  @moduledoc """
  Settings → Évaluations & moyennes (spec D2b-1): the school's trimester and annual
  average rules, rounding and tied-rank behaviour. Each choice saves on click. The
  assessment-type and absence rows of the mockup arrive with D2b-2.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.{AnnualAverageRule, AverageRounding, TrimesterAverageRule}

  @rules [
    {"trimester_average_rule", :trimester, TrimesterAverageRule, :mean_of_sequences},
    {"annual_average_rule", :annual, AnnualAverageRule, :mean_of_sequences},
    {"average_rounding", :rounding, AverageRounding, nil}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, assign(socket, grading: Assessment.grading_rules(scope), rule_rows: @rules)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="evaluations" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Évaluations & moyennes")} />

        <div class="rounded-box border border-base-300 bg-base-100 divide-y divide-base-300">
          <div
            :for={{field, key, enum, official} <- @rule_rows}
            class="flex flex-wrap items-center justify-between gap-3 p-4"
          >
            <p class="font-medium">{rule_title(field)}</p>
            <div class="flex flex-wrap items-center gap-2">
              <button
                :for={value <- enum.values()}
                id={"rule-#{field}-#{value}"}
                type="button"
                phx-click="set_rule"
                phx-value-field={field}
                phx-value-value={value}
                class={[
                  "btn btn-sm rounded-full transition-colors",
                  if(Map.fetch!(@grading, key) == value, do: "btn-primary", else: "btn-ghost border-base-300")
                ]}
              >
                {enum.label(value)}
                <span :if={value == official} class="text-xs opacity-70">· {gettext("règle officielle")}</span>
              </button>
            </div>
          </div>

          <div class="flex items-center justify-between gap-4 p-4">
            <div>
              <p class="font-medium">{gettext("Rang ex æquo")}</p>
              <p class="text-xs text-base-content/60">
                {gettext("Désactivé : départage par la moyenne non arrondie, puis par le nom.")}
              </p>
            </div>
            <input
              id="toggle-shared-ranks"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@grading.shared_ranks?}
              phx-click="toggle_shared_ranks"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("set_rule", %{"field" => field, "value" => value}, socket),
    do: save(socket, %{field => value})

  def handle_event("toggle_shared_ranks", _params, socket),
    do: save(socket, %{"shared_ranks?" => to_string(!socket.assigns.grading.shared_ranks?)})

  defp save(socket, params) do
    scope = socket.assigns.current_scope

    case Assessment.update_grading_rules(scope, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(grading: Assessment.grading_rules(scope))
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp rule_title("trimester_average_rule"), do: gettext("Moyenne trimestrielle")
  defp rule_title("annual_average_rule"), do: gettext("Moyenne annuelle")
  defp rule_title("average_rounding"), do: gettext("Arrondi")
end
```

Run `mix gettext.extract --merge` and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Moyenne des 2 séquences | Mean of the 2 sequences |
| Pondérée (2e séquence ×2) | Weighted (2nd sequence ×2) |
| Moyenne des 6 séquences | Mean of the 6 sequences |
| Moyenne des 3 trimestres | Mean of the 3 terms |
| 2 décimales | 2 decimals |
| 1 décimale | 1 decimal |
| Au quart de point | To the quarter point |
| Évaluations & moyennes | Assessments & averages |
| règle officielle | official rule |
| Rang ex æquo | Tied ranks |
| Désactivé : départage par la moyenne non arrondie, puis par le nom. | Off: ties broken by the unrounded average, then by name. |
| Réglage enregistré. | Setting saved. |
| Moyenne trimestrielle | Term average |
| Moyenne annuelle | Annual average |
| Arrondi | Rounding |

("Réglage non enregistré." already exists from D2a.)

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/evaluations_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web/live/school/evaluations_live_test.exs priv/gettext
git commit -m "feat: evaluations & averages settings page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Name the migration, full gate

- [ ] **Step 1:** Run `mix ash.codegen averaging_rules`. If it hangs on a prompt, rerun it as `printf 'n\n' | mix ash.codegen averaging_rules`. Then `mix ash.reset && MIX_ENV=test mix ash.reset`.
- [ ] **Step 2:** Run `mix ash.codegen --check && mix compile --warnings-as-errors && mix precommit`.
  Expected: no drift, no warnings, and the whole suite green (810 + the new tests). Failures in files the plan didn't touch are most likely unrounded-decimal expectations. Update them to the rounded value. Anything else gets systematic debugging.
- [ ] **Step 3:** Commit:

```bash
git add -A priv/repo/migrations priv/resource_snapshots lib test priv/gettext
git commit -m "chore: name the averaging rules migration

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
