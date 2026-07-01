# Marks & Mark Register (v1.2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the independent (Francophone) teacher a per-subject mark register — class roster, free-form assessments per séquence, /20 marks, and deterministic séquence/annual statistics for their own subject.

**Architecture:** Four new Ash resources (`ClassGroup`, `Student`, `Assessment`, `Mark`) in the existing `TeacherAssistant.Academics` domain, following the established v1 pattern (AshPostgres, uuid_v7 keys, `authorize?: false` domain functions with manual workspace scoping via `fetch_owned_*` helpers). All statistics come from a pure, unit-tested `Academics.Marks` module — no stored aggregates. Three mobile-first LiveViews (roster, mark entry, séquence summary) in the "Tableau" theme, bilingual via `gettext`, with stable DOM IDs.

**Tech Stack:** Elixir, Ash 3.26 / AshPostgres 2.0, Phoenix LiveView, Decimal, gettext, ExUnit.

## Global Constraints

- **Ash Enums, never bare `:atom`.** Closed value sets use a dedicated `Ash.Type.Enum` module. This plan introduces `TeacherAssistant.Academics.Sex` (`[:m, :f]`) and `TeacherAssistant.Academics.Subsystem` (`[:francophone, :anglophone]`).
- **Francophone only.** Pass mark hard-coded **10/20**. `ClassGroup.subsystem` only ever `:francophone` in v1.2.
- **Deterministic before AI.** All statistics computed in `Academics.Marks`, unit-tested before any UI.
- **Money/marks precision:** use `Decimal` throughout (never floats for scores/averages), matching `Academics.Coverage`.
- **Workspace-scoped.** No tenant fallthrough. `Mark`/`Assessment` authorize through the owning `TeachingContext`'s workspace; `Student` through its `ClassGroup`'s workspace.
- **Domain functions** use `authorize?: false` + explicit `Ash.Query.filter` scoping, exactly like existing `TeacherAssistant.Academics` functions.
- **Mobile-first, bilingual, stable DOM IDs** on every LiveView element a test targets. Wrap all user-facing copy in `gettext(...)`.
- **Migrations** are generated with `mix ash.codegen <name>` then applied with `mix ecto.migrate`. The `test` alias runs `mix ash.setup --quiet` first, so tests see migrations automatically.
- **Commit after every task.** End commit messages with the project's `Co-Authored-By` trailer.

---

### Task 1: `Sex` / `Subsystem` enums + `ClassGroup` resource

**Files:**
- Create: `lib/teacher_assistant/academics/sex.ex`
- Create: `lib/teacher_assistant/academics/subsystem.ex`
- Create: `lib/teacher_assistant/academics/class_group.ex`
- Modify: `lib/teacher_assistant/academics.ex` (alias + `resource ClassGroup` + domain functions)
- Test: `test/teacher_assistant/academics/class_group_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Academics.Sex` — `Ash.Type.Enum`, values `[:m, :f]`
  - `TeacherAssistant.Academics.Subsystem` — `Ash.Type.Enum`, values `[:francophone, :anglophone]`
  - `Academics.create_class_group(%PersonalWorkspace{}, %AcademicYear{}, attrs) :: {:ok, %ClassGroup{}} | {:error, term}`
  - `Academics.list_class_groups(%PersonalWorkspace{}, %AcademicYear{}) :: [%ClassGroup{}]`
  - `Academics.fetch_owned_class_group(id, %PersonalWorkspace{}) :: {:ok, %ClassGroup{}} | {:error, :not_found}`
  - `%ClassGroup{}` fields: `id, label, level, serie, subsystem, personal_workspace_id, academic_year_id`

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/class_group_test.exs
defmodule TeacherAssistant.Academics.ClassGroupTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    %{ws: ws, year: year}
  end

  test "creates a class group scoped to workspace + year", %{ws: ws, year: year} do
    {:ok, cg} =
      Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème", serie: nil})

    assert cg.label == "3e M2"
    assert cg.subsystem == :francophone
    assert cg.personal_workspace_id == ws.id
    assert cg.academic_year_id == year.id
  end

  test "lists class groups for the year", %{ws: ws, year: year} do
    {:ok, _} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    assert [%{label: "3e M2"}] = Academics.list_class_groups(ws, year)
  end

  test "fetch_owned_class_group refuses another workspace's group", %{ws: ws, year: year} do
    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.fetch_owned_class_group(cg.id, other)
    assert {:ok, %{id: id}} = Academics.fetch_owned_class_group(cg.id, ws)
    assert id == cg.id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/class_group_test.exs`
Expected: FAIL — `create_class_group/3 undefined` (and enum/resource modules missing).

- [ ] **Step 3: Create the enum modules**

```elixir
# lib/teacher_assistant/academics/sex.ex
defmodule TeacherAssistant.Academics.Sex do
  use Ash.Type.Enum, values: [:m, :f]
end
```

```elixir
# lib/teacher_assistant/academics/subsystem.ex
defmodule TeacherAssistant.Academics.Subsystem do
  use Ash.Type.Enum, values: [:francophone, :anglophone]
end
```

- [ ] **Step 4: Create the `ClassGroup` resource**

```elixir
# lib/teacher_assistant/academics/class_group.ex
defmodule TeacherAssistant.Academics.ClassGroup do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "class_groups"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :level, :serie, :subsystem, :personal_workspace_id, :academic_year_id],
      update: [:label, :level, :serie, :subsystem]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      default: :francophone,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    has_many :students, TeacherAssistant.Academics.Student
  end

  identities do
    identity :unique_class_group, [:personal_workspace_id, :academic_year_id, :label]
  end
end
```

- [ ] **Step 5: Register resource and add domain functions**

In `lib/teacher_assistant/academics.ex`, add the alias near the others:

```elixir
  alias TeacherAssistant.Academics.ClassGroup
```

Add inside the `resources do ... end` block:

```elixir
    resource ClassGroup
