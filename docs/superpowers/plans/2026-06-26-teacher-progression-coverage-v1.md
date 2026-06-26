# Teacher Progression & Coverage (v1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an independent Cameroon secondary teacher, on their phone, in FR or EN, build a *fiche de progression* per subject×class, log what they actually teach, and see their *taux de couverture du programme*.

**Architecture:** Clean-slate rebuild of the domain layer on the retained Phoenix/Ash + AshAuthentication scaffold. New `Academics` domain holds the progression/coverage resources; coverage is a derived pure-function calculation; LiveViews mirror the existing `<Layouts.app>` + `@current_scope` pattern. Bottom-up: reference data → resources → domain functions → LiveViews.

**Tech Stack:** Elixir, Phoenix 1.8, Phoenix LiveView 1.1, Ash 3.26, AshPostgres, AshAuthentication (magic link + password), Cinder, DaisyUI/Tailwind v4, Gettext.

## Global Constraints

- **Spec:** [`docs/superpowers/specs/2026-06-26-teacher-progression-coverage-v1-design.md`](../specs/2026-06-26-teacher-progression-coverage-v1-design.md). **Domain facts:** [`docs/domain/`](../../domain/README.md).
- **Clean slate:** keep only the framework + auth scaffold (User, Token, Secrets, magic-link sender, Repo, endpoint, router shell, `Layouts`, `core_components`, `Scope`, `Workspaces`, `LiveUserAuth`, `WorkspaceController`, gettext, AuthOverrides). Rebuild everything under `lib/teacher_assistant/academics/` and `lib/teacher_assistant_web/live/teacher/` fresh.
- **Bilingual FR + EN:** every user-facing string goes through `gettext(...)`; reference data carries `fr` and `en` labels. Locale lives on the `Scope`.
- **Mobile-first:** every LiveView renders usably at 360px width; prefer stacked rows over wide tables on small screens.
- **Ash conventions (mirror the scaffold):** resources use `use Ash.Resource, otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `uuid_v7_primary_key :id`; `timestamps()`; `public?: true` on public attrs/rels; permissive policy `policy always() do authorize_if always() end`; **all owner-scoping is enforced in domain functions** via `Ash.Query.filter` + `Ash.read!(authorize?: false)` (matching the existing code).
- **Migrations:** NEVER hand-write. Always `mix ash.codegen --dev` (generates migration + snapshot under `priv/resource_snapshots/repo/`).
- **Testing:** `mix test` (alias runs `ash.setup --quiet` first). LiveView tests use `setup :register_and_log_in_user` and assert against **stable DOM IDs**, never raw HTML.
- **Commits:** one per task minimum; message style `feat:` / `chore:` / `test:`. End every commit body with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Verify before done:** `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test) must pass before a task is complete.

---

## File Structure

**Domain (`lib/teacher_assistant/academics/`):**
- `academics.ex` (domain) — resource registry + code-interface functions (the only place LiveViews call).
- `reference.ex` — bilingual suggestion lists (subsystems, levels, subjects, entry types) + the 2025-26 calendar preset. Pure module.
- `personal_workspace.ex`, `academic_year.ex`, `term.ex`, `sequence.ex`, `teaching_context.ex`, `progression_plan.ex`, `progression_entry.ex`, `teaching_log_entry.ex` — Ash resources.
- `coverage.ex` — pure coverage calculator.

**Web (`lib/teacher_assistant_web/`):**
- `live/teacher/setup_live.ex`, `dashboard_live.ex`, `fiche_live.ex`, `log_live.ex`, `coverage_live.ex` — LiveViews.
- `plug/locale.ex` + `live_user_auth.ex` (modify) — locale plumbing.
- `router.ex` (modify), `components/layouts.ex` (modify nav).

**Tests mirror under `test/teacher_assistant/academics/` and `test/teacher_assistant_web/live/teacher/`.**

---

## Task 1: Clean-slate teardown + green baseline

**Files:**
- Delete: `lib/teacher_assistant/academics/` (all files), `lib/teacher_assistant_web/live/teacher/` (all files), `lib/teacher_assistant/academics.ex`
- Delete: `test/teacher_assistant/` (old), `test/teacher_assistant_web/live/teacher_mvp_live_test.exs`, `test/support/fixtures/teacher_fixtures.ex` (rebuilt later)
- Delete stale snapshots: `priv/resource_snapshots/repo/{academic_years,attendance_records,attendance_sessions,learners,lesson_plan_entries,personal_classrooms,personal_workspaces,teaching_log_entries}/`
- Modify: `lib/teacher_assistant/accounts.ex` (drop `ensure_personal_workspace!` delegation for now), `lib/teacher_assistant/accounts/workspaces.ex`, `lib/teacher_assistant/scope.ex`, `lib/teacher_assistant_web/live_user_auth.ex`, `lib/teacher_assistant_web/router.ex`, `config/config.exs` (ash_domains)
- Create: `lib/teacher_assistant/academics.ex` (empty domain), `lib/teacher_assistant_web/live/teacher/dashboard_live.ex` (placeholder)

**Interfaces:**
- Produces: empty `TeacherAssistant.Academics` domain (no resources yet); `TeacherAssistantWeb.Teacher.DashboardLive` placeholder mounted at `/teacher`; `Scope` struct unchanged (fields reused).

- [ ] **Step 1: Remove old domain & feature code**

```bash
git rm -r lib/teacher_assistant/academics lib/teacher_assistant_web/live/teacher \
  test/teacher_assistant test/teacher_assistant_web/live/teacher_mvp_live_test.exs \
  test/support/fixtures/teacher_fixtures.ex
git rm -r priv/resource_snapshots/repo/academic_years \
  priv/resource_snapshots/repo/attendance_records \
  priv/resource_snapshots/repo/attendance_sessions \
  priv/resource_snapshots/repo/learners \
  priv/resource_snapshots/repo/lesson_plan_entries \
  priv/resource_snapshots/repo/personal_classrooms \
  priv/resource_snapshots/repo/teaching_log_entries
```
(Keep `priv/resource_snapshots/repo/{users,tokens}` — auth stays.)

- [ ] **Step 2: Recreate an empty Academics domain**

Create `lib/teacher_assistant/academics.ex`:
```elixir
defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  resources do
  end
end
```

- [ ] **Step 3: Simplify the auth spine to not depend on deleted code**

`lib/teacher_assistant/accounts/workspaces.ex` — reduce to a minimal placeholder scope (rebuilt in Task 3):
```elixir
defmodule TeacherAssistant.Accounts.Workspaces do
  @moduledoc "Workspace scope resolution (rebuilt in Task 3)."
  alias TeacherAssistant.Scope

  def scope_for(user, _workspace_id) do
    {:ok, %Scope{current_user: user, current_role: :teacher, current_workspace_type: :personal_teacher}}
  end
end
```

`lib/teacher_assistant/accounts.ex` — remove the `ensure_personal_workspace!/1` function and its `alias TeacherAssistant.Academics` (re-added in Task 3). Keep `create_user/1` and `get_user/1`.

`lib/teacher_assistant/scope.ex` — remove `academic_year_ready?/1` (it references a deleted module); keep the struct, `personal_context?/1`, and the `Ash.Scope.ToOpts` impl.

`lib/teacher_assistant_web/live_user_auth.ex` — in `resolve_scope/2`, replace the body with:
```elixir
defp resolve_scope(nil, _workspace_id), do: %Scope{}
defp resolve_scope(user, workspace_id) do
  case Workspaces.scope_for(user, workspace_id) do
    {:ok, scope} -> scope
    {:error, _} -> %Scope{current_user: user}
  end
end
```
(Remove the `Workspaces.ensure_personal_workspace!` call.)

- [ ] **Step 4: Reduce the teacher routes to a single placeholder**

In `lib/teacher_assistant_web/router.ex`, replace the `ash_authentication_live_session :teacher_workspace do ... end` body with only:
```elixir
live "/teacher", Teacher.DashboardLive, :index
```

- [ ] **Step 5: Add the placeholder DashboardLive**

Create `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-dashboard" class="p-4">
        <h1 class="text-xl font-semibold">{gettext("Teacher dashboard")}</h1>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 6: Reset the dev database and verify boot**

Run:
```bash
mix ecto.drop && mix ash.setup && mix compile --warning-as-errors
```
Expected: compiles with no warnings; `ash.setup` runs the remaining (auth-only) migrations.

- [ ] **Step 7: Smoke test the placeholder route**

Create `test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`:
```elixir
defmodule TeacherAssistantWeb.Teacher.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "redirects to sign-in when logged out", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/teacher")
  end
