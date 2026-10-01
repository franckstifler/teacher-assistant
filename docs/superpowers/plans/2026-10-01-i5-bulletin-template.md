# I5 — Report card template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The printed report card follows a school template — French, English or bilingual labels, a letter-grade
scale for anglophone classes, hideable elements, the full official header, and a QR code that checks a published
card on a public page — and a published card keeps the template it was issued with.

**Architecture:** Three new `SchoolProfile` settings (language mode, elements, grade scale), resolved per class by a
pure `Academics.BulletinTemplate`. `ReportCards.live_view/3` carries the resolved template, so publishing freezes it
in the snapshot (version 3) and drafts and publications render through one path. The print template translates
its labels with `Gettext.with_locale` per card language. The QR encodes a `Phoenix.Token` over
`{workspace_id, publication_id, student_id}`, checked by a public controller that reads the publication with
`authorize?: false` under the publication's own tenant.

**Tech Stack:** Phoenix 1.8, LiveView, Ash 3 (attribute multitenancy on `workspace_id`), AshPostgres, Gettext
(French source msgids, `fr`/`en`), new dependency `eqrcode`.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"I5 — Report card template (spec)".

## Global Constraints

- Never write migrations by hand: `mix ash.codegen --dev` (then `mix ash.migrate`); finish with `mix ash.codegen --check` clean.
- Enums are `Ash.Type.Enum` modules, never bare `:atom` attributes.
- Every user-facing string goes through gettext; msgids are French. `mix gettext.extract --merge` fuzzy-matches new
  msgids to wrong old ones in both `en` and `fr`: compare `priv/gettext/*/LC_MESSAGES/default.po` with main and fix
  every new fuzzy entry (main has 27 fuzzy in en and 17 in fr — leave those).
- Work in a worktree under `.claude/worktrees/i5`, branch `i5-bulletin-template`, with `MIX_TEST_PARTITION=2`.
  Stage explicit paths only — never `git commit -a` (a parallel session shares the main checkout).
- The template applies to the **printed card only**; on-screen report cards are unchanged.
- `bulletin_elements`: nil = defaults (all but `:qr_code`); `[]` = nothing optional shown. Never collapse `[]` to nil.
- `grade_scale`: nil or `[]` = the default scale (A 16 Excellent, B 14 Very good, C 12 Good, D 10 Pass, E 8 Weak,
  F 0 Fail). Same rules as I1 bands: first `from` 0, strictly increasing within 0..20, letter and remark non-empty.
- Snapshot `snapshot_version` 3 adds key `template`; v1/v2 snapshots (no `template`) render with the current settings.
- The verification page shows no marks: name, school, class, period, publication or withdrawal date only.
- `mix precommit` before the last commit (it rewrites files with the formatter; re-stage them).

## Review Focus

1. A bilingual card whose French and English label are identical (e.g. « Total ») — prints the word once, not
   « Total / Total » (test in Task 4).
2. The school changes language, elements and grade scale after publishing — the published card still prints as
   issued; the draft of another period follows the new settings (tests in Tasks 3 and 4).
3. Every optional element unchecked (`[]`) — saved as `[]`, not reset to the defaults, and the card prints with
   balanced table rows (tests in Tasks 1 and 4).
4. A period withdrawn then republished — the old card's QR says « retiré », the new card's QR says authentic (test
   in Task 5).
5. A token naming a publication of another school, or a student not on that publication — « Lien de vérification
   invalide », never another school's data (test in Task 5).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/teacher_assistant/academics/bulletin_language.ex` (new) | Enum `:by_class | :bilingual` + labels |
| `lib/teacher_assistant/academics/bulletin_element.ex` (new) | Enum of the nine hideable elements, labels, defaults |
| `lib/teacher_assistant/accounts/grade_band.ex` (new) | Embedded `%{from, letter, remark}` |
| `lib/teacher_assistant/accounts/school_profile/validate_grade_scale.ex` (new) | Grade-scale rules |
| `lib/teacher_assistant/accounts/school_profile.ex` | Three attributes, accept list, validation |
| `lib/teacher_assistant/academics/bulletin_template.ex` (new) | Pure: resolve, grade lookup, defaults, header lines |
| `lib/teacher_assistant/assessment.ex` | `bulletin_settings/1`, `update_bulletin_settings/2`, `update_grade_scale/2`, `reset_grade_scale/1` |
| `lib/teacher_assistant/report_cards.ex` | Template in `live_view/3`, `template_of/3`, `verification/3` |
| `lib/teacher_assistant/academics/bulletin_publication.ex` | `snapshot_version` 3 |
| `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` / `_html.ex` / `show.html.heex` | Language, header, grades, hidden elements, class average, QR |
| `lib/teacher_assistant_web/bulletin_verification.ex` (new) | Token sign/verify + QR SVG |
| `lib/teacher_assistant_web/controllers/bulletin_verify_controller.ex` + `_html.ex` + `bulletin_verify_html/show.html.heex` (new) | Public page |
| `lib/teacher_assistant_web/live/school/bulletin_template_live.ex` (new) | Settings page |
| `lib/teacher_assistant_web/router.ex`, `spaces.ex`, `live/school/settings_live.ex` | Routes and links |

---

### Task 0: Worktree

- [ ] **Step 1: Create the worktree and its test database**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/i5 -b i5-bulletin-template main
cd .claude/worktrees/i5
mix deps.get
MIX_TEST_PARTITION=2 mix test test/teacher_assistant/report_cards_test.exs
```

Expected: tests pass (the partitioned test DB `teacher_assistant_test2` exists from earlier increments; if not,
`MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.setup` first).

All later commands run in `.claude/worktrees/i5` with `MIX_TEST_PARTITION=2` for `mix test`.

---

### Task 1: Settings data — language, elements, grade scale

**Files:**
- Create: `lib/teacher_assistant/academics/bulletin_language.ex`, `lib/teacher_assistant/academics/bulletin_element.ex`,
  `lib/teacher_assistant/accounts/grade_band.ex`, `lib/teacher_assistant/accounts/school_profile/validate_grade_scale.ex`
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes after `exclusion_absence_hours`; `:update` accept list; validations)
- Modify: `lib/teacher_assistant/assessment.ex` (new section after "Passage rules (spec I4)")
- Create: `lib/teacher_assistant/academics/bulletin_template.ex` (only `default_grade_scale/0`, `elements/1`, `grade_scale/1` in this task)
- Test: `test/teacher_assistant/academics/bulletin_settings_test.exs`

**Interfaces:**
- Produces: `BulletinLanguage` (`:by_class | :bilingual`, `label/1`); `BulletinElement` (`values/0`, `label/1`,
  `defaults/0`); `SchoolProfile.bulletin_language | bulletin_elements | grade_scale`;
  `BulletinTemplate.default_grade_scale/0 :: [%{from: Decimal, letter: String, remark: String}]`,
  `BulletinTemplate.elements(nil | [atom]) :: [atom]`, `BulletinTemplate.grade_scale(nil | [band]) :: [map]`;
  `Assessment.bulletin_settings(scope) :: %{language: atom, elements: [atom], grade_scale: [map], custom_scale?: boolean}`;
  `Assessment.update_bulletin_settings(scope, %{"language" => s, "elements" => [s]})`;
  `Assessment.update_grade_scale(scope, [%{from: s, letter: s, remark: s}])`; `Assessment.reset_grade_scale(scope)`.
  Errors: `{:error, :invalid_setting}`, `{:error, :invalid_number}`, `{:error, %Ash.Error.Invalid{}}`, `{:error, %Ash.Error.Forbidden{}}`.

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/bulletin_settings_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.BulletinSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "defaults: follow the class, all elements but the QR, the common grade scale", %{scope: scope} do
    s = Assessment.bulletin_settings(scope)
    assert s.language == :by_class
    refute :qr_code in s.elements
    assert :rank in s.elements and :pp_signature in s.elements
    assert length(s.elements) == 8
    assert Enum.map(s.grade_scale, & &1.letter) == ~w(F E D C B A)
    refute s.custom_scale?
  end

  test "saves the language and the elements; an empty selection stays empty", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "bilingual",
               "elements" => ["rank", "qr_code", "rank", ""]
             })

    s = Assessment.bulletin_settings(scope)
    assert s.language == :bilingual
    assert s.elements == [:rank, :qr_code]

    assert {:ok, _} =
             Assessment.update_bulletin_settings(scope, %{"language" => "by_class", "elements" => [""]})

    assert Assessment.bulletin_settings(scope).elements == []
  end

  test "unknown language or element is refused and nothing is written", %{scope: scope} do
    assert {:error, :invalid_setting} =
             Assessment.update_bulletin_settings(scope, %{"language" => "klingon", "elements" => []})

    assert {:error, :invalid_setting} =
             Assessment.update_bulletin_settings(scope, %{
               "language" => "by_class",
               "elements" => ["rank", "photo"]
             })

    assert Assessment.bulletin_settings(scope).language == :by_class
  end

  test "saves a grade scale; bounds accept a comma; reset goes back to the default", %{scope: scope} do
    rows = [
      %{from: "0", letter: "F", remark: "Fail"},
      %{from: "9,5", letter: "P", remark: "Pass"},
      %{from: "15", letter: "A", remark: "Excellent"}
    ]

    assert {:ok, _} = Assessment.update_grade_scale(scope, rows)
    s = Assessment.bulletin_settings(scope)
    assert s.custom_scale?
    assert Enum.map(s.grade_scale, &{Decimal.to_string(&1.from), &1.letter}) ==
             [{"0", "F"}, {"9.5", "P"}, {"15", "A"}]

    assert {:ok, _} = Assessment.reset_grade_scale(scope)
    refute Assessment.bulletin_settings(scope).custom_scale?
  end

  test "grade-scale rules", %{scope: scope} do
    bad = [
      [%{from: "1", letter: "F", remark: "Fail"}],
      [%{from: "0", letter: "F", remark: "Fail"}, %{from: "0", letter: "A", remark: "Top"}],
      [%{from: "0", letter: "F", remark: "Fail"}, %{from: "21", letter: "A", remark: "Top"}],
      [%{from: "0", letter: " ", remark: "Fail"}],
      [%{from: "0", letter: "F", remark: ""}]
    ]

    for rows <- bad do
      assert {:error, %Ash.Error.Invalid{}} = Assessment.update_grade_scale(scope, rows)
    end

    assert {:error, :invalid_number} =
             Assessment.update_grade_scale(scope, [%{from: "x", letter: "F", remark: "Fail"}])
  end

  test "a plain teacher cannot save", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assessment.update_bulletin_settings(teacher, %{"language" => "bilingual", "elements" => []})
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/bulletin_settings_test.exs`
Expected: FAIL — `Assessment.bulletin_settings/1 is undefined`.

