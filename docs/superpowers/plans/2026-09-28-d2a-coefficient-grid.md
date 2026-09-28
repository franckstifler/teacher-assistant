# D2a — Coefficients by level and série, bulletin groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school admin sets each subject's coefficient per level (and per série in the 2nd cycle) and its bulletin group on one grid. Classes read their coefficient live from that grid unless they carry an override. Bulletins list subjects by group, with optional group subtotals.

**Architecture:** A new `SubjectCoefficient` resource stores one row per enabled cell. `TeachingContext` gains a `catalog_subject` link, and its `coefficient` becomes a nullable override. A `from_many?` has_one `grid_coefficient` picks the série cell over the blank-série cell. The calculation `effective_coefficient` is `override || grid cell || subject default`. A pure `CoefficientRules` module resolves cells and validates a proposed grid. `Curriculum.update_coefficient_grid/2` writes it in one `Ash.transact`, like D1's `update_calendar/3`. `Bulletins.aggregate/2` sorts rows by group and returns per-group subtotals.

**Tech Stack:** Elixir 1.20, Ash 3.33 / AshPostgres 2.13, Phoenix LiveView 1.x, daisyUI, Gettext (French msgids, `en` translations).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` § D2a

## Plan rulings (refinements of the spec, decided while planning)

- **Série fallback.** A class in série C uses the (level, "C") cell when it exists, and the (level, blank) cell otherwise. The blank-série cell of a streamed level therefore means "every série unless a série cell overrides it". A new subject's row is seeded with blank-série cells only, so it works for any série. Cost: "not taught in série A only, but taught in C" cannot be expressed. Clear the blank cell and fill the série cells instead.
- **The lookup reads the assignment's own `subsystem`/`level`/`serie`.** These are copied from the class at assignment, and no code path edits a class's level or série. This avoids a relationship path inside `parent(...)`.
- **The grid is its own page.** It lives at `/school/settings/coefficients` (`CoefficientsLive`), linked from the Matières section of Settings, which is already about 850 lines. Adding, renaming and deactivating subjects stay in Settings.
- **`assign_teacher/4` still accepts `subject:` as a name** (every test and the class form pass one) or as a `%Subject{}`. A name resolves to the school's subject of that name, or creates it. The context's `subject` label is set from the resolved subject's name.
- **The relationship is named `catalog_subject`,** because `TeachingContext` already has a `subject` string attribute.
- **The "in use" check and the overrides check look at the active academic year's assignments.**

## Global Constraints

- Migrations are generated, never hand-written. Iterate with `mix ash.codegen --dev`, and finish with the named `mix ash.codegen coefficient_grid` (Task 11). `mix ash.codegen --check` must be clean at the final commit. There is no data backfill (spec point 10): dev and test databases are reset.
- Only coefficients > 0 are valid. User input accepts `,` or `.` as the decimal separator.
- UI copy is written as French gettext msgids. Every new msgid gets an English `msgstr` in `priv/gettext/en/LC_MESSAGES/default.po`. Run `mix gettext.extract --merge` first. Leave unrelated fuzzy entries alone, but un-fuzzy and fill any that match your new msgids.
- Use `<.input>` for form fields. No inline `<script>`. Start every LiveView template with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`.
- Run only each task's own test file(s), plus any existing file the task says it breaks. `mix precommit` runs once, in Task 11. It does not fail on warnings, so also run `mix compile --warnings-as-errors`.
- Some existing tests assign a seeded catalog subject (e.g. "Mathématiques", default 4) without passing a coefficient. They used to get 1 and now get the grid value. When such a test asserts a coefficient or a total, update the expectation to the grid value. Do not change the code to preserve 1.

## Review Focus

1. **A crafted grid submit with an unknown subsystem token, or a subject id from another school.** It is ignored and nothing crashes. Tested in Task 5.
2. **Clearing a série cell while the blank-série cell still covers the class.** This is allowed, because the class falls back. Only clearing the cell a class actually resolves to, with nothing behind it, is refused. Tested in Task 4.
3. **Deleting a subject that classes use.** A flash message appears ("désactivez-la plutôt"), with no crash and no silent failure. Tested in Task 7.
4. **Turning class coefficients off while overrides exist.** This is refused, with the class list. Setting an override while they are off is refused with a flash. Tested in Tasks 6 and 8.
5. **A bulletin for a class whose subjects span no G1 subject.** The empty group heading is hidden, and the subtotal row appears only when the setting is on. Tested in Tasks 9 and 10.

---

### Task 1: `bulletin_group` replaces `Subject.category`

**Files:**
- Create: `lib/teacher_assistant/academics/bulletin_group.ex`
- Delete: `lib/teacher_assistant/academics/subject_category.ex`
- Modify: `lib/teacher_assistant/academics/subject.ex` (attribute + action accept lists)
- Modify: `lib/teacher_assistant/academics/school_templates.ex` (`@general_subjects`, `@technical_subjects`, `to_subjects/1`)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (the two `SubjectCategory` selects and its alias)
- Modify: `test/teacher_assistant/academics/subject_test.exs:30`, `test/teacher_assistant_web/live/school/settings_live_test.exs` (lines ~197–295: `category` params)
- Generated: migration + snapshots

**Interfaces:**
- Produces: `TeacherAssistant.Academics.BulletinGroup` (Ash enum `:g1_lettres | :g2_sciences | :g3_autres`) with `label/1`, `short/1` (`"G1"`…) and `rank/1` (1..3). `Subject.bulletin_group` (default `:g3_autres`), accepted by `Subject` create and update.

- [ ] **Step 1: Write the failing test.** In `test/teacher_assistant/academics/subject_test.exs`, replace `assert s.category == :general` with `assert s.bulletin_group == :g3_autres`. Append to the same module:

```elixir
  test "bulletin groups have labels, short codes and a bulletin order" do
    alias TeacherAssistant.Academics.BulletinGroup

    assert Enum.sort_by([:g3_autres, :g1_lettres, :g2_sciences], &BulletinGroup.rank/1) ==
             [:g1_lettres, :g2_sciences, :g3_autres]

    assert BulletinGroup.short(:g2_sciences) == "G2"
    assert BulletinGroup.label(:g1_lettres) == "Groupe 1 · Lettres"
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `mix test test/teacher_assistant/academics/subject_test.exs`
Expected: FAIL (`bulletin_group` key missing / `BulletinGroup` undefined).

- [ ] **Step 3: Implement.**

`lib/teacher_assistant/academics/bulletin_group.ex`:

```elixir
defmodule TeacherAssistant.Academics.BulletinGroup do
  @moduledoc """
  The group a subject is listed under on the bulletin (mockup "Matières & coefficients"):
  G1 lettres, G2 sciences, G3 autres. Groups order the bulletin rows; subtotals per
  group are a school setting (`SchoolProfile.bulletin_group_subtotals?`).
  """
  use Ash.Type.Enum, values: [:g1_lettres, :g2_sciences, :g3_autres]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:g1_lettres), do: gettext("Groupe 1 · Lettres")
  def label(:g2_sciences), do: gettext("Groupe 2 · Sciences")
  def label(:g3_autres), do: gettext("Groupe 3 · Autres")

  def short(:g1_lettres), do: "G1"
  def short(:g2_sciences), do: "G2"
  def short(:g3_autres), do: "G3"

  def rank(:g1_lettres), do: 1
  def rank(:g2_sciences), do: 2
  def rank(:g3_autres), do: 3
end
```

In `subject.ex`, replace the `:category` attribute with:

```elixir
    attribute :bulletin_group, TeacherAssistant.Academics.BulletinGroup,
      allow_nil?: false,
      default: :g3_autres,
      public?: true
```

and replace `:category` by `:bulletin_group` in both the `create:` and `update:` accept lists.

In `school_templates.ex`, replace the category atom in every tuple with a group:

```elixir
  @general_subjects [
    {"Mathématiques", "MATH", :g2_sciences, 4},
    {"Français", "FR", :g1_lettres, 4},
    {"Anglais", "ANG", :g1_lettres, 2},
    {"Physique", "PHY", :g2_sciences, 2},
    {"Chimie", "CHI", :g2_sciences, 2},
    {"SVT", "SVT", :g2_sciences, 2},
    {"Histoire-Géographie", "HG", :g1_lettres, 2},
    {"ECM", "ECM", :g1_lettres, 1},
    {"Informatique", "INFO", :g2_sciences, 1},
    {"EPS", "EPS", :g3_autres, 1}
  ]

  @technical_subjects [
    {"Technologie", "TECHNO", :g2_sciences, 4},
    {"Dessin technique", "DESS", :g2_sciences, 3},
    {"Atelier / Pratique", "ATEL", :g2_sciences, 4}
  ]
```

and in `to_subjects/1`: `for {name, code, group, coef} <- list, do: %{name: name, code: code, bulletin_group: group, default_coefficient: @dec.(coef)}`.

In `settings_live.ex`, replace `SubjectCategory` with `BulletinGroup` in the alias. Replace both selects (edit row `name="subject_edit[category]"` and create form `field={@subject_form[:category]}`) with:

```heex
                      <.input
                        name="subject_edit[bulletin_group]"
                        type="select"
                        value={to_string(s.bulletin_group)}
                        options={bulletin_group_options()}
                        label={gettext("Groupe du bulletin")}
                      />
```

```heex
              <.input
                field={@subject_form[:bulletin_group]}
                type="select"
                label={gettext("Groupe du bulletin")}
                options={bulletin_group_options()}
              />
```

In the table header, change `gettext("Catégorie")` to `gettext("Groupe du bulletin")`. Add the private helper:

```elixir
  defp bulletin_group_options,
    do: for(g <- BulletinGroup.values(), do: {BulletinGroup.label(g), to_string(g)})
