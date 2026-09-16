# P2.2 — School Enrollment & Shared Classes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a school workspace usable for teaching: durable Student + Enrollment model, school-owned classes/year, teaching assignments (subject × class × teacher), teachers' existing `/teacher/*` tools working under school scope, and school admin UI (classes, class detail, bulk enrollment import).

**Architecture:** `Student` becomes a workspace-scoped person record; a new `Enrollment` resource carries the per-year class link (status inscription/réinscription, repeater). `TeachingContext` gains an optional `teacher_user_id` — set = school teaching assignment, one teacher per subject per class via a partial unique index. Scope resolution for school workspaces resolves the active year and the member's *assigned* contexts; `/teacher/*` opens under school scope for assigned teachers. New context modules `Academics.Enrollments` and `Academics.Assignments` keep `academics.ex` from growing. Admin mutations gated by `Permissions.admin?/1` (Head or Vice-Principal), double-checked server-side.

**Tech Stack:** Elixir/Phoenix LiveView, Ash 3 + AshPostgres, daisyUI "Tableau" theme, gettext FR/EN.

**Spec:** `docs/superpowers/specs/2026-07-03-p2-2-school-enrollment-shared-classes-design.md`

## Global Constraints

- **Never bare `:atom` attributes** — always an `Ash.Type.Enum` module (project rule).
- Resource house style: `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`.
- Context functions call Ash with `authorize?: false` and return tagged tuples; never leak raw Ash errors to the UI.
- Module-level gettext = `use Gettext, backend: TeacherAssistantWeb.Gettext` (NOT `import`). LiveViews/controllers get gettext via `use TeacherAssistantWeb, :live_view / :controller`.
- All user-facing strings wrapped in `gettext/dgettext`; extraction + FR fill happens in Task 12 (do NOT run `mix gettext.extract` in earlier tasks).
- Every task ends with `mix precommit` green (compile --warnings-as-errors, format, full test suite). If `mix format` reflows files from earlier tasks, commit those reflows too.
- Every admin mutation is double-gated: hidden in UI AND re-checked server-side in the event handler; every record lookup scoped to the current workspace (P2.1 pattern).
- Branch: `feat/p2-2-school-enrollment` off `main`.
- Migrations: run `mix ash.codegen <name>` to update resource snapshots, then hand-rewrite the generated migration to be data-preserving as specified. `mix ecto.migrate` + verify.
- Test conventions: `TeacherAssistant.DataCase` (context tests), `TeacherAssistantWeb.ConnCase` (LiveView tests, `setup :register_and_log_in_user` provides `%{conn:, workspace:, actor:}`), `TeacherAssistant.TeacherFixtures.user_fixture/0`.

---

### Task 1: Enrollment data model — Student refactor + Enrollment resource + data-preserving migration

The riskiest task: `Student` loses `class_group_id`/`repeater` and gains `workspace_id`; new `Enrollment` resource carries the class link. Public `Academics` function signatures stay stable so the rest of the app keeps compiling; only their internals change. The whole existing suite must stay green.

**Files:**
- Create: `lib/teacher_assistant/academics/enrollment_status.ex`
- Create: `lib/teacher_assistant/academics/enrollment.ex`
- Modify: `lib/teacher_assistant/academics/student.ex`
- Modify: `lib/teacher_assistant/academics.ex` (student section, `fetch_owned_entry_with_context` effectif)
- Create: `priv/repo/migrations/<timestamp>_p2_2_enrollments.exs` (via codegen, hand-rewritten)
- Test: `test/teacher_assistant/academics/enrollments_model_test.exs`
- Modify (only if they reference `student.repeater`/`student.class_group_id` directly): `lib/teacher_assistant_web/live/teacher/roster_live.ex`, `lib/teacher_assistant_web/live/teacher/import_live.ex` — see Step 5.

**Interfaces:**
- Consumes: existing `Academics.add_student/2`, `list_students/1`, `update_student/2`, `delete_student/1`, `fetch_owned_student/2`.
- Produces (stable signatures, new semantics):
  - `Academics.add_student(%ClassGroup{}, attrs)` → `{:ok, %Student{}}` — creates Student **and** Enrollment; `attrs` may include `:repeater` (routed to the enrollment) and `:full_name, :sex, :matricule`.
  - `Academics.list_students(%ClassGroup{})` → `[%Student{}]` sorted by `full_name` — students enrolled in that class (via enrollments).
  - `Academics.list_roster(%ClassGroup{})` → `[%{student: %Student{}, enrollment: %Enrollment{}}]` sorted by student name — NEW, for pages that need repeater/status.
  - `Academics.update_enrollment(%Enrollment{}, attrs)` → `{:ok, %Enrollment{}}` — NEW (repeater/status/class changes).
  - `Academics.fetch_owned_student(id, %Workspace{})` → `{:ok, %Student{}} | {:error, :not_found}` — now filters `workspace_id` directly.
  - `TeacherAssistant.Academics.Enrollment` struct: `id, status (:inscription | :reinscription), repeater, student_id, class_group_id, academic_year_id, workspace_id`.

- [ ] **Step 1: Write the failing model tests**

`test/teacher_assistant/academics/enrollments_model_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.EnrollmentsModelTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    %{ws: ws, year: year, cg: cg}
  end

  test "add_student creates a student and an enrollment", %{ws: ws, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f, repeater: true})
    assert s.workspace_id == ws.id
    assert [%{student: student, enrollment: enr}] = Academics.list_roster(cg)
    assert student.id == s.id
    assert enr.class_group_id == cg.id
    assert enr.repeater == true
    assert enr.status == :inscription
  end

  test "list_students returns enrolled students sorted by name", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Zoe", sex: :f})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Ali", sex: :m})
    assert ["Ali", "Zoe"] = Academics.list_students(cg) |> Enum.map(& &1.full_name)
  end

  test "matricule is unique per workspace", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f, matricule: "MAT-1"})
    assert {:error, _} = Academics.add_student(cg, %{full_name: "Bi", sex: :m, matricule: "MAT-1"})
    # nil matricules never collide
    {:ok, _} = Academics.add_student(cg, %{full_name: "Cam", sex: :m})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Dan", sex: :m})
  end

  test "a student has one enrollment per year", %{ws: ws, year: year, cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    assert {:error, _} =
             TeacherAssistant.Academics.Enrollment
             |> Ash.Changeset.for_create(:create, %{
               student_id: s.id,
               class_group_id: cg2.id,
               academic_year_id: year.id,
               workspace_id: ws.id
             })
             |> Ash.create(authorize?: false)
  end

  test "update_enrollment toggles repeater", %{cg: cg} do
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enr}] = Academics.list_roster(cg)
    {:ok, enr} = Academics.update_enrollment(enr, %{repeater: true})
    assert enr.repeater
  end

  test "delete_student cascades its enrollments", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    :ok = Academics.delete_student(s)
    assert Academics.list_roster(cg) == []
  end

  test "fetch_owned_student scopes by workspace", %{cg: cg} do
    {:ok, s} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    other = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())
    assert {:ok, _} = Academics.fetch_owned_student(s.id, %{other | id: s.workspace_id})
    assert {:error, :not_found} = Academics.fetch_owned_student(s.id, other)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/teacher_assistant/academics/enrollments_model_test.exs`
Expected: FAIL (Enrollment module undefined / list_roster undefined).

- [ ] **Step 3: Write the enum and resources**

`lib/teacher_assistant/academics/enrollment_status.ex`:

```elixir
defmodule TeacherAssistant.Academics.EnrollmentStatus do
  use Ash.Type.Enum, values: [:inscription, :reinscription]
end
```

`lib/teacher_assistant/academics/enrollment.ex`:

```elixir
defmodule TeacherAssistant.Academics.Enrollment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "enrollments"
    repo TeacherAssistant.Repo

    references do
      reference :student, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :status,
        :repeater,
        :student_id,
        :class_group_id,
        :academic_year_id,
        :workspace_id
      ],
      update: [:status, :repeater, :class_group_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, TeacherAssistant.Academics.EnrollmentStatus,
      allow_nil?: false,
      default: :inscription,
      public?: true

    attribute :repeater, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
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
    identity :unique_enrollment_per_year, [:student_id, :academic_year_id]
  end
end
```

`lib/teacher_assistant/academics/student.ex` — remove `class_group_id`, `repeater`, and the `belongs_to :class_group`; add:

```elixir
  actions do
    defaults [
      :read,
      :destroy,
      create: [:full_name, :sex, :matricule, :workspace_id],
      update: [:full_name, :sex, :matricule]
    ]
  end

  postgres do
    table "students"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :matricule],
        unique: true,
        where: "matricule IS NOT NULL",
        name: "students_unique_matricule_index",
        message: "matricule already used in this workspace"
    end
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :enrollments, TeacherAssistant.Academics.Enrollment
  end
```

Register `Enrollment` in the `TeacherAssistant.Academics` domain's `resources` block.

- [ ] **Step 4: Adapt the Academics context (signatures stable)**