```

Add these functions (place after the teaching-context functions):

```elixir
  def create_class_group(%PersonalWorkspace{} = ws, %AcademicYear{} = year, attrs) do
    attrs =
      attrs
      |> Map.put(:personal_workspace_id, ws.id)
      |> Map.put(:academic_year_id, year.id)
      |> Map.put_new(:subsystem, :francophone)

    ClassGroup |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_class_groups(%PersonalWorkspace{id: ws_id}, %AcademicYear{id: year_id}) do
    ClassGroup
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and academic_year_id == ^year_id)
    |> Ash.Query.sort(label: :asc)
    |> Ash.read!(authorize?: false)
  end

  def fetch_owned_class_group(id, %PersonalWorkspace{id: ws_id}) do
    ClassGroup
    |> Ash.Query.filter(id == ^id and personal_workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end
```

- [ ] **Step 6: Generate migration and run the test**

Run:
```bash
mix ash.codegen add_class_groups
mix test test/teacher_assistant/academics/class_group_test.exs
```
Expected: PASS (3 tests). `ash.codegen` writes a migration under `priv/repo/migrations`; the `test` alias applies it via `ash.setup`.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/ lib/teacher_assistant/academics.ex priv/repo/ test/teacher_assistant/academics/class_group_test.exs
git commit -m "feat: Sex/Subsystem enums + ClassGroup resource with owner-scoped domain fns"
```

---

### Task 2: `Student` resource + roster domain functions

**Files:**
- Create: `lib/teacher_assistant/academics/student.ex`
- Modify: `lib/teacher_assistant/academics.ex` (alias + `resource Student` + functions)
- Test: `test/teacher_assistant/academics/student_test.exs`

**Interfaces:**
- Consumes: `Academics.create_class_group/3`, `%ClassGroup{}`, `Sex` enum (Task 1).
- Produces:
  - `Academics.add_student(%ClassGroup{}, attrs) :: {:ok, %Student{}} | {:error, term}`
  - `Academics.list_students(%ClassGroup{}) :: [%Student{}]` (sorted by `full_name`)
  - `Academics.update_student(%Student{}, attrs) :: {:ok, %Student{}} | {:error, term}`
  - `Academics.delete_student(%Student{}) :: :ok | {:error, term}`
  - `Academics.fetch_owned_student(id, %PersonalWorkspace{}) :: {:ok, %Student{}} | {:error, :not_found}`
  - `%Student{}` fields: `id, full_name, sex, matricule, repeater, class_group_id`

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/student_test.exs
defmodule TeacherAssistant.Academics.StudentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, cg: cg}
  end

  test "adds a student with required sex", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa Bello", sex: :f})
    assert s.full_name == "Awa Bello"
    assert s.sex == :f
    assert s.repeater == false
    assert s.class_group_id == cg.id
  end

  test "lists students alphabetically", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Zoa", sex: :m})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    assert ["Awa", "Zoa"] = Academics.list_students(cg) |> Enum.map(& &1.full_name)
  end

  test "sex is required", %{cg: cg} do
    assert {:error, _} = Academics.add_student(cg, %{full_name: "No Sex"})
  end

  test "fetch_owned_student refuses another workspace", %{ws: ws, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.fetch_owned_student(s.id, other)
    assert {:ok, %{id: id}} = Academics.fetch_owned_student(s.id, ws)
    assert id == s.id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/student_test.exs`
Expected: FAIL — `add_student/2 undefined`.

- [ ] **Step 3: Create the `Student` resource**

```elixir
# lib/teacher_assistant/academics/student.ex
defmodule TeacherAssistant.Academics.Student do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "students"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:full_name, :sex, :matricule, :repeater, :class_group_id],
      update: [:full_name, :sex, :matricule, :repeater]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :full_name, :string, allow_nil?: false, public?: true
    attribute :sex, TeacherAssistant.Academics.Sex, allow_nil?: false, public?: true
    attribute :matricule, :string, allow_nil?: true, public?: true
    attribute :repeater, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 4: Register resource and add domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.Student`, add `resource Student` to the resources block, and add:

```elixir
  def add_student(%ClassGroup{id: cg_id}, attrs) do
    attrs = Map.put(attrs, :class_group_id, cg_id)
    Student |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_students(%ClassGroup{id: cg_id}) do
    Student
    |> Ash.Query.filter(class_group_id == ^cg_id)
    |> Ash.Query.sort(full_name: :asc)
    |> Ash.read!(authorize?: false)
  end

  def update_student(%Student{} = s, attrs),
    do: s |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_student(%Student{} = s), do: Ash.destroy(s, authorize?: false)

  def fetch_owned_student(id, %PersonalWorkspace{} = ws) do
    case Ash.get(Student, id, authorize?: false) do
      {:ok, student} ->
        case fetch_owned_class_group(student.class_group_id, ws) do
          {:ok, _} -> {:ok, student}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end
```

- [ ] **Step 5: Generate migration and run the test**

Run:
```bash
mix ash.codegen add_students
mix test test/teacher_assistant/academics/student_test.exs
```
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/student.ex lib/teacher_assistant/academics.ex priv/repo/ test/teacher_assistant/academics/student_test.exs
git commit -m "feat: Student resource + owner-scoped roster domain fns"
```

---

### Task 3: `Assessment` resource + link `TeachingContext` to `ClassGroup`

**Files:**
- Create: `lib/teacher_assistant/academics/assessment.ex`
- Modify: `lib/teacher_assistant/academics/teaching_context.ex` (add nullable `class_group_id` relationship + update action)
- Modify: `lib/teacher_assistant/academics.ex` (aliases + `resource Assessment` + functions)
- Test: `test/teacher_assistant/academics/assessment_test.exs`

**Interfaces:**
- Consumes: `Academics.create_teaching_context/3`, `Academics.create_class_group/3`, `Academics.list_sequences/1` (existing), `%Sequence{}`.
- Produces:
  - `Academics.link_class_group(%TeachingContext{}, %ClassGroup{}) :: {:ok, %TeachingContext{}}`
  - `Academics.create_assessment(%TeachingContext{}, %Sequence{}, attrs) :: {:ok, %Assessment{}} | {:error, term}`
  - `Academics.list_assessments(%TeachingContext{}, %Sequence{}) :: [%Assessment{}]`
  - `Academics.fetch_owned_assessment(id, %PersonalWorkspace{}) :: {:ok, %Assessment{}} | {:error, :not_found}`
  - `%Assessment{}` fields: `id, label, weight, max_score, given_on, teaching_context_id, sequence_id`

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/assessment_test.exs
defmodule TeacherAssistant.Academics.AssessmentTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    %{ws: ws, ctx: ctx, cg: cg, seq: seq}
  end

  test "links a class group to a teaching context", %{ctx: ctx, cg: cg} do
    {:ok, ctx2} = Academics.link_class_group(ctx, cg)
    assert ctx2.class_group_id == cg.id
  end

  test "creates an assessment with defaults", %{ctx: ctx, seq: seq} do
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    assert a.label == "Devoir 1"
    assert Decimal.equal?(a.weight, Decimal.new(1))
    assert Decimal.equal?(a.max_score, Decimal.new(20))
    assert a.teaching_context_id == ctx.id
    assert a.sequence_id == seq.id
  end

  test "lists assessments for a context + sequence", %{ctx: ctx, seq: seq} do
    {:ok, _} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    {:ok, _} = Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})
    assert length(Academics.list_assessments(ctx, seq)) == 2
  end

  test "fetch_owned_assessment refuses another workspace", %{ws: ws, ctx: ctx, seq: seq} do
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    other = TeacherFixtures.workspace_fixture()
    assert {:error, :not_found} = Academics.fetch_owned_assessment(a.id, other)
    assert {:ok, %{id: id}} = Academics.fetch_owned_assessment(a.id, ws)
    assert id == a.id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/assessment_test.exs`
Expected: FAIL — `link_class_group/2 undefined`.

- [ ] **Step 3: Add nullable `class_group` to `TeachingContext`**

In `lib/teacher_assistant/academics/teaching_context.ex`, add `:class_group_id` to the `update` action list:

```elixir
      update: [:subject, :level, :serie, :subsystem, :weekly_hours, :class_group_id]
