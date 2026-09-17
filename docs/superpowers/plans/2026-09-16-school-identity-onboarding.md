# School Identity & Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a school a real Cameroon identity + true ownership, and gate operating (marks/attendance/bulletins) behind operator verification, via a self-serve create → onboarding flow and an operator verification screen.

**Architecture:** A new `SchoolProfile` Ash resource holds the school's identity + verification, 1:1 with the school `Workspace` (which stays the lean tenant). `create_school` becomes transactional (Workspace + SchoolProfile + `:head` membership). The school-scope `Scope` carries a `school_verified?` flag loaded at mount; operating entry points check it. A creation LiveView + operator LiveView bracket the lifecycle.

**Tech Stack:** Elixir, Phoenix LiveView 1.1, Ash 3 + AshPostgres, Postgres, Gettext (bilingual FR/EN).

**Spec:** `docs/superpowers/specs/2026-09-16-school-identity-onboarding-design.md` — read it alongside this plan.

## Global Constraints

- **No bare `:atom` attributes** — every enumerated attribute is a dedicated `Ash.Type.Enum` (project rule). Enum modules use `use Ash.Type.Enum, values: [...]`; bilingual display labels live in a companion module with `label/1` + `all/0`, mirroring `lib/teacher_assistant/accounts/school_roles.ex`.
- **All domain calls use `authorize?: false`** (current house pattern); authorization is enforced in the web/context layer. Real Ash policies are Increment 3, not here.
- **Bilingual:** all user-facing strings wrapped in `gettext(...)`. Default locale `"fr"`.
- **TDD:** every production change has a failing test written and run first. Full suite (`mix test`) must stay green; `mix compile --warnings-as-errors` and `mix format` must pass before each commit.
- **Ash migrations:** generate with `mix ash.codegen <name>`; apply with `mix ash.setup` (dev) / handled by `test` alias (test). Never hand-write the migration.
- **Personal-teacher workspaces are untouched** — no verification concept applies to `:personal`.

---

### Task 1: Reference-data enums + bilingual labels

**Files:**
- Create: `lib/teacher_assistant/accounts/school_type.ex`, `school_subsystem.ex`, `school_sector.ex`, `cameroon_region.ex`, `school_verification_status.ex`
- Create labels: `lib/teacher_assistant/accounts/school_types.ex`, `school_sectors.ex`, `cameroon_regions.ex`, `school_subsystems.ex`, `school_verification_statuses.ex`
- Test: `test/teacher_assistant/accounts/school_enums_test.exs`

**Interfaces:**
- Produces enum types `TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion, SchoolVerificationStatus}` and label modules with `label/1` and `all/0` returning `[atom]` in display order.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.SchoolEnumsTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Accounts.{
    SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion, SchoolVerificationStatus,
    SchoolTypes, SchoolSubsystems, SchoolSectors, CameroonRegions, SchoolVerificationStatuses
  }

  test "enum value sets" do
    assert :bilingual in SchoolSubsystem.values()
    assert :francophone in SchoolSubsystem.values()
    assert :private_confessional in SchoolSector.values()
    assert :northwest in CameroonRegion.values()
    assert length(CameroonRegion.values()) == 10
    assert :gbhs in SchoolType.values()
    assert Enum.sort(SchoolVerificationStatus.values()) == [:rejected, :unverified, :verified]
  end

  test "every value has a non-empty label and all/0 covers the value set" do
    for {type, labels} <- [
          {SchoolType, SchoolTypes}, {SchoolSubsystem, SchoolSubsystems},
          {SchoolSector, SchoolSectors}, {CameroonRegion, CameroonRegions},
          {SchoolVerificationStatus, SchoolVerificationStatuses}
        ] do
      assert Enum.sort(labels.all()) == Enum.sort(type.values())
      for v <- type.values(), do: assert is_binary(labels.label(v)) and labels.label(v) != ""
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/school_enums_test.exs`
Expected: FAIL — modules not defined.

- [ ] **Step 3: Create the enum modules**

```elixir
# lib/teacher_assistant/accounts/school_type.ex
defmodule TeacherAssistant.Accounts.SchoolType do
  use Ash.Type.Enum,
    values: [:lycee, :ces_ceg, :lycee_technique, :cetic, :gss, :ghs, :gbss, :gbhs, :gtc, :gths, :sar_sm]
end

# lib/teacher_assistant/accounts/school_subsystem.ex
defmodule TeacherAssistant.Accounts.SchoolSubsystem do
  use Ash.Type.Enum, values: [:francophone, :anglophone, :bilingual]
end

# lib/teacher_assistant/accounts/school_sector.ex
defmodule TeacherAssistant.Accounts.SchoolSector do
  use Ash.Type.Enum, values: [:public, :private_lay, :private_confessional, :community]
end

# lib/teacher_assistant/accounts/cameroon_region.ex
defmodule TeacherAssistant.Accounts.CameroonRegion do
  use Ash.Type.Enum,
    values: [:adamawa, :centre, :east, :far_north, :littoral, :north, :northwest, :south, :southwest, :west]
end

# lib/teacher_assistant/accounts/school_verification_status.ex
defmodule TeacherAssistant.Accounts.SchoolVerificationStatus do
  use Ash.Type.Enum, values: [:unverified, :verified, :rejected]