end
```

- [ ] **Step 8: Run it**

Run: `mix test test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: clean-slate teardown of old domain; green auth baseline"
```

---

## Task 2: Reference module (bilingual lists + calendar preset)

**Files:**
- Create: `lib/teacher_assistant/academics/reference.ex`
- Test: `test/teacher_assistant/academics/reference_test.exs`

**Interfaces:**
- Produces:
  - `Reference.subsystems()` → `[%{key: :francophone | :anglophone, fr: String.t(), en: String.t()}]`
  - `Reference.levels(:francophone | :anglophone)` → `[String.t()]`
  - `Reference.subjects()` → `[%{key: atom, fr: String.t(), en: String.t()}]`
  - `Reference.entry_types()` → `[%{key: atom, fr: String.t(), en: String.t()}]`
  - `Reference.entry_type_keys()` → `[atom]`
  - `Reference.default_calendar_preset()` → `%{terms: [%{position: 1..3, sequences: [%{number: 1..6, position_in_term: 1..2, start_date: Date.t(), end_date: Date.t(), integration_week: boolean}]}]}` (the 2025-26 grid from `docs/domain/01` §6)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.ReferenceTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Reference

  test "subsystems are francophone and anglophone with bilingual labels" do
    keys = Enum.map(Reference.subsystems(), & &1.key)
    assert keys == [:francophone, :anglophone]
    assert Enum.all?(Reference.subsystems(), &(&1.fr != "" and &1.en != ""))
  end

  test "francophone levels run 6ème to Terminale" do
    assert Reference.levels(:francophone) |> List.first() == "6ème"
    assert Reference.levels(:francophone) |> List.last() == "Terminale"
  end

  test "anglophone levels run Form 1 to Upper Sixth" do
    assert Reference.levels(:anglophone) |> List.first() == "Form 1"
    assert Reference.levels(:anglophone) |> List.last() == "Upper Sixth"
  end

  test "entry types include lesson and integration" do
    assert :lesson in Reference.entry_type_keys()
    assert :integration in Reference.entry_type_keys()
  end

  test "default calendar preset has 3 terms and 6 sequences" do
    preset = Reference.default_calendar_preset()
    assert length(preset.terms) == 3
    seqs = Enum.flat_map(preset.terms, & &1.sequences)
    assert length(seqs) == 6
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/reference_test.exs`
Expected: FAIL (module undefined).

- [ ] **Step 3: Implement the module**

Create `lib/teacher_assistant/academics/reference.ex`:
```elixir
defmodule TeacherAssistant.Academics.Reference do
  @moduledoc "Bilingual suggestion lists and the default academic calendar preset (see docs/domain)."

  def subsystems do
    [
      %{key: :francophone, fr: "Francophone", en: "Francophone"},
      %{key: :anglophone, fr: "Anglophone", en: "Anglophone"}
    ]
  end

  def levels(:francophone), do: ["6ème", "5ème", "4ème", "3ème", "2nde", "1ère", "Terminale"]
  def levels(:anglophone), do: ["Form 1", "Form 2", "Form 3", "Form 4", "Form 5", "Lower Sixth", "Upper Sixth"]

  def subjects do
    [
      %{key: :maths, fr: "Mathématiques", en: "Mathematics"},
      %{key: :french, fr: "Français", en: "French"},
      %{key: :english, fr: "Anglais", en: "English"},
      %{key: :physics, fr: "Physique", en: "Physics"},
      %{key: :chemistry, fr: "Chimie", en: "Chemistry"},
      %{key: :biology, fr: "SVT", en: "Biology"},
      %{key: :history, fr: "Histoire", en: "History"},
      %{key: :geography, fr: "Géographie", en: "Geography"},
      %{key: :computer_science, fr: "Informatique", en: "Computer Science"},
      %{key: :citizenship, fr: "ECM", en: "Citizenship"},
      %{key: :pe, fr: "EPS", en: "Physical Education"}
    ]
  end

  def entry_types do
    [
      %{key: :lesson, fr: "Leçon", en: "Lesson"},
      %{key: :integration, fr: "Intégration", en: "Integration"},
      %{key: :evaluation, fr: "Évaluation", en: "Evaluation"},
      %{key: :revision, fr: "Révision", en: "Revision"},
      %{key: :correction, fr: "Correction", en: "Correction"},
      %{key: :remediation, fr: "Remédiation", en: "Remediation"},
      %{key: :holiday, fr: "Congé", en: "Holiday"}
    ]
  end

  def entry_type_keys, do: Enum.map(entry_types(), & &1.key)

  @doc "Official 2025-2026 grid (docs/domain/01 §6). Dates are editable in the wizard."
  def default_calendar_preset do
    %{
      terms: [
        %{position: 1, sequences: [
          %{number: 1, position_in_term: 1, start_date: ~D[2025-09-08], end_date: ~D[2025-10-24], integration_week: false},
          %{number: 2, position_in_term: 2, start_date: ~D[2025-10-27], end_date: ~D[2025-11-28], integration_week: true}
        ]},
        %{position: 2, sequences: [
          %{number: 3, position_in_term: 1, start_date: ~D[2025-12-01], end_date: ~D[2026-01-30], integration_week: false},
          %{number: 4, position_in_term: 2, start_date: ~D[2026-02-02], end_date: ~D[2026-03-06], integration_week: true}
        ]},
        %{position: 3, sequences: [
          %{number: 5, position_in_term: 1, start_date: ~D[2026-03-09], end_date: ~D[2026-04-30], integration_week: false},
          %{number: 6, position_in_term: 2, start_date: ~D[2026-05-04], end_date: ~D[2026-06-12], integration_week: true}
        ]}
      ]
    }
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/reference_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/reference.ex test/teacher_assistant/academics/reference_test.exs
git commit -m "feat: add bilingual reference lists and 2025-26 calendar preset"
```

---

## Task 3: PersonalWorkspace resource + scope rebuild

**Files:**
- Create: `lib/teacher_assistant/academics/personal_workspace.ex`
- Modify: `lib/teacher_assistant/academics.ex` (register resource + funcs), `lib/teacher_assistant/accounts.ex` (re-add `ensure_personal_workspace!`), `lib/teacher_assistant/accounts/workspaces.ex` (real `scope_for`), `lib/teacher_assistant/scope.ex` (re-add `academic_year_ready?`)
- Create: `test/support/fixtures/teacher_fixtures.ex`
- Test: `test/teacher_assistant/academics/workspace_test.exs`

**Interfaces:**
- Produces:
  - Resource `TeacherAssistant.Academics.PersonalWorkspace` (attrs: `name`, `owner_user_id`; identity `unique_owner_user`)
  - `Academics.ensure_personal_workspace!(%User{})` → `%PersonalWorkspace{}`
  - `Academics.get_personal_workspace(id)` → `{:ok, ws} | {:error, _}`
  - `Workspaces.scope_for(user, workspace_id | nil)` → `{:ok, %Scope{}} | {:error, :workspace_not_found}`
  - Fixtures: `TeacherAssistant.TeacherFixtures.user_fixture/1`, `workspace_fixture/1`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.WorkspaceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Academics, Accounts}
  alias TeacherAssistant.TeacherFixtures

  test "ensure_personal_workspace! is idempotent per user" do
    user = TeacherFixtures.user_fixture()
    ws1 = Academics.ensure_personal_workspace!(user)
    ws2 = Academics.ensure_personal_workspace!(user)
    assert ws1.id == ws2.id
    assert ws1.owner_user_id == user.id
  end

  test "scope_for returns a personal scope for the owner" do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)
    assert {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, ws.id)
    assert scope.current_workspace.id == ws.id
    assert scope.current_workspace_type == :personal_teacher
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/workspace_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/personal_workspace.ex`:
```elixir
defmodule TeacherAssistant.Academics.PersonalWorkspace do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "personal_workspaces"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:name, :owner_user_id], update: [:name]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :owner_user, TeacherAssistant.Accounts.User do
      source_attribute :owner_user_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_owner_user, [:owner_user_id]
  end
end
```

- [ ] **Step 4: Register + add domain functions**

Replace `lib/teacher_assistant/academics.ex`:
```elixir
defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.PersonalWorkspace

  resources do
    resource PersonalWorkspace
  end

  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, ws} -> ws
      {:error, :not_found} ->
        {:ok, ws} =
          PersonalWorkspace
          |> Ash.Changeset.for_create(:create, %{name: "Personal workspace", owner_user_id: user.id})
          |> Ash.create(authorize?: false)
        ws
    end
  end

  def personal_workspace_for_user(%User{id: user_id}) do
    PersonalWorkspace
    |> Ash.Query.filter(owner_user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def get_personal_workspace(id), do: Ash.get(PersonalWorkspace, id, authorize?: false)
end
```

- [ ] **Step 5: Restore Accounts delegation, Workspaces.scope_for, Scope helper**

`lib/teacher_assistant/accounts.ex` — re-add:
```elixir
def ensure_personal_workspace!(%TeacherAssistant.Accounts.User{} = user),
  do: TeacherAssistant.Academics.ensure_personal_workspace!(user)
```

`lib/teacher_assistant/accounts/workspaces.ex`:
```elixir
defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Academics, Scope}

  def ensure_personal_workspace!(user), do: Academics.ensure_personal_workspace!(user)

  def scope_for(user, nil) do
    ws = ensure_personal_workspace!(user)
    scope_for(user, ws.id)
  end

  def scope_for(user, workspace_id) do
    with {:ok, ws} <- Academics.get_personal_workspace(workspace_id),
         true <- ws.owner_user_id == user.id do
      {:ok, %Scope{
        current_user: user,
        current_workspace: ws,
        current_workspace_type: :personal_teacher,
        current_role: :teacher,
        current_academic_year: nil
      }}
    else
      _ -> {:error, :workspace_not_found}
    end
  end