- [ ] **Step 3: Enums and embedded band**

`lib/teacher_assistant/academics/bulletin_language.ex`:

```elixir
defmodule TeacherAssistant.Academics.BulletinLanguage do
  @moduledoc "Spec I5: a card follows its class's sub-system, or every card is bilingual."
  use Ash.Type.Enum, values: [:by_class, :bilingual]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:by_class), do: gettext("Suivre la classe (francophone / anglophone)")
  def label(:bilingual), do: gettext("Bilingue pour toutes les classes")
end
```

`lib/teacher_assistant/academics/bulletin_element.ex`:

```elixir
defmodule TeacherAssistant.Academics.BulletinElement do
  @moduledoc "Spec I5: the optional elements of the printed report card."
  use Ash.Type.Enum,
    values: [
      :rank,
      :class_average,
      :min_max,
      :subject_appreciation,
      :effectif,
      :absences,
      :conduct,
      :pp_signature,
      :qr_code
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc "Shown when the school has not chosen: everything but the QR code."
  def defaults, do: values() -- [:qr_code]

  def label(:rank), do: gettext("Rang")
  def label(:class_average), do: gettext("Moyenne de la classe")
  def label(:min_max), do: gettext("Min / max de la classe")
  def label(:subject_appreciation), do: gettext("Appréciation (ou grade) par matière")
  def label(:effectif), do: gettext("Effectif")
  def label(:absences), do: gettext("Absences")
  def label(:conduct), do: gettext("Conduite (note, consignes, sanctions)")
  def label(:pp_signature), do: gettext("Signature du professeur principal")
  def label(:qr_code), do: gettext("QR de vérification")
end
```

`lib/teacher_assistant/accounts/grade_band.ex`:

```elixir
defmodule TeacherAssistant.Accounts.GradeBand do
  @moduledoc """
  One band of a school's anglophone grade scale (spec I5), embedded in
  `SchoolProfile.grade_scale`: marks from `from` up to the next band's `from` get
  `letter` and `remark`. List rules live in `SchoolProfile.ValidateGradeScale`.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :from, :decimal, allow_nil?: false, public?: true
    # Nullable so blanks reach `ValidateGradeScale` and its own message.
    attribute :letter, :string, public?: true
    attribute :remark, :string, public?: true
  end
end
```

- [ ] **Step 4: Validation**

`lib/teacher_assistant/accounts/school_profile/validate_grade_scale.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolProfile.ValidateGradeScale do
  @moduledoc """
  Spec I5 rules for the grade scale: bands start at 0, strictly increase, stay within
  0..20, and each has a letter and a remark. nil or [] means the default scale.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @zero Decimal.new(0)
  @twenty Decimal.new(20)

  @impl true
  def validate(changeset, _opts, _context),
    do: changeset |> Ash.Changeset.get_attribute(:grade_scale) |> check()

  defp check(bands) when bands in [nil, []], do: :ok

  defp check([first | _] = bands) do
    froms = Enum.map(bands, & &1.from)

    cond do
      Enum.any?(bands, &(blank?(&1.letter) or blank?(&1.remark))) ->
        error(gettext("Chaque tranche doit avoir une lettre et une remarque."))

      not Decimal.equal?(first.from, @zero) ->
        error(gettext("La première tranche doit commencer à 0."))

      Enum.any?(froms, &(lt?(&1, @zero) or lt?(@twenty, &1))) ->
        error(gettext("Les bornes doivent être comprises entre 0 et 20."))

      not (froms |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> lt?(a, b) end)) ->
        error(gettext("Les bornes doivent être croissantes."))

      true ->
        :ok
    end
  end

  defp blank?(text), do: is_nil(text) or String.trim(text) == ""
  defp lt?(a, b), do: Decimal.compare(a, b) == :lt
  defp error(message), do: {:error, field: :grade_scale, message: message}
end
```

- [ ] **Step 5: Profile attributes**

In `lib/teacher_assistant/accounts/school_profile.ex`, after `attribute :exclusion_absence_hours …`:

```elixir
    # Spec I5: the printed report card's template.
    attribute :bulletin_language, TeacherAssistant.Academics.BulletinLanguage,
      allow_nil?: false,
      default: :by_class,
      public?: true

    # nil = `BulletinElement.defaults/0`; [] = no optional element.
    attribute :bulletin_elements, {:array, TeacherAssistant.Academics.BulletinElement},
      public?: true

    # nil/[] = `BulletinTemplate.default_grade_scale/0`.
    attribute :grade_scale, {:array, TeacherAssistant.Accounts.GradeBand}, public?: true
```

Add `:bulletin_language, :bulletin_elements, :grade_scale` to the end of the `update :update` accept list, and after
`validate TeacherAssistant.Accounts.SchoolProfile.ValidatePassage` add:

```elixir
      validate TeacherAssistant.Accounts.SchoolProfile.ValidateGradeScale
```

- [ ] **Step 6: Template defaults (pure)**

`lib/teacher_assistant/academics/bulletin_template.ex` (Task 2 extends this module):

```elixir
defmodule TeacherAssistant.Academics.BulletinTemplate do
  @moduledoc """
  The printed report card's template (spec I5), pure: language, grading column,
  elements shown, grade scale and header, resolved from the school profile for one
  class. Publishing stores the resolved map in the snapshot.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.BulletinElement

  @doc "The common in-school scale, lowest band first. Remarks are English (anglophone cards)."
  def default_grade_scale do
    [
      {"0", "F", "Fail"},
      {"8", "E", "Weak"},
      {"10", "D", "Pass"},
      {"12", "C", "Good"},
      {"14", "B", "Very good"},
      {"16", "A", "Excellent"}
    ]
    |> Enum.map(fn {from, letter, remark} ->
      %{from: Decimal.new(from), letter: letter, remark: remark}
    end)
  end

  @doc "The elements shown: nil = defaults; a list (even empty) as chosen."
  def elements(nil), do: BulletinElement.defaults()
  def elements(list) when is_list(list), do: list

  @doc "The grade scale in force, as plain maps."
  def grade_scale(bands) when bands in [nil, []], do: default_grade_scale()

  def grade_scale(bands),
    do: Enum.map(bands, &%{from: &1.from, letter: &1.letter, remark: &1.remark})
end
```

- [ ] **Step 7: Assessment functions**

In `lib/teacher_assistant/assessment.ex`, after `update_passage_rules/2` and its private helpers (before
`defp update_profile`), add:

```elixir
  # --- Report card template (spec I5) ---------------------------------------------

  @doc "The school's report card template settings, defaults applied."
  def bulletin_settings(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    %{
      language: profile.bulletin_language,
      elements: TeacherAssistant.Academics.BulletinTemplate.elements(profile.bulletin_elements),
      grade_scale: TeacherAssistant.Academics.BulletinTemplate.grade_scale(profile.grade_scale),
      custom_scale?: profile.grade_scale not in [nil, []]
    }
  end

  @doc """
  Saves the language mode and the elements shown from string params. Values are
  matched against the enums (never `String.to_atom`); blanks are dropped, duplicates
  removed, order kept. `{:error, :invalid_setting}` on anything unknown.
  """
  def update_bulletin_settings(%Scope{} = scope, %{} = params) do
    with {:ok, language} <-
           enum_value(TeacherAssistant.Academics.BulletinLanguage, params["language"]),
         {:ok, elements} <- parse_elements(Map.get(params, "elements", [])) do
      update_profile(scope, %{bulletin_language: language, bulletin_elements: elements})
    end
  end

  @doc """
  Saves the grade scale from `[%{from: "0", letter: "F", remark: "Fail"}, …]`, lowest
  band first; bounds accept a comma. `{:error, :invalid_number}` when a bound is not a
  number; the profile validation enforces the scale's rules.
  """
  def update_grade_scale(%Scope{} = scope, rows) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case parse_score(row.from) do
        {:ok, %Decimal{} = from} ->
          band = %{
            from: from,
            letter: String.trim(row.letter || ""),
            remark: String.trim(row.remark || "")
          }

          {:cont, {:ok, [band | acc]}}

        _ ->
          {:halt, {:error, :invalid_number}}
      end
    end)
    |> case do
      {:ok, bands} -> update_profile(scope, %{grade_scale: Enum.reverse(bands)})
      error -> error
    end
  end

  @doc "Goes back to the default grade scale."
  def reset_grade_scale(%Scope{} = scope), do: update_profile(scope, %{grade_scale: nil})

  defp enum_value(enum, value) when is_binary(value) do
    case Enum.find(enum.values(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_setting}
      atom -> {:ok, atom}
    end
  end

  defp enum_value(_enum, _value), do: {:error, :invalid_setting}

  defp parse_elements(values) when is_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case enum_value(TeacherAssistant.Academics.BulletinElement, value) do
        {:ok, atom} -> {:cont, {:ok, [atom | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp parse_elements(_), do: {:error, :invalid_setting}
```

- [ ] **Step 8: Migration**

Run: `mix ash.codegen --dev && mix ash.migrate && MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.migrate`
Expected: one new migration adding `bulletin_language` (text, not null, default `'by_class'`),
`bulletin_elements` (text[]) and `grade_scale` (jsonb[] or map[]) to `school_profiles`. Then rename the dev
migration per the project convention: `mix ash.codegen i5_bulletin_template` (squashes the `--dev` one) and
`mix ash.codegen --check` → no changes.