end
```

- [ ] **Step 4: Create the label modules** (mirror `school_roles.ex`)

```elixir
# lib/teacher_assistant/accounts/school_types.ex
defmodule TeacherAssistant.Accounts.SchoolTypes do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:lycee, :ces_ceg, :lycee_technique, :cetic, :gss, :ghs, :gbss, :gbhs, :gtc, :gths, :sar_sm]
  def all, do: @order
  def label(:lycee), do: gettext("Lycée")
  def label(:ces_ceg), do: gettext("CES / CEG")
  def label(:lycee_technique), do: gettext("Lycée technique")
  def label(:cetic), do: gettext("CETIC")
  def label(:gss), do: gettext("Government Secondary School (GSS)")
  def label(:ghs), do: gettext("Government High School (GHS)")
  def label(:gbss), do: gettext("Govt Bilingual Secondary School (GBSS)")
  def label(:gbhs), do: gettext("Govt Bilingual High School (GBHS)")
  def label(:gtc), do: gettext("Government Technical College (GTC)")
  def label(:gths), do: gettext("Government Technical High School (GTHS)")
  def label(:sar_sm), do: gettext("SAR/SM")
end

# lib/teacher_assistant/accounts/school_subsystems.ex
defmodule TeacherAssistant.Accounts.SchoolSubsystems do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:francophone, :anglophone, :bilingual]
  def all, do: @order
  def label(:francophone), do: gettext("Francophone")
  def label(:anglophone), do: gettext("Anglophone")
  def label(:bilingual), do: gettext("Bilingue")
end

# lib/teacher_assistant/accounts/school_sectors.ex
defmodule TeacherAssistant.Accounts.SchoolSectors do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:public, :private_lay, :private_confessional, :community]
  def all, do: @order
  def label(:public), do: gettext("Public")
  def label(:private_lay), do: gettext("Privé laïc")
  def label(:private_confessional), do: gettext("Privé confessionnel")
  def label(:community), do: gettext("Communautaire")
end

# lib/teacher_assistant/accounts/cameroon_regions.ex
defmodule TeacherAssistant.Accounts.CameroonRegions do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:adamawa, :centre, :east, :far_north, :littoral, :north, :northwest, :south, :southwest, :west]
  def all, do: @order
  def label(:adamawa), do: gettext("Adamaoua")
  def label(:centre), do: gettext("Centre")
  def label(:east), do: gettext("Est")
  def label(:far_north), do: gettext("Extrême-Nord")
  def label(:littoral), do: gettext("Littoral")
  def label(:north), do: gettext("Nord")
  def label(:northwest), do: gettext("Nord-Ouest")
  def label(:south), do: gettext("Sud")
  def label(:southwest), do: gettext("Sud-Ouest")
  def label(:west), do: gettext("Ouest")
end

# lib/teacher_assistant/accounts/school_verification_statuses.ex
defmodule TeacherAssistant.Accounts.SchoolVerificationStatuses do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:unverified, :verified, :rejected]
  def all, do: @order
  def label(:unverified), do: gettext("Non vérifié")
  def label(:verified), do: gettext("Vérifié")
  def label(:rejected), do: gettext("Rejeté")
end
```

- [ ] **Step 5: Run test + format**

Run: `mix test test/teacher_assistant/accounts/school_enums_test.exs && mix format`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/school_type.ex lib/teacher_assistant/accounts/school_subsystem.ex lib/teacher_assistant/accounts/school_sector.ex lib/teacher_assistant/accounts/cameroon_region.ex lib/teacher_assistant/accounts/school_verification_status.ex lib/teacher_assistant/accounts/school_types.ex lib/teacher_assistant/accounts/school_subsystems.ex lib/teacher_assistant/accounts/school_sectors.ex lib/teacher_assistant/accounts/cameroon_regions.ex lib/teacher_assistant/accounts/school_verification_statuses.ex test/teacher_assistant/accounts/school_enums_test.exs
git commit -m "feat: school identity reference enums + bilingual labels"
```

---

### Task 2: SchoolProfile resource + migration

**Files:**
- Create: `lib/teacher_assistant/accounts/school_profile.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (register the resource in the `resources do ... end` block)
- Test: `test/teacher_assistant/accounts/school_profile_test.exs`

**Interfaces:**
- Produces `TeacherAssistant.Accounts.SchoolProfile` with actions `:create`, `:update`, `:verify`, `:reject`, `:read`, `:destroy`; identity `unique_workspace` on `workspace_id`; `verification_status` defaults `:unverified`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.SchoolProfileTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    {:ok, ws} = Workspace |> Ash.Changeset.for_create(:create, %{name: "Lycée X", kind: :school}) |> Ash.create(authorize?: false)
    %{user: user, ws: ws}
  end

  defp create(ws, user, extra \\ %{}) do
    SchoolProfile
    |> Ash.Changeset.for_create(:create, Map.merge(%{
      workspace_id: ws.id, owner_user_id: user.id, school_type: :lycee,
      subsystem: :francophone, sector: :public, region: :centre, town: "Yaoundé"
    }, extra))
    |> Ash.create(authorize?: false)
  end

  test "creates unverified by default", %{ws: ws, user: user} do
    assert {:ok, p} = create(ws, user)
    assert p.verification_status == :unverified
    assert p.owner_user_id == user.id
  end

  test "enforces one profile per workspace", %{ws: ws, user: user} do
    assert {:ok, _} = create(ws, user)
    assert {:error, _} = create(ws, user)
  end

  test "verify sets status, timestamp and verifier", %{ws: ws, user: user} do
    {:ok, p} = create(ws, user)
    op = TeacherFixtures.user_fixture()
    {:ok, p} = p |> Ash.Changeset.for_update(:verify, %{verified_by_user_id: op.id}) |> Ash.update(authorize?: false)
    assert p.verification_status == :verified
    assert p.verified_at
    assert p.verified_by_user_id == op.id
  end

  test "reject records a reason", %{ws: ws, user: user} do
    {:ok, p} = create(ws, user)
    op = TeacherFixtures.user_fixture()
    {:ok, p} = p |> Ash.Changeset.for_update(:reject, %{verified_by_user_id: op.id, rejection_reason: "Nom incomplet"}) |> Ash.update(authorize?: false)
    assert p.verification_status == :rejected
    assert p.rejection_reason == "Nom incomplet"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/school_profile_test.exs`