In `lib/teacher_assistant/academics.ex` replace the student section:

```elixir
  def add_student(%ClassGroup{} = cg, attrs) do
    {repeater, attrs} = Map.pop(attrs, :repeater, false)
    {status, attrs} = Map.pop(attrs, :status, :inscription)
    attrs = Map.put(attrs, :workspace_id, cg.workspace_id)

    with {:ok, student} <-
           Student |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false),
         {:ok, _enr} <-
           Enrollment
           |> Ash.Changeset.for_create(:create, %{
             student_id: student.id,
             class_group_id: cg.id,
             academic_year_id: cg.academic_year_id,
             workspace_id: cg.workspace_id,
             repeater: repeater,
             status: status
           })
           |> Ash.create(authorize?: false) do
      {:ok, student}
    end
  end

  def list_students(%ClassGroup{id: cg_id}) do
    Enrollment
    |> Ash.Query.filter(class_group_id == ^cg_id)
    |> Ash.Query.load(:student)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.student)
    |> Enum.sort_by(&String.downcase(&1.full_name))
  end

  def list_roster(%ClassGroup{id: cg_id}) do
    Enrollment
    |> Ash.Query.filter(class_group_id == ^cg_id)
    |> Ash.Query.load(:student)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&%{student: &1.student, enrollment: &1})
    |> Enum.sort_by(&String.downcase(&1.student.full_name))
  end

  def update_enrollment(%Enrollment{} = e, attrs),
    do: e |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def update_student(%Student{} = s, attrs),
    do: s |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_student(%Student{} = s), do: Ash.destroy(s, authorize?: false)

  def fetch_owned_student(id, %Workspace{id: ws_id}) do
    Student
    |> Ash.Query.filter(id == ^id and workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, s} -> {:ok, s}
      _ -> {:error, :not_found}
    end
  end
```

Add `alias TeacherAssistant.Academics.Enrollment` to the module's alias list. `fetch_owned_entry_with_context/2`'s `effectif` already calls `list_students/1` — unchanged.

- [ ] **Step 5: Fix call sites that used `student.repeater` or `student.class_group_id`**

`grep -rn "\.repeater\|class_group_id" lib/teacher_assistant_web/` and fix each:
- `RosterLive`: switch its student list to `Academics.list_roster(cg)`; rows read `row.student.*` + `row.enrollment.repeater`; the repeater toggle calls `Academics.update_enrollment(enrollment, %{repeater: ...})` (fetch the enrollment from the socket's roster by id, never trust a raw id without re-finding it in the loaded roster). Delete keeps calling `delete_student` (cascades the enrollment). Add flows keep calling `add_student/2` (unchanged signature).
- `ImportLive` (personal): keeps calling `add_student(cg, %{full_name: ..., sex: ..., matricule: ..., repeater: ...})` — no change needed unless it reads the fields back.
- Any test fixtures constructing students directly must go through `add_student/2`.

- [ ] **Step 6: Generate + hand-rewrite the migration**

Run: `mix ash.codegen p2_2_enrollments`

Replace the generated migration's body so it is data-preserving (keep the module name/timestamp codegen chose):

```elixir
  def up do
    alter table(:students) do
      add :workspace_id,
          references(:workspaces, column: :id, name: "students_workspace_id_fkey", type: :uuid),
          null: true
    end

    execute """
    UPDATE students SET workspace_id = cg.workspace_id
    FROM class_groups cg WHERE cg.id = students.class_group_id
    """

    alter table(:students) do
      modify :workspace_id, :uuid, null: false
    end

    create table(:enrollments, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :status, :text, null: false, default: "inscription"
      add :repeater, :boolean, null: false, default: false

      add :student_id,
          references(:students,
            column: :id,
            name: "enrollments_student_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false

      add :class_group_id,
          references(:class_groups,
            column: :id,
            name: "enrollments_class_group_id_fkey",
            type: :uuid
          ),
          null: false

      add :academic_year_id,
          references(:academic_years,
            column: :id,
            name: "enrollments_academic_year_id_fkey",
            type: :uuid
          ),
          null: false

      add :workspace_id,
          references(:workspaces,
            column: :id,
            name: "enrollments_workspace_id_fkey",
            type: :uuid
          ),
          null: false

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    execute """
    INSERT INTO enrollments
      (id, status, repeater, student_id, class_group_id, academic_year_id, workspace_id,
       inserted_at, updated_at)
    SELECT gen_random_uuid(), 'inscription', s.repeater, s.id, s.class_group_id,
           cg.academic_year_id, cg.workspace_id, now(), now()
    FROM students s JOIN class_groups cg ON cg.id = s.class_group_id
    """

    create unique_index(:enrollments, [:student_id, :academic_year_id],
             name: "enrollments_unique_enrollment_per_year_index"
           )

    create unique_index(:students, [:workspace_id, :matricule],
             where: "matricule IS NOT NULL",
             name: "students_unique_matricule_index"
           )

    alter table(:students) do
      remove :class_group_id
      remove :repeater
    end
  end

  def down do
    raise "irreversible: enrollment refactor"
  end
```

Compare index/constraint names against the codegen output + snapshots and keep whatever names the snapshots recorded (snapshots are the source of truth for future codegens). Run `mix ecto.migrate`, then verify on the dev DB that a pre-existing student kept its class: `psql`-check or `iex -S mix` → `Academics.list_roster/1` on a seeded class group.

- [ ] **Step 7: Run the new tests + full suite**

Run: `mix test test/teacher_assistant/academics/enrollments_model_test.exs` → PASS.
Run: `mix precommit` → all green (existing roster/import/marks tests unchanged in behavior).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(academics): durable Student + Enrollment model with data-preserving migration"
```

---

### Task 2: TeachingContext — teacher assignment column, partial unique indexes, subsystem enum

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex`
- Create: `priv/repo/migrations/<timestamp>_p2_2_teaching_assignments.exs` (codegen, hand-checked)
- Test: `test/teacher_assistant/academics/teaching_context_test.exs`

**Interfaces:**
- Produces: `TeachingContext.teacher_user_id :: Ecto.UUID | nil` (nil = personal context, set = school assignment); `belongs_to :teacher, TeacherAssistant.Accounts.User`; uniqueness — personal: `(workspace, year, subject, level, serie)` where `teacher_user_id IS NULL`; school: `(workspace, year, class_group_id, subject)` where `teacher_user_id IS NOT NULL`. `:subsystem` is now `TeacherAssistant.Academics.Subsystem` (same values, no data change). `create`/`update` accept `:teacher_user_id`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    %{user: user, ws: ws, year: year, cg: cg}
  end

  test "two personal contexts with same subject/level collide", %{ws: ws, year: year} do
    attrs = %{subject: "Maths", level: "6ème", subsystem: :francophone}
    {:ok, _} = Academics.create_teaching_context(ws, year, attrs)
    assert {:error, _} = Academics.create_teaching_context(ws, year, attrs)
  end

  test "two teachers can hold the same subject/level on different classes", ctx do
    %{ws: ws, year: year, cg: cg, user: u1} = ctx
    u2 = TeacherFixtures.user_fixture()
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})

    base = %{subject: "Maths", level: "6ème", subsystem: :francophone}

    {:ok, _} =
      Academics.create_teaching_context(
        ws,
        year,
        base |> Map.put(:teacher_user_id, u1.id) |> Map.put(:class_group_id, cg.id)
      )

    {:ok, _} =
      Academics.create_teaching_context(
        ws,
        year,
        base |> Map.put(:teacher_user_id, u2.id) |> Map.put(:class_group_id, cg2.id)
      )
  end

  test "one teacher per subject per class", ctx do
    %{ws: ws, year: year, cg: cg, user: u1} = ctx
    u2 = TeacherFixtures.user_fixture()

    base = %{
      subject: "Maths",
      level: "6ème",
      subsystem: :francophone,
      class_group_id: cg.id
    }

    {:ok, _} =
      Academics.create_teaching_context(ws, year, Map.put(base, :teacher_user_id, u1.id))

    assert {:error, _} =
             Academics.create_teaching_context(ws, year, Map.put(base, :teacher_user_id, u2.id))
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/teaching_context_test.exs`
Expected: FAIL — `teacher_user_id` not accepted / school-assignment cases collide with the old full unique identity.

- [ ] **Step 3: Modify the resource**

In `teaching_context.ex`:

```elixir
  # attribute change — replace the bare-atom subsystem with the enum:
  attribute :subsystem, TeacherAssistant.Academics.Subsystem,
    allow_nil?: false,
    default: :francophone,
    public?: true

  # add to relationships:
  belongs_to :teacher, TeacherAssistant.Accounts.User do
    source_attribute :teacher_user_id
    allow_nil? true
    public? true
  end
