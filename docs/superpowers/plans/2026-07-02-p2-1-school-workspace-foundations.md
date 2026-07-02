# P2.1 School-layer foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a polymorphic workspace (personal | school) with school membership, roles, and email invitations, so a teacher can create or join a school, switch into it, and see a thin role-gated school shell — per [`docs/superpowers/specs/2026-07-02-p2-1-school-workspace-foundations-design.md`](../specs/2026-07-02-p2-1-school-workspace-foundations-design.md).

**Architecture:** Generalize the single-owner `PersonalWorkspace` into a `Workspace` with a `kind` enum; academic entities reference `workspace_id`. School access is a `SchoolMembership` join; polymorphism is quarantined to `Workspaces.scope_for/3` (personal → owner check; school → membership check). School/membership/invitation logic lives in a new `Accounts.Schools` context. A thin school UI (Members · Settings · stub dashboard) is gated by a coarse `Accounts.Permissions` helper.

**Tech Stack:** Elixir, Ash 3 + AshPostgres (codegen migrations via `mix ash.codegen`), Phoenix LiveView + HEEx, AshAuthentication (existing magic-link email infra), Swoosh mailer, daisyUI/Tailwind ("Tableau" kit), gettext FR/EN.

## Global Constraints

- **Unified workspace, one FK:** academic entities reference `workspace_id` (never a second `school_id`). Polymorphism lives ONLY in `Workspaces.scope_for/3`; academic `fetch_owned_*` helpers stay a flat `workspace_id == ^ws_id`.
- **Every enum is an `Ash.Type.Enum` module** (never a bare `:atom` attribute), matching `TeacherAssistant.Academics.Sex` (`use Ash.Type.Enum, values: [...]`).
- **Roles are multi-valued** (`{:array, SchoolRole}`); a member may hold several. Role catalog = Décret 2001/041 (doc 05 §1): `:head, :vice_principal, :discipline_master, :bursar, :hod, :form_master, :teacher, :guidance_counsellor, :librarian`.
- **Coarse gating only:** `Accounts.Permissions` implements `head?/1`, `member?/1`, `bursar?/1`; the fine-grained pedagogical/disciplinary/financial matrix is deferred (documented as a comment).
- **Invitations are email-keyed** (`:ci_string`), single-use `token`, `expires_at`; accepting requires `user.email == invitation.email`.
- **Last-Head protection:** never remove the `:head` role from, or deactivate, a school's only remaining active Head.
- **Personal path unchanged:** `ensure_personal_workspace!/1` and personal `scope_for` behave exactly as today; all existing **150 tests stay green**.
- All new copy via `gettext`; FR filled in the final task. Tableau kit; stable DOM ids; `mix precommit` green at every commit (compile `--warning-as-errors`, format, test).
- Resources follow the existing pattern: `use Ash.Resource`, `AshPostgres.DataLayer`, `policy always()`, `uuid_v7_primary_key :id`, `timestamps()`. Migrations via `mix ash.codegen <name>` then `mix ecto.migrate`; the `test` alias runs `ash.setup`.
- Work on branch `feat/p2-1-school-foundations` off `main`.

## File Structure

- `lib/teacher_assistant/accounts/workspace_kind.ex`, `school_role.ex`, `membership_status.ex`, `invitation_status.ex` — enums (create).
- `lib/teacher_assistant/academics/workspace.ex` — renamed/generalized from `personal_workspace.ex` (rename+edit).
- `lib/teacher_assistant/accounts/school_membership.ex`, `school_invitation.ex` — resources (create).
- `lib/teacher_assistant/accounts/school_roles.ex` — bilingual label helper (create).
- `lib/teacher_assistant/accounts/schools.ex` — school/membership/invitation context (create).
- `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex` — email sender (create).
- `lib/teacher_assistant/accounts.ex` — register new resources in the Accounts domain (modify).
- `lib/teacher_assistant/academics.ex` — rename `PersonalWorkspace`→`Workspace`, `personal_workspace_id`→`workspace_id` (modify).
- `lib/teacher_assistant/scope.ex`, `lib/teacher_assistant/accounts/workspaces.ex` — scope branching (modify).
- `lib/teacher_assistant/accounts/permissions.ex` — coarse gating helper (create).
- `lib/teacher_assistant_web/controllers/workspace_controller.ex` — create-school + redirect (modify).
- `lib/teacher_assistant_web/components/layouts.ex` — workspace switcher + school nav (modify).
- `lib/teacher_assistant_web/live/school/{dashboard_live,members_live,settings_live}.ex`, `.../controllers/school_invitation_controller.ex` — school UI (create).
- `lib/teacher_assistant_web/router.ex` — school routes (modify).
- Tests alongside each.

Note: check whether `Accounts` is a separate Ash domain (`lib/teacher_assistant/accounts.ex`) or whether these resources should register in `Academics`. The `Workspace` resource currently lives under `Academics`; keep it there (academic entities reference it). Register `SchoolMembership`/`SchoolInvitation` in whichever domain `User` is registered in (`Accounts`) — confirm by reading `lib/teacher_assistant/accounts.ex` before Task 2.

---

### Task 1: Unify `PersonalWorkspace` → `Workspace` (kind, nil-able owner) + FK rename

**Files:**
- Create: `lib/teacher_assistant/accounts/workspace_kind.ex`
- Rename+edit: `lib/teacher_assistant/academics/personal_workspace.ex` → `lib/teacher_assistant/academics/workspace.ex`
- Modify: `lib/teacher_assistant/academics.ex` (all `PersonalWorkspace`/`personal_workspace_id` references — 45 occurrences), and the 5 FK resources: `academic_year.ex`, `class_group.ex`, `teaching_context.ex`, `progression_plan.ex`, `teaching_log_entry.ex`
- Generated: migration + snapshots

**Interfaces:**
- Consumes: existing academic resources.
- Produces: `TeacherAssistant.Academics.Workspace` (attrs `kind` :: `WorkspaceKind`, `name`, `owner_user_id` nil-able; identity `unique_owner_user`; `has_many :school_memberships`). Academic entities' FK is now `workspace_id`. `Academics.ensure_personal_workspace!/1`, `personal_workspace_for_user/1`, `get_personal_workspace/1` keep their names and behavior (now returning `%Workspace{kind: :personal}`).

- [ ] **Step 1: Create the `WorkspaceKind` enum**

`lib/teacher_assistant/accounts/workspace_kind.ex`:

```elixir
defmodule TeacherAssistant.Accounts.WorkspaceKind do
  use Ash.Type.Enum, values: [:personal, :school]
end
```

- [ ] **Step 2: Rename and generalize the resource**

`git mv lib/teacher_assistant/academics/personal_workspace.ex lib/teacher_assistant/academics/workspace.ex`, then replace its contents with:

