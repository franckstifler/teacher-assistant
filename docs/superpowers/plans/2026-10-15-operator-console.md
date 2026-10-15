# Operator Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the platform operator a console to see every school, suspend/reactivate it, switch its six modules on or off, reset any user's password, and read an audit journal — and let heads reset any member of their school.

**Architecture:** A `modules` list and suspension fields on `Workspace`, read from the already-loaded scope. One catalogue (`TeacherAssistant.Modules`) maps every gated LiveView and controller action to a module; an `on_mount` hook, a controller plug, the `Spaces` menus and the jobs all read it. Operator actions and password resets write `AuditEvent` rows in the same transaction. New admin LiveViews live in the existing `:operator` live session.

**Tech Stack:** Elixir 1.20 / OTP 29, Phoenix 1.8 LiveView, Ash 3 + AshPostgres, AshAuthentication, Oban, Gettext (FR default, EN).

**Spec:** `docs/superpowers/specs/2026-10-15-operator-console-design.md`

## Global Constraints

- Never write migrations by hand: `mix ash.codegen <name>` then review the file (AGENTS.md).
- Finish with `mix precommit` (compile with warnings as errors, deps unlock, format, gettext check, tests).
- Module keys, verbatim: `:notes`, `:appel`, `:discipline`, `:emploi_du_temps`, `:frais`, `:photos`.
- Existing schools get all six modules; new schools get `[]` (spec §1 Storage).
- Only the operator (`User.role == :admin`) changes modules, suspends, reactivates, reads the journal.
- `/verify/bulletin/:token` is never gated by modules or suspension.
- A temporary password is shown once and never stored in clear, logged or journaled.
- Every user-facing string goes through `gettext`; French source strings, as in the rest of the app; add the English translation in `priv/gettext/en/LC_MESSAGES/default.po` after `mix gettext.extract --merge`.
- LiveView templates start with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`; inputs use `<.input>`; icons use `<.icon>`; stable DOM ids on every element a test touches.
- Tests that need a running mix in this environment: `MIX_HOME` must point at a Hex built for OTP 29 (`mix local.hex --force` once).

## Review Focus

1. A school created through the UI (no modules) whose head opens `/school` must land on a working dashboard, not a redirect loop — Task 4 test « a school with no modules still opens its dashboard ».
2. A member of two schools, one suspended, must keep working in the other after switching — Task 5 test « a member switches from a suspended school to another ».
3. A head resetting an email-only member who was never created by the school (`created_in_workspace_id == nil`) must succeed — Task 6 test « a head resets an invited (email) member ».
4. An operator who is not a member of any school must be able to open every admin page and the rail must not crash on a scope without a workspace — Task 8 test « an operator with no school opens the console ».
5. Unchecking every module and saving must store `[]`, not keep the old list (an empty checkbox group posts nothing) — Task 8 test « saving with every box unchecked clears the modules ».

---

## File map

| File | Responsibility |
|---|---|
| `lib/teacher_assistant/modules.ex` (create) | Catalogue: keys, labels, LiveView/controller → module map, core list |
| `lib/teacher_assistant/modules/key.ex` (create) | `Ash.Type.Enum` of the six keys |
| `lib/teacher_assistant/accounts/audit_event.ex` (create) | Journal resource |
| `lib/teacher_assistant/accounts/audit_event/action.ex` (create) | Enum of journal actions |
| `lib/teacher_assistant/accounts/audit_event/record.ex` (create) | `after_action` change writing the journal row |
| `lib/teacher_assistant/academics/workspace.ex` (modify) | `modules`, `suspended_at`, `suspension_reason`, actions `:set_modules`, `:suspend`, `:reactivate` |
| `lib/teacher_assistant/accounts/school_profile.ex` (modify) | journal `:verify`, `:reject` |
| `lib/teacher_assistant/accounts/user.ex` (modify) | reset policy, journal reset |
| `lib/teacher_assistant/accounts/checks/active_in_another_school.ex` (modify) | compare against the acting school |
| `lib/teacher_assistant/accounts/checks/head_of_acting_school.ex` (create) | target is a head of the acting school |
| `lib/teacher_assistant/accounts/checks/head_of_members_school.ex` (create) | actor heads the acting school, target is an active member of it |
| `lib/teacher_assistant/scope.ex` (modify) | `module?/2`, `suspended?/1` |
| `lib/teacher_assistant/accounts/workspaces.ex` (modify) | `job_scopes/0` skips suspended schools |
| `lib/teacher_assistant/workers/missed_roll_calls.ex` (modify) | skip schools without `:appel` |
| `lib/teacher_assistant_web/live_user_auth.ex` (modify) | `:require_active_school`, `:require_module` |
| `lib/teacher_assistant_web/plug/school_access.ex` (create) | same checks for controllers |
| `lib/teacher_assistant_web/controllers/*_print_controller.ex`, `student_photo_controller.ex`, `school_logo_controller.ex` (modify) | `plug TeacherAssistantWeb.Plug.SchoolAccess` |
| `lib/teacher_assistant_web/live/school/suspended_live.ex` (create) | « Établissement suspendu » page |
| `lib/teacher_assistant_web/spaces.ex` (modify) | drop items of off modules, skip their counts |
| `lib/teacher_assistant_web/live/school/class_shell.ex`, `bulletin_print_html/show.html.heex`, `student_live.ex`, `my_day_live.ex`, `settings_live.ex` (modify) | hide parts of off modules; read-only modules card |
| `lib/teacher_assistant/operator.ex` (create) | Operator-only queries and commands (counts, lists, reset) |
| `lib/teacher_assistant_web/live/admin/overview_live.ex`, `schools_live.ex` (rewrite), `school_live.ex`, `users_live.ex`, `journal_live.ex` (create) | Console pages |
| `lib/teacher_assistant_web/live/admin/reset_modal.ex` (create) | Shared confirm + one-time password modal |
| `lib/teacher_assistant_web/components/layouts.ex` (modify) | « Administration » rail group for operators |
| `lib/teacher_assistant_web/router.ex` (modify) | new routes |
| `lib/mix/tasks/teacher_assistant.make_operator.ex` (create) | promote a user |
| `config/config.exs`, `config/test.exs` (modify) | `:new_school_modules` |
| `priv/repo/demo_school_seeds.exs`, `priv/repo/seeds.exs` (modify) | enable modules on demo schools |

### Note on the new-school default and the test suite

81 test files create schools through `Organization.create_school/2` and then use marks, roll call, etc. The spec's default for new schools is `[]`. To keep that default without editing 81 files, the default comes from config:

```elixir
# config/config.exs
config :teacher_assistant, :new_school_modules, []
# config/test.exs
config :teacher_assistant, :new_school_modules,
  [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
```

`Application.put_env` is global and would race with async tests, so no test changes the config. Instead: `Modules.new_school_default/0` is unit-tested to return the configured value, `create_school` is tested to store `new_school_default/0` (whatever the environment says), and every « module off » behaviour is tested by setting modules explicitly with `Organization.set_modules/3`. Production and dev read `[]`; the dev seeds enable every module on their schools (Task 9).

---

### Task 1: Audit journal resource

**Files:**
- Create: `lib/teacher_assistant/accounts/audit_event.ex`, `lib/teacher_assistant/accounts/audit_event/action.ex`, `lib/teacher_assistant/accounts/audit_event/record.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (register resource, add `list_audit_events/2`)
- Test: `test/teacher_assistant/accounts/audit_event_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Accounts.AuditEvent` with attributes `actor_user_id`, `action`, `workspace_id`, `target_user_id`, `details` (map), `inserted_at`.
  - `AuditEvent.Action` enum: `:school_verified, :school_rejected, :school_suspended, :school_reactivated, :modules_changed, :password_reset`.
  - Change `{TeacherAssistant.Accounts.AuditEvent.Record, action: atom}` usable on update actions of `Workspace`, `SchoolProfile`, `User`.
  - `Accounts.list_audit_events(scope, opts)` — `opts`: `workspace_id`, `action`, `limit` (default 50), `offset` (default 0); newest first; operator only.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.AuditEventTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Scope, TeacherFixtures}
  alias TeacherAssistant.Accounts.AuditEvent

  test "an operator reads events newest first, filtered by school and action" do
    operator = TeacherFixtures.admin_user_fixture()
    %{workspace: ws} = TeacherFixtures.school_fixture()

    for action <- [:school_verified, :modules_changed] do
      AuditEvent
      |> Ash.Changeset.for_create(:record, %{
        actor_user_id: operator.id,
        action: action,
        workspace_id: ws.id,
        details: %{"n" => 1}
      })
      |> Ash.create!(authorize?: false)
    end

    scope = %Scope{current_user: operator}
    assert [%{action: :modules_changed}, %{action: :school_verified}] =
             Accounts.list_audit_events(scope, workspace_id: ws.id)

    assert [%{action: :school_verified}] =
             Accounts.list_audit_events(scope, action: :school_verified)
  end

  test "nobody but the operator reads the journal" do
    %{scope: head_scope} = TeacherFixtures.school_fixture()
    assert_raise Ash.Error.Forbidden, fn -> Accounts.list_audit_events(head_scope, []) end
  end

  test "events cannot be changed or deleted" do
    refute Ash.Resource.Info.action(AuditEvent, :update)
    refute Ash.Resource.Info.action(AuditEvent, :destroy)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/teacher_assistant/accounts/audit_event_test.exs`
Expected: FAIL — `TeacherAssistant.Accounts.AuditEvent` is undefined.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/accounts/audit_event/action.ex`:

```elixir
defmodule TeacherAssistant.Accounts.AuditEvent.Action do
  use Ash.Type.Enum,
    values: [
      :school_verified,
      :school_rejected,
      :school_suspended,
      :school_reactivated,
      :modules_changed,
      :password_reset
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:school_verified), do: gettext("Établissement vérifié")
  def label(:school_rejected), do: gettext("Établissement rejeté")
  def label(:school_suspended), do: gettext("Établissement suspendu")
  def label(:school_reactivated), do: gettext("Établissement réactivé")
  def label(:modules_changed), do: gettext("Modules modifiés")
  def label(:password_reset), do: gettext("Mot de passe réinitialisé")
end
```

`lib/teacher_assistant/accounts/audit_event.ex`:

```elixir
defmodule TeacherAssistant.Accounts.AuditEvent do
  @moduledoc """
  The operator journal (operator console spec §4): one append-only row per operator
  action and per password reset. Not multitenant — operator events span schools.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "audit_events"
    repo TeacherAssistant.Repo

    references do
      reference :actor, on_delete: :nilify
      reference :target_user, on_delete: :nilify
      reference :workspace, on_delete: :delete
    end

    custom_indexes do
      index [:inserted_at]
      index [:workspace_id, :inserted_at]
    end
  end

  actions do
    # Internal only: written by `AuditEvent.Record` with `authorize?: false`.
    create :record do
      accept [:actor_user_id, :action, :workspace_id, :target_user_id, :details]
    end

    read :read do
      primary? true
      pagination offset?: true, required?: false, default_limit: 50
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :action, TeacherAssistant.Accounts.AuditEvent.Action, allow_nil?: false, public?: true
    attribute :details, :map, allow_nil?: false, default: %{}, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :actor, TeacherAssistant.Accounts.User do
      source_attribute :actor_user_id
      public? true
    end

    belongs_to :target_user, TeacherAssistant.Accounts.User do
      source_attribute :target_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      public? true
    end
  end
end
```

No policy covers `:record`, so Ash forbids it to every actor; `Record` calls it with `authorize?: false`.

`lib/teacher_assistant/accounts/audit_event/record.ex`:

```elixir
defmodule TeacherAssistant.Accounts.AuditEvent.Record do
  @moduledoc """
  Journals the action it is attached to (operator console spec §4), in the action's
  transaction: a failed journal write fails the action.

      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_suspended}
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Accounts.AuditEvent

  @impl true
  def change(changeset, opts, context) do
    action = Keyword.fetch!(opts, :action)
    before = changeset.data

    Ash.Changeset.after_action(changeset, fn changeset, record ->
      AuditEvent
      |> Ash.Changeset.for_create(:record, %{
        actor_user_id: context.actor && context.actor.id,
        action: action,
        workspace_id: workspace_id(record, changeset),
        target_user_id: target_user_id(record),
        details: details(action, before, record, changeset)
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _event} -> {:ok, record}
        {:error, error} -> {:error, error}
      end
    end)
  end

  # Map patterns on `__struct__` names would create compile-time dependencies on the
  # resources using this change; match on the resource module the changeset names.
  defp workspace_id(%{id: id}, %{resource: TeacherAssistant.Academics.Workspace}), do: id
  defp workspace_id(%{workspace_id: id}, _changeset), do: id
  defp workspace_id(_record, %{tenant: tenant}) when is_binary(tenant), do: tenant
  defp workspace_id(_record, _changeset), do: nil

  defp target_user_id(%{__struct__: TeacherAssistant.Accounts.User, id: id}), do: id
  defp target_user_id(_record), do: nil

  defp details(:modules_changed, before, record, _cs),
    do: %{"before" => Enum.map(before.modules, &to_string/1), "after" => Enum.map(record.modules, &to_string/1)}

  defp details(:school_suspended, _before, record, _cs), do: %{"reason" => record.suspension_reason}
  defp details(:school_rejected, _before, record, _cs), do: %{"reason" => record.rejection_reason}
  defp details(_action, _before, _record, _cs), do: %{}
end
```

In `lib/teacher_assistant/accounts.ex`, inside `resources do`, add `resource TeacherAssistant.Accounts.AuditEvent`, then:

```elixir
  @doc "The operator journal, newest first (operator console spec §4). Operator only."
  def list_audit_events(%Scope{} = scope, opts) do
    TeacherAssistant.Accounts.AuditEvent
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> then(fn q ->
      case opts[:workspace_id] do
        nil -> q
        id -> Ash.Query.filter(q, workspace_id == ^id)
      end
    end)
    |> then(fn q ->
      case opts[:action] do
        nil -> q
        action -> Ash.Query.filter(q, action == ^action)
      end
    end)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(opts[:limit] || 50)
    |> Ash.Query.offset(opts[:offset] || 0)
    |> Ash.Query.load([:actor, :target_user, :workspace])
    |> Ash.read!(page: false)
  end
```

- [ ] **Step 4: Generate the migration**

Run: `mix ash.codegen audit_events`
Expected: a migration creating `audit_events` with the two indexes. Read it; then `mix ecto.migrate` (dev) is not needed for tests (`mix test` runs `ash.setup`).

- [ ] **Step 5: Run the test**

Run: `mix test test/teacher_assistant/accounts/audit_event_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/audit_event.ex lib/teacher_assistant/accounts/audit_event lib/teacher_assistant/accounts.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/accounts/audit_event_test.exs
git commit -m "feat(operator): audit journal resource"
```

---

### Task 2: Modules catalogue, school status fields and operator actions

**Files:**
- Create: `lib/teacher_assistant/modules.ex`, `lib/teacher_assistant/modules/key.ex`
- Modify: `lib/teacher_assistant/academics/workspace.ex`, `lib/teacher_assistant/organization.ex`, `lib/teacher_assistant/accounts/school_profile.ex`, `lib/teacher_assistant/scope.ex`, `config/config.exs`, `config/test.exs`
- Test: `test/teacher_assistant/modules_test.exs`, `test/teacher_assistant/organization/school_status_test.exs`

**Interfaces:**
- Consumes: `AuditEvent.Record` (Task 1).
- Produces:
  - `TeacherAssistant.Modules.keys/0 :: [atom]` — the six keys in display order.
  - `Modules.label(key) :: String.t()`.
  - `Modules.module_for_view(module) :: atom | :core | nil` (nil = not a school screen).
  - `Modules.module_for_controller(controller, action) :: atom | :core | nil`.
  - `Modules.new_school_default/0 :: [atom]`.
  - `Workspace` attributes `modules :: [atom]`, `suspended_at :: DateTime | nil`, `suspension_reason :: String | nil`; actions `:set_modules` (accept `modules`), `:suspend` (argument `reason`), `:reactivate`.
  - `Organization.set_modules(scope, workspace, [atom]) :: {:ok, Workspace} | {:error, term}`
  - `Organization.suspend_school(scope, workspace, reason) :: {:ok, Workspace} | {:error, term}`
  - `Organization.reactivate_school(scope, workspace) :: {:ok, Workspace} | {:error, term}`
  - `Scope.module?(scope, key) :: boolean` — true when there is no workspace.
  - `Scope.suspended?(scope) :: boolean`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/modules_test.exs`:

```elixir
defmodule TeacherAssistant.ModulesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Modules
  alias TeacherAssistantWeb.School

  test "six keys, labelled" do
    assert Modules.keys() == [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
    for key <- Modules.keys(), do: assert(is_binary(Modules.label(key)))
  end

  test "views and controller actions map to their module or the core" do
    assert Modules.module_for_view(School.BulletinsLive) == :notes
    assert Modules.module_for_view(School.AbsencesLive) == :appel
    assert Modules.module_for_view(School.SanctionsLive) == :discipline
    assert Modules.module_for_view(School.TimetableEditorLive) == :emploi_du_temps
    assert Modules.module_for_view(School.FeesLive) == :frais
    assert Modules.module_for_view(School.ClassPhotosLive) == :photos
    assert Modules.module_for_view(School.ClassesLive) == :core
    assert Modules.module_for_view(TeacherAssistantWeb.Admin.SchoolsLive) == nil

    assert Modules.module_for_controller(TeacherAssistantWeb.CardPrintController, :show) == :photos
    assert Modules.module_for_controller(TeacherAssistantWeb.StudentPhotoController, :frozen) == :notes
    assert Modules.module_for_controller(TeacherAssistantWeb.StudentPhotoController, :show) == :core
  end

  test "the new-school default is read from config" do
    assert Modules.new_school_default() ==
             Application.fetch_env!(:teacher_assistant, :new_school_modules)
  end
end
```

`test/teacher_assistant/organization/school_status_test.exs`:

```elixir
defmodule TeacherAssistant.Organization.SchoolStatusTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Organization, Scope, TeacherFixtures}

  setup do
    %{workspace: ws, scope: head} = TeacherFixtures.school_fixture()
    operator = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{ws: ws, head: head, operator: operator}
  end

  test "the operator sets modules and the change is journaled", %{ws: ws, operator: op} do
    {:ok, ws} = Organization.set_modules(op, ws, [:notes, :photos])
    assert ws.modules == [:notes, :photos]

    assert [%{action: :modules_changed, details: %{"after" => ["notes", "photos"]}}] =
             Accounts.list_audit_events(op, workspace_id: ws.id)
  end

  test "an unknown module is refused", %{ws: ws, operator: op} do
    assert {:error, _} = Organization.set_modules(op, ws, [:notes, :bogus])
  end

  test "a head cannot change modules, suspend or reactivate", %{ws: ws, head: head} do
    assert_forbidden(Organization.set_modules(head, ws, []))
    assert_forbidden(Organization.suspend_school(head, ws, "x"))
    assert_forbidden(Organization.reactivate_school(head, ws))
  end

  test "suspend needs a reason; reactivate clears it", %{ws: ws, operator: op} do
    assert {:error, _} = Organization.suspend_school(op, ws, "  ")
    {:ok, ws} = Organization.suspend_school(op, ws, "Impayé")
    assert ws.suspended_at && ws.suspension_reason == "Impayé"
    {:ok, ws} = Organization.reactivate_school(op, ws)
    assert ws.suspended_at == nil and ws.suspension_reason == nil

    assert [:school_reactivated, :school_suspended] =
             op |> Accounts.list_audit_events(workspace_id: ws.id) |> Enum.map(& &1.action)
  end

  test "the scope answers module? and suspended?", %{ws: ws, head: head, operator: op} do
    {:ok, _} = Organization.set_modules(op, ws, [:appel])
    scope = school_scope(head.current_user, ws)
    assert Scope.module?(scope, :appel)
    refute Scope.module?(scope, :notes)
    refute Scope.suspended?(scope)
    assert Scope.module?(%Scope{}, :notes)
  end

  test "create_school ignores a modules attribute" do
    user = TeacherFixtures.user_fixture()

    assert {:ok, ws} =
             Organization.create_school(%Scope{current_user: user}, %{name: "X", modules: []})

    assert ws.modules == TeacherAssistant.Modules.new_school_default()
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/modules_test.exs test/teacher_assistant/organization/school_status_test.exs`
Expected: FAIL — `TeacherAssistant.Modules` undefined.

- [ ] **Step 3: Implement the catalogue**

`lib/teacher_assistant/modules/key.ex`:

```elixir
defmodule TeacherAssistant.Modules.Key do
  use Ash.Type.Enum, values: [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
end
```

`lib/teacher_assistant/modules.ex`:

```elixir
defmodule TeacherAssistant.Modules do
  @moduledoc """
  The switchable parts of the product (operator console spec §1): which LiveViews and
  controller actions each module owns. Everything listed under `@core` is always on.
  This map is the single source for the route guard, the controller plug, the menus
  and the router coverage test.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistantWeb, as: W

  @keys [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]

  @views %{
    notes: [
      W.Teacher.RosterLive,
      W.Teacher.MarksLive,
      W.Teacher.MarksSummaryLive,
      W.School.ResultsLive,
      W.School.BulletinLive,
      W.School.BulletinsLive,
      W.School.CouncilsLive,
      W.School.CouncilLive,
      W.School.CorrectionsLive,
      W.School.CorrectionReviewLive,
      W.School.SequenceTrackingLive,
      W.School.EvaluationsLive,
      W.School.CoefficientsLive,
      W.School.AppreciationsLive,
      W.School.PassageLive,
      W.School.BulletinTemplateLive
    ],
    appel: [W.School.AttendanceLive, W.School.RegisterLive, W.School.DayLive, W.School.AbsencesLive],
    discipline: [
      W.School.DisciplineLive,
      W.School.ConductLive,
      W.School.SanctionsLive,
      W.School.SchoolLifeSettingsLive
    ],
    emploi_du_temps: [W.School.TimetableLive, W.School.TimetableEditorLive, W.School.MyTimetableLive],
    frais: [W.School.FeesLive],
    photos: [W.School.ClassPhotosLive]
  }

  @controllers %{
    {W.BulletinPrintController, :show} => :notes,
    {W.BulletinPrintController, :class} => :notes,
    {W.CouncilPrintController, :show} => :notes,
    {W.StudentPhotoController, :frozen} => :notes,
    {W.TimetablePrintController, :class} => :emploi_du_temps,
    {W.TimetablePrintController, :me} => :emploi_du_temps,
    {W.CardPrintController, :show} => :photos,
    {W.StudentPhotoController, :show} => :core,
    {W.SchoolLogoController, :show} => :core
  }

  @core [
    W.School.DashboardLive,
    W.School.CoursesLive,
    W.School.ClassesLive,
    W.School.ClassLive,
    W.School.TeachingsLive,
    W.School.MyDayLive,
    W.School.StudentsLive,
    W.School.StudentLive,
    W.School.EnrollImportLive,
    W.School.MembersLive,
    W.School.SettingsLive,
    W.School.OfficialHeaderLive,
    W.School.RolesLive,
    W.School.NewYearLive,
    W.School.YearLive,
    W.School.HolidaysLive,
    W.School.AssignmentsLive,
    W.School.PeriodsLive,
    W.School.NotificationsLive,
    W.School.SuspendedLive,
    W.Onboarding.SetupWizardLive
  ]

  @by_view for {key, views} <- @views, view <- views, into: %{}, do: {view, key}

  def keys, do: @keys

  def label(:notes), do: gettext("Notes et bulletins")
  def label(:appel), do: gettext("Appel et absences")
  def label(:discipline), do: gettext("Discipline")
  def label(:emploi_du_temps), do: gettext("Emploi du temps")
  def label(:frais), do: gettext("Frais de scolarité")
  def label(:photos), do: gettext("Photos et cartes")

  @doc "The module a LiveView belongs to, `:core`, or nil when it is not a school screen."
  def module_for_view(view) do
    cond do
      key = @by_view[view] -> key
      view in @core -> :core
      true -> nil
    end
  end

  @doc "The module a school controller action belongs to, `:core`, or nil."
  def module_for_controller(controller, action), do: @controllers[{controller, action}]

  @doc "Modules a newly created school starts with (config `:new_school_modules`)."
  def new_school_default, do: Application.fetch_env!(:teacher_assistant, :new_school_modules)
end
```

Note: `W.School.SuspendedLive` is created in Task 5; until then the atom is just an atom in a list, which compiles fine.

Config — `config/config.exs` (near the other `:teacher_assistant` keys):

```elixir
# Modules a new school starts with (operator console spec §1): none; the operator enables them.
config :teacher_assistant, :new_school_modules, []
```

`config/test.exs`:

```elixir
# Tests create schools directly and use every screen.
config :teacher_assistant, :new_school_modules,
  [:notes, :appel, :discipline, :emploi_du_temps, :frais, :photos]
```

- [ ] **Step 4: Workspace fields and actions**

In `lib/teacher_assistant/academics/workspace.ex`:

Inside `actions do`, change `create :create_school do` to also set the default:

```elixir
    create :create_school do
      accept [:name]
      argument :profile, :map, default: %{}

      change set_attribute(:modules, &TeacherAssistant.Modules.new_school_default/0)
      # … existing after_action unchanged …
```

Add after `:create_school`:

```elixir
    update :set_modules do
      accept [:modules]
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :modules_changed}
    end

    update :suspend do
      accept []
      argument :reason, :string, allow_nil?: false, constraints: [max_length: 500, trim?: true]
      change set_attribute(:suspended_at, &DateTime.utc_now/0)
      change set_attribute(:suspension_reason, arg(:reason))
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_suspended}
    end

    update :reactivate do
      accept []
      change set_attribute(:suspended_at, nil)
      change set_attribute(:suspension_reason, nil)
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_reactivated}
    end
```

`trim?: true` turns `"  "` into `nil`, which `allow_nil?: false` refuses.

Inside `policies do`:

```elixir
    policy action([:set_modules, :suspend, :reactivate]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
```

Inside `attributes do`:

```elixir
    attribute :modules, {:array, TeacherAssistant.Modules.Key},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :suspended_at, :utc_datetime, allow_nil?: true, public?: true
    attribute :suspension_reason, :string, allow_nil?: true, public?: true
```

- [ ] **Step 5: Domain functions and scope helpers**

`lib/teacher_assistant/organization.ex`, after `create_school/2`:

```elixir
  @doc "Replaces a school's modules (operator only, journaled)."
  def set_modules(%Scope{} = scope, %Workspace{} = ws, modules) when is_list(modules) do
    ws |> Ash.Changeset.for_update(:set_modules, %{modules: modules}, scope: scope) |> Ash.update()
  end

  @doc "Suspends a school with a reason (operator only, journaled)."
  def suspend_school(%Scope{} = scope, %Workspace{} = ws, reason) do
    ws |> Ash.Changeset.for_update(:suspend, %{reason: reason}, scope: scope) |> Ash.update()
  end

  @doc "Lifts a school's suspension (operator only, journaled)."
  def reactivate_school(%Scope{} = scope, %Workspace{} = ws) do
    ws |> Ash.Changeset.for_update(:reactivate, %{}, scope: scope) |> Ash.update()
  end
```

The operator's scope has no workspace; `Ash.Scope.ToOpts.get_tenant` returns `:error` for it, and `Workspace` is not multitenant, so no tenant is needed.

`lib/teacher_assistant/scope.ex`, after `school_verified?/1`:

```elixir
  @doc "Whether the school's module `key` is on. Always true outside a school."
  def module?(%__MODULE__{current_workspace: %{modules: modules}}, key), do: key in modules
  def module?(_scope, _key), do: true

  @doc "Whether the scope's school is suspended."
  def suspended?(%__MODULE__{current_workspace: %{suspended_at: %DateTime{}}}), do: true
  def suspended?(_scope), do: false
```

- [ ] **Step 6: Journal verification decisions**

In `lib/teacher_assistant/accounts/school_profile.ex`, add a change line to each action:

```elixir
    update :verify do
      accept [:verified_by_user_id]
      change set_attribute(:verification_status, :verified)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:rejection_reason, nil)
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_verified}
    end

    update :reject do
      accept [:verified_by_user_id, :rejection_reason]
      change set_attribute(:verification_status, :rejected)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_rejected}
    end
```

Add to `school_status_test.exs`:

```elixir
  test "verifying a school is journaled", %{head: head, operator: op} do
    TeacherFixtures.verify_school!(head)
    assert Enum.any?(Accounts.list_audit_events(op, []), &(&1.action == :school_verified))
  end
```

- [ ] **Step 7: Migration with backfill**

Run: `mix ash.codegen school_modules_and_suspension`
Then edit the generated migration's `up/0` — after the `alter table(:workspaces)` block add the backfill (the only hand edit; generated DDL stays as generated):

```elixir
    # Existing schools keep every screen they had (operator console spec §1).
    execute("""
    UPDATE workspaces
    SET modules = ARRAY['notes','appel','discipline','emploi_du_temps','frais','photos']::text[]
    """)
```

`down/0` needs no change (dropping the column drops the data).

- [ ] **Step 8: Run the tests**

Run: `mix test test/teacher_assistant/modules_test.exs test/teacher_assistant/organization/school_status_test.exs test/teacher_assistant/accounts/audit_event_test.exs`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant/modules.ex lib/teacher_assistant/modules lib/teacher_assistant/academics/workspace.ex lib/teacher_assistant/organization.ex lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/scope.ex config/config.exs config/test.exs priv/repo/migrations priv/resource_snapshots test/teacher_assistant/modules_test.exs test/teacher_assistant/organization/school_status_test.exs
git commit -m "feat(operator): school modules, suspension fields and journaled operator actions"
```

---

### Task 3: Module and suspension guards on screens and controllers

**Files:**
- Create: `lib/teacher_assistant_web/plug/school_access.ex`, `lib/teacher_assistant_web/live/school/suspended_live.ex`
- Modify: `lib/teacher_assistant_web/live_user_auth.ex`, `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`, `council_print_controller.ex`, `card_print_controller.ex`, `timetable_print_controller.ex`, `student_photo_controller.ex`, `school_logo_controller.ex`
- Test: `test/teacher_assistant_web/module_guard_test.exs`, `test/teacher_assistant_web/router_modules_test.exs`

**Interfaces:**
- Consumes: `Modules.module_for_view/1`, `Modules.module_for_controller/2`, `Scope.module?/2`, `Scope.suspended?/1`, `Organization.set_modules/3`, `Organization.suspend_school/3` (Task 2).
- Produces:
  - `on_mount {TeacherAssistantWeb.LiveUserAuth, :require_active_school}` and `{…, :require_module}`.
  - Plug `TeacherAssistantWeb.Plug.SchoolAccess` (no options).
  - Route `live "/school/suspended", School.SuspendedLive` (DOM id `#school-suspended`, reason `#suspension-reason`).
  - Flash text for a refused module: « Ce module n'est pas activé pour votre établissement. »

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/router_modules_test.exs`:

```elixir
defmodule TeacherAssistantWeb.RouterModulesTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Modules

  test "every /school and /teacher screen is core or belongs to a module" do
    unmapped =
      for route <- TeacherAssistantWeb.Router.__routes__(),
          String.starts_with?(route.path, ["/school", "/teacher"]),
          target = target(route),
          target != :skip,
          mapped(target) == nil,
          do: {route.path, target}

    assert unmapped == []
  end

  # Navigation controllers only set a session value and redirect.
  @navigation [
    TeacherAssistantWeb.SpaceController,
    TeacherAssistantWeb.TeacherContextController
  ]

  defp target(%{metadata: %{phoenix_live_view: {view, _action, _opts, _extra}}}), do: {:view, view}
  defp target(%{plug: plug}) when plug in @navigation, do: :skip
  defp target(%{plug: plug, plug_opts: action}), do: {:controller, plug, action}

  defp mapped({:view, view}), do: Modules.module_for_view(view)
  defp mapped({:controller, c, a}), do: Modules.module_for_controller(c, a)
end
```

`test/teacher_assistant_web/module_guard_test.exs`:

```elixir
defmodule TeacherAssistantWeb.ModuleGuardTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Organization, Scope, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{workspace: ws} do
    %{operator: %Scope{current_user: TeacherFixtures.admin_user_fixture()}, ws: ws}
  end

  test "a screen of an off module is refused when typed", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])

    assert {:error, {:live_redirect, %{to: "/school", flash: flash}}} =
             live(conn, ~p"/school/sanctions")

    assert flash["error"] =~ "pas activé"
  end

  test "a screen of an on module opens", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:discipline])
    assert {:ok, _view, _html} = live(conn, ~p"/school/sanctions")
  end

  test "a core screen opens with no module", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [])
    assert {:ok, _view, _html} = live(conn, ~p"/school/classes")
  end

  test "a print route of an off module redirects", %{conn: conn, operator: op, ws: ws, scope: scope} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])
    [cg | _] = TeacherAssistant.Enrollment.list_class_groups(scope, scope.current_academic_year)
    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    assert redirected_to(conn) == "/school"
  end

  test "a suspended school's member lands on the suspended page", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")

    assert {:error, {:live_redirect, %{to: "/school/suspended"}}} = live(conn, ~p"/school/classes")

    {:ok, view, _html} = live(conn, ~p"/school/suspended")
    assert has_element?(view, "#suspension-reason", "Impayé")
  end

  test "a suspended school's print route redirects", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    conn = get(conn, ~p"/school/logo")
    assert redirected_to(conn) == "/school/suspended"
  end

  test "the suspended page sends an active school's member home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/suspended")
  end

  test "bulletin verification ignores suspension", %{operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    conn = get(Phoenix.ConnTest.build_conn(), ~p"/verify/bulletin/unknown-token")
    refute redirected_to_suspended?(conn)
  end

  defp redirected_to_suspended?(%{status: 302} = conn), do: redirected_to(conn) == "/school/suspended"
  defp redirected_to_suspended?(_conn), do: false
end
```

Add, in the same file, the Review Focus test (item 2):

```elixir
  test "a member switches from a suspended school to another", %{conn: conn, operator: op, ws: ws, actor: head} do
    %{workspace: other} = TeacherFixtures.school_fixture(%{head_user: head})
    TeacherFixtures.complete_school_setup!(school_scope(head, other))
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")

    conn = get(conn, ~p"/workspaces/select/#{other.id}")
    assert {:ok, _view, _html} = live(recycle(conn), ~p"/school/classes")
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant_web/router_modules_test.exs test/teacher_assistant_web/module_guard_test.exs`
Expected: FAIL (the guard test opens `/school/sanctions`; the router test lists `/school/suspended` as missing once the route exists — before that, other failures).

- [ ] **Step 3: on_mount hooks**

In `lib/teacher_assistant_web/live_user_auth.ex`, add after `on_mount(:require_school_setup, …)`:

```elixir
  # Operator console spec §2: a suspended school's members wait on /school/suspended.
  def on_mount(:require_active_school, _params, _session, socket) do
    if TeacherAssistant.Scope.suspended?(socket.assigns.current_scope),
      do: {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school/suspended")},
      else: {:cont, socket}
  end

  # Operator console spec §1: a screen of a module the school does not have is refused,
  # typed URL included. Menus hide it too, but this is the guard.
  def on_mount(:require_module, _params, _session, socket) do
    case TeacherAssistant.Modules.module_for_view(socket.view) do
      key when key in [nil, :core] ->
        {:cont, socket}

      key ->
        if TeacherAssistant.Scope.module?(socket.assigns.current_scope, key) do
          {:cont, socket}
        else
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(
             :error,
             Gettext.gettext(TeacherAssistantWeb.Gettext, "Ce module n'est pas activé pour votre établissement.")
           )
           |> Phoenix.LiveView.push_navigate(to: ~p"/school")}
        end
    end
  end
```

Use `use Gettext, backend: TeacherAssistantWeb.Gettext` at the top of the module instead of the fully qualified call if the module does not already have it; then write `gettext("Ce module n'est pas activé pour votre établissement.")`.

- [ ] **Step 4: Router**

In `lib/teacher_assistant_web/router.ex`, in both the `:teaching` and `:school_workspace` live sessions, insert the two hooks right after `{TeacherAssistantWeb.LiveUserAuth, :live_user_required}`:

```elixir
        {TeacherAssistantWeb.LiveUserAuth, :require_active_school},
        {TeacherAssistantWeb.LiveUserAuth, :require_module},
```

Add a new live session (after `:account`) for the suspended page — it must not carry `:require_active_school`:

```elixir
    ash_authentication_live_session :suspended,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/school/suspended", School.SuspendedLive
    end
```

- [ ] **Step 5: Suspended page**

`lib/teacher_assistant_web/live/school/suspended_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.SuspendedLive do
  @moduledoc "Operator console spec §2: where a suspended school's members wait."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Scope

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Scope.suspended?(scope),
      do: {:ok, assign(socket, :reason, scope.current_workspace.suspension_reason)},
      else: {:ok, push_navigate(socket, to: ~p"/school")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="school-suspended" class="mx-auto max-w-xl space-y-4">
        <.page_header
          eyebrow={@current_scope.current_workspace.name}
          title={gettext("Établissement suspendu")}
        />
        <p class="ta-leaf p-4">
          <span class="block text-sm text-base-content/70">{gettext("Motif")}</span>
          <span id="suspension-reason">{@reason}</span>
        </p>
        <p class="text-sm text-base-content/70">
          {gettext("Contactez l'administrateur de Teacher Assistant pour rétablir l'accès. Si vous appartenez à un autre établissement, choisissez-le dans le menu.")}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 6: Controller plug**

`lib/teacher_assistant_web/plug/school_access.ex`:

```elixir
defmodule TeacherAssistantWeb.Plug.SchoolAccess do
  @moduledoc """
  Operator console spec §1–2 for controller routes: a suspended school's member goes to
  `/school/suspended`; an action of a module the school does not have redirects home.
  Used inside each school controller (`plug TeacherAssistantWeb.Plug.SchoolAccess`), where
  the controller and action are known.
  """
  @behaviour Plug

  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias TeacherAssistant.{Modules, Scope}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    key = Modules.module_for_controller(controller_module(conn), action_name(conn))

    cond do
      Scope.suspended?(scope) ->
        conn |> redirect(to: ~p"/school/suspended") |> halt()

      key in [nil, :core] or Scope.module?(scope, key) ->
        conn

      true ->
        conn
        |> put_flash(:error, gettext("Ce module n'est pas activé pour votre établissement."))
        |> redirect(to: ~p"/school")
        |> halt()
    end
  end
end
```

In each of `BulletinPrintController`, `CouncilPrintController`, `CardPrintController`, `TimetablePrintController`, `StudentPhotoController`, `SchoolLogoController`, add right after `use TeacherAssistantWeb, :controller`:

```elixir
  plug TeacherAssistantWeb.Plug.SchoolAccess
```

- [ ] **Step 7: Run the tests**

Run: `mix test test/teacher_assistant_web/router_modules_test.exs test/teacher_assistant_web/module_guard_test.exs`
Expected: all pass. If the router test lists a route, add its view/controller to `@views`, `@controllers` or `@core` in `TeacherAssistant.Modules` according to spec §1 (do not loosen the test).

Then run the whole suite: `mix test` — expected 0 failures (test config enables every module).

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/live_user_auth.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/plug/school_access.ex lib/teacher_assistant_web/live/school/suspended_live.ex lib/teacher_assistant_web/controllers test/teacher_assistant_web/router_modules_test.exs test/teacher_assistant_web/module_guard_test.exs
git commit -m "feat(operator): guard screens and print routes by module and suspension"
```

---

### Task 4: Menus, shared screens, settings card and jobs follow the modules

**Files:**
- Modify: `lib/teacher_assistant_web/spaces.ex`, `lib/teacher_assistant_web/live/school/class_shell.ex`, `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`, `lib/teacher_assistant_web/live/school/student_live.ex`, `lib/teacher_assistant_web/live/school/my_day_live.ex`, `lib/teacher_assistant_web/live/school/dashboard_live.ex`, `lib/teacher_assistant_web/live/school/settings_live.ex`, `lib/teacher_assistant/accounts/workspaces.ex`, `lib/teacher_assistant/workers/missed_roll_calls.ex`
- Test: `test/teacher_assistant_web/spaces_test.exs` (extend), `test/teacher_assistant_web/live/school/modules_ui_test.exs` (create), `test/teacher_assistant/workers/missed_roll_calls_test.exs` (extend)

**Interfaces:**
- Consumes: `Modules.module_for_view/1`, `Modules.module_for_controller/2`, `Modules.keys/0`, `Modules.label/1`, `Scope.module?/2`, `Scope.suspended?/1`.
- Produces: `TeacherAssistantWeb.Spaces.path_allowed?(scope, path) :: boolean` (used by the class shell); settings card DOM id `#school-modules` with one `#school-module-<key>` per active module.

- [ ] **Step 1: Read the files you will change**

Read `lib/teacher_assistant_web/live/school/class_shell.ex` (its tab list), `my_day_live.ex` and `dashboard_live.ex` (their cards), `student_live.ex` (discipline section), and `bulletin_print_html/show.html.heex` (absence and conduct blocks) before writing tests — the tests below name their DOM ids; adjust the ids in the tests to the ones in the file, never the other way round.

- [ ] **Step 2: Write the failing tests**

Extend `test/teacher_assistant_web/spaces_test.exs`:

```elixir
  describe "modules" do
    test "items of an off module are dropped from the menu" do
      %{scope: scope} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()
      op = %TeacherAssistant.Scope{current_user: TeacherAssistant.TeacherFixtures.admin_user_fixture()}
      {:ok, ws} = TeacherAssistant.Organization.set_modules(op, scope.current_workspace, [:appel])
      scope = %{scope | current_workspace: ws}

      paths =
        scope
        |> TeacherAssistantWeb.Spaces.put_space(nil)
        |> get_in([Access.key(:capabilities), :space, :sections])
        |> Enum.flat_map(& &1.items)
        |> Enum.map(& &1.path)

      refute "/school/bulletins" in paths
      refute "/school/sequences" in paths
      assert "/school/classes" in paths
    end
  end
```

`test/teacher_assistant_web/live/school/modules_ui_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.ModulesUiTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Organization, Scope, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{workspace: ws} do
    %{op: %Scope{current_user: TeacherFixtures.admin_user_fixture()}, ws: ws}
  end

  test "a school with no modules still opens its dashboard", %{conn: conn, op: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [])
    assert {:ok, _view, _html} = live(conn, ~p"/school")
  end

  test "the class page hides the tabs of off modules", %{conn: conn, op: op, ws: ws, scope: scope} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])
    [cg | _] = Enrollment.list_class_groups(scope, scope.current_academic_year)
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, ~s|a[href="/school/classes/#{cg.id}/results"]|)
    refute has_element?(view, ~s|a[href="/school/classes/#{cg.id}/discipline"]|)
    refute has_element?(view, ~s|a[href="/school/classes/#{cg.id}/photos"]|)
  end

  test "settings lists the active modules, read only", %{conn: conn, op: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes, :appel])
    {:ok, view, _html} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#school-module-notes")
    assert has_element?(view, "#school-module-appel")
    refute has_element?(view, "#school-module-frais")
    refute has_element?(view, "#school-modules input")
  end
end
```

Extend `test/teacher_assistant/workers/missed_roll_calls_test.exs` (read it first for its setup helpers) with:

```elixir
  test "a school without the roll call module is skipped" do
    calls = :counters.new(1, [])
    %{scope: scope} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()
    TeacherAssistant.TeacherFixtures.verify_school!(scope)
    op = %TeacherAssistant.Scope{current_user: TeacherAssistant.TeacherFixtures.admin_user_fixture()}
    {:ok, ws} = TeacherAssistant.Organization.set_modules(op, scope.current_workspace, [:notes])

    TeacherAssistant.Workers.MissedRollCalls.run(
      [%{scope | current_workspace: ws}],
      fn _ -> :counters.add(calls, 1, 1) end
    )

    assert :counters.get(calls, 1) == 0
  end
```

And a `Workspaces.job_scopes/0` test in `test/teacher_assistant/accounts/workspaces_test.exs` (create if absent):

```elixir
defmodule TeacherAssistant.Accounts.WorkspacesTest do
  use TeacherAssistant.DataCase, async: false

  alias TeacherAssistant.{Organization, Scope, TeacherFixtures}
  alias TeacherAssistant.Accounts.Workspaces

  test "jobs skip suspended schools" do
    %{workspace: ws} = TeacherFixtures.school_fixture()
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    assert Enum.any?(Workspaces.job_scopes(), &(&1.current_workspace.id == ws.id))
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    refute Enum.any?(Workspaces.job_scopes(), &(&1.current_workspace.id == ws.id))
  end
end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `mix test test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/school/modules_ui_test.exs test/teacher_assistant/workers/missed_roll_calls_test.exs test/teacher_assistant/accounts/workspaces_test.exs`
Expected: the new tests fail.

- [ ] **Step 4: Spaces**

In `lib/teacher_assistant_web/spaces.ex`:

```elixir
  alias TeacherAssistant.{Modules, Scope}

  @doc "Whether `path` leads to a screen the scope's school has (core or an active module)."
  def path_allowed?(scope, path) do
    case Phoenix.Router.route_info(TeacherAssistantWeb.Router, "GET", path, "") do
      %{phoenix_live_view: {view, _action, _opts, _extra}} ->
        allowed?(scope, Modules.module_for_view(view))

      %{plug: controller, plug_opts: action} ->
        allowed?(scope, Modules.module_for_controller(controller, action))

      :error ->
        true
    end
  end

  defp allowed?(_scope, key) when key in [nil, :core], do: true
  defp allowed?(scope, key), do: Scope.module?(scope, key)

  defp drop_off_modules(space, scope) do
    sections =
      space.sections
      |> Enum.map(fn s -> %{s | items: Enum.filter(s.items, &path_allowed?(scope, &1.path))} end)
      |> Enum.reject(&(&1.items == []))

    %{space | sections: sections}
  end
```

In `put_space/2`, apply it:

```elixir
    space = key |> space(Map.merge(facts, counts(key, scope))) |> drop_off_modules(scope)
```

and make `space/2`'s `home` fall back to `~p"/school/classes"` when the home path is not allowed — in `put_space/2`, after `drop_off_modules`:

```elixir
    space = if path_allowed?(scope, space.home), do: space, else: %{space | home: ~p"/school/classes"}
```

In `facts/1` and `counts/2`, compute module-owned badges only when the module is on:

```elixir
      pending_corrections:
        if(Scope.module?(scope, :notes) and Assessment.can_decide_corrections?(scope),
          do: Assessment.pending_corrections_count(scope),
          else: 0
        ),
      decided_corrections:
        if(teaches? and Scope.module?(scope, :notes),
          do: Assessment.unseen_decisions_count(scope),
          else: 0
        )
```

```elixir
  def counts(key, %{current_academic_year: %{} = year} = scope)
      when key in [:proviseur, :censeur] do
    with true <- Scope.module?(scope, :notes),
         seq when not is_nil(seq) <-
           Assessment.default_sequence(Organization.list_sequences(scope, year), Reference.today()) do
      %{late_teachers: Assessment.sequence_entry_grid(scope, year, seq).late_teacher_count}
    else
      _ -> %{}
    end
  end

  def counts(:surveillant, scope) do
    today = Reference.today()
    appel? = Scope.module?(scope, :appel)

    %{
      missed_calls: if(appel?, do: length(Attendance.school_day(scope, today, Reference.now()).missed), else: 0),
      unjustified_absences: if(appel?, do: Attendance.absences_to_justify(scope, today).count, else: 0),
      parents_to_notify:
        case {Scope.module?(scope, :discipline), scope.current_academic_year} do
          {true, %{} = year} -> Discipline.count_parents_to_notify(scope, year)
          _ -> 0
        end
    }
  end

  def counts(:enseignant, %{current_user: user} = scope) do
    if Scope.module?(scope, :appel) do
      calls =
        scope
        |> Attendance.teacher_day(user, Reference.today(), Reference.now())
        |> Enum.count(&(&1.status in [:in_progress, :missed]))

      %{calls_to_do: calls}
    else
      %{}
    end
  end
```

The tab bar (`tab_bar/1`) builds from the filtered sections, so it follows automatically.

- [ ] **Step 5: Shared screens**

- `class_shell.ex`: where the tab list is built, filter it with `TeacherAssistantWeb.Spaces.path_allowed?(scope, tab.path)` (use the tab's existing path field name).
- `bulletin_print_html/show.html.heex`: wrap the absences block in `:if={TeacherAssistant.Scope.module?(@current_scope, :appel)}` and the conduct/sanctions block in `:if={TeacherAssistant.Scope.module?(@current_scope, :discipline)}`. If the template has no `@current_scope`, pass `modules: scope.current_workspace.modules` from `BulletinPrintController` into the assigns and test `:appel in @modules`.
- `student_live.ex`: guard the discipline section with `TeacherAssistant.Scope.module?(@current_scope, :discipline)`, and skip loading its data in `mount` when off.
- `my_day_live.ex` and `dashboard_live.ex`: guard each roll-call card with `:appel`, each marks/sequence card with `:notes`, each timetable card with `:emploi_du_temps`, and skip their queries in `mount` when off.

- [ ] **Step 6: Settings card**

In `settings_live.ex`, in the settings hub render (the `:index` action), add:

```heex
<section id="school-modules" class="ta-leaf space-y-2 p-4">
  <h2 class="font-semibold">{gettext("Modules")}</h2>
  <ul class="flex flex-wrap gap-2">
    <li
      :for={key <- @current_scope.current_workspace.modules}
      id={"school-module-#{key}"}
      class="badge badge-outline"
    >
      {TeacherAssistant.Modules.label(key)}
    </li>
  </ul>
  <p class="text-sm text-base-content/70">
    {gettext("Contactez l'administrateur pour en activer d'autres.")}
  </p>
</section>
```

- [ ] **Step 7: Jobs**

`lib/teacher_assistant/accounts/workspaces.ex`, in `job_scopes/0`, filter before returning:

```elixir
    |> Enum.flat_map(fn m ->
      case scope_for(m.user, m.workspace_id) do
        {:ok, scope} -> [scope]
        _ -> []
      end
    end)
    |> Enum.reject(&TeacherAssistant.Scope.suspended?/1)
```

Update its `@doc` to say suspended schools are skipped.

`lib/teacher_assistant/workers/missed_roll_calls.ex`, in `run/2`:

```elixir
    for scope <- scopes, Scope.school_verified?(scope), Scope.module?(scope, :appel) do
```

- [ ] **Step 8: Run the tests, then the suite**

Run: `mix test test/teacher_assistant_web/spaces_test.exs test/teacher_assistant_web/live/school/modules_ui_test.exs test/teacher_assistant/workers test/teacher_assistant/accounts/workspaces_test.exs`
Expected: pass. Then `mix test` — 0 failures.

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school lib/teacher_assistant_web/controllers/bulletin_print_html lib/teacher_assistant/accounts/workspaces.ex lib/teacher_assistant/workers/missed_roll_calls.ex test
git commit -m "feat(operator): menus, shared screens, settings and jobs follow the school's modules"
```

---

### Task 5: Password reset policy for heads and the operator

**Files:**
- Create: `lib/teacher_assistant/accounts/checks/head_of_acting_school.ex`, `lib/teacher_assistant/accounts/checks/head_of_members_school.ex`
- Modify: `lib/teacher_assistant/accounts/checks/active_in_another_school.ex`, `lib/teacher_assistant/accounts/user.ex`, `lib/teacher_assistant/accounts.ex`
- Test: `test/teacher_assistant/accounts/password_reset_policy_test.exs`

**Interfaces:**
- Consumes: `AuditEvent.Record` (Task 1), `Checks.SchoolRole.workspace_id/1`, `Checks.SchoolRole.holds?/3`.
- Produces:
  - `Accounts.reset_member_password(scope, membership)` — unchanged signature, now allowed for any member the policy admits.
  - `Accounts.operator_reset_password(scope, user) :: {:ok, String.t()} | {:error, term}` — returns the clear temporary password once.
  - `Accounts.can_reset_member_password?(scope, user)` — unchanged.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Accounts.PasswordResetPolicyTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Scope, TeacherFixtures}

  setup do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{head: head, op: op}
  end

  defp member(head, roles) do
    m = TeacherFixtures.membership_fixture(head, %{roles: roles})
    {:ok, m} = Ash.load(m, :user, scope: head)
    m
  end

  test "a head resets an invited (email) member", %{head: head, op: op} do
    m = member(head, [:teacher])
    assert m.user.created_in_workspace_id == nil
    assert {:ok, password} = Accounts.reset_member_password(head, m)
    assert is_binary(password)

    assert [%{action: :password_reset, target_user_id: target}] =
             Accounts.list_audit_events(op, action: :password_reset)

    assert target == m.user_id
  end

  test "a head cannot reset another head", %{head: head} do
    m = member(head, [:head])
    assert_forbidden(Accounts.reset_member_password(head, m))
  end

  test "a head cannot reset themself", %{head: head} do
    {:ok, own} = Accounts.fetch_school_membership(head, head.current_user)
    assert_forbidden(Accounts.reset_member_password(head, own))
  end

  test "a head cannot reset a member active in another school", %{head: head} do
    m = member(head, [:teacher])
    %{scope: other_head} = TeacherFixtures.school_fixture()
    TeacherFixtures.membership_fixture(other_head, %{user: m.user, roles: [:teacher]})
    assert_forbidden(Accounts.reset_member_password(head, m))
  end

  test "the operator resets anyone but an operator", %{head: head, op: op} do
    m = member(head, [:head])
    assert {:ok, _password} = Accounts.operator_reset_password(op, m.user)
    assert {:ok, _password} = Accounts.operator_reset_password(op, head.current_user)

    other_op = TeacherFixtures.admin_user_fixture()
    assert_forbidden(Accounts.operator_reset_password(op, other_op))
  end

  test "a head cannot use the operator reset", %{head: head} do
    m = member(head, [:teacher])
    assert_forbidden(Accounts.operator_reset_password(head, m.user))
  end
end
```

Check `TeacherFixtures.membership_fixture/2` accepts `%{user: user}` (read it); if it does not, add an optional `:user` key there that defaults to a fresh `user_fixture()`.

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/accounts/password_reset_policy_test.exs`
Expected: FAIL — the invited-member reset is forbidden; `operator_reset_password/2` undefined.

- [ ] **Step 3: Checks**

`lib/teacher_assistant/accounts/checks/active_in_another_school.ex` — replace `match?/3` and the moduledoc's first sentences so it compares against the **acting** school (the changeset's tenant) instead of the creating school:

```elixir
  @moduledoc """
  Policy check for `:reset_temporary_password`: the account being changed holds an
  **active** membership in a school other than the one the actor is acting in (the
  changeset's tenant). Such a person is also someone else's colleague, so this school
  must not take the account over by resetting its password (decided 2026-10-07; the
  reference school became the acting school with the operator console, 2026-10-15).

  Memberships are attribute-multitenant (`global? true`): the read below runs
  deliberately without a tenant, across every school.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole
  alias TeacherAssistant.Accounts.SchoolMembership

  @impl true
  def describe(_opts), do: "the account is active in a school other than the acting one"

  @impl true
  def match?(_actor, %{subject: %{data: %{id: user_id}} = subject}, _opts) when is_binary(user_id) do
    acting_id = SchoolRole.workspace_id(subject)

    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user_id})
    |> Ash.read!(authorize?: false)
    |> Enum.any?(&(&1.workspace_id != acting_id))
  end

  def match?(_actor, _context, _opts), do: false
```

`lib/teacher_assistant/accounts/checks/head_of_acting_school.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Checks.HeadOfActingSchool do
  @moduledoc "Policy check: the account being changed is a head of the school the actor acts in."
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "the account is a head of the acting school"

  @impl true
  def match?(_actor, %{subject: %{data: %{id: _} = target} = subject}, _opts),
    do: SchoolRole.holds?(target, SchoolRole.workspace_id(subject), :head)

  def match?(_actor, _context, _opts), do: false
end
```

`lib/teacher_assistant/accounts/checks/head_of_members_school.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Checks.HeadOfMembersSchool do
  @moduledoc """
  Policy check: the actor is an active head of the school they act in (the changeset's
  tenant), and the account being changed is an active member of that school.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "actor heads the acting school and the account is its member"

  @impl true
  def match?(actor, %{subject: %{data: %{id: _} = target} = subject}, _opts) do
    workspace_id = SchoolRole.workspace_id(subject)
    SchoolRole.holds?(actor, workspace_id, :head) and SchoolRole.holds?(target, workspace_id, :member)
  end

  def match?(_actor, _context, _opts), do: false
end
```

- [ ] **Step 4: Policy and journal on User**

In `lib/teacher_assistant/accounts/user.ex`, replace the `:reset_temporary_password` policy:

```elixir
    # Operator console spec §3, in order: never an operator's account; the operator
    # resets anyone else; never yourself; never someone active in another school;
    # never another head; a head resets an active member of the school they act in.
    policy action(:reset_temporary_password) do
      forbid_if expr(role == :admin)
      authorize_if actor_attribute_equals(:role, :admin)
      forbid_if expr(id == ^actor(:id))
      forbid_if TeacherAssistant.Accounts.Checks.ActiveInAnotherSchool
      forbid_if TeacherAssistant.Accounts.Checks.HeadOfActingSchool
      authorize_if TeacherAssistant.Accounts.Checks.HeadOfMembersSchool
    end
```

And journal the action:

```elixir
    update :reset_temporary_password do
      accept []
      require_atomic? false
      change TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword
      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :password_reset}
    end
```

`AuditEvent.Record.workspace_id/2` takes the changeset's tenant for a `User` record (the head's school) and nil for the operator.

- [ ] **Step 5: Operator reset**

In `lib/teacher_assistant/accounts.ex`, after `reset_member_password/2`:

```elixir
  @doc """
  New temporary password for any account but an operator's, by the operator (operator
  console spec §3); signs the person out everywhere. Returns the clear password once.
  """
  def operator_reset_password(%Scope{} = scope, %User{} = user) do
    with {:ok, user} <-
           user
           |> Ash.Changeset.for_update(:reset_temporary_password, %{}, scope: scope)
           |> Ash.update(),
         :ok <- revoke_all_sessions(user) do
      {:ok, user.__metadata__.temporary_password}
    end
  end
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/teacher_assistant/accounts/password_reset_policy_test.exs`
Expected: pass. Then the existing reset tests: `mix test test/teacher_assistant_web/live/school/members_live_test.exs test/teacher_assistant/accounts` — fix any test that asserted the old « only accounts this school created » rule by updating its expectation to the new spec rule (a head may now reset an invited member), not by weakening the policy.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/accounts test/teacher_assistant/accounts
git commit -m "feat(accounts): heads reset any member of their school; operator resets anyone; resets journaled"
```

---

### Task 6: Operator queries

**Files:**
- Create: `lib/teacher_assistant/operator.ex`
- Test: `test/teacher_assistant/operator_test.exs`

**Interfaces:**
- Consumes: `Workspace` fields (Task 2), `AuditEvent` (Task 1).
- Produces (every function raises `Ash.Error.Forbidden` when the actor is not an operator):
  - `Operator.overview(scope) :: %{schools: %{unverified: n, verified: n, rejected: n, suspended: n}, members: n, students: n, roll_calls_7d: n, marks_7d: n}`
  - `Operator.list_schools(scope, filters) :: [%{workspace: Workspace, profile: SchoolProfile, owner: User | nil}]` — `filters`: `%{q: string, status: :unverified | :verified | :rejected | nil, suspended: boolean | nil, module: atom | nil}`
  - `Operator.get_school(scope, id) :: {:ok, %{workspace, profile, members: [SchoolMembership with :user], counts: %{classes, students, staff}, last_activity: DateTime | nil}} | {:error, :not_found}`
  - `Operator.search_users(scope, q) :: [%{user: User, memberships: [SchoolMembership with :workspace]}]` — at most 50.
  - `Operator.get_user(scope, id) :: {:ok, User} | {:error, :not_found}`

All functions start with `ensure_operator!(scope)`, which raises `Ash.Error.Forbidden` when the actor is not an operator, then read with `authorize?: false` (the operator spans tenants).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.OperatorTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Operator, Organization, Scope, TeacherFixtures}

  setup do
    %{scope: head, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{head: head, ws: ws, op: op}
  end

  test "only the operator may call it", %{head: head} do
    assert_raise Ash.Error.Forbidden, fn -> Operator.overview(head) end
  end

  test "overview counts schools by status", %{op: op, ws: ws} do
    before = Operator.overview(op)
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    assert Operator.overview(op).schools.suspended == before.schools.suspended + 1
  end

  test "list_schools filters by name, status, suspension and module", %{op: op, ws: ws} do
    {:ok, ws} = Organization.set_modules(op, ws, [:notes])
    ids = &Enum.map(&1, fn row -> row.workspace.id end)

    assert ws.id in ids.(Operator.list_schools(op, %{q: String.slice(ws.name, 0, 5)}))
    assert ws.id in ids.(Operator.list_schools(op, %{status: :verified}))
    refute ws.id in ids.(Operator.list_schools(op, %{suspended: true}))
    assert ws.id in ids.(Operator.list_schools(op, %{module: :notes}))
    refute ws.id in ids.(Operator.list_schools(op, %{module: :frais}))
  end

  test "get_school returns members and counts", %{op: op, ws: ws, head: head} do
    {:ok, school} = Operator.get_school(op, ws.id)
    assert Enum.any?(school.members, &(&1.user_id == head.current_user.id))
    assert school.counts.classes > 0
    assert {:error, :not_found} = Operator.get_school(op, Ecto.UUID.generate())
  end

  test "search_users finds by name, email and phone", %{op: op, head: head} do
    email = to_string(head.current_user.email)
    assert [%{user: %{id: id}} | _] = Operator.search_users(op, email)
    assert id == head.current_user.id
    assert Operator.search_users(op, "") == []
  end

  test "an operator with no school opens the console", %{op: op} do
    assert %{schools: _} = Operator.overview(op)
    assert is_list(Operator.list_schools(op, %{}))
  end
end
```

`setup_complete_school_fixture/0` verifies the school (read it to confirm; if it does not, call `TeacherFixtures.verify_school!(head)` in setup).

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/operator_test.exs`
Expected: FAIL — `TeacherAssistant.Operator` undefined.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/operator.ex`:

```elixir
defmodule TeacherAssistant.Operator do
  @moduledoc """
  Reads for the operator console (operator console spec §5). The operator spans every
  school, so each function checks the actor is an operator and then reads without
  tenant and with `authorize?: false`. Never call these from a school screen.
  """
  require Ash.Query

  alias TeacherAssistant.Academics.{AttendanceEntry, ClassGroup, Enrollment, MarkEvent, Workspace}
  alias TeacherAssistant.Accounts.{Phone, SchoolMembership, SchoolProfile, User}
  alias TeacherAssistant.Scope

  @read [authorize?: false]

  def overview(%Scope{} = scope) do
    ensure_operator!(scope)
    week_ago = DateTime.add(DateTime.utc_now(), -7, :day)
    profiles = Ash.read!(SchoolProfile, @read)
    workspaces = Ash.read!(Workspace, @read)

    %{
      schools: %{
        unverified: Enum.count(profiles, &(&1.verification_status == :unverified)),
        verified: Enum.count(profiles, &(&1.verification_status == :verified)),
        rejected: Enum.count(profiles, &(&1.verification_status == :rejected)),
        suspended: Enum.count(workspaces, &(&1.suspended_at != nil))
      },
      members: SchoolMembership |> Ash.Query.filter(active == true) |> Ash.count!(@read),
      students: Enrollment |> Ash.Query.filter(academic_year.active == true) |> Ash.count!(@read),
      roll_calls_7d: AttendanceEntry |> Ash.Query.filter(inserted_at >= ^week_ago) |> Ash.count!(@read),
      marks_7d: MarkEvent |> Ash.Query.filter(inserted_at >= ^week_ago) |> Ash.count!(@read)
    }
  end

  def list_schools(%Scope{} = scope, filters) do
    ensure_operator!(scope)
    q = filters |> Map.get(:q, "") |> to_string() |> String.trim()

    SchoolProfile
    |> Ash.Query.load([:workspace, :owner_user])
    |> Ash.Query.sort(inserted_at: :desc)
    |> filter_q(q)
    |> filter_status(filters[:status])
    |> Ash.read!(@read)
    |> Enum.filter(&suspended_matches?(&1.workspace, filters[:suspended]))
    |> Enum.filter(&(filters[:module] == nil or filters[:module] in &1.workspace.modules))
    |> Enum.map(&%{workspace: &1.workspace, profile: &1, owner: &1.owner_user})
  end

  def get_school(%Scope{} = scope, id) do
    ensure_operator!(scope)

    with {:ok, %Workspace{} = ws} <- Ash.get(Workspace, id, Keyword.put(@read, :not_found_error?, false)),
         [profile] <- SchoolProfile |> Ash.Query.filter(workspace_id == ^ws.id) |> Ash.read!(@read) do
      members =
        SchoolMembership
        |> Ash.Query.filter(active == true)
        |> Ash.Query.set_tenant(ws.id)
        |> Ash.Query.load(:user)
        |> Ash.read!(@read)

      {:ok,
       %{
         workspace: ws,
         profile: profile,
         members: members,
         counts: %{
           classes: ClassGroup |> Ash.Query.set_tenant(ws.id) |> Ash.count!(@read),
           students:
             Enrollment
             |> Ash.Query.set_tenant(ws.id)
             |> Ash.Query.filter(academic_year.active == true)
             |> Ash.count!(@read),
           staff: length(members)
         },
         last_activity: last_activity(ws.id)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def search_users(%Scope{} = scope, q) do
    ensure_operator!(scope)
    q = q |> to_string() |> String.trim()

    if q == "" do
      []
    else
      like = "%#{q}%"

      phone =
        case Phone.normalize(q) do
          {:ok, p} -> p
          _ -> nil
        end

      User
      |> Ash.Query.filter(
        ilike(name, ^like) or ilike(type(email, :string), ^like) or
          (not is_nil(^phone) and phone == ^phone)
      )
      |> Ash.Query.limit(50)
      |> Ash.read!(@read)
      |> Enum.map(fn user -> %{user: user, memberships: memberships_of(user)} end)
    end
  end

  def get_user(%Scope{} = scope, id) do
    ensure_operator!(scope)

    case Ash.get(User, id, Keyword.put(@read, :not_found_error?, false)) do
      {:ok, %User{} = user} -> {:ok, user}
      _ -> {:error, :not_found}
    end
  end

  defp memberships_of(user) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
    |> Ash.read!(@read)
  end

  defp last_activity(workspace_id) do
    [AttendanceEntry, MarkEvent]
    |> Enum.map(fn resource ->
      resource
      |> Ash.Query.set_tenant(workspace_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!(@read)
      |> List.first()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.inserted_at)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp filter_q(query, ""), do: query

  defp filter_q(query, q) do
    like = "%#{q}%"
    Ash.Query.filter(query, ilike(workspace.name, ^like) or ilike(town, ^like))
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: Ash.Query.filter(query, verification_status == ^status)

  defp suspended_matches?(_ws, nil), do: true
  defp suspended_matches?(ws, true), do: ws.suspended_at != nil
  defp suspended_matches?(ws, false), do: ws.suspended_at == nil

  defp ensure_operator!(%Scope{current_user: %User{role: :admin}}), do: :ok

  defp ensure_operator!(_scope),
    do: raise(Ash.Error.Forbidden.exception(errors: [Ash.Error.Forbidden.Policy.exception([])]))
end
```

Before running, confirm names against the code and adjust the code (not the spec):
- `SchoolProfile` relationships `:workspace` and `:owner_user` (used by today's `SchoolsLive` as `p.workspace` and `p.owner_user`) and its `inserted_at`.
- `Enrollment` has an `academic_year` relationship (yes — `reference :academic_year`).
- `AttendanceEntry` and `MarkEvent` have `inserted_at` (MarkEvent: yes).
- `Phone.normalize/1` exists (`docs/superpowers/specs/2026-10-07-phone-accounts-design.md`).
- `Ash.Error.Forbidden.Policy.exception([])` builds; if not, use `Ash.Error.Forbidden.exception([])`.

- [ ] **Step 4: Run the tests**

Run: `mix test test/teacher_assistant/operator_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/operator.ex test/teacher_assistant/operator_test.exs
git commit -m "feat(operator): cross-school queries for the console"
```

---

### Task 7: Console pages — overview, schools, school detail

**Files:**
- Create: `lib/teacher_assistant_web/live/admin/overview_live.ex`, `lib/teacher_assistant_web/live/admin/school_live.ex`, `lib/teacher_assistant_web/live/admin/reset_modal.ex`
- Rewrite: `lib/teacher_assistant_web/live/admin/schools_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/components/layouts.ex`
- Test: `test/teacher_assistant_web/live/admin/overview_live_test.exs`, `test/teacher_assistant_web/live/admin/schools_live_test.exs` (rewrite), `test/teacher_assistant_web/live/admin/school_live_test.exs`

**Interfaces:**
- Consumes: `Operator.*` (Task 6), `Organization.set_modules/3`, `suspend_school/3`, `reactivate_school/2` (Task 2), `Accounts.verify_school/3`, `Accounts.reject_school/4` (existing), `Accounts.operator_reset_password/2` (Task 5), `Accounts.list_audit_events/2` (Task 1).
- Produces: routes `/admin`, `/admin/schools`, `/admin/schools/:id`; `TeacherAssistantWeb.Admin.ResetModal.reset_modal/1` component (attrs: `user`, `password`, `on_confirm`, `on_cancel`) used again in Task 8; DOM ids listed in the tests.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/admin/overview_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Admin.OverviewLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  defp signed_in(conn, user),
    do: conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, user.id)

  test "an operator with no school opens the console", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    {:ok, view, _html} = live(signed_in(conn, op), ~p"/admin")
    assert has_element?(view, "#admin-overview")
    assert has_element?(view, "#overview-schools-unverified")
    assert has_element?(view, "#nav-admin-schools")
  end

  test "a non-operator is redirected", %{conn: conn} do
    user = TeacherFixtures.user_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(conn, user), ~p"/admin")
  end
end
```

`test/teacher_assistant_web/live/admin/schools_live_test.exs` (replace the file):

```elixir
defmodule TeacherAssistantWeb.Admin.SchoolsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  defp signed_in(conn, user),
    do: conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, user.id)

  test "a non-admin is redirected", %{conn: conn} do
    user = TeacherFixtures.user_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(conn, user), ~p"/admin/schools")
  end

  test "lists schools and filters to those awaiting verification", %{conn: conn} do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture(%{name: "Lycée Op"})
    op = TeacherFixtures.admin_user_fixture()
    {:ok, view, html} = live(signed_in(conn, op), ~p"/admin/schools")
    assert html =~ "Lycée Op"
    assert html =~ to_string(head.email)

    view |> form("#schools-filter", %{"status" => "unverified"}) |> render_change()
    assert has_element?(view, "#school-row-#{ws.id}")

    view |> form("#schools-filter", %{"status" => "verified"}) |> render_change()
    refute has_element?(view, "#school-row-#{ws.id}")
  end
end
```

`test/teacher_assistant_web/live/admin/school_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Admin.SchoolLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Organization, Scope, TeacherFixtures}

  setup %{conn: conn} do
    %{workspace: ws, head_user: head, scope: head_scope} = TeacherFixtures.school_fixture()
    op = TeacherFixtures.admin_user_fixture()

    conn =
      conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, op.id)

    %{conn: conn, ws: ws, head: head, head_scope: head_scope, op: %Scope{current_user: op}}
  end

  test "verifies the school", %{conn: conn, ws: ws, head: head} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> element("#verify-school") |> render_click()
    {:ok, p} = Accounts.fetch_school_profile(school_scope(head, ws))
    assert p.verification_status == :verified
  end

  test "saves modules", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> form("#modules-form", %{"modules" => ["notes", "photos"]}) |> render_submit()
    {:ok, %{workspace: ws}} = TeacherAssistant.Operator.get_school(op, ws.id)
    assert ws.modules == [:notes, :photos]
  end

  test "saving with every box unchecked clears the modules", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> form("#modules-form", %{}) |> render_submit()
    {:ok, %{workspace: ws}} = TeacherAssistant.Operator.get_school(op, ws.id)
    assert ws.modules == []
  end

  test "suspends with a reason, then reactivates", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> form("#suspend-form", %{"reason" => "Impayé"}) |> render_submit()
    assert has_element?(view, "#school-suspended-badge")
    view |> element("#reactivate-school") |> render_click()
    refute has_element?(view, "#school-suspended-badge")

    assert [:school_reactivated, :school_suspended | _] =
             op |> Accounts.list_audit_events(workspace_id: ws.id) |> Enum.map(& &1.action)
  end

  test "an empty reason is refused", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    html = view |> form("#suspend-form", %{"reason" => " "}) |> render_submit()
    assert html =~ "motif"
    refute has_element?(view, "#school-suspended-badge")
  end

  test "resets a member's password and shows it once", %{conn: conn, ws: ws, head: head} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> element("#reset-user-#{head.id}") |> render_click()
    view |> element("#reset-confirm") |> render_click()
    assert has_element?(view, "#reset-password-value")
    view |> element("#reset-close") |> render_click()
    refute has_element?(view, "#reset-password-value")
  end

  test "an unknown school goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/schools"}}} =
             live(conn, ~p"/admin/schools/#{Ecto.UUID.generate()}")
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant_web/live/admin`
Expected: FAIL (routes missing).

- [ ] **Step 3: Routes**

In `router.ex`, the `:operator` live session becomes:

```elixir
    ash_authentication_live_session :operator,
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_operator}
      ] do
      live "/admin", Admin.OverviewLive
      live "/admin/schools", Admin.SchoolsLive
      live "/admin/schools/:id", Admin.SchoolLive
      live "/admin/users", Admin.UsersLive
      live "/admin/journal", Admin.JournalLive
    end
```

`UsersLive` and `JournalLive` arrive in Task 8; until then create both as minimal modules so the router compiles:

```elixir
defmodule TeacherAssistantWeb.Admin.UsersLive do
  use TeacherAssistantWeb, :live_view
  def mount(_params, _session, socket), do: {:ok, socket}
  def render(assigns), do: ~H"<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}></Layouts.app>"
end
```

(and the same for `JournalLive`). Task 8 replaces both files entirely.

- [ ] **Step 4: Rail group**

In `lib/teacher_assistant_web/components/layouts.ex`, in `app/1` assigns add:

```elixir
      |> assign(:operator?, current_user != nil and current_user.role == :admin)
```

and, right after the `</nav>` that closes `#school-nav`, add:

```heex
            <nav :if={@operator?} id="admin-nav" class="flex flex-col gap-0.5" aria-label={gettext("Administration")}>
              <p class="ta-rail__label px-1.5 pb-1 pt-2">{gettext("Administration")}</p>
              <.rail_link id="nav-admin-overview" href={~p"/admin"} icon="hero-chart-pie" current_path={@current_path}>
                {gettext("Vue d'ensemble")}
              </.rail_link>
              <.rail_link id="nav-admin-schools" href={~p"/admin/schools"} icon="hero-building-library" current_path={@current_path}>
                {gettext("Établissements")}
              </.rail_link>
              <.rail_link id="nav-admin-users" href={~p"/admin/users"} icon="hero-users" current_path={@current_path}>
                {gettext("Utilisateurs")}
              </.rail_link>
              <.rail_link id="nav-admin-journal" href={~p"/admin/journal"} icon="hero-document-text" current_path={@current_path}>
                {gettext("Journal")}
              </.rail_link>
            </nav>
```

Read `rail_link/1` first: if it requires `badge`/`badge_tone`, pass `badge={nil}`.

- [ ] **Step 5: Reset modal component**

`lib/teacher_assistant_web/live/admin/reset_modal.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.ResetModal do
  @moduledoc """
  Operator console spec §3: confirm a password reset, then show the temporary password
  once with a ready-to-send message. The clear password lives only in the LiveView's
  assigns until the modal is closed.
  """
  use TeacherAssistantWeb, :html

  attr :user, :map, required: true
  attr :password, :string, default: nil

  def reset_modal(assigns) do
    ~H"""
    <div id="reset-modal" class="modal modal-open" phx-window-keydown="reset_cancel" phx-key="Escape">
      <div class="modal-box space-y-4">
        <h2 class="font-semibold">
          {gettext("Réinitialiser le mot de passe de %{name}", name: TeacherAssistant.Accounts.User.display_name(@user))}
        </h2>

        <%= if @password do %>
          <p class="text-sm">{gettext("Mot de passe temporaire, affiché une seule fois :")}</p>
          <p id="reset-password-value" class="ta-num text-2xl font-semibold tracking-wider">{@password}</p>
          <textarea id="reset-message" readonly class="textarea textarea-bordered w-full text-sm">{gettext("Votre mot de passe temporaire Teacher Assistant : %{password}. Il est valable 7 jours ; vous en choisirez un nouveau à la connexion.", password: @password)}</textarea>
          <div class="modal-action">
            <button id="reset-close" type="button" class="btn btn-primary" phx-click="reset_cancel">
              {gettext("Fermer")}
            </button>
          </div>
        <% else %>
          <p class="text-sm">
            {gettext("Un mot de passe temporaire valable 7 jours remplacera l'actuel. La personne sera déconnectée de tous ses appareils.")}
          </p>
          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="reset_cancel">{gettext("Annuler")}</button>
            <button id="reset-confirm" type="button" class="btn btn-primary" phx-click="reset_confirm">
              {gettext("Réinitialiser")}
            </button>
          </div>
        <% end %>
      </div>
      <div class="modal-backdrop" phx-click="reset_cancel"></div>
    </div>
    """
  end
end
```

- [ ] **Step 6: Overview page**

`lib/teacher_assistant_web/live/admin/overview_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.OverviewLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Operator}
  alias TeacherAssistant.Accounts.AuditEvent

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     assign(socket,
       overview: Operator.overview(scope),
       events: Accounts.list_audit_events(scope, limit: 10)
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-overview" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Vue d'ensemble")} />

        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <.link
            :for={{status, label} <- [unverified: gettext("À vérifier"), verified: gettext("Vérifiés"), rejected: gettext("Rejetés")]}
            id={"overview-schools-#{status}"}
            navigate={~p"/admin/schools?status=#{status}"}
            class="ta-leaf p-4"
          >
            <span class="ta-num block text-2xl font-semibold">{@overview.schools[status]}</span>
            <span class="text-sm text-base-content/70">{label}</span>
          </.link>
          <.link id="overview-schools-suspended" navigate={~p"/admin/schools?suspended=1"} class="ta-leaf p-4">
            <span class="ta-num block text-2xl font-semibold">{@overview.schools.suspended}</span>
            <span class="text-sm text-base-content/70">{gettext("Suspendus")}</span>
          </.link>
        </div>

        <dl class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div :for={{key, label} <- [members: gettext("Membres actifs"), students: gettext("Élèves inscrits"), roll_calls_7d: gettext("Appels (7 jours)"), marks_7d: gettext("Notes saisies (7 jours)")]} id={"overview-#{key}"} class="ta-leaf p-4">
            <dt class="text-sm text-base-content/70">{label}</dt>
            <dd class="ta-num text-xl font-semibold">{@overview[key]}</dd>
          </div>
        </dl>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Dernières actions")}</h2>
          <ul id="overview-events" class="divide-y divide-base-300">
            <li :for={e <- @events} id={"event-#{e.id}"} class="py-2 text-sm">
              {AuditEvent.Action.label(e.action)}
              <span :if={e.workspace}> · {e.workspace.name}</span>
              <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
              <span class="text-base-content/70"> · {TeacherAssistantWeb.Dates.short_datetime(e.inserted_at)}</span>
            </li>
          </ul>
          <.link navigate={~p"/admin/journal"} class="link text-sm">{gettext("Tout le journal")}</.link>
        </section>
      </section>
    </Layouts.app>
    """
  end
end
```

Check `TeacherAssistantWeb.Dates` for the date-time formatter's real name and use it.

- [ ] **Step 7: Schools list**

Rewrite `lib/teacher_assistant_web/live/admin/schools_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.SchoolsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Modules, Operator}
  alias TeacherAssistant.Accounts.{CameroonRegion, SchoolSubsystem, SchoolType, SchoolVerificationStatus}

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    filters = %{
      q: params["q"] || "",
      status: parse_status(params["status"]),
      suspended: if(params["suspended"] == "1", do: true),
      module: parse_module(params["module"])
    }

    {:noreply,
     assign(socket,
       filters: filters,
       params: Map.take(params, ~w(q status suspended module)),
       schools: Operator.list_schools(socket.assigns.current_scope, filters)
     )}
  end

  def handle_event("filter", params, socket) do
    params = params |> Map.take(~w(q status suspended module)) |> Map.reject(fn {_k, v} -> v in ["", nil] end)
    {:noreply, push_patch(socket, to: ~p"/admin/schools?#{params}")}
  end

  defp parse_status(s) when s in ~w(unverified verified rejected), do: String.to_existing_atom(s)
  defp parse_status(_), do: nil

  defp parse_module(m) when is_binary(m) do
    case Modules.Key.match(m) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp parse_module(_), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-schools" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Établissements")} />

        <form id="schools-filter" phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-2">
          <input type="search" name="q" value={@params["q"]} placeholder={gettext("Nom ou ville")} class="input input-bordered input-sm" phx-debounce="300" />
          <select name="status" class="select select-bordered select-sm">
            <option value="">{gettext("Tous les statuts")}</option>
            <option :for={s <- [:unverified, :verified, :rejected]} value={s} selected={@filters.status == s}>
              {SchoolVerificationStatus.label(s)}
            </option>
          </select>
          <label class="label cursor-pointer gap-2 text-sm">
            <input type="checkbox" name="suspended" value="1" checked={@filters.suspended} class="checkbox checkbox-sm" />
            {gettext("Suspendus")}
          </label>
          <select name="module" class="select select-bordered select-sm">
            <option value="">{gettext("Tous les modules")}</option>
            <option :for={k <- Modules.keys()} value={k} selected={@filters.module == k}>{Modules.label(k)}</option>
          </select>
        </form>

        <.empty_state :if={@schools == []} icon="hero-building-library" title={gettext("Aucun établissement")} />

        <.link
          :for={row <- @schools}
          id={"school-row-#{row.workspace.id}"}
          navigate={~p"/admin/schools/#{row.workspace.id}"}
          class="ta-leaf block space-y-1 p-4"
        >
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="font-semibold">{row.workspace.name}</h2>
            <span class="badge badge-sm">{SchoolVerificationStatus.label(row.profile.verification_status)}</span>
            <span :if={row.workspace.suspended_at} class="badge badge-error badge-sm">{gettext("Suspendu")}</span>
          </div>
          <p class="text-sm text-base-content/70">
            {SchoolType.label(row.profile.school_type)} · {SchoolSubsystem.label(row.profile.subsystem)} · {CameroonRegion.label(row.profile.region)} · {row.profile.town}
          </p>
          <p :if={row.owner} class="text-sm text-base-content/70">{Accounts.User.contact(row.owner)}</p>
          <p class="flex flex-wrap gap-1">
            <span :for={k <- row.workspace.modules} class="badge badge-outline badge-xs">{Modules.label(k)}</span>
          </p>
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 8: School detail**

`lib/teacher_assistant_web/live/admin/school_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.SchoolLive do
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Admin.ResetModal, only: [reset_modal: 1]

  alias TeacherAssistant.{Accounts, Modules, Operator, Organization}
  alias TeacherAssistant.Accounts.{AuditEvent, SchoolRole, SchoolVerificationStatus}

  def mount(%{"id" => id}, _session, socket) do
    case Operator.get_school(socket.assigns.current_scope, id) do
      {:ok, school} -> {:ok, socket |> assign(reset_user: nil, reset_password: nil) |> assign_school(school)}
      {:error, :not_found} -> {:ok, push_navigate(socket, to: ~p"/admin/schools")}
    end
  end

  defp reload(socket) do
    {:ok, school} = Operator.get_school(socket.assigns.current_scope, socket.assigns.school.workspace.id)
    assign_school(socket, school)
  end

  defp assign_school(socket, school) do
    assign(socket,
      school: school,
      events: Accounts.list_audit_events(socket.assigns.current_scope, workspace_id: school.workspace.id, limit: 20)
    )
  end

  def handle_event("verify", _params, socket) do
    %{profile: profile} = socket.assigns.school
    scope = socket.assigns.current_scope
    decided(socket, Accounts.verify_school(profile, scope.current_user.id, scope: scope))
  end

  def handle_event("reject", %{"reason" => reason}, socket) do
    %{profile: profile} = socket.assigns.school
    scope = socket.assigns.current_scope
    decided(socket, Accounts.reject_school(profile, scope.current_user.id, reason, scope: scope))
  end

  def handle_event("save_modules", params, socket) do
    modules =
      params
      |> Map.get("modules", [])
      |> Enum.flat_map(fn m ->
        case Modules.Key.match(m) do
          {:ok, key} -> [key]
          :error -> []
        end
      end)

    decided(socket, Organization.set_modules(socket.assigns.current_scope, socket.assigns.school.workspace, modules))
  end

  def handle_event("suspend", %{"reason" => reason}, socket) do
    case Organization.suspend_school(socket.assigns.current_scope, socket.assigns.school.workspace, reason) do
      {:ok, _} -> {:noreply, reload(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Indiquez le motif de la suspension."))}
    end
  end

  def handle_event("reactivate", _params, socket) do
    decided(socket, Organization.reactivate_school(socket.assigns.current_scope, socket.assigns.school.workspace))
  end

  def handle_event("reset_ask", %{"id" => id}, socket) do
    user = Enum.find_value(socket.assigns.school.members, &(&1.user_id == id && &1.user))
    {:noreply, assign(socket, reset_user: user, reset_password: nil)}
  end

  def handle_event("reset_confirm", _params, socket) do
    case Accounts.operator_reset_password(socket.assigns.current_scope, socket.assigns.reset_user) do
      {:ok, password} -> {:noreply, socket |> assign(:reset_password, password) |> reload()}
      {:error, _} -> {:noreply, socket |> assign(reset_user: nil) |> put_flash(:error, gettext("Réinitialisation impossible."))}
    end
  end

  def handle_event("reset_cancel", _params, socket),
    do: {:noreply, assign(socket, reset_user: nil, reset_password: nil)}

  defp decided(socket, {:ok, _}), do: {:noreply, reload(socket)}

  defp decided(socket, {:error, _}),
    do: {:noreply, put_flash(socket, :error, gettext("Impossible d'enregistrer la décision."))}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-school" class="space-y-6">
        <.page_header eyebrow={gettext("Établissement")} title={@school.workspace.name} />

        <div class="flex flex-wrap items-center gap-2">
          <span id="school-verification" class="badge">{SchoolVerificationStatus.label(@school.profile.verification_status)}</span>
          <span :if={@school.workspace.suspended_at} id="school-suspended-badge" class="badge badge-error">
            {gettext("Suspendu : %{reason}", reason: @school.workspace.suspension_reason)}
          </span>
        </div>

        <section class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Vérification")}</h2>
          <button :if={@school.profile.verification_status != :verified} id="verify-school" type="button" class="btn btn-primary btn-sm" phx-click="verify">
            {gettext("Vérifier")}
          </button>
          <form :if={@school.profile.verification_status == :unverified} id="reject-form" phx-submit="reject" class="flex gap-2">
            <input type="text" name="reason" placeholder={gettext("Motif du rejet")} class="input input-bordered input-sm" />
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Rejeter")}</button>
          </form>
        </section>

        <section class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Accès")}</h2>
          <form :if={is_nil(@school.workspace.suspended_at)} id="suspend-form" phx-submit="suspend" class="flex flex-wrap gap-2">
            <input type="text" name="reason" required placeholder={gettext("Motif de la suspension")} class="input input-bordered input-sm" />
            <button type="submit" class="btn btn-error btn-sm">{gettext("Suspendre")}</button>
          </form>
          <button :if={@school.workspace.suspended_at} id="reactivate-school" type="button" class="btn btn-primary btn-sm" phx-click="reactivate">
            {gettext("Réactiver")}
          </button>
        </section>

        <form id="modules-form" phx-submit="save_modules" class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Modules")}</h2>
          <label :for={k <- Modules.keys()} class="label cursor-pointer justify-start gap-2">
            <input type="checkbox" id={"module-#{k}"} name="modules[]" value={k} checked={k in @school.workspace.modules} class="checkbox checkbox-sm" />
            {Modules.label(k)}
          </label>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </form>

        <dl id="school-counts" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="ta-leaf p-3"><dt class="text-sm">{gettext("Classes")}</dt><dd class="ta-num">{@school.counts.classes}</dd></div>
          <div class="ta-leaf p-3"><dt class="text-sm">{gettext("Élèves")}</dt><dd class="ta-num">{@school.counts.students}</dd></div>
          <div class="ta-leaf p-3"><dt class="text-sm">{gettext("Personnel")}</dt><dd class="ta-num">{@school.counts.staff}</dd></div>
          <div class="ta-leaf p-3">
            <dt class="text-sm">{gettext("Dernière activité")}</dt>
            <dd>{if @school.last_activity, do: TeacherAssistantWeb.Dates.short_datetime(@school.last_activity), else: "—"}</dd>
          </div>
        </dl>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Membres")}</h2>
          <ul id="school-members" class="divide-y divide-base-300">
            <li :for={m <- @school.members} id={"member-#{m.user_id}"} class="flex flex-wrap items-center justify-between gap-2 py-2">
              <span>
                <span class="font-medium">{Accounts.User.display_name(m.user)}</span>
                <span class="text-sm text-base-content/70"> · {Enum.map_join(m.roles, ", ", &SchoolRole.label/1)} · {Accounts.User.contact(m.user)}</span>
                <span :if={m.user.must_change_password} class="badge badge-warning badge-xs">{gettext("Mot de passe temporaire")}</span>
              </span>
              <button :if={m.user.role != :admin} id={"reset-user-#{m.user_id}"} type="button" class="btn btn-ghost btn-xs" phx-click="reset_ask" phx-value-id={m.user_id}>
                {gettext("Réinitialiser le mot de passe")}
              </button>
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Journal")}</h2>
          <ul id="school-events" class="divide-y divide-base-300 text-sm">
            <li :for={e <- @events} id={"event-#{e.id}"} class="py-2">
              {AuditEvent.Action.label(e.action)}
              <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
              <span class="text-base-content/70"> · {TeacherAssistantWeb.Dates.short_datetime(e.inserted_at)}</span>
            </li>
          </ul>
        </section>

        <.reset_modal :if={@reset_user} user={@reset_user} password={@reset_password} />
      </section>
    </Layouts.app>
    """
  end
end
```

An unchecked group posts no `modules` key at all, which `Map.get(params, "modules", [])` turns into `[]` (Review Focus 5).

- [ ] **Step 9: Run the tests**

Run: `mix test test/teacher_assistant_web/live/admin`
Expected: pass. Then `mix test` — 0 failures.

- [ ] **Step 10: Commit**

```bash
git add lib/teacher_assistant_web/live/admin lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/components/layouts.ex test/teacher_assistant_web/live/admin
git commit -m "feat(operator): console overview, school list and school detail"
```

---

### Task 8: Users page and journal page

**Files:**
- Rewrite: `lib/teacher_assistant_web/live/admin/users_live.ex`, `lib/teacher_assistant_web/live/admin/journal_live.ex`
- Test: `test/teacher_assistant_web/live/admin/users_live_test.exs`, `test/teacher_assistant_web/live/admin/journal_live_test.exs`

**Interfaces:**
- Consumes: `Operator.search_users/2`, `Operator.get_user/2` (Task 6), `Accounts.operator_reset_password/2` (Task 5), `ResetModal.reset_modal/1` (Task 7), `Accounts.list_audit_events/2`, `AuditEvent.Action` (Task 1).

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/admin/users_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Admin.UsersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  setup %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, op.id)
    %{conn: conn, op: op}
  end

  test "finds a user by email and resets their password", %{conn: conn} do
    %{head_user: head} = TeacherFixtures.school_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    view |> form("#users-search", %{"q" => to_string(head.email)}) |> render_change()
    assert has_element?(view, "#user-#{head.id}")
    view |> element("#reset-user-#{head.id}") |> render_click()
    view |> element("#reset-confirm") |> render_click()
    assert has_element?(view, "#reset-password-value")
  end

  test "an operator is listed without a reset button", %{conn: conn, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    view |> form("#users-search", %{"q" => to_string(op.email)}) |> render_change()
    assert has_element?(view, "#user-#{op.id}")
    refute has_element?(view, "#reset-user-#{op.id}")
  end
end
```

`test/teacher_assistant_web/live/admin/journal_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.Admin.JournalLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Organization, Scope, TeacherFixtures}

  test "lists events and filters by action", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    %{workspace: ws} = TeacherFixtures.school_fixture()
    {:ok, _} = Organization.suspend_school(%Scope{current_user: op}, ws, "Impayé")
    {:ok, _} = Organization.set_modules(%Scope{current_user: op}, ws, [:notes])

    conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, op.id)
    {:ok, view, html} = live(conn, ~p"/admin/journal")
    assert html =~ "Impayé"

    view |> form("#journal-filter", %{"action" => "modules_changed"}) |> render_change()
    assert render(view) =~ "Modules modifiés"
    refute render(view) =~ "Impayé"
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant_web/live/admin/users_live_test.exs test/teacher_assistant_web/live/admin/journal_live_test.exs`
Expected: FAIL (placeholder pages).

- [ ] **Step 3: Users page**

`lib/teacher_assistant_web/live/admin/users_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.UsersLive do
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Admin.ResetModal, only: [reset_modal: 1]

  alias TeacherAssistant.{Accounts, Operator}
  alias TeacherAssistant.Accounts.SchoolRole

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, q: "", results: [], reset_user: nil, reset_password: nil)}

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, assign(socket, q: q, results: Operator.search_users(socket.assigns.current_scope, q))}

  def handle_event("reset_ask", %{"id" => id}, socket) do
    case Operator.get_user(socket.assigns.current_scope, id) do
      {:ok, user} -> {:noreply, assign(socket, reset_user: user, reset_password: nil)}
      {:error, :not_found} -> {:noreply, socket}
    end
  end

  def handle_event("reset_confirm", _params, socket) do
    case Accounts.operator_reset_password(socket.assigns.current_scope, socket.assigns.reset_user) do
      {:ok, password} -> {:noreply, assign(socket, :reset_password, password)}
      {:error, _} -> {:noreply, socket |> assign(reset_user: nil) |> put_flash(:error, gettext("Réinitialisation impossible."))}
    end
  end

  def handle_event("reset_cancel", _params, socket) do
    socket = assign(socket, reset_user: nil, reset_password: nil)
    {:noreply, assign(socket, :results, Operator.search_users(socket.assigns.current_scope, socket.assigns.q))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-users" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Utilisateurs")} />

        <form id="users-search" phx-change="search" phx-submit="search">
          <input type="search" name="q" value={@q} phx-debounce="300" placeholder={gettext("Nom, téléphone ou e-mail")} class="input input-bordered w-full" />
        </form>

        <ul class="divide-y divide-base-300">
          <li :for={%{user: u, memberships: ms} <- @results} id={"user-#{u.id}"} class="flex flex-wrap items-center justify-between gap-2 py-3">
            <span>
              <span class="font-medium">{Accounts.User.display_name(u)}</span>
              <span class="text-sm text-base-content/70"> · {Accounts.User.contact(u)}</span>
              <span :if={u.role == :admin} class="badge badge-xs">{gettext("Opérateur")}</span>
              <span :if={u.must_change_password} class="badge badge-warning badge-xs">{gettext("Mot de passe temporaire")}</span>
              <span class="block text-sm text-base-content/70">
                {Enum.map_join(ms, " · ", fn m -> "#{m.workspace.name} (#{Enum.map_join(m.roles, ", ", &SchoolRole.label/1)})" end)}
              </span>
            </span>
            <button :if={u.role != :admin} id={"reset-user-#{u.id}"} type="button" class="btn btn-ghost btn-xs" phx-click="reset_ask" phx-value-id={u.id}>
              {gettext("Réinitialiser le mot de passe")}
            </button>
          </li>
        </ul>

        <.reset_modal :if={@reset_user} user={@reset_user} password={@reset_password} />
      </section>
    </Layouts.app>
    """
  end
end
```

`:active_for_user` must load `:workspace` (it does today: `list_workspaces_for/1` maps `& &1.workspace`). If not, add `|> Ash.Query.load(:workspace)` in `Operator.memberships_of/1`.

- [ ] **Step 4: Journal page**

`lib/teacher_assistant_web/live/admin/journal_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Admin.JournalLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.AuditEvent

  @per_page 50

  def mount(_params, _session, socket), do: {:ok, socket}

  def handle_params(params, _uri, socket) do
    action =
      case AuditEvent.Action.match(params["action"] || "") do
        {:ok, a} -> a
        :error -> nil
      end

    page = max(String.to_integer(params["page"] || "1"), 1)

    events =
      Accounts.list_audit_events(socket.assigns.current_scope,
        action: action,
        limit: @per_page + 1,
        offset: (page - 1) * @per_page
      )

    {:noreply,
     assign(socket,
       action: action,
       page: page,
       events: Enum.take(events, @per_page),
       more?: length(events) > @per_page
     )}
  end

  def handle_event("filter", %{"action" => action}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/admin/journal?#{%{action: action}}")}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-journal" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Journal")} />

        <form id="journal-filter" phx-change="filter">
          <select name="action" class="select select-bordered select-sm">
            <option value="">{gettext("Toutes les actions")}</option>
            <option :for={a <- AuditEvent.Action.values()} value={a} selected={@action == a}>{AuditEvent.Action.label(a)}</option>
          </select>
        </form>

        <ul class="divide-y divide-base-300 text-sm">
          <li :for={e <- @events} id={"event-#{e.id}"} class="py-2">
            <span class="font-medium">{AuditEvent.Action.label(e.action)}</span>
            <span :if={e.workspace}> · {e.workspace.name}</span>
            <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
            <span :if={e.details["reason"]}> · {e.details["reason"]}</span>
            <span :if={e.details["after"]}> · {Enum.join(e.details["after"], ", ")}</span>
            <span class="block text-base-content/70">
              {e.actor && Accounts.User.display_name(e.actor)} · {TeacherAssistantWeb.Dates.short_datetime(e.inserted_at)}
            </span>
          </li>
        </ul>

        <div class="flex gap-2">
          <.link :if={@page > 1} patch={~p"/admin/journal?#{%{action: @action || "", page: @page - 1}}"} class="btn btn-sm">{gettext("Précédent")}</.link>
          <.link :if={@more?} patch={~p"/admin/journal?#{%{action: @action || "", page: @page + 1}}"} class="btn btn-sm">{gettext("Suivant")}</.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

`String.to_integer/1` raises on a forged `page`; replace with `Integer.parse/1` and default to 1:

```elixir
    page =
      case Integer.parse(params["page"] || "1") do
        {n, ""} when n > 0 -> n
        _ -> 1
      end
```

- [ ] **Step 5: Run the tests**

Run: `mix test test/teacher_assistant_web/live/admin`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/admin test/teacher_assistant_web/live/admin
git commit -m "feat(operator): user search with password reset, and the audit journal"
```

---

### Task 9: Make-operator task, seeds, translations and precommit

**Files:**
- Create: `lib/mix/tasks/teacher_assistant.make_operator.ex`
- Modify: `priv/repo/seeds.exs`, `priv/repo/demo_school_seeds.exs`, `priv/gettext/*`
- Test: `test/mix/tasks/make_operator_test.exs`

**Interfaces:**
- Consumes: `User :promote_to_admin` (existing), `Accounts.Phone.normalize/1`, `Organization.set_modules/3`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Mix.Tasks.TeacherAssistant.MakeOperatorTest do
  use TeacherAssistant.DataCase, async: false

  import ExUnit.CaptureIO
  alias TeacherAssistant.TeacherFixtures

  test "promotes a user found by email" do
    user = TeacherFixtures.user_fixture()

    output =
      capture_io(fn -> Mix.Tasks.TeacherAssistant.MakeOperator.run([to_string(user.email)]) end)

    assert output =~ "opérateur"
    assert Ash.get!(TeacherAssistant.Accounts.User, user.id, authorize?: false).role == :admin
  end

  test "an unknown identifier fails" do
    assert_raise Mix.Error, fn ->
      capture_io(fn -> Mix.Tasks.TeacherAssistant.MakeOperator.run(["nobody@example.com"]) end)
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/mix/tasks/make_operator_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

`lib/mix/tasks/teacher_assistant.make_operator.ex`:

```elixir
defmodule Mix.Tasks.TeacherAssistant.MakeOperator do
  @shortdoc "Gives a user the platform operator role"
  @moduledoc """
      mix teacher_assistant.make_operator someone@example.com
      mix teacher_assistant.make_operator "6 77 12 34 56"

  A release-time admin task (operator console spec §5): finds the user by e-mail or
  phone and runs `User :promote_to_admin` without an actor.
  """
  use Mix.Task

  require Ash.Query

  alias TeacherAssistant.Accounts.{Phone, User}

  @requirements ["app.start"]

  @impl Mix.Task
  def run([identifier]) do
    with %User{} = user <- find(String.trim(identifier)),
         {:ok, user} <-
           user |> Ash.Changeset.for_update(:promote_to_admin, %{}) |> Ash.update(authorize?: false) do
      Mix.shell().info("#{User.display_name(user)} est maintenant opérateur.")
    else
      _ -> Mix.raise("Aucun utilisateur pour #{identifier}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix teacher_assistant.make_operator <email|téléphone>")

  defp find(identifier) do
    query =
      case Phone.normalize(identifier) do
        {:ok, phone} -> Ash.Query.filter(User, phone == ^phone)
        _ -> Ash.Query.filter(User, email == ^identifier)
      end

    Ash.read_one!(query, authorize?: false)
  end
end
```

- [ ] **Step 4: Seeds**

In `priv/repo/seeds.exs` and `priv/repo/demo_school_seeds.exs`, after each school is created, enable every module (dev config defaults new schools to none):

```elixir
{:ok, _} =
  TeacherAssistant.Organization.set_modules(
    %TeacherAssistant.Scope{current_user: operator},
    workspace,
    TeacherAssistant.Modules.keys()
  )
```

Use the operator user each seed file already promotes (`seeds.exs` calls `promote_to_admin`); in `demo_school_seeds.exs`, if no operator exists there, run the update with `authorize?: false` instead:

```elixir
workspace
|> Ash.Changeset.for_update(:set_modules, %{modules: TeacherAssistant.Modules.keys()})
|> Ash.update!(authorize?: false)
```

- [ ] **Step 5: Translations**

Run: `MIX_ENV=test mix gettext.extract --merge`
Then fill the English `msgstr` for every new French msgid in `priv/gettext/en/LC_MESSAGES/default.po` (search for `msgstr ""` under the new references in `lib/teacher_assistant_web/live/admin/`, `modules.ex`, `audit_event/action.ex`, `suspended_live.ex`, `plug/school_access.ex`, `live_user_auth.ex`, `settings_live.ex`). No new msgid may be left `fuzzy` (`test/teacher_assistant_web/gettext_fuzzy_test.exs`).

- [ ] **Step 6: Full check**

Run: `mix precommit`
Expected: exit 0, every test passing, no warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/mix test/mix priv/repo/seeds.exs priv/repo/demo_school_seeds.exs priv/gettext
git commit -m "feat(operator): make_operator task, seeds enable modules, translations"
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| §1 Catalogue, storage, defaults | 2 |
| §1 Enforcement — LiveViews, controllers | 3 |
| §1 Enforcement — menus, shared screens, settings card, jobs | 4 |
| §1 Guard test | 3 |
| §2 Suspension fields and actions | 2 |
| §2 Suspended page, redirects, verification exempt | 3 |
| §2 Jobs skip suspended | 4 |
| §3 Reset policy, operator reset, journal | 5 |
| §3 Members page widens automatically | 5 (existing `can_reset_member_password?/2`) |
| §3 Operator reset screens | 7, 8 |
| §4 Audit journal | 1 (resource), 2 and 5 (writers), 7 and 8 (readers) |
| §5 Console pages and rail | 6, 7, 8 |
| §5 make_operator | 9 |
| §6 Testing | every task |