- [ ] **Step 9: Run the test to verify it passes**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/bulletin_settings_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 10: Commit**

```bash
git add lib/teacher_assistant/academics/bulletin_language.ex lib/teacher_assistant/academics/bulletin_element.ex \
  lib/teacher_assistant/accounts/grade_band.ex lib/teacher_assistant/accounts/school_profile/validate_grade_scale.ex \
  lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/academics/bulletin_template.ex \
  lib/teacher_assistant/assessment.ex priv/repo/migrations priv/resource_snapshots \
  test/teacher_assistant/academics/bulletin_settings_test.exs
git commit -m "feat: report card template settings (language, elements, grade scale)"
```

---

### Task 2: Template resolution and grade lookup (pure)

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletin_template.ex`
- Test: `test/teacher_assistant/academics/bulletin_template_test.exs`

**Interfaces:**
- Consumes: Task 1 `elements/1`, `grade_scale/1`; `SchoolProfile` fields; `ClassGroup.subsystem` (`:francophone | :anglophone`, default `:francophone`).
- Produces:
  - `BulletinTemplate.resolve(profile, school_name :: String.t(), class_group) :: %{language: :fr | :en | :bilingual, grading: :appreciation | :grade, elements: [atom], grade_scale: [map], header: map}`
  - header map: `%{name, address, town, phone, motto, registration_number, region, department, logo?}`
  - `BulletinTemplate.show?(template, element) :: boolean`
  - `BulletinTemplate.grade(scale, Decimal | nil) :: %{letter, remark} | nil`
  - `BulletinTemplate.official_lines(header) :: [String.t()]` (current locale)
  - `BulletinTemplate.school_lines(header) :: [String.t()]` (current locale)
  - `BulletinTemplate.regional_delegation(region) :: String.t()`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/bulletin_template_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.BulletinTemplateTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{BulletinTemplate, ClassGroup}
  alias TeacherAssistant.Accounts.SchoolProfile

  defp profile(attrs \\ %{}) do
    struct(
      SchoolProfile,
      Map.merge(
        %{
          bulletin_language: :by_class,
          bulletin_elements: nil,
          grade_scale: nil,
          region: :littoral,
          department: "Wouri",
          town: "Douala",
          address: "BP 12",
          phone: "+237 233 00 00 00",
          motto: "Travail",
          registration_number: "123/MINESEC",
          logo_path: nil
        },
        attrs
      )
    )
  end

  test "language follows the class, or bilingual for every class" do
    fr = %ClassGroup{subsystem: :francophone}
    en = %ClassGroup{subsystem: :anglophone}

    assert %{language: :fr, grading: :appreciation} = BulletinTemplate.resolve(profile(), "L", fr)
    assert %{language: :en, grading: :grade} = BulletinTemplate.resolve(profile(), "L", en)

    bi = profile(%{bulletin_language: :bilingual})
    assert %{language: :bilingual, grading: :appreciation} = BulletinTemplate.resolve(bi, "L", fr)
    assert %{language: :bilingual, grading: :grade} = BulletinTemplate.resolve(bi, "L", en)
  end

  test "a class without a sub-system is francophone" do
    assert %{language: :fr} = BulletinTemplate.resolve(profile(), "L", %ClassGroup{subsystem: nil})
  end

  test "elements: nil is the defaults, [] stays empty" do
    t = BulletinTemplate.resolve(profile(), "L", %ClassGroup{subsystem: :francophone})
    assert BulletinTemplate.show?(t, :rank)
    refute BulletinTemplate.show?(t, :qr_code)

    t = BulletinTemplate.resolve(profile(%{bulletin_elements: []}), "L", %ClassGroup{})
    refute BulletinTemplate.show?(t, :rank)
  end

  test "header is plain data from the profile" do
    t = BulletinTemplate.resolve(profile(), "Lycée de Bonabéri", %ClassGroup{})

    assert t.header == %{
             name: "Lycée de Bonabéri",
             address: "BP 12",
             town: "Douala",
             phone: "+237 233 00 00 00",
             motto: "Travail",
             registration_number: "123/MINESEC",
             region: :littoral,
             department: "Wouri",
             logo?: false
           }
  end

  test "grade lookup: the highest band whose bound is met; 20 is in the last band" do
    scale = BulletinTemplate.default_grade_scale()
    assert %{letter: "F", remark: "Fail"} = BulletinTemplate.grade(scale, Decimal.new("7.99"))
    assert %{letter: "D"} = BulletinTemplate.grade(scale, Decimal.new(10))
    assert %{letter: "A"} = BulletinTemplate.grade(scale, Decimal.new(20))
    assert BulletinTemplate.grade(scale, nil) == nil
  end

  test "official lines, in the current locale, with the region's delegation" do
    t = BulletinTemplate.resolve(profile(), "L", %ClassGroup{})

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "fr", fn ->
      lines = BulletinTemplate.official_lines(t.header)
      assert "République du Cameroun" in lines
      assert "Délégation régionale des Enseignements secondaires du Littoral" in lines
      assert Enum.any?(lines, &(&1 =~ "Wouri"))
    end)

    no_dept = %{t.header | department: nil}
    refute Enum.any?(BulletinTemplate.official_lines(no_dept), &(&1 =~ "départementale"))
  end

  test "school lines skip what the profile leaves empty" do
    t = BulletinTemplate.resolve(profile(%{motto: nil, phone: ""}), "L", %ClassGroup{})
    lines = BulletinTemplate.school_lines(t.header)
    assert "L" in lines
    refute Enum.any?(lines, &(&1 in [nil, ""]))
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/bulletin_template_test.exs`
Expected: FAIL — `BulletinTemplate.resolve/3 is undefined`.

- [ ] **Step 3: Implement**

Append to `BulletinTemplate` (before the final `end`):

```elixir
  @doc "The template for `class_group`'s printed cards under `profile`."
  def resolve(profile, school_name, class_group) do
    anglophone? = class_group.subsystem == :anglophone

    %{
      language:
        cond do
          profile.bulletin_language == :bilingual -> :bilingual
          anglophone? -> :en
          true -> :fr
        end,
      grading: if(anglophone?, do: :grade, else: :appreciation),
      elements: elements(profile.bulletin_elements),
      grade_scale: grade_scale(profile.grade_scale),
      header: %{
        name: school_name,
        address: profile.address,
        town: profile.town,
        phone: profile.phone,
        motto: profile.motto,
        registration_number: profile.registration_number,
        region: profile.region,
        department: profile.department,
        logo?: is_binary(profile.logo_path)
      }
    }
  end

  def show?(%{elements: elements}, element), do: element in elements

  @doc "`%{letter, remark}` for `mark`, or nil when there is no mark."
  def grade(_scale, nil), do: nil

  def grade(scale, %Decimal{} = mark) do
    scale
    |> Enum.filter(&(Decimal.compare(mark, &1.from) != :lt))
    |> List.last()
    |> case do
      nil -> nil
      band -> %{letter: band.letter, remark: band.remark}
    end
  end

  @doc "The national lines of the header, in the current locale."
  def official_lines(header) do
    [
      gettext("République du Cameroun"),
      gettext("Paix – Travail – Patrie"),
      gettext("Ministère des Enseignements secondaires"),
      header.region && regional_delegation(header.region),
      present(header.department) &&
        gettext("Délégation départementale des Enseignements secondaires : %{department}",
          department: header.department
        )
    ]
    |> Enum.filter(& &1)
  end

  @doc "The school's own lines (name, address, phone, authorisation, motto), in the current locale."
  def school_lines(header) do
    address = [header.address, header.town] |> Enum.filter(&present/1) |> Enum.join(" · ")

    [
      header.name,
      present(address) && address,
      present(header.phone) && gettext("Tél. %{phone}", phone: header.phone),
      present(header.registration_number) &&
        gettext("Autorisation n° %{number}", number: header.registration_number),
      present(header.motto) && header.motto
    ]
    |> Enum.filter(& &1)
  end

  def regional_delegation(:adamawa),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Adamaoua")

  def regional_delegation(:centre),
    do: gettext("Délégation régionale des Enseignements secondaires du Centre")

  def regional_delegation(:east),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Est")

  def regional_delegation(:far_north),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Extrême-Nord")

  def regional_delegation(:littoral),
    do: gettext("Délégation régionale des Enseignements secondaires du Littoral")

  def regional_delegation(:north),
    do: gettext("Délégation régionale des Enseignements secondaires du Nord")

  def regional_delegation(:northwest),
    do: gettext("Délégation régionale des Enseignements secondaires du Nord-Ouest")

  def regional_delegation(:south),
    do: gettext("Délégation régionale des Enseignements secondaires du Sud")

  def regional_delegation(:southwest),
    do: gettext("Délégation régionale des Enseignements secondaires du Sud-Ouest")

  def regional_delegation(:west),
    do: gettext("Délégation régionale des Enseignements secondaires de l'Ouest")

  defp present(text), do: is_binary(text) and String.trim(text) != ""
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/bulletin_template_test.exs`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/bulletin_template.ex test/teacher_assistant/academics/bulletin_template_test.exs
git commit -m "feat: resolve a class's report card template; grade lookup and header lines"
```

---

### Task 3: The template travels with the view and freezes at publication

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`live_view/3`; new `template/2`, `template_of/3`)
- Modify: `lib/teacher_assistant/academics/bulletin_publication.ex` (`:publish` sets `snapshot_version` 3; comment)
- Test: `test/teacher_assistant/report_cards_test.exs` (new `describe "template (spec I5)"`)

**Interfaces:**
- Consumes: `BulletinTemplate.resolve/3`, `Accounts.fetch_school_profile/1`.
- Produces: `view.template` on every live view; `ReportCards.template_of(scope, class_group, view) :: template`
  (the view's own `template`, else the current settings — v1/v2 snapshots); publications have `snapshot_version: 3`.

- [ ] **Step 1: Write the failing test**

Read the top of `test/teacher_assistant/report_cards_test.exs` for its setup (it builds a school, year, class and
marks; reuse its `scope`, `cg` and term helpers). Add:

```elixir
  describe "template (spec I5)" do
    test "a published card keeps the template it was issued with", %{scope: scope, cg: cg} do
      term = scope |> TeacherAssistant.Organization.list_terms(scope.current_academic_year) |> hd()
      {:ok, pub} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert pub.snapshot_version == 3
      assert %{language: :fr, elements: elements} = pub.snapshot.template
      assert :rank in elements

      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "bilingual",
          "elements" => ["qr_code"]
        })

      {:published, pub, view} = TeacherAssistant.ReportCards.class_view(scope, cg, {:trimester, term})
      assert %{language: :fr} = TeacherAssistant.ReportCards.template_of(scope, cg, view)
      assert pub.snapshot.template.elements == elements

      [_, term2 | _] = TeacherAssistant.Organization.list_terms(scope, scope.current_academic_year)
      {:draft, draft} = TeacherAssistant.ReportCards.class_view(scope, cg, {:trimester, term2})
      assert %{language: :bilingual, elements: [:qr_code]} = draft.template
    end

    test "a snapshot from before I5 renders with the current settings", %{scope: scope, cg: cg} do
      old_view = %{results: nil, roster: []}
      assert %{language: :fr} = TeacherAssistant.ReportCards.template_of(scope, cg, old_view)
    end
  end
