# I1 — Appreciations and distinctions (N09) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school sets its appreciation scale (editable bands) and its distinction / work-warning thresholds; every average, report card and class result uses them.

**Architecture:** The scale and thresholds live on `SchoolProfile` (an embedded list of bands plus decimal and boolean columns), are loaded into the pure `GradingRules` struct by `Assessment.grading_rules/1`, and are applied by a new pure module `Academics.Appreciations` that `Marks` and `Bulletins` call. A settings LiveView edits them; the existing report card, print, results and teacher summary screens display them.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 (embedded resource, attribute multitenancy elsewhere), AshPostgres, Tailwind v4 + daisyUI, Gettext (French source strings).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, section "I1 — Appreciations and distinctions". **Mockup excerpt:** `docs/superpowers/mockups/i1-appreciations-distinctions.html` (band editor markup, default bands `MENTIONS0`, thresholds `DIST0`, editor logic `mrows`).

## Global Constraints

- Scope-first domain functions; `scope: scope` on every Ash call; never `authorize?: false`.
- Never write migrations by hand: `mix ash.codegen --dev`, then `mix ash.codegen appreciations_and_distinctions` to name it (as D3 did), then `mix ash.migrate`.
- Never use a bare `:atom` attribute; the distinction kind is an `Ash.Type.Enum` (`Academics.Distinction`).
- UI strings are French `gettext` sources; finish with `mix gettext.extract --merge` and fill every new `en` msgstr.
- LiveViews start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`; inputs use `<.input>`; icons use `<.icon>`; colors come from the theme (`primary`, `warning`, `error`, `accent`, `base-*`), not the mockup's oklch values.
- Default bands (lower bound → label): 0 Très insuffisant, 5 Insuffisant, 8 Médiocre, 10 Passable, 12 Assez bien, 14 Bien, 16 Très bien, 18 Excellent.
- Default thresholds: Félicitations ≥ 16, Encouragements ≥ 14, Tableau d'honneur ≥ 12, Avertissement travail < 8, Blâme travail < 6. Gates: all subjects ≥ 10 (default on), note de conduite ≥ 12 (default off). Pass mark 10 and conduct minimum 12 are module constants.
- Finish with `mix precommit` AND `mix compile --warnings-as-errors` (precommit does not gate warnings and its format step rewrites files — commit after it).
- Branch `i1-appreciations`; one commit per task.

## Review Focus

1. An average exactly on a band boundary (12.00) takes the upper band; 20 takes the last band; 0 the first — Task 1.
2. A threshold left empty (nil) switches that distinction off without crashing, including when every threshold is empty — Task 1 and Task 2.
3. Decimal input typed with a comma ("9,5") in the band editor and the thresholds is accepted; text like "abc" is refused with nothing saved — Task 2 and Task 4.
4. With the conduct gate on, a student with no conduct mark for the period is not blocked; one below 12 is — Task 2.
5. Saved band labels show as typed under the English locale; default bands are translated — Task 1 and Task 4.

---

### Task 1: Pure appreciation scale and distinctions

**Files:**
- Create: `lib/teacher_assistant/academics/distinction.ex`
- Create: `lib/teacher_assistant/academics/appreciations.ex`
- Modify: `lib/teacher_assistant/academics/grading_rules.ex` (struct fields + moduledoc)
- Modify: `lib/teacher_assistant/academics/marks.ex:12-24` (`mention/1` → `mention/2`), `:57` (summarize uses rules)
- Modify: `lib/teacher_assistant/academics/bulletins.ex` (row mention, per-student distinction, class distinctions; drop `@felicitations/@encouragements/@tableau`)
- Test: create `test/teacher_assistant/academics/appreciations_test.exs`; modify `test/teacher_assistant/academics/marks_test.exs:7-16,70-73`, `test/teacher_assistant/academics/bulletins_test.exs:34,90-104`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Academics.Distinction` — `Ash.Type.Enum` values `[:felicitations, :encouragements, :tableau_honneur, :avertissement_travail, :blame_travail]`; `label/1 :: String.t()`; `honour?/1 :: boolean`.
  - `GradingRules` new fields: `appreciation_bands: nil` (nil/[] = defaults; else list of maps or structs with `:from` Decimal and `:label` String), `felicitations_min: Decimal.new(16)`, `encouragements_min: Decimal.new(14)`, `tableau_honneur_min: Decimal.new(12)`, `avertissement_travail_below: Decimal.new(8)`, `blame_travail_below: Decimal.new(6)`, `distinctions_require_all_passed?: true`, `distinctions_require_conduct?: false`. Any threshold may be nil (off).
  - `Appreciations.default_bands/0 :: [%{from: Decimal.t(), label: String.t()}]`
  - `Appreciations.bands/1 (GradingRules) :: [%{from, label}]`
  - `Appreciations.appreciation/2 (Decimal | nil, GradingRules) :: nil | %{label: String.t(), position: non_neg_integer, passed?: boolean}` (position = band index, 0 = lowest)
  - `Appreciations.distinction/4 (moyenne :: Decimal | nil, subject_averages :: [Decimal | nil], conduct :: Decimal | nil, GradingRules) :: Distinction value | nil`
  - `Marks.mention/2 (avg, rules \\ %GradingRules{})` — delegates to `Appreciations.appreciation/2`; the `mention` key everywhere (summary per student, bulletin per student, bulletin subject row) now holds that map or nil.
  - `Bulletins.aggregate/3` result: each subject row gains `mention`; each `per_student` entry gains `distinction`; `distinctions` is `%{felicitations: [ids], encouragements: [ids], tableau_honneur: [ids], avertissement_travail: [ids], blame_travail: [ids]}`. Student input maps may carry `conduct: Decimal | nil` (absent = nil).

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/academics/appreciations_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.AppreciationsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{Appreciations, GradingRules}

  defp d(n), do: Decimal.new(n)
  defp label(avg, rules \\ %GradingRules{}), do: Appreciations.appreciation(d(avg), rules).label

  describe "appreciation/2 with the default bands" do
    test "each band starts at its lower bound; 20 is in the last band" do
      assert label("0") == "Très insuffisant"
      assert label("4.99") == "Très insuffisant"
      assert label("5") == "Insuffisant"
      assert label("8") == "Médiocre"
      assert label("9.99") == "Médiocre"
      assert label("10") == "Passable"
      assert label("12") == "Assez bien"
      assert label("14") == "Bien"
      assert label("16") == "Très bien"
      assert label("18") == "Excellent"
      assert label("20") == "Excellent"
    end

    test "nil average has no appreciation; passed? is average >= 10" do
      assert Appreciations.appreciation(nil, %GradingRules{}) == nil
      assert %{passed?: false, position: 2} = Appreciations.appreciation(d("9.5"), %GradingRules{})
      assert %{passed?: true, position: 3} = Appreciations.appreciation(d("10"), %GradingRules{})
    end

    test "default labels follow the locale" do
      Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
        assert label("13") == "Fairly good"
      end)
    end
  end

  test "a school's own bands are used as typed" do
    rules = %GradingRules{
      appreciation_bands: [%{from: d("0"), label: "Faible"}, %{from: d("11"), label: "Solide"}]
    }

    assert label("10.99", rules) == "Faible"
    assert label("11", rules) == "Solide"
    assert label("20", rules) == "Solide"

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert label("15", rules) == "Solide"
    end)
  end

  describe "distinction/4" do
    test "highest honour roll wins, at the default thresholds" do
      r = %GradingRules{}
      assert Appreciations.distinction(d("16"), [d("16")], nil, r) == :felicitations
      assert Appreciations.distinction(d("15.99"), [d("15.99")], nil, r) == :encouragements
      assert Appreciations.distinction(d("12"), [d("12")], nil, r) == :tableau_honneur
      assert Appreciations.distinction(d("11.99"), [d("11.99")], nil, r) == nil
      assert Appreciations.distinction(nil, [], nil, r) == nil
    end

    test "work warnings: blâme below 6, avertissement below 8, no gate" do
      r = %GradingRules{}
      assert Appreciations.distinction(d("5.99"), [d("5.99")], d("18"), r) == :blame_travail
      assert Appreciations.distinction(d("6"), [d("6")], nil, r) == :avertissement_travail
      assert Appreciations.distinction(d("7.99"), [nil], nil, r) == :avertissement_travail
      assert Appreciations.distinction(d("8"), [d("8")], nil, r) == nil
    end

    test "all-subjects gate: a subject under 10 blocks honours unless the gate is off" do
      subjects = [d("18"), d("9")]
      assert Appreciations.distinction(d("16"), subjects, nil, %GradingRules{}) == nil

      off = %GradingRules{distinctions_require_all_passed?: false}
      assert Appreciations.distinction(d("16"), subjects, nil, off) == :felicitations
      # ungraded subjects never block
      assert Appreciations.distinction(d("16"), [d("16"), nil], nil, %GradingRules{}) ==
               :felicitations
    end

    test "conduct gate: below 12 blocks, missing conduct does not" do
      on = %GradingRules{distinctions_require_conduct?: true}
      assert Appreciations.distinction(d("17"), [d("17")], d("11.5"), on) == nil
      assert Appreciations.distinction(d("17"), [d("17")], d("12"), on) == :felicitations
      assert Appreciations.distinction(d("17"), [d("17")], nil, on) == :felicitations
      # the conduct gate is ignored when off
      assert Appreciations.distinction(d("17"), [d("17")], d("3"), %GradingRules{}) ==
               :felicitations
    end

    test "a nil threshold switches that distinction off" do
      r = %GradingRules{felicitations_min: nil, blame_travail_below: nil}
      assert Appreciations.distinction(d("19"), [d("19")], nil, r) == :encouragements
      assert Appreciations.distinction(d("2"), [d("2")], nil, r) == :avertissement_travail

      all_off = %GradingRules{
        felicitations_min: nil,
        encouragements_min: nil,
        tableau_honneur_min: nil,
        avertissement_travail_below: nil,
        blame_travail_below: nil
      }

      assert Appreciations.distinction(d("19"), [d("19")], nil, all_off) == nil
      assert Appreciations.distinction(d("1"), [d("1")], nil, all_off) == nil
    end
  end