```elixir
defmodule TeacherAssistant.Academics.Workspace do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :kind, :owner_user_id],
      update: [:name]
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

    attribute :kind, TeacherAssistant.Accounts.WorkspaceKind,
      allow_nil?: false,
      default: :personal,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :owner_user, TeacherAssistant.Accounts.User do
      source_attribute :owner_user_id
      allow_nil? true
      public? true
    end

    has_many :school_memberships, TeacherAssistant.Accounts.SchoolMembership do
      destination_attribute :workspace_id
    end
  end

  identities do
    identity :unique_owner_user, [:owner_user_id]
  end
end
```

(The `has_many :school_memberships` references a resource created in Task 2 — it compiles only after Task 2. To keep Task 1 self-contained and compiling, OMIT the `has_many :school_memberships` block in this task and add it in Task 2 when `SchoolMembership` exists. Everything else in this file stays.)

- [ ] **Step 3: Rename in the domain module**

In `lib/teacher_assistant/academics.ex`: replace the alias `alias TeacherAssistant.Academics.PersonalWorkspace` with `alias TeacherAssistant.Academics.Workspace`; change `resource PersonalWorkspace` → `resource Workspace`; and mechanically replace every remaining `PersonalWorkspace` → `Workspace` and every `personal_workspace_id` → `workspace_id` (45 occurrences). Keep the function NAMES `ensure_personal_workspace!/1`, `personal_workspace_for_user/1`, `get_personal_workspace/1` (they still ensure/return the user's personal workspace). The `ensure_personal_workspace!` create call must set `kind: :personal`:

```elixir
        {:ok, ws} =
          Workspace
          |> Ash.Changeset.for_create(:create, %{
            name: "Personal workspace",
            kind: :personal,
            owner_user_id: user.id
          })
          |> Ash.create(authorize?: false)
```

Verify with `grep -rn "PersonalWorkspace\|personal_workspace_id" lib/` → no matches remain (function names containing `personal_workspace` like `personal_workspace_for_user` are fine; only the module name and the `_id` column must be gone).

- [ ] **Step 4: Rename the FK on the 5 academic resources**

In each of `academic_year.ex`, `class_group.ex`, `teaching_context.ex`, `progression_plan.ex`, `teaching_log_entry.ex`: the `belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do source_attribute :personal_workspace_id ... end` becomes:

```elixir
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
```

and update those resources' `create`/`update` action accept-lists that list `:personal_workspace_id` → `:workspace_id`. Grep each file for `personal_workspace` and replace.

- [ ] **Step 5: Generate the migration and migrate**

Run: `mix ash.codegen unify_workspace`
Then: `mix ecto.migrate`
Expected: migration renames `personal_workspaces` → `workspaces`, adds `kind` (default `personal`), makes `owner_user_id` nullable, and renames the `personal_workspace_id` columns → `workspace_id` on the 5 tables. If codegen proposes a drop+recreate instead of a rename for any column, edit the generated migration to use `rename table(...), :personal_workspace_id, to: :workspace_id` so existing rows are preserved. Confirm `mix ecto.migrate` runs clean.

- [ ] **Step 6: Run the full suite**

Run: `mix test`
Expected: **150 tests, 0 failures** (the rename is behavior-preserving). If a test references `PersonalWorkspace` or `personal_workspace_id` directly, update it to `Workspace`/`workspace_id`; do not change assertions.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(workspace): unify PersonalWorkspace into polymorphic Workspace (kind, workspace_id FK)"
```

---

### Task 2: School enums, membership + invitation resources

**Files:**
- Create: `lib/teacher_assistant/accounts/school_role.ex`, `membership_status.ex`, `invitation_status.ex`, `school_roles.ex`
- Create: `lib/teacher_assistant/accounts/school_membership.ex`, `school_invitation.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (register resources), `lib/teacher_assistant/academics/workspace.ex` (add the `has_many :school_memberships` deferred from Task 1)
- Test: `test/teacher_assistant/accounts/school_resources_test.exs`

**Interfaces:**
- Consumes: `Workspace` (Task 1), `User`.
- Produces: `SchoolRole` (9 values), `MembershipStatus` (3), `InvitationStatus` (3) enums; `SchoolMembership` (`workspace_id`, `user_id`, `roles` `{:array, SchoolRole}`, `status`, `active`; identity `unique_member` on `[:workspace_id, :user_id]`); `SchoolInvitation` (`workspace_id`, `email` ci_string, `roles`, `invited_by_user_id`, `status`, `token`, `expires_at`; unique index on `token`). `SchoolRoles.label/1` bilingual helper.

- [ ] **Step 1: Read the Accounts domain**

Run: `cat lib/teacher_assistant/accounts.ex` — confirm it's an `Ash.Domain` with a `resources do ... end` block and note the alias style. New resources register here (alongside `User`).

- [ ] **Step 2: Create the three enums**

`lib/teacher_assistant/accounts/school_role.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolRole do
  use Ash.Type.Enum,
    values: [
      :head,
      :vice_principal,
      :discipline_master,
      :bursar,
      :hod,
      :form_master,
      :teacher,
      :guidance_counsellor,
      :librarian
    ]
end
```

`lib/teacher_assistant/accounts/membership_status.ex`:

```elixir
defmodule TeacherAssistant.Accounts.MembershipStatus do
  use Ash.Type.Enum, values: [:titulaire, :contractuel, :vacataire]
end
```

`lib/teacher_assistant/accounts/invitation_status.ex`:

```elixir
defmodule TeacherAssistant.Accounts.InvitationStatus do
  use Ash.Type.Enum, values: [:pending, :accepted, :revoked]
end
```

- [ ] **Step 3: Create the bilingual role-label helper**

`lib/teacher_assistant/accounts/school_roles.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolRoles do
  @moduledoc "Bilingual display labels for school roles (Décret 2001/041, doc 05 §1)."
  import TeacherAssistantWeb.Gettext

  @order [
    :head,
    :vice_principal,
    :discipline_master,
    :bursar,
    :hod,
    :form_master,
    :teacher,
    :guidance_counsellor,
    :librarian
  ]

  def all, do: @order

  def label(:head), do: gettext("Chef d'établissement")
  def label(:vice_principal), do: gettext("Censeur")
  def label(:discipline_master), do: gettext("Surveillant général")
  def label(:bursar), do: gettext("Intendant")
  def label(:hod), do: gettext("Animateur pédagogique")
  def label(:form_master), do: gettext("Professeur principal")
  def label(:teacher), do: gettext("Enseignant")
  def label(:guidance_counsellor), do: gettext("Conseiller d'orientation")
  def label(:librarian), do: gettext("Documentaliste")
end
```

- [ ] **Step 4: Create `SchoolMembership`**

`lib/teacher_assistant/accounts/school_membership.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolMembership do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "school_memberships"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:workspace_id, :user_id, :roles, :status, :active],
      update: [:roles, :status, :active]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :roles, {:array, TeacherAssistant.Accounts.SchoolRole}, allow_nil?: false, public?: true
    attribute :status, TeacherAssistant.Accounts.MembershipStatus, allow_nil?: true, public?: true
    attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :user, TeacherAssistant.Accounts.User do
      source_attribute :user_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_member, [:workspace_id, :user_id]
  end
end
```

- [ ] **Step 5: Create `SchoolInvitation`**

`lib/teacher_assistant/accounts/school_invitation.ex`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolInvitation do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "school_invitations"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:workspace_id, :email, :roles, :invited_by_user_id, :status, :token, :expires_at],
      update: [:status]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :roles, {:array, TeacherAssistant.Accounts.SchoolRole}, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Accounts.InvitationStatus,
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :token, :string, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :invited_by_user, TeacherAssistant.Accounts.User do
      source_attribute :invited_by_user_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_token, [:token]
  end
