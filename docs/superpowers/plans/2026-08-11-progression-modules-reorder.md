# Progression Modules First-Class + Drag-and-Drop Reordering — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the progression's `module` from a free-text string into a first-class, orderable `ProgressionModule` entity, and let each teacher reorganize their plan by drag-and-drop (module blocks, lessons within a module, and lessons across modules).

**Architecture:** New `ProgressionModule` Ash resource owned by a `ProgressionPlan`; every `ProgressionEntry` belongs to exactly one module (a per-plan `default?` bucket holds orphan rows). `position` on an entry becomes order *within its module*. A single transactional domain function `apply_layout/2` persists the full reordered tree the client sends on each drop. UI is a grouped `FicheLive` with a SortableJS colocated hook and keyboard-operable drag handles.

**Tech Stack:** Elixir, Ash 3.26 + AshPostgres 2.0, Phoenix LiveView (colocated hooks), SortableJS (vendored), gettext (FR/EN), DaisyUI/Tailwind.

## Global Constraints

- Ash 3 house style: `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; policy `policy always() do authorize_if always() end`; workspace ownership enforced at the **domain-function** layer (`fetch_owned_*`), never in the LiveView.
- All user-facing copy wrapped in `gettext(...)`; add FR + EN in the same commit as the strings (mirror the existing `priv/gettext/{fr,en}/LC_MESSAGES` flow via `mix gettext.extract --merge`).
- Migrations are generated with `mix ash.codegen <snake_name>`; data migrations are hand-written Ecto migrations under `priv/repo/migrations/`.
- Tests: `mix test <path>`; full gate before any PR: `mix precommit` (compile, deps.unlock, format, test).
- Money/decimal hours are `Decimal`; sum with `Decimal.add/2`.
- Every entry always belongs to a module — module blocks are contiguous. There is exactly one `default? = true` bucket per plan; it is undeletable and system-created.

---

### Task 1: `ProgressionModule` resource + nullable FK on entries

**Files:**
- Create: `lib/teacher_assistant/academics/progression_module.ex`
- Modify: `lib/teacher_assistant/academics/progression_entry.ex` (add nullable belongs_to)
- Modify: `lib/teacher_assistant/academics.ex` (register resource + aliases)
- Test: `test/teacher_assistant/academics/progression_module_test.exs`
- Generated: `priv/repo/migrations/*_add_progression_modules.exs`

**Interfaces:**
- Produces: resource `TeacherAssistant.Academics.ProgressionModule` with attrs `id, title:string, position:integer, default?:boolean(default false)` and `belongs_to :progression_plan`, `has_many :entries`. `ProgressionEntry` gains nullable `belongs_to :progression_module` / `:progression_module_id`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/academics/progression_module_test.exs
defmodule TeacherAssistant.Academics.ProgressionModuleTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ProgressionModule
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

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    %{plan: plan}
  end

  test "creates a module belonging to a plan", %{plan: plan} do
    {:ok, m} =
      ProgressionModule
      |> Ash.Changeset.for_create(:create, %{
        title: "M1",
        position: 1,
        progression_plan_id: plan.id
      })
      |> Ash.create(authorize?: false)

    assert m.title == "M1"
    assert m.position == 1
    assert m.default? == false
  end
end
```

- [ ] **Step 2: Run it — expect fail** — `mix test test/teacher_assistant/academics/progression_module_test.exs` → FAIL (module `ProgressionModule` undefined).

- [ ] **Step 3: Create the resource**

```elixir
# lib/teacher_assistant/academics/progression_module.ex
defmodule TeacherAssistant.Academics.ProgressionModule do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_modules"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:title, :position, :progression_plan_id],
      update: [:title, :position]
    ]

    # System-only: creates the undeletable default bucket. `default?` is never
    # publicly accepted, so a teacher can never mint a second bucket.
    create :create_default_bucket do
      accept [:title, :position, :progression_plan_id]
      change set_attribute(:default?, true)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :default?, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    has_many :entries, TeacherAssistant.Academics.ProgressionEntry
  end
end
```

- [ ] **Step 4: Add the nullable FK on `ProgressionEntry`**

In `lib/teacher_assistant/academics/progression_entry.ex`, inside `relationships do`, add:

```elixir
    belongs_to :progression_module, TeacherAssistant.Academics.ProgressionModule do
      source_attribute :progression_module_id
      allow_nil? true
      public? true
    end
```

Do **not** touch the `module` string or the accept lists yet — Task 2 does the cutover.

- [ ] **Step 5: Register in the domain**

In `lib/teacher_assistant/academics.ex`: add `alias TeacherAssistant.Academics.ProgressionModule` near the other aliases, and `resource ProgressionModule` inside the `resources do` block (right after `resource ProgressionEntry`).

- [ ] **Step 6: Generate the migration**

Run: `mix ash.codegen add_progression_modules`
Expected: a migration creating `progression_modules` and adding a nullable `progression_module_id` to `progression_entries`. Skim it to confirm the FK is nullable.

- [ ] **Step 7: Migrate + run test — expect pass** — `mix ecto.migrate && mix test test/teacher_assistant/academics/progression_module_test.exs` → PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/academics/progression_module.ex \
  lib/teacher_assistant/academics/progression_entry.ex \
  lib/teacher_assistant/academics.ex \
  test/teacher_assistant/academics/progression_module_test.exs \
  priv/repo/migrations
git commit -m "feat(academics): ProgressionModule resource + nullable FK on entries"
```

---

### Task 2: Data migration — group string modules, backfill, tighten FK

**Files:**
- Create: `lib/teacher_assistant/academics/module_grouping.ex` (pure, testable core)
- Test: `test/teacher_assistant/academics/module_grouping_test.exs`
- Create: `priv/repo/migrations/*_backfill_progression_modules.exs` (hand-written)
- Modify: `lib/teacher_assistant/academics/progression_entry.ex` (tighten FK, drop `module` string, update accepts)
- Generated: `priv/repo/migrations/*_drop_progression_entry_module.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Academics.ModuleGrouping.group(entries) :: [%{key: String.t() | :default, entry_ids: [binary()]}]` — entries are maps/structs with `:id`, `:module`, `:position`; blank/nil `module` collapses into a single `:default` group; groups returned in first-appearance order.

- [ ] **Step 1: Write the failing test for the pure grouping**

```elixir
# test/teacher_assistant/academics/module_grouping_test.exs
defmodule TeacherAssistant.Academics.ModuleGroupingTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.ModuleGrouping

  defp e(id, module, position), do: %{id: id, module: module, position: position}

  test "groups by first-appearance order, collapsing blanks into one :default group" do
    entries = [
      e("a", "", 1),
      e("b", "M1", 2),
      e("c", "M1", 3),
      e("d", nil, 4),
      e("e", "M2", 5),
      e("f", "M1", 6)
    ]

    assert ModuleGrouping.group(entries) == [
             %{key: :default, entry_ids: ["a", "d"]},
             %{key: "M1", entry_ids: ["b", "c", "f"]},
             %{key: "M2", entry_ids: ["e"]}
           ]
  end
end
```

- [ ] **Step 2: Run it — expect fail** — `mix test test/teacher_assistant/academics/module_grouping_test.exs` → FAIL.

- [ ] **Step 3: Implement the pure core**

```elixir
# lib/teacher_assistant/academics/module_grouping.ex
defmodule TeacherAssistant.Academics.ModuleGrouping do
  @moduledoc "Pure grouping of legacy string modules into ordered module buckets."

  def group(entries) do
    entries
    |> Enum.sort_by(& &1.position)
    |> Enum.reduce({[], %{}}, fn e, {order, acc} ->
      key = normalize(Map.get(e, :module))
      order = if Map.has_key?(acc, key), do: order, else: [key | order]
      acc = Map.update(acc, key, [e.id], &[e.id | &1])
      {order, acc}
    end)
    |> then(fn {order, acc} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn key -> %{key: key, entry_ids: Enum.reverse(acc[key])} end)
    end)
  end

  defp normalize(nil), do: :default
  defp normalize(s) when is_binary(s), do: if(String.trim(s) == "", do: :default, else: s)
end
```

- [ ] **Step 4: Run it — expect pass** — `mix test test/teacher_assistant/academics/module_grouping_test.exs` → PASS.

- [ ] **Step 5: Write the hand-written data migration**

```elixir
# priv/repo/migrations/<ts>_backfill_progression_modules.exs
defmodule TeacherAssistant.Repo.Migrations.BackfillProgressionModules do
  use Ecto.Migration
  import Ecto.Query
  alias TeacherAssistant.Repo
  alias TeacherAssistant.Academics.ModuleGrouping

  # French default-bucket title; EN column comes from gettext at render time, but the
  # stored title is a plain string, so we store the FR label (teacher-editable later).
  @default_title "Général"

  def up do
    plan_ids =
      from(p in "progression_plans", select: p.id) |> Repo.all()

    Enum.each(plan_ids, &backfill_plan/1)
  end

  def down do
    # Non-reversible data migration; the column drop in the paired schema migration
    # is what `down` there restores. Nothing to undo here.
    :ok
  end

  defp backfill_plan(plan_id) do
    entries =
      from(e in "progression_entries",
        where: e.progression_plan_id == ^plan_id,
        select: %{id: e.id, module: e.module, position: e.position}
      )
      |> Repo.all()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries
    |> ModuleGrouping.group()
    |> Enum.with_index(1)
    |> Enum.each(fn {%{key: key, entry_ids: entry_ids}, mod_position} ->
      module_id = Ecto.UUID.generate()
      default? = key == :default
      title = if default?, do: @default_title, else: key

      Repo.insert_all("progression_modules", [
        %{
          id: Ecto.UUID.dump!(module_id) |> elem(1),
          title: title,
          position: mod_position,
          default?: default?,
          progression_plan_id: plan_id,
          inserted_at: now,
          updated_at: now
        }
      ])

      entry_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {entry_id, entry_position} ->
        from(e in "progression_entries", where: e.id == ^entry_id)
        |> Repo.update_all(
          set: [progression_module_id: entry_id_module(module_id), position: entry_position]
        )
      end)
    end)
  end

  # progression_modules.id is a uuid; store the raw uuid the same way Ecto returns it.
  defp entry_id_module(module_id), do: module_id
end
```

> NOTE for the implementer: `Repo.insert_all` with a string UUID for `id` and `progression_plan_id` works directly when the columns are `:uuid` — pass the string UUIDs (`Ecto.UUID.generate()` and the existing `plan_id`), and drop the `Ecto.UUID.dump!` gymnastics if the adapter accepts strings (it does for AshPostgres uuid columns). Verify by running the migration against a seeded dev DB (Step 7) and reading one row back.

- [ ] **Step 6: Tighten the model + generate the drop migration**

In `progression_entry.ex`:
- change the `progression_module` relationship to `allow_nil? false`;
- **remove** `attribute :module, :string, allow_nil?: false, public?: true`;
- in `actions do`, remove `:module` from both the `create:` and `update:` accept lists and add `:progression_module_id` to both.

Run: `mix ash.codegen drop_progression_entry_module`
Expected: a migration that (a) sets `progression_module_id NOT NULL` and (b) drops the `module` column. **Rename the generated file's timestamp is fine; ensure it sorts AFTER the backfill migration** so backfill runs first.

- [ ] **Step 7: Migrate a seeded DB and eyeball**

```bash
mix ecto.reset   # ash.setup + seeds, then runs all migrations in order
```
Expected: clean migrate. Manually confirm in `iex -S mix`:
```elixir
plan = TeacherAssistant.Academics.ProgressionPlan |> Ash.read!(authorize?: false) |> List.first()
```
(If seeds create no plans, skip — the automated tests in later tasks cover behavior.)

- [ ] **Step 8: Full suite** — `mix test` → PASS (existing progression/import/fiche tests will fail here because they still pass `module:` strings; **that is expected and fixed in Tasks 3–6**). If you are running strictly test-green per task, run only `mix test test/teacher_assistant/academics/module_grouping_test.exs` here and defer the suite to Task 6.

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant/academics/module_grouping.ex \
  test/teacher_assistant/academics/module_grouping_test.exs \
  lib/teacher_assistant/academics/progression_entry.ex \
  priv/repo/migrations
git commit -m "feat(academics): backfill string modules into ProgressionModule + drop module column"
```

---

### Task 3: Domain API — module CRUD, module-targeted entry add, list, default bucket, duplicate

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/progression_module_test.exs` (extend)

**Interfaces:**
- Produces:
  - `ensure_default_module(plan) :: {:ok, ProgressionModule.t()}` — fetch-or-create the `default? = true` bucket (appended at end if created).
  - `list_progression_modules(plan) :: [ProgressionModule.t()]` — ordered by position, each with `entries` loaded and ordered by position.
  - `create_module(plan, %{title: String.t()}) :: {:ok, ProgressionModule.t()}` — appended at `position = count + 1`.
  - `rename_module(module, title) :: {:ok, ProgressionModule.t()}`.
  - `delete_module(module) :: :ok | {:error, :default_bucket}` — reassigns its entries to the default bucket (appended) then destroys; refuses when `module.default?`.
  - `add_progression_entry(module, attrs) :: {:ok, ProgressionEntry.t()}` — **signature changes** from plan-targeted to module-targeted; appends within the module.
  - `fetch_owned_module(id, ws) :: {:ok, ProgressionModule.t()} | {:error, :not_found}`.
  - `duplicate_progression_plan/2` copies modules then entries.

- [ ] **Step 1: Write failing tests** (append to `progression_module_test.exs`)

```elixir
  test "add entries into a module get per-module positions", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e1} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, e2} = Academics.add_progression_entry(m, %{lesson_title: "L2", entry_type: :lesson})
    assert e1.position == 1 and e2.position == 2
    assert e1.progression_module_id == m.id
  end

  test "delete_module reassigns entries to the default bucket and refuses on the bucket",
       %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, _e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, bucket} = Academics.ensure_default_module(plan)

    assert :ok = Academics.delete_module(m)
    [reloaded] = Academics.list_progression_modules(plan) |> Enum.filter(& &1.default?)
    assert reloaded.id == bucket.id
    assert length(reloaded.entries) == 1
    assert {:error, :default_bucket} = Academics.delete_module(bucket)
  end

  test "list_progression_modules returns modules ordered with ordered entries", %{plan: plan} do
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, _} = Academics.add_progression_entry(m1, %{lesson_title: "L1", entry_type: :lesson})
    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    assert [%{lesson_title: "L1"}] = hd(mods).entries
    assert m2.id in Enum.map(mods, & &1.id)
  end
```

- [ ] **Step 2: Run — expect fail** — `mix test test/teacher_assistant/academics/progression_module_test.exs` → FAIL (undefined functions).

- [ ] **Step 3: Implement the domain functions**

Add to `lib/teacher_assistant/academics.ex` (near the existing progression helpers ~line 861). Replace the current `add_progression_entry/2` with the module-targeted version.

```elixir
  def ensure_default_module(%ProgressionPlan{id: plan_id} = plan) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id and default? == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %ProgressionModule{} = m} ->
        {:ok, m}

      {:ok, nil} ->
        pos = module_count(plan_id) + 1

        ProgressionModule
        |> Ash.Changeset.for_create(:create_default_bucket, %{
          title: "Général",
          position: pos,
          progression_plan_id: plan_id
        })
        |> Ash.create(authorize?: false)
    end
  end

  def list_progression_modules(%ProgressionPlan{id: plan_id}) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.Query.load(entries: Ash.Query.sort(ProgressionEntry, position: :asc))
    |> Ash.read!(authorize?: false)
  end

  def create_module(%ProgressionPlan{id: plan_id}, attrs) do
    pos = module_count(plan_id) + 1

    ProgressionModule
    |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{position: pos, progression_plan_id: plan_id}))
    |> Ash.create(authorize?: false)
  end

  def rename_module(%ProgressionModule{} = m, title),
    do: m |> Ash.Changeset.for_update(:update, %{title: title}) |> Ash.update(authorize?: false)

  def delete_module(%ProgressionModule{default?: true}), do: {:error, :default_bucket}

  def delete_module(%ProgressionModule{} = m) do
    {:ok, plan} = Ash.get(ProgressionPlan, m.progression_plan_id, authorize?: false)
    {:ok, bucket} = ensure_default_module(plan)
    base = entry_count(bucket.id)

    entries_in_module(m.id)
    |> Enum.with_index(base + 1)
    |> Enum.each(fn {e, pos} ->
      update_progression_entry(e, %{progression_module_id: bucket.id, position: pos})
    end)

    Ash.destroy(m, authorize?: false)
  end

  def add_progression_entry(%ProgressionModule{id: module_id, progression_plan_id: plan_id}, attrs) do
    pos = entry_count(module_id) + 1

    attrs =
      attrs
      |> Map.put(:progression_plan_id, plan_id)
      |> Map.put(:progression_module_id, module_id)
      |> Map.put(:position, pos)

    ProgressionEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def fetch_owned_module(id, %Workspace{id: ws_id}) do
    ProgressionModule
    |> Ash.Query.filter(id == ^id and progression_plan.workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  defp module_count(plan_id) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id)
    |> Ash.count!(authorize?: false)
  end

  defp entry_count(module_id) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.count!(authorize?: false)
  end

  defp entries_in_module(module_id) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end
```

- [ ] **Step 4: Fix `duplicate_progression_plan/2` for the new model**

Replace the entry-copy loop (lines ~838-858) so it copies modules first, then entries into their new module:

```elixir
      for m <- list_progression_modules(plan) do
        {:ok, new_m} =
          ProgressionModule
          |> Ash.Changeset.for_create(
            (if m.default?, do: :create_default_bucket, else: :create),
            %{title: m.title, position: m.position, progression_plan_id: copy.id}
          )
          |> Ash.create(authorize?: false)

        for e <- m.entries do
          ProgressionEntry
          |> Ash.Changeset.for_create(:create, %{
            lesson_title: e.lesson_title,
            planned_hours: e.planned_hours,
            entry_type: e.entry_type,
            week_no: e.week_no,
            position: e.position,
            famille_de_situations: e.famille_de_situations,
            categories_action: e.categories_action,
            competence_visee: e.competence_visee,
            progression_plan_id: copy.id,
            progression_module_id: new_m.id,
            sequence_id: e.sequence_id
          })
          |> Ash.create!(authorize?: false)
        end
      end
```

- [ ] **Step 5: Run — expect pass** — `mix test test/teacher_assistant/academics/progression_module_test.exs` → PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/progression_module_test.exs
git commit -m "feat(academics): module CRUD, module-targeted entry add, default bucket, duplicate"
```

---

### Task 4: `apply_layout/2` — transactional reorder endpoint

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/apply_layout_test.exs`

**Interfaces:**
- Produces: `apply_layout(plan, layout) :: {:ok, :applied} | {:error, :invalid_layout}` where `layout` is `[%{"module_id" => id, "entry_ids" => [id, ...]}, ...]`. Validates the layout covers exactly the plan's current module set and entry set (no missing/extra/foreign/duplicate ids); on success, sets module positions from list order and each entry's `progression_module_id` + `position` from its index; all in one `Repo.transaction`.

- [ ] **Step 1: Write failing tests**

```elixir
# test/teacher_assistant/academics/apply_layout_test.exs
defmodule TeacherAssistant.Academics.ApplyLayoutTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "Y", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "P"})
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, a} = Academics.add_progression_entry(m1, %{lesson_title: "A", entry_type: :lesson})
    {:ok, b} = Academics.add_progression_entry(m1, %{lesson_title: "B", entry_type: :lesson})
    {:ok, c} = Academics.add_progression_entry(m2, %{lesson_title: "C", entry_type: :lesson})
    %{plan: plan, m1: m1, m2: m2, a: a, b: b, c: c}
  end

  test "reorders modules and moves a lesson across modules", %{plan: plan, m1: m1, m2: m2, a: a, b: b, c: c} do
    layout = [
      %{"module_id" => m2.id, "entry_ids" => [c.id, b.id]},
      %{"module_id" => m1.id, "entry_ids" => [a.id]}
    ]

    assert {:ok, :applied} = Academics.apply_layout(plan, layout)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M2", "M1"]
    [first, second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["C", "B"]
    assert Enum.map(second.entries, & &1.lesson_title) == ["A"]
  end

  test "rejects a layout missing an entry", %{plan: plan, m1: m1, m2: m2, a: a, c: c} do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id]}
    ]

    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)
  end

  test "rejects a foreign module id", %{plan: plan, m1: m1, a: a, b: b, c: c} do
    layout = [%{"module_id" => Ecto.UUID.generate(), "entry_ids" => [a.id, b.id, c.id]}]
    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)
  end
end
```

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Implement `apply_layout/2`**

```elixir
  def apply_layout(%ProgressionPlan{id: plan_id}, layout) when is_list(layout) do
    current_modules = ProgressionModule |> Ash.Query.filter(progression_plan_id == ^plan_id) |> Ash.read!(authorize?: false)
    current_entries = list_entries_query(plan_id) |> Ash.read!(authorize?: false)

    layout_module_ids = Enum.map(layout, & &1["module_id"])
    layout_entry_ids = Enum.flat_map(layout, & &1["entry_ids"])

    cond do
      not id_set_matches?(layout_module_ids, Enum.map(current_modules, & &1.id)) ->
        {:error, :invalid_layout}

      not id_set_matches?(layout_entry_ids, Enum.map(current_entries, & &1.id)) ->
        {:error, :invalid_layout}

      true ->
        module_by_id = Map.new(current_modules, &{&1.id, &1})
        entry_by_id = Map.new(current_entries, &{&1.id, &1})

        Repo.transaction(fn ->
          layout
          |> Enum.with_index(1)
          |> Enum.each(fn {%{"module_id" => mid, "entry_ids" => eids}, mpos} ->
            {:ok, _} = update_module_position(module_by_id[mid], mpos)

            eids
            |> Enum.with_index(1)
            |> Enum.each(fn {eid, epos} ->
              {:ok, _} =
                update_progression_entry(entry_by_id[eid], %{
                  progression_module_id: mid,
                  position: epos
                })
            end)
          end)
        end)

        {:ok, :applied}
    end
  end

  defp update_module_position(%ProgressionModule{} = m, pos),
    do: m |> Ash.Changeset.for_update(:update, %{position: pos}) |> Ash.update(authorize?: false)

  defp id_set_matches?(a, b), do: MapSet.new(a) == MapSet.new(b) and length(a) == length(b)
```

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/apply_layout_test.exs
git commit -m "feat(academics): apply_layout/2 transactional reorder with strict validation"
```

---

### Task 5: Rewrite `import_progression_plan/3` for modules

**Files:**
- Modify: `lib/teacher_assistant/academics.ex` (`import_progression_plan/3`, ~line 762)
- Test: `test/teacher_assistant/academics/import_progression_plan_test.exs` (update)

**Interfaces:**
- Consumes: `ModuleGrouping.group/1`, `ensure_default_module/1`. Rows still have `:module` (string), `:lesson_title`, `:planned_hours`, `:entry_type`, `:week_no`, `:sequence_id`.
- Produces: unchanged return `{:ok, plan}`; entries are now linked to created modules.

- [ ] **Step 1: Update the import test** — open `import_progression_plan_test.exs`, and after import assert modules exist and entries are linked. Add:

```elixir
  test "import creates modules from row order and links entries", %{ws: ws, ctx: ctx} do
    rows = [
      %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson},
      %{module: "M1", lesson_title: "L2", planned_hours: Decimal.new("2"), entry_type: :lesson},
      %{module: "", lesson_title: "Prise de contact", planned_hours: Decimal.new("1"), entry_type: :lesson},
      %{module: "M2", lesson_title: "L3", planned_hours: Decimal.new("2"), entry_type: :lesson}
    ]

    {:ok, plan} = Academics.import_progression_plan(ws, %{title: "T", teaching_context_id: ctx.id}, rows)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "Général", "M2"]
    assert Enum.map(hd(mods).entries, & &1.lesson_title) == ["L1", "L2"]
    assert Enum.any?(mods, &(&1.default? and Enum.map(&1.entries, fn e -> e.lesson_title end) == ["Prise de contact"]))
  end
```

> Check the existing setup block in this test file for how `ws`/`ctx` are provided; reuse the same fixture names. If the file’s setup differs, adapt the `%{ws: ws, ctx: ctx}` pattern to match.

- [ ] **Step 2: Run — expect fail** (old import still writes `module:` strings and will now crash on the dropped column).

- [ ] **Step 3: Rewrite the import body**

Replace the `entry_notifs = rows |> ...` section inside the transaction with module-aware creation:

```elixir
          groups = TeacherAssistant.Academics.ModuleGrouping.group(index_rows(rows))
          rows_by_index = rows |> Enum.with_index() |> Map.new(fn {r, i} -> {i, r} end)

          entry_notifs =
            groups
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {%{key: key, entry_ids: row_indexes}, mod_pos} ->
              {:ok, module} = create_import_module(plan, key, mod_pos)

              row_indexes
              |> Enum.with_index(1)
              |> Enum.flat_map(fn {row_index, entry_pos} ->
                row = Map.fetch!(rows_by_index, row_index)

                entry_attrs =
                  row
                  |> Map.take([:lesson_title, :planned_hours, :entry_type, :week_no, :sequence_id])
                  |> Map.put(:progression_plan_id, plan.id)
                  |> Map.put(:progression_module_id, module.id)
                  |> Map.put(:position, entry_pos)

                case ProgressionEntry
                     |> Ash.Changeset.for_create(:create, entry_attrs)
                     |> Ash.create(authorize?: false, return_notifications?: true) do
                  {:ok, _entry, notifs} -> notifs
                  {:error, reason} -> Repo.rollback(reason)
                end
              end)
            end)
```

Add these private helpers near the import function:

```elixir
  # ModuleGrouping.group/1 keys entries by :id; feed it the row *index* as the id so we
  # can map groups back to rows.
  defp index_rows(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {r, i} -> %{id: i, module: Map.get(r, :module), position: i} end)
  end

  defp create_import_module(plan, :default, pos) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create_default_bucket, %{title: "Général", position: pos, progression_plan_id: plan.id})
    |> Ash.create(authorize?: false)
  end

  defp create_import_module(plan, title, pos) when is_binary(title) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create, %{title: title, position: pos, progression_plan_id: plan.id})
    |> Ash.create(authorize?: false)
  end
```

- [ ] **Step 4: Run — expect pass** — `mix test test/teacher_assistant/academics/import_progression_plan_test.exs` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/import_progression_plan_test.exs
git commit -m "feat(academics): import builds ProgressionModules from row order"
```

---

### Task 6: `FicheLive` grouped rendering + module CRUD UI + fiche-print fix

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Modify: `lib/teacher_assistant_web/controllers/fiche_print_html/show.html.heex:51`
- Modify: `lib/teacher_assistant_web/controllers/fiche_print_controller.ex` (preload the module)
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs` (update + add)

**Interfaces:**
- Consumes: `list_progression_modules/1`, `create_module/2`, `rename_module/2`, `delete_module/1`, `add_progression_entry/2` (module-targeted), `fetch_owned_module/2`.

- [ ] **Step 1: Update/extend the LiveView test** — the existing add/delete tests pass `module:` in the entry form and assume a flat table; rewrite them around modules. Add:

```elixir
  test "add a module then a lesson into it", %{conn: conn, plan: plan} do
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view |> form("#add-module-form", %{module: %{title: "Algorithmique"}}) |> render_submit()
    assert render(view) =~ "Algorithmique"

    module = Academics.list_progression_modules(plan) |> Enum.find(&(&1.title == "Algorithmique"))

    view
    |> form("#add-entry-form-#{module.id}", %{entry: %{lesson_title: "Les boucles", planned_hours: "2", entry_type: "lesson"}})
    |> render_submit()

    assert render(view) =~ "Les boucles"
  end

  test "delete a module reassigns its lessons to the default bucket", %{conn: conn, plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, _} = Academics.add_progression_entry(m, %{lesson_title: "Orpheline", entry_type: :lesson})
    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view |> element("#module-delete-#{m.id}") |> render_click()

    assert render(view) =~ "Orpheline"
    refute Academics.list_progression_modules(plan) |> Enum.any?(&(&1.id == m.id))
  end
```

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Rewrite `assign_entries` → `assign_modules`** in `fiche_live.ex`:

```elixir
  defp assign_modules(socket, plan) do
    ctx =
      case Academics.get_teaching_context(plan.teaching_context_id) do
        {:ok, ctx} -> ctx
        _ -> nil
      end

    modules = Academics.list_progression_modules(plan)

    prepared =
      modules
      |> Enum.flat_map(& &1.entries)
      |> Enum.filter(fn e -> Academics.get_lesson_plan_for_entry(e.id) end)
      |> MapSet.new(& &1.id)

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:modules, modules)
    |> assign(:prepared, prepared)
    |> assign(:module_form, to_form(%{}, as: :module))
  end

  defp module_hours(%{entries: entries}),
    do: Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.planned_hours) end)

  defp all_entries(modules), do: Enum.flat_map(modules, & &1.entries)
```

Update `mount/3` to call `assign_modules` and `hours_total/1` to take `all_entries(@modules)`.

- [ ] **Step 4: Update the handlers** — replace `add-entry` to target a module, keep `delete-entry`, add module handlers:

```elixir
  def handle_event("add-module", %{"module" => %{"title" => title}}, socket) do
    case title && String.trim(title) do
      t when t in [nil, ""] ->
        {:noreply, socket}

      t ->
        {:ok, _} = Academics.create_module(socket.assigns.plan, %{title: t})
        {:noreply, assign_modules(socket, socket.assigns.plan)}
    end
  end

  def handle_event("rename-module", %{"id" => id, "title" => title}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         {:ok, _} <- Academics.rename_module(m, title) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not rename module"))}
    end
  end

  def handle_event("delete-module", %{"id" => id}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, m} <- ws && Academics.fetch_owned_module(id, ws),
         :ok <- Academics.delete_module(m) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      {:error, :default_bucket} ->
        {:noreply, put_flash(socket, :error, gettext("The default section cannot be deleted"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete module"))}
    end
  end

  def handle_event("add-entry", %{"module_id" => module_id, "entry" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, module} <- ws && Academics.fetch_owned_module(module_id, ws),
         {:ok, _} <-
           Academics.add_progression_entry(module, %{
             lesson_title: p["lesson_title"],
             planned_hours: Decimal.new(blank_to(p["planned_hours"], "1")),
             entry_type: String.to_existing_atom(p["entry_type"])
           }) do
      {:noreply, assign_modules(socket, socket.assigns.plan)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not add entry"))}
    end
  end
```

- [ ] **Step 5: Rewrite `render/1`** to group by module. Structure (fill in with the existing per-entry cell markup, swapping `e.module` out):

```heex
<section id="fiche-builder" class="space-y-6">
  <.page_header eyebrow={gettext("Fiche de progression")} title={@plan.title}>
    <:actions>
      <.button id="duplicate-plan" phx-click="duplicate-plan" class="btn btn-ghost btn-sm gap-2">
        <.icon name="hero-document-duplicate" class="size-4" /> {gettext("Duplicate")}
      </.button>
    </:actions>
  </.page_header>

  <div id="fiche-hours-total" class="flex items-center gap-3">
    <.stat label={gettext("Planned hours")} value={Decimal.to_string(hours_total(all_entries(@modules)))} suffix="h" />
  </div>

  <div id="fiche-modules" class="space-y-4">
    <article :for={m <- @modules} id={"module-#{m.id}"} class="card bg-base-100 p-4 space-y-2">
      <header class="flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <span class="ta-eyebrow">{m.title}</span>
          <span class="ta-num text-sm text-base-content/60">{Decimal.to_string(module_hours(m))}h</span>
        </div>
        <.button
          :if={not m.default?}
          id={"module-delete-#{m.id}"}
          phx-click="delete-module"
          phx-value-id={m.id}
          class="btn btn-ghost btn-xs text-error"
        >
          <.icon name="hero-trash" class="size-4" />
          <span class="sr-only">{gettext("Delete module")}</span>
        </.button>
      </header>

      <ul class="space-y-1">
        <li :for={e <- m.entries} id={"entry-#{e.id}"} class="ta-leaf flex items-center justify-between gap-2 px-2 py-1.5">
          <span>
            <span class="font-display font-semibold">{e.lesson_title}</span>
            <span class="badge badge-soft badge-sm ml-1">{e.entry_type}</span>
            <span class="ta-num ml-1 text-sm text-base-content/60">{e.planned_hours}h</span>
          </span>
          <div class="flex items-center gap-1">
            <.link navigate={~p"/teacher/entries/#{e.id}/fiche"} class="btn btn-ghost btn-xs gap-1">
              <.icon name="hero-document-text" class="size-3.5" /> {gettext("Préparer")}
              <.icon :if={MapSet.member?(@prepared, e.id)} name="hero-check-circle" class="size-3.5 text-success" />
            </.link>
            <.button phx-click="delete-entry" phx-value-id={e.id} class="btn btn-ghost btn-xs text-error">
              <.icon name="hero-trash" class="size-4" /><span class="sr-only">{gettext("Delete")}</span>
            </.button>
          </div>
        </li>
      </ul>

      <.form for={to_form(%{}, as: :entry)} id={"add-entry-form-#{m.id}"} phx-submit="add-entry" class="flex flex-wrap items-end gap-2">
        <input type="hidden" name="module_id" value={m.id} />
        <.input field={to_form(%{}, as: :entry)[:lesson_title]} label={gettext("Lesson")} />
        <.input type="number" field={to_form(%{}, as: :entry)[:planned_hours]} label={gettext("Hours")} value="1" />
        <.input type="select" field={to_form(%{}, as: :entry)[:entry_type]} label={gettext("Type")}
          options={for t <- Reference.entry_types(), do: {t.fr, t.key}} />
        <.button type="submit" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus" class="size-4" /> {gettext("Add")}
        </.button>
      </.form>
    </article>
  </div>

  <.form for={@module_form} id="add-module-form" phx-submit="add-module" class="card bg-base-100 p-4 flex flex-wrap items-end gap-2">
    <.input field={@module_form[:title]} label={gettext("New module")} />
    <.button type="submit" class="btn btn-primary btn-sm gap-1">
      <.icon name="hero-plus" class="size-4" /> {gettext("Add module")}
    </.button>
  </.form>
</section>
```

> Wrap this in the existing `<Layouts.app flash={@flash} current_scope={@current_scope}>...</Layouts.app>`. Keep the `weeks_estimate` line if you want; it is unaffected.

- [ ] **Step 6: Fix the fiche-print reader** — in `fiche_print_html/show.html.heex:51` change `{@bundle.entry.module}` → `{@bundle.entry.progression_module.title}`, and in `fiche_print_controller.ex` load the association on the entry it fetches (add `Ash.Query.load(:progression_module)` or `Ash.load(entry, :progression_module)` where the bundle entry is read).

- [ ] **Step 7: Run the LiveView + print tests — expect pass**

```bash
mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs \
  test/teacher_assistant_web/controllers/fiche_print_controller_test.exs
```

- [ ] **Step 8: Extract + merge gettext, then full suite**

```bash
mix gettext.extract --merge
mix test
```
Expected: full suite PASS. Fill in FR/EN for the new msgids in `priv/gettext/{fr,en}/LC_MESSAGES/default.po` (e.g. "New module" → "Nouveau module", "Add module" → "Ajouter un module", "The default section cannot be deleted" → "La section par défaut ne peut pas être supprimée").

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant_web priv/gettext test/teacher_assistant_web
git commit -m "feat(fiche): group progression by module, module CRUD UI, print fix"
```

---

### Task 7: SortableJS drag-and-drop + keyboard-accessible handles

**Files:**
- Create: `assets/vendor/sortable.js` (vendored SortableJS 1.15.x ESM build)
- Create: `assets/js/hooks/module_layout.js`
- Modify: `assets/js/app.js` (register hook)
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex` (phx-hook containers + `apply-layout` handler + drag handles)
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs` (add `apply-layout` event test)

**Interfaces:**
- Consumes: `apply_layout/2`.
- Produces: LiveView handles `handle_event("apply-layout", %{"layout" => layout}, socket)`.

- [ ] **Step 1: Write the failing `apply-layout` LiveView test** (the JS DnD itself is not unit-tested; the server contract is)

```elixir
  test "apply-layout event reorders modules and moves a lesson", %{conn: conn, plan: plan} do
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, a} = Academics.add_progression_entry(m1, %{lesson_title: "A", entry_type: :lesson})
    {:ok, c} = Academics.add_progression_entry(m2, %{lesson_title: "C", entry_type: :lesson})

    {:ok, view, _} = live(conn, ~p"/teacher/plans/#{plan.id}")

    render_hook(view, "apply-layout", %{
      "layout" => [
        %{"module_id" => m2.id, "entry_ids" => [c.id, a.id]},
        %{"module_id" => m1.id, "entry_ids" => []}
      ]
    })

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M2", "M1"]
    assert Enum.map(hd(mods).entries, & &1.lesson_title) == ["C", "A"]
  end
```

- [ ] **Step 2: Run — expect fail.**

- [ ] **Step 3: Add the LiveView handler**

```elixir
  def handle_event("apply-layout", %{"layout" => layout}, socket) do
    case Academics.apply_layout(socket.assigns.plan, layout) do
      {:ok, :applied} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
      {:error, _} -> {:noreply, assign_modules(socket, socket.assigns.plan)}
    end
  end
```

- [ ] **Step 4: Run the handler test — expect pass** — `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs -k apply-layout` (or run the whole file).

- [ ] **Step 5: Vendor SortableJS** — download the ESM build of SortableJS 1.15.x to `assets/vendor/sortable.js` (single self-contained ESM file, no transitive deps). Confirm it exports `default` (the `Sortable` class).

- [ ] **Step 6: Write the hook** with cross-module drag + keyboard support

```javascript
// assets/js/hooks/module_layout.js
import Sortable from "../../vendor/sortable.js"

// Reads the DOM under #fiche-modules and builds the layout payload the server expects.
function readLayout(root) {
  return Array.from(root.querySelectorAll("[data-module-id]")).map((moduleEl) => ({
    module_id: moduleEl.getAttribute("data-module-id"),
    entry_ids: Array.from(moduleEl.querySelectorAll("[data-entry-id]")).map((e) =>
      e.getAttribute("data-entry-id")
    ),
  }))
}

const ModuleLayout = {
  mounted() {
    const root = this.el
    const push = () => this.pushEvent("apply-layout", { layout: readLayout(root) })

    // Level 1: modules sortable by their header handle.
    this.moduleSortable = new Sortable(root, {
      handle: "[data-module-handle]",
      animation: 150,
      onEnd: push,
    })

    // Level 2: lessons sortable within each module, shared group => cross-module drag.
    this.entrySortables = Array.from(root.querySelectorAll("[data-entries]")).map((listEl) =>
      new Sortable(listEl, {
        group: "lessons",
        handle: "[data-entry-handle]",
        animation: 150,
        onEnd: push,
      })
    )

    // Keyboard fallback: focusable handles; Enter/Space grabs, Arrow moves, Enter/Space drops.
    this.grabbed = null
    root.addEventListener("keydown", (ev) => this.onKey(ev, root, push))
  },

  onKey(ev, root, push) {
    const handle = ev.target.closest("[data-entry-handle],[data-module-handle]")
    if (!handle) return
    const item = handle.closest("[data-entry-id],[data-module-id]")

    if (ev.key === "Enter" || ev.key === " ") {
      ev.preventDefault()
      this.grabbed = this.grabbed === item ? null : item
      this.announce(root, this.grabbed ? "grabbed" : "dropped")
      if (!this.grabbed) push()
      return
    }

    if (!this.grabbed || (ev.key !== "ArrowUp" && ev.key !== "ArrowDown")) return
    ev.preventDefault()
    const sibling =
      ev.key === "ArrowUp" ? item.previousElementSibling : item.nextElementSibling
    if (!sibling) return
    if (ev.key === "ArrowUp") item.parentNode.insertBefore(item, sibling)
    else item.parentNode.insertBefore(sibling, item)
    handle.focus()
  },

  announce(root, msg) {
    let live = root.querySelector("[data-sr-live]")
    if (live) live.textContent = msg
  },

  destroyed() {
    this.moduleSortable && this.moduleSortable.destroy()
    ;(this.entrySortables || []).forEach((s) => s.destroy())
  },
}

export default ModuleLayout
```

- [ ] **Step 7: Register the hook** in `assets/js/app.js`:

```javascript
import ModuleLayout from "./hooks/module_layout.js"
// ...
  hooks: {...colocatedHooks, ModuleLayout},
```

- [ ] **Step 8: Wire the DOM attributes** in `fiche_live.ex` render:
  - add `phx-hook="ModuleLayout" id="fiche-modules"` to the `#fiche-modules` div, plus `<span data-sr-live aria-live="polite" class="sr-only"></span>` inside it;
  - on each `<article>`: `data-module-id={m.id}`;
  - add a module handle button in the header: `<button type="button" data-module-handle class="btn btn-ghost btn-xs cursor-grab" aria-label={gettext("Reorder module")}><.icon name="hero-bars-3" class="size-4" /></button>`;
  - on the `<ul>`: `data-entries`;
  - on each `<li>`: `data-entry-id={e.id}`, and add `<button type="button" data-entry-handle class="btn btn-ghost btn-xs cursor-grab" aria-label={gettext("Reorder lesson")}><.icon name="hero-bars-2" class="size-3.5" /></button>` at the row start.

- [ ] **Step 9: Build assets + manual smoke** — `mix assets.build`; then `mix phx.server`, open a plan with ≥2 modules, drag a module, drag a lesson across modules, and tab to a handle + Enter + ArrowUp/Down + Enter. Confirm order persists on reload. Add the new gettext msgids (`mix gettext.extract --merge`) with FR/EN ("Reorder module" → "Réordonner le module", etc.).

- [ ] **Step 10: Full gate + commit**

```bash
mix precommit
git add assets lib/teacher_assistant_web priv/gettext test/teacher_assistant_web/live/teacher/fiche_live_test.exs
git commit -m "feat(fiche): SortableJS drag-and-drop reorder + keyboard-accessible handles"
```

---

## Self-Review

**Spec coverage:**
- §1 data model → Task 1 (resource + nullable FK), Task 2 (tighten + drop string). ✅
- §2 migration (group, first-appearance, default bucket, per-module positions) → Task 2 (`ModuleGrouping` + data migration). ✅
- §3 import & parser → Task 5. ✅
- §4 domain API (`list_progression_modules`, module CRUD, `add_progression_entry` module-targeted, `ensure_default_module`, `apply_layout`) → Tasks 3 & 4. ✅
- §5 UI grouped + SortableJS + keyboard → Tasks 6 & 7. ✅
- §6 readers of `entry.module` (FicheLive, FichePrint) → Task 6. ✅
- §7 tests (resource, apply_layout reject, migration, import, LiveView, coverage non-regression) → covered across Tasks 1–7; `Coverage` is untouched so its existing test stands as the non-regression guard (run `mix test test/teacher_assistant/academics/coverage_test.exs` in Task 6 Step 8's full suite). ✅

**Placeholder scan:** No "TBD"/"add error handling"/"similar to". The two implementer NOTES (UUID insert form in Task 2; fixture-name check in Task 5) point at real environment specifics to verify, not deferred work. ✅

**Type consistency:** `apply_layout/2` payload keys `"module_id"`/`"entry_ids"` are identical in the JS hook (`readLayout`), the domain function, and the tests. `add_progression_entry/2` is consistently module-targeted after Task 3 (no remaining plan-targeted callers: import uses direct `Ash.Changeset`; FicheLive uses the module form). `ensure_default_module/1`, `list_progression_modules/1`, `fetch_owned_module/2`, `ModuleGrouping.group/1` names match across tasks. `create_default_bucket` action used by `ensure_default_module`, import, and duplicate. ✅