end
```

`lib/teacher_assistant/scope.ex` — re-add:
```elixir
def academic_year_ready?(%__MODULE__{current_academic_year: %TeacherAssistant.Academics.AcademicYear{}}), do: true
def academic_year_ready?(_), do: false
```
(`current_academic_year` is wired in Task 4; until then it stays `nil` and this returns `false`.)

- [ ] **Step 6: Recreate test fixtures**

Create `test/support/fixtures/teacher_fixtures.ex`:
```elixir
defmodule TeacherAssistant.TeacherFixtures do
  alias TeacherAssistant.{Accounts, Academics}

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, "teacher-#{System.unique_integer([:positive])}@example.com")
    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        password: Map.get(attrs, :password, "password1234"),
        password_confirmation: Map.get(attrs, :password_confirmation, "password1234")
      })
    user
  end

  def workspace_fixture(user \\ user_fixture()), do: Academics.ensure_personal_workspace!(user)
end
```

- [ ] **Step 7: Generate the migration**

Run: `mix ash.codegen --dev`
Expected: creates a migration + `priv/resource_snapshots/repo/personal_workspaces/...`. Then `mix ash.setup`.

- [ ] **Step 8: Run the tests**

Run: `mix test test/teacher_assistant/academics/workspace_test.exs`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: rebuild PersonalWorkspace resource and scope resolution"
```

---

## Task 4: AcademicYear resource + domain functions

**Files:**
- Create: `lib/teacher_assistant/academics/academic_year.ex`
- Modify: `lib/teacher_assistant/academics.ex`, `lib/teacher_assistant/accounts/workspaces.ex` (set `current_academic_year`)
- Test: `test/teacher_assistant/academics/academic_year_test.exs`

**Interfaces:**
- Produces:
  - Resource `AcademicYear` (attrs: `name`, `start_date`, `end_date`, `active`, `personal_workspace_id`; identity `unique_workspace_year` on `[:personal_workspace_id, :name]`)
  - `Academics.create_academic_year(%PersonalWorkspace{}, attrs)` → `{:ok, %AcademicYear{}} | {:error, _}` (deactivates other years when `active`)
  - `Academics.list_academic_years(%PersonalWorkspace{})` → `[%AcademicYear{}]` (sorted start_date desc)
  - `Academics.current_academic_year(%PersonalWorkspace{})` → `%AcademicYear{} | nil`
  - `Academics.get_academic_year(id)` → `{:ok, _} | {:error, _}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.AcademicYearTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    %{ws: ws}
  end

  test "create + current academic year", %{ws: ws} do
    assert {:ok, year} =
             Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    assert year.active
    assert Academics.current_academic_year(ws).id == year.id
  end

  test "creating a second active year deactivates the first", %{ws: ws} do
    {:ok, y1} = Academics.create_academic_year(ws, %{name: "2024-2025", start_date: ~D[2024-09-01], end_date: ~D[2025-07-31], active: true})
    {:ok, _y2} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, y1_reloaded} = Academics.get_academic_year(y1.id)
    refute y1_reloaded.active
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/academic_year_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/academic_year.ex`:
```elixir
defmodule TeacherAssistant.Academics.AcademicYear do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "academic_years"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :start_date, :end_date, :active, :personal_workspace_id],
      update: [:name, :start_date, :end_date, :active]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    has_many :terms, TeacherAssistant.Academics.Term
  end

  identities do
    identity :unique_workspace_year, [:personal_workspace_id, :name]
  end
end
```
(Note: `has_many :terms` references the Task 5 resource — define it before running `ash.codegen` here, OR add the relationship in Task 5. To keep this task self-contained, **omit `has_many :terms` now** and add it in Task 5.)

- [ ] **Step 4: Register + domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.AcademicYear`, `resource AcademicYear`, and:
```elixir
def create_academic_year(%PersonalWorkspace{} = ws, attrs) do
  attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put_new(:active, true)

  with {:ok, year} <- AcademicYear |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false) do
    if year.active, do: deactivate_other_years(ws, year.id)
    {:ok, year}
  end
end

def list_academic_years(%PersonalWorkspace{id: id}) do
  AcademicYear
  |> Ash.Query.filter(personal_workspace_id == ^id)
  |> Ash.Query.sort(start_date: :desc)
  |> Ash.read!(authorize?: false)
end

def current_academic_year(%PersonalWorkspace{id: id}) do
  AcademicYear
  |> Ash.Query.filter(personal_workspace_id == ^id and active == true)
  |> Ash.Query.sort(start_date: :desc)
  |> Ash.read!(authorize?: false)
  |> List.first()
end

def get_academic_year(id), do: Ash.get(AcademicYear, id, authorize?: false)

defp deactivate_other_years(%PersonalWorkspace{id: ws_id}, keep_id) do
  AcademicYear
  |> Ash.Query.filter(personal_workspace_id == ^ws_id and id != ^keep_id and active == true)
  |> Ash.read!(authorize?: false)
  |> Enum.each(fn y -> y |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update!(authorize?: false) end)
end
```

- [ ] **Step 5: Wire current year into the scope**

In `lib/teacher_assistant/accounts/workspaces.ex`, set `current_academic_year: Academics.current_academic_year(ws)` in `scope_for/2`.

- [ ] **Step 6: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 7: Run tests**

Run: `mix test test/teacher_assistant/academics/academic_year_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add AcademicYear resource with active-year management"
```

---

## Task 5: Term + Sequence resources + default-calendar builder

**Files:**
- Create: `lib/teacher_assistant/academics/term.ex`, `lib/teacher_assistant/academics/sequence.ex`
- Modify: `lib/teacher_assistant/academics.ex` (register + builder), `lib/teacher_assistant/academics/academic_year.ex` (add `has_many :terms`)
- Test: `test/teacher_assistant/academics/calendar_test.exs`

**Interfaces:**
- Produces:
  - Resource `Term` (attrs: `position`, `academic_year_id`; `has_many :sequences`)
  - Resource `Sequence` (attrs: `number` 1..6, `position_in_term` 1..2, `start_date`, `end_date`, `integration_week`, `term_id`)
  - `Academics.build_default_calendar(%AcademicYear{})` → `:ok` (creates 3 terms + 6 sequences from `Reference.default_calendar_preset/0`)
  - `Academics.list_sequences(%AcademicYear{})` → `[%Sequence{}]` (ordered by `number`, term preloaded)
  - `Academics.current_sequence(%AcademicYear{}, Date.t())` → `%Sequence{} | nil`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.CalendarTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    %{year: year}
  end

  test "build_default_calendar creates 3 terms and 6 sequences", %{year: year} do
    assert :ok = Academics.build_default_calendar(year)
    seqs = Academics.list_sequences(year)
    assert length(seqs) == 6
    assert Enum.map(seqs, & &1.number) == [1, 2, 3, 4, 5, 6]
  end

  test "current_sequence finds the sequence covering a date", %{year: year} do
    :ok = Academics.build_default_calendar(year)
    seq = Academics.current_sequence(year, ~D[2025-09-20])
    assert seq.number == 1
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/calendar_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create Term resource**

Create `lib/teacher_assistant/academics/term.ex`:
```elixir
defmodule TeacherAssistant.Academics.Term do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "terms"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:position, :academic_year_id], update: [:position]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :position, :integer, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    has_many :sequences, TeacherAssistant.Academics.Sequence
  end

  identities do
    identity :unique_year_term, [:academic_year_id, :position]
  end
end
```

- [ ] **Step 4: Create Sequence resource**

Create `lib/teacher_assistant/academics/sequence.ex`:
```elixir
defmodule TeacherAssistant.Academics.Sequence do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sequences"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:number, :position_in_term, :start_date, :end_date, :integration_week, :term_id],
      update: [:number, :position_in_term, :start_date, :end_date, :integration_week]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :number, :integer, allow_nil?: false, public?: true
    attribute :position_in_term, :integer, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :integration_week, :boolean, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 5: Add `has_many :terms` to AcademicYear**

In `lib/teacher_assistant/academics/academic_year.ex`, add inside `relationships do`:
```elixir
has_many :terms, TeacherAssistant.Academics.Term
```

- [ ] **Step 6: Register + builder + query functions**

In `lib/teacher_assistant/academics.ex` add aliases for `Term`, `Sequence`, `AcademicYear`, register both resources, and:
```elixir
def build_default_calendar(%AcademicYear{} = year) do
  preset = TeacherAssistant.Academics.Reference.default_calendar_preset()

  Enum.each(preset.terms, fn term_spec ->
    {:ok, term} =
      Term
      |> Ash.Changeset.for_create(:create, %{position: term_spec.position, academic_year_id: year.id})
      |> Ash.create(authorize?: false)

    Enum.each(term_spec.sequences, fn s ->
      Sequence
      |> Ash.Changeset.for_create(:create, Map.put(Map.take(s, [:number, :position_in_term, :start_date, :end_date, :integration_week]), :term_id, term.id))
      |> Ash.create!(authorize?: false)
    end)
  end)

  :ok
end

def list_sequences(%AcademicYear{id: year_id}) do
  Sequence
  |> Ash.Query.filter(term.academic_year_id == ^year_id)
  |> Ash.Query.load(:term)
  |> Ash.Query.sort(number: :asc)
  |> Ash.read!(authorize?: false)
end

def current_sequence(%AcademicYear{} = year, %Date{} = date) do
  year
  |> list_sequences()
  |> Enum.find(fn s -> Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt end)
end
```