end
```

- [ ] **Step 6: Register resources + add the deferred `has_many`**

In `lib/teacher_assistant/accounts.ex` `resources do` block add `resource TeacherAssistant.Accounts.SchoolMembership` and `resource TeacherAssistant.Accounts.SchoolInvitation` (match the file's alias/registration style). Then add to `lib/teacher_assistant/academics/workspace.ex`'s `relationships do` block the deferred:

```elixir
    has_many :school_memberships, TeacherAssistant.Accounts.SchoolMembership do
      destination_attribute :workspace_id
    end
```

- [ ] **Step 7: Migration**

Run: `mix ash.codegen add_school_membership_and_invitation` then `mix ecto.migrate`
Expected: creates `school_memberships` (unique on `[workspace_id, user_id]`) and `school_invitations` (unique on `token`); clean migrate.

- [ ] **Step 8: Write the resource test**

`test/teacher_assistant/accounts/school_resources_test.exs`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolResourcesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, SchoolInvitation, SchoolRoles}
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Workspace
      |> Ash.Changeset.for_create(:create, %{name: "Lycée de Test", kind: :school})
      |> Ash.create(authorize?: false)

    %{user: user, school: school}
  end

  test "a membership persists with multiple roles", %{user: user, school: school} do
    {:ok, m} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: school.id,
        user_id: user.id,
        roles: [:head, :teacher],
        status: :titulaire
      })
      |> Ash.create(authorize?: false)

    assert m.roles == [:head, :teacher]
    assert m.active == true
  end

  test "membership is unique per (school, user)", %{user: user, school: school} do
    attrs = %{workspace_id: school.id, user_id: user.id, roles: [:teacher]}
    {:ok, _} = SchoolMembership |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

    assert {:error, _} =
             SchoolMembership |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  test "an invitation defaults to pending and enforces a unique token", %{school: school} do
    attrs = %{workspace_id: school.id, email: "t@example.com", roles: [:teacher], token: "tok-1"}
    {:ok, inv} = SchoolInvitation |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
    assert inv.status == :pending

    assert {:error, _} =
             SchoolInvitation
             |> Ash.Changeset.for_create(:create, %{attrs | email: "u@example.com"})
             |> Ash.create(authorize?: false)
  end

  test "role labels are bilingual-ready", do: assert SchoolRoles.label(:head) =~ "Chef"
end
```

- [ ] **Step 9: Run + commit**

Run: `mix test test/teacher_assistant/accounts/school_resources_test.exs` → 4 tests pass.

```bash
git add -A
git commit -m "feat(accounts): SchoolMembership + SchoolInvitation resources, school enums + role labels"
```

---

### Task 3: `Accounts.Schools` context — create-school, membership queries, role management

**Files:**
- Create: `lib/teacher_assistant/accounts/schools.ex`
- Test: `test/teacher_assistant/accounts/schools_test.exs`

**Interfaces:**
- Consumes: `Workspace`, `SchoolMembership`, `User`, `Academics.ensure_personal_workspace!/1`.
- Produces:
  - `create_school(%User{}, %{name}) :: {:ok, %Workspace{}}` (creator becomes Head)
  - `list_workspaces_for(%User{}) :: [%Workspace{}]` (personal + active-member schools)
  - `fetch_school_membership(%Workspace{}, %User{}) :: {:ok, %SchoolMembership{}} | {:error, :not_a_member}`
  - `list_members(%Workspace{}) :: [%SchoolMembership{}]` (active, with `:user` loaded)
  - `update_member_roles(%SchoolMembership{}, roles) :: {:ok, _} | {:error, :last_head}`
  - `deactivate_member(%SchoolMembership{}) :: {:ok, _} | {:error, :last_head}`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/accounts/schools_test.exs`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{head: TeacherFixtures.user_fixture(), other: TeacherFixtures.user_fixture()}
  end

  test "create_school makes the creator a Head", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Bilingue"})
    assert school.kind == :school
    assert {:ok, m} = Schools.fetch_school_membership(school, head)
    assert :head in m.roles
  end

  test "list_workspaces_for returns the personal workspace plus member schools", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "École A"})
    ids = Schools.list_workspaces_for(head) |> Enum.map(& &1.id)
    assert school.id in ids
    # personal workspace also present
    assert Enum.any?(Schools.list_workspaces_for(head), &(&1.kind == :personal))
  end

  test "a non-member is rejected", %{head: head, other: other} do
    {:ok, school} = Schools.create_school(head, %{name: "École B"})
    assert {:error, :not_a_member} = Schools.fetch_school_membership(school, other)
  end

  test "last-Head protection blocks removing the only Head", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "École C"})
    {:ok, m} = Schools.fetch_school_membership(school, head)
    assert {:error, :last_head} = Schools.update_member_roles(m, [:teacher])
    assert {:error, :last_head} = Schools.deactivate_member(m)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/accounts/schools_test.exs`
Expected: FAIL (`Schools.create_school/2` undefined).

- [ ] **Step 3: Implement**