```

Delete `lib/teacher_assistant/academics/subject_category.ex`. In `settings_live_test.exs`, replace every `category: "language"` with `bulletin_group: "g1_lettres"`, and `"category" => "general"` with `"bulletin_group" => "g3_autres"`.

Run `mix gettext.extract --merge` and add English msgstrs: "Group 1 · Humanities", "Group 2 · Sciences", "Group 3 · Other", "Bulletin group".

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/subject_test.exs test/teacher_assistant/academics/subjects_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS. The migration drops `subjects.category` and adds `subjects.bulletin_group`.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant/academics lib/teacher_assistant_web/live/school/settings_live.ex test priv/repo/migrations priv/resource_snapshots priv/gettext
git commit -m "feat: subject bulletin groups replace categories

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `SubjectCoefficient` cells, seeded when a subject is created

**Files:**
- Create: `lib/teacher_assistant/academics/subject_coefficient.ex`
- Create: `lib/teacher_assistant/academics/subject/seed_coefficient_cells.ex`
- Modify: `lib/teacher_assistant/academics/subject.ex` (explicit `create :create` with the change; composite-FK target index)
- Modify: `lib/teacher_assistant/academics/school_templates.ex` (add `grid_subsystems/1`)
- Modify: `lib/teacher_assistant/curriculum.ex` (register the resource; `coefficient_cells/1`)
- Test: `test/teacher_assistant/academics/subject_coefficient_test.exs`

**Interfaces:**
- Produces:
  - `SubjectCoefficient`: `subject_id`, `subsystem :: Academics.Subsystem`, `level :: String.t()`, `serie :: String.t() | nil`, `coefficient :: Decimal.t()`. Unique cell identity with `nils_distinct?: false`. Actions: `:read`, `:destroy`, `:create` (all fields), `:update` (`:coefficient`).
  - `SchoolTemplates.grid_subsystems(:francophone | :anglophone | :bilingual) :: [:francophone | :anglophone]`.
  - `Curriculum.coefficient_cells(scope) :: %{{subject_id, subsystem, level, serie} => %SubjectCoefficient{}}`.
  - Creating a `Subject` creates one blank-série cell per (grid subsystem × `SchoolTemplates.levels_for(school_type, subsystem)`) at `default_coefficient`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.SubjectCoefficientTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.{SchoolTemplates, SubjectCoefficient}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "a new subject is taught at every level of the school, at its default coefficient",
       %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "Musique", default_coefficient: Decimal.new(2)})

    cells =
      scope |> Curriculum.coefficient_cells() |> Map.values() |> Enum.filter(&(&1.subject_id == s.id))

    assert Enum.map(cells, & &1.level) |> Enum.sort() ==
             Enum.sort(~w(6ème 5ème 4ème 3ème 2nde 1ère Terminale))

    assert Enum.all?(cells, &(&1.subsystem == :francophone and is_nil(&1.serie)))
    assert Enum.all?(cells, &Decimal.equal?(&1.coefficient, Decimal.new(2)))
  end

  test "the seeded catalog gets its cells at school creation", %{scope: scope} do
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    assert %SubjectCoefficient{} = Curriculum.coefficient_cells(scope)[{maths.id, :francophone, "2nde", nil}]
  end

  test "one cell per subject, subsystem, level and série, blank série included", %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "Musique"})

    assert {:error, %Ash.Error.Invalid{}} =
             SubjectCoefficient
             |> Ash.Changeset.for_create(
               :create,
               %{subject_id: s.id, subsystem: :francophone, level: "6ème", serie: nil, coefficient: 1},
               scope: scope
             )
             |> Ash.create()
  end

  test "a coefficient must be positive", %{scope: scope} do
    {:ok, s} = Curriculum.create_subject(scope, %{name: "Musique"})

    assert {:error, %Ash.Error.Invalid{}} =
             SubjectCoefficient
             |> Ash.Changeset.for_create(
               :create,
               %{subject_id: s.id, subsystem: :francophone, level: "2nde", serie: "C", coefficient: 0},
               scope: scope
             )
             |> Ash.create()
  end

  test "a bilingual school edits both subsystems" do
    assert SchoolTemplates.grid_subsystems(:bilingual) == [:francophone, :anglophone]
    assert SchoolTemplates.grid_subsystems(:anglophone) == [:anglophone]
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/subject_coefficient_test.exs`
Expected: FAIL (`SubjectCoefficient` / `coefficient_cells/1` undefined).

- [ ] **Step 3: Implement.**

`lib/teacher_assistant/academics/subject_coefficient.ex`:

```elixir
defmodule TeacherAssistant.Academics.SubjectCoefficient do
  @moduledoc """
  One enabled cell of the school's coefficient grid: a subject's coefficient at a
  level (and, for streamed 2nd-cycle levels, a série). A missing row means the
  subject is not taught there. A blank série applies to every série that has no
  cell of its own (see `CoefficientRules.resolve/2`).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "subject_coefficients"
    repo TeacherAssistant.Repo

    references do
      reference :subject,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :coefficient, "subject_coefficients_positive_check",
        check: "coefficient > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:subject_id, :subsystem, :level, :serie, :coefficient],
      update: [:coefficient]
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

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      public?: true

    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true
    attribute :coefficient, :decimal, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :subject, TeacherAssistant.Academics.Subject do
      source_attribute :subject_id
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
    identity :unique_cell, [:subject_id, :subsystem, :level, :serie], nils_distinct?: false
  end
end
```

`lib/teacher_assistant/academics/subject/seed_coefficient_cells.ex`:

```elixir
defmodule TeacherAssistant.Academics.Subject.SeedCoefficientCells do
  @moduledoc """
  A new subject is taught everywhere by default: one blank-série cell per level of
  the school's subsystem(s), at the subject's `default_coefficient`. The admin then
  empties the cells where it is not taught. Runs inside the subject's create
  (covers both `Curriculum.create_subject/2` and the catalog seeded at school
  creation, after the profile exists).
  """
  use Ash.Resource.Change
  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.{SchoolTemplates, SubjectCoefficient}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, subject ->
      case school_profile(subject.workspace_id) do
        nil -> {:ok, subject}
        profile -> seed(subject, profile)
      end
    end)
  end

  # Internal read of the owning school's profile (the subject create is already
  # authorized; this is its own side effect).
  defp school_profile(workspace_id) do
    SchoolProfile
    |> Ash.Query.filter(workspace_id == ^workspace_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp seed(subject, profile) do
    inputs =
      for subsystem <- SchoolTemplates.grid_subsystems(profile.subsystem),
          level <- SchoolTemplates.levels_for(profile.school_type, subsystem) do
        %{
          subject_id: subject.id,
          subsystem: subsystem,
          level: level,
          serie: nil,
          coefficient: subject.default_coefficient
        }
      end

    case Ash.bulk_create(inputs, SubjectCoefficient, :create,
           tenant: subject.workspace_id,
           authorize?: false,
           return_errors?: true,
           stop_on_error?: true
         ) do
      %Ash.BulkResult{status: :success} -> {:ok, subject}
      %Ash.BulkResult{errors: [error | _]} -> {:error, error}
    end
  end
end
```

In `subject.ex`:
- Add a composite-FK target index inside `postgres do`:

```elixir
    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end
```

- In `actions`, remove `create: [...]` from `defaults` and add:

```elixir
    create :create do
      primary? true
      accept [:name, :code, :default_coefficient, :bulletin_group, :position, :active?]
      change TeacherAssistant.Academics.Subject.SeedCoefficientCells
    end
```

In `school_templates.ex`, add below `stream_label/1`:

```elixir
  @doc "The subsystems whose levels appear on the coefficient grid for a school subsystem."
  def grid_subsystems(:bilingual), do: [:francophone, :anglophone]
  def grid_subsystems(subsystem), do: [subsystem]
```

In `curriculum.ex`, add `SubjectCoefficient` to the `Academics` alias list and `resource SubjectCoefficient` inside `resources do`. Then, after `can_manage_subjects?/1`:

```elixir
  # --- Coefficient grid ------------------------------------------------------

  @doc "The school's coefficient grid cells, keyed `{subject_id, subsystem, level, serie}`."
  def coefficient_cells(%Scope{} = scope) do
    SubjectCoefficient
    |> Ash.read!(scope: scope)
    |> Map.new(&{{&1.subject_id, &1.subsystem, &1.level, &1.serie}, &1})
  end
```

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/subject_coefficient_test.exs test/teacher_assistant/academics/subjects_test.exs`
Expected: PASS. The migration creates `subject_coefficients` with a unique index `NULLS NOT DISTINCT`, and adds the `subjects` unique index on `(workspace_id, id)`. If the identity is rejected because the Postgres version is below 15, stop and report it.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/subject_coefficient_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: coefficient grid cells, seeded for every level when a subject is created

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Assignments link to their subject; effective coefficient

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex`
- Modify: `lib/teacher_assistant/curriculum.ex` (`assign_teacher/4`, `parse_coefficient/1`, `set_assignment_coefficient/3`; add `clear_assignment_coefficient/2`, `subjects_taught_in/2`)
- Modify: `test/teacher_assistant/academics/assignments_test.exs` (the "defaults to 1" test)
- Test: `test/teacher_assistant/academics/coefficient_resolution_test.exs`