- [ ] **Step 7: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 8: Run tests**

Run: `mix test test/teacher_assistant/academics/calendar_test.exs`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add Term/Sequence resources and default-calendar builder"
```

---

## Task 6: TeachingContext resource + domain functions

**Files:**
- Create: `lib/teacher_assistant/academics/teaching_context.ex`
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/teaching_context_test.exs`

**Interfaces:**
- Produces:
  - Resource `TeachingContext` (attrs: `subject`, `level`, `serie` (nullable), `subsystem` (atom: `:francophone | :anglophone`), `weekly_hours` (integer), `personal_workspace_id`, `academic_year_id`; identity `unique_context` on `[:personal_workspace_id, :academic_year_id, :subject, :level, :serie]`)
  - `Academics.create_teaching_context(%PersonalWorkspace{}, %AcademicYear{}, attrs)` → `{:ok, _} | {:error, _}`
  - `Academics.list_teaching_contexts(%PersonalWorkspace{}, %AcademicYear{})` → `[%TeachingContext{}]`
  - `Academics.get_teaching_context(id)` → `{:ok, _} | {:error, _}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.TeachingContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    %{ws: ws, year: year}
  end

  test "create and list a teaching context", %{ws: ws, year: year} do
    assert {:ok, ctx} =
             Academics.create_teaching_context(ws, year, %{subject: "Mathematics", level: "Form 1", subsystem: :anglophone, weekly_hours: 4})
    assert ctx.subject == "Mathematics"
    assert [listed] = Academics.list_teaching_contexts(ws, year)
    assert listed.id == ctx.id
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/teaching_context_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/teaching_context.ex`:
```elixir
defmodule TeacherAssistant.Academics.TeachingContext do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_contexts"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:subject, :level, :serie, :subsystem, :weekly_hours, :personal_workspace_id, :academic_year_id],
      update: [:subject, :level, :serie, :subsystem, :weekly_hours]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true
    attribute :subsystem, :atom, constraints: [one_of: [:francophone, :anglophone]], allow_nil?: false, public?: true
    attribute :weekly_hours, :integer, default: 4, public?: true
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
  end

  identities do
    identity :unique_context, [:personal_workspace_id, :academic_year_id, :subject, :level, :serie]
  end
end
```

- [ ] **Step 4: Register + domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.TeachingContext`, `resource TeachingContext`, and:
```elixir
def create_teaching_context(%PersonalWorkspace{} = ws, %AcademicYear{} = year, attrs) do
  attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put(:academic_year_id, year.id)
  TeachingContext |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
end

def list_teaching_contexts(%PersonalWorkspace{id: ws_id}, %AcademicYear{id: year_id}) do
  TeachingContext
  |> Ash.Query.filter(personal_workspace_id == ^ws_id and academic_year_id == ^year_id)
  |> Ash.Query.sort(subject: :asc)
  |> Ash.read!(authorize?: false)
end

def get_teaching_context(id), do: Ash.get(TeachingContext, id, authorize?: false)
```

- [ ] **Step 5: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 6: Run tests**

Run: `mix test test/teacher_assistant/academics/teaching_context_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add TeachingContext resource"
```

---

## Task 7: ProgressionPlan resource (+ duplicate / template)

**Files:**
- Create: `lib/teacher_assistant/academics/progression_plan.ex`
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/progression_plan_test.exs`

**Interfaces:**
- Produces:
  - Resource `ProgressionPlan` (attrs: `title`, `status` (atom `:draft | :active`, default `:draft`), `template` (boolean, default false), `teaching_context_id`, `academic_year_id`, `personal_workspace_id`)
  - `Academics.create_progression_plan(%TeachingContext{}, attrs)` → `{:ok, _} | {:error, _}`
  - `Academics.list_progression_plans(%PersonalWorkspace{})` → `[%ProgressionPlan{}]`
  - `Academics.get_progression_plan(id)` → `{:ok, _} | {:error, _}`
  - `Academics.duplicate_progression_plan(%ProgressionPlan{}, overrides)` → `{:ok, %ProgressionPlan{}}` (copies the plan **and its entries** — entries copied in Task 8 once that resource exists; in this task, copy the plan record only and add an entry-copy line in Task 8)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.ProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    %{ws: ws, year: year, ctx: ctx}
  end

  test "create and list a progression plan", %{ws: ws, ctx: ctx} do
    assert {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème 2025-2026"})
    assert plan.status == :draft
    assert [listed] = Academics.list_progression_plans(ws)
    assert listed.id == plan.id
  end

  test "duplicate creates a new plan record", %{ctx: ctx} do
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Original"})
    {:ok, copy} = Academics.duplicate_progression_plan(plan, %{title: "Copy"})
    assert copy.id != plan.id
    assert copy.title == "Copy"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/progression_plan_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/progression_plan.ex`:
```elixir
defmodule TeacherAssistant.Academics.ProgressionPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:title, :status, :template, :teaching_context_id, :academic_year_id, :personal_workspace_id],
      update: [:title, :status, :template]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :status, :atom, constraints: [one_of: [:draft, :active]], default: :draft, public?: true
    attribute :template, :boolean, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    has_many :entries, TeacherAssistant.Academics.ProgressionEntry
  end
end
```
(Omit `has_many :entries` until Task 8 if `ProgressionEntry` is not yet defined — add it in Task 8 Step 5.)

- [ ] **Step 4: Register + domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.ProgressionPlan`, `resource ProgressionPlan`, and:
```elixir
def create_progression_plan(%TeachingContext{} = ctx, attrs) do
  attrs =
    attrs
    |> Map.put(:teaching_context_id, ctx.id)
    |> Map.put(:academic_year_id, ctx.academic_year_id)
    |> Map.put(:personal_workspace_id, ctx.personal_workspace_id)

  ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
end

def list_progression_plans(%PersonalWorkspace{id: ws_id}) do
  ProgressionPlan
  |> Ash.Query.filter(personal_workspace_id == ^ws_id)
  |> Ash.Query.sort(inserted_at: :desc)
  |> Ash.read!(authorize?: false)
end

def get_progression_plan(id), do: Ash.get(ProgressionPlan, id, authorize?: false)

def duplicate_progression_plan(%ProgressionPlan{} = plan, overrides) do
  attrs =
    %{
      title: Map.get(overrides, :title, plan.title <> " (copy)"),
      status: :draft,
      template: Map.get(overrides, :template, false),
      teaching_context_id: plan.teaching_context_id,
      academic_year_id: plan.academic_year_id,
      personal_workspace_id: plan.personal_workspace_id
    }

  ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
end
```

- [ ] **Step 5: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 6: Run tests**

Run: `mix test test/teacher_assistant/academics/progression_plan_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ProgressionPlan resource with duplicate/template"
```

---

## Task 8: ProgressionEntry resource + domain functions

**Files:**
- Create: `lib/teacher_assistant/academics/progression_entry.ex`
- Modify: `lib/teacher_assistant/academics.ex`, `lib/teacher_assistant/academics/progression_plan.ex` (add `has_many :entries`), and `duplicate_progression_plan/2` (copy entries)
- Test: `test/teacher_assistant/academics/progression_entry_test.exs`