end
```

In `test/teacher_assistant/academics/marks_test.exs`, replace the `describe "mention/1"` block (lines 7-16) with:

```elixir
  describe "mention/2" do
    test "uses the default bands" do
      assert Marks.mention(d("9")).label == "Médiocre"
      assert Marks.mention(d("10")).label == "Passable"
      assert Marks.mention(d("18")).label == "Excellent"
      assert Marks.mention(nil) == nil
    end
  end
```

and in the summarize test (around lines 70-73) replace `== :assez_bien` with `.label == "Assez bien"` and the `mention == nil` assertion for `s3` with the label of s3's average under the default bands (read s3's average in that test; e.g. an average of 8 → `"Médiocre"`, an ungraded student stays `nil`).

In `test/teacher_assistant/academics/bulletins_test.exs` line 34 replace `assert r.per_student["s1"].mention == :bien` with:

```elixir
    assert r.per_student["s1"].mention.label == "Bien"
    maths = Enum.find(r.per_student["s1"].subjects, &(&1.context_id == "maths"))
    assert maths.mention.label == "Très bien"
```

and append to the file (before the final `end`):

```elixir
  test "distinctions include work warnings and follow the rules' thresholds" do
    students = [%{id: "top", sex: :m}, %{id: "low", sex: :f}, %{id: "vlow", sex: :f}]

    subjects = [
      subject("maths", "Maths", "1", [{"top", "15"}, {"low", "7"}, {"vlow", "5"}])
    ]

    r = Bulletins.compile(students, subjects)
    assert r.per_student["top"].distinction == :encouragements
    assert r.per_student["low"].distinction == :avertissement_travail
    assert r.per_student["vlow"].distinction == :blame_travail
    assert r.distinctions.avertissement_travail == ["low"]
    assert r.distinctions.blame_travail == ["vlow"]

    strict = %GradingRules{encouragements_min: Decimal.new(16)}
    r = Bulletins.compile(students, subjects, strict)
    assert r.per_student["top"].distinction == :tableau_honneur
  end

  test "a student's conduct gates honours when the school requires it" do
    students = [%{id: "a", sex: :m, conduct: Decimal.new(10)}, %{id: "b", sex: :m}]
    subjects = [subject("maths", "Maths", "1", [{"a", "17"}, {"b", "17"}])]
    rules = %GradingRules{distinctions_require_conduct?: true}

    r = Bulletins.compile(students, subjects, rules)
    assert r.per_student["a"].distinction == nil
    assert r.per_student["b"].distinction == :felicitations
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant/academics/appreciations_test.exs test/teacher_assistant/academics/marks_test.exs test/teacher_assistant/academics/bulletins_test.exs`
Expected: FAIL — `Appreciations` undefined, `mention` returns atoms.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/distinction.ex`:

```elixir
defmodule TeacherAssistant.Academics.Distinction do
  @moduledoc """
  A student's distinction for a period (spec I1): one of the three honour rolls, or a
  work warning (avertissement / blâme de travail). Computed from the school's
  thresholds by `Academics.Appreciations.distinction/4`.
  """
  use Ash.Type.Enum,
    values: [:felicitations, :encouragements, :tableau_honneur, :avertissement_travail, :blame_travail]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:felicitations), do: gettext("Félicitations")
  def label(:encouragements), do: gettext("Encouragements")
  def label(:tableau_honneur), do: gettext("Tableau d'honneur")
  def label(:avertissement_travail), do: gettext("Avertissement travail")
  def label(:blame_travail), do: gettext("Blâme travail")

  def honour?(value), do: value in [:felicitations, :encouragements, :tableau_honneur]
end
```

`lib/teacher_assistant/academics/appreciations.ex`:

```elixir
defmodule TeacherAssistant.Academics.Appreciations do
  @moduledoc """
  A school's appreciation scale and distinctions (spec I1), pure. The scale is a list
  of bands, each `%{from, label}`: a band covers `from` ≤ average < the next band's
  `from`, and the last band includes 20. With no saved bands the default scale applies,
  its labels translated; saved labels are shown as typed.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.GradingRules

  @pass Decimal.new(10)
  @conduct_min Decimal.new(12)

  @honours [
    felicitations: :felicitations_min,
    encouragements: :encouragements_min,
    tableau_honneur: :tableau_honneur_min
  ]

  def pass_mark, do: @pass
  def conduct_minimum, do: @conduct_min

  @doc "The default scale (labels in the current locale)."
  def default_bands do
    [
      {"0", gettext("Très insuffisant")},
      {"5", gettext("Insuffisant")},
      {"8", gettext("Médiocre")},
      {"10", gettext("Passable")},
      {"12", gettext("Assez bien")},
      {"14", gettext("Bien")},
      {"16", gettext("Très bien")},
      {"18", gettext("Excellent")}
    ]
    |> Enum.map(fn {from, label} -> %{from: Decimal.new(from), label: label} end)
  end

  @doc "The scale in force under `rules`, lowest band first."
  def bands(%GradingRules{appreciation_bands: bands}) when bands in [nil, []], do: default_bands()

  def bands(%GradingRules{appreciation_bands: bands}),
    do: Enum.map(bands, &%{from: &1.from, label: &1.label})

  @doc "`%{label, position, passed?}` for `average`, or nil when there is no average."
  def appreciation(nil, _rules), do: nil

  def appreciation(%Decimal{} = average, %GradingRules{} = rules) do
    [first | _] = indexed = rules |> bands() |> Enum.with_index()

    {band, position} =
      Enum.reduce(indexed, first, fn {band, _} = entry, acc ->
        if gte(average, band.from), do: entry, else: acc
      end)

    %{label: band.label, position: position, passed?: gte(average, @pass)}
  end

  @doc """
  The distinction earned with `moyenne`: the highest honour roll whose threshold is
  met and whose gates pass, else a work warning (blâme before avertissement), else nil.
  `subject_averages` are the student's subject averages (nil = ungraded, never blocks);
  `conduct` is the period's note de conduite (nil = none, never blocks).
  """
  def distinction(nil, _subject_averages, _conduct, _rules), do: nil

  def distinction(%Decimal{} = moyenne, subject_averages, conduct, %GradingRules{} = rules) do
    honour(moyenne, subject_averages, conduct, rules) || warning(moyenne, rules)
  end

  defp honour(moyenne, subject_averages, conduct, rules) do
    if all_passed_ok?(subject_averages, rules) and conduct_ok?(conduct, rules) do
      Enum.find_value(@honours, fn {kind, field} ->
        threshold = Map.fetch!(rules, field)
        if threshold && gte(moyenne, threshold), do: kind
      end)
    end
  end

  defp warning(moyenne, rules) do
    cond do
      below?(moyenne, rules.blame_travail_below) -> :blame_travail
      below?(moyenne, rules.avertissement_travail_below) -> :avertissement_travail
      true -> nil
    end
  end

  defp all_passed_ok?(_averages, %GradingRules{distinctions_require_all_passed?: false}), do: true

  defp all_passed_ok?(averages, _rules),
    do: Enum.all?(averages, &(is_nil(&1) or gte(&1, @pass)))

  defp conduct_ok?(_conduct, %GradingRules{distinctions_require_conduct?: false}), do: true
  defp conduct_ok?(nil, _rules), do: true
  defp conduct_ok?(conduct, _rules), do: gte(conduct, @conduct_min)

  defp below?(_value, nil), do: false
  defp below?(value, threshold), do: Decimal.compare(value, threshold) == :lt

  defp gte(a, b), do: Decimal.compare(a, b) != :lt
end
```