**Interfaces:**
- Consumes: `SubjectCoefficient`, `Subject` composite-FK index (Task 2).
- Produces:
  - `TeachingContext.subject_id` (required), `belongs_to :catalog_subject`, a nullable `coefficient` (the override), `has_one :grid_coefficient`, calculations `effective_coefficient :: Decimal.t()` and `taught_here? :: boolean`.
  - `:for_class_group` loads `[:teacher, :combined_course, :catalog_subject, :grid_coefficient, :effective_coefficient, :taught_here?]`.
  - `Curriculum.assign_teacher(scope, cg, user, %{subject: String.t() | %Subject{}, coefficient: Decimal.t() | nil, weekly_hours: integer})`
  - `Curriculum.clear_assignment_coefficient(scope, tc) :: {:ok, tc} | {:error, term}`
  - `Curriculum.subjects_taught_in(scope, %ClassGroup{}) :: [%Subject{}]` (active subjects with a resolving cell)
  - `Curriculum.parse_coefficient/1` accepts `"2,5"`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CoefficientResolutionTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Academics.SubjectCoefficient
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

    {:ok, cg_c} =
      Enrollment.create_class_group(scope, year, %{label: "2nde C", level: "2nde", serie: "C"})

    {:ok, cg_a} =
      Enrollment.create_class_group(scope, year, %{label: "2nde A", level: "2nde", serie: "A4"})

    {:ok, musique} =
      Curriculum.create_subject(scope, %{name: "Musique", default_coefficient: Decimal.new(2)})

    blank = Curriculum.coefficient_cells(scope)[{musique.id, :francophone, "2nde", nil}]
    {:ok, _} = blank |> Ash.Changeset.for_update(:update, %{coefficient: 4}, scope: scope) |> Ash.update()

    %{scope: scope, head: head, cg_c: cg_c, cg_a: cg_a, musique: musique}
  end

  defp assign(scope, cg, head, subject) do
    {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: subject})
    [tc] = Curriculum.list_assignments_for_class(scope, cg)
    tc
  end

  defp put_cell(scope, subject, level, serie, coef) do
    {:ok, cell} =
      SubjectCoefficient
      |> Ash.Changeset.for_create(
        :create,
        %{subject_id: subject.id, subsystem: :francophone, level: level, serie: serie, coefficient: coef},
        scope: scope
      )
      |> Ash.create()

    cell
  end

  test "an assignment without override takes the grid value", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")
    assert tc.subject_id == ctx.musique.id
    assert tc.coefficient == nil
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(4))
    assert tc.taught_here?
  end

  test "a série cell beats the blank-série cell, for that série only", ctx do
    put_cell(ctx.scope, ctx.musique, "2nde", "C", 5)
    assert Decimal.equal?(assign(ctx.scope, ctx.cg_c, ctx.head, "Musique").effective_coefficient, 5)
    assert Decimal.equal?(assign(ctx.scope, ctx.cg_a, ctx.head, "Musique").effective_coefficient, 4)
  end

  test "a class override beats the grid, and clearing it returns to the grid", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")
    {:ok, _} = Curriculum.set_assignment_coefficient(ctx.scope, tc, "6,5")
    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new("6.5"))

    {:ok, _} = Curriculum.clear_assignment_coefficient(ctx.scope, tc)
    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    assert tc.coefficient == nil
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(4))
  end

  test "without a cell the subject default applies and the assignment is flagged", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Musique")
    :ok = Ash.destroy(Curriculum.coefficient_cells(ctx.scope)[{ctx.musique.id, :francophone, "2nde", nil}], scope: ctx.scope)
    [tc] = Curriculum.list_assignments_for_class(ctx.scope, ctx.cg_c)
    refute tc.taught_here?
    assert Decimal.equal?(tc.effective_coefficient, Decimal.new(2))
    assert tc.id
  end

  test "only subjects taught at the class's level are offered", ctx do
    assert ctx.musique.id in Enum.map(Curriculum.subjects_taught_in(ctx.scope, ctx.cg_c), & &1.id)
    :ok = Ash.destroy(Curriculum.coefficient_cells(ctx.scope)[{ctx.musique.id, :francophone, "2nde", nil}], scope: ctx.scope)
    refute ctx.musique.id in Enum.map(Curriculum.subjects_taught_in(ctx.scope, ctx.cg_c), & &1.id)
  end

  test "assigning an unknown subject name creates it in the catalog", ctx do
    tc = assign(ctx.scope, ctx.cg_c, ctx.head, "Espagnol")
    assert %{name: "Espagnol"} = Enum.find(Curriculum.list_subjects(ctx.scope), &(&1.id == tc.subject_id))
    assert tc.subject == "Espagnol"
  end
end
```

In `assignments_test.exs`, in "assign accepts a coefficient; defaults to 1", replace the last assertion `assert Decimal.equal?(tc2.coefficient, Decimal.new(1))` with the following. Seeded "Anglais" has default coefficient 2, so its 6ème cell is 2.

```elixir
      assert tc2.coefficient == nil
      [tc2] = Enum.filter(Curriculum.list_assignments_for_class(scope, cg), &(&1.id == tc2.id))
      assert Decimal.equal?(tc2.effective_coefficient, Decimal.new(2))
```

Rename that test to "assign accepts a coefficient override; without one the grid applies".

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/coefficient_resolution_test.exs test/teacher_assistant/academics/assignments_test.exs`
Expected: FAIL (`subject_id` / `effective_coefficient` missing).

- [ ] **Step 3: Implement.**

`teaching_context.ex`:
- In `postgres do … references do`, add:

```elixir
      reference :catalog_subject,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true
```

- Add `:subject_id` to the `create:` and `update:` accept lists.
- In `read :for_class_group`, change the prepare to `prepare build(load: [:teacher, :combined_course, :catalog_subject, :grid_coefficient, :effective_coefficient, :taught_here?], sort: [subject: :asc])`.
- Replace the `:coefficient` attribute with:

```elixir
    # The class override. nil = the coefficient grid (see `effective_coefficient`).
    attribute :coefficient, :decimal, allow_nil?: true, public?: true
```

- In `relationships`, add:

```elixir
    belongs_to :catalog_subject, TeacherAssistant.Academics.Subject do
      source_attribute :subject_id
      allow_nil? false
      public? true
    end

    # The grid cell this assignment resolves to: its série's cell, else the
    # blank-série cell of its level (same rule as `CoefficientRules.resolve/2`).
    has_one :grid_coefficient, TeacherAssistant.Academics.SubjectCoefficient do
      no_attributes? true
      from_many? true
      public? true

      filter expr(
               subject_id == parent(subject_id) and subsystem == parent(subsystem) and
                 level == parent(level) and (serie == parent(serie) or is_nil(serie))
             )

      sort serie: :asc_nils_last
    end
```

- Add after `relationships`:

```elixir
  calculations do
    calculate :effective_coefficient,
              :decimal,
              expr(coefficient || grid_coefficient.coefficient || catalog_subject.default_coefficient) do
      public? true
    end

    calculate :taught_here?, :boolean, expr(not is_nil(grid_coefficient.id)) do
      public? true
    end
  end
```

`curriculum.ex`:
- Replace `assign_teacher/4`'s body with:

```elixir
  def assign_teacher(%Scope{} = scope, %ClassGroup{} = cg, %User{} = teacher, attrs) do
    with :ok <- assignable(scope, teacher),
         {:ok, subject} <- resolve_subject(scope, Map.fetch!(attrs, :subject)) do
      TeachingContext
      |> Ash.Changeset.for_create(
        :create,
        %{
          subject: subject.name,
          subject_id: subject.id,
          weekly_hours: Map.get(attrs, :weekly_hours, 4),
          coefficient: Map.get(attrs, :coefficient),
          level: cg.level,
          serie: cg.serie,
          subsystem: cg.subsystem,
          class_group_id: cg.id,
          teacher_user_id: teacher.id,
          academic_year_id: cg.academic_year_id
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, tc} ->
          {:ok, tc}

        {:error, error} ->
          if already_assigned?(error), do: {:error, :already_assigned}, else: {:error, error}
      end
    end
  end

  # A `%Subject{}`, or a name: the school's subject of that name, created if absent.
  defp resolve_subject(_scope, %Subject{} = subject), do: {:ok, subject}

  defp resolve_subject(%Scope{} = scope, name) when is_binary(name) do
    name = String.trim(name)

    case Enum.find(list_subjects(scope), &(&1.name == name)) do
      %Subject{} = subject -> {:ok, subject}
      nil -> create_subject(scope, %{name: name})
    end
  end
```

- In `parse_coefficient/1` (binary clause), parse `value |> String.trim() |> String.replace(",", ".")`.
- Add after `set_assignment_coefficient/3`:

```elixir
  @doc "Removes a class's coefficient override: the grid applies again."
  def clear_assignment_coefficient(%Scope{} = scope, %TeachingContext{} = tc) do
    tc
    |> Ash.Changeset.for_update(:update, %{coefficient: nil}, scope: scope)
    |> Ash.update()
  end

  @doc "Active subjects with a grid cell for the class's level and série (the assignable ones)."
  def subjects_taught_in(%Scope{} = scope, %ClassGroup{} = cg) do
    cells = coefficient_cells(scope)

    scope
    |> list_subjects()
    |> Enum.filter(fn s ->
      s.active? and
        TeacherAssistant.Academics.CoefficientRules.resolve(cells, %{
          subject_id: s.id,
          subsystem: cg.subsystem,
          level: cg.level,
          serie: cg.serie
        }) != nil
    end)
  end
```

`subjects_taught_in/2` uses `CoefficientRules.resolve/2`, which Task 4 fleshes out. Create the module now with just `resolve/2`, and Task 4 adds `validate/4`:

```elixir
defmodule TeacherAssistant.Academics.CoefficientRules do
  @moduledoc """
  Pure coefficient-grid rules. `cells` is a map keyed `{subject_id, subsystem, level, serie}`
  (values: anything non-nil). An assignment resolves to its série's cell, else to its
  level's blank-série cell, else to nothing (not taught there).
  """

  def resolve(cells, %{subject_id: s, subsystem: sub, level: l, serie: serie}) do
    cond do
      serie != nil and Map.has_key?(cells, {s, sub, l, serie}) -> {s, sub, l, serie}
      Map.has_key?(cells, {s, sub, l, nil}) -> {s, sub, l, nil}
      true -> nil
    end
  end
end
```

(file: `lib/teacher_assistant/academics/coefficient_rules.ex`)

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/coefficient_resolution_test.exs test/teacher_assistant/academics/assignments_test.exs test/teacher_assistant/academics/bulletin_data_test.exs test/teacher_assistant/academics/courses_test.exs`
Expected: PASS. The migration adds `teaching_contexts.subject_id` (not null) with its composite FK, and drops the not-null constraint and default on `coefficient`. If the `from_many?` has_one filter with `parent(...)` fails to compile or query, stop and report it; do not replace it with a hand-written join.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics priv/repo/migrations priv/resource_snapshots
git commit -m "feat: assignments resolve their coefficient from the grid unless overridden

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `CoefficientRules.validate/4`

**Files:**
- Modify: `lib/teacher_assistant/academics/coefficient_rules.ex`
- Test: `test/teacher_assistant/academics/coefficient_rules_test.exs`

**Interfaces:**
- Consumes: `resolve/2` (Task 3).
- Produces: `CoefficientRules.validate(cells, cell_changes, group_changes, assignments) :: :ok | {:error, {:invalid, errors}}` where
  - `cells :: %{key => Decimal.t()}` (current grid), `key = {subject_id, subsystem, level, serie}`
  - `cell_changes :: %{key => Decimal.t() | nil | :invalid}` (`nil` = clear the cell)
  - `group_changes :: %{subject_id => BulletinGroup.t() | :invalid}`
  - `assignments :: [%{subject_id, subsystem, level, serie, class_label}]` (active year)
  - `errors :: %{key => [:invalid_coefficient | {:in_use, [class_label]}], {:group, subject_id} => [:invalid_group]}`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CoefficientRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.CoefficientRules

  @blank {"maths", :francophone, "2nde", nil}
  @serie_c {"maths", :francophone, "2nde", "C"}
  @cells %{@blank => Decimal.new(4), @serie_c => Decimal.new(5)}
  @class_c %{subject_id: "maths", subsystem: :francophone, level: "2nde", serie: "C", class_label: "2nde C"}
  @class_a %{subject_id: "maths", subsystem: :francophone, level: "2nde", serie: "A4", class_label: "2nde A"}

  defp errors(result) do
    assert {:error, {:invalid, errors}} = result
    errors
  end

  test "resolve prefers the série cell, then the blank cell" do
    assert CoefficientRules.resolve(@cells, @class_c) == @serie_c
    assert CoefficientRules.resolve(@cells, @class_a) == @blank
    assert CoefficientRules.resolve(%{}, @class_a) == nil
  end

  test "valid changes pass" do
    assert :ok =
             CoefficientRules.validate(@cells, %{@blank => Decimal.new(3)}, %{"maths" => :g2_sciences}, [@class_a, @class_c])
  end

  test "an unparseable coefficient is reported on its cell" do
    errs = errors(CoefficientRules.validate(@cells, %{@blank => :invalid}, %{}, []))
    assert errs[@blank] == [:invalid_coefficient]
  end

  test "clearing a série cell is allowed while the blank cell covers the class" do
    assert :ok = CoefficientRules.validate(@cells, %{@serie_c => nil}, %{}, [@class_c])
  end

  test "clearing the cell a class resolves to, with nothing behind it, names the classes" do
    errs = errors(CoefficientRules.validate(@cells, %{@blank => nil}, %{}, [@class_a, @class_c]))
    assert errs[@blank] == [{:in_use, ["2nde A"]}]

    errs = errors(CoefficientRules.validate(@cells, %{@blank => nil, @serie_c => nil}, %{}, [@class_a, @class_c]))
    assert errs[@blank] == [{:in_use, ["2nde A"]}]
    assert errs[@serie_c] == [{:in_use, ["2nde C"]}]
  end

  test "an unknown group is reported on the subject" do
    errs = errors(CoefficientRules.validate(@cells, %{}, %{"maths" => :invalid}, []))
    assert errs[{:group, "maths"}] == [:invalid_group]
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/coefficient_rules_test.exs`
Expected: FAIL (`validate/4` undefined). The `resolve` test passes.

