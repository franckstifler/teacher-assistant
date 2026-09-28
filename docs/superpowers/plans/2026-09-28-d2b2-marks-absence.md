# D2b-2 — Marks and absence: assessment types, default max, absent marker and rule, optional subjects — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Teachers record `abs`/`abj` separately from "not entered". The school's absence rule (0 by default) drives averages, and make-ups are flagged.
- Assessments get a school type whose weight is copied at creation, plus a school default max.
- Optional subjects let students be exempted.

**Architecture:**
- `Mark` gains a `status` enum. A blank saves as *no row*.
- `GradingRules` gains `absence`, and `Marks.subject_average/3` applies the status table.
- `AssessmentType` is a seeded school catalog. An `Assessment` create change copies the type's weight and the school's default max.
- `Subject.optional?` plus `SubjectExemption` rows (who does *not* take it).
- `Bulletins` carries `makeup_pending` and `exempt` per subject.
- Screens: marks page, Évaluations page, coefficients page, class page, bulletin, results.

**Tech Stack:** Elixir 1.20, Ash 3.33 / AshPostgres 2.13, Phoenix LiveView 1.x, daisyUI, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` § D2b-2

## Plan rulings

- **Mark inputs become `type="text"`** with `inputmode="text"`, `autocapitalize="off"` and `autocomplete="off"`, because a number field cannot hold `abs`/`abj`. Cost: phones show the letter keyboard instead of the numeric keypad.
- **Upsert entries keep their shape** `%{student_id, score}` and gain an optional `status`. `score: nil` without a status now means "not entered", and deletes any existing mark. Every existing caller that passes numbers keeps working.
- **The `GradingRules` struct default is `absence: :excluded`,** the historic behaviour, so pure callers keep today's figures. The stored school default is `:zero`, per the spec.
- **Exemption writes are admin-axis only** (the same policy as assigning teachers), matching every other resource in the codebase, where writes are role-based. A form master sees the "Élèves concernés" count read-only. The spec said "class managers and admins"; this narrows it to admins.
- **Sibling columns on the marks page** show `abs`/`abj` for absent and excused marks.

## Global Constraints

- Migrations: iterate with `mix ash.codegen --dev`, finish with `mix ash.codegen marks_absence` (Task 11); `mix ash.codegen --check` must be clean. No real data exists, so reset with `mix ash.reset && MIX_ENV=test mix ash.reset`. If a named codegen seems to hang, rerun it with `printf 'n\n' |` piped in.
- Status codes accepted in mark fields, trimmed and case-insensitive: `a`/`abs` → `:absent`; `abj` → `:excused`; blank → not entered.
- Absence rule defaults to `:zero`. The default max is 20; it and type weights must be > 0.
- Never `String.to_atom` on input.
- UI copy is French gettext msgids, and every new msgid gets an English msgstr after `mix gettext.extract --merge`. Un-fuzzy any fuzzy entry that matches a new msgid.
- LiveView templates start with `<Layouts.app …>`. Use `<.input>` for form fields, with a string `class` if you override it. No inline `<script>`.
- Run only each task's own test files (plus any file it says it breaks). `mix precommit` and `mix compile --warnings-as-errors` run once, in Task 11.

## Review Focus

1. **A crafted mark value such as `"abx"` in a batch.** The whole batch is rejected with nothing saved, on both the solo and combined paths. Tested in Task 7.
2. **A crafted `set_exemptions` naming a student from another class, or on a non-optional subject.** Refused, nothing written. Tested in Task 5.
3. **Switching the absence rule from `:zero` to `:makeup`.** No stale zeros remain; the bulletin moves from 0-counted to "R". Tested in Task 10.
4. **Unticking "Facultative" while exemptions exist.** Refused, and the classes are named. Tested in Task 5.
5. **A type weight or default max ≤ 0, or a teacher saving types or rules.** Refused, or Forbidden for the teacher. Tested in Tasks 3 and 4.

---

### Task 1: `Mark.status` and blank-as-no-row

**Files:**
- Create: `lib/teacher_assistant/academics/mark_status.ex`
- Modify: `lib/teacher_assistant/academics/mark.ex` (attribute, check constraint, accepts, `upsert_group/3`, pub_sub `:destroy`)
- Modify: `lib/teacher_assistant/assessment.ex` (`upsert_marks/3` and `upsert_marks_all_or_nothing/2` pass `status`; doc)
- Modify: `test/teacher_assistant/academics/mark_test.exs` (the "nil score records absent" test)

**Interfaces:**
- Produces:
  - `Academics.MarkStatus` (`:graded | :absent | :excused`) with `code(:absent) == "abs"`, `code(:excused) == "abj"`.
  - `Mark.status` (default `:graded`).
  - Upsert entries: `%{student_id, score: Decimal.t() | nil, status: :graded | :absent | :excused}`, where `status` is optional:
    - a missing status with a nil score deletes the mark;
    - a missing status with a score means graded;
    - `:absent`/`:excused` store a nil score.

- [ ] **Step 1: Write the failing tests.** In `mark_test.exs`, replace the test `"nil score records absent"` with:

```elixir
  test "a nil score means not entered: no mark is stored, and an existing one is removed",
       %{a: a, s1: s1, scope: scope} do
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: nil}])
    assert Assessment.list_marks(scope, a) == []

    :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: Decimal.new(12)}])
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: nil}])
    assert Assessment.list_marks(scope, a) == []
  end

  test "absent and excused marks are stored without a score", %{a: a, s1: s1, s2: s2, scope: scope} do
    :ok =
      Assessment.upsert_marks(scope, a, [
        %{student_id: s1.id, score: nil, status: :absent},
        %{student_id: s2.id, score: nil, status: :excused}
      ])

    by_student = Map.new(Assessment.list_marks(scope, a), &{&1.student_id, &1})
    assert %{status: :absent, score: nil} = by_student[s1.id]
    assert %{status: :excused, score: nil} = by_student[s2.id]

    :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: Decimal.new(9)}])
    assert %{status: :graded} = Enum.find(Assessment.list_marks(scope, a), &(&1.student_id == s1.id))
  end

  test "a graded mark needs a score and an absence cannot carry one", %{a: a, s1: s1, scope: scope} do
    assert {:error, %Ash.Error.Invalid{}} =
             TeacherAssistant.Academics.Mark
             |> Ash.Changeset.for_create(
               :create,
               %{assessment_id: a.id, student_id: s1.id, score: Decimal.new(5), status: :absent},
               scope: scope
             )
             |> Ash.create()
  end
```

Check that the file's setup provides `s2`; if it doesn't, add a second student in the setup, following its existing `s1` line.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/mark_test.exs`
Expected: FAIL (no `status`; a nil score still stores a row).

- [ ] **Step 3: Implement.**

`lib/teacher_assistant/academics/mark_status.ex`:

```elixir
defmodule TeacherAssistant.Academics.MarkStatus do
  @moduledoc """
  What a stored mark records (spec D2b-2): a score, an unjustified absence (`abs`) or a
  justified one (`abj`). "Not entered yet" is the absence of a mark row.
  """
  use Ash.Type.Enum, values: [:graded, :absent, :excused]

  def code(:absent), do: "abs"
  def code(:excused), do: "abj"
end
```

`mark.ex`:
- In `check_constraints`, add:

```elixir
      check_constraint :status, "marks_status_score_check",
        check: "(status = 'graded') = (score IS NOT NULL)",
        message: "a graded mark needs a score; an absence has none"
```

- Default create accepts `[:score, :status, :assessment_id, :student_id]`; `update :update` accepts `[:score, :status]`.
- Attribute, after `:score`: `attribute :status, TeacherAssistant.Academics.MarkStatus, allow_nil?: false, default: :graded, public?: true`.
- pub_sub: add `publish_all :destroy, ["assessment", :assessment_id]`.
- Replace `upsert_group/3`'s per-entry `result = case …` with:

```elixir
      result =
        case {Map.get(existing, entry.student_id), mark_attrs(entry)} do
          {nil, :blank} ->
            {:ok, nil, []}

          {%__MODULE__{} = mark, :blank} ->
            case Ash.destroy(mark, scope: scope, return_notifications?: true) do
              {:ok, notifications} -> {:ok, nil, notifications}
              :ok -> {:ok, nil, []}
              {:error, reason} -> {:error, reason}
            end

          {nil, attrs} ->
            __MODULE__
            |> Ash.Changeset.for_create(
              :create,
              Map.merge(attrs, %{assessment_id: assessment_id, student_id: entry.student_id}),
              scope: scope
            )
            |> Ash.create(return_notifications?: true)

          {%__MODULE__{} = mark, attrs} ->
            mark
            |> Ash.Changeset.for_update(:update, attrs, scope: scope)
            |> Ash.update(return_notifications?: true)
        end
```

and add:

```elixir
  # An upsert entry's stored attributes, or :blank ("not entered": no row).
  defp mark_attrs(%{status: status}) when status in [:absent, :excused],
    do: %{status: status, score: nil}

  defp mark_attrs(entry) do
    case Map.get(entry, :score) do
      nil -> :blank
      score -> %{status: :graded, score: score}
    end
  end
```