Expected: FAIL — `SchoolProfile` undefined.

- [ ] **Step 3: Create the resource**

```elixir
# lib/teacher_assistant/accounts/school_profile.ex
defmodule TeacherAssistant.Accounts.SchoolProfile do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "school_profiles"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :workspace_id, :owner_user_id, :short_name, :school_type, :subsystem, :sector,
        :region, :department, :town, :phone, :email, :address, :head_name, :motto,
        :registration_number, :logo_path
      ]
    end

    update :update do
      accept [
        :short_name, :school_type, :subsystem, :sector, :region, :department, :town,
        :phone, :email, :address, :head_name, :motto, :registration_number, :logo_path
      ]
    end

    update :verify do
      accept [:verified_by_user_id]
      change set_attribute(:verification_status, :verified)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:rejection_reason, nil)
    end

    update :reject do
      accept [:verified_by_user_id, :rejection_reason]
      change set_attribute(:verification_status, :rejected)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :short_name, :string, public?: true
    attribute :school_type, TeacherAssistant.Accounts.SchoolType, allow_nil?: false, public?: true
    attribute :subsystem, TeacherAssistant.Accounts.SchoolSubsystem, allow_nil?: false, public?: true
    attribute :sector, TeacherAssistant.Accounts.SchoolSector, allow_nil?: false, public?: true
    attribute :region, TeacherAssistant.Accounts.CameroonRegion, allow_nil?: false, public?: true
    attribute :department, :string, public?: true
    attribute :town, :string, allow_nil?: false, public?: true
    attribute :phone, :string, public?: true
    attribute :email, :string, public?: true
    attribute :address, :string, public?: true
    attribute :head_name, :string, public?: true
    attribute :motto, :string, public?: true
    attribute :registration_number, :string, public?: true
    attribute :logo_path, :string, public?: true

    attribute :verification_status, TeacherAssistant.Accounts.SchoolVerificationStatus,
      allow_nil?: false, default: :unverified, public?: true

    attribute :verified_at, :utc_datetime_usec, public?: true
    attribute :verified_by_user_id, :uuid, public?: true
    attribute :rejection_reason, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :owner_user, TeacherAssistant.Accounts.User do
      source_attribute :owner_user_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_workspace, [:workspace_id]
  end
end
```

- [ ] **Step 4: Register the resource** in `lib/teacher_assistant/accounts.ex` — inside `resources do ... end`, add:

```elixir
    resource TeacherAssistant.Accounts.SchoolProfile
```

- [ ] **Step 5: Generate + apply the migration**

Run: `mix ash.codegen create_school_profiles && mix ash.setup`
Expected: a new migration + snapshot under `priv/repo/migrations` and `priv/resource_snapshots`; DB migrated.

- [ ] **Step 6: Run tests + format**

Run: `mix test test/teacher_assistant/accounts/school_profile_test.exs && mix format`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/accounts.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/accounts/school_profile_test.exs
git commit -m "feat: SchoolProfile resource (identity + verification)"
```

---

### Task 3: Atomic create_school + profile/verify/reject context functions

**Files:**
- Modify: `lib/teacher_assistant/accounts/schools.ex` (`create_school/2` at lines 10-28; add helpers)
- Test: `test/teacher_assistant/accounts/schools_create_test.exs`

**Interfaces:**
- Consumes: `SchoolProfile` (Task 2).
- Produces:
  - `Schools.create_school(user, attrs)` → `{:ok, %Workspace{}}` — now atomic, requiring `attrs` with `:name, :school_type, :subsystem, :sector, :region, :town`; also creates the `SchoolProfile{owner_user_id: user.id, verification_status: :unverified}` and the `:head` membership. Returns `{:error, term}` on any failure with nothing persisted.
  - `Schools.fetch_school_profile(%Workspace{})` → `{:ok, %SchoolProfile{}} | {:error, :not_found}`
  - `Schools.update_school_profile(%SchoolProfile{}, attrs)` → `{:ok, profile}`
  - `Schools.verify_school(%SchoolProfile{}, operator_user_id)` → `{:ok, profile}`
  - `Schools.reject_school(%SchoolProfile{}, operator_user_id, reason)` → `{:ok, profile}`
  - `Schools.list_unverified_schools()` → `[%SchoolProfile{}]` (with `:workspace` and `:owner_user` loaded)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.SchoolsCreateTest do
  use TeacherAssistant.DataCase, async: true
  require Ash.Query
  alias TeacherAssistant.Accounts.{Schools, SchoolProfile, SchoolMembership}
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.TeacherFixtures

  @attrs %{name: "Lycée Bilingue", school_type: :gbhs, subsystem: :bilingual, sector: :public, region: :centre, town: "Yaoundé"}

  test "creates workspace + unverified profile + head membership, with the creator as owner" do
    user = TeacherFixtures.user_fixture()
    assert {:ok, %Workspace{} = school} = Schools.create_school(user, @attrs)
    assert {:ok, profile} = Schools.fetch_school_profile(school)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
    assert profile.subsystem == :bilingual
    assert {:ok, membership} = Schools.fetch_school_membership(school, user)
    assert :head in membership.roles
  end

  test "is atomic: an invalid profile field leaves no workspace, profile or membership" do
    user = TeacherFixtures.user_fixture()
    before_ws = Workspace |> Ash.Query.filter(kind == :school) |> Ash.count!(authorize?: false)
    assert {:error, _} = Schools.create_school(user, Map.delete(@attrs, :region))
    assert Workspace |> Ash.Query.filter(kind == :school) |> Ash.count!(authorize?: false) == before_ws
    assert SchoolProfile |> Ash.count!(authorize?: false) == 0
    assert SchoolMembership |> Ash.count!(authorize?: false) == 0
  end

  test "verify and reject transitions" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, @attrs)
    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, verified} = Schools.verify_school(profile, op.id)
    assert verified.verification_status == :verified
    {:ok, rejected} = Schools.reject_school(verified, op.id, "doc manquant")
    assert rejected.verification_status == :rejected
    assert rejected.rejection_reason == "doc manquant"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/schools_create_test.exs`