In `lib/teacher_assistant/academics/grading_rules.ex`, extend the struct and the moduledoc:

```elixir
  defstruct trimester: :mean_of_sequences,
            annual: :mean_of_sequences,
            rounding: :none,
            shared_ranks?: true,
            absence: :excluded,
            # Spec I1: nil/[] = default scale (`Academics.Appreciations.default_bands/0`).
            appreciation_bands: nil,
            # Spec I1: a nil threshold switches that distinction off.
            felicitations_min: Decimal.new(16),
            encouragements_min: Decimal.new(14),
            tableau_honneur_min: Decimal.new(12),
            avertissement_travail_below: Decimal.new(8),
            blame_travail_below: Decimal.new(6),
            distinctions_require_all_passed?: true,
            distinctions_require_conduct?: false
```

Append to the moduledoc: "Spec I1 adds the appreciation scale and the distinction thresholds and gates, applied by `Academics.Appreciations`."

In `lib/teacher_assistant/academics/marks.ex`, replace `mention/1` (lines 12-24) with:

```elixir
  @doc "The appreciation of a /20 average under the school's scale (`Academics.Appreciations`)."
  def mention(avg, rules \\ %GradingRules{}), do: Appreciations.appreciation(avg, rules)
```

add `Appreciations` to the alias (`alias TeacherAssistant.Academics.{Appreciations, GradingRules}`), and in `summarize/4` (line 57) change `mention: mention(avg)` to `mention: mention(avg, rules)`.

In `lib/teacher_assistant/academics/bulletins.ex`:
- alias: `alias TeacherAssistant.Academics.{Appreciations, BulletinGroup, Distinction, GradingRules, Marks}`; delete `@felicitations`, `@encouragements`, `@tableau` (keep `@pass`).
- in the subject row map (inside `per_student_core`, the map with `average: avg`), add `mention: Marks.mention(avg, rules),`.
- in the student map, change `mention: Marks.mention(moy),` to `mention: Marks.mention(moy, rules),`.
- replace the `per_student =` assignment with:

```elixir
    per_student =
      per_student_core
      |> Map.new(fn {id, d} ->
        {id, d |> Map.delete(:precise_moyenne) |> Map.put(:rank, class_ranks[id])}
      end)
      |> put_distinctions(students, rules)
```

- change `distinctions: distinctions(students, per_student),` to keep the same call, and replace the private `distinctions/2` and `prepend/3` with:

```elixir
  defp put_distinctions(per_student, students, rules) do
    Map.new(students, fn s ->
      d = per_student[s.id]

      distinction =
        Appreciations.distinction(
          d.moyenne_generale,
          Enum.map(d.subjects, & &1.average),
          Map.get(s, :conduct),
          rules
        )

      {s.id, Map.put(d, :distinction, distinction)}
    end)
  end

  defp distinctions(students, per_student) do
    base = Map.new(Distinction.values(), &{&1, []})

    Enum.reduce(students, base, fn s, acc ->
      case per_student[s.id].distinction do
        nil -> acc
        kind -> Map.update!(acc, kind, &(&1 ++ [s.id]))
      end
    end)
  end
```

- update the moduledoc's first line to "Pure, deterministic cross-subject bulletin computation (Francophone /20, spec I1 scale and distinctions)."

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant/academics/appreciations_test.exs test/teacher_assistant/academics/marks_test.exs test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/period_results_test.exs test/teacher_assistant/academics/marks_rules_test.exs`
Expected: PASS. (`"Assez bien"` already translates to "Fairly good" in `priv/gettext/en/LC_MESSAGES/default.po`.)

Then run `mix compile`: it must succeed (only `Bulletins` and `Marks` call `mention`; the web layer only renders the value, and is updated in Task 3).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics test/teacher_assistant/academics priv/gettext
git commit -m "feat: configurable-ready appreciation scale and distinctions (pure)"
```

(The web views still render the old badge until Task 3; `mix test` of web tests may fail on `mention_badge` until then — that is expected only between Task 1 and Task 3; run the full suite at the end of Task 3.)

---

### Task 2: School settings data, save functions and the conduct gate