`lib/teacher_assistant/accounts/schools.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Schools do
  @moduledoc "School workspaces, memberships, and invitations (Phase 2 school layer)."
  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, User}

  def create_school(%User{} = user, %{} = attrs) do
    with {:ok, school} <-
           Workspace
           |> Ash.Changeset.for_create(:create, %{name: attrs[:name] || attrs["name"], kind: :school})
           |> Ash.create(authorize?: false),
         {:ok, _membership} <-
           SchoolMembership
           |> Ash.Changeset.for_create(:create, %{
             workspace_id: school.id,
             user_id: user.id,
             roles: [:head]
           })
           |> Ash.create(authorize?: false) do
      {:ok, school}
    end
  end

  def list_workspaces_for(%User{} = user) do
    personal = Academics.ensure_personal_workspace!(user)

    schools =
      SchoolMembership
      |> Ash.Query.filter(user_id == ^user.id and active == true)
      |> Ash.Query.load(:workspace)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.workspace)

    [personal | schools]
  end

  def fetch_school_membership(%Workspace{id: ws_id}, %User{id: user_id}) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and user_id == ^user_id and active == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_a_member}
      {:ok, m} -> {:ok, m}
      error -> error
    end
  end

  def list_members(%Workspace{id: ws_id}) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
    |> Ash.Query.load(:user)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def update_member_roles(%SchoolMembership{} = m, roles) do
    if removing_last_head?(m, roles) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:update, %{roles: roles}) |> Ash.update(authorize?: false)
    end
  end

  def deactivate_member(%SchoolMembership{} = m) do
    if :head in m.roles and last_head?(m) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update(authorize?: false)
    end
  end

  defp removing_last_head?(%SchoolMembership{} = m, new_roles) do
    :head in m.roles and :head not in new_roles and last_head?(m)
  end

  defp last_head?(%SchoolMembership{workspace_id: ws_id, id: id}) do
    heads =
      SchoolMembership
      |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn m -> :head in m.roles and m.id != id end)

    heads == []
  end
end
```

- [ ] **Step 4: Run + commit**

Run: `mix test test/teacher_assistant/accounts/schools_test.exs` → 4 pass.

```bash
git add lib/teacher_assistant/accounts/schools.ex test/teacher_assistant/accounts/schools_test.exs
git commit -m "feat(accounts): Schools context — create-school (Head), workspace list, membership queries, last-Head protection"
```

---

### Task 4: Invitations — invite (+ email), accept, revoke

**Files:**
- Create: `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex`
- Modify: `lib/teacher_assistant/accounts/schools.ex`
- Test: `test/teacher_assistant/accounts/school_invitations_test.exs`

**Interfaces:**
- Consumes: `SchoolInvitation`, `SchoolMembership`, `fetch_school_membership/2`. NOTE: this app has **no Mailer wired yet** — the existing `SendMagicLinkEmail` is a no-op stub (`def send(_,_,_), do: :ok`). Mirror that: the invitation sender is a **stub** (returns `:ok`), NOT a real Swoosh delivery. Do not add a Mailer or `assert_email_sent` — that's out of scope for P2.1.
- Produces:
  - `invite_member(%Workspace{}, %User{} = inviter, %{email, roles}) :: {:ok, %SchoolInvitation{}} | {:error, :already_member}`
  - `accept_invitation(token, %User{}) :: {:ok, %Workspace{}} | {:error, :invalid | :expired | :email_mismatch | :already_member}`
  - `revoke_invitation(%SchoolInvitation{}) :: {:ok, %SchoolInvitation{}}`
  - `fetch_invitation_by_token(token) :: {:ok, %SchoolInvitation{}} | {:error, :not_found}`
  - `list_pending_invitations(%Workspace{}) :: [%SchoolInvitation{}]`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/accounts/school_invitations_test.exs`:

```elixir
defmodule TeacherAssistant.Accounts.SchoolInvitationsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Collège Test"})
    %{head: head, school: school}
  end

  test "invite_member creates a pending invitation with a token", %{school: school, head: head} do
    {:ok, inv} = Schools.invite_member(school, head, %{email: "prof@example.com", roles: [:teacher]})
    assert inv.status == :pending
    assert to_string(inv.email) == "prof@example.com"
    assert is_binary(inv.token) and inv.token != ""
  end

  test "accept_invitation as the matching user creates a membership", %{school: school, head: head} do
    invitee = TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})

    assert {:ok, joined} = Schools.accept_invitation(inv.token, invitee)
    assert joined.id == school.id
    assert {:ok, m} = Schools.fetch_school_membership(school, invitee)
    assert :teacher in m.roles
  end

  test "accept rejects an email mismatch", %{school: school, head: head} do
    {:ok, inv} = Schools.invite_member(school, head, %{email: "someone@example.com", roles: [:teacher]})
    other = TeacherFixtures.user_fixture()
    assert {:error, :email_mismatch} = Schools.accept_invitation(inv.token, other)
  end

  test "accept rejects a revoked invitation", %{school: school, head: head} do
    invitee = TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})
    {:ok, _} = Schools.revoke_invitation(inv)
    assert {:error, :invalid} = Schools.accept_invitation(inv.token, invitee)
  end

  test "inviting an existing active member is rejected", %{school: school, head: head} do
    assert {:error, :already_member} =
             Schools.invite_member(school, head, %{email: to_string(head.email), roles: [:teacher]})
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/accounts/school_invitations_test.exs`
Expected: FAIL (`invite_member/3` undefined).

- [ ] **Step 3: Create the email sender (stub, mirroring the codebase)**

The app has no Mailer wired (`SendMagicLinkEmail` is a no-op `def send(_,_,_), do: :ok`). Mirror that with a stub that will become a real delivery when a Mailer is introduced later. `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex`:

```elixir
defmodule TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail do
  @moduledoc """
  Stub sender for school invitations. Email delivery is not yet wired in this
  app (the magic-link sender is likewise a no-op); this returns `:ok` and is
  the single place to add real Swoosh delivery once a Mailer is configured.
  The accept link is `/schools/invitations/<token>`.
  """
  require Logger

  def send(email, school_name, token) do
    Logger.debug("[school-invite] #{email} → #{school_name} (/schools/invitations/#{token})")
    :ok
  end