`assessment.ex`: in both `upsert_marks/3` and `upsert_marks_all_or_nothing/2`, build each entry as `%{assessment_id: …, student_id: entry.student_id, score: Map.get(entry, :score), status: Map.get(entry, :status)}`, and in `Mark`'s `upsert_group/3` treat `status: nil` like a missing key. `mark_attrs/1` already does, because its first clause only matches `:absent`/`:excused`. Update `upsert_marks/3`'s doc: "A `nil` score is 'not entered' and removes any existing mark; `status: :absent | :excused` records an absence."

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/mark_test.exs test/teacher_assistant_web/live/teacher/`
Expected: PASS. If a marks-page test asserted that a blank field stores a nil-score row, update it to "no row".

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test priv/repo/migrations priv/resource_snapshots
git commit -m "feat: marks record absent and excused; a blank is not entered

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Absence rule in the calculation, make-up flags

**Files:**
- Modify: `lib/teacher_assistant/academics/grading_rules.ex` (field `absence`)
- Modify: `lib/teacher_assistant/academics/marks.ex` (`subject_average/3`, `makeup_pending?/2`)
- Test: `test/teacher_assistant/academics/absence_rules_test.exs`

**Interfaces:**
- Consumes: `MarkStatus` (Task 1).
- Produces:
  - `%GradingRules{absence: :zero | :excluded | :makeup}`, struct default `:excluded`.
  - `Marks.subject_average(marks, weights, rules \\ %GradingRules{})`. `marks` entries may carry `status`, and a missing status is `:graded` when a score is present.
  - `Marks.makeup_pending?(marks, rules) :: boolean`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.AbsenceRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{GradingRules, Marks}

  defp d(x), do: Decimal.new(x)
  @w %{"a" => %{weight: d(1), max_score: d(20)}, "b" => %{weight: d(1), max_score: d(20)}}

  defp marks(b_status),
    do: [
      %{assessment_id: "a", score: d(14), status: :graded},
      %{assessment_id: "b", score: nil, status: b_status}
    ]

  test "absent counts as zero only under the zero rule" do
    assert Decimal.equal?(Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :zero}), 7)
    assert Decimal.equal?(Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :excluded}), 14)
    assert Decimal.equal?(Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :makeup}), 14)
  end

  test "excused is always left out" do
    for rule <- [:zero, :excluded, :makeup] do
      assert Decimal.equal?(Marks.subject_average(marks(:excused), @w, %GradingRules{absence: rule}), 14)
    end
  end

  test "an absence alone under the zero rule gives 0, otherwise no average" do
    only = [%{assessment_id: "a", score: nil, status: :absent}]
    assert Decimal.equal?(Marks.subject_average(only, @w, %GradingRules{absence: :zero}), 0)
    assert Marks.subject_average(only, @w, %GradingRules{absence: :excluded}) == nil
  end

  test "marks without a status keep working (graded when scored)" do
    assert Decimal.equal?(Marks.subject_average([%{assessment_id: "a", score: d(12)}], @w), 12)
  end

  test "make-ups are pending only under the make-up rule, for absent or excused" do
    makeup = %GradingRules{absence: :makeup}
    assert Marks.makeup_pending?(marks(:absent), makeup)
    assert Marks.makeup_pending?(marks(:excused), makeup)
    refute Marks.makeup_pending?(marks(:absent), %GradingRules{absence: :zero})
    refute Marks.makeup_pending?([%{assessment_id: "a", score: d(1), status: :graded}], makeup)
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/absence_rules_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement.** In `grading_rules.ex`, add `absence: :excluded` to `defstruct`, and add to the moduledoc: "`absence` (`:zero | :excluded | :makeup`) decides what an unjustified absence counts; its struct default is the historic `:excluded`."

In `marks.ex`, replace `subject_average/2` with:

```elixir
  @doc """
  Weighted /20 average for one student in one subject/séquence, under the school's
  absence rule. `marks` = `[%{assessment_id, score, status}]` (`status` optional:
  graded when a score is present); `weights` = `%{assessment_id => %{weight, max_score}}`.
  Graded marks count; an `:absent` mark counts as 0 under `absence: :zero` and is left
  out otherwise; an `:excused` mark is always left out. Returns nil when nothing counts.
  """
  def subject_average(marks, weights, rules \\ %GradingRules{}) do
    contributions =
      marks
      |> Enum.flat_map(&counted_score(&1, rules))
      |> Enum.map(fn {assessment_id, score} ->
        a = Map.fetch!(weights, assessment_id)
        normalized = Decimal.div(Decimal.mult(score, @scale), a.max_score)
        {Decimal.mult(normalized, a.weight), a.weight}
      end)

    case contributions do
      [] ->
        nil

      list ->
        total = Enum.reduce(list, Decimal.new(0), fn {c, _w}, acc -> Decimal.add(acc, c) end)
        weight = Enum.reduce(list, Decimal.new(0), fn {_c, w}, acc -> Decimal.add(acc, w) end)
        if Decimal.equal?(weight, Decimal.new(0)), do: nil, else: Decimal.div(total, weight)
    end
  end

  @doc "Whether a make-up is expected: the make-up rule and an absent or excused mark."
  def makeup_pending?(marks, %GradingRules{absence: :makeup}),
    do: Enum.any?(marks, &(status(&1) in [:absent, :excused]))

  def makeup_pending?(_marks, _rules), do: false

  defp counted_score(mark, rules) do
    case {status(mark), rules.absence} do
      {:graded, _} -> [{mark.assessment_id, mark.score}]
      {:absent, :zero} -> [{mark.assessment_id, Decimal.new(0)}]
      _ -> []
    end
  end

  defp status(%{status: status}) when not is_nil(status), do: status
  defp status(%{score: nil}), do: :blank
  defp status(_mark), do: :graded
```

`status/1` returns `:blank` for legacy `score: nil` entries without a status, which fall through `counted_score/2`'s `_` clause and are left out. That's today's behaviour.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/absence_rules_test.exs test/teacher_assistant/academics/marks_test.exs test/teacher_assistant/academics/marks_rules_test.exs test/teacher_assistant/academics/bulletins_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/grading_rules.ex lib/teacher_assistant/academics/marks.ex test/teacher_assistant/academics/absence_rules_test.exs
git commit -m "feat: absence rule in subject averages, make-up flags

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: School absence rule and default max

**Files:**
- Create: `lib/teacher_assistant/academics/absence_rule.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes, update accept list, check constraint)
- Modify: `lib/teacher_assistant/assessment.ex` (`grading_rules/1` sets `absence`; `@rule_fields` gains `"absence_rule"`; add `update_default_max_score/2`)
- Test: append to `test/teacher_assistant/academics/grading_settings_test.exs`

**Interfaces:**
- Produces:
  - `Academics.AbsenceRule` (`:zero | :excluded | :makeup`, each with `label/1`).
  - `SchoolProfile.absence_rule` (default `:zero`) and `SchoolProfile.default_max_score` (default 20, > 0).
  - `Assessment.update_grading_rules/2` accepts `"absence_rule"`.
  - `Assessment.update_default_max_score(scope, String.t()) :: {:ok, profile} | {:error, :invalid_max} | {:error, term}`.

- [ ] **Step 1: Write the failing tests** (append to `GradingSettingsTest`):

```elixir
  test "absence rule defaults to zero and can be changed", %{scope: scope} do
    assert Assessment.grading_rules(scope).absence == :zero
    {:ok, _} = Assessment.update_grading_rules(scope, %{"absence_rule" => "makeup"})
    assert Assessment.grading_rules(scope).absence == :makeup
    assert {:error, :invalid_rule} = Assessment.update_grading_rules(scope, %{"absence_rule" => "ignore"})
  end

  test "the default maximum mark must be positive", %{scope: scope} do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert Decimal.equal?(profile.default_max_score, 20)
    assert {:ok, %{default_max_score: max}} = Assessment.update_default_max_score(scope, "10")
    assert Decimal.equal?(max, 10)
    assert {:error, :invalid_max} = Assessment.update_default_max_score(scope, "0")
    assert {:error, :invalid_max} = Assessment.update_default_max_score(scope, "abc")
  end
```

Update the existing defaults test: the expected struct gains `absence: :zero`.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/grading_settings_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement.**

`absence_rule.ex`:

```elixir
defmodule TeacherAssistant.Academics.AbsenceRule do
  use Ash.Type.Enum, values: [:zero, :excluded, :makeup]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:zero), do: gettext("Zéro")
  def label(:excluded), do: gettext("Non noté (exclu du calcul)")
  def label(:makeup), do: gettext("Rattrapage obligatoire")
end
```

`school_profile.ex`: after `shared_ranks?`, add:

```elixir
    attribute :absence_rule, TeacherAssistant.Academics.AbsenceRule,
      allow_nil?: false,
      default: :zero,
      public?: true

    attribute :default_max_score, :decimal,
      allow_nil?: false,
      default: Decimal.new(20),
      public?: true
```

Append `:absence_rule, :default_max_score` to the `update :update` accept list. In `postgres do`, add (creating a `check_constraints` block if there is none):

```elixir
    check_constraints do
      check_constraint :default_max_score, "school_profiles_default_max_positive_check",
        check: "default_max_score > 0",
        message: "must be positive"
    end
```

`assessment.ex`:
- In `grading_rules/1`, add `absence: profile.absence_rule`.
- Add `"absence_rule" => {:absence_rule, AbsenceRule}` to `@rule_fields`, and `AbsenceRule` to the alias list.
- Add:

```elixir
  @doc "Sets the school's default maximum mark for new assessments (a positive number)."
  def update_default_max_score(%Scope{} = scope, value) when is_binary(value) do
    with {:ok, max} <- TeacherAssistant.Curriculum.parse_coefficient(value),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, %{default_max_score: max}, scope: scope)
    else
      :error -> {:error, :invalid_max}
      other -> other
    end
  end
```

(`parse_coefficient/1` is the shared positive-decimal parser, and it accepts `,`.)

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/grading_settings_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/grading_settings_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: school absence rule and default maximum mark

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Assessment types, and weight and max copied at creation

**Files:**
- Create: `lib/teacher_assistant/academics/assessment_type.ex`
- Create: `lib/teacher_assistant/academics/assessment/apply_defaults.ex`
- Modify: `lib/teacher_assistant/academics/assessment.ex` (resource: `assessment_type_id`, create accept, the change; `:create_combined` takes `assessment_type_id` and `max_score`)
- Modify: `lib/teacher_assistant/academics/reference.ex` (`default_assessment_types/0`)
- Modify: `lib/teacher_assistant/academics/workspace.ex` (`seed_assessment_types/1` in `create_school`)
- Modify: `lib/teacher_assistant/assessment.ex` (domain: register the resource; `list_assessment_types/1`, `create_assessment_type/2`, `update_assessment_type/3`, `delete_assessment_type/2`; `create_combined_assessment/4` passes the new attrs)
- Test: `test/teacher_assistant/academics/assessment_types_test.exs`

**Interfaces:**
- Consumes: `SchoolProfile.default_max_score` (Task 3).
- Produces:
  - `AssessmentType`: `name`, `default_weight` (> 0), `position`. Unique name per school. Read by members, written by admins.
  - `Assessment.assessment_type_id` (nullable).
  - The `Assessment :create` change: when `assessment_type_id` is set and `weight` isn't given, the weight is copied from the type; when `max_score` isn't given, it comes from the school's `default_max_score`.
  - `Assessment.list_assessment_types(scope) :: [%AssessmentType{}]`, sorted by position and name, each with `usage_count`.
  - `create_assessment_type(scope, %{name, default_weight})`, `update_assessment_type(scope, type, attrs)`, and `delete_assessment_type(scope, type) :: :ok | {:error, :in_use} | {:error, term}`.
  - `create_combined_assessment(scope, course, seq, %{label, assessment_type_id, max_score})`, where the last two are optional.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.AssessmentTypesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    %{scope: scope, seq: seq, tc: tc}
  end

  test "a school starts with the three usual types", %{scope: scope} do
    assert [{"Interrogation écrite", "0.5"}, {"Devoir surveillé", "1"}, {"Travaux pratiques", "0.5"}] =
             Enum.map(Assessment.list_assessment_types(scope), &{&1.name, Decimal.to_string(Decimal.normalize(&1.default_weight), :normal)})
  end

  test "an assessment of a type copies its weight; changing the type later does not", ctx do
    [ie | _] = Assessment.list_assessment_types(ctx.scope)
    {:ok, a} = Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{label: "IE 1", assessment_type_id: ie.id})
    assert Decimal.equal?(a.weight, Decimal.new("0.5"))

    {:ok, _} = Assessment.update_assessment_type(ctx.scope, ie, %{default_weight: Decimal.new(2)})
    {:ok, reloaded} = Assessment.fetch_owned_assessment(ctx.scope, a.id)
    assert Decimal.equal?(reloaded.weight, Decimal.new("0.5"))
  end

  test "the school's default maximum applies when none is given", ctx do
    {:ok, _} = Assessment.update_default_max_score(ctx.scope, "10")
    {:ok, a} = Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{label: "Quiz"})
    assert Decimal.equal?(a.max_score, 10)
  end

  test "a used type cannot be deleted; an unused one can", ctx do
    [ie, ds | _] = Assessment.list_assessment_types(ctx.scope)
    {:ok, _} = Assessment.create_assessment(ctx.scope, ctx.tc, ctx.seq, %{label: "IE 1", assessment_type_id: ie.id})
    assert {:error, :in_use} = Assessment.delete_assessment_type(ctx.scope, ie)
    assert :ok = Assessment.delete_assessment_type(ctx.scope, ds)
  end

  test "a type weight must be positive; teachers cannot manage types", %{scope: scope} do
    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.create_assessment_type(scope, %{name: "Oral", default_weight: Decimal.new(0)})

    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert_forbidden(Assessment.create_assessment_type(teacher, %{name: "Oral", default_weight: Decimal.new(1)}))
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/assessment_types_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement.**

`lib/teacher_assistant/academics/assessment_type.ex`:

```elixir
defmodule TeacherAssistant.Academics.AssessmentType do
  @moduledoc """
  A school's kind of assessment (interrogation écrite, devoir surveillé…) and its default
  weight. The weight is copied onto an assessment when it is created, so changing a type
  never alters tests already given (spec D2b-2).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "assessment_types"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true
    end

    custom_indexes do
      # Composite-FK target for `Assessment.assessment_type_id`.
      index [:id], unique: true
    end

    check_constraints do
      check_constraint :default_weight, "assessment_types_weight_positive_check",
        check: "default_weight > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :default_weight, :position],
      update: [:name, :default_weight, :position]
    ]
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [trim?: true]
    attribute :default_weight, :decimal, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, default: 0, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :assessments, TeacherAssistant.Academics.Assessment
  end

  aggregates do
    count :usage_count, :assessments do
      public? true
    end
  end

  identities do
    identity :unique_type_name, [:workspace_id, :name]
  end
end
```

`lib/teacher_assistant/academics/assessment/apply_defaults.ex`:

```elixir
defmodule TeacherAssistant.Academics.Assessment.ApplyDefaults do
  @moduledoc """
  On create: copies the assessment type's `default_weight` when no weight was given,
  and the school's `default_max_score` when no maximum was given (spec D2b-2).
  """
  use Ash.Resource.Change
  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.AssessmentType

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      changeset
      |> default_weight(context)
      |> default_max(changeset.tenant)
    end)
  end

  defp default_weight(changeset, context) do
    type_id = Ash.Changeset.get_attribute(changeset, :assessment_type_id)

    if type_id && not Ash.Changeset.changing_attribute?(changeset, :weight) do
      case Ash.get(AssessmentType, type_id, scope: context) do
        {:ok, type} -> Ash.Changeset.force_change_attribute(changeset, :weight, type.default_weight)
        _ -> Ash.Changeset.add_error(changeset, field: :assessment_type_id, message: "is not a type of this school")
      end
    else
      changeset
    end
  end

  defp default_max(changeset, tenant) do
    if Ash.Changeset.changing_attribute?(changeset, :max_score) do
      changeset
    else
      case SchoolProfile |> Ash.Query.filter(workspace_id == ^tenant) |> Ash.read_one!(authorize?: false) do
        %{default_max_score: max} -> Ash.Changeset.force_change_attribute(changeset, :max_score, max)
        nil -> changeset
      end
    end
  end
end
```

`Assessment` resource (`academics/assessment.ex`):
- Add `:assessment_type_id` to the default `create` accept list.
- Replace the default create with an explicit one so the change can be attached. Remove `create: [...]` from `defaults` and add:

```elixir
    create :create do
      primary? true
      accept [:label, :weight, :max_score, :given_on, :teaching_context_id, :sequence_id, :assessment_type_id]
      change TeacherAssistant.Academics.Assessment.ApplyDefaults
    end
```

- In `references`: `reference :assessment_type, match_with: [workspace_id: :workspace_id], match_type: :simple, index?: true`.
- In `relationships`: `belongs_to :assessment_type, TeacherAssistant.Academics.AssessmentType do source_attribute :assessment_type_id; allow_nil? true; public? true end`.
- `:create_combined`: add `argument :assessment_type_id, :uuid, allow_nil?: true` and `argument :max_score, :decimal, allow_nil?: true`. Pass both to `create_assessment/…`, which becomes `create_assessment(ctx, seq, attrs, scope)` with `attrs = %{label: …}`, adding `assessment_type_id`/`max_score` only when they're non-nil (so `ApplyDefaults` still fills the defaults):

```elixir
      run fn input, scope ->
        %{course: course, sequence: seq, label: label} = input.arguments

        attrs =
          %{label: label}
          |> put_present(:assessment_type_id, input.arguments[:assessment_type_id])
          |> put_present(:max_score, input.arguments[:max_score])

        contexts = course_member_contexts(course, scope)

        Enum.reduce_while(contexts, {:ok, []}, fn ctx, {:ok, acc} ->
          case create_assessment(ctx, seq, attrs, scope) do
            {:ok, assessment} -> {:cont, {:ok, acc ++ [assessment]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
```

```elixir
  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp create_assessment(ctx, seq, attrs, scope) do
    __MODULE__
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{teaching_context_id: ctx.id, sequence_id: seq.id}),
      scope: scope
    )
    |> Ash.create()
  end
```

`reference.ex`:

```elixir
  @doc "The assessment types a new school starts with (mockup 'Évaluations & moyennes')."
  def default_assessment_types do
    [
      %{name: "Interrogation écrite", default_weight: Decimal.new("0.5"), position: 0},
      %{name: "Devoir surveillé", default_weight: Decimal.new(1), position: 1},
      %{name: "Travaux pratiques", default_weight: Decimal.new("0.5"), position: 2}
    ]
  end
```

`workspace.ex`: alias `AssessmentType`. In `create_school`'s `with`, after `:ok <- seed_periods(workspace)`, add `:ok <- seed_assessment_types(workspace)`, and add this helper next to `seed_periods/1`:

```elixir
  defp seed_assessment_types(workspace) do
    Reference.default_assessment_types()
    |> Enum.reduce_while(:ok, fn attrs, :ok ->
      case AssessmentType
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.Changeset.set_tenant(workspace.id)
           |> Ash.create(authorize?: false) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
```

Domain `lib/teacher_assistant/assessment.ex`: add `resource AssessmentType` to its `resources do` block and `AssessmentType` to the alias list. Then add:

```elixir
  # --- Assessment types (spec D2b-2) -----------------------------------------------

  def list_assessment_types(%Scope{} = scope) do
    AssessmentType
    |> Ash.Query.sort(position: :asc, name: :asc)
    |> Ash.Query.load(:usage_count)
    |> Ash.read!(scope: scope)
  end

  def create_assessment_type(%Scope{} = scope, attrs) do
    position = length(list_assessment_types(scope))

    AssessmentType
    |> Ash.Changeset.for_create(:create, Map.put_new(attrs, :position, position), scope: scope)
    |> Ash.create()
  end

  def update_assessment_type(%Scope{} = scope, %AssessmentType{} = type, attrs) do
    type |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  @doc "Deletes a type no assessment uses; a used type is kept (`{:error, :in_use}`)."
  def delete_assessment_type(%Scope{} = scope, %AssessmentType{} = type) do
    case Ash.load!(type, :usage_count, scope: scope) do
      %{usage_count: 0} -> Ash.destroy(type, scope: scope)
      _ -> {:error, :in_use}
    end
  end
```

In `create_combined_assessment/4`, build `args` with `assessment_type_id: Map.get(attrs, :assessment_type_id)` and `max_score: Map.get(attrs, :max_score)` next to `label`.