```

If the file's setup names differ (`class_group` instead of `cg`, no `current_academic_year` on the scope), adapt the
bindings to the setup — that is the only allowed change to the test.

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/report_cards_test.exs`
Expected: FAIL — `snapshot_version` is 2 / `template_of/3` undefined.

- [ ] **Step 3: Implement**

In `ReportCards.live_view/3`, add to the returned map:

```elixir
      template: template(scope, cg),
```

and add the public functions (after `live_view/3`):

```elixir
  @doc "The class's printed-card template under the school's current settings (spec I5)."
  def template(%Scope{} = scope, %ClassGroup{} = cg) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    BulletinTemplate.resolve(profile, scope.current_workspace.name, cg)
  end

  @doc "The template a view renders with: its own (drafts, v3 snapshots), else the current settings."
  def template_of(%Scope{} = scope, %ClassGroup{} = cg, view),
    do: Map.get(view, :template) || template(scope, cg)
```

Add `BulletinTemplate` to the `alias TeacherAssistant.Academics.{…}` list.

In `BulletinPublication`, `create :publish`: `change set_attribute(:snapshot_version, 3)`, and the attribute comment
becomes `# 1: I2; 2: adds council (spec I3); 3: adds template (spec I5) — set by the :publish action.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/report_cards_test.exs test/teacher_assistant/report_cards_access_test.exs`
Expected: 0 failures. Then `MIX_TEST_PARTITION=2 mix test` — any test asserting `snapshot_version == 2` is updated to 3
(ledger a ruling if one exists).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/report_cards.ex lib/teacher_assistant/academics/bulletin_publication.ex test/teacher_assistant/report_cards_test.exs
git commit -m "feat: report card views carry their template; publishing freezes it (snapshot v3)"
```

---

### Task 4: The printed card follows the template

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (rewrite below)
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (new `describe "template (spec I5)"`)

**Interfaces:**
- Consumes: `ReportCards.template_of/3`, `BulletinTemplate.show?/2`, `grade/2`, `official_lines/1`, `school_lines/1`.
- Produces: `BulletinPrintHTML.tr(language, fun) :: String.t()` (Task 5 uses the same assigns); the controller assigns
  `template`, `lang`, `class_average`, and each bundle gets `qr_svg: nil` (Task 5 fills it).

- [ ] **Step 1: Write the failing tests**

Add to `bulletin_print_controller_test.exs` (the file's setup gives `conn`, `cg` (francophone 6e A), `seq`, `scope`,
two students with 14/20 in Maths):

```elixir
  describe "template (spec I5)" do
    defp print(conn, cg, seq),
      do: conn |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}") |> html_response(200)

    test "a francophone class prints in French with the official header", %{conn: conn, cg: cg, seq: seq, scope: scope} do
      {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

      {:ok, _} =
        TeacherAssistant.Accounts.update_school_profile(
          profile,
          %{region: :littoral, department: "Wouri", motto: "Discipline – Travail"},
          scope: scope
        )

      html = print(conn, cg, seq)
      assert html =~ ~s(<html lang="fr">)
      assert html =~ "République du Cameroun"
      assert html =~ "Ministère des Enseignements secondaires"
      assert html =~ "Délégation régionale des Enseignements secondaires du Littoral"
      assert html =~ "Wouri"
      assert html =~ "Discipline – Travail"
      assert html =~ "Matière"
      refute html =~ "Subject"
    end

    test "an anglophone class prints in English with grades", %{conn: conn, scope: scope, seq: seq} do
      {:ok, en} =
        TeacherAssistant.Enrollment.create_class_group(scope, scope.current_academic_year || TeacherAssistant.Organization.current_academic_year(scope), %{
          label: "Form 1 A",
          level: "Form 1",
          subsystem: :anglophone
        })

      {:ok, _} = TeacherAssistant.Enrollment.add_student(scope, en, %{full_name: "Ngum Che", sex: :f})

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, en, scope.current_user, %{
          subject: "Biology",
          coefficient: Decimal.new(2)
        })

      {:ok, a} =
        TeacherAssistant.Assessment.create_assessment(scope, tc, seq, %{
          label: "T1",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      [%{student: s}] = TeacherAssistant.Enrollment.list_roster(scope, en)
      TeacherAssistant.Assessment.upsert_marks(scope, a, [%{student_id: s.id, score: Decimal.new(15)}])

      html = print(conn, en, seq)
      assert html =~ ~s(<html lang="en">)
      assert html =~ "Republic of Cameroon"
      assert html =~ "Subject"
      assert html =~ "Grade"
      # 15/20 on the default scale: B, Very good
      assert html =~ "Very good"
      refute html =~ "Matière"
    end

    test "bilingual: both labels, an identical word printed once", %{conn: conn, cg: cg, seq: seq, scope: scope} do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "bilingual",
          "elements" => Enum.map(TeacherAssistant.Academics.BulletinElement.defaults(), &Atom.to_string/1)
        })

      html = print(conn, cg, seq)
      assert html =~ "Matière / Subject"
      assert html =~ "République du Cameroun"
      assert html =~ "Republic of Cameroon"
      refute html =~ "Coefficient / Coefficient"
    end

    test "hidden elements disappear and rows stay balanced", %{conn: conn, cg: cg, seq: seq, scope: scope} do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{"language" => "by_class", "elements" => [""]})

      html = print(conn, cg, seq)
      refute html =~ "Rang"
      refute html =~ "Cote classe"
      refute html =~ "Visa Professeur Principal"
      refute html =~ "Moyenne de la classe"
      refute html =~ "Absences non justifiées"
      assert html =~ "Moyenne générale"
      assert html =~ "Visa Chef d&#39;établissement"

      # Every body row has as many cells as the header (3 columns: Matière, Coefficient, Note, Note×Coef → 4).
      [thead | _] = Regex.run(~r/<thead>.*?<\/thead>/s, html)
      header_cells = length(Regex.scan(~r/<th[ >]/, thead))
      [tfoot | _] = Regex.run(~r/<tfoot>.*?<\/tfoot>/s, html)
      assert length(Regex.scan(~r/<th[ >]/, tfoot)) == header_cells
    end

    test "the class average prints when shown", %{conn: conn, cg: cg, seq: seq} do
      html = print(conn, cg, seq)
      assert html =~ "Moyenne de la classe"
    end

    test "a published card ignores later template changes", %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)

      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{"language" => "bilingual", "elements" => [""]})

      html =
        conn
        |> get(~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}")
        |> html_response(200)

      refute html =~ "Matière / Subject"
      assert html =~ "Rang"
    end
  end