- [ ] **Step 3: Implement.** Add to `CoefficientRules`:

```elixir
  @doc """
  Checks a proposed grid edit before anything is written: every changed cell holds a
  positive coefficient or is cleared, every group is known, and no active-year class
  loses the cell it resolves to without another cell behind it.
  """
  def validate(cells, cell_changes, group_changes, assignments) do
    proposed =
      Enum.reduce(cell_changes, cells, fn
        {key, nil}, acc -> Map.delete(acc, key)
        {_key, :invalid}, acc -> acc
        {key, value}, acc -> Map.put(acc, key, value)
      end)

    errors =
      for({key, :invalid} <- cell_changes, do: {key, :invalid_coefficient}) ++
        for({subject_id, :invalid} <- group_changes, do: {{:group, subject_id}, :invalid_group}) ++
        in_use_errors(cells, proposed, assignments)

    case Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1)) do
      map when map_size(map) == 0 -> :ok
      map -> {:error, {:invalid, map}}
    end
  end

  defp in_use_errors(cells, proposed, assignments) do
    assignments
    |> Enum.flat_map(fn a ->
      current = resolve(cells, a)
      if current != nil and resolve(proposed, a) == nil, do: [{current, a.class_label}], else: []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {key, labels} -> {key, {:in_use, labels |> Enum.uniq() |> Enum.sort()}} end)
  end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/coefficient_rules_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/coefficient_rules.ex test/teacher_assistant/academics/coefficient_rules_test.exs
git commit -m "feat: coefficient grid coherence rules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `update_coefficient_grid/2` and the grid layout

**Files:**
- Modify: `lib/teacher_assistant/curriculum.ex` (Coefficient grid section)
- Test: `test/teacher_assistant/academics/coefficient_grid_test.exs`

**Interfaces:**
- Consumes: `coefficient_cells/1` (Task 2), `CoefficientRules.validate/4` (Task 4), `BulletinGroup` (Task 1).
- Produces:
  - `Curriculum.coefficient_grid_layout(scope) :: [%{subsystem, levels: [%{level, streamed?}], series: [String.t()]}]`
  - `Curriculum.grid_assignments(scope) :: [%{subject_id, subsystem, level, serie, class_label, override?}]` (active year)
  - `Curriculum.cell_token({subsystem, level, serie}) :: String.t()` (`"francophone|2nde|C"`, blank série as `""`)
  - `Curriculum.update_coefficient_grid(scope, %{"cells" => %{subject_id => %{token => "4" | ""}}, "groups" => %{subject_id => "g1_lettres"}}) :: :ok | {:error, {:invalid, errors}} | {:error, Ash.Error.t()}`. Only keys present change. Unknown subsystems and foreign subject ids are ignored.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CoefficientGridTest do
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

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "2nde C", level: "2nde", serie: "C"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    %{scope: scope, head: head, cg: cg, maths: maths}
  end

  defp tok(level, serie \\ nil), do: Curriculum.cell_token({:francophone, level, serie})

  test "the layout lists the school's levels and the séries its classes use", %{scope: scope} do
    [%{subsystem: :francophone, levels: levels, series: series}] = Curriculum.coefficient_grid_layout(scope)
    assert %{level: "2nde", streamed?: true} in levels
    assert %{level: "6ème", streamed?: false} in levels
    assert series == ["C"]
  end

  test "saves values, a new série cell, a cleared cell and a group", %{scope: scope, maths: m} do
    params = %{
      "cells" => %{m.id => %{tok("2nde") => "3,5", tok("2nde", "C") => "5", tok("6ème") => ""}},
      "groups" => %{m.id => "g1_lettres"}
    }

    assert :ok = Curriculum.update_coefficient_grid(scope, params)
    cells = Curriculum.coefficient_cells(scope)
    assert Decimal.equal?(cells[{m.id, :francophone, "2nde", nil}].coefficient, Decimal.new("3.5"))
    assert Decimal.equal?(cells[{m.id, :francophone, "2nde", "C"}].coefficient, 5)
    refute Map.has_key?(cells, {m.id, :francophone, "6ème", nil})
    assert Enum.find(Curriculum.list_subjects(scope), &(&1.id == m.id)).bulletin_group == :g1_lettres
  end

  test "an invalid value writes nothing", %{scope: scope, maths: m} do
    params = %{"cells" => %{m.id => %{tok("2nde") => "3", tok("1ère") => "abc"}}}
    assert {:error, {:invalid, errors}} = Curriculum.update_coefficient_grid(scope, params)
    assert errors[{m.id, :francophone, "1ère", nil}] == [:invalid_coefficient]
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 4)
  end

  test "a cell used by a class cannot be cleared", %{scope: scope, head: head, cg: cg, maths: m} do
    {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: m})
    params = %{"cells" => %{m.id => %{tok("2nde") => ""}}}
    assert {:error, {:invalid, errors}} = Curriculum.update_coefficient_grid(scope, params)
    assert errors[{m.id, :francophone, "2nde", nil}] == [{:in_use, ["2nde C"]}]
  end

  test "unknown subsystems and foreign subjects are ignored", %{scope: scope, maths: m} do
    params = %{
      "cells" => %{
        m.id => %{"martian|2nde|" => "9"},
        Ecto.UUID.generate() => %{tok("2nde") => "9"}
      }
    }

    assert :ok = Curriculum.update_coefficient_grid(scope, params)
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 4)
  end

  test "a teacher cannot change the grid", %{scope: scope, maths: m} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    params = %{"cells" => %{m.id => %{tok("2nde") => "9", tok("1ère") => "9"}}}
    assert_forbidden(Curriculum.update_coefficient_grid(teacher, params))
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "1ère", nil}].coefficient, 4)
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/coefficient_grid_test.exs`
Expected: FAIL (`coefficient_grid_layout/1` undefined).

- [ ] **Step 3: Implement.** In `curriculum.ex`'s Coefficient grid section, add `BulletinGroup`, `CoefficientRules`, `SchoolTemplates` and `SubjectCoefficient` to the aliases, then:

```elixir
  @doc """
  What the grid shows: per subsystem, the school's levels (streamed 2nd-cycle levels
  flagged) and the séries its active-year classes use at streamed levels.
  """
  def coefficient_grid_layout(%Scope{} = scope) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    classes = active_classes(scope)

    for subsystem <- SchoolTemplates.grid_subsystems(profile.subsystem) do
      streamed = SchoolTemplates.streams_for(profile.school_type, subsystem).levels

      %{
        subsystem: subsystem,
        levels:
          for(
            level <- SchoolTemplates.levels_for(profile.school_type, subsystem),
            do: %{level: level, streamed?: level in streamed}
          ),
        series:
          classes
          |> Enum.filter(&(&1.subsystem == subsystem and &1.level in streamed and &1.serie))
          |> Enum.map(& &1.serie)
          |> Enum.uniq()
          |> Enum.sort()
      }
    end
  end

  @doc "The active year's assignments, shaped for `CoefficientRules`."
  def grid_assignments(%Scope{} = scope) do
    case scope.current_academic_year do
      nil ->
        []

      year ->
        TeachingContext
        |> Ash.Query.filter(academic_year_id == ^year.id)
        |> Ash.Query.load(:class_group)
        |> Ash.read!(scope: scope)
        |> Enum.map(fn tc ->
          %{
            subject_id: tc.subject_id,
            subsystem: tc.subsystem,
            level: tc.level,
            serie: tc.serie,
            class_label: tc.class_group.label,
            override?: tc.coefficient != nil
          }
        end)
    end
  end

  defp active_classes(%Scope{current_academic_year: nil}), do: []
  defp active_classes(%Scope{} = scope), do: Enrollment.list_class_groups(scope, scope.current_academic_year)

  @doc "Form token of a grid column: `\"francophone|2nde|C\"`, blank série as `\"\"`."
  def cell_token({subsystem, level, serie}), do: "#{subsystem}|#{level}|#{serie}"

  @grid_subsystems %{"francophone" => :francophone, "anglophone" => :anglophone}
  @groups Map.new(BulletinGroup.values(), &{Atom.to_string(&1), &1})

  @doc """
  Saves the coefficient grid and bulletin groups in one transaction, after
  `CoefficientRules` accepts the whole edit. `params` is form-shaped:
  `%{"cells" => %{subject_id => %{cell_token => "4" | ""}}, "groups" => %{subject_id => "g1_lettres"}}`.
  A missing key keeps the stored value; `""` clears a cell. Tokens with an unknown
  subsystem and subject ids outside the school are ignored. Authorization is the
  per-row admin policy: a forbidden row rolls back every write.
  """
  def update_coefficient_grid(%Scope{} = scope, %{} = params) do
    subjects = Map.new(list_subjects(scope), &{&1.id, &1})
    stored = coefficient_cells(scope)
    cell_changes = parse_cell_changes(Map.get(params, "cells", %{}), subjects)
    group_changes = parse_group_changes(Map.get(params, "groups", %{}), subjects)
    current = Map.new(stored, fn {key, cell} -> {key, cell.coefficient} end)

    with :ok <- CoefficientRules.validate(current, cell_changes, group_changes, grid_assignments(scope)),
         {:ok, :ok} <-
           Ash.transact([SubjectCoefficient, Subject], fn ->
             with :ok <- write_cells(cell_changes, stored, scope) do
               write_groups(group_changes, subjects, scope)
             end
           end) do
      :ok
    end
  end

  defp parse_cell_changes(cells_params, subjects) do
    for {subject_id, tokens} <- cells_params,
        Map.has_key?(subjects, subject_id),
        {token, value} <- tokens,
        [sub, level, serie] <- [String.split(token, "|")],
        Map.has_key?(@grid_subsystems, sub),
        into: %{} do
      key = {subject_id, @grid_subsystems[sub], level, if(serie == "", do: nil, else: serie)}

      parsed =
        case String.trim(value) do
          "" ->
            nil

          text ->
            case parse_coefficient(text) do
              {:ok, dec} -> dec
              :error -> :invalid
            end
        end

      {key, parsed}
    end
  end

  defp parse_group_changes(groups_params, subjects) do
    for {subject_id, value} <- groups_params, Map.has_key?(subjects, subject_id), into: %{} do
      {subject_id, Map.get(@groups, value, :invalid)}
    end
  end

  defp write_cells(changes, stored, scope) do
    Enum.reduce_while(changes, :ok, fn {key, value}, :ok ->
      case write_cell(key, value, stored[key], scope) do
        :ok -> {:cont, :ok}
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp write_cell(_key, nil, nil, _scope), do: :ok
  defp write_cell(_key, nil, cell, scope), do: Ash.destroy(cell, scope: scope)

  defp write_cell({subject_id, subsystem, level, serie}, value, nil, scope) do
    SubjectCoefficient
    |> Ash.Changeset.for_create(
      :create,
      %{subject_id: subject_id, subsystem: subsystem, level: level, serie: serie, coefficient: value},
      scope: scope
    )
    |> Ash.create()
  end

  defp write_cell(_key, value, cell, scope) do
    if Decimal.equal?(value, cell.coefficient),
      do: :ok,
      else:
        cell
        |> Ash.Changeset.for_update(:update, %{coefficient: value}, scope: scope)
        |> Ash.update()
  end

  defp write_groups(changes, subjects, scope) do
    Enum.reduce_while(changes, :ok, fn {subject_id, group}, :ok ->
      subject = subjects[subject_id]

      if subject.bulletin_group == group do
        {:cont, :ok}
      else
        case update_subject(scope, subject, %{bulletin_group: group}) do
          {:ok, _} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end
    end)
  end
```

Also check that `scope.current_academic_year` is set by `school_fixture` scopes. If `grid_assignments/1` returns `[]` in the "in use" test because the fixture scope has no `current_academic_year`, fall back to `TeacherAssistant.Organization.current_academic_year(scope)` in both `grid_assignments/1` and `active_classes/1`, and record a ruling.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/coefficient_grid_test.exs`
Expected: PASS (6 tests). If the teacher test returns a wrapped `Invalid` instead of `Forbidden`, unwrap it with `Ash.Error.to_error_class/1` in the domain function, as D1 anticipated. Do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/curriculum.ex test/teacher_assistant/academics/coefficient_grid_test.exs
git commit -m "feat: atomic coefficient grid update

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: School settings: class overrides and group subtotals

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (two attributes; `update` accept list)
- Modify: `lib/teacher_assistant/curriculum.ex` (`set_class_coefficients_allowed/2`, `set_bulletin_group_subtotals/2`, guard in `set_assignment_coefficient/3`)
- Test: `test/teacher_assistant/academics/coefficient_settings_test.exs`

**Interfaces:**
- Consumes: `grid_assignments/1` (Task 5).
- Produces:
  - `SchoolProfile.class_coefficients_allowed? :: boolean` (default true), `SchoolProfile.bulletin_group_subtotals? :: boolean` (default false)
  - `Curriculum.set_class_coefficients_allowed(scope, boolean) :: {:ok, profile} | {:error, {:overrides_exist, [label]}} | {:error, term}`
  - `Curriculum.set_bulletin_group_subtotals(scope, boolean) :: {:ok, profile} | {:error, term}`
  - `set_assignment_coefficient/3` returns `{:error, :class_coefficients_disabled}` when overrides are off.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CoefficientSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}
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

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})
    %{scope: scope, tc: tc}
  end

  test "defaults: class overrides allowed, no group subtotals", %{scope: scope} do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.class_coefficients_allowed?
    refute profile.bulletin_group_subtotals?
  end

  test "overrides cannot be switched off while a class has one", %{scope: scope, tc: tc} do
    {:ok, _} = Curriculum.set_assignment_coefficient(scope, tc, "3")
    assert {:error, {:overrides_exist, ["6e A"]}} = Curriculum.set_class_coefficients_allowed(scope, false)

    {:ok, _} = Curriculum.clear_assignment_coefficient(scope, tc)
    assert {:ok, %{class_coefficients_allowed?: false}} = Curriculum.set_class_coefficients_allowed(scope, false)
  end

  test "with overrides off, a class coefficient cannot be set", %{scope: scope, tc: tc} do
    {:ok, _} = Curriculum.set_class_coefficients_allowed(scope, false)
    assert {:error, :class_coefficients_disabled} = Curriculum.set_assignment_coefficient(scope, tc, "3")
  end

  test "group subtotals can be switched on", %{scope: scope} do
    assert {:ok, %{bulletin_group_subtotals?: true}} = Curriculum.set_bulletin_group_subtotals(scope, true)
  end

  test "a teacher cannot change these settings", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert_forbidden(Curriculum.set_bulletin_group_subtotals(teacher, true))
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/coefficient_settings_test.exs`
Expected: FAIL (attributes missing / functions undefined).

- [ ] **Step 3: Implement.**

`school_profile.ex`: add both attributes in `attributes` (after `:logo_path`), and add both to the `update :update` accept list:

```elixir
    attribute :class_coefficients_allowed?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :bulletin_group_subtotals?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true
```

`curriculum.ex`, in the Coefficient grid section:

```elixir
  @doc """
  Allows or forbids class-specific coefficient overrides. Switching them off is
  refused while active-year classes carry one: overrides are never silently ignored
  or deleted (spec D2a §7).
  """
  def set_class_coefficients_allowed(%Scope{} = scope, allowed?) when is_boolean(allowed?) do
    overridden =
      if allowed?,
        do: [],
        else:
          scope
          |> grid_assignments()
          |> Enum.filter(& &1.override?)
          |> Enum.map(& &1.class_label)
          |> Enum.uniq()
          |> Enum.sort()

    if overridden == [],
      do: update_profile(scope, %{class_coefficients_allowed?: allowed?}),
      else: {:error, {:overrides_exist, overridden}}
  end

  @doc "Shows or hides the per-group subtotal rows on bulletins."
  def set_bulletin_group_subtotals(%Scope{} = scope, on?) when is_boolean(on?),
    do: update_profile(scope, %{bulletin_group_subtotals?: on?})

  defp update_profile(scope, attrs) do
    with {:ok, profile} <- Accounts.fetch_school_profile(scope) do
      Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end
```

Change `set_assignment_coefficient/3` to:

```elixir
  def set_assignment_coefficient(%Scope{} = scope, %TeachingContext{} = tc, value) do
    with {:ok, %{class_coefficients_allowed?: true}} <- Accounts.fetch_school_profile(scope),
         {:ok, dec} <- parse_coefficient(value) do
      tc
      |> Ash.Changeset.for_update(:update, %{coefficient: dec}, scope: scope)
      |> Ash.update()
    else
      {:ok, %{class_coefficients_allowed?: false}} -> {:error, :class_coefficients_disabled}
      :error -> {:error, :invalid_coefficient}
      {:error, error} -> {:error, error}
    end
  end
```

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.reset && MIX_ENV=test mix ash.reset && mix test test/teacher_assistant/academics/coefficient_settings_test.exs test/teacher_assistant/academics/assignments_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib/teacher_assistant test/teacher_assistant/academics/coefficient_settings_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat: school settings for class coefficients and bulletin group subtotals

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The "Matières & coefficients" page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/coefficients_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`:school_workspace` live session)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (a link in `#matieres`; the `delete_subject` handler)
- Test: `test/teacher_assistant_web/live/school/coefficients_live_test.exs`; append one test to `settings_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: `coefficient_grid_layout/1`, `coefficient_cells/1`, `grid_assignments/1`, `cell_token/1`, `update_coefficient_grid/2` (Task 5); `set_class_coefficients_allowed/2`, `set_bulletin_group_subtotals/2` (Task 6); `CoefficientRules.resolve/2`.
- Produces: route `/school/settings/coefficients`. DOM: `#coefficient-grid-form`, one `<tr id="grid-row-<subject_id>">` per subject, inputs `grid[cells][<subject_id>][<token>]` and `grid[groups][<subject_id>]`, view buttons `#grid-view-<subsystem>-<serie or "all">`, `#toggle-class-coefficients`, `#toggle-group-subtotals`, the link `#coefficients-link` in Settings.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.CoefficientsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée G"})

    scope = school_scope(user, school)
    year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "2nde Z", level: "2nde", serie: "C"})
    maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope, cg: cg, maths: maths, user: user}
  end

  defp tok(level, serie \\ nil), do: Curriculum.cell_token({:francophone, level, serie})

  test "settings links to the grid, which lists subjects by group", %{conn: conn, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#coefficients-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    assert has_element?(view, "#grid-row-#{m.id}", "Mathématiques")
    assert has_element?(view, "input[name='grid[cells][#{m.id}][#{tok("2nde")}]'][value='4']")
  end

  test "admin saves a coefficient and a group", %{conn: conn, scope: scope, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")

    view
    |> form("#coefficient-grid-form", %{
      "grid" => %{"cells" => %{m.id => %{tok("2nde") => "5"}}, "groups" => %{m.id => "g1_lettres"}}
    })
    |> render_submit()

    assert render(view) =~ "Coefficients enregistrés."
    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", nil}].coefficient, 5)
  end

  test "clearing a cell a class uses is refused on that cell", ctx do
    {:ok, _} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.user, %{subject: ctx.maths})
    {:ok, view, _} = live(ctx.conn, ~p"/school/settings/coefficients")

    view
    |> form("#coefficient-grid-form", %{"grid" => %{"cells" => %{ctx.maths.id => %{tok("2nde") => ""}}}})
    |> render_submit()

    assert has_element?(view, "#grid-row-#{ctx.maths.id}", "Utilisée par : 2nde Z")
  end

  test "the série view edits série cells over the blank-série value", %{conn: conn, scope: scope, maths: m} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    view |> element("#grid-view-francophone-C") |> render_click()
    assert has_element?(view, "input[name='grid[cells][#{m.id}][#{tok("2nde", "C")}]'][placeholder='4']")

    view
    |> form("#coefficient-grid-form", %{"grid" => %{"cells" => %{m.id => %{tok("2nde", "C") => "6"}}}})
    |> render_submit()

    assert Decimal.equal?(Curriculum.coefficient_cells(scope)[{m.id, :francophone, "2nde", "C"}].coefficient, 6)
  end

  test "switching overrides off is refused while a class has one", ctx do
    {:ok, tc} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.user, %{subject: ctx.maths})
    {:ok, _} = Curriculum.set_assignment_coefficient(ctx.scope, tc, "3")
    {:ok, view, _} = live(ctx.conn, ~p"/school/settings/coefficients")
    view |> element("#toggle-class-coefficients") |> render_click()
    assert render(view) =~ "2nde Z"
    assert {:ok, %{class_coefficients_allowed?: true}} = Accounts.fetch_school_profile(ctx.scope)
  end

  test "group subtotals toggle", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/coefficients")
    view |> element("#toggle-group-subtotals") |> render_click()
    assert {:ok, %{bulletin_group_subtotals?: true}} = Accounts.fetch_school_profile(scope)
  end