end
```

Do NOT add a Swoosh Mailer or real delivery in P2.1 — it would be inconsistent with the stubbed magic-link path and is out of scope.

- [ ] **Step 4: Implement the context functions**

Append to `lib/teacher_assistant/accounts/schools.ex` (add `alias TeacherAssistant.Accounts.SchoolInvitation` and the sender alias at the top):

```elixir
  def invite_member(%Workspace{} = school, %User{} = inviter, %{} = attrs) do
    email = attrs[:email] || attrs["email"]
    roles = attrs[:roles] || attrs["roles"] || [:teacher]

    if active_member_email?(school, email) do
      {:error, :already_member}
    else
      {:ok, invitation} =
        SchoolInvitation
        |> Ash.Changeset.for_create(:create, %{
          workspace_id: school.id,
          email: email,
          roles: roles,
          invited_by_user_id: inviter.id,
          token: gen_token(),
          expires_at: DateTime.add(DateTime.utc_now(), 14, :day) |> DateTime.truncate(:second)
        })
        |> Ash.create(authorize?: false)

      TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail.send(
        invitation.email,
        school.name,
        invitation.token
      )

      {:ok, invitation}
    end
  end

  def fetch_invitation_by_token(token) do
    SchoolInvitation
    |> Ash.Query.filter(token == ^token)
    |> Ash.Query.load(:workspace)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, inv} -> {:ok, inv}
      error -> error
    end
  end

  def list_pending_invitations(%Workspace{id: ws_id}) do
    SchoolInvitation
    |> Ash.Query.filter(workspace_id == ^ws_id and status == :pending)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def revoke_invitation(%SchoolInvitation{} = inv) do
    inv |> Ash.Changeset.for_update(:update, %{status: :revoked}) |> Ash.update(authorize?: false)
  end

  def accept_invitation(token, %User{} = user) do
    with {:ok, inv} <- fetch_invitation_by_token(token),
         :ok <- check_acceptable(inv),
         :ok <- check_email(inv, user) do
      case fetch_school_membership(inv.workspace, user) do
        {:ok, _already} ->
          {:ok, inv.workspace}

        {:error, :not_a_member} ->
          {:ok, _m} =
            SchoolMembership
            |> Ash.Changeset.for_create(:create, %{
              workspace_id: inv.workspace_id,
              user_id: user.id,
              roles: inv.roles
            })
            |> Ash.create(authorize?: false)

          {:ok, _} = inv |> Ash.Changeset.for_update(:update, %{status: :accepted}) |> Ash.update(authorize?: false)
          {:ok, inv.workspace}
      end
    else
      {:error, :not_found} -> {:error, :invalid}
      other -> other
    end
  end

  defp check_acceptable(%SchoolInvitation{status: :pending} = inv) do
    cond do
      inv.expires_at && DateTime.compare(DateTime.utc_now(), inv.expires_at) == :gt -> {:error, :expired}
      true -> :ok
    end
  end

  defp check_acceptable(_), do: {:error, :invalid}

  defp check_email(%SchoolInvitation{email: email}, %User{email: user_email}) do
    if to_string(email) == to_string(user_email), do: :ok, else: {:error, :email_mismatch}
  end

  defp active_member_email?(%Workspace{id: ws_id}, email) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Enum.any?(fn m -> to_string(m.user.email) == to_string(email) end)
  end

  defp gen_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