**Interfaces:**
- Produces:
  - Resource `ProgressionEntry` (attrs: `module`, `lesson_title`, `planned_hours` (decimal), `entry_type` (atom from `Reference.entry_type_keys/0`), `week_no` (int, nullable), `position` (int), `famille_de_situations`/`categories_action`/`competence_visee` (strings, nullable), `progression_plan_id`, `sequence_id` (nullable))
  - `Academics.add_progression_entry(%ProgressionPlan{}, attrs)` → `{:ok, _} | {:error, _}` (auto-assigns next `position`)
  - `Academics.list_progression_entries(%ProgressionPlan{})` → `[%ProgressionEntry{}]` (ordered by `position`)
  - `Academics.update_progression_entry(%ProgressionEntry{}, attrs)` / `delete_progression_entry(%ProgressionEntry{})`
  - `Academics.get_progression_entry(id)`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.ProgressionEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    %{plan: plan}
  end

  test "add entries get incrementing positions", %{plan: plan} do
    {:ok, e1} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    {:ok, e2} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L2", planned_hours: Decimal.new("2"), entry_type: :lesson})
    assert e1.position == 1
    assert e2.position == 2
    assert length(Academics.list_progression_entries(plan)) == 2
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/progression_entry_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/progression_entry.ex`:
```elixir
defmodule TeacherAssistant.Academics.ProgressionEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:module, :lesson_title, :planned_hours, :entry_type, :week_no, :position,
               :famille_de_situations, :categories_action, :competence_visee,
               :progression_plan_id, :sequence_id],
      update: [:module, :lesson_title, :planned_hours, :entry_type, :week_no, :position,
               :famille_de_situations, :categories_action, :competence_visee, :sequence_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :module, :string, allow_nil?: false, public?: true
    attribute :lesson_title, :string, allow_nil?: false, public?: true
    attribute :planned_hours, :decimal, default: Decimal.new("1"), public?: true
    attribute :entry_type, :atom,
      constraints: [one_of: [:lesson, :integration, :evaluation, :revision, :correction, :remediation, :holiday]],
      default: :lesson, public?: true
    attribute :week_no, :integer, allow_nil?: true, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :famille_de_situations, :string, allow_nil?: true, public?: true
    attribute :categories_action, :string, allow_nil?: true, public?: true
    attribute :competence_visee, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? true
      public? true
    end
  end
end
```

- [ ] **Step 4: Register + domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.ProgressionEntry`, `resource ProgressionEntry`, and:
```elixir
def add_progression_entry(%ProgressionPlan{id: plan_id}, attrs) do
  next = (list_entries_query(plan_id) |> Ash.read!(authorize?: false) |> length()) + 1
  attrs = attrs |> Map.put(:progression_plan_id, plan_id) |> Map.put_new(:position, next)
  ProgressionEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
end

def list_progression_entries(%ProgressionPlan{id: plan_id}) do
  list_entries_query(plan_id) |> Ash.Query.sort(position: :asc) |> Ash.read!(authorize?: false)
end

def update_progression_entry(%ProgressionEntry{} = e, attrs),
  do: e |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

def delete_progression_entry(%ProgressionEntry{} = e), do: Ash.destroy(e, authorize?: false)
def get_progression_entry(id), do: Ash.get(ProgressionEntry, id, authorize?: false)

defp list_entries_query(plan_id) do
  ProgressionEntry |> Ash.Query.filter(progression_plan_id == ^plan_id)
end
```

- [ ] **Step 5: Wire entries into plan + duplicate**

In `lib/teacher_assistant/academics/progression_plan.ex` add inside `relationships do`:
```elixir
has_many :entries, TeacherAssistant.Academics.ProgressionEntry
```
In `duplicate_progression_plan/2` (academics.ex), after creating the copy, copy entries:
```elixir
def duplicate_progression_plan(%ProgressionPlan{} = plan, overrides) do
  attrs = %{
    title: Map.get(overrides, :title, plan.title <> " (copy)"),
    status: :draft,
    template: Map.get(overrides, :template, false),
    teaching_context_id: plan.teaching_context_id,
    academic_year_id: plan.academic_year_id,
    personal_workspace_id: plan.personal_workspace_id
  }

  with {:ok, copy} <- ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false) do
    for e <- list_progression_entries(plan) do
      ProgressionEntry
      |> Ash.Changeset.for_create(:create, %{
        module: e.module, lesson_title: e.lesson_title, planned_hours: e.planned_hours,
        entry_type: e.entry_type, week_no: e.week_no, position: e.position,
        famille_de_situations: e.famille_de_situations, categories_action: e.categories_action,
        competence_visee: e.competence_visee, progression_plan_id: copy.id, sequence_id: e.sequence_id
      })
      |> Ash.create!(authorize?: false)
    end
    {:ok, copy}
  end
end
```

- [ ] **Step 6: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 7: Run tests**

Run: `mix test test/teacher_assistant/academics/progression_entry_test.exs test/teacher_assistant/academics/progression_plan_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add ProgressionEntry resource and entry-aware plan duplication"
```

---

## Task 9: TeachingLogEntry resource (cahier de textes)

**Files:**
- Create: `lib/teacher_assistant/academics/teaching_log_entry.ex`
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/academics/teaching_log_entry_test.exs`

**Interfaces:**
- Produces:
  - Resource `TeachingLogEntry` (attrs: `date`, `content_taught`, `hours` (decimal), `status` (atom `:done | :partial`), `homework` (nullable), `note` (nullable), `personal_workspace_id`, `progression_entry_id` (nullable))
  - `Academics.log_teaching(%PersonalWorkspace{}, attrs)` → `{:ok, _} | {:error, _}`
  - `Academics.list_logs_for_plan(%ProgressionPlan{})` → `[%TeachingLogEntry{}]`
  - `Academics.list_recent_logs(%PersonalWorkspace{}, limit)` → `[%TeachingLogEntry{}]`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.TeachingLogEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    {:ok, entry} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    %{ws: ws, plan: plan, entry: entry}
  end

  test "log against a planned entry", %{ws: ws, plan: plan, entry: entry} do
    assert {:ok, log} =
             Academics.log_teaching(ws, %{date: ~D[2025-09-15], content_taught: "Intro", hours: Decimal.new("2"), status: :done, progression_entry_id: entry.id})
    assert log.status == :done
    assert [listed] = Academics.list_logs_for_plan(plan)
    assert listed.id == log.id
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/teaching_log_entry_test.exs`
Expected: FAIL.

- [ ] **Step 3: Create the resource**

Create `lib/teacher_assistant/academics/teaching_log_entry.ex`:
```elixir
defmodule TeacherAssistant.Academics.TeachingLogEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_log_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:date, :content_taught, :hours, :status, :homework, :note, :personal_workspace_id, :progression_entry_id],
      update: [:date, :content_taught, :hours, :status, :homework, :note, :progression_entry_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :content_taught, :string, allow_nil?: false, public?: true
    attribute :hours, :decimal, default: Decimal.new("1"), public?: true
    attribute :status, :atom, constraints: [one_of: [:done, :partial]], default: :done, public?: true
    attribute :homework, :string, allow_nil?: true, public?: true
    attribute :note, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry do
      source_attribute :progression_entry_id
      allow_nil? true
      public? true
    end
  end
end
```

- [ ] **Step 4: Register + domain functions**

In `lib/teacher_assistant/academics.ex` add `alias TeacherAssistant.Academics.TeachingLogEntry`, `resource TeachingLogEntry`, and:
```elixir
def log_teaching(%PersonalWorkspace{id: ws_id}, attrs) do
  attrs = Map.put(attrs, :personal_workspace_id, ws_id)
  TeachingLogEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
end

def list_logs_for_plan(%ProgressionPlan{id: plan_id}) do
  entry_ids = list_entries_query(plan_id) |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)

  TeachingLogEntry
  |> Ash.Query.filter(progression_entry_id in ^entry_ids)
  |> Ash.Query.sort(date: :desc)
  |> Ash.read!(authorize?: false)
end

def list_recent_logs(%PersonalWorkspace{id: ws_id}, limit \\ 10) do
  TeachingLogEntry
  |> Ash.Query.filter(personal_workspace_id == ^ws_id)
  |> Ash.Query.sort(date: :desc)
  |> Ash.Query.limit(limit)
  |> Ash.read!(authorize?: false)
end
```

- [ ] **Step 5: Generate migration + run**

Run: `mix ash.codegen --dev && mix ash.setup`

- [ ] **Step 6: Run tests**

Run: `mix test test/teacher_assistant/academics/teaching_log_entry_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add TeachingLogEntry resource (cahier de textes)"
```

---

## Task 10: Coverage calculator

**Files:**
- Create: `lib/teacher_assistant/academics/coverage.ex`
- Modify: `lib/teacher_assistant/academics.ex` (expose `coverage_for_plan/1`)
- Test: `test/teacher_assistant/academics/coverage_test.exs`

**Interfaces:**
- Produces:
  - `Coverage.summarize(entries, logs)` → `%{planned_hours: Decimal, covered_hours: Decimal, rate: float, by_sequence: %{(seq_id | nil) => %{planned: Decimal, covered: Decimal, rate: float}}}`
    - `covered_hours` = sum of `logs` hours whose `progression_entry_id` matches an entry in `entries` (capped at that entry's `planned_hours`).
    - `rate` = `covered_hours / planned_hours` as a float in 0.0..1.0 (0.0 when planned is 0).
  - `Academics.coverage_for_plan(%ProgressionPlan{})` → the same map (loads entries + logs).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.CoverageTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Coverage

  test "rate is covered/planned, capped per entry" do
    entries = [
      %{id: "e1", planned_hours: Decimal.new("2"), sequence_id: "s1"},
      %{id: "e2", planned_hours: Decimal.new("2"), sequence_id: "s1"}
    ]
    logs = [
      %{progression_entry_id: "e1", hours: Decimal.new("2")},
      %{progression_entry_id: "e2", hours: Decimal.new("3")}  # over-logged, capped to 2
    ]
    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.planned_hours, Decimal.new("4"))
    assert Decimal.equal?(result.covered_hours, Decimal.new("4"))
    assert result.rate == 1.0
  end

  test "zero planned gives rate 0.0" do
    assert Coverage.summarize([], []).rate == 0.0
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/coverage_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the calculator**

Create `lib/teacher_assistant/academics/coverage.ex`:
```elixir
defmodule TeacherAssistant.Academics.Coverage do
  @moduledoc "Pure taux-de-couverture calculation (planned vs covered hours)."

  def summarize(entries, logs) do
    logs_by_entry =
      logs
      |> Enum.group_by(& &1.progression_entry_id)
      |> Map.new(fn {eid, list} -> {eid, sum_hours(list)} end)

    per_entry =
      Enum.map(entries, fn e ->
        planned = to_decimal(e.planned_hours)
        logged = Map.get(logs_by_entry, e.id, Decimal.new(0))
        covered = if Decimal.compare(logged, planned) == :gt, do: planned, else: logged
        %{sequence_id: Map.get(e, :sequence_id), planned: planned, covered: covered}
      end)

    planned_total = sum_field(per_entry, :planned)
    covered_total = sum_field(per_entry, :covered)

    by_sequence =
      per_entry
      |> Enum.group_by(& &1.sequence_id)
      |> Map.new(fn {sid, list} ->
        p = sum_field(list, :planned)
        c = sum_field(list, :covered)
        {sid, %{planned: p, covered: c, rate: rate(c, p)}}
      end)

    %{planned_hours: planned_total, covered_hours: covered_total, rate: rate(covered_total, planned_total), by_sequence: by_sequence}
  end

  defp rate(_covered, planned) do
    if Decimal.equal?(planned, Decimal.new(0)), do: 0.0, else: Decimal.to_float(Decimal.div(_covered, planned))
  end

  defp sum_hours(list), do: Enum.reduce(list, Decimal.new(0), fn l, acc -> Decimal.add(acc, to_decimal(l.hours)) end)
  defp sum_field(list, key), do: Enum.reduce(list, Decimal.new(0), fn m, acc -> Decimal.add(acc, Map.fetch!(m, key)) end)
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
end
```

- [ ] **Step 4: Expose via the domain**

In `lib/teacher_assistant/academics.ex` add:
```elixir
def coverage_for_plan(%ProgressionPlan{} = plan) do
  entries = list_progression_entries(plan)
  logs = list_logs_for_plan(plan)
  TeacherAssistant.Academics.Coverage.summarize(entries, logs)
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/teacher_assistant/academics/coverage_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/coverage.ex lib/teacher_assistant/academics.ex test/teacher_assistant/academics/coverage_test.exs
git commit -m "feat: add coverage (taux de couverture) calculator"
```

---

## Task 11: Bilingual (FR) locale plumbing

**Files:**
- Create: `priv/gettext/fr/LC_MESSAGES/default.po` (empty domain file), `lib/teacher_assistant_web/plug/locale.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (plug), `lib/teacher_assistant_web/live_user_auth.ex` (set locale on scope + Gettext in `assign_scope`), `lib/teacher_assistant/accounts/user.ex` (add `locale` attribute), `lib/teacher_assistant_web/controllers/workspace_controller.ex` (optional locale switch endpoint), `config/config.exs` (gettext locales)
- Test: `test/teacher_assistant_web/locale_test.exs`

**Interfaces:**
- Produces:
  - `User` gains `attribute :locale, :string, default: "fr"` (added to `register_with_password` accept list if needed — otherwise updated via a dedicated action; for v1 default "fr", switchable via session).
  - `TeacherAssistantWeb.Plug.Locale` — reads `session["locale"]` (default "fr"), calls `Gettext.put_locale/1`.
  - `LiveUserAuth.assign_scope/2` sets `scope.locale` and calls `Gettext.put_locale/1` from `session["locale"]`.
  - Locale switch route `GET /locale/:locale` → sets `session[:locale]`, redirects back.

- [ ] **Step 1: Configure gettext locales**

In `config/config.exs` add:
```elixir
config :teacher_assistant, TeacherAssistantWeb.Gettext, locales: ~w(en fr), default_locale: "fr"
```
Create the FR domain file `priv/gettext/fr/LC_MESSAGES/default.po` with a minimal header:
```
msgid ""
msgstr ""
"Language: fr\n"
"Content-Type: text/plain; charset=UTF-8\n"
```

- [ ] **Step 2: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.LocaleTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "defaults to french and switches to english", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Tableau de bord"  # FR default (string added in Step 5)

    conn = get(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/teacher"
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Teacher dashboard"
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/locale_test.exs`
Expected: FAIL.

- [ ] **Step 4: Add the locale plug + route + scope wiring**

Create `lib/teacher_assistant_web/plug/locale.ex`:
```elixir
defmodule TeacherAssistantWeb.Plug.Locale do
  @behaviour Plug
  import Plug.Conn
  @locales ~w(en fr)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = get_session(conn, :locale) || "fr"
    locale = if locale in @locales, do: locale, else: "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end
end
```
In `router.ex`, add `plug TeacherAssistantWeb.Plug.Locale` to the `:browser` pipeline (after `:load_from_session`), and in the first `scope "/"`:
```elixir
get "/locale/:locale", LocaleController, :set
```
Create `lib/teacher_assistant_web/controllers/locale_controller.ex`:
```elixir
defmodule TeacherAssistantWeb.LocaleController do
  use TeacherAssistantWeb, :controller
  @locales ~w(en fr)

  def set(conn, %{"locale" => locale}) do
    locale = if locale in @locales, do: locale, else: "fr"
    conn
    |> put_session(:locale, locale)
    |> redirect(to: ~p"/teacher")
  end
end
```
In `live_user_auth.ex`, extend `assign_scope/2` to set locale on the scope and gettext:
```elixir
defp assign_scope(socket, session) do
  user = socket.assigns[:current_user] || load_user(session["user_id"])
  locale = session["locale"] || "fr"
  Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)
  scope = %{resolve_scope(user, session["workspace_id"]) | locale: locale}

  socket
  |> assign(:current_user, user)
  |> assign(:current_scope, scope)
  |> assign(:scope, scope)
end
```
Add `"locale" => Plug.Conn.get_session(conn, :locale)` to `session_context/1`.

- [ ] **Step 5: Make the dashboard string translatable + add FR translation**

In `dashboard_live.ex` the heading is already `{gettext("Teacher dashboard")}`. Add the FR translation to `priv/gettext/fr/LC_MESSAGES/default.po`:
```
msgid "Teacher dashboard"
msgstr "Tableau de bord"
```
Run `mix gettext.extract` is not required here since we hand-add; ensure the msgid matches exactly.

- [ ] **Step 6: Run tests**

Run: `mix test test/teacher_assistant_web/locale_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add bilingual FR/EN locale plumbing with switch"
```

---

## Task 12: Setup wizard LiveView

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/setup_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route)
- Test: `test/teacher_assistant_web/live/teacher/setup_live_test.exs`