end
```

Append to `settings_live_test.exs`:

```elixir
  test "deleting a subject a class uses explains why it stays", %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    maths = Enum.find(TeacherAssistant.Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))
    {:ok, _} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, scope.current_user, %{subject: maths})

    {:ok, view, _} = live(conn, ~p"/school/settings")
    view |> element("#subject-delete-#{maths.id}") |> render_click()
    assert render(view) =~ "Matière utilisée par des classes : désactivez-la plutôt."
    assert Enum.any?(TeacherAssistant.Curriculum.list_subjects(scope), &(&1.id == maths.id))
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/coefficients_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: FAIL (no route; no link; no flash).

- [ ] **Step 3: Implement.**

Router, inside `ash_authentication_live_session :school_workspace` after `/school/settings`:

```elixir
      live "/school/settings/coefficients", School.CoefficientsLive, :index
```

`settings_live.ex`: in `<section :if={@can_manage_subjects?} id="matieres" …>`, right after the `<h2>`:

```heex
          <.link
            id="coefficients-link"
            navigate={~p"/school/settings/coefficients"}
            class="link link-primary text-sm"
          >
            {gettext("Coefficients par niveau et groupes du bulletin")}
          </.link>
```

Replace the `delete_subject` handler:

```elixir
  def handle_event("delete_subject", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = subject <- Enum.find(socket.assigns.subjects, &(&1.id == id)) do
      case Curriculum.delete_subject(subject, scope: scope) do
        {:error, %Ash.Error.Forbidden{}} ->
          {:noreply, Authz.put_not_allowed(socket)}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, gettext("Matière utilisée par des classes : désactivez-la plutôt."))}

        _ ->
          {:noreply, assign(socket, :subjects, Curriculum.list_subjects(scope))}
      end
    else
      _ -> {:noreply, socket}
    end
  end
```

`lib/teacher_assistant_web/live/school/coefficients_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.CoefficientsLive do
  @moduledoc """
  Settings → Matières & coefficients: the coefficient grid (subject × level, per série
  for streamed 2nd-cycle levels), bulletin groups, and the two related school settings.
  An empty cell means "not taught at this level"; in a série view an empty cell
  inherits the blank-série value (shown as placeholder).
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Curriculum}
  alias TeacherAssistant.Academics.{BulletinGroup, CoefficientRules}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace && Curriculum.can_manage_subjects?(scope) do
      [first | _] = layout = Curriculum.coefficient_grid_layout(scope)

      {:ok,
       socket
       |> assign(layout: layout, subsystem: first.subsystem, serie: nil, errors: %{}, submitted: %{})
       |> load_grid()}
    else
      {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    assigns = assign(assigns, :columns, columns(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="coefficients" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Matières & coefficients")} />
        <p class="text-sm text-base-content/70">
          {gettext(
            "Case vide : matière non enseignée à ce niveau. Bordure ambre : une classe a un coefficient propre."
          )}
        </p>

        <div class="flex flex-wrap items-center gap-2">
          <%= for view <- @layout do %>
            <button
              :for={serie <- [nil | view.series]}
              id={"grid-view-#{view.subsystem}-#{serie || "all"}"}
              type="button"
              phx-click="select_view"
              phx-value-subsystem={view.subsystem}
              phx-value-serie={serie || ""}
              class={[
                "btn btn-sm",
                if(view.subsystem == @subsystem and serie == @serie, do: "btn-primary", else: "btn-ghost")
              ]}
            >
              {view_label(view.subsystem, serie, length(@layout) > 1)}
            </button>
          <% end %>
        </div>

        <.form for={%{}} as={:grid} id="coefficient-grid-form" phx-submit="save_grid" class="space-y-3">
          <div class="overflow-x-auto rounded-box border border-base-300">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Matière")}</th>
                  <th>{gettext("Groupe")}</th>
                  <th :for={col <- @columns} class="text-center">{col.level}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={s <- @subjects} id={"grid-row-#{s.id}"} class="align-top">
                  <td class="whitespace-nowrap font-medium">{s.name}</td>
                  <td>
                    <.input
                      type="select"
                      name={"grid[groups][#{s.id}]"}
                      value={to_string(s.bulletin_group)}
                      options={for g <- BulletinGroup.values(), do: {BulletinGroup.short(g), to_string(g)}}
                      errors={error_texts(@errors, {:group, s.id})}
                    />
                  </td>
                  <td :for={col <- @columns} class="min-w-20">
                    <.input
                      type="text"
                      inputmode="decimal"
                      name={"grid[cells][#{s.id}][#{Curriculum.cell_token(col.key)}]"}
                      value={cell_value(@submitted, @cells, s.id, col.key)}
                      placeholder={col.inherits? && fmt(@cells[put_elem(key(s.id, col.key), 3, nil)])}
                      class={[
                        "input input-sm w-16 text-center",
                        MapSet.member?(@overridden, key(s.id, col.key)) && "border-warning"
                      ]}
                      errors={error_texts(@errors, key(s.id, col.key))}
                    />
                  </td>
                </tr>
              </tbody>
              <tfoot>
                <tr>
                  <th colspan="2">{gettext("Total des coefficients")}</th>
                  <th :for={col <- @columns} class="ta-num text-center">
                    {fmt(column_total(@subjects, @cells, col))}
                  </th>
                </tr>
              </tfoot>
            </table>
          </div>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer les coefficients")}</button>
        </.form>

        <div class="rounded-box border border-base-300 bg-base-100 divide-y divide-base-300">
          <div class="flex items-center justify-between gap-4 p-4">
            <div>
              <p class="font-medium">{gettext("Autoriser un coefficient propre à une classe")}</p>
              <p class="text-xs text-base-content/60">{gettext("Modifiable depuis la page de la classe.")}</p>
            </div>
            <input
              id="toggle-class-coefficients"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@profile.class_coefficients_allowed?}
              phx-click="toggle_class_coefficients"
            />
          </div>
          <div class="flex items-center justify-between gap-4 p-4">
            <p class="font-medium">{gettext("Sous-totaux par groupe sur le bulletin")}</p>
            <input
              id="toggle-group-subtotals"
              type="checkbox"
              class="toggle toggle-primary"
              checked={@profile.bulletin_group_subtotals?}
              phx-click="toggle_group_subtotals"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("select_view", %{"subsystem" => sub, "serie" => serie}, socket) do
    view = Enum.find(socket.assigns.layout, &(Atom.to_string(&1.subsystem) == sub))

    if view && (serie == "" or serie in view.series) do
      {:noreply,
       assign(socket, subsystem: view.subsystem, serie: if(serie == "", do: nil, else: serie), errors: %{}, submitted: %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_grid", %{"grid" => params}, socket) do
    case Curriculum.update_coefficient_grid(socket.assigns.current_scope, params) do
      :ok ->
        {:noreply,
         socket
         |> assign(errors: %{}, submitted: %{})
         |> load_grid()
         |> put_flash(:info, gettext("Coefficients enregistrés."))}

      {:error, {:invalid, errors}} ->
        {:noreply,
         socket
         |> assign(errors: errors, submitted: Map.get(params, "cells", %{}))
         |> put_flash(:error, gettext("Coefficients non enregistrés : corrigez les cases signalées."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Coefficients non enregistrés."))}
    end
  end

  def handle_event("save_grid", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_class_coefficients", _params, socket) do
    allowed? = !socket.assigns.profile.class_coefficients_allowed?

    case Curriculum.set_class_coefficients_allowed(socket.assigns.current_scope, allowed?) do
      {:ok, _} ->
        {:noreply, load_grid(socket)}

      {:error, {:overrides_exist, labels}} ->
        {:noreply,
         socket
         |> load_grid()
         |> put_flash(
           :error,
           gettext("%{count} classes ont un coefficient propre : réinitialisez-les d'abord (%{classes}).",
             count: length(labels),
             classes: Enum.join(labels, ", ")
           )
         )}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  def handle_event("toggle_group_subtotals", _params, socket) do
    on? = !socket.assigns.profile.bulletin_group_subtotals?

    case Curriculum.set_bulletin_group_subtotals(socket.assigns.current_scope, on?) do
      {:ok, _} -> {:noreply, load_grid(socket)}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Réglage non enregistré."))}
    end
  end

  defp load_grid(socket) do
    scope = socket.assigns.current_scope
    cells = Map.new(Curriculum.coefficient_cells(scope), fn {k, c} -> {k, c.coefficient} end)
    {:ok, profile} = Accounts.fetch_school_profile(scope)

    overridden =
      for a <- Curriculum.grid_assignments(scope),
          a.override?,
          key = CoefficientRules.resolve(cells, a),
          key != nil,
          into: MapSet.new(),
          do: key

    subjects =
      scope
      |> Curriculum.list_subjects()
      |> Enum.filter(& &1.active?)
      |> Enum.sort_by(&{BulletinGroup.rank(&1.bulletin_group), &1.position, &1.name})

    assign(socket, cells: cells, overridden: overridden, subjects: subjects, profile: profile)
  end

  # Columns of the current view: every level of the subsystem; streamed levels use
  # the selected série (inheriting the blank-série value), others the blank série.
  defp columns(%{layout: layout, subsystem: subsystem, serie: serie}) do
    view = Enum.find(layout, &(&1.subsystem == subsystem))

    for %{level: level, streamed?: streamed?} <- view.levels do
      col_serie = if streamed?, do: serie, else: nil
      %{level: level, key: {subsystem, level, col_serie}, inherits?: col_serie != nil}
    end
  end

  defp key(subject_id, {subsystem, level, serie}), do: {subject_id, subsystem, level, serie}

  defp cell_value(submitted, cells, subject_id, col_key) do
    case get_in(submitted, [subject_id, Curriculum.cell_token(col_key)]) do
      nil -> fmt(cells[key(subject_id, col_key)])
      value -> value
    end
  end

  defp column_total(subjects, cells, col) do
    subjects
    |> Enum.map(fn s ->
      cells[key(s.id, col.key)] || (col.inherits? && cells[put_elem(key(s.id, col.key), 3, nil)]) || nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp error_texts(errors, key), do: Enum.map(Map.get(errors, key, []), &error_text/1)

  defp error_text(:invalid_coefficient), do: gettext("Coefficient invalide.")
  defp error_text(:invalid_group), do: gettext("Groupe invalide.")

  defp error_text({:in_use, labels}),
    do: gettext("Utilisée par : %{classes}", classes: Enum.join(labels, ", "))

  defp view_label(subsystem, nil, true),
    do: "#{TeacherAssistant.Academics.Subsystem.label(subsystem)} · #{gettext("Toutes séries")}"

  defp view_label(_subsystem, nil, false), do: gettext("Toutes séries")
  defp view_label(_subsystem, serie, _), do: gettext("Série %{serie}", serie: serie)

  defp fmt(nil), do: nil
  defp fmt(false), do: nil
  defp fmt(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
end
```