```

Add `:teacher_user_id` and `:class_group_id` to the `create` accept list, and `:teacher_user_id` to `update`. Delete the `identities do ... end` block and add partial unique indexes:

```elixir
  postgres do
    table "teaching_contexts"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :academic_year_id, :subject, :level, :serie],
        unique: true,
        where: "teacher_user_id IS NULL",
        name: "teaching_contexts_unique_personal_context",
        message: "a context for this subject and level already exists"

      index [:workspace_id, :academic_year_id, :class_group_id, :subject],
        unique: true,
        where: "teacher_user_id IS NOT NULL",
        name: "teaching_contexts_unique_school_assignment",
        message: "this class already has a teacher for this subject"
    end
  end
```

- [ ] **Step 4: Codegen + verify migration**

Run: `mix ash.codegen p2_2_teaching_assignments`

Hand-check the migration does exactly: add `teacher_user_id` referencing `users`, drop the old `teaching_contexts_unique_context_index` unique index, create the two partial unique indexes. No column drops, no data movement — existing rows have `teacher_user_id IS NULL` and land under the personal index, preserving today's guarantees. Run `mix ecto.migrate`.

- [ ] **Step 5: Tests + suite + commit**

Run: `mix test test/teacher_assistant/academics/teaching_context_test.exs` → PASS, then `mix precommit` → green.

```bash
git add -A && git commit -m "feat(academics): teaching assignments on TeachingContext + subsystem enum"
```

---

### Task 3: Enrollments context API — enroll, search, transfer, import matching

**Files:**
- Create: `lib/teacher_assistant/academics/enrollments.ex`
- Test: `test/teacher_assistant/academics/enrollments_test.exs`

**Interfaces:**
- Consumes: Task 1's `Enrollment`/`Student`, `Academics.add_student/2`, `list_roster/1`.
- Produces `TeacherAssistant.Academics.Enrollments` with:
  - `enroll_new(%ClassGroup{}, attrs)` → `{:ok, %{student:, enrollment:}} | {:error, :duplicate_matricule} | {:error, %Ash.Error{}}` — attrs: `:full_name, :sex, :matricule, :repeater`.
  - `enroll_existing(%ClassGroup{}, %Student{}, attrs \\ %{})` → `{:ok, %Enrollment{}} | {:error, :already_enrolled}` — creates a `:reinscription` enrollment for this year; `:already_enrolled` if the student has any enrollment this academic year.
  - `search_students(%Workspace{}, query :: String.t())` → `[%Student{}]` (≤ 10; exact matricule match first, then case-insensitive name contains).
  - `transfer(%Enrollment{}, %ClassGroup{})` → `{:ok, %Enrollment{}} | {:error, :different_year}`.
  - `withdraw(%Enrollment{})` → `:ok`.
  - `import_rows(%ClassGroup{}, rows :: [map()])` → `%{created: n, reenrolled: n, conflicts: [map()]}` — row: `%{full_name:, sex:, matricule: nil | String.t(), repeater: boolean}`. Matricule matches an existing workspace student → `enroll_existing` (réinscription); already enrolled this year → collected in `conflicts` (row + `:reason`); no matricule or unknown matricule → `enroll_new`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.EnrollmentsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "6e B", level: "6ème"})
    %{ws: ws, year: year, cg: cg, cg2: cg2}
  end

  test "enroll_new creates student + inscription enrollment", %{cg: cg} do
    {:ok, %{student: s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert e.status == :inscription and e.student_id == s.id
  end

  test "enroll_new rejects duplicate matricule", %{cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    assert {:error, :duplicate_matricule} =
             Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-1"})
  end

  test "enroll_existing re-enrolls as réinscription; double-enroll rejected", ctx do
    %{cg: cg, cg2: cg2} = ctx
    {:ok, %{student: s, enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    :ok = Enrollments.withdraw(e)
    {:ok, e2} = Enrollments.enroll_existing(cg2, s)
    assert e2.status == :reinscription and e2.class_group_id == cg2.id
    assert {:error, :already_enrolled} = Enrollments.enroll_existing(cg, s)
  end

  test "search_students finds by matricule and by name fragment", %{ws: ws, cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Ngo Bassa Marie", sex: :f, matricule: "M-9"})
    assert [%{matricule: "M-9"}] = Enrollments.search_students(ws, "M-9")
    assert [%{full_name: "Ngo Bassa Marie"}] = Enrollments.search_students(ws, "bassa")
    assert [] = Enrollments.search_students(ws, "zzz")
  end

  test "transfer moves the enrollment to another class in the same year", ctx do
    %{cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, e} = Enrollments.transfer(e, cg2)
    assert e.class_group_id == cg2.id
  end

  test "transfer to a different year is rejected", %{ws: ws, cg: cg} do
    {:ok, other_year} =
      Academics.create_academic_year(ws, %{
        name: "2026-2027",
        start_date: ~D[2026-09-07],
        end_date: ~D[2027-07-31],
        active: false
      })

    {:ok, cg_other} = Academics.create_class_group(ws, other_year, %{label: "5e A", level: "5ème"})
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    assert {:error, :different_year} = Enrollments.transfer(e, cg_other)
  end

  test "import_rows: creates, re-enrolls by matricule, flags same-year conflicts", ctx do
    %{cg: cg, cg2: cg2} = ctx
    # existing student with matricule, not enrolled this year in cg2's class
    {:ok, %{student: _s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)
    # still-enrolled student → conflict
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    rows = [
      %{full_name: "Awa", sex: :f, matricule: "M-1", repeater: false},
      %{full_name: "Bi", sex: :m, matricule: "M-2", repeater: false},
      %{full_name: "Cam", sex: :m, matricule: nil, repeater: true}
    ]

    result = Enrollments.import_rows(cg2, rows)
    assert result.created == 1
    assert result.reenrolled == 1
    assert [%{matricule: "M-2", reason: :already_enrolled}] = result.conflicts
  end
end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/teacher_assistant/academics/enrollments_test.exs` → FAIL (module undefined).

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/enrollments.ex`:

```elixir
defmodule TeacherAssistant.Academics.Enrollments do
  @moduledoc """
  School-facing enrollment operations (P2.2). Personal-roster paths keep using
  Academics.add_student/list_roster; this module adds search, re-enrollment,
  transfer and bulk import with matricule matching.
  """
  import Ash.Expr, only: []
  require Ash.Query
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{ClassGroup, Enrollment, Student, Workspace}

  def enroll_new(%ClassGroup{} = cg, attrs) do
    case Academics.add_student(cg, Map.put_new(attrs, :status, :inscription)) do
      {:ok, student} ->
        [%{enrollment: e}] =
          Academics.list_roster(cg) |> Enum.filter(&(&1.student.id == student.id))

        {:ok, %{student: student, enrollment: e}}

      {:error, error} ->
        if duplicate_matricule?(error), do: {:error, :duplicate_matricule}, else: {:error, error}
    end
  end

  def enroll_existing(%ClassGroup{} = cg, %Student{} = student, attrs \\ %{}) do
    Enrollment
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        student_id: student.id,
        class_group_id: cg.id,
        academic_year_id: cg.academic_year_id,
        workspace_id: cg.workspace_id,
        status: :reinscription
      })
    )
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, e} -> {:ok, e}
      {:error, _} -> {:error, :already_enrolled}
    end
  end

  def search_students(%Workspace{id: ws_id}, query) do
    q = String.trim(query)

    if q == "" do
      []
    else
      by_matricule =
        Student
        |> Ash.Query.filter(workspace_id == ^ws_id and matricule == ^q)
        |> Ash.read!(authorize?: false)

      by_name =
        Student
        |> Ash.Query.filter(workspace_id == ^ws_id and contains(string_downcase(full_name), ^String.downcase(q)))
        |> Ash.Query.sort(full_name: :asc)
        |> Ash.Query.limit(10)
        |> Ash.read!(authorize?: false)

      Enum.uniq_by(by_matricule ++ by_name, & &1.id) |> Enum.take(10)
    end
  end

  def transfer(%Enrollment{} = e, %ClassGroup{} = cg) do
    if cg.academic_year_id == e.academic_year_id do
      Academics.update_enrollment(e, %{class_group_id: cg.id})
    else
      {:error, :different_year}
    end
  end

  def withdraw(%Enrollment{} = e) do
    Ash.destroy!(e, authorize?: false)
    :ok
  end

  def import_rows(%ClassGroup{} = cg, rows) do
    ws = %Workspace{id: cg.workspace_id}

    Enum.reduce(rows, %{created: 0, reenrolled: 0, conflicts: []}, fn row, acc ->
      case classify_row(ws, cg, row) do
        :create ->
          case enroll_new(cg, Map.take(row, [:full_name, :sex, :matricule, :repeater])) do
            {:ok, _} -> %{acc | created: acc.created + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:reenroll, student} ->
          case enroll_existing(cg, student, %{repeater: row[:repeater] || false}) do
            {:ok, _} -> %{acc | reenrolled: acc.reenrolled + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:conflict, reason} ->
          conflict(acc, row, reason)
      end
    end)
  end

  defp classify_row(_ws, _cg, %{matricule: nil}), do: :create
  defp classify_row(_ws, _cg, %{matricule: ""}), do: :create

  defp classify_row(ws, cg, %{matricule: mat}) do
    case Student
         |> Ash.Query.filter(workspace_id == ^ws.id and matricule == ^mat)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        :create

      {:ok, student} ->
        if enrolled_this_year?(student, cg),
          do: {:conflict, :already_enrolled},
          else: {:reenroll, student}

      _ ->
        {:conflict, :lookup_failed}
    end
  end

  defp enrolled_this_year?(student, cg) do
    Enrollment
    |> Ash.Query.filter(student_id == ^student.id and academic_year_id == ^cg.academic_year_id)
    |> Ash.read!(authorize?: false) != []
  end

  defp conflict(acc, row, reason),
    do: %{acc | conflicts: acc.conflicts ++ [Map.put(row, :reason, reason)]}

  defp duplicate_matricule?(error) do
    error |> Exception.message() |> String.contains?("matricule")
  rescue
    _ -> false
  end