Expected: FAIL — `fetch_school_profile/1` undefined and non-atomic create.

- [ ] **Step 3: Rewrite `create_school/2` and add helpers** in `schools.ex`

Add `alias TeacherAssistant.Accounts.SchoolProfile` and `alias TeacherAssistant.Repo` to the aliases, then:

```elixir
  @profile_keys [:short_name, :school_type, :subsystem, :sector, :region, :department, :town,
                 :phone, :email, :address, :head_name, :motto, :registration_number]

  def create_school(%User{} = user, %{} = attrs) do
    name = attrs[:name] || attrs["name"]
    profile_attrs = Map.take(attrs, @profile_keys)

    result =
      Repo.transaction(fn ->
        with {:ok, school} <-
               Workspace
               |> Ash.Changeset.for_create(:create, %{name: name, kind: :school})
               |> Ash.create(authorize?: false),
             {:ok, _profile} <-
               SchoolProfile
               |> Ash.Changeset.for_create(:create, Map.merge(profile_attrs, %{
                 workspace_id: school.id, owner_user_id: user.id
               }))
               |> Ash.create(authorize?: false),
             {:ok, _membership} <-
               SchoolMembership
               |> Ash.Changeset.for_create(:create, %{
                 workspace_id: school.id, user_id: user.id, roles: [:head]
               })
               |> Ash.create(authorize?: false) do
          school
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, school} -> {:ok, school}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_school_profile(%Workspace{id: ws_id}) do
    SchoolProfile
    |> Ash.Query.filter(workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def update_school_profile(%SchoolProfile{} = profile, attrs) do
    profile |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)
  end

  def verify_school(%SchoolProfile{} = profile, operator_user_id) do
    profile
    |> Ash.Changeset.for_update(:verify, %{verified_by_user_id: operator_user_id})
    |> Ash.update(authorize?: false)
  end

  def reject_school(%SchoolProfile{} = profile, operator_user_id, reason) do
    profile
    |> Ash.Changeset.for_update(:reject, %{verified_by_user_id: operator_user_id, rejection_reason: reason})
    |> Ash.update(authorize?: false)
  end

  def list_unverified_schools do
    SchoolProfile
    |> Ash.Query.filter(verification_status == :unverified)
    |> Ash.Query.load([:workspace, :owner_user])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end
```

- [ ] **Step 4: Run test + full suite + format**

Run: `mix test test/teacher_assistant/accounts/schools_create_test.exs && mix test && mix format`
Expected: PASS. (Note: any existing test calling `create_school/2` with only `%{name: ...}` must be updated to pass the required identity fields — grep `create_school` in `test/` and add `school_type: :lycee, subsystem: :francophone, sector: :public, region: :centre, town: "…"`.)

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/schools.ex test/teacher_assistant/accounts/schools_create_test.exs test/
git commit -m "feat: atomic create_school with profile + owner; verify/reject helpers"
```

---

### Task 4: Scope carries verification; school_scope loads the profile

**Files:**
- Modify: `lib/teacher_assistant/scope.ex` (add two struct fields)
- Modify: `lib/teacher_assistant/accounts/workspaces.ex` (`school_scope/3` at lines 42-62)
- Test: `test/teacher_assistant/accounts/workspaces_verification_test.exs`

**Interfaces:**
- Consumes: `Schools.fetch_school_profile/1`, `Schools.verify_school/2`.
- Produces: `Scope` gains `:school_verification_status` (atom | nil) and `school_verified?/1` (`Scope.school_verified?(scope) :: boolean`). Personal scope → `nil` status, `false`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.WorkspacesVerificationTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.{Schools, Workspaces}
  alias TeacherAssistant.Scope
  alias TeacherAssistant.TeacherFixtures

  @attrs %{name: "Lycée V", school_type: :lycee, subsystem: :francophone, sector: :public, region: :centre, town: "Yaoundé"}

  test "school scope reflects verification status" do
    user = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, @attrs)

    {:ok, scope} = Workspaces.scope_for(user, school.id)
    assert scope.school_verification_status == :unverified
    refute Scope.school_verified?(scope)

    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, _} = Schools.verify_school(profile, user.id)

    {:ok, scope2} = Workspaces.scope_for(user, school.id)
    assert scope2.school_verification_status == :verified
    assert Scope.school_verified?(scope2)
  end

  test "personal scope has no verification" do
    user = TeacherFixtures.user_fixture()
    ws = TeacherAssistant.Academics.ensure_personal_workspace!(user)
    {:ok, scope} = Workspaces.scope_for(user, ws.id)
    assert scope.school_verification_status == nil
    refute Scope.school_verified?(scope)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/workspaces_verification_test.exs`