```

`with_year/1` and `first_term/1` already exist in this file (private helpers under `describe "publication"`); if
they are defined after this describe, move them above it or keep them at module level — Elixir resolves private
functions module-wide, so order does not matter.

- [ ] **Step 2: Run them to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: the new tests FAIL (no official header, no English, elements never hidden); the old ones pass.

- [ ] **Step 3: Helpers in `BulletinPrintHTML`**

Replace `lib/teacher_assistant_web/controllers/bulletin_print_html.ex` with:

```elixir
defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{BulletinGroup, BulletinTemplate, Sex}
  alias TeacherAssistantWeb.SanctionLabels

  embed_templates "bulletin_print_html/*"

  @backend TeacherAssistantWeb.Gettext

  @doc """
  Runs `fun` (which calls gettext) in the card's language: French or English, or both
  joined « fr / en » on a bilingual card — once when the two are the same.
  """
  def tr(:fr, fun), do: Gettext.with_locale(@backend, "fr", fun)
  def tr(:en, fun), do: Gettext.with_locale(@backend, "en", fun)

  def tr(:bilingual, fun) do
    case {tr(:fr, fun), tr(:en, fun)} do
      {same, same} -> same
      {fr, en} -> fr <> " / " <> en
    end
  end

  # The header's national block: one column per language.
  defp header_langs(:bilingual), do: [:fr, :en]
  defp header_langs(lang), do: [lang]

  defp official_lines(lang, header), do: tr_list(lang, fn -> BulletinTemplate.official_lines(header) end)

  # The school block is one column: a bilingual card uses French for its few words.
  defp school_lines(lang, header),
    do: tr_list(if(lang == :en, do: :en, else: :fr), fn -> BulletinTemplate.school_lines(header) end)

  defp tr_list(lang, fun) when lang in [:fr, :en],
    do: Gettext.with_locale(@backend, Atom.to_string(lang), fun)

  defp html_lang(:en), do: "en"
  defp html_lang(_), do: "fr"

  defp show?(template, element), do: BulletinTemplate.show?(template, element)

  # Columns between "Coefficient" and "Note×Coef" for each period kind.
  defp period_cols(:trimester), do: 3
  defp period_cols(:annual), do: 4
  defp period_cols(_), do: 1

  # Appreciation (francophone) or Grade + Remark (anglophone), when shown.
  defp mention_cols(template) do
    cond do
      not show?(template, :subject_appreciation) -> 0
      template.grading == :grade -> 2
      true -> 1
    end
  end

  defp min_max_cols(template), do: if(show?(template, :min_max), do: 1, else: 0)

  # Every column after "Note×Coef".
  defp trailing_cols(template), do: mention_cols(template) + min_max_cols(template)

  defp body_cols(kind, template), do: 2 + period_cols(kind) + 1 + trailing_cols(template)

  defp grade(template, mark), do: BulletinTemplate.grade(template.grade_scale, mark)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp comp(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp sex_label(s), do: Sex.label(s)

  defp group_label(g), do: BulletinGroup.label(g)

  defp sanctions_line(sanctions), do: SanctionLabels.sanctions_line(sanctions)
end
```

- [ ] **Step 4: Controller assigns**

In `BulletinPrintController.render_bulletins/8`:
- compute `template = ReportCards.template_of(scope, cg, view)` and `lang = template.language`;
- add `qr_svg: nil` to each bundle map;
- `period_heading:` becomes `BulletinPrintHTML.tr(lang, fn -> period_heading(period) end)`;
- `published_on:` unchanged (the template wraps the sentence);
- add assigns `template: template, lang: lang, class_average: results && results.class_average`;
- `etablissement:` stays (used in `<title>` only).

```elixir
    template = ReportCards.template_of(scope, cg, view)
    lang = template.language
```

and alias `TeacherAssistantWeb.BulletinPrintHTML`.

- [ ] **Step 5: Rewrite the template**

Replace `show.html.heex` with (style block: keep the existing rules, add the four `.header*` and `.qr` rules shown):

```heex
<!DOCTYPE html>
<html lang={html_lang(@lang)}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{tr(@lang, fn -> gettext("Bulletin de notes") end)} — {@cg.label}</title>
    <style>
      /* … every existing rule from the current file, unchanged, minus `.national` … */
      .header { display: flex; justify-content: space-between; gap: 12px; text-align: center; font-size: 9pt; }
      .header .col { flex: 1; }
      .header .col div:first-child { font-variant: small-caps; font-weight: bold; }
      .school { text-align: center; margin: 6px 0; font-size: 10pt; }
      .school .name { font-size: 13pt; font-weight: bold; }
      .school img { max-height: 56px; }
      .qr svg { width: 88px; height: 88px; }
    </style>
  </head>
  <body>
    <section :for={b <- @bundles} class="bulletin-page">
      <div :if={@draft?} class="watermark">{tr(@lang, fn -> gettext("BROUILLON") end)}</div>
      <p :if={@published_on} class="published">
        {tr(@lang, fn -> gettext("Publié le %{date}", date: @published_on) end)}
      </p>

      <div class="header">
        <div :for={l <- header_langs(@lang)} class="col">
          <div :for={line <- official_lines(l, @template.header)}>{line}</div>
        </div>
      </div>
      <div class="school">
        <img :if={@template.header.logo?} src={~p"/school/logo"} alt="" />
        <div
          :for={{line, i} <- Enum.with_index(school_lines(@lang, @template.header))}
          class={i == 0 && "name"}
        >
          {line}
        </div>
      </div>

      <h1>{tr(@lang, fn -> gettext("Bulletin de notes") end)}</h1>

      <table class="cartouche">
        <tr>
          <td class="k">{tr(@lang, fn -> gettext("Année scolaire") end)}</td>
          <td>{@annee || "—"}</td>
          <td class="k">{tr(@lang, fn -> gettext("Période") end)}</td>
          <td>{@period_heading}</td>
        </tr>
        <tr>
          <td class="k">{tr(@lang, fn -> gettext("Nom et prénoms") end)}</td>
          <td>{b.student.full_name}</td>
          <td class="k">{tr(@lang, fn -> gettext("Matricule") end)}</td>
          <td>{b.student.matricule || "—"}</td>
        </tr>
        <tr>
          <td class="k">{tr(@lang, fn -> gettext("Classe") end)}</td>
          <td>{@cg.label} — {@cg.level}</td>
          <td class="k">{tr(@lang, fn -> gettext("Sexe") end)}</td>
          <td>{tr(@lang, fn -> sex_label(b.student.sex) end)}</td>
        </tr>
        <tr :if={show?(@template, :effectif)}>
          <td class="k">{tr(@lang, fn -> gettext("Effectif") end)}</td>
          <td>{@effectif}</td>
          <td></td>
          <td></td>
        </tr>
      </table>

      <%= if b.data do %>
        <table class="body">
          <thead>
            <tr>
              <th>{tr(@lang, fn -> gettext("Matière") end)}</th>
              <th class="num">{tr(@lang, fn -> gettext("Coefficient") end)}</th>
              <%= case @period_kind do %>
                <% :trimester -> %>
                  <th class="num">{tr(@lang, fn -> gettext("Séq 1") end)}</th>
                  <th class="num">{tr(@lang, fn -> gettext("Séq 2") end)}</th>
                  <th class="num">{tr(@lang, fn -> gettext("Moy. trim.") end)}</th>
                <% :annual -> %>
                  <th class="num">{tr(@lang, fn -> gettext("Trim 1") end)}</th>
                  <th class="num">{tr(@lang, fn -> gettext("Trim 2") end)}</th>
                  <th class="num">{tr(@lang, fn -> gettext("Trim 3") end)}</th>
                  <th class="num">{tr(@lang, fn -> gettext("Moy. ann.") end)}</th>
                <% _ -> %>
                  <th class="num">{tr(@lang, fn -> gettext("Note") end)}/20</th>
              <% end %>
              <th class="num">{tr(@lang, fn -> gettext("Note×Coef") end)}</th>
              <%= if show?(@template, :subject_appreciation) do %>
                <%= if @template.grading == :grade do %>
                  <th>{tr(@lang, fn -> gettext("Grade") end)}</th>
                  <th>{tr(@lang, fn -> gettext("Remarque") end)}</th>
                <% else %>
                  <th>{tr(@lang, fn -> gettext("Appréciation") end)}</th>
                <% end %>
              <% end %>
              <th :if={show?(@template, :min_max)} class="num">
                {tr(@lang, fn -> gettext("Cote classe") end)}
              </th>
            </tr>
          </thead>
          <tbody :for={g <- b.data.groups} id={"bulletin-group-#{g.group}"}>
            <tr class="group">
              <th colspan={body_cols(@period_kind, @template)}>
                {tr(@lang, fn -> group_label(g.group) end)}
              </th>
            </tr>
            <tr :for={row <- g.rows}>
              <td>{row.label}</td>
              <td class="num">{fmt(row.coefficient)}</td>
              <%= case @period_kind do %>
                <% :trimester -> %>
                  <td class="num">{fmt(comp(row, :sequences, 0))}</td>
                  <td class="num">{fmt(comp(row, :sequences, 1))}</td>
                  <td class="num">{fmt(row.average)}<sup :if={row.makeup_pending}>R</sup></td>
                <% :annual -> %>
                  <td class="num">{fmt(comp(row, :trimesters, 0))}</td>
                  <td class="num">{fmt(comp(row, :trimesters, 1))}</td>
                  <td class="num">{fmt(comp(row, :trimesters, 2))}</td>
                  <td class="num">{fmt(row.average)}<sup :if={row.makeup_pending}>R</sup></td>
                <% _ -> %>
                  <td class="num">{fmt(row.average)}<sup :if={row.makeup_pending}>R</sup></td>
              <% end %>
              <td class="num">{fmt(row.note_x_coef)}</td>
              <%= if show?(@template, :subject_appreciation) do %>
                <%= if @template.grading == :grade do %>
                  <% g = grade(@template, row.average) %>
                  <td>{g && g.letter}</td>
                  <td>{g && g.remark}</td>
                <% else %>
                  <td>{row.mention && row.mention.label}</td>
                <% end %>
              <% end %>
              <td :if={show?(@template, :min_max)} class="num">
                {fmt(row.class_min)} – {fmt(row.class_max)}
              </td>
            </tr>
            <tr :if={@group_subtotals?} id={"bulletin-group-total-#{g.group}"} class="group-total">
              <td>{tr(@lang, fn -> gettext("Total groupe") end)}</td>
              <td class="num">{fmt(g.total_coef)}</td>
              <td :for={_ <- 2..period_cols(@period_kind)//1}></td>
              <td class="num">{fmt(g.average)}</td>
              <td class="num">{fmt(g.total_points)}</td>
              <td :for={_ <- 1..trailing_cols(@template)//1}></td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <th>
                {tr(@lang, fn -> gettext("Total des coefficients") end)} / {tr(@lang, fn ->
                  gettext("Total des points")
                end)}
              </th>
              <th class="num">{fmt(b.data.total_coef)}</th>
              <th :for={_ <- 1..period_cols(@period_kind)//1}></th>
              <th class="num">{fmt(b.data.total_points)}</th>
              <th :for={_ <- 1..trailing_cols(@template)//1}></th>
            </tr>
          </tfoot>
        </table>
        <p :if={Enum.any?(b.data.subjects, & &1.makeup_pending)} class="legend">
          {tr(@lang, fn -> gettext("R : rattrapage attendu") end)}
        </p>

        <p class="totals">
          <strong>
            {tr(@lang, fn -> gettext("Moyenne générale") end)} : {fmt(b.data.moyenne_generale)}/20
          </strong>
          <span :if={show?(@template, :rank)}>
            &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Rang") end)} : {b.data.rank || "—"}<span :if={
              show?(@template, :effectif)
            }> / {@effectif}</span>
          </span>
          <span :if={show?(@template, :class_average) and @class_average}>
            &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Moyenne de la classe") end)} : {fmt(@class_average)}
          </span>
          <%= if @template.grading == :grade do %>
            <% g = grade(@template, b.data.moyenne_generale) %>
            <span :if={g}>&nbsp;·&nbsp; {tr(@lang, fn -> gettext("Grade") end)} : {g.letter} — {g.remark}</span>
          <% else %>
            <span :if={b.data.mention}>&nbsp;·&nbsp; {b.data.mention.label}</span>
          <% end %>
          <span :if={b.distinction}>
            &nbsp;·&nbsp;
            <strong>
              {tr(@lang, fn -> TeacherAssistant.Academics.Distinction.label(b.distinction) end)}
            </strong>
          </span>
          <span :if={b.outcome && b.outcome.conduct_warning}>
            &nbsp;·&nbsp;
            <strong>
              {tr(@lang, fn ->
                TeacherAssistant.Academics.ConductWarning.label(b.outcome.conduct_warning)
              end)}
            </strong>
          </span>
        </p>
      <% else %>
        <p>{tr(@lang, fn -> gettext("No marks for this séquence yet.") end)}</p>
      <% end %>

      <p :if={b.conduct && show?(@template, :absences)} class="totals">
        <strong>{tr(@lang, fn -> gettext("Assiduité") end)}</strong>
        &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Absences justifiées") end)} : {fmt(
          b.conduct.justified_hours
        )} h &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Absences non justifiées") end)} : {fmt(
          b.conduct.unjustified_hours
        )} h &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Retards") end)} : {b.conduct.retards}
      </p>

      <p :if={b.discipline && show?(@template, :conduct)} class="totals">
        <strong>{tr(@lang, fn -> gettext("Discipline") end)}</strong>
        &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Consignes") end)} : {b.discipline.consignes_count}
        &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Note de conduite") end)} : {fmt(
          b.discipline.note_de_conduite
        )}/20 &nbsp;·&nbsp; {tr(@lang, fn -> gettext("Sanctions") end)} : {tr(@lang, fn ->
          sanctions_line(b.discipline.sanctions)
        end)}
      </p>

      <div class="appreciation">
        <span class="k">{tr(@lang, fn -> gettext("Appréciation du conseil de classe") end)}</span>
        <p :if={b.outcome && b.outcome.appreciation} class="council-text">
          {b.outcome.appreciation}
        </p>
        <div :if={!(b.outcome && b.outcome.appreciation)} class="rule"></div>
      </div>

      <div class="visa">
        <div class="slot">
          <div :if={b.outcome && Map.get(b.outcome, :passage)} class="decision">
            {tr(@lang, fn -> TeacherAssistant.Academics.PassageDecision.label(b.outcome.passage) end)}
          </div>
          <div class="line">{tr(@lang, fn -> gettext("Décision") end)}</div>
        </div>
        <div :if={show?(@template, :pp_signature)} class="slot">
          <div :if={@professeur_principal} class="pp-name">{@professeur_principal}</div>
          <div class="line">{tr(@lang, fn -> gettext("Visa Professeur Principal") end)}</div>
        </div>
        <div class="slot">
          <div class="line">{tr(@lang, fn -> gettext("Visa Chef d'établissement") end)}</div>
        </div>
        <div :if={b.qr_svg} class="qr">{Phoenix.HTML.raw(b.qr_svg)}</div>
      </div>
    </section>
  </body>