```

And add this relationship inside the `relationships do ... end` block:

```elixir
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? true
      public? true
    end
```

- [ ] **Step 4: Create the `Assessment` resource**

```elixir
# lib/teacher_assistant/academics/assessment.ex
defmodule TeacherAssistant.Academics.Assessment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "assessments"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :weight, :max_score, :given_on, :teaching_context_id, :sequence_id],
      update: [:label, :weight, :max_score, :given_on]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :weight, :decimal, allow_nil?: false, default: Decimal.new(1), public?: true
    attribute :max_score, :decimal, allow_nil?: false, default: Decimal.new(20), public?: true
    attribute :given_on, :date, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end

    has_many :marks, TeacherAssistant.Academics.Mark
  end
end
```

> Note: `has_many :marks` references the `Mark` resource created in Task 4. The reference compiles because Ash resolves relationships lazily by module name; `Mark` need not exist yet to compile this file, but Task 4 must land before running the full suite. If you run this task's test in isolation before Task 4, temporarily omit the `has_many :marks` line and restore it in Task 4.

- [ ] **Step 5: Register resource and add domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.Assessment`, add `resource Assessment` to the resources block, and add:

```elixir
  def link_class_group(%TeachingContext{} = ctx, %ClassGroup{id: cg_id}) do
    ctx
    |> Ash.Changeset.for_update(:update, %{class_group_id: cg_id})
    |> Ash.update(authorize?: false)
  end

  def create_assessment(%TeachingContext{} = ctx, %Sequence{id: seq_id}, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:sequence_id, seq_id)

    Assessment |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_assessments(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    Assessment
    |> Ash.Query.filter(teaching_context_id == ^ctx_id and sequence_id == ^seq_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def fetch_owned_assessment(id, %PersonalWorkspace{} = ws) do
    case Ash.get(Assessment, id, authorize?: false) do
      {:ok, assessment} ->
        case fetch_owned_teaching_context(assessment.teaching_context_id, ws) do
          {:ok, _} -> {:ok, assessment}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end
```

- [ ] **Step 6: Generate migration and run the test**

Run:
```bash
mix ash.codegen add_assessments_and_context_class_group
mix test test/teacher_assistant/academics/assessment_test.exs
```
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/ lib/teacher_assistant/academics.ex priv/repo/ test/teacher_assistant/academics/assessment_test.exs
git commit -m "feat: Assessment resource + link TeachingContext to ClassGroup"
```

---

### Task 4: `Mark` resource + transactional mark upsert

**Files:**
- Create: `lib/teacher_assistant/academics/mark.ex`
- Modify: `lib/teacher_assistant/academics.ex` (alias + `resource Mark` + functions)
- Test: `test/teacher_assistant/academics/mark_test.exs`

**Interfaces:**
- Consumes: `Academics.create_assessment/3`, `Academics.add_student/2`, `%Assessment{}`, `%Student{}`.
- Produces:
  - `Academics.upsert_marks(%Assessment{}, [%{student_id: id, score: Decimal.t() | nil}]) :: :ok | {:error, term}` — one transaction; creates or updates the `(assessment, student)` mark; a `nil` score clears/records absent.
  - `Academics.list_marks(%Assessment{}) :: [%Mark{}]`
  - `Academics.list_marks_for_context_sequence(%TeachingContext{}, %Sequence{}) :: [%Mark{}]` (all marks across the context's assessments in that séquence)
  - `%Mark{}` fields: `id, score, assessment_id, student_id`

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/mark_test.exs
defmodule TeacherAssistant.Academics.MarkTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    %{ctx: ctx, seq: seq, a: a, s1: s1, s2: s2}
  end

  test "upsert creates marks", %{a: a, s1: s1, s2: s2} do
    :ok =
      Academics.upsert_marks(a, [
        %{student_id: s1.id, score: Decimal.new("15")},
        %{student_id: s2.id, score: Decimal.new("9")}
      ])

    scores =
      Academics.list_marks(a)
      |> Map.new(fn m -> {m.student_id, m.score} end)

    assert Decimal.equal?(scores[s1.id], Decimal.new("15"))
    assert Decimal.equal?(scores[s2.id], Decimal.new("9"))
  end

  test "upsert updates an existing mark (no duplicate)", %{a: a, s1: s1} do
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("18")}])
    assert [m] = Academics.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("18"))
  end

  test "nil score records absent", %{a: a, s1: s1} do
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: nil}])
    assert [m] = Academics.list_marks(a)
    assert m.score == nil
  end

  test "list_marks_for_context_sequence spans assessments", %{ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, a2} = Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Academics.upsert_marks(a2, [%{student_id: s1.id, score: Decimal.new("11")}])
    assert length(Academics.list_marks_for_context_sequence(ctx, seq)) == 2
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/mark_test.exs`
Expected: FAIL — `upsert_marks/2 undefined`.

- [ ] **Step 3: Create the `Mark` resource**

```elixir
# lib/teacher_assistant/academics/mark.ex
defmodule TeacherAssistant.Academics.Mark do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "marks"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:score, :assessment_id, :student_id],
      update: [:score]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :score, :decimal, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :assessment, TeacherAssistant.Academics.Assessment do
      source_attribute :assessment_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_mark, [:assessment_id, :student_id]
  end
end
```