end
```

Note for the implementer: if `contains(string_downcase(...))` isn't available in your Ash version's expression syntax, use `Ash.Query.filter(workspace_id == ^ws_id and ilike(full_name, ^"%#{q}%"))` or fall back to reading workspace students and filtering in Elixir with a `limit` — correctness first, the workspace-scoping filter is the non-negotiable part.

- [ ] **Step 4: Run tests + suite + commit**

`mix test test/teacher_assistant/academics/enrollments_test.exs` → PASS; `mix precommit` → green.

```bash
git add -A && git commit -m "feat(academics): Enrollments API — enroll/search/transfer/import matching"
```

---

### Task 4: Assignments context API — assign, reassign, remove, list

**Files:**
- Create: `lib/teacher_assistant/academics/assignments.ex`
- Test: `test/teacher_assistant/academics/assignments_test.exs`

**Interfaces:**
- Consumes: Task 2's `TeachingContext.teacher_user_id`; `Schools.fetch_school_membership/2` (returns `{:ok, %SchoolMembership{}} | {:error, :not_a_member}`; only active memberships).
- Produces `TeacherAssistant.Academics.Assignments` with:
  - `assign(%ClassGroup{}, %User{}, attrs)` → `{:ok, %TeachingContext{}} | {:error, :not_assignable} | {:error, :already_assigned}` — attrs: `:subject` (required), `:weekly_hours` (default 4). Level/série/subsystem copied from the class group.
  - `reassign(%TeachingContext{}, %User{})` → `{:ok, %TeachingContext{}} | {:error, :not_assignable}`.
  - `remove(%TeachingContext{})` → `:ok | {:error, :has_data}` — blocked when progression plans or assessments reference the context.
  - `list_for_class(%ClassGroup{})` → `[%TeachingContext{}]` with `:teacher` loaded, sorted by subject.
  - `list_for_user(%Workspace{}, %AcademicYear{}, %User{})` → `[%TeachingContext{}]` (this user's assignments in this year).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.AssignmentsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    %{head: head, school: school, year: year, cg: cg}
  end

  test "assign creates a school context derived from the class", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", weekly_hours: 5})
    assert tc.teacher_user_id == head.id
    assert tc.class_group_id == cg.id
    assert tc.level == "6ème"
    assert tc.weekly_hours == 5
  end

  test "assign rejects a non-member", %{cg: cg} do
    outsider = TeacherFixtures.user_fixture()
    assert {:error, :not_assignable} = Assignments.assign(cg, outsider, %{subject: "Maths"})
  end

  test "one teacher per subject per class; reassign swaps", ctx do
    %{head: head, school: school, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _m} = add_active_member(school, head, other)

    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    assert {:error, :already_assigned} = Assignments.assign(cg, other, %{subject: "Maths"})
    {:ok, tc} = Assignments.reassign(tc, other)
    assert tc.teacher_user_id == other.id
  end

  test "remove is blocked when the context has data", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    {:ok, _plan} = Academics.create_progression_plan(tc, %{title: "Plan"})
    assert {:error, :has_data} = Assignments.remove(tc)
  end

  test "remove deletes a data-free assignment", ctx do
    %{head: head, cg: cg} = ctx
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    assert :ok = Assignments.remove(tc)
    assert Assignments.list_for_class(cg) == []
  end

  test "list_for_user returns only this user's assignments", ctx do
    %{head: head, school: school, year: year, cg: cg} = ctx
    other = TeacherFixtures.user_fixture()
    {:ok, _} = add_active_member(school, head, other)
    {:ok, _} = Assignments.assign(cg, head, %{subject: "Maths"})
    {:ok, _} = Assignments.assign(cg, other, %{subject: "Anglais"})

    assert [%{subject: "Maths"}] = Assignments.list_for_user(school, year, head)
  end

  # Creates an active membership for `user` in `school` via the invitation flow.
  defp add_active_member(school, head, user) do
    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    Schools.accept_invitation(inv.token, user)
  end
end
```

Adjust `add_active_member` to whatever `Schools.invite_member/3` + `accept_invitation/2` actually return (see `test/teacher_assistant/accounts/school_invitations_test.exs` for the working pattern) — reuse the existing test helper style rather than inventing a new path.