</html>
```

Notes for the implementer:
- The old « Conduite » line is renamed « Assiduité » (it shows attendance); its test in this file asserting
  `"Conduite"` on that line — update the expectation and ledger a ruling.
- `Établissement` leaves the cartouche: the school is now in the header. Update any test asserting the cartouche's
  « Établissement » cell; the school name is still on the page.
- The `.national` CSS rule is no longer used; drop it.

- [ ] **Step 5b: English labels now**

The English-card tests need English msgstrs. Do Task 7 Step 1 now (extract, translate the table, fix new fuzzy
entries); Task 7 runs it again for the strings later tasks add.

- [ ] **Step 6: Run the print tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: 0 failures (after the ledgered expectation updates above).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/controllers/bulletin_print_controller.ex lib/teacher_assistant_web/controllers/bulletin_print_html.ex \
  lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs
git commit -m "feat: the printed report card follows the school template (language, header, grades, elements)"
```

---

### Task 5: QR code and public verification page

**Files:**
- Modify: `mix.exs` (deps: `{:eqrcode, "~> 0.2"}`), `mix.lock`
- Create: `lib/teacher_assistant_web/bulletin_verification.ex`
- Modify: `lib/teacher_assistant/report_cards.ex` (new `verification/3`)
- Create: `lib/teacher_assistant_web/controllers/bulletin_verify_controller.ex`, `bulletin_verify_html.ex`,
  `bulletin_verify_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (public `:browser` scope), `bulletin_print_controller.ex` (fill `qr_svg`)
- Test: `test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs`; one test added to the print test

**Interfaces:**
- Consumes: `BulletinPublication` (`workspace_id`, `status`, `snapshot.roster`, `published_at`, `withdrawn_at`),
  `ReportCards.published_on/1`.
- Produces:
  - `ReportCards.verification(workspace_id, publication_id, student_id) :: {:published | :withdrawn, info} | :invalid`,
    `info = %{student_name, school_name, class_label, period_kind, term_position, published_on, withdrawn_on}`
  - `TeacherAssistantWeb.BulletinVerification.token(pub, student_id) :: String.t()`,
    `verify(token) :: {:published | :withdrawn, info} | :invalid`, `qr_svg(url) :: String.t()`

- [ ] **Step 1: Add the dependency**

Add `{:eqrcode, "~> 0.2"}` to `deps` in `mix.exs`; run `mix deps.get`.
Expected: `eqrcode` fetched. Check its API: `mix usage_rules.docs EQRCode.svg` — `EQRCode.encode(text) |> EQRCode.svg(width: n)` returns an SVG string.

- [ ] **Step 2: Write the failing tests**

`test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs`:

```elixir
defmodule TeacherAssistantWeb.BulletinVerifyControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistantWeb.BulletinVerification

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture(%{name: "Lycée Vérif"})
    :ok = TeacherFixtures.verify_school!(scope)
    TeacherFixtures.complete_school_setup!(scope)
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e V", level: "3ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, scope.current_user, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{label: "D1", weight: Decimal.new(1), max_score: Decimal.new(20)})

    [%{student: student}] = Enrollment.list_roster(scope, cg)
    Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(12)}])
    {:ok, pub} = TeacherFixtures.publish_trimester(scope, cg, term)
    %{scope: scope, cg: cg, term: term, pub: pub, student: student}
  end

  test "a published card is authentic, without logging in", %{pub: pub, student: student} do
    html = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(pub, student.id)}") |> html_response(200)
    assert html =~ "Bulletin authentique"
    assert html =~ "Awa Ngo"
    assert html =~ "Lycée Vérif"
    assert html =~ "3e V"
    refute html =~ "Maths"
  end

  test "withdrawn then republished: the old code says withdrawn, the new one authentic",
       %{scope: scope, cg: cg, term: term, pub: pub, student: student} do
    {:ok, _} = ReportCards.withdraw(scope, pub, "Erreur de saisie")
    {:ok, new_pub} = ReportCards.publish(scope, cg, {:trimester, term})

    old = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(pub, student.id)}") |> html_response(200)
    assert old =~ "Ce bulletin a été retiré"
    refute old =~ "Erreur de saisie"

    new = build_conn() |> get(~p"/verify/bulletin/#{BulletinVerification.token(new_pub, student.id)}") |> html_response(200)
    assert new =~ "Bulletin authentique"
  end

  test "tampered, foreign-school and wrong-student tokens are invalid", %{pub: pub, student: student} do
    invalid = fn token ->
      build_conn() |> get(~p"/verify/bulletin/#{token}") |> html_response(200) =~ "Lien de vérification invalide"
    end

    assert invalid.(BulletinVerification.token(pub, student.id) <> "x")
    assert invalid.("not-a-token")

    %{workspace: other} = TeacherFixtures.school_fixture()
    foreign = Phoenix.Token.sign(TeacherAssistantWeb.Endpoint, "bulletin-verify", {other.id, pub.id, student.id})
    assert invalid.(foreign)

    assert invalid.(BulletinVerification.token(pub, Ecto.UUID.generate()))
  end
end
```

Add to the print test's `describe "template (spec I5)"`:

```elixir
    test "the QR prints on published cards only, when chosen", %{conn: conn, cg: cg, scope: scope} do
      scope = with_year(scope)
      term = first_term(scope)
      url = ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term.id}"
      elements = ["qr_code" | Enum.map(TeacherAssistant.Academics.BulletinElement.defaults(), &Atom.to_string/1)]
      {:ok, _} = TeacherAssistant.Assessment.update_bulletin_settings(scope, %{"language" => "by_class", "elements" => elements})

      refute conn |> get(url) |> html_response(200) =~ "<svg"
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(scope, cg, term)
      assert conn |> get(url) |> html_response(200) =~ "<svg"
    end
```

If `TeacherFixtures.verify_school!/1` or `complete_school_setup!/1` returns something other than shown, follow their
actual return in `test/support/fixtures/teacher_fixtures.ex`.

- [ ] **Step 3: Run them to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs`
Expected: FAIL — `BulletinVerification` undefined / no route.

- [ ] **Step 4: Domain read**

In `ReportCards`, add:

```elixir
  @doc """
  What the public verification page may say about a student's card in a publication
  (spec I5). The one read outside authentication: it bypasses policies, scoped to the
  workspace the signed token names, and returns no marks.
  """
  def verification(workspace_id, publication_id, student_id) do
    with {:ok, pub} <-
           Ash.get(BulletinPublication, publication_id,
             tenant: workspace_id,
             authorize?: false,
             load: [:workspace, :class_group, :term]
           ),
         %{student: student} <-
           Enum.find(pub.snapshot.roster, &(&1.student.id == student_id)) do
      {pub.status,
       %{
         student_name: student.full_name,
         school_name: pub.workspace.name,
         class_label: pub.class_group.label,
         period_kind: pub.period_kind,
         term_position: pub.term && pub.term.position,
         published_on: published_on(pub),
         withdrawn_on: pub.withdrawn_at && pub.withdrawn_at |> DateTime.add(3600) |> DateTime.to_date()
       }}
    else
      _ -> :invalid
    end
  end
```