The domain module needs `require Ash.Query` for `Ash.Query.sort`; add it if it's missing.

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/assessment_types_test.exs test/teacher_assistant/academics/courses_test.exs test/teacher_assistant_web/live/teacher/`
Expected: PASS. If the generated migration creates the `assessments.assessment_type_id` composite FK before the `assessment_types` `(workspace_id, id)` index, stop and report it (see D2a's ordering note). Don't hand-edit the migration.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/assessment_types_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: school assessment types; weight and maximum copied at creation

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Optional subjects and exemptions

**Files:**
- Create: `lib/teacher_assistant/academics/subject_exemption.ex`
- Modify: `lib/teacher_assistant/academics/subject.ex` (`optional?`)
- Modify: `lib/teacher_assistant/curriculum.ex` (register the resource; `exempt_student_ids/2`, `set_exemptions/3`; `update_coefficient_grid/2` accepts `"optional"`)
- Test: `test/teacher_assistant/academics/subject_exemptions_test.exs`

**Interfaces:**
- Consumes: `update_coefficient_grid/2` (D2a).
- Produces:
  - `Subject.optional?` (default false).
  - `SubjectExemption`: `teaching_context_id`, `student_id`, unique on the pair. Read by members; create and destroy by admins.
  - `Curriculum.exempt_student_ids(scope, %TeachingContext{}) :: MapSet.t()`.
  - `Curriculum.set_exemptions(scope, tc, taking_student_ids :: [id]) :: :ok | {:error, :not_optional} | {:error, :unknown_student} | {:error, term}`. It writes the exemptions so that exactly the students of the context's class **not** in `taking_student_ids` are exempted, in one transaction.
  - `update_coefficient_grid/2` params accept `"optional" => %{subject_id => "true" | "false"}`. Switching an optional subject off while exemptions exist is refused: `{:error, {:invalid, %{{:optional, subject_id} => [{:has_exemptions, [class_label]}]}}}`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.SubjectExemptionsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e A", level: "4ème"})
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "4e B", level: "4ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, zoe} = Enrollment.add_student(scope, other, %{full_name: "Zoé", sex: :f})
    {:ok, esp} = Curriculum.create_subject(scope, %{name: "Espagnol"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: esp})
    %{scope: scope, esp: esp, tc: tc, awa: awa, bob: bob, zoe: zoe}
  end

  defp make_optional(scope, subject, on?) do
    Curriculum.update_coefficient_grid(scope, %{"optional" => %{subject.id => to_string(on?)}})
  end

  test "only optional subjects accept exemptions", ctx do
    assert {:error, :not_optional} = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    assert :ok = make_optional(ctx.scope, ctx.esp, true)
    assert :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new([ctx.bob.id])

    assert :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id, ctx.bob.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new()
  end

  test "a student from another class is refused and nothing changes", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    assert {:error, :unknown_student} = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.zoe.id])
    assert Curriculum.exempt_student_ids(ctx.scope, ctx.tc) == MapSet.new()
  end

  test "an optional subject with exemptions cannot be made compulsory again", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])

    assert {:error, {:invalid, errors}} = make_optional(ctx.scope, ctx.esp, false)
    assert errors[{:optional, ctx.esp.id}] == [{:has_exemptions, ["4e A"]}]
  end

  test "a teacher cannot change exemptions", ctx do
    :ok = make_optional(ctx.scope, ctx.esp, true)
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)
    assert_forbidden(Curriculum.set_exemptions(teacher, ctx.tc, [ctx.awa.id]))
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/subject_exemptions_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement.**

`subject.ex`: attribute `attribute :optional?, :boolean, allow_nil?: false, default: false, public?: true`, added to the create and update accept lists.

`lib/teacher_assistant/academics/subject_exemption.ex`:

```elixir
defmodule TeacherAssistant.Academics.SubjectExemption do
  @moduledoc """
  A student who does not take an optional subject in their class (spec D2b-2). Stored as
  an exclusion so a student enrolled later takes every subject by default.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "subject_exemptions"
    repo TeacherAssistant.Repo

    references do
      reference :teaching_context,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:teaching_context_id, :student_id]]
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_exemption, [:teaching_context_id, :student_id]
  end
end
```

If codegen complains that `Student` has no `(workspace_id, id)` unique index, check how `Mark` references `:student` with `match_type: :full` (it does), and follow the same pattern. The index already exists for `Mark`'s reference.

`curriculum.ex`: add `SubjectExemption` to the aliases and `resource SubjectExemption` to `resources`. Then add, in the Teaching-context assignments section:

```elixir
  @doc "Students of `tc`'s class who do not take its (optional) subject."
  def exempt_student_ids(%Scope{} = scope, %TeachingContext{id: tc_id}) do
    SubjectExemption
    |> Ash.Query.filter(teaching_context_id == ^tc_id)
    |> Ash.read!(scope: scope)
    |> MapSet.new(& &1.student_id)
  end

  @doc """
  Sets who takes an optional subject in a class: every student of the class not in
  `taking_ids` is exempted, the others are not. Refused for a compulsory subject
  (`:not_optional`) or an id outside the class (`:unknown_student`); one transaction.
  """
  def set_exemptions(%Scope{} = scope, %TeachingContext{} = tc, taking_ids) when is_list(taking_ids) do
    tc = Ash.load!(tc, [:catalog_subject, :class_group], scope: scope)
    class_ids = scope |> Enrollment.list_students(tc.class_group) |> MapSet.new(& &1.id)
    taking = MapSet.new(taking_ids)

    cond do
      not tc.catalog_subject.optional? ->
        {:error, :not_optional}

      not MapSet.subset?(taking, class_ids) ->
        {:error, :unknown_student}

      true ->
        wanted = MapSet.difference(class_ids, taking)

        existing =
          SubjectExemption
          |> Ash.Query.filter(teaching_context_id == ^tc.id)
          |> Ash.read!(scope: scope)

        Ash.transact([SubjectExemption], fn ->
          with :ok <- destroy_exemptions(Enum.reject(existing, &MapSet.member?(wanted, &1.student_id)), scope) do
            have = MapSet.new(existing, & &1.student_id)
            create_exemptions(tc, MapSet.difference(wanted, have), scope)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, error} -> {:error, error}
        end
    end
  end

  defp destroy_exemptions(exemptions, scope) do
    Enum.reduce_while(exemptions, :ok, fn e, :ok ->
      case Ash.destroy(e, scope: scope) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp create_exemptions(tc, student_ids, scope) do
    Enum.reduce_while(student_ids, :ok, fn sid, :ok ->
      SubjectExemption
      |> Ash.Changeset.for_create(:create, %{teaching_context_id: tc.id, student_id: sid}, scope: scope)
      |> Ash.create()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
```

Loading `:catalog_subject` and `:class_group` on a teacher's scope succeeds, because both are readable by members. The forbidden result comes from the exemption write, which the transaction returns as `{:error, %Ash.Error.Forbidden{}}`. If it comes back wrapped as `Invalid`, unwrap it with `Ash.Error.to_error_class/1`.

`update_coefficient_grid/2`: before `CoefficientRules.validate`, parse `Map.get(params, "optional", %{})` into `optional_changes = %{subject_id => true | false}`, keeping only the school's subject ids and the values `"true"`/`"false"`. Then check that none switches `true → false` while exemptions exist for that subject:

```elixir
    optional_changes = parse_optional_changes(Map.get(params, "optional", %{}), subjects)

    with :ok <- check_optional_changes(optional_changes, subjects, scope),
         :ok <- CoefficientRules.validate(current, cell_changes, group_changes, grid_assignments(scope)),
         {:ok, :ok} <-
           Ash.transact([SubjectCoefficient, Subject], fn ->
             with :ok <- write_cells(cell_changes, stored, scope),
                  :ok <- write_groups(group_changes, subjects, scope) do
               write_optional(optional_changes, subjects, scope)
             end
           end) do
      :ok
    end
```

```elixir
  defp parse_optional_changes(params, subjects) do
    for {subject_id, value} <- params,
        Map.has_key?(subjects, subject_id),
        value in ["true", "false"],
        into: %{},
        do: {subject_id, value == "true"}
  end

  defp check_optional_changes(changes, subjects, scope) do
    errors =
      for {subject_id, false} <- changes,
          subjects[subject_id].optional?,
          labels = exempted_class_labels(subject_id, scope),
          labels != [],
          into: %{},
          do: {{:optional, subject_id}, [{:has_exemptions, labels}]}

    if errors == %{}, do: :ok, else: {:error, {:invalid, errors}}
  end

  defp exempted_class_labels(subject_id, scope) do
    SubjectExemption
    |> Ash.Query.filter(teaching_context.subject_id == ^subject_id)
    |> Ash.Query.load(teaching_context: :class_group)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.teaching_context.class_group.label)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp write_optional(changes, subjects, scope) do
    Enum.reduce_while(changes, :ok, fn {subject_id, optional?}, :ok ->
      subject = subjects[subject_id]

      if subject.optional? == optional? do
        {:cont, :ok}
      else
        case update_subject(scope, subject, %{optional?: optional?}) do
          {:ok, _} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end
    end)
  end
```

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/subject_exemptions_test.exs test/teacher_assistant/academics/coefficient_grid_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/subject_exemptions_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: optional subjects with per-student exemptions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Bulletins: statuses, the absence rule, make-up flags, exemptions

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletins.ex` (`compile/3`, `aggregate/3`)
- Modify: `lib/teacher_assistant/assessment.ex` (`class_subjects/3`, `period_result/4`)
- Test: append to `test/teacher_assistant/academics/bulletins_test.exs` and `test/teacher_assistant/academics/period_results_test.exs`

**Interfaces:**
- Consumes: `Marks.subject_average/3`, `makeup_pending?/2` (Task 2); `exempt_student_ids/2` (Task 5); `grading_rules/1` with `absence` (Task 3).
- Produces:
  - Subject inputs may carry `exempt :: MapSet` (student ids) and `makeup_pending :: %{student_id => boolean}`.
  - `compile/3` computes `makeup_pending` from the subject's marks and rules.
  - Exempt students: their average in that subject is nil, and their `subjects` rows (and group rows) omit it.
  - Each row gains `makeup_pending :: boolean`.
  - The top-level result gains `makeup_pending_count :: non_neg_integer` (rows with a pending make-up, across students).
  - `class_subjects/3` entries carry `marks` with `status` and `exempt`.

- [ ] **Step 1: Write the failing tests.** Append to `bulletins_test.exs` (its `subject/4` helper builds weight-1 /20 marks):

```elixir
  test "the absence rule, make-up flags and exemptions reach the bulletin" do
    students = [%{id: "s1", sex: :f, name: "Awa"}, %{id: "s2", sex: :m, name: "Bob"}]

    maths = %{
      subject("maths", "Maths", "2", [{"s1", "14"}])
      | marks: [
          %{student_id: "s1", assessment_id: "maths-a", score: Decimal.new(14), status: :graded},
          %{student_id: "s2", assessment_id: "maths-a", score: nil, status: :absent}
        ]
    }

    esp = subject("esp", "Espagnol", "1", [{"s1", "10"}]) |> Map.put(:exempt, MapSet.new(["s2"]))

    zero = Bulletins.compile(students, [maths, esp], %GradingRules{absence: :zero})
    assert Decimal.equal?(Enum.find(zero.per_student["s2"].subjects, &(&1.label == "Maths")).average, 0)
    refute Enum.any?(zero.per_student["s2"].subjects, &(&1.label == "Espagnol"))
    assert zero.makeup_pending_count == 0

    makeup = Bulletins.compile(students, [maths, esp], %GradingRules{absence: :makeup})
    row = Enum.find(makeup.per_student["s2"].subjects, &(&1.label == "Maths"))
    assert row.average == nil and row.makeup_pending
    assert makeup.makeup_pending_count == 1
  end
```

Append to `period_results_test.exs`. It checks through the domain that an `abs` mark counts as 0 by default and switches to the "R" flag under the make-up rule:

```elixir
  test "an absence counts 0 by default and is flagged under the make-up rule", ctx do
    %{year: year, cg: cg, sequences: [s1 | _], student: st, grade: grade, scope: scope} = ctx
    grade.(s1, 16)
    [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)

    {:ok, a2} =
      Assessment.create_assessment(scope, tc, s1, %{label: "D2", weight: Decimal.new(1), max_score: Decimal.new(20)})

    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: st.id, score: nil, status: :absent}])

    r = Assessment.class_results_for_period(scope, cg, {:sequence, s1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 8)

    {:ok, _} = Assessment.update_grading_rules(scope, %{"absence_rule" => "makeup"})
    r = Assessment.class_results_for_period(scope, cg, {:sequence, s1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 16)
    assert [%{makeup_pending: true}] = r.per_student[st.id].subjects
    _ = year
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/period_results_test.exs`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement.**

`bulletins.ex`, in `compile/3`: pass the rules to the subject average and compute the flags:

```elixir
        per_student_avg =
          Map.new(students, fn s ->
            student_marks = Enum.filter(subj.marks, &(&1.student_id == s.id))
            {s.id, Marks.subject_average(student_marks, subj.assessments_by_id, rules)}
          end)

        makeup_pending =
          Map.new(students, fn s ->
            student_marks = Enum.filter(subj.marks, &(&1.student_id == s.id))
            {s.id, Marks.makeup_pending?(student_marks, rules)}
          end)
```

and add `exempt: Map.get(subj, :exempt, MapSet.new()), makeup_pending: makeup_pending` to the input map.

In `aggregate/3`:
- In the first rounding pass, also set exempt students' averages to nil:

```elixir
      Enum.map(subject_inputs, fn subj ->
        exempt = Map.get(subj, :exempt, MapSet.new())

        %{
          subj
          | per_student_avg:
              Map.new(subj.per_student_avg, fn {id, avg} ->
                {id, if(MapSet.member?(exempt, id), do: nil, else: GradingRules.round_average(avg, rules))}
              end)
        }
        |> Map.put(:exempt, exempt)
        |> Map.put_new(:makeup_pending, %{})
      end)
```

- Carry `exempt` and `makeup_pending` into each `subject_views` map.
- Per student, build rows only for subjects the student takes: `subject_views |> Enum.reject(&MapSet.member?(&1.exempt, s.id)) |> Enum.map(fn sv -> … end)`. Each row gains `makeup_pending: Map.get(sv.makeup_pending, s.id, false)`.
- In the result map, add:

```elixir
      makeup_pending_count:
        per_student |> Map.values() |> Enum.flat_map(& &1.subjects) |> Enum.count(& &1.makeup_pending),
```

`assessment.ex`:
- In `class_subjects/3`, map marks with `status: m.status`, and add `exempt: TeacherAssistant.Curriculum.exempt_student_ids(scope, tc)` to each entry.
- Pass `rules` to `Marks.subject_average/3` there too. `class_subjects/3` gains a 4th argument `rules \\ nil`; when it's nil, compute `grading_rules(scope)` once at the top.
- In `class_results/3`, the rules already go to `Bulletins.compile/3`, which recomputes averages from the marks. `class_subjects` itself doesn't compute averages; only `period_result/4` does.
- In `period_result/4`:
  - the per-séquence `psa` uses `Marks.subject_average(sm, subj.assessments_by_id, rules)` (then rounded);
  - each per-séquence subject map also stores `makeup: Map.new(students, fn s -> {s.id, Marks.makeup_pending?(sm_for(s), rules)} end)` (compute `sm` once per student and reuse it for both) and `exempt: subj.exempt`;
  - each subject input gets `exempt: meta.exempt` and `makeup_pending: Map.new(students, fn s -> {s.id, Enum.any?(per_seq, fn {_seq, m} -> m[cid] && m[cid].makeup[s.id] end)} end)`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/period_results_test.exs test/teacher_assistant/academics/bulletin_data_test.exs test/teacher_assistant/academics/marks_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/bulletins.ex lib/teacher_assistant/assessment.ex test/teacher_assistant/academics
git commit -m "feat: bulletins apply the absence rule, flag make-ups and skip exempt students

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Marks page: `abs`/`abj`, types, exemptions, pending make-ups

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex` (marks carry `status`; rules already passed)
- Test: `test/teacher_assistant_web/live/teacher/marks_absence_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes:
  - the upsert `status` entries (Task 1);
  - `MarkStatus.code/1`;
  - `list_assessment_types/1` and `SchoolProfile.default_max_score` (Tasks 3–4);
  - `exempt_student_ids/2` (Task 5);
  - `Marks.makeup_pending?/2` and `grading_rules/1`.
- Produces:
  - Mark inputs `#mark-input-<student_id>` become `type="text"`.
  - The new-assessment form `#new-assessment-form` has `assessment[assessment_type_id]` (select), `assessment[label]` and `assessment[max_score]`.
  - `#pending-makeups` lists the students with a pending make-up for the selected assessment, under the make-up rule.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.Teacher.MarksAbsenceTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée M"})
    scope = school_scope(head, school)
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "4e M", level: "4ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, a} = Assessment.create_assessment(scope, tc, seq, %{label: "D1"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    path = ~p"/teacher/contexts/#{tc.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
    %{conn: conn, scope: scope, tc: tc, seq: seq, a: a, awa: awa, bob: bob, path: path}
  end

  test "abs and abj are saved as absences, blank as not entered", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "ABS", ctx.bob.id => "abj"}})
    |> render_submit()

    by_student = Map.new(Assessment.list_marks(ctx.scope, ctx.a), &{&1.student_id, &1.status})
    assert by_student == %{ctx.awa.id => :absent, ctx.bob.id => :excused}
    assert has_element?(view, "#mark-input-#{ctx.awa.id}[value='abs']")

    view |> form("#marks-form", %{"scores" => %{ctx.awa.id => "", ctx.bob.id => "abj"}}) |> render_submit()
    assert [%{status: :excused}] = Assessment.list_marks(ctx.scope, ctx.a)
  end

  test "an unknown code rejects the whole batch", ctx do
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#marks-form", %{"scores" => %{ctx.awa.id => "12", ctx.bob.id => "abx"}})
    |> render_submit()

    assert Assessment.list_marks(ctx.scope, ctx.a) == []
  end

  test "a new assessment takes its type's weight and the school's maximum", ctx do
    [ie | _] = Assessment.list_assessment_types(ctx.scope)
    {:ok, view, _} = live(ctx.conn, ctx.path)

    view
    |> form("#new-assessment-form", %{"assessment" => %{"assessment_type_id" => ie.id, "label" => "IE 1", "max_score" => "10"}})
    |> render_submit()

    created = Enum.find(Assessment.list_assessments(ctx.scope, ctx.tc, ctx.seq), &(&1.label == "IE 1"))
    assert Decimal.equal?(created.weight, Decimal.new("0.5"))
    assert Decimal.equal?(created.max_score, 10)
  end

  test "exempt students are not listed", ctx do
    subject = Enum.find(Curriculum.list_subjects(ctx.scope), &(&1.id == ctx.tc.subject_id))
    :ok = Curriculum.update_coefficient_grid(ctx.scope, %{"optional" => %{subject.id => "true"}})
    :ok = Curriculum.set_exemptions(ctx.scope, ctx.tc, [ctx.awa.id])
    {:ok, view, _} = live(ctx.conn, ctx.path)
    assert has_element?(view, "#mark-row-#{ctx.awa.id}")
    refute has_element?(view, "#mark-row-#{ctx.bob.id}")
  end

  test "under the make-up rule, absent students are listed as pending", ctx do
    {:ok, _} = Assessment.update_grading_rules(ctx.scope, %{"absence_rule" => "makeup"})
    :ok = Assessment.upsert_marks(ctx.scope, ctx.a, [%{student_id: ctx.awa.id, score: nil, status: :absent}])
    {:ok, view, _} = live(ctx.conn, ctx.path)
    assert has_element?(view, "#pending-makeups", "Awa")
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_absence_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement** in `marks_live.ex`.

1. **Parsing.** Replace `parse_score/1` with a mark-entry parser. Its contract: `{:ok, :blank | {:graded, Decimal.t()} | :absent | :excused} | :error`.

```elixir
  # Parses a raw mark field: a number (French comma accepted), `a`/`abs` (absent),
  # `abj` (justified absence), or blank ("not entered"). Anything else is :error, so a
  # typo never becomes a silent absence.
  defp parse_entry(nil), do: {:ok, :blank}

  defp parse_entry(raw) do
    case raw |> String.trim() |> String.downcase() |> String.replace(",", ".") do
      "" -> {:ok, :blank}
      code when code in ["a", "abs"] -> {:ok, :absent}
      "abj" -> {:ok, :excused}
      normalized ->
        case Decimal.parse(normalized) do
          {d, ""} -> {:ok, {:graded, d}}
          _ -> :error
        end
    end
  end

  defp entry_attrs(:blank), do: %{score: nil}
  defp entry_attrs({:graded, d}), do: %{score: d}
  defp entry_attrs(status) when status in [:absent, :excused], do: %{score: nil, status: status}
```

   In `save_solo/2`, `save_combined/2` and `preview_average/4`, call `parse_entry/1` instead of `parse_score/1`, and build entries as `Map.merge(%{student_id: id}, entry_attrs(parsed))`. `preview_average/4` maps each parsed entry to a mark `%{assessment_id: …, student_id: …, score: …, status: …}`: `:graded` with its score, `:absent`/`:excused` with a nil score, and `:blank` left out. It passes `@grading_rules`. Delete `score_or_nil/1` if nothing else uses it. Update the invalid-value flash to: `gettext("Some marks aren't valid — use a number (e.g. 12 or 13,5), abs or abj.")`.

2. **Display.** In `existing_scores/2` and `combined_existing_scores/2`, map each mark to `mark_field(m)`:

```elixir
  defp mark_field(%{status: :graded, score: score}), do: Decimal.to_string(score, :normal)
  defp mark_field(%{status: status}), do: TeacherAssistant.Academics.MarkStatus.code(status)
```

   `sibling_scores/3` builds `{{student_id, assessment_id}, mark}` values. The sibling cell renders `sibling_text(@sibling_scores[{s.id, a.id}])`:

```elixir
  defp sibling_text(nil), do: "—"
  defp sibling_text(%{status: :graded, score: score}), do: fmt_avg(score)
  defp sibling_text(%{status: status}), do: TeacherAssistant.Academics.MarkStatus.code(status)
```

3. **Inputs.** In both templates, replace the mark `<input>`'s `type="number" step="0.25" min="0" max="20" inputmode="decimal"` with `type="text" inputmode="text" autocapitalize="off" autocomplete="off"`, and its `placeholder={gettext("Abs")}` with `placeholder="—"`. Replace both hint paragraphs with:

```heex
          <p class="text-xs text-base-content/55">
            {gettext("Vide = non saisi · abs = absent · abj = absence justifiée · notes sur %{max}.",
              max: max_label(@assessment)
            )}
          </p>
```

   Use `@selected` instead of `@assessment` in the combined template.

4. **Exemptions.** In the solo mount, after loading `students`, drop the exempt ones: `students = Enum.reject(students, &MapSet.member?(Curriculum.exempt_student_ids(scope, ctx), &1.id))`. Compute the set once. In combined mode, filter each group's `students` the same way, using the group's own `teaching_context`.

5. **Pending make-ups.** Add an assign `pending_makeups` (a list of student names), recomputed wherever `:scores` is assigned from stored marks (`existing_scores`/`combined_existing_scores` calls):

```elixir
  defp pending_makeups(_scope, _students, nil, _rules), do: []

  defp pending_makeups(scope, students, assessment, rules) do
    by_student = scope |> Assessment.list_marks(assessment) |> Map.new(&{&1.student_id, [&1]})

    for s <- students, TeacherAssistant.Academics.Marks.makeup_pending?(Map.get(by_student, s.id, []), rules),
        do: s.full_name
  end
```

   In the solo template, after the hint:

```heex
          <div :if={@pending_makeups != []} id="pending-makeups" class="alert alert-warning text-sm">
            <.icon name="hero-arrow-path" class="size-4" />
            <span>{gettext("Rattrapage attendu :")} {Enum.join(@pending_makeups, ", ")}</span>
          </div>
```

   Combined mode: compute over `Enum.flat_map(@groups, & &1.students)`, reading marks from each of the selected column's per-class assessments (`selected.by_class_group_id` values). Show the same block with the same id.

6. **New-assessment form.**
   - Assign `assessment_types: Assessment.list_assessment_types(scope)` and `default_max: profile.default_max_score` at mount.
   - Replace the label-only input in both templates with:

```heex
            <.input
              type="select"
              name="assessment[assessment_type_id]"
              value=""
              options={[{gettext("Type"), ""} | for(t <- @assessment_types, do: {t.name, t.id})]}
            />
            <.input field={@new_assessment_form[:label]} placeholder={gettext("New assessment")} />
            <.input
              type="text"
              inputmode="decimal"
              name="assessment[max_score]"
              value={Decimal.to_string(@default_max, :normal)}
              class="input input-bordered w-20"
              aria-label={gettext("Note maximale")}
            />
```

   - `new_solo_assessment/2`: before submitting, normalise the params. Drop an empty `assessment_type_id`. If the label is blank and a type is chosen, set it to `"#{type.name} #{n}"`, where `n` is 1 + the number of existing assessments of that type in the séquence. Parse `max_score` with `Curriculum.parse_coefficient/1`, keeping the Decimal or dropping the key when invalid, so the change applies the default.
   - `new_combined_assessment/3` becomes `/2` taking the whole params map. It does the same normalisation and passes `%{label: …, assessment_type_id: …, max_score: …}` to `Assessment.create_combined_assessment/4`.
   - The `handle_event("new_assessment", …)` dispatcher passes `p` to both.

`marks_summary_live.ex`: map marks with `status: m.status`, and drop exempt students from `students` the same way (`Curriculum.exempt_student_ids(scope, ctx)`).

Run `mix gettext.extract --merge`, and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Vide = non saisi · abs = absent · abj = absence justifiée · notes sur %{max}. | Blank = not entered · abs = absent · abj = excused · marks out of %{max}. |
| Some marks aren't valid — use a number (e.g. 12 or 13,5), abs or abj. | (identity) |
| Rattrapage attendu : | Make-up expected: |
| Type | Type |
| Note maximale | Maximum mark |

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/teacher/`
Expected: PASS. Existing marks-page tests that typed a blank to mean "absent" and asserted a stored nil row must now assert *no row*. Tests that fill `type=number` inputs work unchanged with text inputs.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher test/teacher_assistant_web/live/teacher priv/gettext
git commit -m "feat: marks page records abs/abj, assessment types, exemptions and pending make-ups

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Évaluations & moyennes: types, maximum mark, absence rule

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/evaluations_live.ex`
- Test: append to `test/teacher_assistant_web/live/school/evaluations_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: `list/create/update/delete_assessment_type` (Task 4); `update_default_max_score/2` and `"absence_rule"` (Task 3); `AbsenceRule.label/1`.
- Produces:
  - DOM: `#assessment-types` with a `<form id="type-<id>">` per type (`type[name]`, `type[default_weight]`), `#new-type-form`, `#delete-type-<id>`, `#default-max-form`, and rule buttons `#rule-absence_rule-<value>`.
  - The absence rule row joins the existing `@rules` list with official value `:zero`, labelled "pratique courante" rather than "règle officielle".

- [ ] **Step 1: Write the failing tests** (append):

```elixir
  test "admin manages assessment types", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0,5"}}) |> render_submit()
    oral = Enum.find(Assessment.list_assessment_types(scope), &(&1.name == "Oral"))
    assert Decimal.equal?(oral.default_weight, Decimal.new("0.5"))

    view |> form("#type-#{oral.id}", %{"type" => %{"name" => "Oral", "default_weight" => "2"}}) |> render_submit()
    assert Decimal.equal?(Enum.find(Assessment.list_assessment_types(scope), &(&1.id == oral.id)).default_weight, 2)

    view |> element("#delete-type-#{oral.id}") |> render_click()
    refute Enum.any?(Assessment.list_assessment_types(scope), &(&1.id == oral.id))
  end

  test "a zero weight is refused", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    view |> form("#new-type-form", %{"type" => %{"name" => "Oral", "default_weight" => "0"}}) |> render_submit()
    assert render(view) =~ "Type non enregistré."
  end

  test "maximum mark and absence rule", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/evaluations")
    assert has_element?(view, "#rule-absence_rule-zero.btn-primary")
    view |> form("#default-max-form", %{"default_max_score" => "10"}) |> render_submit()
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert Decimal.equal?(profile.default_max_score, 10)

    view |> element("#rule-absence_rule-makeup") |> render_click()
    assert Assessment.grading_rules(scope).absence == :makeup
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/evaluations_live_test.exs`
Expected: the 3 new tests FAIL.

- [ ] **Step 3: Implement** in `evaluations_live.ex`:

- Add `{"absence_rule", :absence, AbsenceRule, :zero}` to `@rules`, and alias `AbsenceRule`. In the button label, show `gettext("pratique courante")` instead of `gettext("règle officielle")` when `field == "absence_rule"`:

```heex
                <span :if={value == official} class="text-xs opacity-70">
                  · {if field == "absence_rule", do: gettext("pratique courante"), else: gettext("règle officielle")}
                </span>
```

- Add `defp rule_title("absence_rule"), do: gettext("Élève absent à une évaluation")`.
- At mount, also assign `types: Assessment.list_assessment_types(scope)` and `default_max: profile.default_max_score`.
- Above the rules panel, add the types panel and the maximum form:

```heex
        <div id="assessment-types" class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3">
          <h2 class="ta-eyebrow">{gettext("Types d'évaluation et poids par défaut")}</h2>
          <.form
            :for={t <- @types}
            for={%{}}
            as={:type}
            id={"type-#{t.id}"}
            phx-submit="update_type"
            class="flex flex-wrap items-end gap-2"
          >
            <input type="hidden" name="type_id" value={t.id} />
            <.input name="type[name]" value={t.name} class="input input-sm flex-1" />
            <span class="text-xs text-base-content/60">{gettext("poids")}</span>
            <.input
              name="type[default_weight]"
              value={Decimal.to_string(Decimal.normalize(t.default_weight), :normal)}
              inputmode="decimal"
              class="input input-sm w-20 text-right"
            />
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Enregistrer")}</button>
            <button
              :if={t.usage_count == 0}
              id={"delete-type-#{t.id}"}
              type="button"
              phx-click="delete_type"
              phx-value-id={t.id}
              class="btn btn-ghost btn-sm"
              aria-label={gettext("Supprimer")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </.form>
          <.form for={%{}} as={:type} id="new-type-form" phx-submit="create_type" class="flex flex-wrap items-end gap-2">
            <.input name="type[name]" value="" placeholder={gettext("Nouveau type")} class="input input-sm flex-1" />
            <.input name="type[default_weight]" value="1" inputmode="decimal" class="input input-sm w-20 text-right" />
            <button type="submit" class="btn btn-outline btn-sm">{gettext("+ Type d'évaluation")}</button>
          </.form>
          <p class="ta-num text-right text-xs text-warning">
            {gettext("Exemple : 12 (×0,5) et 14 (×1) → moyenne 13,33")}
          </p>
        </div>

        <.form for={%{}} id="default-max-form" phx-submit="save_default_max" class="flex items-end gap-2">
          <.input
            name="default_max_score"
            value={Decimal.to_string(Decimal.normalize(@default_max), :normal)}
            label={gettext("Note maximale")}
            inputmode="decimal"
            class="input input-sm w-24 text-right"
          />
          <button type="submit" class="btn btn-ghost btn-sm">{gettext("Enregistrer")}</button>
        </.form>
```

- Events:

```elixir
  def handle_event("create_type", %{"type" => p}, socket), do: save_type(socket, nil, p)

  def handle_event("update_type", %{"type_id" => id, "type" => p}, socket) do
    case Enum.find(socket.assigns.types, &(&1.id == id)) do
      nil -> {:noreply, socket}
      type -> save_type(socket, type, p)
    end
  end

  def handle_event("delete_type", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = type <- Enum.find(socket.assigns.types, &(&1.id == id)) do
      case Assessment.delete_assessment_type(scope, type) do
        {:error, :in_use} ->
          {:noreply, put_flash(socket, :error, gettext("Type utilisé par des évaluations : il est conservé."))}

        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        _ ->
          {:noreply, assign(socket, types: Assessment.list_assessment_types(scope))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_default_max", %{"default_max_score" => value}, socket) do
    scope = socket.assigns.current_scope

    case Assessment.update_default_max_score(scope, value) do
      {:ok, profile} ->
        {:noreply,
         socket |> assign(default_max: profile.default_max_score) |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp save_type(socket, type, params) do
    scope = socket.assigns.current_scope

    with {:ok, weight} <- TeacherAssistant.Curriculum.parse_coefficient(params["default_weight"] || ""),
         attrs = %{name: params["name"], default_weight: weight},
         {:ok, _} <-
           if(type,
             do: Assessment.update_assessment_type(scope, type, attrs),
             else: Assessment.create_assessment_type(scope, attrs)
           ) do
      {:noreply,
       socket
       |> assign(types: Assessment.list_assessment_types(scope))
       |> put_flash(:info, gettext("Type enregistré."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Type non enregistré."))}
    end
  end
```

Run `mix gettext.extract --merge`, and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Zéro | Zero |
| Non noté (exclu du calcul) | Not graded (left out) |
| Rattrapage obligatoire | Make-up required |
| pratique courante | common practice |
| Élève absent à une évaluation | Student absent from an assessment |
| Types d'évaluation et poids par défaut | Assessment types and default weights |
| poids | weight |
| Nouveau type | New type |
| + Type d'évaluation | + Assessment type |
| Exemple : 12 (×0,5) et 14 (×1) → moyenne 13,33 | Example: 12 (×0.5) and 14 (×1) → average 13.33 |
| Type utilisé par des évaluations : il est conservé. | Type used by assessments: it is kept. |
| Type enregistré. | Type saved. |
| Type non enregistré. | Type not saved. |

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/evaluations_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/evaluations_live.ex test/teacher_assistant_web/live/school/evaluations_live_test.exs priv/gettext
git commit -m "feat: assessment types, maximum mark and absence rule on the evaluations page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Coefficients grid "Facultative"; class page "Élèves concernés"

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/coefficients_live.ex` (an `optional` checkbox per row; error display)
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (a checklist per optional subject)
- Test: append to `coefficients_live_test.exs` and `class_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: `update_coefficient_grid/2` with `"optional"`, `set_exemptions/3`, `exempt_student_ids/2` (Task 5).
- Produces:
  - The grid posts `grid[optional][<subject_id>]` (a hidden `"false"` plus a checkbox `"true"`).
  - Class page DOM: `#takers-<tc_id>` (`<details>`) containing `<form id="takers-form-<tc_id>">` with checkboxes `takers[]` (student ids).

- [ ] **Step 1: Write the failing tests.** Append to `coefficients_live_test.exs`:

```elixir
  test "a subject can be marked optional from the grid", %{conn: conn, scope: scope, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")

    view
    |> form("#coefficient-grid-form", %{"grid" => %{"optional" => %{m.id => "true"}}})
    |> render_submit()

    assert Enum.find(Curriculum.list_subjects(scope), &(&1.id == m.id)).optional?
  end
```

Append to `class_live_test.exs` (inside `describe "assignments panel"`):

```elixir
    test "an optional subject lists who takes it", %{conn: conn, cg: cg, user: head, scope: scope} do
      {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
      {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
      {:ok, esp} = TeacherAssistant.Curriculum.create_subject(scope, %{name: "Espagnol"})
      :ok = TeacherAssistant.Curriculum.update_coefficient_grid(scope, %{"optional" => %{esp.id => "true"}})
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: esp})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#takers-#{tc.id}", "2/2")

      view |> form("#takers-form-#{tc.id}", %{"takers" => [awa.id]}) |> render_submit()
      assert TeacherAssistant.Curriculum.exempt_student_ids(scope, tc) == MapSet.new([bob.id])
      assert has_element?(view, "#takers-#{tc.id}", "1/2")
    end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/coefficients_live_test.exs test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement.**

`coefficients_live.ex`: add a "Facultative" column after "Groupe":

```heex
                  <td class="text-center">
                    <input type="hidden" name={"grid[optional][#{s.id}]"} value="false" />
                    <input
                      type="checkbox"
                      name={"grid[optional][#{s.id}]"}
                      value="true"
                      checked={s.optional?}
                      class="checkbox checkbox-sm"
                      aria-label={gettext("Facultative")}
                    />
                    <p :for={msg <- error_texts(@errors, {:optional, s.id})} class="text-xs text-error">
                      {msg}
                    </p>
                  </td>
```

Add the `<th>{gettext("Facultative")}</th>` header, and in the footer change `colspan="2"` to `colspan="3"`. Add:

```elixir
  defp error_text({:has_exemptions, labels}),
    do: gettext("Des élèves en sont dispensés : %{classes}", classes: Enum.join(labels, ", "))
```

`class_live.ex`:
- Add an assign `exemptions` in `load_roster/1`: `Map.new(assignments, &{&1.id, Curriculum.exempt_student_ids(scope, &1)})` for assignments whose `catalog_subject.optional?`.
- Add an assign `roster_students`: `Enrollment.list_students(scope, cg)`.
- In the subject cell of each assignment row (`<td>{tc.subject}</td>`):

```heex
                  <td>
                    {tc.subject}
                    <details :if={tc.catalog_subject.optional?} id={"takers-#{tc.id}"} class="mt-1 text-xs">
                      <summary class="cursor-pointer text-base-content/70">
                        {gettext("Élèves concernés")}
                        <span class="ta-num">
                          ({length(@roster_students) - MapSet.size(Map.get(@exemptions, tc.id, MapSet.new()))}/{length(@roster_students)})
                        </span>
                      </summary>
                      <form
                        :if={@can_manage_assignments?}
                        id={"takers-form-#{tc.id}"}
                        phx-submit="set_takers"
                        class="mt-2 space-y-1"
                      >
                        <input type="hidden" name="context-id" value={tc.id} />
                        <input type="hidden" name="takers[]" value="" />
                        <label :for={s <- @roster_students} class="flex items-center gap-2">
                          <input
                            type="checkbox"
                            name="takers[]"
                            value={s.id}
                            checked={not MapSet.member?(Map.get(@exemptions, tc.id, MapSet.new()), s.id)}
                            class="checkbox checkbox-xs"
                          />
                          {s.full_name}
                        </label>
                        <button type="submit" class="btn btn-ghost btn-xs">{gettext("Enregistrer")}</button>
                      </form>
                    </details>
                  </td>
```

- Event:

```elixir
  def handle_event("set_takers", %{"context-id" => cid} = params, socket) do
    takers = params |> Map.get("takers", []) |> Enum.reject(&(&1 == ""))

    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      case Curriculum.set_exemptions(socket.assigns.current_scope, tc, takers) do
        :ok -> {:noreply, socket |> put_flash(:info, gettext("Élèves concernés enregistrés.")) |> load_roster()}
        {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Liste non enregistrée."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end
```

Run `mix gettext.extract --merge`, and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Facultative | Optional |
| Des élèves en sont dispensés : %{classes} | Students are exempted in: %{classes} |
| Élèves concernés | Students taking it |
| Élèves concernés enregistrés. | Students saved. |
| Liste non enregistrée. | List not saved. |

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/coefficients_live_test.exs test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school test/teacher_assistant_web/live/school priv/gettext
git commit -m "feat: optional subjects on the grid and who takes them on the class page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Bulletin, print and results: "R" and the pending make-up count

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex`, `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`, `lib/teacher_assistant_web/live/school/results_live.ex`
- Test: append to `bulletin_live_test.exs` and `results_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: row `makeup_pending` and result `makeup_pending_count` (Task 6).
- Produces: DOM `#makeup-<context_id>` (an "R" badge) on bulletin rows, `#makeup-legend`, and `#results-makeups` (only when the count is > 0).

- [ ] **Step 1: Write the failing tests.** Append to `bulletin_live_test.exs` (its setup gives Awa 15 in "Maths" through `a`; it also has `seq`, `cg`, `enr`, `scope`):

```elixir
  test "switching to the make-up rule turns a zero into an R", ctx do
    %{conn: conn, cg: cg, enr: enr, seq: seq, scope: scope, head: head} = ctx
    [tc] = Curriculum.list_assignments_for_class(scope, cg)
    {:ok, a2} = Assessment.create_assessment(scope, tc, seq, %{label: "D2", weight: Decimal.new(1), max_score: Decimal.new(20)})
    [%{student: st}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: st.id, score: nil, status: :absent}])
    path = ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}"

    {:ok, view, _} = live(conn, path)
    assert render(view) =~ "7.50"
    refute has_element?(view, "#makeup-#{tc.id}")

    {:ok, _} = Assessment.update_grading_rules(scope, %{"absence_rule" => "makeup"})
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#makeup-#{tc.id}", "R")
    assert has_element?(view, "#makeup-legend")
    _ = head
  end
```

(15 and an absence counted as 0 over two weight-1 /20 assessments gives 7.50.)

Append to `results_live_test.exs`, reusing its setup: give one student an `:absent` mark, switch to `"makeup"`, and assert `#results-makeups` contains `"1"`. Before the switch it must be absent. Match the file's setup keys and route.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement.**

`bulletin_live.ex`: in the average cell of each subject row (the cell showing `fmt(row.average)` for the period), append:

```heex
                      <span
                        :if={row.makeup_pending}
                        id={"makeup-#{row.context_id}"}
                        class="badge badge-warning badge-xs ml-1"
                        title={gettext("Rattrapage attendu")}
                      >
                        R
                      </span>
```

For trimester and annual periods, put it on the `row.average` cell, not the component cells. After the table:

```heex
          <p :if={Enum.any?(@data.subjects, & &1.makeup_pending)} id="makeup-legend" class="text-xs text-base-content/70">
            {gettext("R : rattrapage attendu")}
          </p>
```

`show.html.heex`: the same "R" (plain text `<sup>R</sup>`) and the legend, inside each bundle when `b.data` has a pending row.

`results_live.ex`: after the stats grid:

```heex
          <p :if={@results.makeup_pending_count > 0} id="results-makeups" class="alert alert-warning text-sm">
            {gettext("Rattrapages attendus : %{count}", count: @results.makeup_pending_count)}
          </p>
```

Run `mix gettext.extract --merge`, and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Rattrapage attendu | Make-up expected |
| R : rattrapage attendu | R: make-up expected |
| Rattrapages attendus : %{count} | Make-ups expected: %{count} |

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web priv/gettext
git commit -m "feat: pending make-ups on bulletins, print and class results

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Name the migration, full gate

- [ ] **Step 1:** Run `printf 'n\nn\n' | mix ash.codegen marks_absence`, then `mix ash.reset && MIX_ENV=test mix ash.reset`.
- [ ] **Step 2:** Run `mix ash.codegen --check && mix compile --warnings-as-errors && mix precommit`.
  Expected: no drift, no warnings, and the whole suite green (831 + the new tests).
  - Tests outside the touched files that now break are mostly one of two cases, and both get their expectations updated, not the code:
    1. a blank mark that used to store a nil row;
    2. an average that assumed an absence was left out, whereas an explicit `:absent` now counts as 0 by default.
  - Anything else gets systematic debugging.
- [ ] **Step 3:** Commit:

```bash
git add -A priv/repo/migrations priv/resource_snapshots lib test priv/gettext
git commit -m "chore: name the marks and absence migration

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
