# v1.3 Fiche de préparation (lesson-plan editor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-lesson **fiche de préparation** editor scaffolded from a progression entry, with autosave-on-blur editing and a print route for browser Save-as-PDF, per [`docs/superpowers/specs/2026-07-02-lesson-plan-fiche-preparation-v1_3-design.md`](../specs/2026-07-02-lesson-plan-fiche-preparation-v1_3-design.md).

**Architecture:** Two new Ash resources (`LessonPlan` 1:1 with a `ProgressionEntry`, ordered `LessonStep` children) behind new `Academics` context functions; a LiveView editor (`LessonPlanLive`) with per-field autosave; a plain controller (`FichePrintController`) rendering a print-only HTML layout. Ownership is resolved by walking the entry → progression plan → teaching context to the workspace, reusing existing `fetch_owned_*` helpers.

**Tech Stack:** Elixir, Ash 3 + AshPostgres (codegen migrations via `mix ash.codegen`), Phoenix LiveView + HEEx, daisyUI/Tailwind ("Tableau" theme), gettext FR/EN.

## Global Constraints

- **Ownership / IDOR:** every entry point resolves through `Academics.fetch_owned_entry_with_context/2`; a foreign/unknown entry id → `:error` → redirect to `/teacher`. Step mutations resolve the step scoped to the mounted `LessonPlan` (`fetch_owned_lesson_step/2`).
- **CBA fields optional:** all `LessonPlan`/`LessonStep` content fields `allow_nil? true` (usable PPO-style). Only `duration_minutes` (default 55) and step `position` are non-nil.
- **No new enums:** nothing here needs a constrained atom; do NOT introduce a bare `:atom` attribute. (If one is ever needed, define an `Ash.Type.Enum`.)
- **Derived-at-render (never stored on the fiche):** `module`, `famille_de_situations`, `categories_action` read from the entry; `classe` from `ctx.level`; `discipline` from `ctx.subject`; `effectif` from `length(list_students(class_group))`; `annee` from `year.name`.
- **Design system:** reuse the "Tableau" kit — `<.page_header>`, `<.stat>`, `<.empty_state>`, `ta-leaf`, `ta-eyebrow`, `ta-num`; mobile-first cards → `md:` table; touch inputs ≥44px; `inputmode="numeric"` on minute fields.
- **All copy via `gettext`**; new msgids extracted + FR-translated in the final task (do NOT run `gettext.extract` per task).
- **Stable DOM ids** (tests pin them): `#lesson-plan`, `#fiche-header-form`, `#fiche-saved-indicator`, `#fiche-duration-check`, `#lesson-steps`, `#step-row-<id>`, `#step-add`, `#step-delete-<id>`, `#step-up-<id>`, `#step-down-<id>`, `#fiche-print-link`; on the progression builder `#entry-prepare-<id>`, `#entry-prepared-<id>`.
- `mix precommit` green at every commit (`compile --warning-as-errors`, `deps.unlock --unused`, `format`, `test`). Suite is currently **127 tests, 0 failures**.
- Migrations use the Ash codegen flow: `mix ash.codegen <name>` (writes migration + resource snapshot), then `mix ecto.migrate`. The `test` alias runs `ash.setup` so tests pick up new migrations automatically.
- Work on branch `feat/lesson-plan-v1_3` off `main`.

## File Structure

- `lib/teacher_assistant/academics/lesson_plan.ex` — the fiche resource (create).
- `lib/teacher_assistant/academics/lesson_step.ex` — the step resource (create).
- `lib/teacher_assistant/academics.ex` — register resources + add context functions (modify).
- `priv/repo/migrations/*_add_lesson_plans_and_steps.exs` + `priv/resource_snapshots/repo/...` — generated (create).
- `lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex` — editor LiveView (create).
- `lib/teacher_assistant_web/controllers/fiche_print_controller.ex` — print controller (create).
- `lib/teacher_assistant_web/controllers/fiche_print_html.ex` + `controllers/fiche_print_html/show.html.heex` — print template (create).
- `lib/teacher_assistant_web/router.ex` — routes (modify).
- `lib/teacher_assistant_web/live/teacher/fiche_live.ex` — "Préparer" action + prepared indicator (modify).
- Tests alongside each (create/modify).

---

### Task 1: LessonPlan + LessonStep resources and migration

**Files:**
- Create: `lib/teacher_assistant/academics/lesson_plan.ex`
- Create: `lib/teacher_assistant/academics/lesson_step.ex`
- Modify: `lib/teacher_assistant/academics.ex` (aliases + `resources do` block)
- Generated: migration + `priv/resource_snapshots/repo/lesson_plans/*.json`, `.../lesson_steps/*.json`
- Test: `test/teacher_assistant/academics/lesson_plan_resource_test.exs`

**Interfaces:**
- Consumes: existing `ProgressionEntry`, `ProgressionPlan`, `TeachingContext` resources.
- Produces: `TeacherAssistant.Academics.LessonPlan` (attrs `lesson_date`, `duration_minutes`, `titre`, `competence_attendue`, `situation_probleme`, `objectifs`, `supports`, `prerequis`; `belongs_to :progression_entry`; `has_many :lesson_steps`; identity `unique_entry` on `[:progression_entry_id]`). `TeacherAssistant.Academics.LessonStep` (attrs `position`, `etape`, `duration_minutes`, `contenus`, `supports`, `activites`; `belongs_to :lesson_plan`).

- [ ] **Step 1: Create the `LessonPlan` resource**

`lib/teacher_assistant/academics/lesson_plan.ex`:

```elixir
defmodule TeacherAssistant.Academics.LessonPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :progression_entry_id,
        :lesson_date,
        :duration_minutes,
        :titre,
        :competence_attendue,
        :situation_probleme,
        :objectifs,
        :supports,
        :prerequis
      ],
      update: [
        :lesson_date,
        :duration_minutes,
        :titre,
        :competence_attendue,
        :situation_probleme,
        :objectifs,
        :supports,
        :prerequis
      ]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :lesson_date, :date, allow_nil?: true, public?: true
    attribute :duration_minutes, :integer, default: 55, public?: true
    attribute :titre, :string, allow_nil?: true, public?: true
    attribute :competence_attendue, :string, allow_nil?: true, public?: true
    attribute :situation_probleme, :string, allow_nil?: true, public?: true
    attribute :objectifs, :string, allow_nil?: true, public?: true
    attribute :supports, :string, allow_nil?: true, public?: true
    attribute :prerequis, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry do
      source_attribute :progression_entry_id
      allow_nil? false
      public? true
    end

    has_many :lesson_steps, TeacherAssistant.Academics.LessonStep
  end

  identities do
    identity :unique_entry, [:progression_entry_id]
  end
end
```