`Ash.get` with a malformed id returns `{:error, _}` → `:invalid`. If loading `:workspace` or `:class_group` under
`authorize?: false` needs the tenant on the load, pass it through `Ash.load(pub, [...], tenant: workspace_id,
authorize?: false)` instead — ledger the ruling.

- [ ] **Step 5: Web token module**

`lib/teacher_assistant_web/bulletin_verification.ex`:

```elixir
defmodule TeacherAssistantWeb.BulletinVerification do
  @moduledoc """
  The QR code on a published report card (spec I5): a signed token over
  `{workspace_id, publication_id, student_id}`, with no expiry, so every reprint
  carries the same code. Rotating `secret_key_base` invalidates printed codes.
  """
  alias TeacherAssistant.ReportCards

  @salt "bulletin-verify"

  def token(pub, student_id),
    do: Phoenix.Token.sign(TeacherAssistantWeb.Endpoint, @salt, {pub.workspace_id, pub.id, student_id})

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TeacherAssistantWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, {workspace_id, publication_id, student_id}} ->
        ReportCards.verification(workspace_id, publication_id, student_id)

      _ ->
        :invalid
    end
  end

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 88)
end
```

- [ ] **Step 6: Public page**

Router — in the first `scope "/", TeacherAssistantWeb do pipe_through :browser` block, after
`get "/locale/:locale", …`:

```elixir
    get "/verify/bulletin/:token", BulletinVerifyController, :show
```

`lib/teacher_assistant_web/controllers/bulletin_verify_controller.ex`:

```elixir
defmodule TeacherAssistantWeb.BulletinVerifyController do
  @moduledoc "Public check of a printed report card's QR code (spec I5): no login, no marks."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.BulletinVerification

  def show(conn, %{"token" => token}) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show, result: BulletinVerification.verify(token))
  end
end
```

`lib/teacher_assistant_web/controllers/bulletin_verify_html.ex`:

```elixir
defmodule TeacherAssistantWeb.BulletinVerifyHTML do
  use TeacherAssistantWeb, :html

  embed_templates "bulletin_verify_html/*"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp period(%{period_kind: :annual}), do: gettext("Année scolaire")
  defp period(%{term_position: n}), do: gettext("Trimestre %{n}", n: n)
end
```

`lib/teacher_assistant_web/controllers/bulletin_verify_html/show.html.heex`:

```heex
<!DOCTYPE html>
<html lang={Gettext.get_locale(TeacherAssistantWeb.Gettext)}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{gettext("Vérification d'un bulletin")}</title>
    <style>
      body { font-family: system-ui, sans-serif; background: #f6f7f6; color: #111; margin: 0; padding: 24px 16px; }
      main { max-width: 480px; margin: 0 auto; background: #fff; border: 1px solid #ddd; border-radius: 12px; padding: 24px; }
      h1 { font-size: 1.3rem; margin: 0 0 12px; }
      .ok { color: #11663a; } .ko { color: #9b2c1f; }
      dl { display: grid; grid-template-columns: auto 1fr; gap: 6px 12px; margin: 0; }
      dt { color: #555; }
    </style>
  </head>
  <body>
    <main>
      <%= case @result do %>
        <% {:published, info} -> %>
          <h1 class="ok">✓ {gettext("Bulletin authentique")}</h1>
          <dl>
            <dt>{gettext("Élève")}</dt><dd>{info.student_name}</dd>
            <dt>{gettext("Établissement")}</dt><dd>{info.school_name}</dd>
            <dt>{gettext("Classe")}</dt><dd>{info.class_label}</dd>
            <dt>{gettext("Période")}</dt><dd>{period(info)}</dd>
            <dt>{gettext("Publié le")}</dt><dd>{date(info.published_on)}</dd>
          </dl>
        <% {:withdrawn, info} -> %>
          <h1 class="ko">{gettext("Ce bulletin a été retiré le %{date}", date: date(info.withdrawn_on))}</h1>
          <dl>
            <dt>{gettext("Élève")}</dt><dd>{info.student_name}</dd>
            <dt>{gettext("Établissement")}</dt><dd>{info.school_name}</dd>
          </dl>
        <% :invalid -> %>
          <h1 class="ko">{gettext("Lien de vérification invalide")}</h1>
      <% end %>
    </main>
  </body>
</html>
```

- [ ] **Step 7: QR on the print**

In `BulletinPrintController.render_bulletins/8`, the bundle's `qr_svg`:

```elixir
          qr_svg:
            pub && BulletinTemplate.show?(template, :qr_code) &&
              BulletinVerification.qr_svg(
                url(~p"/verify/bulletin/#{BulletinVerification.token(pub, student.id)}")
              )
```

(alias `TeacherAssistant.Academics.BulletinTemplate` and `TeacherAssistantWeb.BulletinVerification`; `url/1` comes
from `use TeacherAssistantWeb, :controller` verified routes). A falsy value renders nothing (`:if={b.qr_svg}`); use
`|| nil` if the `&&` chain yields `false`.

- [ ] **Step 8: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: 0 failures.

- [ ] **Step 9: Commit**

```bash
git add mix.exs mix.lock lib/teacher_assistant/report_cards.ex lib/teacher_assistant_web/bulletin_verification.ex \
  lib/teacher_assistant_web/controllers/bulletin_verify_controller.ex lib/teacher_assistant_web/controllers/bulletin_verify_html.ex \
  lib/teacher_assistant_web/controllers/bulletin_verify_html/show.html.heex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/controllers/bulletin_print_controller.ex \
  test/teacher_assistant_web/controllers/bulletin_verify_controller_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs
git commit -m "feat: QR code on published report cards and a public verification page"
```

---

### Task 6: "Modèle de bulletin" settings page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/bulletin_template_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (after `live "/school/settings/passage", …`),
  `lib/teacher_assistant_web/spaces.ex` (item next to `passage()` in both menus), `lib/teacher_assistant_web/live/school/settings_live.ex` (link after `#passage-link`)
- Test: `test/teacher_assistant_web/live/school/bulletin_template_live_test.exs`

**Interfaces:**
- Consumes: Task 1 `Assessment.bulletin_settings/1`, `update_bulletin_settings/2`, `update_grade_scale/2`,
  `reset_grade_scale/1`; `BulletinLanguage.label/1`, `BulletinElement.values/0`, `label/1`;
  Task 2 `BulletinTemplate.official_lines/1`, `school_lines/1`, `resolve/3`.
- Produces: route `/school/settings/bulletin`; DOM ids `#settings-form`, `#grade-scale-form`, `#add-grade`,
  `#remove-grade-<i>`, `#reset-grades`, `#header-preview`, `#bulletin-template-link`, `#settings-error`, `#scale-error`.

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant_web/live/school/bulletin_template_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.BulletinTemplateLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "settings links to the page, which shows the defaults and the header", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#bulletin-template-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")
    assert has_element?(view, "#settings-form input[value='by_class'][checked]")
    assert has_element?(view, "#settings-form input[value='rank'][checked]")
    refute has_element?(view, "#settings-form input[value='qr_code'][checked]")
    assert has_element?(view, "#grade-scale-form input[value='A']")
    assert has_element?(view, "#header-preview", "République du Cameroun")
  end

  test "saves the language and elements, unchecking everything", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")

    view
    |> form("#settings-form", %{bulletin: %{language: "bilingual", elements: [""]}})
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    assert %{language: :bilingual, elements: []} = Assessment.bulletin_settings(scope)
  end

  test "edits the grade scale; a bad scale shows the error; reset restores the default",
       %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")

    view |> element("#remove-grade-5") |> render_click()

    view
    |> form("#grade-scale-form", %{
      grades: %{
        "0" => %{from: "0", letter: "F", remark: "Fail"},
        "1" => %{from: "8", letter: "E", remark: "Weak"},
        "2" => %{from: "10", letter: "D", remark: "Pass"},
        "3" => %{from: "12", letter: "C", remark: "Good"},
        "4" => %{from: "15", letter: "B+", remark: "Very good"}
      }
    })
    |> render_submit()

    assert Assessment.bulletin_settings(scope).custom_scale?
    assert List.last(Assessment.bulletin_settings(scope).grade_scale).letter == "B+"

    view
    |> form("#grade-scale-form", %{grades: %{"0" => %{from: "2", letter: "F", remark: "Fail"}}})
    |> render_submit()

    assert has_element?(view, "#scale-error", "La première tranche doit commencer à 0.")

    view |> element("#reset-grades") |> render_click()
    refute Assessment.bulletin_settings(scope).custom_scale?
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/bulletin")
  end