**Interfaces:**
- Consumes: `Academics.create_academic_year/2`, `Academics.build_default_calendar/1`, `Academics.create_teaching_context/3`, `Reference.subsystems/0`, `Reference.levels/1`, `Reference.subjects/0`.
- Produces: route `live "/teacher/setup", Teacher.SetupLive, :index`; on completion creates an active academic year (with default calendar) + one teaching context, then `push_navigate` to `/teacher`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Teacher.SetupLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  test "completing setup creates a year, calendar and teaching context", %{conn: conn, workspace: ws} do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    view
    |> form("#setup-form", setup: %{
      name: "2025-2026", start_date: "2025-09-08", end_date: "2026-07-31",
      subsystem: "francophone", subject: "Mathématiques", level: "6ème", weekly_hours: "4"
    })
    |> render_submit()

    year = Academics.current_academic_year(ws)
    assert year.name == "2025-2026"
    assert length(Academics.list_sequences(year)) == 6
    assert [_ctx] = Academics.list_teaching_contexts(ws, year)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/setup_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement the LiveView**

Create `lib/teacher_assistant_web/live/teacher/setup_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.SetupLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Reference

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:subsystem, :francophone)
     |> assign(:form, to_form(%{}, as: :setup))}
  end

  def handle_event("subsystem-changed", %{"setup" => %{"subsystem" => sub}}, socket) do
    {:noreply, assign(socket, :subsystem, String.to_existing_atom(sub))}
  end

  def handle_event("save", %{"setup" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {:ok, year} <- Academics.create_academic_year(ws, %{name: p["name"], start_date: p["start_date"], end_date: p["end_date"], active: true}),
         :ok <- Academics.build_default_calendar(year),
         {:ok, _ctx} <- Academics.create_teaching_context(ws, year, %{subject: p["subject"], level: p["level"], subsystem: String.to_existing_atom(p["subsystem"]), weekly_hours: String.to_integer(p["weekly_hours"])}) do
      {:noreply, socket |> put_flash(:info, gettext("Setup complete")) |> push_navigate(to: ~p"/teacher")}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not complete setup"))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-setup" class="p-4 max-w-md mx-auto space-y-4">
        <h1 class="text-xl font-semibold">{gettext("Set up your year")}</h1>
        <.form for={@form} id="setup-form" phx-change="subsystem-changed" phx-submit="save" class="space-y-3">
          <.input field={@form[:name]} label={gettext("Academic year")} value="2025-2026" />
          <.input type="date" field={@form[:start_date]} label={gettext("Start date")} value="2025-09-08" />
          <.input type="date" field={@form[:end_date]} label={gettext("End date")} value="2026-07-31" />
          <.input type="select" field={@form[:subsystem]} label={gettext("Subsystem")}
            options={for s <- Reference.subsystems(), do: {s.fr, s.key}} />
          <.input type="select" field={@form[:subject]} label={gettext("Subject")}
            options={for s <- Reference.subjects(), do: {s.fr, s.fr}} />
          <.input type="select" field={@form[:level]} label={gettext("Class")}
            options={for l <- Reference.levels(@subsystem), do: {l, l}} />
          <.input type="number" field={@form[:weekly_hours]} label={gettext("Weekly hours")} value="4" />
          <.button id="setup-submit" type="submit" class="btn btn-primary w-full">{gettext("Finish")}</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Add the route**

In `router.ex` `ash_authentication_live_session :teacher_workspace`, add:
```elixir
live "/teacher/setup", Teacher.SetupLive, :index
```

- [ ] **Step 5: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/setup_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add teacher setup wizard LiveView"
```