Notes for the implementer:
- `TeacherAssistant.Academics.Subsystem.label/1` exists (see `subsystem.ex`).
- `Authz` is available in LiveViews the same way `SettingsLive` uses it.
- `CoefficientRules.resolve/2` only checks key presence, so it works on the `cells` map of decimals.
- The `for` comprehension in `load_grid/1` binds `key` with `=` inside the generator list. That is valid Elixir.

Run `mix gettext.extract --merge` and add English msgstrs: "Subjects & coefficients", "Empty cell: subject not taught at this level. Amber border: a class has its own coefficient.", "Group", "Save coefficients", "Coefficients saved.", "Coefficients not saved: fix the highlighted cells.", "Coefficients not saved.", "Allow a class-specific coefficient", "Editable from the class page.", "Group subtotals on the bulletin", "%{count} classes have their own coefficient: reset them first (%{classes}).", "Setting not saved.", "Invalid coefficient.", "Invalid group.", "Used by: %{classes}", "All séries", "Série %{serie}", "Coefficients by level and bulletin groups", "Subject used by classes: deactivate it instead.". Reuse existing msgids such as "Paramètres", "Matière" and "Total des coefficients" where they already exist.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/coefficients_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web/live/school/coefficients_live_test.exs test/teacher_assistant_web/live/school/settings_live_test.exs priv/gettext
git commit -m "feat: coefficient grid page with bulletin groups and school settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Class page: taught subjects, effective coefficient, override and reset

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (mount `subject_options`; `assign` handler; the coefficient `<td>`; `set_coefficient` handler; new `reset_coefficient` handler)
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs` (append; update "assign form lists catalog subjects" if needed)
- Modify: gettext files

**Interfaces:**
- Consumes: `subjects_taught_in/2`, `clear_assignment_coefficient/2` (Task 3); `tc.effective_coefficient`, `tc.grid_coefficient`, `tc.taught_here?` loaded by `list_assignments_for_class/2` (Task 3); `SchoolProfile.class_coefficients_allowed?`, `{:error, :class_coefficients_disabled}` (Task 6).
- Produces: DOM `#coefficient-<tc_id>` (form), `#reset-coefficient-<tc_id>`, `#not-taught-<tc_id>`.

- [ ] **Step 1: Write the failing tests** (append inside `describe "assignments panel"`):

```elixir
    test "only subjects taught at the class's level are offered", %{conn: conn, cg: cg, scope: scope} do
      {:ok, s} = TeacherAssistant.Curriculum.create_subject(scope, %{name: "Philosophie"})
      cell = TeacherAssistant.Curriculum.coefficient_cells(scope)[{s.id, :francophone, "6ème", nil}]
      :ok = Ash.destroy(cell, scope: scope)

      {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}")
      refute html =~ "Philosophie"
    end

    test "the class shows the grid coefficient, takes an override and resets it", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#coefficient-#{tc.id} input[value='4']")
      refute has_element?(view, "#reset-coefficient-#{tc.id}")

      view |> form("#coefficient-#{tc.id}", %{"coefficient" => "3"}) |> render_change()
      assert has_element?(view, "#coefficient-#{tc.id} input.border-warning[value='3']")
      assert render(view) =~ "modèle : 4"

      view |> element("#reset-coefficient-#{tc.id}") |> render_click()
      assert has_element?(view, "#coefficient-#{tc.id} input[value='4']")
    end

    test "with class coefficients off the value is read-only", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})
      {:ok, _} = TeacherAssistant.Curriculum.set_class_coefficients_allowed(scope, false)
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      refute has_element?(view, "#coefficient-#{tc.id} input")
      assert has_element?(view, "#assignment-row-#{tc.id}", "4")
    end

    test "an assignment with no grid cell is flagged", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})
      cell = TeacherAssistant.Curriculum.coefficient_cells(scope)[{tc.subject_id, :francophone, "6ème", nil}]
      :ok = Ash.destroy(cell, scope: scope)
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#not-taught-#{tc.id}", "Non enseignée à ce niveau selon la grille")
    end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: the 4 new tests FAIL.

- [ ] **Step 3: Implement.**

In `mount/3`, replace the `subject_options` computation with `subject_options = Curriculum.subjects_taught_in(scope, cg)`, and add to the assigns `class_coefficients_allowed?: class_coefficients_allowed?(scope)`. Add the helper:

```elixir
  defp class_coefficients_allowed?(scope) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.class_coefficients_allowed?
      _ -> false
    end
  end
```

In `handle_event("assign", …)`, delete the `coef = …` block and the `coefficient: coef` entry. The grid supplies the coefficient.

Replace the coefficient `<td>` with:

```heex
                  <td>
                    <form
                      :if={@can_manage_assignments? and @class_coefficients_allowed?}
                      id={"coefficient-#{tc.id}"}
                      phx-change="set_coefficient"
                      class="flex items-center gap-1"
                    >
                      <input type="hidden" name="context-id" value={tc.id} />
                      <input
                        type="text"
                        inputmode="decimal"
                        name="coefficient"
                        value={fmt_coef(tc.effective_coefficient)}
                        class={["input input-bordered input-xs w-16", tc.coefficient && "border-warning"]}
                      />
                      <span :if={tc.coefficient && tc.grid_coefficient} class="text-xs text-base-content/60">
                        {gettext("modèle : %{value}", value: fmt_coef(tc.grid_coefficient.coefficient))}
                      </span>
                      <button
                        :if={tc.coefficient}
                        id={"reset-coefficient-#{tc.id}"}
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="reset_coefficient"
                        phx-value-context-id={tc.id}
                      >
                        {gettext("Revenir au modèle")}
                      </button>
                    </form>
                    <span
                      :if={!(@can_manage_assignments? and @class_coefficients_allowed?)}
                      class="ta-num"
                    >
                      {fmt_coef(tc.effective_coefficient)}
                    </span>
                    <span
                      :if={!tc.taught_here?}
                      id={"not-taught-#{tc.id}"}
                      class="badge badge-warning badge-sm mt-1"
                    >
                      {gettext("Non enseignée à ce niveau selon la grille")}
                    </span>
                  </td>
```

Add the helper `defp fmt_coef(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)`.

In `set_coefficient`'s `else`, add a clause before `_ ->`:

```elixir
      {:error, :class_coefficients_disabled} ->
        {:noreply,
         put_flash(socket, :error, gettext("Les coefficients propres à une classe sont désactivés."))}
```

Add the reset handler next to it:

```elixir
  def handle_event("reset_coefficient", %{"context-id" => cid}, socket) do
    with %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         {:ok, _} <- Curriculum.clear_assignment_coefficient(socket.assigns.current_scope, tc) do
      {:noreply, socket |> put_flash(:info, gettext("Coefficient updated.")) |> load_roster()}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, socket}
    end
  end
```

If the existing test "assign form lists catalog subjects" fails because "Musique" is created after mount, it doesn't: the subject is created before `live/2`, and its cells include 6ème. Leave it unchanged.

Run `mix gettext.extract --merge` and add English msgstrs: "default: %{value}", "Back to default", "Not taught at this level per the grid", "Class-specific coefficients are turned off.".

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/class_live.ex test/teacher_assistant_web/live/school/class_live_test.exs priv/gettext
git commit -m "feat: class page reads the coefficient grid, with override and reset

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Bulletins: effective coefficient, group order, group subtotals

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletins.ex` (`compile/2`, `aggregate/2`)
- Modify: `lib/teacher_assistant/assessment.ex` (`class_subjects/3`, `period_result/4`, `context_label_coef/2`)
- Test: `test/teacher_assistant/academics/bulletins_test.exs` (append), `test/teacher_assistant/academics/bulletin_data_test.exs` (append)

**Interfaces:**
- Consumes: `tc.effective_coefficient`, `tc.catalog_subject` loaded by `list_assignments_for_class/2` (Task 3); `BulletinGroup.rank/1` (Task 1).
- Produces:
  - Subject inputs to `Bulletins.compile/2`/`aggregate/2` accept optional `:group` (default `:g3_autres`) and `:position` (default 0). `class_subjects/3` sets `coefficient: tc.effective_coefficient`, `group`, `position`.
  - Each `per_student[id].subjects` row gains `:group`, and rows are sorted by group rank, position, label.
  - `per_student[id].groups :: [%{group, rows, total_coef, total_points, average}]` holds non-empty groups only, in bulletin order. `total_points`/`average` are nil when nothing in the group is graded.

- [ ] **Step 1: Write the failing tests.** Append to `bulletins_test.exs` (it has the `subject/4` helper):