Expected: FAIL — `school_verification_status` key + `school_verified?/1` missing.

- [ ] **Step 3: Add fields + helper to `scope.ex`**

Add `:school_verification_status` to the `defstruct` list, then:

```elixir
  def school_verified?(%__MODULE__{school_verification_status: :verified}), do: true
  def school_verified?(_scope), do: false
```

- [ ] **Step 4: Set the field in `school_scope/3`** (`workspaces.ex`)

Inside `school_scope`, after resolving `membership`, compute the status and add it to the `%Scope{...}`:

```elixir
      {:ok, membership} ->
        year = Academics.current_academic_year(ws)

        status =
          case Schools.fetch_school_profile(ws) do
            {:ok, p} -> p.verification_status
            _ -> :unverified
          end

        {:ok,
         %Scope{
           # ... existing fields ...
           current_context: resolve_assigned_context(ws, year, user, context_id),
           school_verification_status: status
         }}
```

(Personal scope leaves the field `nil` — no change needed there.)

- [ ] **Step 5: Run test + format**

Run: `mix test test/teacher_assistant/accounts/workspaces_verification_test.exs && mix format`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/scope.ex lib/teacher_assistant/accounts/workspaces.ex test/teacher_assistant/accounts/workspaces_verification_test.exs
git commit -m "feat: carry school verification status on Scope"
```

---

### Task 5: Operate-gate — block marks / attendance / bulletins while unverified

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex` (`handle_event("save", ...)` — the `save_marks/2` path)
- Modify: `lib/teacher_assistant_web/live/school/attendance_live.ex` (`handle_event("record", ...)`)
- Modify: the bulletin print controller (`lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` — grep for the action that renders a bulletin)
- Test: `test/teacher_assistant_web/live/school/operate_gate_test.exs`

**Interfaces:**
- Consumes: `Scope.school_verified?/1`.
- Produces: a shared guard. Add to `lib/teacher_assistant/accounts/permissions.ex`:
  `Permissions.operating_allowed?(scope) :: boolean` — `true` unless the scope is a school scope that is not verified (i.e. `scope.current_workspace_type != :school or Scope.school_verified?(scope)`). Personal scope always `true`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.School.OperateGateTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Attendance, Timetables}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée G", school_type: :lycee, subsystem: :francophone, sector: :public, region: :centre, town: "Yaoundé"})
    {:ok, year} = Academics.create_academic_year(school, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    :ok = Timetables.build_default_periods(school)
    period = Timetables.list_periods(school) |> Enum.find(&(&1.kind == :lesson))
    {:ok, _slot} = Timetables.place_slot(cg, %{day: :monday, period_id: period.id, teaching_context_id: tc.id})
    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, period: period, date: ~D[2025-09-08], head: head}
  end

  test "an unverified school cannot record attendance", %{conn: conn, cg: cg, period: period, date: date} do
    {:ok, view, _} = live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")
    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(cg, period, date)
    assert Enum.all?(roll.students, &(&1.status == nil))
  end

  test "a verified school can record attendance", %{conn: conn, school: school, cg: cg, period: period, date: date, head: head} do
    {:ok, p} = Schools.fetch_school_profile(school)
    {:ok, _} = Schools.verify_school(p, head.id)
    {:ok, view, _} = live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")
    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(cg, period, date)
    assert Enum.any?(roll.students, &(&1.status == :present))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/operate_gate_test.exs`
Expected: the "unverified cannot record" test FAILS (attendance is recorded today regardless of verification).

- [ ] **Step 3: Add the guard to `permissions.ex`**

```elixir
  def operating_allowed?(scope) do
    scope.current_workspace_type != :school or TeacherAssistant.Scope.school_verified?(scope)
  end