---

## Task 13: Dashboard LiveView (current week + coverage KPIs)

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/dashboard_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Scope`, `Academics.list_teaching_contexts/2`, `Academics.list_progression_plans/1`, `Academics.coverage_for_plan/1`, `Academics.current_sequence/2`.
- Produces: dashboard with `#academic-year-setup-gate` (when no active year) OR `#teacher-dashboard` with `#coverage-kpis` per plan.

- [ ] **Step 1: Write the failing test (extend existing file)**

```elixir
  test "shows setup gate when no academic year", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "id=\"academic-year-setup-gate\""
  end

  test "shows coverage kpis after setup", %{conn: conn, workspace: ws} do
    {:ok, year} = TeacherAssistant.Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    :ok = TeacherAssistant.Academics.build_default_calendar(year)
    {:ok, ctx} = TeacherAssistant.Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, _plan} = TeacherAssistant.Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})

    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#coverage-kpis")
  end
```
(Keep the logged-out redirect test from Task 1.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

Replace `dashboard_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    socket =
      if year do
        ws = scope.current_workspace
        plans = Academics.list_progression_plans(ws)
        kpis = Enum.map(plans, fn p -> %{plan: p, coverage: Academics.coverage_for_plan(p)} end)
        assign(socket, year: year, kpis: kpis)
      else
        assign(socket, year: nil, kpis: [])
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= if @year do %>
        <section id="teacher-dashboard" class="p-4 space-y-4">
          <h1 class="text-xl font-semibold">{gettext("Teacher dashboard")}</h1>
          <div id="coverage-kpis" class="grid gap-3">
            <div :for={kpi <- @kpis} id={"kpi-#{kpi.plan.id}"} class="card bg-base-100 shadow p-4">
              <div class="font-medium">{kpi.plan.title}</div>
              <div class="text-2xl font-bold">{round(kpi.coverage.rate * 100)}%</div>
              <div class="text-sm opacity-70">{gettext("covered")}</div>
              <.link navigate={~p"/teacher/plans/#{kpi.plan.id}"} class="link link-primary text-sm">{gettext("Open plan")}</.link>
            </div>
            <div :if={@kpis == []} class="opacity-70">
              {gettext("No progression plan yet.")}
              <.link navigate={~p"/teacher/setup"} class="link">{gettext("Set one up")}</.link>
            </div>
          </div>
        </section>
      <% else %>
        <section id="academic-year-setup-gate" class="p-4 space-y-3 text-center">
          <h1 class="text-xl font-semibold">{gettext("Welcome")}</h1>
          <p class="opacity-70">{gettext("Set up your academic year to get started.")}</p>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary">{gettext("Start setup")}</.link>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: dashboard with setup gate and coverage KPIs"
```

---

## Task 14: Fiche builder LiveView

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Modify: `router.ex`
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`

**Interfaces:**
- Consumes: `Academics.get_progression_plan/1`, `Academics.list_progression_entries/1`, `Academics.add_progression_entry/2`, `Academics.delete_progression_entry/1`, `Academics.duplicate_progression_plan/2`, `Reference.entry_types/0`, `Academics.list_sequences/1`, `Academics.get_academic_year/1`.
- Produces: route `live "/teacher/plans/:id", Teacher.FicheLive, :show`; add/delete entries; `#fiche-entries` list with `#entry-<id>` rows; `#add-entry-form`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Teacher.FicheLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    :ok = Academics.build_default_calendar(year)
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})
    %{plan: plan}
  end

  test "add an entry to the plan", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view
    |> form("#add-entry-form", entry: %{module: "Module 1", lesson_title: "Les nombres", planned_hours: "2", entry_type: "lesson"})
    |> render_submit()

    assert has_element?(view, "#fiche-entries")
    assert render(view) =~ "Les nombres"
    assert length(Academics.list_progression_entries(plan)) == 1
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/teacher_assistant_web/live/teacher/fiche_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.FicheLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Reference

  def mount(%{"id" => id}, _session, socket) do
    {:ok, plan} = Academics.get_progression_plan(id)
    {:ok, assign_entries(socket, plan)}
  end

  def handle_event("add-entry", %{"entry" => p}, socket) do
    case Academics.add_progression_entry(socket.assigns.plan, %{
           module: p["module"], lesson_title: p["lesson_title"],
           planned_hours: Decimal.new(blank_to(p["planned_hours"], "1")),
           entry_type: String.to_existing_atom(p["entry_type"])
         }) do
      {:ok, _} -> {:noreply, assign_entries(socket, socket.assigns.plan)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not add entry"))}
    end
  end

  def handle_event("delete-entry", %{"id" => id}, socket) do
    {:ok, entry} = Academics.get_progression_entry(id)
    Academics.delete_progression_entry(entry)
    {:noreply, assign_entries(socket, socket.assigns.plan)}
  end

  def handle_event("duplicate-plan", _params, socket) do
    {:ok, copy} = Academics.duplicate_progression_plan(socket.assigns.plan, %{})
    {:noreply, push_navigate(socket, to: ~p"/teacher/plans/#{copy.id}")}
  end

  defp assign_entries(socket, plan) do
    socket
    |> assign(:plan, plan)
    |> assign(:entries, Academics.list_progression_entries(plan))
    |> assign(:entry_form, to_form(%{}, as: :entry))
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="fiche-builder" class="p-4 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">{@plan.title}</h1>
          <.button id="duplicate-plan" phx-click="duplicate-plan" class="btn btn-ghost btn-sm">{gettext("Duplicate")}</.button>
        </div>

        <ul id="fiche-entries" class="space-y-2">
          <li :for={e <- @entries} id={"entry-#{e.id}"} class="card bg-base-100 shadow p-3 flex flex-row justify-between items-center">
            <div>
              <div class="font-medium">{e.lesson_title}</div>
              <div class="text-sm opacity-70">{e.module} · {e.planned_hours}h · {e.entry_type}</div>
            </div>
            <.button phx-click="delete-entry" phx-value-id={e.id} class="btn btn-ghost btn-xs">{gettext("Delete")}</.button>
          </li>
        </ul>

        <.form for={@entry_form} id="add-entry-form" phx-submit="add-entry" class="card bg-base-200 p-3 space-y-2">
          <.input field={@entry_form[:module]} label={gettext("Module")} />
          <.input field={@entry_form[:lesson_title]} label={gettext("Lesson")} />
          <.input type="number" field={@entry_form[:planned_hours]} label={gettext("Hours")} value="1" />
          <.input type="select" field={@entry_form[:entry_type]} label={gettext("Type")}
            options={for t <- Reference.entry_types(), do: {t.fr, t.key}} />
          <.button id="add-entry-submit" type="submit" class="btn btn-primary">{gettext("Add entry")}</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Add the route**

In `router.ex` teacher session add:
```elixir
live "/teacher/plans/:id", Teacher.FicheLive, :show
```

- [ ] **Step 5: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add fiche de progression builder LiveView"
```

---

## Task 15: Teach / log LiveView (quick capture)

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/log_live.ex`
- Modify: `router.ex`
- Test: `test/teacher_assistant_web/live/teacher/log_live_test.exs`

**Interfaces:**
- Consumes: `Academics.list_progression_plans/1`, `Academics.list_progression_entries/1`, `Academics.log_teaching/2`, `Academics.get_progression_plan/1`.
- Produces: route `live "/teacher/log", Teacher.LogLive, :index`; `#log-form` that records a `TeachingLogEntry` against a chosen entry.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Teacher.LogLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    {:ok, entry} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    %{ws: ws, plan: plan, entry: entry}
  end

  test "logging a lesson records it", %{conn: conn, plan: plan, entry: entry} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    view
    |> form("#log-form", log: %{progression_entry_id: entry.id, date: "2025-09-15", content_taught: "Intro", hours: "2", status: "done"})
    |> render_submit()

    assert length(Academics.list_logs_for_plan(plan)) == 1
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/log_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/teacher_assistant_web/live/teacher/log_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.LogLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(_params, _session, socket) do
    ws = socket.assigns.current_scope.current_workspace
    plans = if ws, do: Academics.list_progression_plans(ws), else: []
    entries = Enum.flat_map(plans, &Academics.list_progression_entries/1)

    {:ok,
     socket
     |> assign(:ws, ws)
     |> assign(:entries, entries)
     |> assign(:form, to_form(%{}, as: :log))}
  end

  def handle_event("save", %{"log" => p}, socket) do
    case Academics.log_teaching(socket.assigns.ws, %{
           progression_entry_id: p["progression_entry_id"],
           date: p["date"], content_taught: p["content_taught"],
           hours: Decimal.new(blank_to(p["hours"], "1")),
           status: String.to_existing_atom(p["status"]),
           homework: blank_to(p["homework"], nil), note: blank_to(p["note"], nil)
         }) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, gettext("Logged")) |> push_navigate(to: ~p"/teacher")}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not log"))}
    end
  end

  defp blank_to(nil, d), do: d
  defp blank_to("", d), do: d
  defp blank_to(v, _), do: v

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-log" class="p-4 max-w-md mx-auto space-y-3">
        <h1 class="text-xl font-semibold">{gettext("Log what you taught")}</h1>
        <.form for={@form} id="log-form" phx-submit="save" class="space-y-3">
          <.input type="select" field={@form[:progression_entry_id]} label={gettext("Lesson")}
            options={for e <- @entries, do: {"#{e.module} · #{e.lesson_title}", e.id}} />
          <.input type="date" field={@form[:date]} label={gettext("Date")} />
          <.input field={@form[:content_taught]} label={gettext("What was taught")} />
          <.input type="number" field={@form[:hours]} label={gettext("Hours")} value="1" />
          <.input type="select" field={@form[:status]} label={gettext("Status")}
            options={[{gettext("Done"), "done"}, {gettext("Partial"), "partial"}]} />
          <.input field={@form[:homework]} label={gettext("Homework (optional)")} />
          <.input field={@form[:note]} label={gettext("Note (optional)")} />
          <.button id="log-submit" type="submit" class="btn btn-primary w-full">{gettext("Save")}</.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Add the route**