```elixir
  test "rows are ordered by bulletin group, then position, and grouped with subtotals" do
    students = [%{id: "s1", sex: :m}]

    subjects = [
      "eps" |> subject("EPS", "1", [{"s1", "10"}]) |> Map.merge(%{group: :g3_autres, position: 0}),
      "maths" |> subject("Maths", "4", [{"s1", "15"}]) |> Map.merge(%{group: :g2_sciences, position: 0}),
      "fr" |> subject("Français", "4", [{"s1", "12"}]) |> Map.merge(%{group: :g1_lettres, position: 1}),
      "ang" |> subject("Anglais", "2", [{"s1", nil}]) |> Map.merge(%{group: :g1_lettres, position: 0})
    ]

    d = Bulletins.compile(students, subjects).per_student["s1"]
    assert Enum.map(d.subjects, & &1.label) == ["Anglais", "Français", "Maths", "EPS"]
    assert Enum.map(d.groups, & &1.group) == [:g1_lettres, :g2_sciences, :g3_autres]

    [lettres | _] = d.groups
    assert Enum.map(lettres.rows, & &1.label) == ["Anglais", "Français"]
    assert Decimal.equal?(lettres.total_coef, 4)
    assert Decimal.equal?(lettres.total_points, 48)
    assert Decimal.equal?(lettres.average, 12)

    # (12*4 + 15*4 + 10*1) / 9 — grouping never changes the moyenne générale
    assert Decimal.equal?(d.moyenne_generale, Decimal.div(Decimal.new(118), Decimal.new(9)))
  end

  test "subjects without a group fall in G3, and a group with no graded subject has no average" do
    students = [%{id: "s1", sex: :f}]
    d = Bulletins.compile(students, [subject("x", "X", "1", [{"s1", nil}])]).per_student["s1"]
    assert [%{group: :g3_autres, average: nil, total_points: nil}] = d.groups
  end
```

Append to `bulletin_data_test.exs` (its setup assigns "Maths" with `coefficient: Decimal.new(4)` as an override):

```elixir
  test "class_subjects carries the effective coefficient, bulletin group and position", ctx do
    [subj] = Assessment.class_subjects(ctx.scope, ctx.cg, ctx.seq)
    assert Decimal.equal?(subj.coefficient, Decimal.new(4))
    assert subj.group == :g3_autres
    assert is_integer(subj.position)
  end
```

Check the setup's key names in `bulletin_data_test.exs` (`ctx.scope`, `ctx.cg`, `ctx.seq`) and adapt them to what its setup returns.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/bulletin_data_test.exs`
Expected: the new tests FAIL (no `groups` key; no `group` in `class_subjects`).

- [ ] **Step 3: Implement.**

`bulletins.ex`: alias `TeacherAssistant.Academics.BulletinGroup`. In `compile/2`, add to each input map `group: Map.get(subj, :group, :g3_autres), position: Map.get(subj, :position, 0)`. In `aggregate/2`:
- Each `subject_views` map gets `group: Map.get(subj, :group, :g3_autres), position: Map.get(subj, :position, 0)`.
- Sort `subject_views` right after building them:

```elixir
    subject_views =
      Enum.sort_by(subject_views, &{BulletinGroup.rank(&1.group), &1.position, &1.label})
```

- Add `group: sv.group` to each per-student row map.
- Add `groups: group_subtotals(rows)` to the per-student map (next to `subjects: rows`), with:

```elixir
  # Rows are already in bulletin order, so consecutive rows share a group.
  defp group_subtotals(rows) do
    rows
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [%{group: group} | _] = group_rows ->
      graded = Enum.filter(group_rows, &(&1.average != nil))
      total_coef = sum(Enum.map(graded, & &1.coefficient))
      total_points = sum(Enum.map(graded, & &1.note_x_coef))

      %{
        group: group,
        rows: group_rows,
        total_coef: total_coef,
        total_points: if(graded == [], do: nil, else: total_points),
        average:
          if(Decimal.equal?(total_coef, Decimal.new(0)),
            do: nil,
            else: Decimal.div(total_points, total_coef)
          )
      }
    end)
  end
```

`assessment.ex`:
- In `class_subjects/3`, replace `coefficient: tc.coefficient,` with:

```elixir
        coefficient: tc.effective_coefficient,
        group: tc.catalog_subject.bulletin_group,
        position: tc.catalog_subject.position,
```

- In `period_result/4`, the per-séquence map value becomes `%{label: subj.label, coefficient: subj.coefficient, group: subj.group, position: subj.position, per_student_avg: psa}`.
- Replace `context_label_coef/2` with `context_meta/2` returning the whole map:

```elixir
  defp context_meta(per_seq, cid) do
    {_seq, m} = Enum.find(per_seq, fn {_seq, m} -> Map.has_key?(m, cid) end)
    m[cid]
  end
```

and in the `subject_inputs` builder use `meta = context_meta(per_seq, cid)`, setting `label: meta.label, coefficient: meta.coefficient, group: meta.group, position: meta.position`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/bulletin_data_test.exs test/teacher_assistant/academics/period_results_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/bulletins.ex lib/teacher_assistant/assessment.ex test/teacher_assistant/academics/bulletins_test.exs test/teacher_assistant/academics/bulletin_data_test.exs
git commit -m "feat: bulletins use the effective coefficient and order rows by bulletin group

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Bulletin screen and print: group headings and optional subtotals

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex` (mount assign; table body; helpers)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (`render_bulletins/6` assign)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (table body)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex` (helpers)
- Test: `test/teacher_assistant_web/live/school/bulletin_live_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (append)
- Modify: gettext files

**Interfaces:**
- Consumes: `per_student[id].groups` (Task 9); `SchoolProfile.bulletin_group_subtotals?`, `Curriculum.set_bulletin_group_subtotals/2` (Task 6); `BulletinGroup.label/1`.
- Produces: DOM `#bulletin-group-<group>` (tbody), `#bulletin-group-total-<group>` (subtotal row, only when enabled). Existing `#bulletin-subject-<context_id>` rows are kept.

- [ ] **Step 1: Write the failing tests.** Append to `bulletin_live_test.exs` (its setup assigns "Maths", which is created on the fly and so sits in G3):

```elixir
  test "subjects appear under their bulletin group; subtotals only when enabled", ctx do
    %{conn: conn, cg: cg, enr: enr, seq: seq, scope: scope} = ctx
    path = ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}"

    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#bulletin-group-g3_autres", "Groupe 3 · Autres")
    refute has_element?(view, "#bulletin-group-g1_lettres")
    refute has_element?(view, "#bulletin-group-total-g3_autres")

    {:ok, _} = TeacherAssistant.Curriculum.set_bulletin_group_subtotals(scope, true)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#bulletin-group-total-g3_autres", "Total groupe")
  end
```

Open `bulletin_print_controller_test.exs`, reuse its existing setup and request helper, and append one test. It should GET the single-student print route for a séquence, then assert the response contains "Groupe 3 · Autres" and does not contain "Total groupe". It should then call `Curriculum.set_bulletin_group_subtotals(scope, true)`, GET again, and assert "Total groupe" is present. Write it in that file's own style, using its setup's keys.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: the new tests FAIL.

- [ ] **Step 3: Implement.**

`bulletin_live.ex`: alias `TeacherAssistant.Academics.BulletinGroup`. In `mount/3`, add the assign `group_subtotals?: group_subtotals?(scope)`, with:

```elixir
  defp group_subtotals?(scope) do
    case TeacherAssistant.Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.bulletin_group_subtotals?
      _ -> false
    end
  end

  # Columns between "Coefficient" and "Note×Coef" for each period kind.
  defp period_cols(:trimester), do: 3
  defp period_cols(:annual), do: 4
  defp period_cols(_), do: 1
```

Replace the `<tbody>…</tbody>` of the subjects table with:

```heex
              <tbody :for={g <- @data.groups} id={"bulletin-group-#{g.group}"}>
                <tr class="bg-base-200/60">
                  <th
                    colspan={period_cols(@period_kind) + 4}
                    class="text-xs uppercase tracking-wide text-base-content/70"
                  >
                    {BulletinGroup.label(g.group)}
                  </th>
                </tr>
                <tr :for={row <- g.rows} id={"bulletin-subject-#{row.context_id}"}>
                  <!-- the existing <td> cells of the subject row, unchanged -->
                </tr>
                <tr
                  :if={@group_subtotals?}
                  id={"bulletin-group-total-#{g.group}"}
                  class="font-semibold"
                >
                  <td>{gettext("Total groupe")}</td>
                  <td class="ta-num">{fmt(g.total_coef)}</td>
                  <td :for={_ <- 2..period_cols(@period_kind)//1}></td>
                  <td class="ta-num">{fmt(g.average)}</td>
                  <td class="ta-num">{fmt(g.total_points)}</td>
                  <td></td>
                </tr>
              </tbody>
```

The HTML comment marks where the existing row cells go. Move the current row's `<td>` cells (label, coefficient, the `case @period_kind` block, note×coef, cote classe) there verbatim, and do not leave the comment in the file.

Print (`bulletin_print_controller.ex`): add to `render_bulletins/6`'s `render(:show, …)` the assign `group_subtotals?: group_subtotals?(scope)`, with the same private `group_subtotals?/1` as above. In `bulletin_print_html.ex`, alias `BulletinGroup` and add the same `period_cols/1`. In `show.html.heex`, replace `<tbody>…</tbody>` with the same structure, iterating `b.data.groups`. Use the template's class names: `class="num"` instead of `ta-num`, and `class="group"` on the heading row. Add to the template's `<style>` block:

```css
      tr.group th { text-align: left; font-size: 9pt; text-transform: uppercase; background: #f2f2f2; }
      tr.group-total td { font-weight: 600; }
```

and use `class="group"` on the heading row and `class="group-total"` on the subtotal row.

Run `mix gettext.extract --merge` and add the English msgstr "Group total".

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web priv/gettext
git commit -m "feat: bulletin group headings and optional group subtotals

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Name the migration, full gate

- [ ] **Step 1:** Run `mix ash.codegen coefficient_grid`. This squashes the `_dev` migrations into one named migration. Then run `mix ash.reset && MIX_ENV=test mix ash.reset`. There is no real data, per spec point 10.
- [ ] **Step 2:** Run `mix ash.codegen --check && mix compile --warnings-as-errors && mix precommit`.
  Expected: no drift, no warnings, and the whole suite green (765 + the new tests). Failures in files this plan didn't touch are almost always the Global Constraints case: a test assigned a seeded catalog subject without a coefficient and asserted 1. Update such expectations to the grid value. Anything else is a real bug: use systematic debugging.
- [ ] **Step 3:** Commit the named migration, snapshots and any formatter rewrites (check `git status`):

```bash
git add -A priv/repo/migrations priv/resource_snapshots lib test priv/gettext
git commit -m "chore: name the coefficient grid migration

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