```

- [ ] **Step 5: Run + commit**

Run: `mix test test/teacher_assistant/accounts/school_invitations_test.exs` → 5 pass.

```bash
git add -A
git commit -m "feat(accounts): school invitations — invite (+email), accept with email/expiry/status guards, revoke"
```

---

### Task 5: Scope branching by workspace kind + workspace-select redirect

**Files:**
- Modify: `lib/teacher_assistant/scope.ex`, `lib/teacher_assistant/accounts/workspaces.ex`, `lib/teacher_assistant_web/controllers/workspace_controller.ex`
- Test: `test/teacher_assistant/accounts/workspaces_test.exs` (extend)

**Interfaces:**
- Consumes: `Schools.fetch_school_membership/2`, `Workspace.kind`.
- Produces: `%Scope{}` with `current_roles` (list) and `current_membership` (schools); `current_workspace_type: :personal_teacher | :school`. `Workspaces.scope_for/3` resolves both kinds; a school with no active membership → `{:error, :not_a_member}`.

- [ ] **Step 1: Write the failing test**

Extend `test/teacher_assistant/accounts/workspaces_test.exs` (read it first for its setup; add):

```elixir
  test "scope_for resolves a school workspace via active membership", %{user: user} do
    {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(user, %{name: "École Scope"})
    assert {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
    assert scope.current_workspace_type == :school
    assert :head in scope.current_roles
  end

  test "scope_for rejects a school the user is not a member of", %{user: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(head, %{name: "École X"})
    assert {:error, :not_a_member} = TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
  end
```

(If the file's setup doesn't bind `user`, add `setup do %{user: TeacherAssistant.TeacherFixtures.user_fixture()} end` or adapt to the existing setup.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/accounts/workspaces_test.exs`
Expected: the 2 new tests FAIL (school branch not implemented).

- [ ] **Step 3: Add scope fields**

In `lib/teacher_assistant/scope.ex`, add `:current_roles` and `:current_membership` to the `defstruct` list (after `:current_role`).

- [ ] **Step 4: Branch `scope_for/3`**

Replace `lib/teacher_assistant/accounts/workspaces.ex` with:

```elixir
defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Academics, Scope}
  alias TeacherAssistant.Accounts.Schools

  def ensure_personal_workspace!(user), do: Academics.ensure_personal_workspace!(user)

  def scope_for(user, workspace_id, context_id \\ nil)

  def scope_for(user, nil, context_id) do
    ws = ensure_personal_workspace!(user)
    scope_for(user, ws.id, context_id)
  end

  def scope_for(user, workspace_id, context_id) do
    case Academics.get_personal_workspace(workspace_id) do
      {:ok, %{kind: :personal} = ws} -> personal_scope(user, ws, context_id)
      {:ok, %{kind: :school} = ws} -> school_scope(user, ws)
      _ -> {:error, :workspace_not_found}
    end
  end

  defp personal_scope(user, ws, context_id) do
    if ws.owner_user_id == user.id do
      year = Academics.current_academic_year(ws)

      {:ok,
       %Scope{
         current_user: user,
         current_workspace: ws,
         current_workspace_type: :personal_teacher,
         current_role: :teacher,
         current_roles: [:teacher],
         current_membership: nil,
         current_academic_year: year,
         current_context: Academics.resolve_current_context(ws, year, context_id)
       }}
    else
      {:error, :workspace_not_found}
    end
  end

  defp school_scope(user, ws) do
    case Schools.fetch_school_membership(ws, user) do
      {:ok, membership} ->
        {:ok,
         %Scope{
           current_user: user,
           current_workspace: ws,
           current_workspace_type: :school,
           current_role: List.first(membership.roles),
           current_roles: membership.roles,
           current_membership: membership,
           current_academic_year: nil,
           current_context: nil
         }}

      {:error, :not_a_member} ->
        {:error, :not_a_member}
    end
  end
end
```

Note: `get_personal_workspace/1` is `Ash.get(Workspace, id, ...)` — it fetches any workspace by id regardless of kind (the name is legacy from Task 1; keep it). Confirm it returns `{:ok, ws}`/`{:error, _}`.

- [ ] **Step 5: Redirect after select by kind**

In `workspace_controller.ex` `select/2`, branch the redirect on the resolved scope's type:

```elixir
    case Workspaces.scope_for(user, workspace_id) do
      {:ok, scope} ->
        to = if scope.current_workspace_type == :school, do: ~p"/school", else: ~p"/teacher"

        conn
        |> put_session(:workspace_id, workspace_id)
        |> put_flash(:info, gettext("Workspace selected"))
        |> redirect(to: to)

      {:error, _} ->
        conn
        |> delete_session(:workspace_id)
        |> put_flash(:error, gettext("Workspace not found or access denied"))
        |> redirect(to: ~p"/teacher")
    end
```

(`delete_session(:workspace_id)` clears a stale school id — the switch-fallback guard. Add `import TeacherAssistantWeb.Gettext` if not already available via `use TeacherAssistantWeb, :controller`.)

- [ ] **Step 6: Run + commit**

Run: `mix test test/teacher_assistant/accounts/workspaces_test.exs` → all pass (incl. 2 new). Then `mix test` → full suite green.

```bash
git add -A
git commit -m "feat(scope): resolve school workspaces via membership; redirect + stale-session fallback"
```

---

### Task 6: `Accounts.Permissions` helper + `LiveUserAuth` school scope + routes

**Files:**
- Create: `lib/teacher_assistant/accounts/permissions.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (school routes), `lib/teacher_assistant_web/live_user_auth.ex` (confirm scope reaches LiveViews — read it first)
- Test: `test/teacher_assistant/accounts/permissions_test.exs`

**Interfaces:**
- Consumes: `%Scope{current_workspace_type, current_roles}`.
- Produces: `Permissions.member?/1`, `head?/1`, `bursar?/1` (all take a `%Scope{}`); the `/school`, `/school/members`, `/school/settings`, `/schools/invitations/:token` route stubs (LiveViews land in Tasks 7-9, but the routes are declared here so mounts can redirect).

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/accounts/permissions_test.exs`:

```elixir
defmodule TeacherAssistant.Accounts.PermissionsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Scope

  test "head? and member? read the school roles" do
    head = %Scope{current_workspace_type: :school, current_roles: [:head, :teacher]}
    plain = %Scope{current_workspace_type: :school, current_roles: [:teacher]}
    personal = %Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]}

    assert Permissions.head?(head)
    refute Permissions.head?(plain)
    assert Permissions.member?(plain)
    refute Permissions.member?(personal)
    refute Permissions.bursar?(plain)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs`
Expected: FAIL (`Permissions` undefined).

- [ ] **Step 3: Implement the helper**

`lib/teacher_assistant/accounts/permissions.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Permissions do
  @moduledoc """
  Coarse, role-based access checks for school workspaces (P2.1).

  Permissions in the domain split on three axes — pedagogical, disciplinary,
  and financial (see docs/domain/05 §1). P2.1 implements only coarse role
  checks; the fine-grained per-axis matrix arrives with the features it
  protects (bulletins → P2.3, fees → P2.4).
  """
  alias TeacherAssistant.Scope

  def member?(%Scope{current_workspace_type: :school}), do: true
  def member?(_), do: false

  def head?(%Scope{current_workspace_type: :school, current_roles: roles}),
    do: :head in (roles || [])

  def head?(_), do: false

  def bursar?(%Scope{current_workspace_type: :school, current_roles: roles}),
    do: :bursar in (roles || [])

  def bursar?(_), do: false
end
```

- [ ] **Step 4: Declare the school routes**

Read `lib/teacher_assistant_web/live_user_auth.ex` to confirm the `:live_user_required` on_mount builds `current_scope` for LiveViews (it does for `/teacher`). In `router.ex`, inside the same `ash_authentication_live_session :teacher_workspace` block, add:

```elixir
      live "/school", School.DashboardLive, :index
      live "/school/members", School.MembersLive, :index
      live "/school/settings", School.SettingsLive, :index
```

and the invitation accept route — a LiveView is fine but the accept action mutates, so use a controller in the first browser scope (with the other `get` routes):

```elixir
    get "/schools/invitations/:token", SchoolInvitationController, :show
    post "/schools/invitations/:token/accept", SchoolInvitationController, :accept
```

The LiveView modules (`School.DashboardLive` etc.) and `SchoolInvitationController` are created in Tasks 7-9. **To keep this task compiling and green, create minimal stubs now** — each LiveView renders `<Layouts.app>` with just a `page_header` placeholder, and the controller renders "not found" — then Tasks 7-9 flesh them out. (Stubs are cheap and let the routes exist so mounts/redirects can be tested incrementally.)

Minimal stub example `lib/teacher_assistant_web/live/school/dashboard_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :scope, socket.assigns.current_scope)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-dashboard" class="space-y-4">
        <.page_header eyebrow={gettext("École")} title={@current_scope.current_workspace.name} />
      </section>
    </Layouts.app>
    """
  end
end
```

Create analogous stubs for `School.MembersLive` (`#school-members`) and `School.SettingsLive` (`#school-settings`), and a `SchoolInvitationController` with `show`/`accept` returning `text(conn, "stub")` for now.

- [ ] **Step 5: Run + commit**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs` → pass; `mix compile --warning-as-errors` clean; `mix test` full suite green.

```bash
git add -A
git commit -m "feat(accounts): coarse Permissions helper; declare school routes + LiveView stubs"
```

---

### Task 7: School shell nav + stub dashboard + workspace switcher + create-school

**Files:**
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (workspace switcher + school nav), `lib/teacher_assistant_web/live/school/dashboard_live.ex` (flesh out), `lib/teacher_assistant_web/controllers/workspace_controller.ex` (add `create` action)
- Modify: `lib/teacher_assistant_web/router.ex` (create-school route)
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs`, `test/teacher_assistant_web/components/workspace_switcher_test.exs`

**Interfaces:**
- Consumes: `Schools.list_workspaces_for/1`, `Schools.create_school/2`, `Permissions`, `%Scope{}`.
- Produces: a workspace switcher in the top bar (`#workspace-switcher`) listing personal + schools with an "École" chip; a `POST /workspaces` create-school route → `WorkspaceController.create`; school nav (`#school-nav`) with Members/Settings(Head)/dashboard; DOM ids `#school-dashboard`, `#create-school`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/dashboard_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, user: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Central"})
    conn = get(conn, ~p"/teacher/../workspaces/select/#{school.id}")
    # follow the redirect into the school
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end
end
```

(If `~p"/teacher/../workspaces/select/#{id}"` path-normalization is awkward, drive selection by putting `workspace_id` in the session directly via the controller: `conn = get(conn, ~p"/workspaces/select/#{school.id}")` then `live(conn, ~p"/school")`. Use the real select route `~p"/workspaces/select/#{school.id}"`.)

`test/teacher_assistant_web/components/workspace_switcher_test.exs`:

```elixir
defmodule TeacherAssistantWeb.WorkspaceSwitcherTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "the switcher lists the personal workspace and member schools", %{conn: conn, user: user} do
    {:ok, _school} = Schools.create_school(user, %{name: "École Deux"})
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "École Deux"
    assert html =~ "id=\"workspace-switcher\""
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs test/teacher_assistant_web/components/workspace_switcher_test.exs`
Expected: FAIL (no `#workspace-switcher`, `#school-nav`).

- [ ] **Step 3: Add the create-school action + route**

In `router.ex` first browser scope: `post "/workspaces", WorkspaceController, :create`. In `workspace_controller.ex`:

```elixir
  def create(conn, %{"school" => %{"name" => name}}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    case name && String.trim(name) != "" && TeacherAssistant.Accounts.Schools.create_school(user, %{name: name}) do
      {:ok, school} ->
        conn |> put_session(:workspace_id, school.id) |> redirect(to: ~p"/school")

      _ ->
        conn |> put_flash(:error, gettext("Enter a school name")) |> redirect(to: ~p"/teacher")
    end
  end
```

- [ ] **Step 4: Workspace switcher + school nav in `layouts.ex`**

Read `layouts.ex` around the existing `#main-nav`/class-switcher. Compute the workspace list in the `app/1` component (it already loads scope). Add, in the top bar, a `#workspace-switcher` dropdown listing `Schools.list_workspaces_for(@current_scope.current_user)` — each item links to `~p"/workspaces/select/#{ws.id}"`, schools show a small "École" chip; a footer item is a `<.form for={%{}} action={~p"/workspaces"} method="post">` with a name input + `#create-school` submit ("Create a school"). Then branch the nav: when `@current_scope.current_workspace_type == :school`, render `#school-nav` (links: Dashboard `~p"/school"`, Members `~p"/school/members"`, and Settings `~p"/school/settings"` only if `Permissions.head?(@current_scope)`); otherwise the existing teacher `#main-nav`. Keep `#main-nav` and its ids intact for the personal branch (existing navigation tests depend on them).

- [ ] **Step 5: Flesh out the school dashboard**

Replace the stub `dashboard_live.ex` render with a real stub-content dashboard: `page_header` (school name), a `<.stat>`-style member count via `length(Schools.list_members(...))`, and an `<.empty_state>` "Classes & enrollment coming next" (the P2.2 hook). Guard mount: if `@current_scope.current_workspace_type != :school`, `push_navigate(to: ~p"/teacher")`.

- [ ] **Step 6: Run + commit**

Run the two test files → green; `mix test` full suite green (existing navigation tests still pass — personal `#main-nav` intact).

```bash
git add -A
git commit -m "feat(school): workspace switcher (personal + schools), create-school, school nav + dashboard"
```

---

### Task 8: Members LiveView — list, invite, revoke, role-edit/deactivate (Head-gated)

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/members_live.ex` (flesh out the stub)
- Test: `test/teacher_assistant_web/live/school/members_live_test.exs`

**Interfaces:**
- Consumes: `Schools.list_members/1`, `list_pending_invitations/1`, `invite_member/3`, `revoke_invitation/1`, `update_member_roles/2`, `deactivate_member/1`, `SchoolRoles.all/0` + `label/1`, `Permissions.head?/1`.
- Produces: `#school-members`, `#members-table`, `#member-row-<id>`, `#invite-form`, `#invitations-list`, `#invitation-<id>`, `#invite-revoke-<id>`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant_web/live/school/members_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.MembersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  defp enter_school(conn, school) do
    get(conn, ~p"/workspaces/select/#{school.id}")
  end

  test "head sees members, can invite, and sees the pending invitation", %{conn: conn, user: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Membres"})
    conn = enter_school(conn, school)
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#school-members")
    assert has_element?(view, "#members-table")
    assert has_element?(view, "#invite-form")

    view
    |> form("#invite-form", %{"invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}})
    |> render_submit()

    assert has_element?(view, "#invitations-list", "prof@example.com")
  end

  test "a non-head member does not see the invite form", %{conn: conn, user: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Gate"})
    member = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})
    {:ok, _} = Schools.accept_invitation(inv.token, member)

    conn = conn |> log_in_user(member) |> get(~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/members")

    assert has_element?(view, "#members-table")
    refute has_element?(view, "#invite-form")
  end
end
```

(Confirm the test helper for logging in a specific user — `register_and_log_in_user` sets `%{user: user}`; for the second test you need to log in `member`. Check `TeacherAssistantWeb.ConnCase` for a `log_in_user/2` helper; if it's named differently, adapt. If none exists, register the member via the conn's session by using the same mechanism `register_and_log_in_user` uses.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/school/members_live_test.exs`
Expected: FAIL (stub has no `#members-table`/`#invite-form`).

- [ ] **Step 3: Implement the Members LiveView**

Flesh out `members_live.ex`: mount guards `member?` (redirect non-members to `/teacher`); assigns `members`, `invitations`, `head? = Permissions.head?(scope)`, and an invite form. Render (Tableau kit):
- `page_header` "Membres";
- `#members-table` responsive table (Nom = `m.user.email` · Rôles = `m.roles |> Enum.map(&SchoolRoles.label/1) |> Enum.join(", ")` · Statut · Head-only actions: a role-edit control and a deactivate button `#member-deactivate-<id>`), each row `#member-row-<id>`;
- `:if={@head?}` `#invite-form` (`<.form for={@invite_form} phx-submit="invite">` with an email input and role checkboxes from `SchoolRoles.all()`);
- `#invitations-list` with `#invitation-<id>` rows (email + roles + `#invite-revoke-<id>` button, Head only).

Handlers: `"invite"` → `Schools.invite_member(school, current_user, %{email, roles})` (roles default `["teacher"]`; convert strings to atoms with `String.to_existing_atom/1`), reload, flash on `{:error, :already_member}`; `"revoke_invite"` (`phx-value-id`) → fetch pending invitation by id scoped to the school, `revoke_invitation`, reload; `"deactivate_member"` → resolve membership scoped to the school, `deactivate_member`, flash on `{:error, :last_head}`; `"set_roles"` → `update_member_roles`, flash on `{:error, :last_head}`. Every mutation re-checks `head?` server-side (defense-in-depth, not just template hiding).

- [ ] **Step 4: Run + commit**

Run: `mix test test/teacher_assistant_web/live/school/members_live_test.exs` → green.

```bash
git add -A
git commit -m "feat(school): members page — list, invite, revoke, role-edit/deactivate (Head-gated)"
```

---

### Task 9: Settings LiveView + invitation accept controller

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex`, `lib/teacher_assistant_web/controllers/school_invitation_controller.ex` (flesh out stubs)
- Create: `lib/teacher_assistant_web/controllers/school_invitation_html.ex` + `school_invitation_html/show.html.heex`
- Test: `test/teacher_assistant_web/live/school/settings_live_test.exs`, `test/teacher_assistant_web/controllers/school_invitation_controller_test.exs`

**Interfaces:**
- Consumes: `Schools.fetch_invitation_by_token/1`, `accept_invitation/2`, `Academics.update_*`? (no — school name update via a small `Schools.rename_school/2`), `Permissions.head?/1`.
- Produces: `Schools.rename_school(%Workspace{}, name) :: {:ok, %Workspace{}}`; `#school-settings` form; `GET/POST /schools/invitations/:token`.

- [ ] **Step 1: Add `rename_school/2` to the Schools context**

In `schools.ex`:

```elixir
  def rename_school(%Workspace{} = school, name) do
    school |> Ash.Changeset.for_update(:update, %{name: name}) |> Ash.update(authorize?: false)
  end
```

- [ ] **Step 2: Write the failing tests**

`test/teacher_assistant_web/live/school/settings_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "head renames the school", %{conn: conn, user: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Ancien Nom"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#school-settings")
    view |> form("#school-settings", %{"school" => %{"name" => "Nouveau Nom"}}) |> render_submit()

    assert TeacherAssistant.Academics.get_personal_workspace(school.id) |> elem(1) |> Map.get(:name) ==
             "Nouveau Nom"
  end
end
```

`test/teacher_assistant_web/controllers/school_invitation_controller_test.exs`:

```elixir
defmodule TeacherAssistantWeb.SchoolInvitationControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "accepting a matching invitation joins the school", %{conn: conn, user: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "École Accept"})
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/school"
    assert {:ok, _m} = Schools.fetch_school_membership(school, user)
  end

  test "a mismatched invitation is rejected", %{conn: conn} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "École Mismatch"})
    {:ok, inv} = Schools.invite_member(school, head, %{email: "someone@example.com", roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/teacher"
    refute Schools.fetch_school_membership(school, conn.assigns.current_user) |> match?({:ok, _})
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run both new test files → FAIL (stubs).

- [ ] **Step 4: Implement Settings LiveView**

Flesh out `settings_live.ex`: mount guards `head?` (non-head → `push_navigate(~p"/school")`); `#school-settings` `<.form phx-submit="save">` with a name input prefilled from `@current_scope.current_workspace.name`; handler `"save"` → `Schools.rename_school(scope.current_workspace, name)`, reassign scope's workspace, flash success.

- [ ] **Step 5: Implement the invitation controller + template**

`school_invitation_controller.ex`:
- `show/2`: `fetch_invitation_by_token(token)`; render `:show` with the invitation + school name and (if a current_user is present) whether their email matches. If not signed in, the template shows a "sign in / register to accept" prompt linking to sign-in with a return to this token.
- `accept/2`: resolve current_user (`conn.assigns[:current_user] || load_user(session)`); `Schools.accept_invitation(token, user)`; on `{:ok, school}` → put `workspace_id` in session, redirect `/school`; on error → flash the reason, redirect `/teacher`.

`school_invitation_html.ex` (`use TeacherAssistantWeb, :html`, `embed_templates`) + `school_invitation_html/show.html.heex` rendering the standalone accept screen (can reuse `Layouts.app` or a minimal layout — use `Layouts.app` so signed-in users keep chrome).

- [ ] **Step 6: Run + commit**

Run both test files → green; `mix test` full suite green.

```bash
git add -A
git commit -m "feat(school): settings (rename, Head-only) + invitation accept controller"
```

---

### Task 10: Gettext extraction + FR translations + full precommit gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`
Expected: new msgids for the school UI + role labels appear.

- [ ] **Step 2: Fill FR msgstr**

In `priv/gettext/fr/LC_MESSAGES/default.po`, set `msgstr` for the new empty entries. The role labels are already French (identity). Use exactly:

| msgid | FR msgstr |
|---|---|
| École | École |
| Members | Membres |
| Settings | Paramètres |
| Create a school | Créer un établissement |
| Enter a school name | Saisissez le nom de l'établissement |
| Workspace selected | Espace sélectionné |
| Workspace not found or access denied | Espace introuvable ou accès refusé |
| Invite staff | Inviter un membre |
| Classes & enrollment coming next | Classes et inscriptions à venir |
| Chef d'établissement | Chef d'établissement |
| Censeur | Censeur |
| Surveillant général | Surveillant général |
| Intendant | Intendant |
| Animateur pédagogique | Animateur pédagogique |
| Professeur principal | Professeur principal |
| Enseignant | Enseignant |
| Conseiller d'orientation | Conseiller d'orientation |
| Documentaliste | Documentaliste |
| Nom | Nom |
| Rôles | Rôles |
| Statut | Statut |
| Revoke | Révoquer |
| Deactivate | Désactiver |
| Accept the invitation | Accepter l'invitation |
| Join %{school} | Rejoindre %{school} |

Only fill entries `gettext.extract` actually added and that are empty; never overwrite existing non-empty msgstr; skip any listed msgid that wasn't extracted or already exists translated (e.g. "Nom", "Enseignant", "Date" may already be present from earlier phases — leave them).

- [ ] **Step 3: Full gate**

Run: `mix precommit`
Expected: compile (warnings-as-errors) clean, format clean, ALL tests pass (≈170: 150 prior + ~20 new).

- [ ] **Step 4: Commit**

```bash
git add priv/gettext
git commit -m "chore(i18n): extract + FR translations for P2.1 school layer"
```

---

## Self-Review (done at plan time)

- **Spec coverage:** §2 data model → Tasks 1-2; §3 context API → Tasks 3-4 (+ rename_school in 9); §4 scope & switching → Tasks 5, 7; §5 UI + gating → Tasks 6-9; §6 migration → Task 1 (+2); §7 testing folded per task; §8 DoD satisfied by Tasks 5-9; §9 guardrails (enums, gettext, kit) throughout. Deliberately out of scope (spec §1): academic structure, bulletins, fees, fine-grained matrix, join-requests, notifications — no tasks.
- **Type consistency:** `Workspace` (kind/owner_user_id/name) consistent Tasks 1-9; `SchoolMembership` fields (`roles` list, `active`, `status`) consistent; `Schools` function signatures match their call sites (`create_school/2`, `fetch_school_membership/2`, `invite_member/3`, `accept_invitation/2`, `list_workspaces_for/1`, `rename_school/2`); `Scope` gains `current_roles`/`current_membership` in Task 5 and every later consumer (`Permissions`, layouts, LiveViews) reads those exact names; `Permissions.head?/member?/bursar?` take `%Scope{}`; route paths `/school`, `/school/members`, `/school/settings`, `/schools/invitations/:token`, `/workspaces` and `/workspaces/select/:id` consistent across Tasks 5-9.
- **Placeholder scan:** the two "create minimal stubs, flesh out later" instructions (Task 6 → Tasks 7-9) are explicit and sequenced, not vague; all code steps carry real code. `get_personal_workspace/1` is intentionally the by-id fetch reused for any kind (noted in Task 5).
- **Risk note:** Task 1 is the heavy one (45-reference rename + column renames); it is isolated with its own gate and a "150 tests stay green" bar, and the migration step flags the rename-vs-drop pitfall explicitly.
```