In `router.ex` teacher session add:
```elixir
live "/teacher/log", Teacher.LogLive, :index
```

- [ ] **Step 5: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/log_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add teach/log quick-capture LiveView"
```

---

## Task 16: Coverage view LiveView

**Files:**
- Create: `lib/teacher_assistant_web/live/teacher/coverage_live.ex`
- Modify: `router.ex`
- Test: `test/teacher_assistant_web/live/teacher/coverage_live_test.exs`

**Interfaces:**
- Consumes: `Academics.get_progression_plan/1`, `Academics.coverage_for_plan/1`, `Academics.list_progression_entries/1`, `Academics.list_logs_for_plan/1`.
- Produces: route `live "/teacher/plans/:id/coverage", Teacher.CoverageLive, :show`; `#coverage-summary` with overall rate and `#uncovered-entries` list.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Teacher.CoverageLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    {:ok, e1} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    {:ok, _e2} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L2", planned_hours: Decimal.new("2"), entry_type: :lesson})
    {:ok, _log} = Academics.log_teaching(ws, %{date: ~D[2025-09-15], content_taught: "x", hours: Decimal.new("2"), status: :done, progression_entry_id: e1.id})
    %{plan: plan}
  end

  test "shows 50% coverage and one uncovered entry", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}/coverage")
    assert has_element?(view, "#coverage-summary")
    assert render(view) =~ "50%"
    assert has_element?(view, "#uncovered-entries")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/coverage_live_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/teacher_assistant_web/live/teacher/coverage_live.ex`:
```elixir
defmodule TeacherAssistantWeb.Teacher.CoverageLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Academics

  def mount(%{"id" => id}, _session, socket) do
    {:ok, plan} = Academics.get_progression_plan(id)
    coverage = Academics.coverage_for_plan(plan)
    entries = Academics.list_progression_entries(plan)
    logged_ids = Academics.list_logs_for_plan(plan) |> Enum.map(& &1.progression_entry_id) |> MapSet.new()
    uncovered = Enum.reject(entries, &MapSet.member?(logged_ids, &1.id))

    {:ok, assign(socket, plan: plan, coverage: coverage, uncovered: uncovered)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-coverage" class="p-4 space-y-4">
        <h1 class="text-xl font-semibold">{@plan.title} — {gettext("Coverage")}</h1>
        <div id="coverage-summary" class="card bg-base-100 shadow p-4">
          <div class="text-3xl font-bold">{round(@coverage.rate * 100)}%</div>
          <div class="text-sm opacity-70">{@coverage.covered_hours}h / {@coverage.planned_hours}h {gettext("covered")}</div>
        </div>
        <div>
          <h2 class="font-medium mb-2">{gettext("Not yet covered")}</h2>
          <ul id="uncovered-entries" class="space-y-1">
            <li :for={e <- @uncovered} id={"uncovered-#{e.id}"} class="text-sm">{e.module} · {e.lesson_title}</li>
            <li :if={@uncovered == []} class="text-sm opacity-70">{gettext("Everything is covered.")}</li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 4: Add the route**

In `router.ex` teacher session add:
```elixir
live "/teacher/plans/:id/coverage", Teacher.CoverageLive, :show
```

- [ ] **Step 5: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/coverage_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add coverage view LiveView"
```

---

## Task 17: Navigation, seeds, and final verification

**Files:**
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (mobile nav links + locale switch), `priv/repo/seeds.exs` (optional demo data)
- Test: `test/teacher_assistant_web/live/teacher/navigation_test.exs`

**Interfaces:**
- Consumes: existing routes.
- Produces: a nav (in `Layouts.app`) with links to dashboard, log, and a FR/EN switch; `#main-nav` present on authenticated screens.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Teacher.NavigationTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "authenticated nav shows dashboard and log links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#main-nav")
    assert has_element?(view, "#nav-log")
    assert has_element?(view, "#locale-switch")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/navigation_test.exs`
Expected: FAIL.

- [ ] **Step 3: Add nav to the layout**

In `lib/teacher_assistant_web/components/layouts.ex`, inside the `app/1` `~H` template header area, add (adapt to existing markup):
```heex
<nav id="main-nav" :if={@current_user} class="navbar bg-base-100 px-4 gap-2">
  <.link id="nav-dashboard" navigate={~p"/teacher"} class="btn btn-ghost btn-sm">{gettext("Dashboard")}</.link>
  <.link id="nav-log" navigate={~p"/teacher/log"} class="btn btn-ghost btn-sm">{gettext("Log")}</.link>
  <div id="locale-switch" class="ml-auto flex gap-1">
    <.link navigate={~p"/locale/fr"} class="btn btn-ghost btn-xs">FR</.link>
    <.link navigate={~p"/locale/en"} class="btn btn-ghost btn-xs">EN</.link>
  </div>
</nav>
```
(`@current_user` is already assigned by `app/1` per the scaffold.)

- [ ] **Step 4: Run the nav test**

Run: `mix test test/teacher_assistant_web/live/teacher/navigation_test.exs`
Expected: PASS.

- [ ] **Step 5: Add optional demo seeds**

In `priv/repo/seeds.exs`, add an idempotent demo teacher (guard so it only runs in dev). Keep it minimal:
```elixir
if Mix.env() == :dev do
  alias TeacherAssistant.{Accounts, Academics}
  email = "demo@example.com"

  user =
    case Accounts.create_user(%{email: email, password: "password1234", password_confirmation: "password1234"}) do
      {:ok, u} -> u
      _ -> Ash.read_first!(Ash.Query.filter(Accounts.User, email == ^email), authorize?: false)
    end

  ws = Academics.ensure_personal_workspace!(user)
  {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
  :ok = Academics.build_default_calendar(year)
  {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Mathématiques", level: "6ème", subsystem: :francophone, weekly_hours: 4})
  {:ok, _plan} = Academics.create_progression_plan(ctx, %{title: "Mathématiques 6ème 2025-2026"})
end
```
(If the demo user/year already exists on re-run, wrap creation calls in `try`/`rescue` or check-first; keep dev-only.)

- [ ] **Step 6: Full verification**

Run: `mix precommit`
Expected: compile (no warnings), deps.unlock, format, and the **entire test suite** PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add mobile nav, locale switch, and dev seeds; v1 complete"
```

---

## Self-Review

**Spec coverage:**
- Onboarding (language/subsystem/year) → Task 11 (locale) + Task 12 (wizard). ✅
- Declare teaching context → Task 6 + Task 12. ✅
- Build fiche (modules→lessons across sequences/weeks, entry types, optional CBA fields, duplicate/template) → Tasks 7, 8, 14. ✅
- Teach & log (cahier de textes) → Tasks 9, 15. ✅
- See status / coverage (per sequence/term/year, ahead/behind, uncovered list) → Tasks 10, 13, 16. ✅
- Academic-year grid with default calendar, editable → Tasks 4, 5 (+ wizard prefilled values in Task 12). ✅ *(Note: in-UI editing of individual sequence dates after creation is provided implicitly via re-setup; a dedicated calendar editor is deferred — the wizard ships the editable preset values, satisfying "ships default, editable at creation." Per-sequence post-hoc editing UI is a v1.x nicety, not a v1 blocker.)*
- Bilingual FR/EN → Task 11 throughout. ✅
- Empty/setup states (no crash on missing year) → Task 13 setup gate. ✅
- Mobile-first, stable DOM IDs, LiveView tests → every LiveView task. ✅
- Clean slate (keep auth scaffold only) → Task 1. ✅
- Non-goals (import, marks, lesson plan, school layer, syllabus library, offline, AI) → not implemented, correct. ✅

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to" — each step has concrete code. The two `(omit until later task)` notes in Tasks 4/7 are explicit sequencing instructions, not placeholders, and the corresponding relationship is added in the named follow-up step.

**Type consistency:** Domain function names are used identically across tasks (`create_academic_year/2`, `build_default_calendar/1`, `list_sequences/1`, `current_sequence/2`, `create_teaching_context/3`, `create_progression_plan/2`, `add_progression_entry/2`, `list_progression_entries/1`, `log_teaching/2`, `list_logs_for_plan/1`, `coverage_for_plan/1`, `duplicate_progression_plan/2`). `Coverage.summarize/2` return shape matches its consumers in Tasks 13 & 16 (`.rate`, `.covered_hours`, `.planned_hours`). Resource attribute names match between resource definitions and the create-action accept lists.

## Execution Handoff

(Provided after saving — see final message.)