- [ ] **Step 4: Register resource and add domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.Mark`, add `resource Mark` to the resources block, and add:

```elixir
  def upsert_marks(%Assessment{id: assessment_id}, entries) do
    result =
      Repo.transaction(fn ->
        existing =
          Mark
          |> Ash.Query.filter(assessment_id == ^assessment_id)
          |> Ash.read!(authorize?: false)
          |> Map.new(fn m -> {m.student_id, m} end)

        Enum.each(entries, fn %{student_id: student_id} = entry ->
          score = Map.get(entry, :score)

          case Map.get(existing, student_id) do
            nil ->
              Mark
              |> Ash.Changeset.for_create(:create, %{
                assessment_id: assessment_id,
                student_id: student_id,
                score: score
              })
              |> Ash.create!(authorize?: false)

            %Mark{} = mark ->
              mark
              |> Ash.Changeset.for_update(:update, %{score: score})
              |> Ash.update!(authorize?: false)
          end
        end)
      end)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_marks(%Assessment{id: assessment_id}) do
    Mark
    |> Ash.Query.filter(assessment_id == ^assessment_id)
    |> Ash.read!(authorize?: false)
  end

  def list_marks_for_context_sequence(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    assessment_ids =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^ctx_id and sequence_id == ^seq_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    Mark
    |> Ash.Query.filter(assessment_id in ^assessment_ids)
    |> Ash.read!(authorize?: false)
  end
```

- [ ] **Step 5: Generate migration and run the test**

Run:
```bash
mix ash.codegen add_marks
mix test test/teacher_assistant/academics/mark_test.exs
```
Expected: PASS (4 tests). If Task 3 omitted `has_many :marks`, restore that line now.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/ lib/teacher_assistant/academics.ex priv/repo/ test/teacher_assistant/academics/mark_test.exs
git commit -m "feat: Mark resource + transactional upsert_marks + context-sequence query"
```

---

### Task 5: `Academics.Marks` pure statistics module (TDD)

**Files:**
- Create: `lib/teacher_assistant/academics/marks.ex`
- Test: `test/teacher_assistant/academics/marks_test.exs`

**Interfaces:**
- Consumes: nothing (pure functions over plain maps, like `Academics.Coverage`).
- Produces:
  - `Marks.summarize(students, assessments, marks) :: map` where:
    - `students` = `[%{id: id, sex: :m | :f}]`
    - `assessments` = `[%{id: id, weight: Decimal.t(), max_score: Decimal.t()}]`
    - `marks` = `[%{assessment_id: id, student_id: id, score: Decimal.t() | nil}]`
    - returns `%{per_student: %{student_id => %{average: Decimal.t() | nil, mention: atom | nil, rank: integer | nil}}, class_average: Decimal.t() | nil, pass_rate: float, highest: Decimal.t() | nil, lowest: Decimal.t() | nil, graded_count: integer, by_sex: %{m: sex_stats, f: sex_stats}}` where `sex_stats = %{class_average: Decimal.t() | nil, pass_rate: float, graded_count: integer}`
  - `Marks.annual_average([Decimal.t() | nil]) :: Decimal.t() | nil` — unweighted mean of the non-nil séquence averages
  - `Marks.mention(Decimal.t() | nil) :: :passable | :assez_bien | :bien | :tres_bien | :excellent | nil`

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/marks_test.exs
defmodule TeacherAssistant.Academics.MarksTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Marks

  defp d(n), do: Decimal.new(n)

  describe "mention/1" do
    test "bands per domain doc" do
      assert Marks.mention(d("9")) == nil
      assert Marks.mention(d("10")) == :passable
      assert Marks.mention(d("12")) == :assez_bien
      assert Marks.mention(d("14")) == :bien
      assert Marks.mention(d("16")) == :tres_bien
      assert Marks.mention(d("18")) == :excellent
      assert Marks.mention(nil) == nil
    end
  end

  describe "annual_average/1" do
    test "unweighted mean of non-nil sequence averages" do
      assert Decimal.equal?(Marks.annual_average([d("10"), d("14"), nil]), d("12"))
    end

    test "nil when nothing graded" do
      assert Marks.annual_average([nil, nil]) == nil
    end
  end

  describe "summarize/3" do
    setup do
      students = [%{id: "s1", sex: :f}, %{id: "s2", sex: :m}, %{id: "s3", sex: :m}]

      assessments = [
        %{id: "a1", weight: d("1"), max_score: d("20")},
        %{id: "a2", weight: d("2"), max_score: d("20")}
      ]

      # s1: (16*1 + 10*2)/3 = 12 ; s2: (8*1 + 8*2)/3 = 8 ; s3: no marks -> nil
      marks = [
        %{assessment_id: "a1", student_id: "s1", score: d("16")},
        %{assessment_id: "a2", student_id: "s1", score: d("10")},
        %{assessment_id: "a1", student_id: "s2", score: d("8")},
        %{assessment_id: "a2", student_id: "s2", score: d("8")}
      ]

      %{result: Marks.summarize(students, assessments, marks)}
    end

    test "weighted per-student averages and mentions", %{result: r} do
      assert Decimal.equal?(r.per_student["s1"].average, d("12"))
      assert r.per_student["s1"].mention == :assez_bien
      assert Decimal.equal?(r.per_student["s2"].average, d("8"))
      assert r.per_student["s3"].average == nil
      assert r.per_student["s3"].mention == nil
    end

    test "ranking, ungraded students unranked", %{result: r} do
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 2
      assert r.per_student["s3"].rank == nil
    end

    test "class stats exclude ungraded", %{result: r} do
      assert Decimal.equal?(r.class_average, d("10"))
      assert r.graded_count == 2
      assert r.pass_rate == 0.5
      assert Decimal.equal?(r.highest, d("12"))
      assert Decimal.equal?(r.lowest, d("8"))
    end

    test "gender split", %{result: r} do
      assert Decimal.equal?(r.by_sex.f.class_average, d("12"))
      assert r.by_sex.f.pass_rate == 1.0
      assert Decimal.equal?(r.by_sex.m.class_average, d("8"))
      assert r.by_sex.m.pass_rate == 0.0
      assert r.by_sex.m.graded_count == 1
    end
  end

  describe "summarize/3 ties" do
    test "ex-aequo share a rank" do
      students = [%{id: "s1", sex: :f}, %{id: "s2", sex: :m}]
      assessments = [%{id: "a1", weight: d("1"), max_score: d("20")}]

      marks = [
        %{assessment_id: "a1", student_id: "s1", score: d("14")},
        %{assessment_id: "a1", student_id: "s2", score: d("14")}
      ]

      r = Marks.summarize(students, assessments, marks)
      assert r.per_student["s1"].rank == 1
      assert r.per_student["s2"].rank == 1
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/academics/marks_test.exs`
Expected: FAIL — `Marks.mention/1 undefined`.

- [ ] **Step 3: Implement the pure module**

```elixir
# lib/teacher_assistant/academics/marks.ex
defmodule TeacherAssistant.Academics.Marks do
  @moduledoc """
  Pure, deterministic per-subject mark statistics (Francophone /20).
  No database access — operates on plain maps, like `Academics.Coverage`.
  """

  @pass Decimal.new(10)
  @scale Decimal.new(20)

  @doc "Mention label for a /20 average, per domain doc bands (10/12/14/16/18)."
  def mention(nil), do: nil

  def mention(%Decimal{} = avg) do
    cond do
      Decimal.compare(avg, Decimal.new(18)) != :lt -> :excellent
      Decimal.compare(avg, Decimal.new(16)) != :lt -> :tres_bien
      Decimal.compare(avg, Decimal.new(14)) != :lt -> :bien
      Decimal.compare(avg, Decimal.new(12)) != :lt -> :assez_bien
      Decimal.compare(avg, @pass) != :lt -> :passable
      true -> nil
    end
  end

  @doc "Unweighted mean of the non-nil séquence averages (Cameroon annual rule)."
  def annual_average(sequence_averages) do
    graded = Enum.reject(sequence_averages, &is_nil/1)
    mean(graded)
  end

  @doc "Full per-séquence subject summary. See module docs / plan for the shape."
  def summarize(students, assessments, marks) do
    weights = Map.new(assessments, fn a -> {a.id, a} end)

    marks_by_student =
      marks
      |> Enum.group_by(& &1.student_id)

    per_student =
      Map.new(students, fn s ->
        avg = student_average(Map.get(marks_by_student, s.id, []), weights)
        {s.id, %{average: avg, mention: mention(avg), rank: nil}}
      end)

    per_student = assign_ranks(per_student)

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

  # --- per-student weighted average, normalized to /20 over non-nil marks ---

  defp student_average(marks, weights) do
    contributions =
      marks
      |> Enum.reject(&is_nil(&1.score))
      |> Enum.map(fn m ->
        a = Map.fetch!(weights, m.assessment_id)
        normalized = Decimal.mult(Decimal.div(m.score, a.max_score), @scale)
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

  # --- ranking: sort graded desc, ties share a rank (ex-aequo) ---

  defp assign_ranks(per_student) do
    ranked =
      per_student
      |> Enum.filter(fn {_id, %{average: a}} -> not is_nil(a) end)
      |> Enum.sort_by(fn {_id, %{average: a}} -> a end, &(Decimal.compare(&1, &2) != :lt))

    {ranks, _, _} =
      Enum.reduce(ranked, {%{}, 0, nil}, fn {id, %{average: a}}, {acc, index, prev} ->
        position = index + 1
        rank = if prev && Decimal.equal?(prev, a), do: Map.get(acc, :last_rank, position), else: position
        acc = acc |> Map.put(id, rank) |> Map.put(:last_rank, rank)
        {acc, position, a}
      end)

    Map.new(per_student, fn {id, data} ->
      {id, %{data | rank: Map.get(ranks, id)}}
    end)
  end

  # --- aggregates ---

  defp graded_averages(students, per_student) do
    students
    |> Enum.map(fn s -> per_student[s.id].average end)
    |> Enum.reject(&is_nil/1)
  end

  defp sex_stats(students, per_student, sex) do
    graded =
      students
      |> Enum.filter(fn s -> s.sex == sex end)
      |> Enum.map(fn s -> per_student[s.id].average end)
      |> Enum.reject(&is_nil/1)

    %{class_average: mean(graded), pass_rate: pass_rate(graded), graded_count: length(graded)}
  end

  defp pass_rate([]), do: 0.0

  defp pass_rate(averages) do
    passed = Enum.count(averages, fn a -> Decimal.compare(a, @pass) != :lt end)
    passed / length(averages)
  end

  defp mean([]), do: nil

  defp mean(list) do
    sum = Enum.reduce(list, Decimal.new(0), &Decimal.add(&1, &2))
    Decimal.div(sum, Decimal.new(length(list)))
  end

  defp max_of([]), do: nil
  defp max_of(list), do: Enum.reduce(list, fn a, acc -> if Decimal.compare(a, acc) == :gt, do: a, else: acc end)

  defp min_of([]), do: nil
  defp min_of(list), do: Enum.reduce(list, fn a, acc -> if Decimal.compare(a, acc) == :lt, do: a, else: acc end)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/teacher_assistant/academics/marks_test.exs`
Expected: PASS (all describe blocks). If the ranking helper misbehaves on ties, fix `assign_ranks/1` until the ex-aequo test passes — the invariant is: sorted descending, equal averages share the lower position number.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/marks.ex test/teacher_assistant/academics/marks_test.exs
git commit -m "feat: Academics.Marks pure statistics (weighted avg, ranks, pass rate, gender split)"
```

---

### Task 6: Roster management LiveView

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/roster_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add route)
- Test: `test/teacher_assistant_web/live/teacher/roster_live_test.exs`

**Interfaces:**
- Consumes: `Academics.fetch_owned_teaching_context/2`, `Academics.create_class_group/3`, `Academics.link_class_group/2`, `Academics.list_students/1`, `Academics.add_student/2`, `Academics.delete_student/1`, `Academics.current_academic_year/1`.
- Produces: route `live "/teacher/contexts/:id/roster", Teacher.RosterLive, :index`. DOM IDs: `#teacher-roster`, `#roster-create-class-form`, `#student-form`, `#student-submit`, `#student-row-<id>`, `#student-delete-<id>`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant_web/live/teacher/roster_live_test.exs
defmodule TeacherAssistantWeb.Teacher.RosterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{ws: ws, year: year, ctx: ctx}
  end

  test "creates a class group then adds a student", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

    view
    |> form("#roster-create-class-form", class_group: %{label: "3e M2", level: "3ème"})
    |> render_submit()

    view
    |> form("#student-form", student: %{full_name: "Awa Bello", sex: "f"})
    |> render_submit()

    assert render(view) =~ "Awa Bello"
  end

  test "unknown context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/roster_live_test.exs`
Expected: FAIL — no route / module.

- [ ] **Step 3: Add the route**

In `lib/teacher_assistant_web/router.ex`, inside the `ash_authentication_live_session :teacher_workspace` block (next to the other `/teacher/...` routes):

```elixir
      live "/teacher/contexts/:id/roster", Teacher.RosterLive, :index
```

- [ ] **Step 4: Create the LiveView**

```elixir
# lib/teacher_assistant_web/live/teacher/roster_live.ex
defmodule TeacherAssistantWeb.Teacher.RosterLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => ctx_id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(ctx_id, ws) do
      {:ok, load(socket, ws, ctx)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp load(socket, ws, ctx) do
    class_group =
      case ctx.class_group_id do
        nil -> nil
        id -> case Academics.fetch_owned_class_group(id, ws), do: ({:ok, cg} -> cg; _ -> nil)
      end

    students = if class_group, do: Academics.list_students(class_group), else: []

    socket
    |> assign(:ws, ws)
    |> assign(:ctx, ctx)
    |> assign(:class_group, class_group)
    |> assign(:students, students)
    |> assign(:class_form, to_form(%{}, as: :class_group))
    |> assign(:student_form, to_form(%{}, as: :student))
  end

  def handle_event("create_class", %{"class_group" => p}, socket) do
    ws = socket.assigns.ws
    year = Academics.current_academic_year(ws)

    with false <- is_nil(year),
         {:ok, cg} <-
           Academics.create_class_group(ws, year, %{label: p["label"], level: p["level"]}),
         {:ok, ctx} <- Academics.link_class_group(socket.assigns.ctx, cg) do
      {:noreply, load(socket, ws, ctx)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the class"))}
    end
  end

  def handle_event("add_student", %{"student" => p}, socket) do
    cg = socket.assigns.class_group

    with false <- is_nil(cg),
         {:ok, _s} <-
           Academics.add_student(cg, %{
             full_name: p["full_name"],
             sex: String.to_existing_atom(p["sex"]),
             matricule: blank_to(p["matricule"], nil)
           }) do
      {:noreply,
       socket
       |> assign(:students, Academics.list_students(cg))
       |> assign(:student_form, to_form(%{}, as: :student))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not add the student"))}
    end
  end

  def handle_event("delete_student", %{"id" => id}, socket) do
    with {:ok, s} <- Academics.fetch_owned_student(id, socket.assigns.ws),
         :ok <- Academics.delete_student(s) do
      {:noreply, assign(socket, :students, Academics.list_students(socket.assigns.class_group))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not remove the student"))}
    end
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-roster" class="mx-auto max-w-md space-y-5">
        <header>
          <p class="ta-eyebrow">{gettext("Roster")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">
            {@ctx.subject} · {@ctx.level}
          </h1>
        </header>

        <%= if @class_group do %>
          <.form for={@student_form} id="student-form" phx-submit="add_student" class="ta-leaf space-y-2">
            <.input field={@student_form[:full_name]} label={gettext("Full name")} />
            <.input
              type="select"
              field={@student_form[:sex]}
              label={gettext("Sex")}
              options={[{gettext("Girl"), "f"}, {gettext("Boy"), "m"}]}
            />
            <.input field={@student_form[:matricule]} label={gettext("Matricule (optional)")} />
            <.button id="student-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Add student")}
            </.button>
          </.form>

          <ul class="space-y-1">
            <li :for={s <- @students} id={"student-row-#{s.id}"} class="ta-leaf flex items-center justify-between">
              <span>{s.full_name}</span>
              <button
                id={"student-delete-#{s.id}"}
                phx-click="delete_student"
                phx-value-id={s.id}
                class="btn btn-ghost btn-xs"
              >
                {gettext("Remove")}
              </button>
            </li>
          </ul>
        <% else %>
          <.form for={@class_form} id="roster-create-class-form" phx-submit="create_class" class="ta-leaf space-y-2">
            <p class="text-sm opacity-80">{gettext("Create the class this subject is taught to.")}</p>
            <.input field={@class_form[:label]} label={gettext("Class label")} />
            <.input field={@class_form[:level]} label={gettext("Level")} value={@ctx.level} />
            <.button type="submit" class="btn btn-primary w-full">{gettext("Create class")}</.button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/teacher_assistant_web/live/teacher/roster_live_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/roster_live.ex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/live/teacher/roster_live_test.exs
git commit -m "feat: RosterLive — create class group, add/remove students"
```

---

### Task 7: Mark entry LiveView

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add route)
- Test: `test/teacher_assistant_web/live/teacher/marks_live_test.exs`