- [ ] **Step 2: Create the `LessonStep` resource**

`lib/teacher_assistant/academics/lesson_step.ex`:

```elixir
defmodule TeacherAssistant.Academics.LessonStep do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_steps"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:lesson_plan_id, :position, :etape, :duration_minutes, :contenus, :supports, :activites],
      update: [:position, :etape, :duration_minutes, :contenus, :supports, :activites]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :etape, :string, allow_nil?: true, public?: true
    attribute :duration_minutes, :integer, allow_nil?: true, public?: true
    attribute :contenus, :string, allow_nil?: true, public?: true
    attribute :supports, :string, allow_nil?: true, public?: true
    attribute :activites, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lesson_plan, TeacherAssistant.Academics.LessonPlan do
      source_attribute :lesson_plan_id
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 3: Register both resources in the domain**

In `lib/teacher_assistant/academics.ex`, add aliases after line 17 (`alias ... TeachingLogEntry`):

```elixir
  alias TeacherAssistant.Academics.LessonPlan
  alias TeacherAssistant.Academics.LessonStep
```

and inside `resources do ... end` (after `resource TeachingLogEntry`):

```elixir
    resource LessonPlan
    resource LessonStep
```

- [ ] **Step 4: Generate the migration and migrate**

Run: `mix ash.codegen add_lesson_plans_and_steps`
Then: `mix ecto.migrate`
Expected: a new migration under `priv/repo/migrations/` creating `lesson_plans` (with a unique index on `progression_entry_id`) and `lesson_steps` (FK to `lesson_plans`), plus snapshot JSONs. Migration runs clean.

- [ ] **Step 5: Write the resource test**

`test/teacher_assistant/academics/lesson_plan_resource_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.LessonPlanResourceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{LessonPlan, LessonStep}
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

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, entry: entry}
  end

  test "a lesson plan persists and links to its entry", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id, titre: "Les entiers"})
      |> Ash.create(authorize?: false)

    assert lp.progression_entry_id == entry.id
    assert lp.duration_minutes == 55
  end

  test "the entry↔plan link is 1:1 (unique)", %{entry: entry} do
    {:ok, _} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(authorize?: false)

    assert {:error, _} =
             LessonPlan
             |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
             |> Ash.create(authorize?: false)
  end

  test "steps persist against a lesson plan", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(authorize?: false)

    {:ok, step} =
      LessonStep
      |> Ash.Changeset.for_create(:create, %{lesson_plan_id: lp.id, position: 1, etape: "Découverte"})
      |> Ash.create(authorize?: false)

    assert step.position == 1
    assert step.etape == "Découverte"
  end
end
```

- [ ] **Step 6: Run the test**

Run: `mix test test/teacher_assistant/academics/lesson_plan_resource_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/lesson_plan.ex lib/teacher_assistant/academics/lesson_step.ex lib/teacher_assistant/academics.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/lesson_plan_resource_test.exs
git commit -m "feat(academics): LessonPlan + LessonStep resources (fiche de préparation)"
```

---

### Task 2: Context API — lesson plan create-from-entry, ownership, autosave

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/lesson_plan_test.exs`

**Interfaces:**
- Consumes: `LessonPlan`, `ProgressionEntry`, `TeachingContext`; existing `fetch_owned_entry/2`, `fetch_owned_plan/2`, `fetch_owned_teaching_context/2`, `fetch_owned_class_group/2`, `current_academic_year/1`, `list_students/1`.
- Produces:
  - `fetch_owned_entry_with_context(entry_id, ws) :: {:ok, %{entry, plan, ctx, class_group, year, effectif}} | {:error, term}`
  - `ensure_lesson_plan(%ProgressionEntry{}, %TeachingContext{}) :: {:ok, %LessonPlan{}}`
  - `get_lesson_plan_for_entry(entry_id) :: %LessonPlan{} | nil`
  - `update_lesson_plan(%LessonPlan{}, attrs) :: {:ok, %LessonPlan{}} | {:error, term}`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/lesson_plan_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.LessonPlanTest do
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

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson,
        competence_visee: "Résoudre un problème additif"
      })

    %{ws: ws, entry: entry, ctx: ctx}
  end

  test "fetch_owned_entry_with_context returns derived cartouche", %{ws: ws, entry: entry} do
    assert {:ok, ctx_bundle} = Academics.fetch_owned_entry_with_context(entry.id, ws)
    assert ctx_bundle.entry.id == entry.id
    assert ctx_bundle.ctx.subject == "Maths"
    assert ctx_bundle.effectif == 2
    assert ctx_bundle.year.name == "2025-2026"
  end

  test "fetch_owned_entry_with_context rejects a foreign entry (IDOR)", %{entry: entry} do
    other = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())
    assert {:error, _} = Academics.fetch_owned_entry_with_context(entry.id, other)
  end

  test "ensure_lesson_plan seeds header from the entry and is idempotent", %{entry: entry, ctx: ctx} do
    assert {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    assert lp.titre == "Les entiers"
    assert lp.competence_attendue == "Résoudre un problème additif"
    # 2 planned hours => 120 minutes
    assert lp.duration_minutes == 120

    assert {:ok, lp2} = Academics.ensure_lesson_plan(entry, ctx)
    assert lp2.id == lp.id
  end

  test "get_lesson_plan_for_entry returns nil before creation", %{entry: entry} do
    assert Academics.get_lesson_plan_for_entry(entry.id) == nil
  end

  test "update_lesson_plan persists a single field", %{entry: entry, ctx: ctx} do
    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    {:ok, lp} = Academics.update_lesson_plan(lp, %{situation_probleme: "Au marché…"})
    assert lp.situation_probleme == "Au marché…"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/lesson_plan_test.exs`
Expected: FAIL (`fetch_owned_entry_with_context/2` undefined).

- [ ] **Step 3: Implement the context functions**

In `lib/teacher_assistant/academics.ex`, add (place after `fetch_owned_entry/2`, around line 215):

```elixir
  def fetch_owned_entry_with_context(entry_id, %PersonalWorkspace{} = ws) do
    with {:ok, entry} <- fetch_owned_entry(entry_id, ws),
         {:ok, plan} <- fetch_owned_plan(entry.progression_plan_id, ws),
         {:ok, ctx} <- fetch_owned_teaching_context(plan.teaching_context_id, ws) do
      class_group = load_owned_class_group(ctx.class_group_id, ws)
      effectif = if class_group, do: length(list_students(class_group)), else: 0

      {:ok,
       %{
         entry: entry,
         plan: plan,
         ctx: ctx,
         class_group: class_group,
         year: current_academic_year(ws),
         effectif: effectif
       }}
    end
  end

  defp load_owned_class_group(nil, _ws), do: nil

  defp load_owned_class_group(id, ws) do
    case fetch_owned_class_group(id, ws) do
      {:ok, cg} -> cg
      _ -> nil
    end
  end
```

Then add the lesson-plan functions (place after the progression-entry functions, near the bottom before `log_teaching`):

```elixir
  def get_lesson_plan_for_entry(entry_id) do
    LessonPlan
    |> Ash.Query.filter(progression_entry_id == ^entry_id)
    |> Ash.read_one!(authorize?: false)
  end

  def ensure_lesson_plan(%ProgressionEntry{} = entry, %TeachingContext{} = _ctx) do
    case get_lesson_plan_for_entry(entry.id) do
      nil -> create_lesson_plan_from_entry(entry)
      %LessonPlan{} = lp -> {:ok, lp}
    end
  end

  defp create_lesson_plan_from_entry(%ProgressionEntry{} = entry) do
    duration =
      entry.planned_hours
      |> Decimal.mult(60)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    attrs = %{
      progression_entry_id: entry.id,
      titre: entry.lesson_title,
      competence_attendue: entry.competence_visee,
      duration_minutes: duration
    }

    LessonPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def update_lesson_plan(%LessonPlan{} = lp, attrs),
    do: lp |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)