- [ ] **Step 2: Run to verify failure** — module undefined.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/assignments.ex`:

```elixir
defmodule TeacherAssistant.Academics.Assignments do
  @moduledoc """
  Teaching assignments (P2.2): a school-owned TeachingContext with a teacher.
  One teacher per subject per class (partial unique index); assignment requires
  an active school membership.
  """
  require Ash.Query
  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    ProgressionPlan,
    TeachingContext,
    Workspace
  }

  alias TeacherAssistant.Accounts.{Schools, User}

  def assign(%ClassGroup{} = cg, %User{} = teacher, attrs) do
    with :ok <- assignable(cg, teacher) do
      TeachingContext
      |> Ash.Changeset.for_create(:create, %{
        subject: Map.fetch!(attrs, :subject),
        weekly_hours: Map.get(attrs, :weekly_hours, 4),
        level: cg.level,
        serie: cg.serie,
        subsystem: cg.subsystem,
        class_group_id: cg.id,
        teacher_user_id: teacher.id,
        workspace_id: cg.workspace_id,
        academic_year_id: cg.academic_year_id
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, tc} -> {:ok, tc}
        {:error, _} -> {:error, :already_assigned}
      end
    end
  end

  def reassign(%TeachingContext{} = tc, %User{} = teacher) do
    with :ok <- assignable_ws(tc.workspace_id, teacher) do
      tc
      |> Ash.Changeset.for_update(:update, %{teacher_user_id: teacher.id})
      |> Ash.update(authorize?: false)
    end
  end

  def remove(%TeachingContext{id: id} = tc) do
    has_plans =
      ProgressionPlan
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(authorize?: false) != []

    has_assessments =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(authorize?: false) != []

    if has_plans or has_assessments do
      {:error, :has_data}
    else
      Ash.destroy!(tc, authorize?: false)
      :ok
    end
  end

  def list_for_class(%ClassGroup{id: cg_id}) do
    TeachingContext
    |> Ash.Query.filter(class_group_id == ^cg_id and not is_nil(teacher_user_id))
    |> Ash.Query.load(:teacher)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def list_for_user(%Workspace{id: ws_id}, %AcademicYear{id: year_id}, %User{id: user_id}) do
    TeachingContext
    |> Ash.Query.filter(
      workspace_id == ^ws_id and academic_year_id == ^year_id and teacher_user_id == ^user_id
    )
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp assignable(%ClassGroup{workspace_id: ws_id}, teacher), do: assignable_ws(ws_id, teacher)

  defp assignable_ws(ws_id, teacher) do
    case Schools.fetch_school_membership(%Workspace{id: ws_id}, teacher) do
      {:ok, _membership} -> :ok
      {:error, :not_a_member} -> {:error, :not_assignable}
    end
  end
end
```

Check `Schools.fetch_school_membership/2` pattern-matches `%Workspace{id: ws_id}` (it does — see `schools.ex:47`) and that it already filters to active memberships (P2.1 behavior); if it returns inactive ones, add a status check here and return `{:error, :not_assignable}`.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/academics/assignments_test.exs && mix precommit
git add -A && git commit -m "feat(academics): Assignments API — assign/reassign/remove/list"
```

---

### Task 5: Scope resolution for school teaching + `require_teaching_scope` guard

**Files:**
- Modify: `lib/teacher_assistant/accounts/workspaces.ex`
- Modify: `lib/teacher_assistant_web/live_user_auth.ex`
- Modify: `lib/teacher_assistant_web/router.ex`
- Test: `test/teacher_assistant/accounts/workspaces_test.exs` (extend), `test/teacher_assistant_web/live/school_teaching_scope_test.exs`

**Interfaces:**
- Consumes: `Assignments.list_for_user/3` (Task 4), `Academics.current_academic_year/1`.
- Produces: school branch of `Workspaces.scope_for(user, ws_id, context_id)` now fills `current_academic_year` (school's active year) and `current_context` (the user's assigned context matching `context_id`, else their first assignment, else nil). `LiveUserAuth.on_mount(:require_teaching_scope, ...)`: personal scope → cont; school scope with `current_context` → cont; school scope without → redirect `/school`. Router's `:teacher_workspace` session uses `:require_teaching_scope` instead of `:require_personal_scope` (the old clause is deleted).

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant/accounts/workspaces_test.exs`:

```elixir
  describe "school teaching scope (P2.2)" do
    setup %{user: user} do
      {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(user, %{name: "Lycée S"})

      {:ok, year} =
        Academics.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
      %{school: school, year: year, cg: cg}
    end

    test "school scope resolves year and assigned context", ctx do
      %{user: user, school: school, year: year, cg: cg} = ctx

      {:ok, tc} =
        TeacherAssistant.Academics.Assignments.assign(cg, user, %{subject: "Maths"})

      {:ok, scope} = Workspaces.scope_for(user, school.id)
      assert scope.current_academic_year.id == year.id
      assert scope.current_context.id == tc.id
    end

    test "school scope without assignments has nil context but a year", ctx do
      %{user: user, school: school, year: year} = ctx
      {:ok, scope} = Workspaces.scope_for(user, school.id)
      assert scope.current_academic_year.id == year.id
      assert scope.current_context == nil
    end

    test "context_id from another teacher falls back to own first assignment", ctx do
      %{user: user, school: school, cg: cg} = ctx
      other = TeacherFixtures.user_fixture()

      {:ok, inv} =
        TeacherAssistant.Accounts.Schools.invite_member(school, user, %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} = TeacherAssistant.Accounts.Schools.accept_invitation(inv.token, other)

      {:ok, mine} = TeacherAssistant.Academics.Assignments.assign(cg, user, %{subject: "Maths"})

      {:ok, theirs} =
        TeacherAssistant.Academics.Assignments.assign(cg, other, %{subject: "Anglais"})

      {:ok, scope} = Workspaces.scope_for(user, school.id, theirs.id)
      assert scope.current_context.id == mine.id
    end
  end
```

(Adapt the invite/accept helper to the pattern already used in `school_invitations_test.exs`.)

New `test/teacher_assistant_web/live/school_teaching_scope_test.exs`:

```elixir
defmodule TeacherAssistantWeb.SchoolTeachingScopeTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée G"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, user: user}
  end

  test "a member without assignments is bounced from /teacher to /school", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher")
  end

  test "an assigned teacher reaches /teacher under school scope", ctx do
    %{conn: conn, cg: cg, user: user} = ctx
    {:ok, _tc} = Assignments.assign(cg, user, %{subject: "Maths"})
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Maths"
  end

  test "personal scope still reaches /teacher", %{conn: conn, workspace: personal} do
    conn = Plug.Conn.put_session(conn, :workspace_id, personal.id)
    assert {:ok, _view, _html} = live(conn, ~p"/teacher")
  end
end
```

- [ ] **Step 2: Run to verify failure** — school scope currently returns `current_academic_year: nil`; `/teacher` redirects assigned teachers away.

- [ ] **Step 3: Implement**

In `workspaces.ex`, thread `context_id` into the school branch and resolve:

```elixir
  def scope_for(user, workspace_id, context_id) do
    case Academics.get_personal_workspace(workspace_id) do
      {:ok, %{kind: :personal} = ws} -> personal_scope(user, ws, context_id)
      {:ok, %{kind: :school} = ws} -> school_scope(user, ws, context_id)
      _ -> {:error, :workspace_not_found}
    end
  end

  defp school_scope(user, ws, context_id) do
    case Schools.fetch_school_membership(ws, user) do
      {:ok, membership} ->
        year = Academics.current_academic_year(ws)

        {:ok,
         %Scope{
           current_user: user,
           current_workspace: ws,
           current_workspace_type: :school,
           current_role: List.first(membership.roles),
           current_roles: membership.roles,
           current_membership: membership,
           current_academic_year: year,
           current_context: resolve_assigned_context(ws, year, user, context_id)
         }}

      {:error, :not_a_member} ->
        {:error, :not_a_member}
    end
  end

  defp resolve_assigned_context(_ws, nil, _user, _context_id), do: nil

  defp resolve_assigned_context(ws, year, user, context_id) do
    contexts = TeacherAssistant.Academics.Assignments.list_for_user(ws, year, user)
    Enum.find(contexts, &(&1.id == context_id)) || List.first(contexts)
  end
```

In `live_user_auth.ex`, replace the `:require_personal_scope` clause:

```elixir
  def on_mount(:require_teaching_scope, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope && scope.current_workspace_type == :school && is_nil(scope.current_context) do
      {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school")}
    else
      {:cont, socket}
    end
  end
```

In `router.ex`, change the `:teacher_workspace` on_mount list to `{TeacherAssistantWeb.LiveUserAuth, :require_teaching_scope}`. Grep for any other `require_personal_scope` references (tests from P2.1!) and update them: the P2.1 test asserting "school scope is bounced from /teacher" remains true only for members *without assignments* — adjust that test's name/setup accordingly rather than deleting it.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/accounts/workspaces_test.exs test/teacher_assistant_web/live/school_teaching_scope_test.exs && mix precommit
git add -A && git commit -m "feat(scope): school teaching scope — year + assigned contexts + require_teaching_scope"
```

---

### Task 6: Teacher UX under school scope — switcher, read-only roster, setup redirect, cartouche

**Files:**
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (context switcher source)
- Modify: `lib/teacher_assistant_web/live/teacher/roster_live.ex`
- Modify: `lib/teacher_assistant_web/live/teacher/setup_live.ex`
- Modify: `lib/teacher_assistant_web/controllers/fiche_print_controller.ex` + its HTML (cartouche établissement)
- Modify: `lib/teacher_assistant/academics.ex` (scope-aware context listing)
- Test: `test/teacher_assistant_web/live/teacher/school_scope_ux_test.exs`

**Interfaces:**
- Consumes: Task 5's school scope; `Assignments.list_for_user/3`.
- Produces: `Academics.list_contexts_for_scope(%Scope{})` → `[%TeachingContext{}]` — personal: `list_teaching_contexts(ws, year)`; school: `Assignments.list_for_user(ws, year, user)`; `[]` when no year. All layout/switcher call sites use it.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/teacher/school_scope_ux_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Teacher.SchoolScopeUxTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Enrollments}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée UX"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, user, %{subject: "Maths"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, tc: tc, user: user}
  end

  test "roster is read-only under school scope", %{conn: conn, tc: tc} do
    {:ok, view, html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    assert html =~ "Awa"
    refute has_element?(view, "#roster-add-form")
    refute has_element?(view, "[id^='roster-delete-']")
  end

  test "forged roster mutation events are rejected under school scope", %{conn: conn, tc: tc} do
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    # event name must match RosterLive's actual add handler
    render_hook(view, "add_student", %{"student" => %{"full_name" => "X", "sex" => "m"}})
    assert Academics.list_students(%TeacherAssistant.Academics.ClassGroup{id: tc.class_group_id}) |> length() == 1
  end

  test "setup redirects to /school under school scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher/setup")
  end

  test "fiche print shows the school name as établissement", ctx do
    %{conn: conn, tc: tc} = ctx
    {:ok, plan} = Academics.create_progression_plan(tc, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    conn = get(conn, ~p"/teacher/entries/#{entry.id}/fiche/print")
    assert html_response(conn, 200) =~ "Lycée UX"
  end
end
```

Before writing the forged-event test, read `roster_live.ex` and use its real event names and DOM ids; same for the add-form selector. If the roster's add form has a different id, target that.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

1. `Academics.list_contexts_for_scope/1`:

```elixir
  def list_contexts_for_scope(%TeacherAssistant.Scope{
        current_workspace: ws,
        current_academic_year: year,
        current_workspace_type: type,
        current_user: user
      }) do
    cond do
      is_nil(ws) or is_nil(year) -> []
      type == :school -> TeacherAssistant.Academics.Assignments.list_for_user(ws, year, user)
      true -> list_teaching_contexts(ws, year)
    end
  end
```

Replace the switcher's context source in `layouts.ex` (find where it calls `list_teaching_contexts` or receives the contexts assign) with `list_contexts_for_scope(scope)`. School-scope switcher labels: "`{subject} — {class label}`" — the class label needs `class_group` loaded; extend `Assignments.list_for_user/3` with `Ash.Query.load(:class_group)` and render `ctx.class_group.label` when present.

2. `RosterLive`: compute `read_only? = @scope.current_workspace_type == :school` in mount; wrap the add form, edit and delete controls in `:if={!@read_only?}`; guard every mutating `handle_event` clause with:

```elixir
  def handle_event(event, _params, %{assigns: %{read_only?: true}} = socket)
      when event in ~w(add_student delete_student undo_delete update_student toggle_repeater) do
    {:noreply, socket}
  end
```

placed ABOVE the real clauses (match the actual event names found in the file).

3. `SetupLive` mount: if `socket.assigns.current_scope.current_workspace_type == :school`, `{:ok, push_navigate(socket, to: ~p"/school")}` before any data loading.

4. Fiche print cartouche: in `fiche_print_controller.ex` (and `LessonPlanLive` if it renders établissement), pass `etablissement` = `scope.current_workspace.name` when `current_workspace_type == :school`, else the existing value (blank/em-dash today). Render it in the existing cartouche slot.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/teacher/school_scope_ux_test.exs && mix precommit
git add -A && git commit -m "feat(teacher): school-scope UX — assigned-context switcher, read-only roster, setup redirect, cartouche"
```

---

### Task 7: `Permissions.admin?/1` + `/school/classes` list + nav

**Files:**
- Modify: `lib/teacher_assistant/accounts/permissions.ex`
- Create: `lib/teacher_assistant_web/live/school/classes_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add route), `lib/teacher_assistant_web/components/layouts.ex` (nav item)
- Modify: `lib/teacher_assistant/academics.ex` (`delete_class_group/1`, `update_class_group/2` if missing)
- Test: `test/teacher_assistant/accounts/permissions_test.exs` (extend), `test/teacher_assistant_web/live/school/classes_live_test.exs`

**Interfaces:**
- Produces: `Permissions.admin?(%Scope{})` → true iff school scope and `:head` or `:vice_principal` in roles. `Academics.delete_class_group(%ClassGroup{})` → `:ok | {:error, :has_data}` (blocked when enrollments or assignments exist). `Academics.update_class_group(%ClassGroup{}, attrs)` → `{:ok, %ClassGroup{}}`. Route: `live "/school/classes", School.ClassesLive, :index` in the `:school_workspace` session. Nav: "Classes" item in `#school-nav` between Dashboard and Members.

- [ ] **Step 1: Write the failing tests**

Extend `permissions_test.exs`:

```elixir
  test "admin?/1 is true for head and vice_principal, false otherwise" do
    alias TeacherAssistant.Accounts.Permissions
    alias TeacherAssistant.Scope
    assert Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:head]})
    assert Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:vice_principal]})
    refute Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:teacher]})
    refute Permissions.admin?(%Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]})
    refute Permissions.admin?(nil)
  end
```

`test/teacher_assistant_web/live/school/classes_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.ClassesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée C"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, user: user}
  end

  test "lists classes with effectif", %{conn: conn, school: school, year: year} do
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    assert html =~ "6e A"
    assert html =~ "1"
  end

  test "head can create a class", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")

    view
    |> form("#class-form", %{"class_group" => %{"label" => "2nde C", "level" => "2nde", "serie" => "C"}})
    |> render_submit()

    assert render(view) =~ "2nde C"
  end

  test "delete is blocked when the class has enrollments", ctx do
    %{conn: conn, school: school, year: year} = ctx
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#class-delete-#{cg.id}") |> render_click()
    assert render(view) =~ "6e A"
  end

  test "a plain teacher member sees no admin controls and forged events are rejected", ctx do
    %{conn: conn, school: school, year: year, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#class-form")

    render_hook(view, "create_class", %{"class_group" => %{"label" => "X", "level" => "6ème"}})
    assert Academics.list_class_groups(school, year) == []
  end

  test "no active year shows the setup gate", %{conn: conn, actor: user} do
    {:ok, school2} = Schools.create_school(user, %{name: "Lycée SansAnnée"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school2.id)
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    assert html =~ "année" or html =~ "year"
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`permissions.ex` — add:

```elixir
  def admin?(%Scope{current_workspace_type: :school, current_roles: roles}) do
    r = roles || []
    :head in r or :vice_principal in r
  end

  def admin?(_), do: false
```

`academics.ex` — add:

```elixir
  def update_class_group(%ClassGroup{} = cg, attrs),
    do: cg |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_class_group(%ClassGroup{id: id} = cg) do
    has_enrollments =
      Enrollment |> Ash.Query.filter(class_group_id == ^id) |> Ash.read!(authorize?: false) != []

    has_assignments =
      TeachingContext
      |> Ash.Query.filter(class_group_id == ^id and not is_nil(teacher_user_id))
      |> Ash.read!(authorize?: false) != []

    if has_enrollments or has_assignments do
      {:error, :has_data}
    else
      Ash.destroy!(cg, authorize?: false)
      :ok
    end
  end
```

`School.ClassesLive` — follow `School.MembersLive`'s structure exactly (mount guards, `Permissions` re-checks in handlers, flash patterns, daisyUI table + `<.page_header>` / `<.empty_state>` / `<.setup_gate>` components). Sketch:

```elixir
defmodule TeacherAssistantWeb.School.ClassesLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Permissions

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type != :school do
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    else
      {:ok, socket |> assign(admin?: Permissions.admin?(scope)) |> load_classes()}
    end
  end

  defp load_classes(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    classes =
      if year do
        Academics.list_class_groups(scope.current_workspace, year)
        |> Enum.map(fn cg ->
          %{cg: cg, effectif: length(Academics.list_roster(cg))}
        end)
      else
        []
      end

    assign(socket, classes: classes, year: year)
  end

  def handle_event("create_class", %{"class_group" => params}, socket) do
    %{current_scope: scope} = socket.assigns

    with true <- Permissions.admin?(scope),
         year when not is_nil(year) <- scope.current_academic_year,
         {:ok, _} <-
           Academics.create_class_group(scope.current_workspace, year, %{
             label: params["label"],
             level: params["level"],
             serie: presence(params["serie"]),
             subsystem: String.to_existing_atom(params["subsystem"] || "francophone")
           }) do
      {:noreply, socket |> put_flash(:info, gettext("Class created.")) |> load_classes()}
    else
      false -> {:noreply, socket}
      nil -> {:noreply, put_flash(socket, :error, gettext("Create an academic year first."))}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not create the class."))}
    end
  end

  def handle_event("delete_class", %{"id" => id}, socket) do
    %{current_scope: scope} = socket.assigns

    with true <- Permissions.admin?(scope),
         %{cg: cg} <- Enum.find(socket.assigns.classes, &(&1.cg.id == id)),
         :ok <- Academics.delete_class_group(cg) do
      {:noreply, socket |> put_flash(:info, gettext("Class deleted.")) |> load_classes()}
    else
      {:error, :has_data} ->
        {:noreply,
         put_flash(socket, :error, gettext("This class has students or teachers — remove them first."))}

      _ ->
        {:noreply, socket}
    end
  end

  defp presence(""), do: nil
  defp presence(v), do: v
end
```

Render: table of classes (label / level / série / subsystem / effectif / actions), each label linking to `~p"/school/classes/#{cg.id}"` (route exists after Task 8 — use the path helper only once that route lands; in this task render plain text and add the link in Task 8). Admin-only `#class-form` (label, level, serie, subsystem select from `TeacherAssistant.Academics.Subsystem.values()`), `#class-delete-{id}` buttons with `data-confirm`. `<.setup_gate>` when `@year == nil` pointing to `/school/settings`. Subsystem parse: guard with a whitelist (`params["subsystem"] in ~w(francophone anglophone)`) before `String.to_existing_atom` — do not let forged strings raise.

Router: add `live "/school/classes", School.ClassesLive, :index` inside `:school_workspace`. Layouts: add Classes nav item to `#school-nav`:

```heex
<.link navigate={~p"/school/classes"} class={nav_class(@current_path == "/school/classes")}>
  {gettext("Classes")}
</.link>
```

(match the exact helper/classes used by the existing school nav items).

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/accounts/permissions_test.exs test/teacher_assistant_web/live/school/classes_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): admin? permission + classes list page + nav"
```

---

### Task 8: Class detail — roster panel (enroll, search, transfer, withdraw)

**Files:**
- Create: `lib/teacher_assistant_web/live/school/class_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/classes/:id", School.ClassLive, :show`), `classes_live.ex` (link labels to the detail page)
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs`

**Interfaces:**
- Consumes: `Enrollments.enroll_new/2`, `enroll_existing/3`, `search_students/2`, `transfer/2`, `withdraw/1`, `Academics.list_roster/1`, `fetch_owned_class_group/2`, `Permissions.admin?/1`.
- Produces: DOM contract used by tests and Task 9 — `#class-roster` table, `#enroll-form`, `#enroll-search` input + `#search-results`, `#transfer-{enrollment_id}` select, `#withdraw-{enrollment_id}` button.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.ClassLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée D"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, cg2: cg2, user: user}
  end

  test "shows the roster with status and repeater", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, repeater: true})
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert html =~ "Awa"
  end

  test "enrolls a new student (inscription)", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{"student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-3"}})
    |> render_submit()

    assert [%{student: %{full_name: "Bi"}}] = Academics.list_roster(cg)
  end

  test "duplicate matricule surfaces a friendly error", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{"student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-1"}})
    |> render_submit()

    assert length(Academics.list_roster(cg)) == 1
    assert render(view) =~ "matricule"
  end

  test "search finds an existing student and re-enrolls (réinscription)", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, %{student: s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa Zang", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-search") |> render_change(%{"q" => "M-1"})
    assert render(view) =~ "Awa Zang"
    view |> element("#search-enroll-#{s.id}") |> render_click()

    assert [%{enrollment: %{status: :reinscription}}] = Academics.list_roster(cg2)
  end

  test "transfer moves a student to another class", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> element("#transfer-#{e.id}")
    |> render_change(%{"class_group_id" => cg2.id})

    assert [] = Academics.list_roster(cg)
    assert [_] = Academics.list_roster(cg2)
  end

  test "withdraw removes the enrollment", %{conn: conn, cg: cg} do
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#withdraw-#{e.id}") |> render_click()
    assert [] = Academics.list_roster(cg)
  end

  test "cross-school class id is not found", %{conn: conn, actor: user} do
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, other_school} = Schools.create_school(other_head, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(other_school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(other_school, oy, %{label: "6e Z", level: "6ème"})
    _ = user
    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}")
  end

  test "non-admin member: no mutation controls, forged events rejected", ctx do
    %{school: school, cg: cg, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#enroll-form")

    render_hook(view, "enroll_new", %{"student" => %{"full_name" => "X", "sex" => "m"}})
    assert [] = Academics.list_roster(cg)
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `School.ClassLive`**

Structure (roster panel this task; an empty "Enseignements" section placeholder heading is fine — Task 9 fills it):

```elixir
defmodule TeacherAssistantWeb.School.ClassLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Permissions

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace) do
      {:ok,
       socket
       |> assign(cg: cg, admin?: Permissions.admin?(scope), search_results: [], q: "")
       |> load_roster()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  defp load_roster(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg

    assign(socket,
      roster: Academics.list_roster(cg),
      other_classes:
        Academics.list_class_groups(scope.current_workspace, scope.current_academic_year)
        |> Enum.reject(&(&1.id == cg.id))
    )
  end

  def handle_event("enroll_new", %{"student" => params}, socket) do
    with true <- socket.assigns.admin? do
      case Enrollments.enroll_new(socket.assigns.cg, %{
             full_name: params["full_name"],
             sex: parse_sex(params["sex"]),
             matricule: presence(params["matricule"]),
             repeater: params["repeater"] == "true"
           }) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, gettext("Student enrolled.")) |> load_roster()}

        {:error, :duplicate_matricule} ->
          {:noreply,
           put_flash(socket, :error, gettext("This matricule already belongs to another student."))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not enroll the student."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("search", %{"q" => q}, socket) do
    results =
      if socket.assigns.admin?,
        do: Enrollments.search_students(socket.assigns.current_scope.current_workspace, q),
        else: []

    {:noreply, assign(socket, search_results: results, q: q)}
  end

  def handle_event("enroll_existing", %{"student-id" => sid}, socket) do
    with true <- socket.assigns.admin?,
         %{} = student <- Enum.find(socket.assigns.search_results, &(&1.id == sid)) do
      case Enrollments.enroll_existing(socket.assigns.cg, student) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("Student re-enrolled."))
           |> assign(search_results: [], q: "")
           |> load_roster()}

        {:error, :already_enrolled} ->
          {:noreply,
           put_flash(socket, :error, gettext("This student is already enrolled this year."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("transfer", %{"enrollment-id" => eid, "class_group_id" => cgid}, socket) do
    with true <- socket.assigns.admin?,
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         %{} = target <- Enum.find(socket.assigns.other_classes, &(&1.id == cgid)),
         {:ok, _} <- Enrollments.transfer(e, target) do
      {:noreply, socket |> put_flash(:info, gettext("Student transferred.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("withdraw", %{"enrollment-id" => eid}, socket) do
    with true <- socket.assigns.admin?,
         %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)) do
      :ok = Enrollments.withdraw(e)
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_sex("m"), do: :m
  defp parse_sex(_), do: :f
  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(v), do: v
end
```

Render (responsive-collapse table pattern from the P1 roster): `#class-roster` table with name / sex / matricule / status badge (Inscription/Réinscription) / repeater badge / actions (`#transfer-{id}` select over `@other_classes` with `phx-change="transfer" phx-value-enrollment-id={id}`, `#withdraw-{id}` button with `data-confirm`). Admin-only `#enroll-form` (full_name, sex select, matricule, repeater checkbox) and `#enroll-search` (`phx-change="search"`, results list with `#search-enroll-{student.id}` buttons, each row showing name + matricule). Note on the transfer select: `phx-value-*` doesn't ride along on `phx-change`; put the enrollment id in the select's `name` (e.g. `name="class_group_id"` inside a form carrying a hidden `enrollment-id` input, or encode both in the event params via `phx-change` on a wrapping form `#transfer-{id}`) — match what the test drives (`render_change(%{"class_group_id" => ...})` on `#transfer-{e.id}` means the *form* has that id).

Router: add `live "/school/classes/:id", School.ClassLive, :show` in `:school_workspace`; link class labels from `ClassesLive`.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/class_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): class detail roster panel — enroll/search/transfer/withdraw"
```

---

### Task 9: Class detail — teaching assignments panel

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex`
- Test: extend `test/teacher_assistant_web/live/school/class_live_test.exs`

**Interfaces:**
- Consumes: `Assignments.assign/3`, `reassign/2`, `remove/1`, `list_for_class/1`; `Schools.list_members/1` (active members with `:user` loaded — check the actual return shape in `schools.ex:58`).
- Produces: DOM contract — `#assignments` table, `#assign-form` (member select + subject + weekly hours), `#reassign-{context_id}` select, `#unassign-{context_id}` button.

- [ ] **Step 1: Write the failing tests (append to class_live_test.exs)**

```elixir
  describe "assignments panel" do
    test "assigns a teacher to a subject", %{conn: conn, cg: cg, user: head} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{"user_id" => head.id, "subject" => "Maths", "weekly_hours" => "5"}
      })
      |> render_submit()

      assert [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)
      assert tc.subject == "Maths" and tc.teacher_user_id == head.id
    end

    test "duplicate subject on the class is rejected with a message", ctx do
      %{conn: conn, cg: cg, user: head} = ctx
      {:ok, _} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{"user_id" => head.id, "subject" => "Maths", "weekly_hours" => "4"}
      })
      |> render_submit()

      assert length(TeacherAssistant.Academics.Assignments.list_for_class(cg)) == 1
      assert render(view) =~ "Maths"
    end

    test "unassign removes a data-free assignment; blocked with data", ctx do
      %{conn: conn, cg: cg, user: head} = ctx
      {:ok, tc} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, _} = TeacherAssistant.Academics.create_progression_plan(tc, %{title: "P"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view |> element("#unassign-#{tc.id}") |> render_click()
      assert [_] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

      {:ok, tc2} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Anglais"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      view |> element("#unassign-#{tc2.id}") |> render_click()
      assert length(TeacherAssistant.Academics.Assignments.list_for_class(cg)) == 1
    end
  end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

In `ClassLive.mount`/`load_roster` also load `assignments: Assignments.list_for_class(cg)` and `members: Schools.list_members(scope.current_workspace)`. Handlers (same admin gating shape as Task 8):

```elixir
  def handle_event("assign", %{"assignment" => params}, socket) do
    with true <- socket.assigns.admin?,
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == params["user_id"])) do
      case TeacherAssistant.Academics.Assignments.assign(socket.assigns.cg, member.user, %{
             subject: params["subject"],
             weekly_hours: parse_hours(params["weekly_hours"])
           }) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, gettext("Teacher assigned.")) |> reload()}

        {:error, :already_assigned} ->
          {:noreply,
           put_flash(socket, :error, gettext("This class already has a teacher for this subject."))}

        {:error, :not_assignable} ->
          {:noreply, put_flash(socket, :error, gettext("This member cannot be assigned."))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unassign", %{"context-id" => cid}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)) do
      case TeacherAssistant.Academics.Assignments.remove(tc) do
        :ok ->
          {:noreply, socket |> put_flash(:info, gettext("Assignment removed.")) |> reload()}

        {:error, :has_data} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("This assignment has marks or progressions — it cannot be removed.")
           )}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reassign", %{"context-id" => cid, "user_id" => uid}, socket) do
    with true <- socket.assigns.admin?,
         %{} = tc <- Enum.find(socket.assigns.assignments, &(&1.id == cid)),
         %{} = member <- Enum.find(socket.assigns.members, &(&1.user_id == uid)),
         {:ok, _} <- TeacherAssistant.Academics.Assignments.reassign(tc, member.user) do
      {:noreply, socket |> put_flash(:info, gettext("Teacher reassigned.")) |> reload()}
    else
      _ -> {:noreply, socket}
    end
  end

  defp parse_hours(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 and n <= 40 -> n
      _ -> 4
    end
  end
```

(`reload/1` = the roster+assignments loader; `member.user` requires `Schools.list_members/1` to load `:user` — if it doesn't, load it here or extend that function's `Ash.Query.load`.) Render: `#assignments` table (subject / teacher name / h·week / actions), admin-only `#assign-form` with a member select (`member.user.email` or display name), subject text input, hours number input.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/class_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): class detail assignments panel — assign/reassign/unassign"
```

---

### Task 10: School bulk enrollment import

**Files:**
- Create: `lib/teacher_assistant_web/live/school/enroll_import_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/classes/:id/import", School.EnrollImportLive, :new`), `class_live.ex` (link to import)
- Test: `test/teacher_assistant_web/live/school/enroll_import_live_test.exs`

**Interfaces:**
- Consumes: `Enrollments.import_rows/2`, `Academics.fetch_owned_class_group/2`, `Permissions.admin?/1`. Read `lib/teacher_assistant_web/live/teacher/import_live.ex` first and reuse its parsing helpers/stepper markup wholesale (extract a shared private parser only if it's a clean lift — do not rewrite the teacher import).
- Produces: paste → preview (per-row badge: create / réinscription / conflict) → confirm flow at `/school/classes/:id/import`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.EnrollImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée I"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, cg2: cg2}
  end

  test "paste → preview → confirm enrolls the students", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1\nBi;m;"}})
    |> render_submit()

    assert render(view) =~ "Awa"
    view |> element("#import-confirm") |> render_click()
    assert length(Academics.list_roster(cg)) == 2
  end

  test "matricule matching an existing student previews as réinscription", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1"}})
    |> render_submit()

    assert render(view) =~ "éinscription"
    view |> element("#import-confirm") |> render_click()
    assert [%{enrollment: %{status: :reinscription}}] = Academics.list_roster(cg2)
  end

  test "already-enrolled matricule is flagged as a conflict and skipped", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Bi;m;M-2"}})
    |> render_submit()

    view |> element("#import-confirm") |> render_click()
    assert [] = Academics.list_roster(cg2)
    assert render(view) =~ "conflit" or render(view) =~ "conflict"
  end

  test "non-admin cannot reach the import page", ctx do
    %{school: school, cg: cg} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    head = school |> then(fn _ -> nil end)
    _ = head

    {:ok, inv} =
      Schools.invite_member(school, ctx[:actor] || raise("actor missing"), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: _}}} = live(conn, ~p"/school/classes/#{cg.id}/import")
  end