end
```

(The second-form submit with only row "0" relies on the LiveView keeping the five rows from the previous save; the
form params replace them — `save_grades` builds the rows from the submitted params only, so a single row is saved
and refused for starting at 2.)

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/bulletin_template_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Implement the LiveView**

`lib/teacher_assistant_web/live/school/bulletin_template_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.BulletinTemplateLive do
  @moduledoc """
  Settings → Modèle de bulletin (spec I5, mockup `Paramètres école`): the printed
  card's language mode, the optional elements, the anglophone grade scale, and a
  preview of the official header built from the school profile.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.{BulletinElement, BulletinLanguage, BulletinTemplate, ClassGroup}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      header = BulletinTemplate.resolve(profile, scope.current_workspace.name, %ClassGroup{}).header

      {:ok,
       socket
       |> assign(header: header, settings_error: nil, scale_error: nil)
       |> load(scope)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket, scope) do
    settings = Assessment.bulletin_settings(scope)
    assign(socket, settings: settings, rows: Enum.map(settings.grade_scale, &row/1))
  end

  defp row(band), do: %{from: show(band.from), letter: band.letter, remark: band.remark}

  defp show(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)

  def handle_event("save_settings", %{"bulletin" => params}, socket) do
    params = Map.put_new(params, "elements", [])

    socket.assigns.current_scope
    |> Assessment.update_bulletin_settings(params)
    |> respond(socket, :settings_error)
  end

  def handle_event("add_grade", _params, socket),
    do: {:noreply, update(socket, :rows, &(&1 ++ [%{from: "", letter: "", remark: ""}]))}

  def handle_event("remove_grade", %{"index" => i}, socket),
    do: {:noreply, update(socket, :rows, &List.delete_at(&1, String.to_integer(i)))}

  def handle_event("save_grades", %{"grades" => grades}, socket) do
    rows =
      grades
      |> Enum.sort_by(fn {i, _} -> String.to_integer(i) end)
      |> Enum.map(fn {_, r} -> %{from: r["from"] || "", letter: r["letter"], remark: r["remark"]} end)

    socket = assign(socket, rows: rows)

    socket.assigns.current_scope
    |> Assessment.update_grade_scale(rows)
    |> respond(socket, :scale_error)
  end

  def handle_event("reset_grades", _params, socket) do
    socket.assigns.current_scope
    |> Assessment.reset_grade_scale()
    |> respond(socket, :scale_error)
  end

  defp respond(result, socket, error_key) do
    scope = socket.assigns.current_scope

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> load(scope)
         |> assign(settings_error: nil, scale_error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :invalid_number} ->
        {:noreply, assign(socket, [{error_key, gettext("Utilisez des nombres, par exemple 9,5.")}])}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        message = Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1)))
        {:noreply, assign(socket, [{error_key, message}])}

      {:error, _} ->
        {:noreply, assign(socket, [{error_key, gettext("Réglage non enregistré.")}])}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="bulletin-template" class="space-y-6">
        <.page_header
          eyebrow={gettext("Évaluation")}
          title={gettext("Modèle de bulletin")}
          subtitle={gettext("Ce qui apparaît sur le bulletin imprimé.")}
        />

        <.form
          for={%{}}
          as={:bulletin}
          id="settings-form"
          phx-submit="save_settings"
          class="space-y-4 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <fieldset class="space-y-2">
            <legend class="ta-eyebrow">{gettext("Langue du bulletin")}</legend>
            <label :for={lang <- BulletinLanguage.values()} class="flex items-center gap-2 text-sm">
              <input
                type="radio"
                name="bulletin[language]"
                value={lang}
                checked={@settings.language == lang}
                class="radio radio-sm"
              />
              {BulletinLanguage.label(lang)}
            </label>
            <p class="text-xs text-base-content/60">
              {gettext(
                "Classes francophones : appréciation par matière. Classes anglophones : grade et remarque."
              )}
            </p>
          </fieldset>

          <fieldset class="space-y-2">
            <legend class="ta-eyebrow">{gettext("Éléments affichés")}</legend>
            <input type="hidden" name="bulletin[elements][]" value="" />
            <div class="grid gap-2 sm:grid-cols-2">
              <label :for={el <- BulletinElement.values()} class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  name="bulletin[elements][]"
                  value={el}
                  checked={el in @settings.elements}
                  class="checkbox checkbox-sm"
                />
                {BulletinElement.label(el)}
              </label>
            </div>
          </fieldset>
          <p :if={@settings_error} id="settings-error" class="text-sm text-error">{@settings_error}</p>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </.form>

        <.form
          for={%{}}
          as={:grades}
          id="grade-scale-form"
          phx-submit="save_grades"
          class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <h2 class="ta-eyebrow">{gettext("Grades anglophones (sur 20)")}</h2>
          <div class="grid grid-cols-[90px_70px_minmax(0,1fr)_34px] gap-2 text-xs font-semibold text-base-content/70">
            <span>{gettext("À partir de")}</span><span>{gettext("Grade")}</span>
            <span>{gettext("Remarque")}</span><span></span>
          </div>
          <div
            :for={{row, i} <- Enum.with_index(@rows)}
            class="grid grid-cols-[90px_70px_minmax(0,1fr)_34px] items-center gap-2"
          >
            <input name={"grades[#{i}][from]"} value={row.from} inputmode="decimal" class="input input-sm ta-num text-right" />
            <input name={"grades[#{i}][letter]"} value={row.letter} class="input input-sm" />
            <input name={"grades[#{i}][remark]"} value={row.remark} class="input input-sm w-full" />
            <button
              :if={length(@rows) > 1}
              id={"remove-grade-#{i}"}
              type="button"
              phx-click="remove_grade"
              phx-value-index={i}
              class="btn btn-ghost btn-sm btn-square"
              aria-label={gettext("Retirer")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <p :if={@scale_error} id="scale-error" class="text-sm text-error">{@scale_error}</p>
          <div class="flex flex-wrap gap-2">
            <button id="add-grade" type="button" phx-click="add_grade" class="btn btn-ghost btn-sm">
              {gettext("Ajouter une tranche")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
            <button
              :if={@settings.custom_scale?}
              id="reset-grades"
              type="button"
              phx-click="reset_grades"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Revenir au barème par défaut")}
            </button>
          </div>
        </.form>

        <div id="header-preview" class="rounded-box border border-base-300 bg-base-100 p-4 text-center text-sm">
          <h2 class="ta-eyebrow mb-2">{gettext("En-tête officiel")}</h2>
          <div :for={line <- BulletinTemplate.official_lines(@header)}>{line}</div>
          <div class="mt-2 font-semibold">
            <div :for={line <- BulletinTemplate.school_lines(@header)}>{line}</div>
          </div>
          <p class="mt-2 text-xs text-base-content/60">
            {gettext("Modifiable dans la fiche de l'établissement.")}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

The reset test clicks `#reset-grades`, which only renders when `custom_scale?` — true after the first save in that
test. `Authz` is the alias every school LiveView already uses (see `PassageLive`); if it is not available through
`use TeacherAssistantWeb, :live_view`, copy `PassageLive`'s alias.

- [ ] **Step 4: Route and links**

Router, after `live "/school/settings/passage", School.PassageLive, :index`:

```elixir
      live "/school/settings/bulletin", School.BulletinTemplateLive, :index
```

`spaces.ex`, next to `defp passage`:

```elixir
  defp bulletin_template,
    do:
      item(
        "bulletin_template",
        gettext("Modèle de bulletin"),
        "hero-document-duplicate",
        ~p"/school/settings/bulletin"
      )
```

and add `bulletin_template()` right after each `passage()` call (two menus).

`settings_live.ex`, after the `#passage-link` link:

```heex
          <.link
            id="bulletin-template-link"
            navigate={~p"/school/settings/bulletin"}
            class="link link-primary text-sm"
          >
            {gettext("Modèle de bulletin")}
          </.link>
```

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/bulletin_template_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: 0 failures (if `spaces_test.exs` asserts exact menu lists, add `"bulletin_template"` after `"passage"` and ledger it).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/bulletin_template_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/bulletin_template_live_test.exs
git commit -m "feat: Modèle de bulletin settings page"
```

---

### Task 7: Translations, status, full checks

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (I5 status line)

- [ ] **Step 1: Extract and translate**

Run: `mix gettext.extract --merge`
Then, in `en/…/default.po`, give every new msgid its English text, including at least:

| msgid | en |
|---|---|
| République du Cameroun | Republic of Cameroon |
| Paix – Travail – Patrie | Peace – Work – Fatherland |
| Ministère des Enseignements secondaires | Ministry of Secondary Education |
| Délégation régionale des Enseignements secondaires de l'Adamaoua | Regional Delegation of Secondary Education for Adamawa |
| … du Centre / de l'Est / de l'Extrême-Nord / du Littoral / du Nord / du Nord-Ouest / du Sud / du Sud-Ouest / de l'Ouest | … for the Centre / for the East / for the Far North / for the Littoral / for the North / for the North West / for the South / for the South West / for the West |
| Délégation départementale des Enseignements secondaires : %{department} | Divisional Delegation of Secondary Education: %{department} |
| Tél. %{phone} | Tel. %{phone} |
| Autorisation n° %{number} | Authorisation no. %{number} |
| Matière | Subject |
| Note×Coef | Mark×Coef |
| Remarque | Remark |
| Grade | Grade |
| Assiduité | Attendance |
| Moyenne de la classe | Class average |
| Bulletin authentique | Authentic report card |
| Ce bulletin a été retiré le %{date} | This report card was withdrawn on %{date} |
| Lien de vérification invalide | Invalid verification link |
| Vérification d'un bulletin | Report card check |
| Modèle de bulletin | Report card template |
| Suivre la classe (francophone / anglophone) | Follow the class (francophone / anglophone) |
| Bilingue pour toutes les classes | Bilingual for every class |
| QR de vérification | Verification QR code |

Every existing print label already used (Coefficient, Rang, Moyenne générale, Séq 1, Visa Professeur Principal, …)
must have a non-empty, non-fuzzy English msgstr — check each one the template now renders on an English card. For
the `fr` file, new msgstrs stay empty (msgid is French). Then compare with main:

```bash
git diff main -- priv/gettext | grep -B2 '^+#, fuzzy'
```

Fix every new fuzzy entry (remove the flag and write the correct translation). The fuzzy counts must return to 27 (en)
and 17 (fr): `grep -c '#, fuzzy' priv/gettext/en/LC_MESSAGES/default.po priv/gettext/fr/LC_MESSAGES/default.po`.

- [ ] **Step 2: Status line**

Under `## I5 — Report card template (spec)` add, before "Mockup:":

```markdown
Status: implemented 2026-10-01 (branch `i5-bulletin-template`, plan `docs/superpowers/plans/2026-10-01-i5-bulletin-template.md`); no visual check done.
```

- [ ] **Step 3: Full checks**

Run: `MIX_TEST_PARTITION=2 mix precommit`, then `mix ash.codegen --check`, then `mix compile --warnings-as-errors --force`.
Expected: 0 failures; codegen clean; no warnings. Re-stage any file the formatter rewrote.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test   # only files this branch already changed, reformatted by precommit — check `git status` first
git commit -m "chore: I5 translations and status"
```