```

- [ ] **Step 4: Run the test**

Run: `mix test test/teacher_assistant/academics/lesson_plan_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/lesson_plan_test.exs
git commit -m "feat(academics): lesson-plan ownership resolution, create-from-entry, autosave update"
```

---

### Task 3: Context API — steps CRUD, ordering, owned-step fetch

**Files:**
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/lesson_step_test.exs`

**Interfaces:**
- Consumes: `LessonStep`, `LessonPlan`, `ensure_lesson_plan/2` from Task 2.
- Produces:
  - `list_lesson_steps(%LessonPlan{}) :: [%LessonStep{}]` (ordered by `position`)
  - `add_lesson_step(%LessonPlan{}, attrs \\ %{}) :: {:ok, %LessonStep{}}` (appends at max position + 1)
  - `update_lesson_step(%LessonStep{}, attrs) :: {:ok, %LessonStep{}}`
  - `delete_lesson_step(%LessonStep{}) :: :ok | {:error, term}`
  - `move_lesson_step(%LessonStep{}, :up | :down) :: {:ok, %LessonStep{}}` (no-op at the ends)
  - `fetch_owned_lesson_step(id, %LessonPlan{}) :: {:ok, %LessonStep{}} | {:error, :not_found}`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/lesson_step_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.LessonStepTest do
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

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    %{ws: ws, lp: lp}
  end

  test "add appends steps in order", %{lp: lp} do
    {:ok, s1} = Academics.add_lesson_step(lp, %{etape: "Découverte"})
    {:ok, s2} = Academics.add_lesson_step(lp, %{etape: "Analyse"})

    assert s1.position == 1
    assert s2.position == 2
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["Découverte", "Analyse"]
  end

  test "move down then up swaps order and no-ops at the ends", %{lp: lp} do
    {:ok, s1} = Academics.add_lesson_step(lp, %{etape: "A"})
    {:ok, s2} = Academics.add_lesson_step(lp, %{etape: "B"})

    {:ok, _} = Academics.move_lesson_step(s1, :down)
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["B", "A"]

    # s2 is now first; moving it up is a no-op-free swap back
    [first, _second] = Academics.list_lesson_steps(lp)
    {:ok, _} = Academics.move_lesson_step(first, :up)
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["B", "A"]

    _ = s2
  end

  test "update and delete a step", %{lp: lp} do
    {:ok, s} = Academics.add_lesson_step(lp, %{etape: "X"})
    {:ok, s} = Academics.update_lesson_step(s, %{contenus: "les nombres"})
    assert s.contenus == "les nombres"

    :ok = Academics.delete_lesson_step(s)
    assert Academics.list_lesson_steps(lp) == []
  end

  test "fetch_owned_lesson_step rejects a step from another plan", %{lp: lp, ws: ws} do
    {:ok, s} = Academics.add_lesson_step(lp, %{etape: "X"})

    {:ok, year} = {:ok, Academics.current_academic_year(ws)}

    {:ok, ctx2} =
      Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 2
      })

    {:ok, plan2} = Academics.create_progression_plan(ctx2, %{title: "P2"})

    {:ok, entry2} =
      Academics.add_progression_entry(plan2, %{
        module: "M",
        lesson_title: "L",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, other_lp} = Academics.ensure_lesson_plan(entry2, ctx2)

    assert {:error, :not_found} = Academics.fetch_owned_lesson_step(s.id, other_lp)
    assert {:ok, _} = Academics.fetch_owned_lesson_step(s.id, lp)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/academics/lesson_step_test.exs`
Expected: FAIL (`add_lesson_step/2` undefined).

- [ ] **Step 3: Implement**

In `lib/teacher_assistant/academics.ex`, add after `update_lesson_plan/2` (from Task 2):

```elixir
  def list_lesson_steps(%LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.filter(lesson_plan_id == ^lp_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def add_lesson_step(%LessonPlan{} = lp, attrs \\ %{}) do
    next =
      lp
      |> list_lesson_steps()
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    attrs =
      attrs
      |> Map.put(:lesson_plan_id, lp.id)
      |> Map.put_new(:position, next)

    LessonStep |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def update_lesson_step(%LessonStep{} = s, attrs),
    do: s |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_lesson_step(%LessonStep{} = s), do: Ash.destroy(s, authorize?: false)

  def move_lesson_step(%LessonStep{} = step, direction) when direction in [:up, :down] do
    steps =
      LessonStep
      |> Ash.Query.filter(lesson_plan_id == ^step.lesson_plan_id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    idx = Enum.find_index(steps, &(&1.id == step.id))
    swap_idx = if direction == :up, do: idx && idx - 1, else: idx && idx + 1

    cond do
      is_nil(idx) ->
        {:ok, step}

      swap_idx < 0 or swap_idx >= length(steps) ->
        {:ok, step}

      true ->
        other = Enum.at(steps, swap_idx)
        {:ok, _} = update_lesson_step(other, %{position: step.position})
        update_lesson_step(step, %{position: other.position})
    end
  end

  def fetch_owned_lesson_step(id, %LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.filter(id == ^id and lesson_plan_id == ^lp_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end
```

- [ ] **Step 4: Run the test**

Run: `mix test test/teacher_assistant/academics/lesson_step_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics.ex test/teacher_assistant/academics/lesson_step_test.exs
git commit -m "feat(academics): lesson-step CRUD, position ordering, owned-step fetch"
```

---

### Task 4: Editor LiveView — header autosave + cartouche + route

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`
- Test: `test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`

**Interfaces:**
- Consumes: `fetch_owned_entry_with_context/2`, `ensure_lesson_plan/2`, `update_lesson_plan/2`, `list_lesson_steps/1`.
- Produces: route `~p"/teacher/entries/:entry_id/fiche"`; assigns `@ctx_bundle`, `@lesson_plan`, `@steps`, `@saved_at`; event `"save_header"`.

- [ ] **Step 1: Add the route**

In `lib/teacher_assistant_web/router.ex`, inside the `ash_authentication_live_session :teacher_workspace` block (after the marks/summary lines, ~line 72):

```elixir
      live "/teacher/entries/:entry_id/fiche", Teacher.LessonPlanLive, :edit
```

- [ ] **Step 2: Write the failing test**

`test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Teacher.LessonPlanLiveTest do
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
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson,
        competence_visee: "Résoudre un problème"
      })

    %{ws: ws, entry: entry}
  end

  test "renders the cartouche and prefilled header", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    assert has_element?(view, "#lesson-plan")
    # derived cartouche
    assert render(view) =~ "Maths"
    assert render(view) =~ "6e A" or render(view) =~ "6ème"
    # prefilled header field
    assert has_element?(view, "#fiche-header-form input[name='lesson_plan[titre]'][value='Les entiers']")
  end

  test "autosaves a header field on blur", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    view
    |> element("#fiche-header-form")
    |> render_blur(%{"_target" => ["lesson_plan", "situation_probleme"], "lesson_plan" => %{"situation_probleme" => "Au marché"}})

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    assert lp.situation_probleme == "Au marché"
    assert has_element?(view, "#fiche-saved-indicator")
  end

  test "unknown entry redirects to /teacher", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher"}}} =
             live(conn, ~p"/teacher/entries/#{Ecto.UUID.generate()}/fiche")
  end
end
```

- [ ] **Step 3: Implement the LiveView (header only; steps section added in Task 5)**

`lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Teacher.LessonPlanLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"entry_id" => entry_id}, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace

    case ws && Academics.fetch_owned_entry_with_context(entry_id, ws) do
      {:ok, bundle} ->
        {:ok, lesson_plan} = Academics.ensure_lesson_plan(bundle.entry, bundle.ctx)

        {:ok,
         socket
         |> assign(:ctx_bundle, bundle)
         |> assign(:lesson_plan, lesson_plan)
         |> assign(:steps, Academics.list_lesson_steps(lesson_plan))
         |> assign(:saved_at, nil)
         |> assign(:header_form, header_form(lesson_plan))}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  defp header_form(lesson_plan) do
    to_form(%{
      "titre" => lesson_plan.titre,
      "duration_minutes" => lesson_plan.duration_minutes,
      "lesson_date" => lesson_plan.lesson_date,
      "competence_attendue" => lesson_plan.competence_attendue,
      "situation_probleme" => lesson_plan.situation_probleme,
      "objectifs" => lesson_plan.objectifs,
      "supports" => lesson_plan.supports,
      "prerequis" => lesson_plan.prerequis
    }, as: :lesson_plan)
  end

  def handle_event("save_header", %{"lesson_plan" => params}, socket) do
    {:ok, lesson_plan} = Academics.update_lesson_plan(socket.assigns.lesson_plan, params)

    {:noreply,
     socket
     |> assign(:lesson_plan, lesson_plan)
     |> assign(:header_form, header_form(lesson_plan))
     |> assign(:saved_at, DateTime.utc_now())}
  end

  defp fmt_min(nil), do: "—"
  defp fmt_min(n), do: "#{n}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="lesson-plan" class="mx-auto max-w-3xl space-y-5">
        <.page_header
          eyebrow={gettext("Fiche de préparation")}
          title={@lesson_plan.titre || @ctx_bundle.entry.lesson_title}
        >
          <:actions>
            <.link
              id="fiche-print-link"
              href={~p"/teacher/entries/#{@ctx_bundle.entry.id}/fiche/print"}
              target="_blank"
              class="btn btn-outline btn-sm gap-2"
            >
              <.icon name="hero-printer" class="size-4" />
              {gettext("Print / Save as PDF")}
            </.link>
          </:actions>
        </.page_header>

        <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm text-base-content/70">
          <span><span class="ta-eyebrow">{gettext("Discipline")}</span> {@ctx_bundle.ctx.subject}</span>
          <span><span class="ta-eyebrow">{gettext("Classe")}</span> {@ctx_bundle.ctx.level}</span>
          <span class="ta-num">
            <span class="ta-eyebrow">{gettext("Effectif")}</span> {@ctx_bundle.effectif}
          </span>
          <span><span class="ta-eyebrow">{gettext("Module")}</span> {@ctx_bundle.entry.module}</span>
          <span :if={@ctx_bundle.entry.famille_de_situations}>
            <span class="ta-eyebrow">{gettext("Famille de situations")}</span>
            {@ctx_bundle.entry.famille_de_situations}
          </span>
        </div>

        <p id="fiche-saved-indicator" class="text-xs text-base-content/50">
          <span :if={@saved_at}>
            <.icon name="hero-check-circle" class="inline size-3.5 text-success" />
            {gettext("Saved")}
          </span>
          <span :if={is_nil(@saved_at)}>{gettext("Autosaves as you type")}</span>
        </p>

        <.form
          for={@header_form}
          id="fiche-header-form"
          phx-blur="save_header"
          phx-change="save_header"
          class="ta-leaf space-y-3"
        >
          <div class="grid gap-3 sm:grid-cols-2">
            <.input field={@header_form[:titre]} label={gettext("Titre de la leçon")} />
            <.input
              type="number"
              field={@header_form[:duration_minutes]}
              label={gettext("Durée (min)")}
              inputmode="numeric"
            />
          </div>
          <.input type="date" field={@header_form[:lesson_date]} label={gettext("Date")} />
          <.input
            type="textarea"
            field={@header_form[:competence_attendue]}
            label={gettext("Compétence attendue")}
          />
          <.input
            type="textarea"
            field={@header_form[:situation_probleme]}
            label={gettext("Situation problème")}
          />
          <.input type="textarea" field={@header_form[:objectifs]} label={gettext("Objectifs")} />
          <.input type="textarea" field={@header_form[:supports]} label={gettext("Supports")} />
          <.input type="textarea" field={@header_form[:prerequis]} label={gettext("Prérequis")} />
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

Note: `phx-blur` is set on the form so blurring any field saves the whole header map; `phx-change` also bound so `type="date"`/`select` changes persist immediately (blur alone doesn't fire on some controls). `fmt_min/1` is used by the steps section in Task 5 — it is defined here so the module compiles; if the linter flags it as unused at this step, add a temporary `@doc false` or move it to Task 5. (It IS consumed in Task 5.)

- [ ] **Step 4: Run the test**

Run: `mix test test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`
Expected: PASS (3 tests). If `fmt_min/1` triggers an unused-warning under `--warning-as-errors` in the plain `mix test`, that only bites at `mix precommit`; Task 5 consumes it. To keep this task's commit `precommit`-clean, prefix with `_` is NOT possible (it's a real def) — instead inline `fmt_min` usage is added in Task 5; for THIS commit, delete the `fmt_min/1` defs and re-add them in Task 5 (they are only referenced there).

Correction to avoid the warning: do NOT include `fmt_min/1` in this task. Remove both `defp fmt_min` lines from Step 3 above before committing Task 4; they are introduced in Task 5 where they are used.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs
git commit -m "feat(fiche-prep): lesson-plan editor — cartouche + autosave header + route"
```

---

### Task 5: Editor steps section — table/cards, add/edit/reorder/delete, duration check

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`

**Interfaces:**
- Consumes: `add_lesson_step/2`, `update_lesson_step/2`, `delete_lesson_step/2`, `move_lesson_step/2`, `fetch_owned_lesson_step/2`, `list_lesson_steps/1`.
- Produces: events `"add_step"`, `"save_step"`, `"move_step"`, `"delete_step"`; DOM ids `#lesson-steps`, `#step-row-<id>`, `#step-add`, `#step-delete-<id>`, `#step-up-<id>`, `#step-down-<id>`, `#fiche-duration-check`.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`:

```elixir
  test "adds, edits, reorders and deletes steps", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")

    # empty state first
    assert render(view) =~ "Aucune étape"

    view |> element("#step-add") |> render_click()
    view |> element("#step-add") |> render_click()

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    [s1, s2] = Academics.list_lesson_steps(lp)

    # edit step 1's étape via blur
    view
    |> element("#step-row-#{s1.id} form")
    |> render_blur(%{"_target" => ["step", "etape"], "step" => %{"etape" => "Découverte"}})

    assert Academics.list_lesson_steps(lp) |> List.first() |> Map.get(:etape) == "Découverte"

    # move step 1 down
    view |> element("#step-down-#{s1.id}") |> render_click()
    assert Academics.list_lesson_steps(lp) |> Enum.map(& &1.id) == [s2.id, s1.id]

    # delete step 2 (now first)
    view |> element("#step-delete-#{s2.id}") |> render_click()
    assert Academics.list_lesson_steps(lp) |> Enum.map(& &1.id) == [s1.id]
  end

  test "shows the running-duration check", %{conn: conn, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/entries/#{entry.id}/fiche")
    view |> element("#step-add") |> render_click()

    lp = Academics.get_lesson_plan_for_entry(entry.id)
    [s1] = Academics.list_lesson_steps(lp)

    view
    |> element("#step-row-#{s1.id} form")
    |> render_blur(%{"_target" => ["step", "duration_minutes"], "step" => %{"duration_minutes" => "20"}})

    assert render(element(view, "#fiche-duration-check")) =~ "20"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`
Expected: the 2 new tests FAIL (no `#step-add`).

- [ ] **Step 3: Implement**

In `lesson_plan_live.ex`, add the `fmt_min/1` helpers back (removed at the end of Task 4) and a step-total helper, above `render/1`:

```elixir
  defp fmt_min(nil), do: "—"
  defp fmt_min(n), do: "#{n}"

  defp steps_total(steps) do
    Enum.reduce(steps, 0, fn s, acc -> acc + (s.duration_minutes || 0) end)
  end

  defp step_form(step) do
    to_form(%{
      "etape" => step.etape,
      "duration_minutes" => step.duration_minutes,
      "contenus" => step.contenus,
      "supports" => step.supports,
      "activites" => step.activites
    }, as: :step)
  end
```

Add the event handlers (after `handle_event("save_header", ...)`):

```elixir
  def handle_event("add_step", _params, socket) do
    {:ok, _} = Academics.add_lesson_step(socket.assigns.lesson_plan)
    {:noreply, reload_steps(socket)}
  end

  def handle_event("save_step", %{"id" => id, "step" => params}, socket) do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan),
         {:ok, _} <- Academics.update_lesson_step(step, params) do
      {:noreply, socket |> reload_steps() |> assign(:saved_at, DateTime.utc_now())}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("move_step", %{"id" => id, "dir" => dir}, socket)
      when dir in ["up", "down"] do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan) do
      {:ok, _} = Academics.move_lesson_step(step, String.to_existing_atom(dir))
      {:noreply, reload_steps(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    with {:ok, step} <- Academics.fetch_owned_lesson_step(id, socket.assigns.lesson_plan) do
      :ok = Academics.delete_lesson_step(step)
      {:noreply, reload_steps(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp reload_steps(socket) do
    assign(socket, :steps, Academics.list_lesson_steps(socket.assigns.lesson_plan))
  end
```

Insert the déroulement block into `render/1`, right before the closing `</section>`:

```heex
        <div class="space-y-3">
          <div class="flex items-center justify-between gap-2">
            <h2 class="ta-eyebrow">{gettext("Déroulement")}</h2>
            <p id="fiche-duration-check" class="ta-num text-xs text-base-content/60">
              {steps_total(@steps)} / {fmt_min(@lesson_plan.duration_minutes)} {gettext("min")}
            </p>
          </div>

          <table :if={@steps != []} id="lesson-steps" class="w-full border-separate border-spacing-y-1">
            <caption class="sr-only">{gettext("Lesson steps")}</caption>
            <thead class="hidden md:table-header-group">
              <tr class="text-left">
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Étape")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Durée")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Contenus")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Supports")}</th>
                <th scope="col" class="ta-eyebrow px-2 pb-1">{gettext("Activités")}</th>
                <th scope="col" class="px-2 pb-1"><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody class="block space-y-2 md:table-row-group">
              <tr :for={s <- @steps} id={"step-row-#{s.id}"} class="ta-leaf block md:table-row align-top">
                <td class="block md:table-cell md:px-2 md:py-1" colspan="6">
                  <.form
                    for={step_form(s)}
                    phx-blur="save_step"
                    phx-change="save_step"
                    phx-value-id={s.id}
                    class="grid gap-2 md:grid-cols-[8rem_5rem_1fr_1fr_1fr_auto] md:items-start"
                  >
                    <.input field={step_form(s)[:etape]} placeholder={gettext("Étape")} />
                    <.input
                      type="number"
                      field={step_form(s)[:duration_minutes]}
                      placeholder={gettext("min")}
                      inputmode="numeric"
                    />
                    <.input type="textarea" field={step_form(s)[:contenus]} placeholder={gettext("Contenus")} />
                    <.input type="textarea" field={step_form(s)[:supports]} placeholder={gettext("Supports")} />
                    <.input type="textarea" field={step_form(s)[:activites]} placeholder={gettext("Activités")} />
                    <div class="flex items-center gap-1">
                      <button
                        type="button"
                        id={"step-up-#{s.id}"}
                        phx-click="move_step"
                        phx-value-id={s.id}
                        phx-value-dir="up"
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-chevron-up" class="size-4" />
                        <span class="sr-only">{gettext("Move up")}</span>
                      </button>
                      <button
                        type="button"
                        id={"step-down-#{s.id}"}
                        phx-click="move_step"
                        phx-value-id={s.id}
                        phx-value-dir="down"
                        class="btn btn-ghost btn-xs"
                      >
                        <.icon name="hero-chevron-down" class="size-4" />
                        <span class="sr-only">{gettext("Move down")}</span>
                      </button>
                      <button
                        type="button"
                        id={"step-delete-#{s.id}"}
                        phx-click="delete_step"
                        phx-value-id={s.id}
                        data-confirm={gettext("Delete this step?")}
                        class="btn btn-ghost btn-xs text-error"
                      >
                        <.icon name="hero-trash" class="size-4" />
                        <span class="sr-only">{gettext("Delete")}</span>
                      </button>
                    </div>
                  </.form>
                </td>
              </tr>
            </tbody>
          </table>

          <.empty_state
            :if={@steps == []}
            icon="hero-list-bullet"
            title={gettext("Aucune étape — ajoutez la première phase.")}
          />

          <button id="step-add" type="button" phx-click="add_step" class="btn btn-outline btn-sm gap-2">
            <.icon name="hero-plus" class="size-4" />
            {gettext("Add step")}
          </button>
        </div>
```

Note: `save_step` receives `id` via `phx-value-id` on the form plus the `step` param map. Blurring any field submits the whole step map — one changed field, the rest re-sent from their current inputs.

- [ ] **Step 4: Run the test**

Run: `mix test test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/lesson_plan_live.ex test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs
git commit -m "feat(fiche-prep): déroulement steps — add/edit/reorder/delete, duration check, empty state"
```

---

### Task 6: Print route (controller + print layout + CSS)

**Files:**
- Create: `lib/teacher_assistant_web/controllers/fiche_print_controller.ex`
- Create: `lib/teacher_assistant_web/controllers/fiche_print_html.ex`
- Create: `lib/teacher_assistant_web/controllers/fiche_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex`
- Test: `test/teacher_assistant_web/controllers/fiche_print_controller_test.exs`

**Interfaces:**
- Consumes: `fetch_owned_entry_with_context/2`, `ensure_lesson_plan/2`, `list_lesson_steps/1`; `TeacherAssistant.Accounts.Workspaces.scope_for/3`.
- Produces: route `GET ~p"/teacher/entries/:entry_id/fiche/print"`.

- [ ] **Step 1: Add the route**

In `lib/teacher_assistant_web/router.ex`, in the FIRST `scope "/", TeacherAssistantWeb do pipe_through :browser` block (with the other `get` routes, after the `get "/teacher/select-context/:id"` line ~31):

```elixir
    get "/teacher/entries/:entry_id/fiche/print", FichePrintController, :show
```

- [ ] **Step 2: Write the failing test**

`test/teacher_assistant_web/controllers/fiche_print_controller_test.exs`:

```elixir
defmodule TeacherAssistantWeb.FichePrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
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
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    {:ok, _} = Academics.add_lesson_step(lp, %{etape: "Découverte", contenus: "les nombres"})
    %{entry: entry}
  end

  test "renders the printable fiche with header and steps", %{conn: conn, entry: entry} do
    conn = get(conn, ~p"/teacher/entries/#{entry.id}/fiche/print")
    html = html_response(conn, 200)

    assert html =~ "Les entiers"
    assert html =~ "Découverte"
    assert html =~ "les nombres"
    # print layout: no app nav
    refute html =~ ~s(id="main-nav")
  end

  test "a foreign entry redirects to /teacher", %{conn: conn} do
    conn = get(conn, ~p"/teacher/entries/#{Ecto.UUID.generate()}/fiche/print")
    assert redirected_to(conn) == "/teacher"
  end
end
```

- [ ] **Step 3: Implement the controller**

`lib/teacher_assistant_web/controllers/fiche_print_controller.ex`:

```elixir
defmodule TeacherAssistantWeb.FichePrintController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Workspaces

  def show(conn, %{"entry_id" => entry_id}) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         ws when not is_nil(ws) <- scope.current_workspace,
         {:ok, bundle} <- Academics.fetch_owned_entry_with_context(entry_id, ws) do
      {:ok, lesson_plan} = Academics.ensure_lesson_plan(bundle.entry, bundle.ctx)
      steps = Academics.list_lesson_steps(lesson_plan)

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show, bundle: bundle, lesson_plan: lesson_plan, steps: steps)
    else
      _ -> redirect(conn, to: ~p"/teacher")
    end
  end
end
```

Note: `put_layout(false)` + `put_root_layout(false)` bypass `Layouts.app` and the root layout entirely — the print template is a standalone HTML document (its own `<html>`), so no app nav renders.

- [ ] **Step 4: Implement the HTML module + template**

`lib/teacher_assistant_web/controllers/fiche_print_html.ex`:

```elixir
defmodule TeacherAssistantWeb.FichePrintHTML do
  use TeacherAssistantWeb, :html

  embed_templates "fiche_print_html/*"
end
```

`lib/teacher_assistant_web/controllers/fiche_print_html/show.html.heex`:

```heex
<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{gettext("Fiche de préparation")} — {@lesson_plan.titre || @bundle.entry.lesson_title}</title>
    <style>
      * { box-sizing: border-box; }
      body {
        font-family: Georgia, "Times New Roman", serif;
        color: #111; background: #fff; margin: 0; padding: 24px;
        font-size: 12pt; line-height: 1.4;
      }
      h1 { font-size: 16pt; margin: 0 0 4px; }
      .cartouche { width: 100%; border-collapse: collapse; margin: 12px 0 16px; }
      .cartouche td { border: 1px solid #999; padding: 4px 8px; vertical-align: top; }
      .cartouche .k { font-variant: small-caps; color: #444; width: 22%; }
      .block { margin: 8px 0; }
      .block .k { font-variant: small-caps; color: #444; display: block; font-size: 10pt; }
      table.body { width: 100%; border-collapse: collapse; margin-top: 8px; }
      table.body th, table.body td { border: 1px solid #999; padding: 6px 8px; text-align: left; vertical-align: top; }
      table.body th { background: #f0f0f0; font-variant: small-caps; }
      @page { size: A4; margin: 15mm; }
      @media print {
        body { padding: 0; }
        thead { display: table-header-group; }
        tr { break-inside: avoid; }
      }
    </style>
  </head>
  <body>
    <h1>{gettext("Fiche de préparation")}</h1>

    <table class="cartouche">
      <tr>
        <td class="k">{gettext("Discipline")}</td>
        <td>{@bundle.ctx.subject}</td>
        <td class="k">{gettext("Classe")}</td>
        <td>{@bundle.ctx.level}</td>
      </tr>
      <tr>
        <td class="k">{gettext("Effectif")}</td>
        <td>{@bundle.effectif}</td>
        <td class="k">{gettext("Durée (min)")}</td>
        <td>{@lesson_plan.duration_minutes}</td>
      </tr>
      <tr>
        <td class="k">{gettext("Module")}</td>
        <td>{@bundle.entry.module}</td>
        <td class="k">{gettext("Date")}</td>
        <td>{@lesson_plan.lesson_date}</td>
      </tr>
      <tr>
        <td class="k">{gettext("Titre de la leçon")}</td>
        <td colspan="3">{@lesson_plan.titre || @bundle.entry.lesson_title}</td>
      </tr>
    </table>

    <div :if={@lesson_plan.competence_attendue} class="block">
      <span class="k">{gettext("Compétence attendue")}</span>
      {@lesson_plan.competence_attendue}
    </div>
    <div :if={@lesson_plan.situation_probleme} class="block">
      <span class="k">{gettext("Situation problème")}</span>
      {@lesson_plan.situation_probleme}
    </div>
    <div :if={@lesson_plan.objectifs} class="block">
      <span class="k">{gettext("Objectifs")}</span>
      {@lesson_plan.objectifs}
    </div>
    <div :if={@lesson_plan.prerequis} class="block">
      <span class="k">{gettext("Prérequis")}</span>
      {@lesson_plan.prerequis}
    </div>
    <div :if={@lesson_plan.supports} class="block">
      <span class="k">{gettext("Supports")}</span>
      {@lesson_plan.supports}
    </div>

    <table class="body">
      <thead>
        <tr>
          <th>{gettext("Étape")}</th>
          <th>{gettext("Durée")}</th>
          <th>{gettext("Contenus")}</th>
          <th>{gettext("Supports")}</th>
          <th>{gettext("Activités")}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={s <- @steps}>
          <td>{s.etape}</td>
          <td>{s.duration_minutes}</td>
          <td>{s.contenus}</td>
          <td>{s.supports}</td>
          <td>{s.activites}</td>
        </tr>
      </tbody>
    </table>
  </body>
</html>
```

- [ ] **Step 5: Run the test**

Run: `mix test test/teacher_assistant_web/controllers/fiche_print_controller_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/controllers/fiche_print_controller.ex lib/teacher_assistant_web/controllers/fiche_print_html.ex lib/teacher_assistant_web/controllers/fiche_print_html/show.html.heex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/controllers/fiche_print_controller_test.exs
git commit -m "feat(fiche-prep): print route — A4 print layout for browser Save-as-PDF"
```

---

### Task 7: Reachability — "Préparer" action + prepared indicator on the fiche builder

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`

**Interfaces:**
- Consumes: `get_lesson_plan_for_entry/1`; route `~p"/teacher/entries/:entry_id/fiche"`.
- Produces: per-entry link `#entry-prepare-<id>` and indicator `#entry-prepared-<id>`.

- [ ] **Step 1: Write the failing test**

Append to `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`:

```elixir
  test "each entry links to its lesson plan and shows a prepared indicator", %{conn: conn, plan: plan} do
    {:ok, entry} =
      TeacherAssistant.Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    # prepare link present, not-yet-prepared (no indicator)
    assert has_element?(view, "#entry-prepare-#{entry.id}")
    refute has_element?(view, "#entry-prepared-#{entry.id}")

    # once a fiche exists, the indicator shows on reload
    {:ok, ctx} = TeacherAssistant.Academics.get_teaching_context(plan.teaching_context_id)
    {:ok, _lp} = TeacherAssistant.Academics.ensure_lesson_plan(entry, ctx)

    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")
    assert has_element?(view, "#entry-prepared-#{entry.id}")
  end
```

(If the existing `fiche_live_test.exs` setup already binds `plan`, reuse it; the test above assumes `%{plan: plan}` from setup, matching the file's other tests.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: the new test FAILS (no `#entry-prepare-<id>`).

- [ ] **Step 3: Implement**

In `fiche_live.ex`, load a prepared-lookup set in `assign_entries/2`. Replace the `assign(:entries, ...)` line so both entries and a prepared-id set are assigned:

```elixir
  defp assign_entries(socket, plan) do
    ctx =
      case Academics.get_teaching_context(plan.teaching_context_id) do
        {:ok, ctx} -> ctx
        _ -> nil
      end

    entries = Academics.list_progression_entries(plan)

    prepared =
      entries
      |> Enum.filter(fn e -> Academics.get_lesson_plan_for_entry(e.id) end)
      |> MapSet.new(& &1.id)

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:entries, entries)
    |> assign(:prepared, prepared)
    |> assign(:entry_form, to_form(%{}, as: :entry))
  end
```

(The `ctx` assignment already exists from the P2 fiche work — keep a single copy; do not duplicate.)

In `render/1`, inside the entry row (`<tr ... id={"entry-#{e.id}"}>`), add a "Préparer" link and prepared indicator. Put it in the mobile-visible lesson sub-line and the desktop actions cell — simplest is to add, in the lesson-title `<td>` (the one that also holds the mobile delete), a link:

```heex
                <.link
                  id={"entry-prepare-#{e.id}"}
                  navigate={~p"/teacher/entries/#{e.id}/fiche"}
                  class="btn btn-ghost btn-xs gap-1"
                >
                  <.icon name="hero-document-text" class="size-3.5" />
                  {gettext("Préparer")}
                  <.icon
                    :if={MapSet.member?(@prepared, e.id)}
                    name="hero-check-circle"
                    id={"entry-prepared-#{e.id}"}
                    class="size-3.5 text-success"
                  />
                </.link>
```

Place this link adjacent to the existing per-row delete control so it appears on every entry row at both breakpoints. Ensure the ids `#entry-prepare-<id>` and `#entry-prepared-<id>` are unique (one link per row).

- [ ] **Step 4: Run the test**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: PASS (all, incl. new).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/fiche_live.ex test/teacher_assistant_web/live/teacher/fiche_live_test.exs
git commit -m "feat(fiche-prep): Préparer action + prepared indicator on the progression builder"
```

---

### Task 8: Gettext extraction + FR translations + full precommit gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`

**Interfaces:**
- Consumes: every `gettext(...)` msgid added in Tasks 4–7 and the print template.

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`
Expected: new msgids appear in the `.pot` and both `.po` files.

- [ ] **Step 2: Fill the FR msgstr for the new msgids**

In `priv/gettext/fr/LC_MESSAGES/default.po`, set `msgstr` for each newly added empty entry. Use exactly:

| msgid | FR msgstr |
|---|---|
| Fiche de préparation | Fiche de préparation |
| Print / Save as PDF | Imprimer / Enregistrer en PDF |
| Discipline | Discipline |
| Classe | Classe |
| Effectif | Effectif |
| Module | Module |
| Famille de situations | Famille de situations |
| Saved | Enregistré |
| Autosaves as you type | Enregistrement automatique |
| Titre de la leçon | Titre de la leçon |
| Durée (min) | Durée (min) |
| Date | Date |
| Compétence attendue | Compétence attendue |
| Situation problème | Situation problème |
| Objectifs | Objectifs |
| Supports | Supports |
| Prérequis | Prérequis |
| Déroulement | Déroulement |
| min | min |
| Lesson steps | Étapes de la leçon |
| Étape | Étape |
| Durée | Durée |
| Contenus | Contenus |
| Activités | Activités |
| Actions | Actions |
| Move up | Monter |
| Move down | Descendre |
| Delete this step? | Supprimer cette étape ? |
| Delete | Supprimer |
| Aucune étape — ajoutez la première phase. | Aucune étape — ajoutez la première phase. |
| Add step | Ajouter une étape |
| Préparer | Préparer |

Only fill entries `gettext.extract` actually added and that are empty; never overwrite existing non-empty msgstr; skip any listed msgid that already exists translated (e.g. "Classe", "Date", "Module", "Supports", "Actions", "Delete" may already be present from earlier phases — leave them).

- [ ] **Step 3: Full gate**

Run: `mix precommit`
Expected: compile (warnings-as-errors) clean, format clean, ALL tests pass (≥141 expected: 127 prior + 14 new).

- [ ] **Step 4: Commit**

```bash
git add priv/gettext
git commit -m "chore(i18n): extract + FR translations for v1.3 fiche de préparation"
```

---

## Self-Review (done at plan time)

- **Spec coverage:** §2 model → Task 1; §3 context API → Tasks 2–3; §4 editor (cartouche/autosave/steps/duration/empty) → Tasks 4–5; §5 print route → Task 6; §6 reachability + i18n → Tasks 7–8; §7 testing folded into each task; §8 DoD satisfied by Tasks 4–6 + 8. **Deliberately deferred (spec §1 out-of-scope):** server-side PDF, DOCX, phase presets, multi-fiche, visa — no tasks, as intended.
- **Placeholder scan:** every code step shows real code; the one meta-instruction (remove/re-add `fmt_min/1` between Tasks 4–5) is explicit, not a placeholder. FR table gives exact strings.
- **Type consistency:** `fetch_owned_entry_with_context/2` returns the `%{entry, plan, ctx, class_group, year, effectif}` map used identically in Tasks 4 and 6; `ensure_lesson_plan/2` arity (entry, ctx) consistent across Tasks 2/4/6/7; `move_lesson_step/2` takes `:up|:down` and the LiveView converts the `"up"/"down"` param via `String.to_existing_atom/1`; step form field names (`etape`, `duration_minutes`, `contenus`, `supports`, `activites`) match the resource attrs and the `save_step` param map. Route path `~p"/teacher/entries/:entry_id/fiche"` consistent in Tasks 4 (live), 6 (print, `/print` suffix), 7 (link).
- **Ownership:** every web entry point (Tasks 4, 6) and every step mutation (Task 5) funnels through `fetch_owned_entry_with_context/2` or `fetch_owned_lesson_step/2` — IDOR covered by tests in Tasks 2, 3, 4, 6.
```