end
```

(Clean up that last test's setup plumbing when writing it for real — pull `actor` from the setup context properly.) Match the paste format (`;` vs tab vs comma) to whatever the teacher `ImportLive` parser accepts — read it first and use the same format in tests.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`School.EnrollImportLive`: mount = school-type check + `fetch_owned_class_group` + **`Permissions.admin?` or redirect to the class page** (this page is mutations-only, so gate the whole page). State machine mirroring the teacher import stepper: `:paste` → `:preview` → `:done`.

- `parse` submit: split lines, split fields (reuse teacher `ImportLive`'s separator logic), build rows `%{full_name:, sex:, matricule:, repeater: false}`, then compute each row's predicted action by running the same matching logic as `Enrollments.import_rows/2` *without writing* — simplest correct approach: add `Enrollments.preview_rows(cg, rows)` next to `import_rows/2` returning `[{row, :create | :reenroll | {:conflict, reason}}]`, and implement `import_rows/2` on top of it so preview and commit can't drift. (Refactor `import_rows/2` in this task; its Task 3 tests must stay green.)
- `#import-confirm` click: `Enrollments.import_rows(cg, rows)`, then show the `%{created:, reenrolled:, conflicts:}` summary with conflict rows listed.
- Render preview rows with badges: `badge-success` create, `badge-info` réinscription, `badge-warning` conflict.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant/academics/enrollments_test.exs test/teacher_assistant_web/live/school/enroll_import_live_test.exs && mix precommit
git add -A && git commit -m "feat(school): bulk enrollment import with matricule matching"
```

---

### Task 11: Settings year management + dashboard stats & gates

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: extend `test/teacher_assistant_web/live/school/settings_live_test.exs` and `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `Academics.create_academic_year/2`, `list_academic_years/1`, `current_academic_year/1`; `Academics.list_class_groups/2`, `list_roster/1`; `Assignments.list_for_class/1`; `Permissions.admin?/1`. Year activation: check how the personal Setup flow activates a year (an `:active` flag with "only one active" handling) and reuse the exact same function; if activation is only reachable via create today, add `Academics.activate_academic_year(%AcademicYear{})` → `{:ok, year}` that deactivates siblings first (same workspace) then sets `active: true`.
- Produces: settings year section (`#year-form`, `#year-activate-{id}`); dashboard stats (classes / students / teachers assigned) + setup-gate prompts.