**Interfaces:**
- Consumes: `Academics.fetch_owned_teaching_context/2`, `Academics.current_academic_year/1`, `Academics.list_sequences/1`, `Academics.fetch_owned_class_group/2`, `Academics.list_students/1`, `Academics.list_assessments/2`, `Academics.create_assessment/3`, `Academics.list_marks/1`, `Academics.upsert_marks/2`.
- Produces: route `live "/teacher/contexts/:id/marks", Teacher.MarksLive, :index`. DOM IDs: `#teacher-marks`, `#seq-select`, `#assessment-select`, `#new-assessment-form`, `#marks-form`, `#marks-submit`, `#mark-input-<student_id>`. Params: `?seq=<sequence_id>&assessment=<assessment_id>`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant_web/live/teacher/marks_live_test.exs
defmodule TeacherAssistantWeb.Teacher.MarksLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    %{ws: ws, ctx: ctx, seq: seq, a: a, s1: s1}
  end

  test "enters a mark for a student", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    view
    |> form("#marks-form", %{"scores" => %{s1.id => "15"}})
    |> render_submit()

    assert [m] = Academics.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("15"))
  end

  test "context without class group redirects to roster", %{conn: conn, ws: ws} do
    {:ok, year} = {:ok, Academics.current_academic_year(ws)}

    {:ok, ctx2} =
      Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/teacher/contexts/#{ctx2.id}/marks")

    assert to =~ "/roster"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: FAIL — no route / module.