**Files:**
- Create: `lib/teacher_assistant/accounts/appreciation_band.ex` (embedded resource)
- Create: `lib/teacher_assistant/accounts/school_profile/validate_appreciations.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes, `:update` accept list, validation)
- Modify: `lib/teacher_assistant/assessment.ex:438-450` (`grading_rules/1`), add save functions after `update_entry_grace_days/2`, `class_results/3` (~l.566) and `period_result/4` (~l.610) student building
- Generated: `priv/repo/migrations/*_appreciations_and_distinctions.exs`, `priv/resource_snapshots/repo/school_profiles/*.json`
- Test: create `test/teacher_assistant/academics/appreciation_settings_test.exs`; modify `test/teacher_assistant/academics/grading_settings_test.exs:12-20`

**Interfaces:**
- Consumes: Task 1 `GradingRules` fields, `Appreciations`.
- Produces:
  - `TeacherAssistant.Accounts.AppreciationBand` — embedded, attributes `from :decimal`, `label :string`.
  - `SchoolProfile` attributes: `appreciation_bands {:array, AppreciationBand}` (nil default), `felicitations_min`, `encouragements_min`, `tableau_honneur_min`, `avertissement_travail_below`, `blame_travail_below` (decimal, nullable, defaults 16/14/12/8/6), `distinctions_require_all_passed?` (bool, default true), `distinctions_require_conduct?` (bool, default false).
  - `Assessment.update_appreciation_bands(scope, [%{from: String.t() | Decimal.t(), label: String.t()}]) :: {:ok, SchoolProfile} | {:error, :invalid_number} | {:error, Ash.Error.Invalid | Ash.Error.Forbidden}`
  - `Assessment.reset_appreciation_bands(scope) :: {:ok, SchoolProfile} | {:error, term}`
  - `Assessment.update_distinction_rules(scope, %{"felicitations_min" => "16", ..., "distinctions_require_all_passed?" => "true" | "false", "distinctions_require_conduct?" => "true" | "false"}) :: {:ok, SchoolProfile} | {:error, :invalid_number} | {:error, Ash.Error.*}` — an empty or missing threshold string means nil (off); a missing toggle means false.
  - `Assessment.grading_rules/1` fills the I1 fields from the profile.
  - `Assessment.class_results_for_period/3` students carry `conduct:` when `distinctions_require_conduct?` is on.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/academics/appreciation_settings_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.AppreciationSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Assessment, Curriculum, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{Appreciations, GradingRules}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    %{scope: scope, head: head}
  end

  defp band(from, label), do: %{from: from, label: label}

  test "defaults: no saved scale, official thresholds", %{scope: scope} do
    rules = Assessment.grading_rules(scope)
    assert rules.appreciation_bands in [nil, []]
    assert Appreciations.bands(rules) |> length() == 8
    assert Decimal.equal?(rules.felicitations_min, 16)
    assert Decimal.equal?(rules.blame_travail_below, 6)
    assert rules.distinctions_require_all_passed?
    refute rules.distinctions_require_conduct?
  end

  test "a school saves its own bands, comma decimals accepted", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_appreciation_bands(scope, [
               band("0", "Faible"),
               band("9,5", " Moyen "),
               band("15", "Fort")
             ])

    rules = Assessment.grading_rules(scope)
    assert [%{label: "Faible"}, %{label: "Moyen"}, %{label: "Fort"}] = Appreciations.bands(rules)
    assert Appreciations.appreciation(Decimal.new("9.5"), rules).label == "Moyen"

    assert {:ok, _} = Assessment.reset_appreciation_bands(scope)
    assert Assessment.grading_rules(scope) |> Appreciations.bands() |> length() == 8
  end

  test "invalid bands are refused and nothing changes", %{scope: scope} do
    assert {:error, :invalid_number} =
             Assessment.update_appreciation_bands(scope, [band("0", "A"), band("abc", "B")])

    for bad <- [
          [band("1", "A")],
          [band("0", "A"), band("12", "B"), band("10", "C")],
          [band("0", "A"), band("10", "B"), band("10", "C")],
          [band("0", "A"), band("21", "B")],
          [band("0", "A"), band("10", "  ")]
        ] do
      assert {:error, %Ash.Error.Invalid{}} = Assessment.update_appreciation_bands(scope, bad)
    end

    assert {:ok, %{appreciation_bands: bands}} = Accounts.fetch_school_profile(scope)
    assert bands in [nil, []]
  end

  test "thresholds: empty switches off, order is enforced", %{scope: scope} do
    params = %{
      "felicitations_min" => "17",
      "encouragements_min" => "14,5",
      "tableau_honneur_min" => "12",
      "avertissement_travail_below" => "",
      "blame_travail_below" => "5",
      "distinctions_require_all_passed?" => "false",
      "distinctions_require_conduct?" => "true"
    }

    assert {:ok, _} = Assessment.update_distinction_rules(scope, params)

    assert %GradingRules{
             avertissement_travail_below: nil,
             distinctions_require_all_passed?: false,
             distinctions_require_conduct?: true
           } = rules = Assessment.grading_rules(scope)

    assert Decimal.equal?(rules.encouragements_min, Decimal.new("14.5"))

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{params | "encouragements_min" => "18"})

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{
               params
               | "avertissement_travail_below" => "4"
             })

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{params | "tableau_honneur_min" => "25"})

    assert {:error, :invalid_number} =
             Assessment.update_distinction_rules(scope, %{params | "felicitations_min" => "x"})

    assert Decimal.equal?(Assessment.grading_rules(scope).felicitations_min, 17)
  end

  test "every threshold empty: no distinction at all, no crash", %{scope: scope} do
    empty =
      Map.new(
        ~w(felicitations_min encouragements_min tableau_honneur_min avertissement_travail_below blame_travail_below),
        &{&1, ""}
      )

    assert {:ok, _} = Assessment.update_distinction_rules(scope, empty)
    rules = Assessment.grading_rules(scope)
    assert Appreciations.distinction(Decimal.new(19), [], nil, rules) == nil
  end

  test "the conduct gate reads the period's note de conduite", %{scope: scope, head: head} do
    year = TeacherFixtures.complete_school_setup!(scope)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e G", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bella", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Diane", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    roster = Enrollment.list_roster(scope, cg)

    :ok =
      Assessment.upsert_marks(
        scope,
        a,
        Enum.map(roster, &%{student_id: &1.student.id, score: Decimal.new(17)})
      )

    [bella, chantal, _diane] = roster
    {:ok, _} = Discipline.set_conduct_mark(scope, bella.enrollment, seq, "10")
    {:ok, _} = Discipline.set_conduct_mark(scope, chantal.enrollment, seq, "15")

    {:ok, _} =
      Assessment.update_distinction_rules(scope, %{
        "felicitations_min" => "16",
        "encouragements_min" => "14",
        "tableau_honneur_min" => "12",
        "avertissement_travail_below" => "8",
        "blame_travail_below" => "6",
        "distinctions_require_all_passed?" => "true",
        "distinctions_require_conduct?" => "true"
      })

    r = Assessment.class_results_for_period(scope, cg, {:sequence, seq})
    by_name = Map.new(roster, &{&1.student.full_name, r.per_student[&1.student.id].distinction})
    assert by_name == %{"Bella" => nil, "Chantal" => :felicitations, "Diane" => :felicitations}
  end
end
```

(If `Discipline.set_conduct_mark/4` returns something other than `{:ok, _}`, read its doc at `lib/teacher_assistant/discipline.ex:130-150` and match its success shape; it accepts a string or decimal value.)

In `test/teacher_assistant/academics/grading_settings_test.exs`, the first test compares the whole struct; change it to match only the D2b fields:

```elixir
    assert %GradingRules{
             trimester: :mean_of_sequences,
             annual: :mean_of_sequences,
             rounding: :hundredth,
             shared_ranks?: true,
             absence: :zero
           } = Assessment.grading_rules(scope)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant/academics/appreciation_settings_test.exs`
Expected: FAIL — `update_appreciation_bands/2` undefined.

- [ ] **Step 3: Implement the data**

`lib/teacher_assistant/accounts/appreciation_band.ex`:

```elixir
defmodule TeacherAssistant.Accounts.AppreciationBand do
  @moduledoc """
  One band of a school's appreciation scale (spec I1), embedded in
  `SchoolProfile.appreciation_bands`: averages from `from` up to the next band's
  `from` read `label`. The list-level rules live in `SchoolProfile.ValidateAppreciations`.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :from, :decimal, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
  end
end
```

`lib/teacher_assistant/accounts/school_profile/validate_appreciations.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolProfile.ValidateAppreciations do
  @moduledoc """
  Spec I1 rules for the appreciation scale and the distinction thresholds:
  bands start at 0, strictly increase, stay within 0..20 and have a label;
  set thresholds stay within 0..20 with Félicitations ≥ Encouragements ≥ Tableau
  d'honneur, Blâme < Avertissement and Avertissement ≤ Tableau d'honneur.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @zero Decimal.new(0)
  @twenty Decimal.new(20)

  @thresholds [
    :felicitations_min,
    :encouragements_min,
    :tableau_honneur_min,
    :avertissement_travail_below,
    :blame_travail_below
  ]

  @impl true
  def validate(changeset, _opts, _context) do
    with :ok <- validate_bands(Ash.Changeset.get_attribute(changeset, :appreciation_bands)) do
      validate_thresholds(Map.new(@thresholds, &{&1, Ash.Changeset.get_attribute(changeset, &1)}))
    end
  end

  defp validate_bands(bands) when bands in [nil, []], do: :ok

  defp validate_bands([first | _] = bands) do
    froms = Enum.map(bands, & &1.from)

    cond do
      Enum.any?(bands, &blank?(&1.label)) ->
        band_error(gettext("Chaque tranche doit avoir une appréciation."))

      not Decimal.equal?(first.from, @zero) ->
        band_error(gettext("La première tranche doit commencer à 0."))

      Enum.any?(froms, &out_of_range?/1) ->
        band_error(gettext("Les bornes doivent être comprises entre 0 et 20."))

      not strictly_increasing?(froms) ->
        band_error(gettext("Les bornes doivent être croissantes."))

      true ->
        :ok
    end
  end

  defp validate_thresholds(t) do
    cond do
      t |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.any?(&out_of_range?/1) ->
        threshold_error(gettext("Les seuils doivent être compris entre 0 et 20."))

      not non_increasing?([t.felicitations_min, t.encouragements_min, t.tableau_honneur_min]) ->
        threshold_error(
          gettext("Félicitations ≥ Encouragements ≥ Tableau d'honneur.")
        )

      both?(t.blame_travail_below, t.avertissement_travail_below) and
          not lt?(t.blame_travail_below, t.avertissement_travail_below) ->
        threshold_error(gettext("Le seuil du blâme doit être inférieur à celui de l'avertissement."))

      both?(t.avertissement_travail_below, t.tableau_honneur_min) and
          lt?(t.tableau_honneur_min, t.avertissement_travail_below) ->
        threshold_error(
          gettext("Le seuil de l'avertissement ne peut pas dépasser celui du tableau d'honneur.")
        )

      true ->
        :ok
    end
  end

  defp blank?(label), do: is_nil(label) or String.trim(label) == ""

  defp out_of_range?(d), do: lt?(d, @zero) or lt?(@twenty, d)

  defp strictly_increasing?(values),
    do: values |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> lt?(a, b) end)

  # Over the set values only, in the given order.
  defp non_increasing?(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> not lt?(a, b) end)
  end

  defp both?(a, b), do: not is_nil(a) and not is_nil(b)
  defp lt?(a, b), do: Decimal.compare(a, b) == :lt

  defp band_error(message), do: {:error, field: :appreciation_bands, message: message}
  defp threshold_error(message), do: {:error, field: :felicitations_min, message: message}
end
```

In `lib/teacher_assistant/accounts/school_profile.ex`:
- add to the `:update` accept list after `:entry_grace_days`:

```elixir
        :entry_grace_days,
        :appreciation_bands,
        :felicitations_min,
        :encouragements_min,
        :tableau_honneur_min,
        :avertissement_travail_below,
        :blame_travail_below,
        :distinctions_require_all_passed?,
        :distinctions_require_conduct?
```

- inside `update :update do`, after the accept list, add `validate TeacherAssistant.Accounts.SchoolProfile.ValidateAppreciations`.
- add attributes after `entry_grace_days`:

```elixir
    # Spec I1: the school's appreciation scale; nil = the default scale.
    attribute :appreciation_bands, {:array, TeacherAssistant.Accounts.AppreciationBand},
      public?: true

    # Spec I1: distinction and work-warning thresholds (/20); nil = switched off.
    attribute :felicitations_min, :decimal, default: Decimal.new(16), public?: true
    attribute :encouragements_min, :decimal, default: Decimal.new(14), public?: true
    attribute :tableau_honneur_min, :decimal, default: Decimal.new(12), public?: true
    attribute :avertissement_travail_below, :decimal, default: Decimal.new(8), public?: true
    attribute :blame_travail_below, :decimal, default: Decimal.new(6), public?: true

    attribute :distinctions_require_all_passed?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :distinctions_require_conduct?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true
```

Generate and apply the migration:

```bash
mix ash.codegen --dev
mix ash.codegen appreciations_and_distinctions
mix ash.migrate
```

Check the generated migration adds the eight columns to `school_profiles` with the defaults above (existing schools get 16/14/12/8/6, true, false, and NULL bands).

- [ ] **Step 4: Implement the domain functions**

In `lib/teacher_assistant/assessment.ex`, extend `grading_rules/1`:

```elixir
    %GradingRules{
      trimester: profile.trimester_average_rule,
      annual: profile.annual_average_rule,
      rounding: profile.average_rounding,
      shared_ranks?: profile.shared_ranks?,
      absence: profile.absence_rule,
      appreciation_bands: profile.appreciation_bands,
      felicitations_min: profile.felicitations_min,
      encouragements_min: profile.encouragements_min,
      tableau_honneur_min: profile.tableau_honneur_min,
      avertissement_travail_below: profile.avertissement_travail_below,
      blame_travail_below: profile.blame_travail_below,
      distinctions_require_all_passed?: profile.distinctions_require_all_passed?,
      distinctions_require_conduct?: profile.distinctions_require_conduct?
    }
```

Add after `update_entry_grace_days/2`:

```elixir
  # --- Appreciations and distinctions (spec I1) -----------------------------------

  @threshold_fields ~w(felicitations_min encouragements_min tableau_honneur_min avertissement_travail_below blame_travail_below)a
  @distinction_gates ~w(distinctions_require_all_passed? distinctions_require_conduct?)a

  @doc """
  Saves the school's appreciation scale from `[%{from: "0", label: "…"}, …]`, lowest
  band first; bounds accept a comma. `{:error, :invalid_number}` when a bound is not a
  number; the profile validation enforces the scale's rules.
  """
  def update_appreciation_bands(%Scope{} = scope, rows) when is_list(rows) do
    with {:ok, bands} <- parse_bands(rows) do
      update_profile(scope, %{appreciation_bands: bands})
    end
  end

  @doc "Goes back to the default appreciation scale."
  def reset_appreciation_bands(%Scope{} = scope),
    do: update_profile(scope, %{appreciation_bands: nil})

  @doc """
  Saves the distinction thresholds and gates from string params. An empty threshold
  switches it off; a missing gate is false; a non-number gives `{:error, :invalid_number}`.
  """
  def update_distinction_rules(%Scope{} = scope, %{} = params) do
    with {:ok, thresholds} <- parse_thresholds(params) do
      gates = Map.new(@distinction_gates, &{&1, Map.get(params, Atom.to_string(&1)) == "true"})
      update_profile(scope, Map.merge(thresholds, gates))
    end
  end

  defp update_profile(scope, attrs) do
    with {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end

  defp parse_bands(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case parse_score(row.from) do
        {:ok, %Decimal{} = from} ->
          {:cont, {:ok, acc ++ [%{from: from, label: String.trim(row.label || "")}]}}

        _ ->
          {:halt, {:error, :invalid_number}}
      end
    end)
  end

  defp parse_thresholds(params) do
    Enum.reduce_while(@threshold_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case parse_score(Map.get(params, Atom.to_string(field), "")) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        :error -> {:halt, {:error, :invalid_number}}
      end
    end)
  end

  # "" → nil; "9,5" → 9.5; anything else not a number → :error. Range checks are the
  # profile validation's job.
  defp parse_score(%Decimal{} = d), do: {:ok, d}

  defp parse_score(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") do
      "" ->
        {:ok, nil}

      text ->
        case Decimal.parse(text) do
          {dec, ""} -> {:ok, dec}
          _ -> :error
        end
    end
  end

  defp parse_score(nil), do: {:ok, nil}
  defp parse_score(_), do: :error
```

`parse_bands/1` refuses an empty bound: only `{:ok, %Decimal{}}` continues; `{:ok, nil}` falls to `_`.

Students carry their conduct when the gate is on. In `class_results/3` replace the `students = …` block with `students = bulletin_students(scope, cg, {:sequence, seq}, rules)` after binding `rules = grading_rules(scope)`, and pass `rules` to `Bulletins.compile`:

```elixir
  def class_results(%Scope{} = scope, %ClassGroup{} = cg, %Sequence{} = seq) do
    case class_subjects(scope, cg, seq) do
      [] ->
        nil

      subjects ->
        rules = grading_rules(scope)
        students = bulletin_students(scope, cg, {:sequence, seq}, rules)
        Bulletins.compile(students, subjects, rules)
    end
  end
```

`period_result/4` receives `seqs` and a component kind, not the period tuple. Change its signature to also take the period tuple: `defp period_result(%Scope{} = scope, cg, period, seqs, component_kind)`, update the two callers (`period_result(scope, cg, {:trimester, term}, seqs, :sequences)` and `period_result(scope, cg, {:annual, year}, seqs, :trimesters)`), and replace its `students = …` block with `students = bulletin_students(scope, cg, period, rules)`.

Add:

```elixir
  # The roster as bulletin inputs. With the conduct gate on (spec I1), each student
  # carries the period's note de conduite, read once for the class.
  defp bulletin_students(scope, cg, period, %GradingRules{distinctions_require_conduct?: true}) do
    conduct = TeacherAssistant.Discipline.class_discipline(scope, cg, period)

    scope
    |> TeacherAssistant.Enrollment.list_roster(cg)
    |> Enum.map(fn %{student: s, enrollment: e} ->
      note = conduct |> Map.get(e.id, %{}) |> Map.get(:note_de_conduite)
      %{id: s.id, sex: s.sex, name: s.full_name, conduct: note}
    end)
  end

  defp bulletin_students(scope, cg, _period, _rules) do
    scope
    |> TeacherAssistant.Enrollment.list_students(cg)
    |> Enum.map(fn s -> %{id: s.id, sex: s.sex, name: s.full_name} end)
  end
```

(Reading conduct marks is allowed to the conduct roles and the class's form master — the same people `class_manager?` lets open results and bulletins.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant/academics/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant priv/repo priv/resource_snapshots test/teacher_assistant
git commit -m "feat: schools store their appreciation scale and distinction thresholds"
```

---

### Task 3: Show appreciations and distinctions on the report card, results and teacher summary

**Files:**
- Modify: `lib/teacher_assistant_web/components/core_components.ex:601-625` (`mention_badge`)
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex` (Appréciation column, distinction under the totals)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (same, print)
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex:182-196` (five groups)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex:9,88-96` (distribution by band)
- Test: `test/teacher_assistant_web/components/kit_test.exs:54-59`, `test/teacher_assistant_web/live/school/bulletin_live_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`, `test/teacher_assistant_web/live/school/results_live_test.exs`, `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs:84-85`

**Interfaces:**
- Consumes: `mention` maps (`%{label, position, passed?}`) on bulletin rows, per-student bulletins and the teacher summary; `distinction` per student; `distinctions` with five keys; `Distinction.label/1`, `Distinction.honour?/1`.
- Produces: `<.mention_badge mention={map | nil} />`; `<.distinction_badge distinction={atom | nil} />` (new, in core_components).

- [ ] **Step 1: Write the failing tests**

`kit_test.exs` — replace the mention test with:

```elixir
  test "mention_badge shows the appreciation with a check when passed, an x otherwise" do
    passed = render_component(&mention_badge/1, %{mention: %{label: "Bien", passed?: true}})
    assert passed =~ "Bien"
    assert passed =~ "hero-check-circle"

    failed = render_component(&mention_badge/1, %{mention: %{label: "Médiocre", passed?: false}})
    assert failed =~ "Médiocre"
    assert failed =~ "hero-x-circle"

    assert render_component(&mention_badge/1, %{mention: nil}) =~ "—"
  end

  test "distinction_badge names the distinction" do
    assert render_component(&distinction_badge/1, %{distinction: :tableau_honneur}) =~
             "Tableau d&#39;honneur"

    assert render_component(&distinction_badge/1, %{distinction: :blame_travail}) =~
             "Blâme travail"
  end
```

`bulletin_live_test.exs` — the setup gives Awa 15/20 in Maths (coef 4). Add:

```elixir
  test "the bulletin shows each subject's appreciation and the student's distinction", %{
    conn: conn,
    cg: cg,
    enr: enr,
    seq: seq,
    tc: tc
  } do
    {:ok, view, _} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert view |> element("#bulletin-subject-#{tc.id} [data-role=appreciation]") |> render() =~
             "Bien"

    assert render(element(view, "#bulletin-distinction")) =~ "Encouragements"
  end

  test "the bulletin uses the school's own scale", %{conn: conn, cg: cg, enr: enr, seq: seq, scope: scope} do
    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [
        %{from: "0", label: "À revoir"},
        %{from: "14", label: "Réussi"}
      ])

    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "Réussi"
  end
```

Add `tc: tc` to the setup's returned map (line ~49). Subject rows are keyed by `context_id`, the teaching context id. Awa's 15 reads "Bien" and her moyenne 15 earns Encouragements.

`bulletin_print_controller_test.exs` — in "single bulletin print shows the school and the student", add `assert html =~ "Appréciation"` and the student's expected appreciation label (the test's mark decides it: e.g. a 15 → `"Bien"`), and the distinction label when the average qualifies.

`results_live_test.exs` — add a test giving one student 7/20 and checking `render(element(view, "#results-distinctions")) =~ "Avertissement travail"`; reuse the file's existing setup to create the class, assessment and marks.

`marks_summary_live_test.exs:84-85` — "Insuffisant" no longer exists for averages ≥ 8; change the second assertion to the label of the low student's band under the default scale (read that test's marks: a 9 → `"Médiocre"`, a 6 → `"Insuffisant"`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant_web/components/kit_test.exs test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

`core_components.ex` — replace `mention_badge` and the private `mention_label/1` clauses with:

```elixir
  attr :mention, :map, default: nil, doc: "an appreciation `%{label, passed?}` (`Marks.mention/2`)"

  def mention_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 text-sm font-semibold",
      if(@mention && @mention.passed?, do: "text-primary", else: "text-accent")
    ]}>
      <.icon
        :if={@mention}
        name={if @mention.passed?, do: "hero-check-circle", else: "hero-x-circle"}
        class="size-4"
      />
      {if @mention, do: @mention.label, else: "—"}
    </span>
    """
  end

  attr :distinction, :atom, default: nil, doc: "a `TeacherAssistant.Academics.Distinction` value"

  def distinction_badge(assigns) do
    ~H"""
    <span
      :if={@distinction}
      class={[
        "badge badge-sm",
        case @distinction do
          :blame_travail -> "badge-error"
          :avertissement_travail -> "badge-warning"
          _ -> "badge-success"
        end
      ]}
    >
      {TeacherAssistant.Academics.Distinction.label(@distinction)}
    </span>
    """
  end
```

`bulletin_live.ex`:
- In the `<thead>` row, after `<th>{gettext("Note×Coef")}</th>` add `<th>{gettext("Appréciation")}</th>` (keep "Cote classe" last).
- In each subject `<tr :for={row <- g.rows} …>`, after the note×coef cell add `<td data-role="appreciation"><.mention_badge :if={row.mention} mention={row.mention} /></td>`.
- Group header `colspan={period_cols(@period_kind) + 4}` → `+ 5`; in the "Total groupe" row add one more `<td></td>` before the last `<td></td>`; in `<tfoot>` add one more `<th></th>` after the total points `<th>`.
- In `#bulletin-totals`, replace the mention cell with:

```heex
            <div class="ta-leaf flex flex-wrap items-center gap-2">
              <.mention_badge :if={@data.mention} mention={@data.mention} />
              <span id="bulletin-distinction">
                <.distinction_badge distinction={@data.distinction} />
              </span>
            </div>
```

`bulletin_print_html/show.html.heex`: same column additions (header `<th class="num">{gettext("Appréciation")}</th>` after Note×Coef, row cell `<td>{row.mention && row.mention.label}</td>`, colspan `+ 5`, one more empty cell in the group-total row and in the tfoot). Change the totals paragraph to:

```heex
        <p class="totals">
          <strong>{gettext("Moyenne générale")} : {fmt(b.data.moyenne_generale)}/20</strong>
          &nbsp;·&nbsp; {gettext("Rang")} : {b.data.rank || "—"} / {@effectif}
          <span :if={b.data.mention}>&nbsp;·&nbsp; {b.data.mention.label}</span>
          <span :if={b.data.distinction}>
            &nbsp;·&nbsp; <strong>{TeacherAssistant.Academics.Distinction.label(b.data.distinction)}</strong>
          </span>
        </p>
```

`results_live.ex` — replace the three `<p>` of `#results-distinctions` with one loop:

```heex
          <div id="results-distinctions" class="space-y-1 text-sm">
            <p
              :for={kind <- TeacherAssistant.Academics.Distinction.values()}
              :if={@results.distinctions[kind] != []}
              id={"distinction-#{kind}"}
            >
              <.distinction_badge distinction={kind} />
              {Enum.join(names(@results.distinctions[kind], @roster), ", ")}
            </p>
          </div>
```

(`:for` and `:if` on the same tag: `:if` is evaluated per iteration in HEEx — correct here.) The table's `<.mention_badge :if={row.data.mention} …>` keeps working with the new map.

`marks_summary_live.ex` — delete `@mention_order` and replace `mention_distribution/1` with:

```elixir
  # Appreciation counts, best band first.
  defp mention_distribution(summary) do
    summary.per_student
    |> Map.values()
    |> Enum.reject(&is_nil(&1.mention))
    |> Enum.frequencies_by(& &1.mention)
    |> Enum.sort_by(fn {mention, _count} -> mention.position end, :desc)
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test`
Expected: PASS (the whole suite; Task 1 left the web layer mid-change).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web
git commit -m "feat: report cards and results show the school's appreciations and distinctions"
```

---

### Task 4: Settings page "Appréciations & distinctions"

**Files:**
- Create: `lib/teacher_assistant_web/live/school/appreciations_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex:136` (route after evaluations)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex:346-352` (link after `#evaluations-link`)
- Modify: `lib/teacher_assistant_web/spaces.ex:92,109,238-245` (menu item in the Proviseur and Censeur "Paramètres" sections)
- Test: create `test/teacher_assistant_web/live/school/appreciations_live_test.exs`; check `test/teacher_assistant_web/spaces_test.exs`, `test/teacher_assistant_web/live/role_spaces_test.exs`

**Interfaces:**
- Consumes: `Assessment.grading_rules/1`, `update_appreciation_bands/2`, `reset_appreciation_bands/1`, `update_distinction_rules/2` (Task 2); `Appreciations.bands/1`, `appreciation/2`; `Distinction.label/1`; `GradingRules` (Task 1).
- Produces: route `/school/settings/appreciations`; DOM ids used by tests: `#appreciations-link` (settings page), `#bands-form`, `#band-<i>-to`, `#band-<i>-label`, `#remove-band-<i>`, `#split-last-band`, `#save-bands`, `#reset-bands`, `#band-test-form`, `#band-test-result`, `#bands-error`, `#distinctions-form`, `#distinctions-error`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/appreciations_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.AppreciationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Assessment, Organization}
  alias TeacherAssistant.Academics.Appreciations

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée A"})

    scope = school_scope(user, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
    _year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope}
  end

  test "settings links to the page, which shows the default scale and thresholds", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#appreciations-link")

    {:ok, view, html} = live(conn, ~p"/school/settings/appreciations")
    assert html =~ "Très insuffisant"
    assert html =~ "Excellent"
    assert has_element?(view, "#band-7-label")
    refute has_element?(view, "#band-7-to")
    assert has_element?(view, "#distinctions-form input[name='distinctions[felicitations_min]'][value='16']")
  end

  test "test a mark against the scale being edited", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    view |> form("#band-test-form", %{test: "13,5"}) |> render_change()
    assert render(element(view, "#band-test-result")) =~ "Assez bien"
  end

  test "edit, split, remove and save the scale", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view |> element("#remove-band-0") |> render_click()
    view |> element("#split-last-band") |> render_click()

    view
    |> form("#bands-form", %{"bands" => %{"7" => %{"label" => "Remarquable"}}})
    |> render_change()

    view |> element("#save-bands") |> render_click()
    assert render(view) =~ "Barème enregistré."

    labels = Assessment.grading_rules(scope) |> Appreciations.bands() |> Enum.map(& &1.label)
    # first band removed (now "Insuffisant" starts at 0), last split in two
    assert hd(labels) == "Insuffisant"
    assert length(labels) == 8
    assert "Remarquable" in labels
  end

  test "an invalid scale is refused with a message and nothing is saved", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view
    |> form("#bands-form", %{"bands" => %{"0" => %{"to" => "12"}, "1" => %{"to" => "9"}}})
    |> render_change()

    view |> element("#save-bands") |> render_click()
    assert render(element(view, "#bands-error")) =~ "croissantes"
    assert {:ok, %{appreciation_bands: bands}} = Accounts.fetch_school_profile(scope)
    assert bands in [nil, []]
  end

  test "thresholds and toggles save; a bad order shows an error", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view
    |> form("#distinctions-form", %{
      "distinctions" => %{
        "felicitations_min" => "17",
        "blame_travail_below" => "",
        "distinctions_require_conduct?" => "true"
      }
    })
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    rules = Assessment.grading_rules(scope)
    assert Decimal.equal?(rules.felicitations_min, 17)
    assert rules.blame_travail_below == nil
    assert rules.distinctions_require_conduct?

    view
    |> form("#distinctions-form", %{"distinctions" => %{"encouragements_min" => "19"}})
    |> render_submit()

    assert render(element(view, "#distinctions-error")) =~ "Félicitations"
  end

  test "reset goes back to the default scale", %{conn: conn, scope: scope} do
    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [%{from: "0", label: "X"}, %{from: "10", label: "Y"}])

    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    view |> element("#reset-bands") |> render_click()
    assert render(view) =~ "Très insuffisant"
    assert Assessment.grading_rules(scope) |> Appreciations.bands() |> length() == 8
  end

  test "saved labels show as typed in English", %{conn: conn, scope: scope} do
    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [%{from: "0", label: "Faible"}, %{from: "10", label: "Admis"}])

    conn = Plug.Conn.put_session(conn, :locale, "en")
    {:ok, _view, html} = live(conn, ~p"/school/settings/appreciations")
    assert html =~ "Faible"
    assert html =~ "Admis"
  end
end
```

Also add a test that a teacher without the admin axis is redirected: create a second user as a plain teacher member, following how `test/teacher_assistant_web/live/school/evaluations_live_test.exs` or `coefficients_live_test.exs` tests non-admin access (copy that test's member setup), and assert `{:error, {:live_redirect, %{to: "/school/settings"}}} = live(teacher_conn, ~p"/school/settings/appreciations")`.

(The locale lives in the session under `:locale` — `lib/teacher_assistant_web/plug/locale.ex:9`; `test/teacher_assistant_web/locale_test.exs` switches it with `get(conn, ~p"/locale/en")`, which also works here instead of `put_session`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/teacher_assistant_web/live/school/appreciations_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Implement**

Router, after the evaluations route:

```elixir
      live "/school/settings/appreciations", School.AppreciationsLive, :index
```

`settings_live.ex`, after the `#evaluations-link` link:

```heex
          <.link
            id="appreciations-link"
            navigate={~p"/school/settings/appreciations"}
            class="link link-primary text-sm"
          >
            {gettext("Appréciations & distinctions")}
          </.link>
```

`spaces.ex`: add `appreciations()` after `evaluations()` in both "Paramètres" sections (lines 92 and 109), and the helper after `evaluations/0`:

```elixir
  defp appreciations,
    do:
      item(
        "appreciations",
        gettext("Appréciations & distinctions"),
        "hero-academic-cap",
        ~p"/school/settings/appreciations"
      )
```

`lib/teacher_assistant_web/live/school/appreciations_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.AppreciationsLive do
  @moduledoc """
  Settings → Appréciations & distinctions (spec I1): the school's appreciation scale
  (editable bands, mockup "Paramètres · Appréciations") and the distinction and
  work-warning thresholds with their two gates. The scale is edited locally and saved
  as a whole; the thresholds save as one form.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.{Appreciations, Distinction, GradingRules}

  @twenty Decimal.new(20)

  # {distinction, profile field, comparison shown}
  @thresholds [
    {:felicitations, :felicitations_min, "≥"},
    {:encouragements, :encouragements_min, "≥"},
    {:tableau_honneur, :tableau_honneur_min, "≥"},
    {:avertissement_travail, :avertissement_travail_below, "<"},
    {:blame_travail, :blame_travail_below, "<"}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok,
       socket
       |> assign(thresholds: @thresholds, test: "", bands_error: nil, distinctions_error: nil)
       |> load_rules(Assessment.grading_rules(scope))}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load_rules(socket, %GradingRules{} = rules),
    do: assign(socket, rules: rules, rows: rows_from(Appreciations.bands(rules)))

  # Editor rows hold what the user edits: each row's upper bound ("À (exclu)", a
  # string; nil on the last row) and its label. A row's lower bound is the previous
  # row's upper bound (0 for the first).
  defp rows_from(bands) do
    uppers = bands |> Enum.drop(1) |> Enum.map(&show(&1.from))
    Enum.zip_with(bands, uppers ++ [nil], fn band, to -> %{to: to, label: band.label} end)
  end

  defp lower_bounds(rows), do: ["0" | rows |> Enum.drop(-1) |> Enum.map(& &1.to)]

  defp band_rows(rows) do
    rows
    |> lower_bounds()
    |> Enum.zip_with(rows, fn from, row -> %{from: from || "", label: row.label} end)
  end

  defp show(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp parse(text) when is_binary(text) do
    case text |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp parse(_), do: nil

  # The scale being edited, for the test box and the bar; nil when a bound is not a number.
  defp draft_rules(rows) do
    bands = band_rows(rows)
    froms = Enum.map(bands, &parse(&1.from))

    if Enum.all?(froms, & &1),
      do: %GradingRules{
        appreciation_bands: Enum.zip_with(froms, bands, &%{from: &1, label: &2.label})
      }
  end

  defp test_result(rows, test) do
    with %Decimal{} = mark <- parse(test),
         %GradingRules{} = rules <- draft_rules(rows) do
      Appreciations.appreciation(mark, rules).label
    else
      _ -> nil
    end
  end

  # Bar segments: {label, width share} from the draft scale.
  defp segments(rows) do
    case draft_rules(rows) do
      nil ->
        []

      rules ->
        bands = Appreciations.bands(rules)
        uppers = bands |> Enum.drop(1) |> Enum.map(& &1.from)

        Enum.zip_with(bands, uppers ++ [@twenty], fn band, upper ->
          width = upper |> Decimal.sub(band.from) |> Decimal.max(Decimal.new(0))
          {band.label, Decimal.to_float(width) / 20 * 100}
        end)
    end
  end

  defp threshold_value(rules, field) do
    case Map.fetch!(rules, field) do
      nil -> ""
      d -> show(d)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="appreciations" class="space-y-6">
        <.page_header
          eyebrow={gettext("Paramètres")}
          title={gettext("Appréciations & distinctions")}
        />

        <div class="rounded-box border border-base-300 bg-base-100 p-4 space-y-4">
          <h2 class="ta-eyebrow">{gettext("Appréciation selon la note (sur 20)")}</h2>

          <div class="flex h-8 overflow-hidden rounded-field border border-base-300">
            <div
              :for={{label, pct} <- segments(@rows)}
              class="flex items-center justify-center truncate border-r border-base-100 bg-primary/15 px-1 text-xs last:border-r-0"
              style={"width: #{pct}%"}
              title={label}
            >
              {if pct >= 10, do: label}
            </div>
          </div>

          <.form for={%{}} as={:bands} id="bands-form" phx-change="edit_bands" class="space-y-2">
            <div class="grid grid-cols-[4rem_1rem_5rem_1fr_2rem] gap-2 text-xs text-base-content/60">
              <span>{gettext("De")}</span><span></span><span>{gettext("À (exclu)")}</span>
              <span>{gettext("Appréciation")}</span><span></span>
            </div>
            <div
              :for={{{row, from}, i} <- Enum.with_index(Enum.zip(@rows, lower_bounds(@rows)))}
              class="grid grid-cols-[4rem_1rem_5rem_1fr_2rem] items-center gap-2"
            >
              <span class="ta-num text-sm">{from}</span>
              <span class="text-base-content/40">→</span>
              <.input
                :if={row.to}
                id={"band-#{i}-to"}
                name={"bands[#{i}][to]"}
                value={row.to}
                inputmode="decimal"
                class="input input-sm w-20 text-right"
              />
              <span :if={is_nil(row.to)} class="ta-num text-sm">20</span>
              <.input
                id={"band-#{i}-label"}
                name={"bands[#{i}][label]"}
                value={row.label}
                class="input input-sm w-full"
              />
              <button
                :if={length(@rows) > 1}
                id={"remove-band-#{i}"}
                type="button"
                phx-click="remove_band"
                phx-value-index={i}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Supprimer")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </.form>

          <p :if={@bands_error} id="bands-error" class="text-sm text-error">{@bands_error}</p>

          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-wrap gap-2">
              <button id="split-last-band" type="button" phx-click="split_last" class="btn btn-ghost btn-sm">
                {gettext("+ Scinder la dernière tranche")}
              </button>
              <button id="reset-bands" type="button" phx-click="reset_bands" class="btn btn-ghost btn-sm">
                {gettext("Rétablir le barème par défaut")}
              </button>
              <button id="save-bands" type="button" phx-click="save_bands" class="btn btn-primary btn-sm">
                {gettext("Enregistrer le barème")}
              </button>
            </div>
            <.form for={%{}} id="band-test-form" phx-change="test_mark" class="flex items-center gap-2">
              <span class="text-xs text-base-content/60">{gettext("Tester une note")}</span>
              <.input name="test" value={@test} inputmode="decimal" class="input input-sm w-20 text-right" />
              <span id="band-test-result" class="text-sm font-semibold">
                {test_result(@rows, @test) || "—"}
              </span>
            </.form>
          </div>
        </div>

        <.form
          for={%{}}
          as={:distinctions}
          id="distinctions-form"
          phx-submit="save_distinctions"
          class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
        >
          <h2 class="ta-eyebrow">{gettext("Distinctions et sanctions de travail")}</h2>
          <p class="text-xs text-base-content/60">
            {gettext("Seuils sur la moyenne de la période. Laisser vide pour ne pas l'attribuer.")}
          </p>
          <div :for={{kind, field, op} <- @thresholds} class="flex items-center gap-3">
            <span class="flex-1"><.distinction_badge distinction={kind} /></span>
            <span class="ta-num text-sm text-base-content/60">{op}</span>
            <.input
              name={"distinctions[#{field}]"}
              value={threshold_value(@rules, field)}
              inputmode="decimal"
              class="input input-sm w-20 text-right"
            />
          </div>
          <.input
            type="checkbox"
            name="distinctions[distinctions_require_all_passed?]"
            checked={@rules.distinctions_require_all_passed?}
            label={gettext("Distinctions seulement si toutes les matières sont ≥ 10")}
          />
          <.input
            type="checkbox"
            name="distinctions[distinctions_require_conduct?]"
            checked={@rules.distinctions_require_conduct?}
            label={gettext("Distinctions soumises à une conduite ≥ 12")}
          />
          <p :if={@distinctions_error} id="distinctions-error" class="text-sm text-error">
            {@distinctions_error}
          </p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("edit_bands", %{"bands" => params}, socket) do
    rows =
      socket.assigns.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        p = Map.get(params, Integer.to_string(i), %{})

        %{
          to: if(row.to, do: Map.get(p, "to", row.to), else: nil),
          label: Map.get(p, "label", row.label)
        }
      end)

    {:noreply, assign(socket, rows: rows, bands_error: nil)}
  end

  def handle_event("edit_bands", _params, socket), do: {:noreply, socket}

  def handle_event("remove_band", %{"index" => index}, socket) do
    rows = socket.assigns.rows

    rows =
      case Integer.parse(index) do
        {i, ""} when length(rows) > 1 and i >= 0 and i < length(rows) ->
          rows |> List.delete_at(i) |> close_last()

        _ ->
          rows
      end

    {:noreply, assign(socket, rows: rows, bands_error: nil)}
  end

  def handle_event("split_last", _params, socket) do
    rows = socket.assigns.rows

    case rows |> lower_bounds() |> List.last() |> parse() do
      %Decimal{} = from ->
        mid = from |> Decimal.add(@twenty) |> Decimal.div(2) |> Decimal.round(2)
        {last, rest} = List.pop_at(rows, -1)
        new_rows = rest ++ [%{last | to: show(mid)}, %{to: nil, label: gettext("Nouvelle tranche")}]
        {:noreply, assign(socket, rows: new_rows, bands_error: nil)}

      nil ->
        {:noreply, assign(socket, bands_error: gettext("Corrigez d'abord les bornes."))}
    end
  end

  def handle_event("test_mark", %{"test" => test}, socket),
    do: {:noreply, assign(socket, test: test)}

  def handle_event("save_bands", _params, socket) do
    scope = socket.assigns.current_scope

    socket.assigns.rows
    |> band_rows()
    |> then(&Assessment.update_appreciation_bands(scope, &1))
    |> after_save(socket, :bands_error, gettext("Barème enregistré."))
  end

  def handle_event("reset_bands", _params, socket) do
    socket.assigns.current_scope
    |> Assessment.reset_appreciation_bands()
    |> after_save(socket, :bands_error, gettext("Barème par défaut rétabli."))
  end

  def handle_event("save_distinctions", %{"distinctions" => params}, socket) do
    socket.assigns.current_scope
    |> Assessment.update_distinction_rules(params)
    |> after_save(socket, :distinctions_error, gettext("Réglage enregistré."))
  end

  defp after_save({:ok, _profile}, socket, error_key, message) do
    rules = Assessment.grading_rules(socket.assigns.current_scope)

    {:noreply,
     socket
     |> load_rules(rules)
     |> assign(error_key, nil)
     |> put_flash(:info, message)}
  end

  defp after_save({:error, %Ash.Error.Forbidden{}}, socket, _key, _message),
    do: {:noreply, Authz.put_not_allowed(socket)}

  defp after_save({:error, :invalid_number}, socket, key, _message),
    do: {:noreply, assign(socket, key, gettext("Utilisez des nombres, par exemple 9,5."))}

  defp after_save({:error, %Ash.Error.Invalid{errors: errors}}, socket, key, _message) do
    message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
    {:noreply, assign(socket, key, message)}
  end

  defp after_save({:error, _other}, socket, key, _message),
    do: {:noreply, assign(socket, key, gettext("Réglage non enregistré."))}

  defp close_last(rows) do
    {last, rest} = List.pop_at(rows, -1)
    rest ++ [%{last | to: nil}]
  end
end
```

Notes for the implementer:
- `Authz` (`TeacherAssistantWeb.Authz`) is aliased by `use TeacherAssistantWeb, :live_view` (`lib/teacher_assistant_web.ex:55`).
- The checkbox `<.input type="checkbox">` in `core_components.ex` renders a hidden `"false"` input before the box, so an unticked box submits `"false"` and a ticked one `"true"`; `update_distinction_rules/2` treats anything but `"true"` as false.
- The test "thresholds and toggles save" submits only some fields: `render_submit` merges them with the form's current values, so the untouched thresholds keep their shown values.
- Error messages from the validation carry no interpolation; if `Map.get(error, :message)` is nil for some error type, `Exception.message/1` is the fallback.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/teacher_assistant_web/live/school/appreciations_live_test.exs test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/role_spaces_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS. If a spaces test lists the exact Proviseur/Censeur "Paramètres" items, add `"appreciations"` after `"evaluations"` there.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web
git commit -m "feat: settings page for appreciations and distinctions"
```

---

### Task 5: Translations, checks and roadmap status

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (I1 status line)

- [ ] **Step 1: Extract and translate**

Run: `mix gettext.extract --merge`
Then fill every empty `msgstr` in `priv/gettext/en/LC_MESSAGES/default.po` for the new msgids. Existing msgstrs stay (Assez bien "Fairly good", Bien "Good", Très bien "Very good", Excellent, Insuffisant "Below average", Passable). New ones: Très insuffisant → "Very poor", Médiocre → "Weak", Félicitations → "Congratulations", Encouragements → "Encouragement", Tableau d'honneur → "Honour roll", Avertissement travail → "Work warning", Blâme travail → "Work reprimand", Appréciations & distinctions → "Appreciations & distinctions", Appréciation → "Remark", others translated literally. Keep any msgstr that already existed (e.g. "Passable", "Bien" from the old badge) unless it is empty.

Run: `grep -c 'msgstr ""$' priv/gettext/en/LC_MESSAGES/default.po` before and after; the count must not grow from the new strings (the file header's own empty msgstr stays).

- [ ] **Step 2: Full checks**

Run: `mix precommit`
Then: `mix compile --warnings-as-errors`
Then: `mix test`
Expected: all green, no warnings. Precommit's format step may rewrite files — include them in the commit.

- [ ] **Step 3: Roadmap status**

In `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, I1 section, change `Status: spec approved 2026-10-01, not implemented.` to `Status: implemented <date> (branch \`i1-appreciations\`, plan \`docs/superpowers/plans/2026-10-01-i1-appreciations-distinctions.md\`); no visual check done.`

- [ ] **Step 4: Commit**

```bash
git add -A priv/gettext docs lib test
git commit -m "chore: I1 translations and status"
```