- [ ] **Step 1: Write the failing tests**

Append to `settings_live_test.exs` (reuse its existing setup which builds a school + logs in the Head):

```elixir
  test "head creates and activates an academic year", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    assert render(view) =~ "2025-2026"
  end

  test "activating a year deactivates the previous one", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics

    {:ok, y1} =
      Academics.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, y2} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: false
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")
    view |> element("#year-activate-#{y2.id}") |> render_click()

    assert Academics.current_academic_year(school).id == y2.id
    assert {:ok, %{active: false}} = Academics.get_academic_year(y1.id)
  end

  test "a plain teacher member cannot create years (forged event)", ctx do
    # build a non-admin member session as in members_live_test.exs, then:
    # render_hook(view, "create_year", %{"year" => %{...}})
    # assert Academics.list_academic_years(school) == []
  end
```

(Write the third test fully, following the non-admin session pattern already in `members_live_test.exs`.) Append to `dashboard_live_test.exs`:

```elixir
  test "dashboard shows structure stats", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics
    alias TeacherAssistant.Academics.{Assignments, Enrollments}

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})

    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "6e A" or html =~ "1"
  end

  test "dashboard without a year prompts to create one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "année" or html =~ "year"
  end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`Academics.activate_academic_year/1` (only if no equivalent exists — check first):

```elixir
  def activate_academic_year(%AcademicYear{} = year) do
    AcademicYear
    |> Ash.Query.filter(workspace_id == ^year.workspace_id and active == true and id != ^year.id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn y ->
      y |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update!(authorize?: false)
    end)

    year |> Ash.Changeset.for_update(:update, %{active: true}) |> Ash.update(authorize?: false)
  end