- [ ] **Step 3: Add the route**

In `lib/teacher_assistant_web/router.ex`, inside the `:teacher_workspace` session block:

```elixir
      live "/teacher/contexts/:id/marks", Teacher.MarksLive, :index
```

- [ ] **Step 4: Create the LiveView**

```elixir
# lib/teacher_assistant_web/live/teacher/marks_live.ex
defmodule TeacherAssistantWeb.Teacher.MarksLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(ctx_id, ws),
         false <- is_nil(ctx.class_group_id),
         {:ok, cg} <- Academics.fetch_owned_class_group(ctx.class_group_id, ws) do
      year = Academics.current_academic_year(ws)
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = pick(sequences, params["seq"])
      assessments = if seq, do: Academics.list_assessments(ctx, seq), else: []
      assessment = pick(assessments, params["assessment"])
      students = Academics.list_students(cg)

      {:ok,
       socket
       |> assign(:ws, ws)
       |> assign(:ctx, ctx)
       |> assign(:sequences, sequences)
       |> assign(:seq, seq)
       |> assign(:assessments, assessments)
       |> assign(:assessment, assessment)
       |> assign(:students, students)
       |> assign(:scores, existing_scores(assessment))
       |> assign(:new_assessment_form, to_form(%{}, as: :assessment))}
    else
      _ ->
        case socket.assigns.current_scope.current_workspace &&
               Academics.fetch_owned_teaching_context(ctx_id, socket.assigns.current_scope.current_workspace) do
          {:ok, _ctx} -> {:ok, push_navigate(socket, to: ~p"/teacher/contexts/#{ctx_id}/roster")}
          _ -> {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
        end
    end
  end

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp existing_scores(nil), do: %{}

  defp existing_scores(assessment) do
    assessment
    |> Academics.list_marks()
    |> Map.new(fn m -> {m.student_id, (m.score && Decimal.to_string(m.score)) || ""} end)
  end

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq_id}")}
  end

  def handle_event("select_assessment", %{"assessment" => aid}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{socket.assigns.seq.id}&assessment=#{aid}"
     )}
  end

  def handle_event("new_assessment", %{"assessment" => p}, socket) do
    with %{} = seq when not is_nil(seq) <- socket.assigns.seq,
         {:ok, a} <- Academics.create_assessment(socket.assigns.ctx, seq, %{label: p["label"]}) do
      {:noreply,
       push_patch(socket,
         to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}"
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not create the assessment"))}
    end
  end

  def handle_event("save", %{"scores" => scores}, socket) do
    entries =
      Enum.map(socket.assigns.students, fn s ->
        %{student_id: s.id, score: parse_score(Map.get(scores, s.id))}
      end)

    case Academics.upsert_marks(socket.assigns.assessment, entries) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Marks saved"))
         |> assign(:scores, existing_scores(socket.assigns.assessment))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not save marks"))}
    end
  end

  def handle_params(params, _uri, socket) do
    seq = pick(socket.assigns.sequences, params["seq"])
    assessments = if seq, do: Academics.list_assessments(socket.assigns.ctx, seq), else: []
    assessment = pick(assessments, params["assessment"])

    {:noreply,
     socket
     |> assign(:seq, seq)
     |> assign(:assessments, assessments)
     |> assign(:assessment, assessment)
     |> assign(:scores, existing_scores(assessment))}
  end

  defp parse_score(nil), do: nil
  defp parse_score(""), do: nil

  defp parse_score(v) do
    case Decimal.parse(v) do
      {d, _} -> d
      :error -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks" class="mx-auto max-w-md space-y-4">
        <header>
          <p class="ta-eyebrow">{gettext("Marks")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@ctx.subject} · {@ctx.level}</h1>
        </header>

        <form id="seq-select" phx-change="select_seq">
          <.input
            type="select"
            name="seq"
            value={@seq && @seq.id}
            label={gettext("Séquence")}
            options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
          />
        </form>

        <%= if @seq do %>
          <form id="assessment-select" phx-change="select_assessment">
            <.input
              type="select"
              name="assessment"
              value={@assessment && @assessment.id}
              label={gettext("Assessment")}
              options={for a <- @assessments, do: {a.label, a.id}}
            />
          </form>

          <.form for={@new_assessment_form} id="new-assessment-form" phx-submit="new_assessment" class="flex gap-2">
            <.input field={@new_assessment_form[:label]} placeholder={gettext("New assessment")} />
            <.button type="submit" class="btn btn-outline btn-sm">{gettext("Add")}</.button>
          </.form>
        <% end %>

        <%= if @assessment do %>
          <.form for={to_form(%{}, as: :scores)} id="marks-form" phx-submit="save" class="space-y-2">
            <div :for={s <- @students} id={"mark-row-#{s.id}"} class="ta-leaf flex items-center justify-between gap-2">
              <span class="flex-1">{s.full_name}</span>
              <input
                id={"mark-input-#{s.id}"}
                type="number"
                step="0.25"
                min="0"
                max="20"
                name={"scores[#{s.id}]"}
                value={Map.get(@scores, s.id, "")}
                class="input input-bordered w-24"
              />
            </div>
            <.button id="marks-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Save marks")}
            </.button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/marks_live.ex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/live/teacher/marks_live_test.exs
git commit -m "feat: MarksLive — per-assessment mark entry with transactional save"
```