```

- [ ] **Step 4: Apply the guard at the three operating entry points**

In `attendance_live.ex` `handle_event("record", ...)`, wrap the body:

```elixir
  def handle_event("record", _params, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Permissions.operating_allowed?(scope) ->
        {:noreply, put_flash(socket, :error, gettext("École en attente de vérification — enregistrement indisponible."))}

      authorized?(scope, socket.assigns.slot) ->
        # ... existing record body ...

      true ->
        {:noreply, socket}
    end
  end
```

In `marks_live.ex` `handle_event("save", ...)`, before parsing, add:

```elixir
    if not TeacherAssistantWeb.… # use Permissions.operating_allowed?(socket.assigns.current_scope)
```
concretely:

```elixir
  def handle_event("save", %{"scores" => scores}, socket) do
    if not TeacherAssistant.Accounts.Permissions.operating_allowed?(socket.assigns.current_scope) do
      {:noreply, put_flash(socket, :error, gettext("École en attente de vérification — enregistrement indisponible."))}
    else
      # ... existing parse + save_marks body ...
    end
  end
```

In the bulletin print controller action, before rendering, resolve the scope (the controller has `conn.assigns.current_scope` if assigned by the auth plug; otherwise fetch the profile for the workspace) and, when it's a school and not verified, halt with a flash + redirect back to `/school`. Mirror the existing not-found/redirect handling already in that controller.

- [ ] **Step 5: Run test + full suite + format**

Run: `mix test test/teacher_assistant_web/live/school/operate_gate_test.exs && mix test && mix format`
Expected: PASS. Fix any existing marks/attendance/bulletin test that now needs a verified school by verifying the school in that test's setup.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/permissions.ex lib/teacher_assistant_web/live/teacher/marks_live.ex lib/teacher_assistant_web/live/school/attendance_live.ex lib/teacher_assistant_web/controllers/bulletin_print_controller.ex test/teacher_assistant_web/live/school/operate_gate_test.exs test/
git commit -m "feat: gate marks/attendance/bulletins behind school verification"
```

---

### Task 6: Create-school onboarding screen

**Files:**
- Create: `lib/teacher_assistant_web/live/onboarding/create_school_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add an authenticated live_session `:onboarding` with only `:live_user_required`, route `live "/schools/new", Onboarding.CreateSchoolLive`)
- Modify: `lib/teacher_assistant_web/components/layouts.ex:118-124` (replace the inline create-school form with a `<.link navigate={~p"/schools/new"}>` "Créer un établissement")
- Test: `test/teacher_assistant_web/live/onboarding/create_school_live_test.exs`

**Interfaces:**
- Consumes: `Schools.create_school/2`; the existing `GET /workspaces/select/:id` controller (sets `workspace_id` session then redirects `/school`).
- Produces: route `~p"/schools/new"`; on submit, creates the school and `push_navigate`s to `~p"/workspaces/select/#{school.id}"`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.Academics.Workspace
  require Ash.Query

  setup :register_and_log_in_user

  test "creates an unverified school and switches into it", %{conn: conn, actor: user} do
    {:ok, view, _} = live(conn, ~p"/schools/new")

    assert {:error, {:redirect, %{to: to}}} =
             view
             |> form("#create-school-form", %{school: %{
               name: "Collège Vogt", school_type: "ces_ceg", subsystem: "francophone",
               sector: "private_confessional", region: "centre", town: "Yaoundé"
             }})
             |> render_submit()

    assert to =~ "/workspaces/select/"

    school = Workspace |> Ash.Query.filter(name == "Collège Vogt") |> Ash.read_one!(authorize?: false)
    {:ok, profile} = Schools.fetch_school_profile(school)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/onboarding/create_school_live_test.exs`
Expected: FAIL — route/LiveView missing.

- [ ] **Step 3: Create the LiveView** (form with the six essentials; `<select>`s populated from the label modules `all/0` + `label/1`; ids `#create-school-form`)

```elixir
defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.Accounts.{SchoolTypes, SchoolSubsystems, SchoolSectors, CameroonRegions}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :school))}
  end

  def handle_event("create", %{"school" => p}, socket) do
    attrs = %{
      name: p["name"], school_type: to_atom(p["school_type"]), subsystem: to_atom(p["subsystem"]),
      sector: to_atom(p["sector"]), region: to_atom(p["region"]), town: p["town"]
    }

    case Schools.create_school(socket.assigns.current_scope.current_user, attrs) do
      {:ok, school} -> {:noreply, push_navigate(socket, to: ~p"/workspaces/select/#{school.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Impossible de créer l'établissement — vérifiez les champs."))}
    end
  end

  defp to_atom(nil), do: nil
  defp to_atom(""), do: nil
  defp to_atom(s), do: String.to_existing_atom(s)

  # render/1: a centered card with <.form for={@form} id="create-school-form"
  # phx-submit="create"> containing text inputs name + town, and <.input type="select">
  # for school_type/subsystem/sector/region built from
  # `for t <- SchoolTypes.all(), do: {SchoolTypes.label(t), t}` (etc.), and a submit button.
  # Mirror the markup style of lib/teacher_assistant_web/live/teacher/setup_live.ex.
end
```

- [ ] **Step 4: Add the route + onboarding live_session** in `router.ex`

```elixir
    ash_authentication_live_session :onboarding,
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/schools/new", TeacherAssistantWeb.Onboarding.CreateSchoolLive
    end
```

- [ ] **Step 5: Update the header dropdown** (`layouts.ex:118-124`) — replace the inline `<.form action={~p"/workspaces"}>` with:

```heex
<.link navigate={~p"/schools/new"} class="btn btn-primary btn-xs w-full">
  {gettext("Créer un établissement")}
</.link>
```

- [ ] **Step 6: Run test + full suite + format**

Run: `mix test test/teacher_assistant_web/live/onboarding/create_school_live_test.exs && mix test && mix format`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/onboarding/create_school_live.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/components/layouts.ex test/teacher_assistant_web/live/onboarding/create_school_live_test.exs
git commit -m "feat: self-serve school creation screen"
```

---

### Task 7: Pending-verification banner + setup checklist on the dashboard

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs` (create if absent)

**Interfaces:**
- Consumes: `scope.school_verification_status`.
- Produces: a `#pending-verification` banner rendered when `scope.school_verification_status != :verified`, and a `#setup-checklist` with items keyed `profile`, `year`, `classes`, `staff`.

- [ ] **Step 1: Write the failing test**

```elixir
# in dashboard_live_test.exs, school setup like operate_gate_test.exs
test "shows a pending-verification banner while unverified", %{conn: conn} do
  {:ok, view, _} = live(conn, ~p"/school")
  assert has_element?(view, "#pending-verification")
  assert has_element?(view, "#setup-checklist")
end

test "hides the banner once verified", %{conn: conn, school: school, head: head} do
  {:ok, p} = Schools.fetch_school_profile(school)
  {:ok, _} = Schools.verify_school(p, head.id)
  {:ok, view, _} = live(conn, ~p"/school")
  refute has_element?(view, "#pending-verification")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs`
Expected: FAIL — banner element absent.

- [ ] **Step 3: Add the banner + checklist to `dashboard_live.ex` render**

At the top of the dashboard section, before the existing `cond`, render (when `@current_scope.school_verification_status != :verified`) a `<div id="pending-verification" class="ta-leaf border-l-4 border-warning ...">` with the copy *"Votre établissement est configuré mais pas encore vérifié. Vous pouvez préparer classes et personnel ; la saisie des notes, de l'appel et des bulletins sera débloquée après vérification."* Below it a `<ul id="setup-checklist">` with four `<li>` items (profile / année scolaire / classes / personnel) each showing a done/todo marker computed from existing assigns (`@year`, `@classes`) plus profile-completeness and staff-count checks (add lightweight assigns in `mount`).

- [ ] **Step 4: Run test + format**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs && mix format`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/dashboard_live.ex test/teacher_assistant_web/live/school/dashboard_live_test.exs
git commit -m "feat: pending-verification banner + setup checklist on school dashboard"
```

---

### Task 8: Settings — full profile editing

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex`
- Test: `test/teacher_assistant_web/live/school/settings_profile_test.exs`

**Interfaces:**
- Consumes: `Schools.fetch_school_profile/1`, `Schools.update_school_profile/2`, label modules.
- Produces: a `#school-profile-form` (admin-only, gated by existing `Permissions.admin?`) editing all identity fields except logo (Task 9).

- [ ] **Step 1: Write the failing test**

```elixir
test "an admin edits the full school profile", %{conn: conn, school: school} do
  {:ok, view, _} = live(conn, ~p"/school/settings")
  view |> form("#school-profile-form", %{profile: %{
    short_name: "GBHS", head_name: "M. Ndenge", phone: "+237 6...", motto: "Rigueur",
    registration_number: "AR/2019/001", department: "Mfoundi", address: "BP 100"
  }}) |> render_submit()

  {:ok, p} = Schools.fetch_school_profile(school)
  assert p.short_name == "GBHS"
  assert p.head_name == "M. Ndenge"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/settings_profile_test.exs`
Expected: FAIL — form absent.

- [ ] **Step 3: Add the profile form to `settings_live.ex`** — load the profile in `mount`, render `<.form id="school-profile-form" phx-submit="save_profile">` with inputs for `short_name, school_type, subsystem, sector, region, department, town, phone, email, address, head_name, motto, registration_number` (selects from label modules), and a `handle_event("save_profile", %{"profile" => attrs}, socket)` calling `Schools.update_school_profile/2` then re-loading. Gate render + handler on `Permissions.admin?`.

- [ ] **Step 4: Run test + format**

Run: `mix test test/teacher_assistant_web/live/school/settings_profile_test.exs && mix format`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/settings_live.ex test/teacher_assistant_web/live/school/settings_profile_test.exs
git commit -m "feat: edit full school profile in settings"
```

---

### Task 9: Logo upload, storage & serving

**Files:**
- Modify: `config/config.exs`, `config/dev.exs`, `config/test.exs` (add `config :teacher_assistant, :uploads_dir, ...`)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (`allow_upload` + save)
- Create: `lib/teacher_assistant_web/controllers/school_logo_controller.ex` + route (serve the stored file, members only)
- Test: `test/teacher_assistant_web/live/school/settings_logo_test.exs`

**Interfaces:**
- Consumes: `Schools.update_school_profile/2` (sets `logo_path`).
- Produces: `config :teacher_assistant, :uploads_dir` (dev: `Path.join(File.cwd!(), "priv/uploads")`, test: a `System.tmp_dir!/0` subdir); `GET /school/logo` route → serves `logo_path`.

- [ ] **Step 1: Write the failing test**

```elixir
test "uploading a logo stores a file and sets logo_path", %{conn: conn, school: school} do
  {:ok, view, _} = live(conn, ~p"/school/settings")
  logo = file_input(view, "#school-logo-form", :logo, [%{
    name: "logo.png", content: File.read!("test/support/fixtures/files/1x1.png"), type: "image/png"
  }])
  render_upload(logo, "logo.png")
  view |> element("#school-logo-form") |> render_submit()

  {:ok, p} = Schools.fetch_school_profile(school)
  assert p.logo_path
  assert File.exists?(Path.join(Application.fetch_env!(:teacher_assistant, :uploads_dir), p.logo_path))
end
```

(Add a tiny `test/support/fixtures/files/1x1.png` fixture — a 1×1 PNG.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/settings_logo_test.exs`
Expected: FAIL — upload form absent.

- [ ] **Step 3: Add config + upload handling + serving** — `allow_upload(:logo, accept: ~w(.png .jpg .jpeg), max_entries: 1, max_file_size: 2_000_000)` in `mount`; a `#school-logo-form` with `<.live_file_input>`; `handle_event("save_logo", ...)` consumes the entry, writes it under `uploads_dir/school_logos/<workspace_id>/<uuid>.<ext>`, and stores the relative path via `update_school_profile`. Add `SchoolLogoController` serving the current school's `logo_path` (scoped to a member) and a `get "/school/logo"` route.

- [ ] **Step 4: Run test + full suite + format**

Run: `mix test test/teacher_assistant_web/live/school/settings_logo_test.exs && mix test && mix format`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/config.exs config/dev.exs config/test.exs lib/teacher_assistant_web/live/school/settings_live.ex lib/teacher_assistant_web/controllers/school_logo_controller.ex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/live/school/settings_logo_test.exs test/support/fixtures/files/1x1.png
git commit -m "feat: school logo upload, storage and serving"
```

---

### Task 10: Operator verification screen (`/admin/schools`)

**Files:**
- Create: `lib/teacher_assistant_web/live/admin/schools_live.ex`
- Modify: `lib/teacher_assistant_web/live_user_auth.ex` (add `on_mount(:require_operator, ...)` requiring global `UserRole == :admin`)
- Modify: `lib/teacher_assistant_web/router.ex` (live_session `:operator` with `:live_user_required` + `:require_operator`, route `live "/admin/schools", Admin.SchoolsLive`)
- Modify: `priv/repo/seeds.exs` (note: promote the demo user to `:admin` in dev so the screen is reachable)
- Test: `test/teacher_assistant_web/live/admin/schools_live_test.exs`

**Interfaces:**
- Consumes: `Schools.list_unverified_schools/0`, `Schools.verify_school/2`, `Schools.reject_school/3`. The global role is `User.role` (`TeacherAssistant.Accounts.UserRole`, value `:admin`).
- Produces: on_mount `:require_operator` (halts non-admins to `/`); route `~p"/admin/schools"`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.Admin.SchoolsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  @attrs %{name: "Lycée Op", school_type: :lycee, subsystem: :francophone, sector: :public, region: :centre, town: "Yaoundé"}

  test "a non-admin is redirected", %{conn: conn} = _ctx do
    user = TeacherFixtures.user_fixture()
    conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, user.id)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/schools")
  end

  test "an admin sees an unverified school and verifies it", %{conn: conn} do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, @attrs)
    admin = TeacherFixtures.admin_user_fixture()   # helper sets role: :admin
    conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, admin.id)

    {:ok, view, html} = live(conn, ~p"/admin/schools")
    assert html =~ "Lycée Op"
    view |> element("#verify-#{school.id}") |> render_click()

    {:ok, p} = Schools.fetch_school_profile(school)
    assert p.verification_status == :verified
  end
end
```

(Add `TeacherFixtures.admin_user_fixture/0` — creates a user then sets `role: :admin` via an update action; check how `User.role` is set and add a minimal helper.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant_web/live/admin/schools_live_test.exs`
Expected: FAIL — route/on_mount/LiveView missing.

- [ ] **Step 3: Add the `:require_operator` on_mount** in `live_user_auth.ex`

```elixir
  def on_mount(:require_operator, _params, _session, socket) do
    if socket.assigns[:current_user] && socket.assigns.current_user.role == :admin do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end
```

(It runs after `:live_user_required`, which already assigns `current_user`.)

- [ ] **Step 4: Create `Admin.SchoolsLive`** — `mount` assigns `schools: Schools.list_unverified_schools()`; render a list, each row `#school-row-<id>` showing name (workspace), type/subsystem/sector/region·town, owner email, with `#verify-<id>` (phx-click "verify") and a reject form (`#reject-<id>` with a reason). Handlers call `Schools.verify_school/2` / `reject_school/3` with `socket.assigns.current_scope.current_user.id`, then reload the list.

- [ ] **Step 5: Add the operator live_session + route** in `router.ex`

```elixir
    ash_authentication_live_session :operator,
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_operator}
      ] do
      live "/admin/schools", TeacherAssistantWeb.Admin.SchoolsLive
    end
```

- [ ] **Step 6: Promote the demo user in `seeds.exs`** — after the demo user is created, set `role: :admin` (dev only) so `/admin/schools` is reachable locally.

- [ ] **Step 7: Run test + full suite + format**

Run: `mix test test/teacher_assistant_web/live/admin/schools_live_test.exs && mix test && mix format`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/live/admin/schools_live.ex lib/teacher_assistant_web/live_user_auth.ex lib/teacher_assistant_web/router.ex priv/repo/seeds.exs test/support/fixtures/teacher_fixtures.ex test/teacher_assistant_web/live/admin/schools_live_test.exs
git commit -m "feat: operator school-verification screen (/admin/schools)"
```

---

## Self-review (author checklist — completed)

**Spec coverage:** SchoolProfile + fields (T2) · enums incl. bilingual (T1) · owner on profile + atomic create (T3) · verification states + scope flag (T4) · operate-gate at marks/attendance/bulletins (T5) · self-serve creation flow (T6) · pending banner + checklist (T7) · settings profile editing (T8) · logo local storage (T9) · operator screen + global-admin gate (T10). Success criteria all map to tasks.

**Placeholder scan:** the two spots that intentionally reference an existing sibling file for *markup style only* (T6 render, T8/T9 forms) still specify exact element ids, phx bindings, data sources and handlers; the logic and tests are fully spelled. Bulletin-controller and settings HEEx follow the file's own established pattern.

**Type consistency:** `Schools.create_school/2`, `fetch_school_profile/1`, `update_school_profile/2`, `verify_school/2`, `reject_school/3`, `list_unverified_schools/0`; `Scope.school_verified?/1` + `:school_verification_status`; `Permissions.operating_allowed?/1`; `SchoolProfile` actions `:verify`/`:reject` — names are consistent across tasks.

**Known follow-ups (out of scope, by spec):** real Ash policies (Inc 3), staff email delivery (Inc 2), applying identity to the report-card header (Inc 4/5). A data backfill is unnecessary (no existing school rows in this DB lineage); if any exist, add a one-off task creating a default `:unverified` profile per school workspace before enabling the gate.