```

(If `AcademicYear`'s update action doesn't accept `:active`, add it.) SettingsLive: new "Année scolaire" section — years table (name, dates, active badge, `#year-activate-{id}` button on inactive rows), `#year-form` (name, start_date, end_date date inputs; created active when it's the first year, inactive otherwise). Gate both behind `Permissions.admin?` in UI + handlers (note: rename stays Head-only as in P2.1; year management uses `admin?`). DashboardLive: replace stub body with `<.stat>` cards (classes count, enrolled students = sum of roster lengths, assigned teachers = distinct `teacher_user_id`s across classes) and `<.setup_gate>` prompts when no year / no classes, linking to `/school/settings` and `/school/classes`.

- [ ] **Step 4: Run tests + suite + commit**

```bash
mix test test/teacher_assistant_web/live/school/ && mix precommit
git add -A && git commit -m "feat(school): settings year management + dashboard stats and gates"
```

---

### Task 12: gettext extract + FR translations + final gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/{en,fr}/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Fill translations**

Every new msgid from P2.2 gets: FR `msgstr` (translate; FR-authored msgids get `msgstr` = msgid) and EN `msgstr` (translate French-authored msgids to English; **no empty msgstr for any new msgid** — this was final-review finding I2 in P2.1, don't repeat it). New strings include (non-exhaustive — grep the diff): "Classes", "Class created.", "Class deleted.", "This class has students or teachers — remove them first.", "Student enrolled.", "Student re-enrolled.", "Student transferred.", "Enrollment removed.", "This matricule already belongs to another student.", "This student is already enrolled this year.", "Teacher assigned.", "Teacher reassigned.", "Assignment removed.", "This class already has a teacher for this subject.", "This member cannot be assigned.", "This assignment has marks or progressions — it cannot be removed.", "Create an academic year first.", inscription/réinscription labels, import stepper strings, dashboard stat labels, settings year section strings.

- [ ] **Step 3: Full gate**

Run: `mix precommit` → green. Check `git status` for format-reflowed files from earlier tasks and include them.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore(i18n): extract + EN/FR translations for P2.2 school enrollment"
```

---

## Final verification (after all tasks)

1. `mix precommit` on the branch tip — green.
2. Manual smoke on dev DB: create school → settings: create+activate year → classes: create 6e A → detail: enroll 2 students (1 with matricule) + assign self to Maths → switch workspace switcher to the school → `/teacher` shows "Maths — 6e A" → enter marks → roster read-only → fiche print shows the school name. Switch back to personal workspace → everything as before.
3. Final whole-branch code review (requesting-code-review skill), then finishing-a-development-branch.