---

### Task 8: Séquence summary LiveView + dashboard entry points

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add route)
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex` (add links to roster + marks per context)
- Test: `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`

**Interfaces:**
- Consumes: `Academics.fetch_owned_teaching_context/2`, `Academics.fetch_owned_class_group/2`, `Academics.list_students/1`, `Academics.list_assessments/2`, `Academics.list_marks_for_context_sequence/2`, `Academics.list_sequences/1`, `Academics.current_academic_year/1`, `Marks.summarize/3`.
- Produces: route `live "/teacher/contexts/:id/marks/summary", Teacher.MarksSummaryLive, :index`. DOM IDs: `#teacher-marks-summary`, `#summary-class-average`, `#summary-pass-rate`, `#summary-row-<student_id>`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs
defmodule TeacherAssistantWeb.Teacher.MarksSummaryLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Academics.create_assessment(ctx, seq, %{label: "Devoir 1"})
    :ok = Academics.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("14")}, %{student_id: s2.id, score: Decimal.new("8")}])
    %{ctx: ctx, seq: seq}
  end

  test "shows class average and pass rate", %{conn: conn, ctx: ctx, seq: seq} do
    {:ok, _view, html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert html =~ "11"     # class average (14 + 8) / 2
    assert html =~ "50"     # pass rate %
    assert html =~ "Awa"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`
Expected: FAIL — no route / module.

- [ ] **Step 3: Add the route**

In `lib/teacher_assistant_web/router.ex`, inside the `:teacher_workspace` session block:

```elixir
      live "/teacher/contexts/:id/marks/summary", Teacher.MarksSummaryLive, :index
```

- [ ] **Step 4: Create the LiveView**

```elixir
# lib/teacher_assistant_web/live/teacher/marks_summary_live.ex
defmodule TeacherAssistantWeb.Teacher.MarksSummaryLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Marks

  def mount(%{"id" => ctx_id} = params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with true <- not is_nil(ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(ctx_id, ws),
         false <- is_nil(ctx.class_group_id),
         {:ok, cg} <- Academics.fetch_owned_class_group(ctx.class_group_id, ws) do
      year = Academics.current_academic_year(ws)
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = pick(sequences, params["seq"]) || List.first(sequences)

      students = Academics.list_students(cg)

      summary =
        if seq do
          assessments = Academics.list_assessments(ctx, seq)
          marks = Academics.list_marks_for_context_sequence(ctx, seq)

          Marks.summarize(
            Enum.map(students, fn s -> %{id: s.id, sex: s.sex} end),
            Enum.map(assessments, fn a -> %{id: a.id, weight: a.weight, max_score: a.max_score} end),
            Enum.map(marks, fn m -> %{assessment_id: m.assessment_id, student_id: m.student_id, score: m.score} end)
          )
        else
          nil
        end

      {:ok,
       socket
       |> assign(:ctx, ctx)
       |> assign(:sequences, sequences)
       |> assign(:seq, seq)
       |> assign(:students, students)
       |> assign(:summary, summary)}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/teacher/setup")}
    end
  end

  defp pick(_list, nil), do: nil
  defp pick(list, id), do: Enum.find(list, fn x -> x.id == id end)

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp pct(rate), do: "#{round(rate * 100)}%"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks-summary" class="mx-auto max-w-md space-y-4">
        <header>
          <p class="ta-eyebrow">{gettext("Séquence results")}</p>
          <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@ctx.subject} · {@ctx.level}</h1>
        </header>

        <%= if @summary do %>
          <div class="grid grid-cols-2 gap-2">
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Class average")}</p>
              <p id="summary-class-average" class="text-2xl font-bold">{fmt(@summary.class_average)}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Pass rate")}</p>
              <p id="summary-pass-rate" class="text-2xl font-bold">{pct(@summary.pass_rate)}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Highest / lowest")}</p>
              <p class="text-lg">{fmt(@summary.highest)} / {fmt(@summary.lowest)}</p>
            </div>
            <div class="ta-leaf">
              <p class="ta-eyebrow">{gettext("Girls / boys pass")}</p>
              <p class="text-lg">{pct(@summary.by_sex.f.pass_rate)} / {pct(@summary.by_sex.m.pass_rate)}</p>
            </div>
          </div>

          <ul class="space-y-1">
            <li :for={s <- @students} id={"summary-row-#{s.id}"} class="ta-leaf flex items-center justify-between">
              <span>{s.full_name}</span>
              <span class="font-mono">
                {fmt(@summary.per_student[s.id].average)}
                <span :if={@summary.per_student[s.id].rank} class="opacity-60">
                  ({@summary.per_student[s.id].rank})
                </span>
              </span>
            </li>
          </ul>
        <% else %>
          <p class="ta-leaf">{gettext("No séquences yet — set up the school year first.")}</p>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Add dashboard entry points**

In `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`, find the per-context KPI card (the block rendering `kpi.plan`, around line 50-65) and add roster + marks links alongside the existing plan link. Insert inside the card's link group:

```elixir
              <.link navigate={~p"/teacher/contexts/#{kpi.context_id}/marks"} class="btn btn-outline btn-xs gap-1">
                <.icon name="hero-pencil-square" class="size-3" />
                {gettext("Marks")}
              </.link>
              <.link navigate={~p"/teacher/contexts/#{kpi.context_id}/marks/summary"} class="btn btn-ghost btn-xs">
                {gettext("Results")}
              </.link>
```

> If the dashboard's KPI struct does not already carry `context_id`, use `kpi.plan.teaching_context_id` instead (the plan struct carries it). Verify the exact assign name in `dashboard_live.ex` before editing and match it; the test in Step 6 confirms the links render.

- [ ] **Step 6: Extend the dashboard test**

Add to `test/teacher_assistant_web/live/teacher/dashboard_live_test.exs` a test asserting the Marks link renders once a context + plan exist. Match the existing setup in that file; the assertion:

```elixir
  test "dashboard links to marks for a context", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "/marks"
  end
```

If the existing dashboard test file has no context/plan in its setup, add the minimal setup (year + context + plan) mirroring `log_live_test.exs` so a KPI card renders.

- [ ] **Step 7: Run the tests**

Run:
```bash
mix test test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs test/teacher_assistant_web/live/teacher/dashboard_live_test.exs
```
Expected: PASS.

- [ ] **Step 8: Full suite + commit**

Run: `mix test`
Expected: whole suite green.

```bash
git add lib/teacher_assistant_web/ test/teacher_assistant_web/
git commit -m "feat: MarksSummaryLive (séquence stats) + dashboard entry points"
```

---

## Self-Review

**Spec coverage:**
- ClassGroup / roster-shared-per-class → Tasks 1, 3 (link), 6. ✅
- Student (name, sex required, matricule, repeater) → Task 2. ✅
- Free-form Assessment (label, weight, max_score, given_on) → Task 3. ✅
- Mark (nullable score, unique per assessment+student) → Task 4. ✅
- Deterministic statistics (weighted moyenne séquentielle, class avg, pass rate at 10, highest/lowest, rank with ties, garçons/filles split, running annual mean, mention bands) → Task 5. ✅
- Roster management UI → Task 6. ✅
- Mark entry primary flow (séquence → assessment → student list → transactional save, blank = absent) → Task 7. ✅
- Séquence summary payoff + dashboard tile → Task 8. ✅
- Setup-gate redirects on missing prerequisites → Tasks 6, 7, 8. ✅
- Ash Enums not `:atom` (Sex, Subsystem) → Task 1. ✅
- Francophone-only, pass 10/20 hard-coded → Task 5 constants. ✅
- Non-goals (multi-subject bulletin, printed relevé, conduct, Anglophone, AI) → not present. ✅

**Placeholder scan:** No TBD/TODO. Two conditional notes (Task 3 `has_many :marks` ordering; Task 8 dashboard assign name) give explicit fallback instructions rather than leaving a gap.

**Type consistency:** `fetch_owned_*` helpers return `{:ok, struct} | {:error, :not_found}` consistently. `upsert_marks/2` returns `:ok | {:error, term}` and is used that way in Task 7. `Marks.summarize/3` output shape in Task 5 matches the reads in Task 8 (`per_student[id].average/.rank`, `class_average`, `pass_rate`, `highest`, `lowest`, `by_sex.f/.m.pass_rate`). Assessment `weight`/`max_score` are `Decimal` in both resource (Task 3) and calc (Task 5).

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-01-teacher-marks-register-v1_2.md`.
