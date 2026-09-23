# Authorization Hardening (Increment C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move write authorization from the presentation layer into enforced Ash resource policies, driven by one shared role-set definition, and plumb the acting scope through every context write so those policies actually bite.

**Architecture:** Every one of the ~32 Ash resources currently has an allow-all policy and every context write is actor-less; all nine domains are `authorize :when_requested`, so actor-less writes silently bypass authorization. C (1) defines the role→axis mapping once, consumed by both the web `Permissions.*` predicates and new `Ash.Policy.SimpleCheck` modules; (2) adds a per-resource `OwningWorkspace` resolver the checks use to load the actor's membership; (3) replaces the allow-all write policy on each resource with a real one; and (4) threads `scope` through each write context function so the call passes `actor: scope.current_user, authorize?: true`. Reads stay open at the data layer. The web-layer gates stay as the UX layer.

**Tech Stack:** Elixir ~> 1.15, Ash 3.33.4, AshPostgres 2.13.1, AshPhoenix 2.3.25, AshAuthentication 4.14.2, Phoenix LiveView 1.1, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-23-authorization-hardening-design.md` (read it alongside this plan).

## Global Constraints

- **Ash version 3.33.4.** `Ash.Policy.SimpleCheck` callback is `match?(actor, context, opts)` (arity 3). `context` is an `%Ash.Policy.Authorizer{}` struct; on a write it carries the changeset in both `:changeset` and `:subject`. Return a bare boolean or `{:ok, boolean}`. `use Ash.Policy.SimpleCheck` auto-implements everything except `match?/3` (and optional `describe/1`).
- **All nine domains are `authorize :when_requested`** — enforcement runs only when a call sets an actor. Every enforced write MUST pass `actor: scope.current_user, authorize?: true` explicitly (do not rely on `Ash.Scope.ToOpts`, which returns `:error` for `authorize?`).
- **Reads stay `authorize_if always()`** on every resource (writes-only decision). Never add a read/filter policy.
- **Never bare `:atom`** — roles/status are existing `Ash.Type.Enum`s; do not introduce new bare atoms (per repo convention).
- **No new schema, no migration.** Policies and checks are code. If `mix ash.codegen --check` ever reports drift, stop — something structural changed that this plan did not intend.
- **`mix precommit` does NOT gate on warnings.** Gate every commit on `mix test` green AND a clean `mix compile --warnings-as-errors`.
- **Scope** is `TeacherAssistant.Scope` with fields `current_user, current_workspace, current_workspace_type, current_role, current_roles, current_membership, current_academic_year, current_context, school_verification_status`. **Permissions** is `TeacherAssistant.Accounts.Permissions`. Membership roles live at `membership.roles` (array of `SchoolRole`).
- **Canonical write-policy block** (parameterised per resource by the check list; `forbid_unless SchoolVerified` present ONLY on operational resources):

  ```elixir
  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      # forbid_unless Checks.SchoolVerified          # operational resources only
      authorize_if Checks.HasSchoolRole(roles: :admin)
      # additional authorize_if lines are OR-ed
    end
  end
  ```

  Preserve the existing `bypass AshAuthentication.Checks.AshAuthenticationInteraction` blocks on `User`/`Token` verbatim; those resources are out of this sweep.
- **Canonical plumbing** (context write fn gains `scope` as its FIRST parameter):

  ```elixir
  def create_thing(%Scope{} = scope, ...args) do
    Thing
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(actor: scope.current_user, authorize?: true)
  end
  # destroy: Ash.destroy(record, actor: scope.current_user, authorize?: true)
  # bang variants keep the bang and take the same opts
  ```

  Every caller (LiveView, wizard, controller, fixture) passes `socket.assigns.current_scope` (or the test scope) as the new first argument.
- **Canonical boundary test** (every domain task adds these three for at least its representative write):

  ```elixir
  assert {:ok, _}   = Context.create_thing(authorized_scope, args)
  assert {:error, %Ash.Error.Forbidden{}} = Context.create_thing(wrong_role_scope, args)
  assert {:error, %Ash.Error.Forbidden{}} = Context.create_thing(non_member_scope, args)
  ```

## Review Focus

The spec implies these input classes; no single task's happy-path tests exercise them, so each is pinned to the owning task's negative tests, most-likely-to-bite first:

- **A non-member calls a write context function** (the allow-all hole). Expected: `Ash.Error.Forbidden`. Pinned in every domain task (Tasks 4–13) via the non-member boundary case.
- **A wrong-role member writes** (e.g. a `:teacher` creating a `ClassGroup`, or a non-head editing membership). Expected: `Forbidden`. Pinned in Tasks 4–7, 11–13.
- **A teacher writes another teacher's context marks/progression.** Expected: `Forbidden`; the assigned teacher succeeds; an admin overrides. Pinned in Tasks 8 and 9.
- **An operational write in an unverified school** (marks, attendance) is blocked even for the right role/owner, while a config write (class group) is allowed. Pinned in Tasks 9 and 10 (blocked) and Task 6 (allowed pre-verification).
- **A nil chain link** — `AttendanceEntry.teaching_context_id` nil (whole-class roll), `TeachingLogEntry.progression_entry_id` nil — must not crash the check or mis-authorize; ownership returns false and authorization falls to the role branch. Pinned in Tasks 8 and 10.
- **A plumbing miss stays a silent bypass** (not a red suite), because `:when_requested`. Every domain task's negative case calls the REAL context function (now scope-taking) as an unauthorized actor, so a write left un-plumbed fails the test.

---

## Task 1: Canonical role-sets + Permissions delegation

**Files:**
- Modify: `lib/teacher_assistant/accounts/permissions.ex`
- Test: `test/teacher_assistant/accounts/permissions_test.exs` (create if absent)

**Interfaces:**
- Produces: `Permissions.roles_for(:admin | :conduct | :fees | :head) :: [atom]`; existing predicates (`admin?/1`, `head?/1`, `bursar?/1`, `discipline_master?/1`, `conduct_manager?/1`, `fees_manager?/1`, `member?/1`, `form_master?/2`, `admin_or_form_master?/2`, `operating_allowed?/1`) keep their exact signatures.
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/accounts/permissions_test.exs
defmodule TeacherAssistant.Accounts.PermissionsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Scope

  test "roles_for/1 defines the canonical axis sets" do
    assert Permissions.roles_for(:admin) == [:head, :vice_principal]
    assert Permissions.roles_for(:conduct) == [:head, :vice_principal, :discipline_master]
    assert Permissions.roles_for(:fees) == [:head, :vice_principal, :bursar]
    assert Permissions.roles_for(:head) == [:head]
  end

  test "admin?/1 is true for head or vice_principal, false otherwise" do
    assert Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:vice_principal]})
    refute Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:teacher]})
    refute Permissions.admin?(%Scope{current_workspace_type: :personal_teacher, current_roles: [:head]})
  end

  test "conduct_manager?/1 and fees_manager?/1 use the canonical sets" do
    dm = %Scope{current_workspace_type: :school, current_roles: [:discipline_master]}
    assert Permissions.conduct_manager?(dm)
    refute Permissions.fees_manager?(dm)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs`
Expected: FAIL — `roles_for/1` undefined.

- [ ] **Step 3: Add `roles_for/1` and make predicates delegate**

In `permissions.ex`, add the canonical sets and rewrite the role predicates to use them (keep every signature; keep `form_master?/2`, `admin_or_form_master?/2`, `operating_allowed?/1` unchanged):

```elixir
def roles_for(:admin), do: [:head, :vice_principal]
def roles_for(:conduct), do: [:head, :vice_principal, :discipline_master]
def roles_for(:fees), do: [:head, :vice_principal, :bursar]
def roles_for(:head), do: [:head]

defp any_role?(roles, axis), do: Enum.any?(roles || [], &(&1 in roles_for(axis)))

def admin?(%Scope{current_workspace_type: :school, current_roles: roles}), do: any_role?(roles, :admin)
def admin?(_), do: false

def head?(%Scope{current_workspace_type: :school, current_roles: roles}), do: any_role?(roles, :head)
def head?(_), do: false

def bursar?(%Scope{current_workspace_type: :school, current_roles: roles}), do: :bursar in (roles || [])
def bursar?(_), do: false

def discipline_master?(%Scope{current_workspace_type: :school, current_roles: roles}),
  do: :discipline_master in (roles || [])
def discipline_master?(_), do: false

def conduct_manager?(%Scope{current_workspace_type: :school, current_roles: roles}), do: any_role?(roles, :conduct)
def conduct_manager?(_), do: false

def fees_manager?(%Scope{current_workspace_type: :school, current_roles: roles}), do: any_role?(roles, :fees)
def fees_manager?(_), do: false
```

Leave `member?/1`, `form_master?/2`, `admin_or_form_master?/2`, `operating_allowed?/1` exactly as they are.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs` then `mix test`
Expected: PASS; full suite still green.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/permissions.ex test/teacher_assistant/accounts/permissions_test.exs
git commit -m "feat(authz): canonical role-sets on Permissions, predicates delegate"
```

---

## Task 2: OwningWorkspace resolver

Resolves a write subject (an `Ash.Changeset`) to its owning `workspace_id`, so a check can load the actor's membership. Most resources expose `workspace_id` directly; six reach it through a parent.

**Files:**
- Create: `lib/teacher_assistant/authorization/owning_workspace.ex`
- Test: `test/teacher_assistant/authorization/owning_workspace_test.exs`

**Interfaces:**
- Produces: `OwningWorkspace.resolve(Ash.Changeset.t()) :: {:ok, workspace_id :: binary} | :error`
- Consumes: nothing (reads parents with `Ash.get(_, id, authorize?: false)`).

- [ ] **Step 1: Write the failing test**

```elixir
# test/teacher_assistant/authorization/owning_workspace_test.exs
defmodule TeacherAssistant.Authorization.OwningWorkspaceTest do
  use TeacherAssistant.DataCase, async: true
  import TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Authorization.OwningWorkspace
  alias TeacherAssistant.Academics.{ClassGroup, Assessment}

  test "resolves a direct-workspace_id resource on create" do
    %{workspace: ws, year: year} = setup_complete_school_fixture()
    cs = Ash.Changeset.for_create(ClassGroup, :create, %{workspace_id: ws.id, academic_year_id: year.id, name: "6e A", level: "6e"})
    assert {:ok, ws_id} = OwningWorkspace.resolve(cs)
    assert ws_id == ws.id
  end

  test "resolves a deep resource (Assessment) via its teaching_context on create" do
    %{workspace: ws} = ctx = teaching_context_fixture()  # returns %{workspace:, context:}
    cs = Ash.Changeset.for_create(Assessment, :create, %{teaching_context_id: ctx.context.id, title: "Devoir 1"})
    assert {:ok, ws_id} = OwningWorkspace.resolve(cs)
    assert ws_id == ws.id
  end

  test "returns :error when the workspace cannot be resolved" do
    cs = Ash.Changeset.for_create(ClassGroup, :create, %{name: "x", level: "6e"})
    assert :error = OwningWorkspace.resolve(cs)
  end
end
```

> If `teaching_context_fixture/0` does not exist, add a minimal one to `test/support/fixtures/teacher_fixtures.ex` returning `%{workspace: ws, context: ctx}` for a context with a known `teacher_user_id`; it is reused by Tasks 8/9.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/authorization/owning_workspace_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the resolver**

```elixir
defmodule TeacherAssistant.Authorization.OwningWorkspace do
  @moduledoc "Resolves a write changeset to the workspace_id that owns the record."
  alias TeacherAssistant.Academics.{Assessment, Mark, ProgressionPlan, ProgressionEntry,
    ProgressionModule, LessonPlan, LessonStep, TeachingContext, Workspace}

  # Resources whose workspace_id is a direct attribute (create casts it; update/destroy carry it on data).
  @direct ~w(SchoolProfile SchoolMembership SchoolInvitation AcademicYear ClassGroup Enrollment
             Subject TeachingContext CombinedCourse ProgressionPlan TeachingLogEntry AttendanceEntry
             Period SanctionEntry ConductMark FeeTranche Payment FeeAdjustment TimetableSlot)a

  def resolve(%Ash.Changeset{resource: Workspace} = cs), do: ok(attr(cs, :id))

  def resolve(%Ash.Changeset{resource: resource} = cs) do
    short = resource |> Module.split() |> List.last() |> String.to_atom()

    cond do
      short in @direct -> ok(attr(cs, :workspace_id))
      resource == Assessment -> via(attr(cs, :teaching_context_id), TeachingContext, & &1.workspace_id)
      resource == Mark -> mark_ws(cs)
      resource in [ProgressionEntry, ProgressionModule] ->
        via(attr(cs, :progression_plan_id), ProgressionPlan, & &1.workspace_id)
      resource == LessonPlan -> lesson_ws(attr(cs, :progression_entry_id))
      resource == LessonStep ->
        with %LessonPlan{} = lp <- get(LessonPlan, attr(cs, :lesson_plan_id)),
             do: lesson_ws(lp.progression_entry_id), else: (_ -> :error)
      true -> :error
    end
  end

  def resolve(_), do: :error

  defp mark_ws(cs) do
    with %Assessment{} = a <- get(Assessment, attr(cs, :assessment_id)),
         %TeachingContext{} = c <- get(TeachingContext, a.teaching_context_id) do
      ok(c.workspace_id)
    else _ -> :error end
  end

  defp lesson_ws(nil), do: :error
  defp lesson_ws(entry_id) do
    with %ProgressionEntry{} = e <- get(ProgressionEntry, entry_id),
         %ProgressionPlan{} = p <- get(ProgressionPlan, e.progression_plan_id) do
      ok(p.workspace_id)
    else _ -> :error end
  end

  defp via(nil, _mod, _fun), do: :error
  defp via(id, mod, fun) do
    case get(mod, id) do
      nil -> :error
      record -> ok(fun.(record))
    end
  end

  defp attr(cs, key), do: Ash.Changeset.get_attribute(cs, key)
  defp get(_mod, nil), do: nil
  defp get(mod, id), do: Ash.get(mod, id, authorize?: false) |> case(do: ({:ok, r} -> r; _ -> nil))
  defp ok(nil), do: :error
  defp ok(id), do: {:ok, id}
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/teacher_assistant/authorization/owning_workspace_test.exs` then `mix test`
Expected: PASS; suite green.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/authorization/owning_workspace.ex test/teacher_assistant/authorization/owning_workspace_test.exs test/support/fixtures/teacher_fixtures.ex
git commit -m "feat(authz): OwningWorkspace resolver (direct + deep chains)"
```

---

## Task 3: The check family + membership helpers

Six `SimpleCheck`s plus the `Accounts` helpers they call. No resource policies flip yet, so the suite stays green; the checks are unit-tested directly.

**Files:**
- Create: `lib/teacher_assistant/accounts/checks/active_member.ex`, `has_school_role.ex`, `owns_assigned_context.ex`, `school_verified.ex`, `is_operator.ex`, `is_invitation_recipient.ex`
- Modify: `lib/teacher_assistant/accounts.ex` (add `membership_roles/2`, `active_member?/2`)
- Test: `test/teacher_assistant/accounts/checks_test.exs`

**Interfaces:**
- Consumes: `OwningWorkspace.resolve/1` (Task 2); `Permissions.roles_for/1` (Task 1).
- Produces (checks, referenced from policies as `Checks.<Name>`): `ActiveMember`, `HasSchoolRole` (opt `roles: axis`), `OwnsAssignedContext`, `SchoolVerified`, `IsOperator`, `IsInvitationRecipient`.
- Produces (helpers): `Accounts.membership_roles(ws_id, user_id) :: {:ok, [atom]} | :error`; `Accounts.active_member?(ws_id, user_id) :: boolean`.

- [ ] **Step 1: Add the `Accounts` helpers with a test**

```elixir
# in test/teacher_assistant/accounts/checks_test.exs (helpers section)
test "membership_roles/2 returns the active membership roles or :error" do
  %{workspace: ws} = school = setup_complete_school_fixture()
  head = school.head
  assert {:ok, roles} = Accounts.membership_roles(ws.id, head.id)
  assert :head in roles
  outsider = user_fixture(%{email: "out@ex.cm"})
  assert :error = Accounts.membership_roles(ws.id, outsider.id)
end
```

Implement in `accounts.ex` (reusing the existing `:for_workspace_and_user` read, which already filters `active == true`):

```elixir
def membership_roles(ws_id, user_id) do
  SchoolMembership
  |> Ash.Query.for_read(:for_workspace_and_user, %{workspace_id: ws_id, user_id: user_id})
  |> Ash.read_one()
  |> case do
    {:ok, %SchoolMembership{roles: roles}} -> {:ok, roles}
    _ -> :error
  end
end

def active_member?(ws_id, user_id), do: match?({:ok, _}, membership_roles(ws_id, user_id))
```

- [ ] **Step 2: Write failing check tests**

```elixir
defmodule TeacherAssistant.Accounts.ChecksTest do
  use TeacherAssistant.DataCase, async: true
  import TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.ClassGroup

  defp ctx(changeset), do: %Ash.Policy.Authorizer{changeset: changeset, subject: changeset, resource: changeset.resource}

  test "ActiveMember: member true, outsider false, nil actor false" do
    %{workspace: ws, year: year} = school = setup_complete_school_fixture()
    cs = Ash.Changeset.for_create(ClassGroup, :create, %{workspace_id: ws.id, academic_year_id: year.id, name: "A", level: "6e"})
    assert Checks.ActiveMember.match?(school.head, ctx(cs), [])
    refute Checks.ActiveMember.match?(user_fixture(%{email: "o@ex.cm"}), ctx(cs), [])
    refute Checks.ActiveMember.match?(nil, ctx(cs), [])
  end

  test "HasSchoolRole(:admin): head true, plain teacher false" do
    %{workspace: ws, year: year} = school = setup_complete_school_fixture()
    teacher = member_with_roles(school, [:teacher])
    cs = Ash.Changeset.for_create(ClassGroup, :create, %{workspace_id: ws.id, academic_year_id: year.id, name: "A", level: "6e"})
    assert Checks.HasSchoolRole.match?(school.head, ctx(cs), roles: :admin)
    refute Checks.HasSchoolRole.match?(teacher, ctx(cs), roles: :admin)
  end
end
```

> Add `member_with_roles(school, roles)` to `teacher_fixtures.ex` (creates a user + active `SchoolMembership` with those roles in `school.workspace`, returns the `%User{}`). Reused by every domain task.

- [ ] **Step 3: Run to verify failure**

Run: `mix test test/teacher_assistant/accounts/checks_test.exs`
Expected: FAIL — check modules undefined.

- [ ] **Step 4: Implement the six checks**

```elixir
# active_member.ex
defmodule TeacherAssistant.Accounts.Checks.ActiveMember do
  use Ash.Policy.SimpleCheck
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Authorization.OwningWorkspace

  def describe(_), do: "actor is an active member of the record's school"
  def match?(nil, _ctx, _opts), do: false
  def match?(actor, %{subject: cs}, _opts) do
    case OwningWorkspace.resolve(cs) do
      {:ok, ws_id} -> Accounts.active_member?(ws_id, actor.id)
      :error -> false
    end
  end
  def match?(_, _, _), do: false
end
```

```elixir
# has_school_role.ex
defmodule TeacherAssistant.Accounts.Checks.HasSchoolRole do
  use Ash.Policy.SimpleCheck
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Authorization.OwningWorkspace

  def describe(opts), do: "actor holds a #{inspect(opts[:roles])} role in the record's school"
  def match?(nil, _ctx, _opts), do: false
  def match?(actor, %{subject: cs}, opts) do
    axis = Keyword.fetch!(opts, :roles)
    with {:ok, ws_id} <- OwningWorkspace.resolve(cs),
         {:ok, roles} <- Accounts.membership_roles(ws_id, actor.id) do
      Enum.any?(roles, &(&1 in Permissions.roles_for(axis)))
    else
      _ -> false
    end
  end
  def match?(_, _, _), do: false
end
```

```elixir
# school_verified.ex
defmodule TeacherAssistant.Accounts.Checks.SchoolVerified do
  use Ash.Policy.SimpleCheck
  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Authorization.OwningWorkspace

  def describe(_), do: "the record's school is verified"
  def match?(_actor, %{subject: cs}, _opts) do
    with {:ok, ws_id} <- OwningWorkspace.resolve(cs),
         {:ok, %SchoolProfile{verification_status: :verified}} <-
           (SchoolProfile |> Ash.Query.filter(workspace_id == ^ws_id) |> Ash.read_one(authorize?: false)) do
      true
    else
      _ -> false
    end
  end
  def match?(_, _, _), do: false
end
```

> Confirm the `SchoolProfile` read: it has `workspace_id` and `verification_status`. If a named read (e.g. `:for_workspace`) exists, use it; otherwise the inline filter above is fine with `authorize?: false`.

```elixir
# is_operator.ex
defmodule TeacherAssistant.Accounts.Checks.IsOperator do
  use Ash.Policy.SimpleCheck
  def describe(_), do: "actor is a platform operator"
  def match?(%{role: :admin}, _ctx, _opts), do: true
  def match?(_, _, _), do: false
end
```

```elixir
# owns_assigned_context.ex
defmodule TeacherAssistant.Accounts.Checks.OwnsAssignedContext do
  use Ash.Policy.SimpleCheck
  alias TeacherAssistant.Academics.{Assessment, Mark, AttendanceEntry, ProgressionPlan,
    ProgressionEntry, ProgressionModule, TeachingLogEntry, LessonPlan, TeachingContext, CombinedCourse}

  def describe(_), do: "actor is the teacher assigned to the record's teaching context"
  def match?(nil, _ctx, _opts), do: false
  def match?(actor, %{subject: cs}, _opts) do
    case owning_teacher_id(cs) do
      teacher_id when is_binary(teacher_id) -> teacher_id == actor.id
      _ -> false
    end
  end
  def match?(_, _, _), do: false

  defp a(cs, k), do: Ash.Changeset.get_attribute(cs, k)
  defp get(_m, nil), do: nil
  defp get(m, id), do: Ash.get(m, id, authorize?: false) |> case(do: ({:ok, r} -> r; _ -> nil))

  defp owning_teacher_id(%{resource: Assessment} = cs), do: ctx_teacher(a(cs, :teaching_context_id))
  defp owning_teacher_id(%{resource: AttendanceEntry} = cs), do: ctx_teacher(a(cs, :teaching_context_id))
  defp owning_teacher_id(%{resource: Mark} = cs) do
    with %Assessment{} = as <- get(Assessment, a(cs, :assessment_id)), do: ctx_teacher(as.teaching_context_id), else: (_ -> nil)
  end
  defp owning_teacher_id(%{resource: ProgressionPlan} = cs), do: plan_teacher(a(cs, :teaching_context_id), a(cs, :combined_course_id))
  defp owning_teacher_id(%{resource: r} = cs) when r in [ProgressionEntry, ProgressionModule], do: plan_by_id(a(cs, :progression_plan_id))
  defp owning_teacher_id(%{resource: TeachingLogEntry} = cs), do: entry_teacher(a(cs, :progression_entry_id))
  defp owning_teacher_id(%{resource: LessonPlan} = cs), do: entry_teacher(a(cs, :progression_entry_id))
  defp owning_teacher_id(_), do: nil

  defp ctx_teacher(nil), do: nil
  defp ctx_teacher(ctx_id), do: get(TeachingContext, ctx_id) |> then(&(&1 && &1.teacher_user_id))
  defp course_teacher(nil), do: nil
  defp course_teacher(cc_id), do: get(CombinedCourse, cc_id) |> then(&(&1 && &1.teacher_user_id))
  defp plan_teacher(ctx_id, cc_id), do: ctx_teacher(ctx_id) || course_teacher(cc_id)
  defp plan_by_id(nil), do: nil
  defp plan_by_id(plan_id), do: get(ProgressionPlan, plan_id) |> then(&(&1 && plan_teacher(&1.teaching_context_id, &1.combined_course_id)))
  defp entry_teacher(nil), do: nil
  defp entry_teacher(entry_id), do: get(ProgressionEntry, entry_id) |> then(&(&1 && plan_by_id(&1.progression_plan_id)))
end
```

```elixir
# is_invitation_recipient.ex
defmodule TeacherAssistant.Accounts.Checks.IsInvitationRecipient do
  use Ash.Policy.SimpleCheck
  def describe(_), do: "actor's email matches the invitation being accepted"
  def match?(nil, _ctx, _opts), do: false
  def match?(actor, %{subject: cs}, _opts) do
    inv_email = Ash.Changeset.get_attribute(cs, :email) || (cs.data && cs.data.email)
    inv_email && to_string(inv_email) == to_string(actor.email)
  end
  def match?(_, _, _), do: false
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/teacher_assistant/accounts/checks_test.exs` then `mix test`
Expected: PASS; suite green (no policies flipped yet).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/checks/ lib/teacher_assistant/accounts.ex test/teacher_assistant/accounts/checks_test.exs test/support/fixtures/teacher_fixtures.ex
git commit -m "feat(authz): SimpleCheck family + membership_roles/active_member helpers"
```

---

## Domain-task shape (Tasks 4–13)

Each domain task is one deliverable and follows the same six steps. **Alias** `alias TeacherAssistant.Accounts.Checks` at the top of each resource that gains a policy.

1. **Write the boundary tests** for this domain's writes — authorized scope succeeds; wrong-role and non-member scopes get `%Ash.Error.Forbidden{}`; plus the domain's specific cases named in its row of the Review Focus. Tests call the REAL context functions (with their new `scope` first arg).
2. **Run → fail** (context arity changed / not yet enforcing).
3. **Apply** the per-resource policy blocks (from the table) AND thread `scope` through this domain's context write functions AND update every listed call site.
4. **Run this domain's tests → pass.**
5. **Run `mix test` + `mix compile --warnings-as-errors`** → green (fix any fixture/call-site fallout in THIS domain; record each fixed file).
6. **Commit.**

Policy blocks use the canonical shape from Global Constraints; the table gives each resource's `authorize_if`/`forbid_unless` lines. "Plumb" means: add `%Scope{} = scope` as the write function's first parameter and pass `actor: scope.current_user, authorize?: true` to its `Ash.create/update/destroy`.

---

## Task 4: Accounts — membership, invitation, profile, operator verify

**Resources & policies:**

| Resource | create/update/destroy policy |
|---|---|
| `SchoolMembership` | `authorize_if Checks.HasSchoolRole(roles: :head)` |
| `SchoolInvitation` (create, `:update`, `:revoke`) | `authorize_if Checks.HasSchoolRole(roles: :head)` |
| `SchoolInvitation` (accept path → membership create in `accept_invitation`) | see note ‡ |
| `SchoolProfile` (`:create`, `:update`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |
| `SchoolProfile` (`:verify`, `:reject`) | `authorize_if Checks.IsOperator` |

‡ Accept path: `accept_invitation/2` creates a `SchoolMembership` for a user who is **not yet a member**, so a `:head` policy would reject it. Keep that specific membership-create call actor-scoped to the accepting user but authorized by the invitation, not the membership policy: pass `authorize?: false` on the `SchoolMembership` create **inside `accept_invitation`** (the invitation's own recipient/expiry checks in `check_email`/`check_acceptable` are the gate), and add a comment. The `SchoolInvitation` `:update` to `:accepted` in that flow likewise passes `authorize?: false`. Do NOT weaken the head policy for ordinary invite creation.

**Context plumbing (`lib/teacher_assistant/accounts.ex`):**

| Function | Change |
|---|---|
| `invite_member/3` → `invite_member/4` | add `%Scope{} = scope` first; the `SchoolInvitation` create passes `actor: scope.current_user, authorize?: true` |
| `update_member_roles/2` → `/3` | add scope first; `Ash.update(actor: scope.current_user, authorize?: true)` |
| `update_member_status/2` → `/3` | add scope first; **remove `authorize?: false`**, pass `actor: scope.current_user, authorize?: true` |
| `deactivate_member/1` → `/2` | add scope first; pass actor+authorize? |
| `accept_invitation/2` | unchanged arity; internal membership-create + invitation-update use `authorize?: false` per ‡ |

**Profile writes** live in `SchoolProfile` actions invoked from `settings_live` and `school_logo` upload — find their context entry points (likely `Accounts` or `Organization`) and plumb the same way; the operator `:verify`/`:reject` are invoked from `Admin.SchoolsLive` — plumb its scope (operator).

**Call sites to update:** `lib/teacher_assistant_web/live/school/members_live.ex` (invite / role change / status change / deactivate — pass `socket.assigns.current_scope`); `settings_live.ex` (profile writes); `Admin.SchoolsLive` (verify/reject); the accept controller path stays as-is (uses `accept_invitation/2`). Update any fixture that calls `invite_member`/`update_member_*`/`deactivate_member` to pass a scope.

**Domain-specific tests:** head invites/edits/deactivates → ok; a `:vice_principal` (admin but not head) → `Forbidden` for membership writes; non-member → `Forbidden`; operator `:verify` succeeds while a head's `:verify` → `Forbidden`; accept-invitation still creates the membership for the invited user (unchanged behavior).

Steps 1–6 per the domain-task shape. Commit: `feat(authz): enforce membership/invitation/profile writes (head/admin/operator)`.

---

## Task 5: Organization — workspace bootstrap & academic year

**Resources & policies:**

| Resource | policy |
|---|---|
| `Workspace` (`:create_school`) | `authorize_if actor_present()` (Ash built-in — signed-in user creates their own school) |
| `Workspace` (default `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |
| `AcademicYear` (`:create_for_workspace`, `:update`, `:activate`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |

> No `SchoolVerified` here — school creation and year setup precede verification.

**Context plumbing (`lib/teacher_assistant/organization.ex`):** `create_school/…` (pass the creator's scope; `authorize?: true` with `actor_present` passes), `create_academic_year/…`, and the year `:activate` path — add `%Scope{} = scope` first, pass actor+authorize?. `ensure_personal_workspace!` is personal (non-school) — leave actor-less/allow-all (it has no school policy).

**Call sites:** `create_school_live.ex` (create), `setup_wizard_live.ex` (year create + activate), `settings_live.ex` (year create). Fixtures: `setup_complete_school_fixture/1`, `complete_school_setup!/2` create years — pass the head's scope.

**Tests:** any signed-in user creates a school → ok; a plain member creating an `AcademicYear` in someone else's school → `Forbidden`; the school's admin → ok; unverified school can still create the year (no verification gate).

Commit: `feat(authz): enforce workspace/academic-year writes; create_school = actor_present`.

---

## Task 6: Enrollment — class groups & student enrollment

**Resources & policies** (config; no verification gate):

| Resource | policy |
|---|---|
| `ClassGroup` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |
| `Enrollment` (`:create`, `:update`, `:destroy`, `:enroll_new`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |

**Context plumbing (`lib/teacher_assistant/enrollment.ex`):** `create_class_group/3`→`/4`, `update_class_group`, `delete_class_group`, `enroll_existing`, `enroll_new`, `withdraw`, `update_enrollment` — add scope first, pass actor+authorize? (destroys via `Ash.destroy(record, actor: scope.current_user, authorize?: true)`).

**Call sites:** `classes_live.ex` (add/delete class — the two `admin?`-guarded handlers), `setup_wizard_live.ex` (wizard add/delete class), `enroll_import_live.ex`, `class_live.ex` (enrollment writes). Fixtures: `complete_school_setup!` / `setup_complete_school_fixture` seed classes via `Enrollment.create_class_group` (through `Seeding`) — thread scope; if `Seeding.seed_starter_classes/2` calls `create_class_group`, give it a scope too (or seed with `authorize?: false` as trusted system seeding — prefer passing the head scope for realism).

**Tests:** admin adds/deletes a class → ok; a `:teacher` → `Forbidden`; non-member → `Forbidden`; allowed pre-verification (unverified school, admin creates class → ok — pins the "config writes allowed before verification" Review-Focus line).

Commit: `feat(authz): enforce class-group/enrollment writes (admin)`.

---

## Task 7: Curriculum config — subjects, teaching contexts, combined courses

**Resources & policies** (config; no verification gate):

| Resource | policy |
|---|---|
| `Subject` (`:create`, `:update`, `:deactivate`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |
| `TeachingContext` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |
| `CombinedCourse` (`:create`, `:update`, `:destroy`, `:combine`, `:split`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |

**Context plumbing (`lib/teacher_assistant/curriculum.ex`):** `create_subject`, `update_subject`, `deactivate_subject`, `assign_teacher` (TeachingContext create), context update/destroy, `combine`/`split` combined-course fns — scope first, actor+authorize?.

**Call sites:** `settings_live.ex` (Matières add/edit/deactivate/delete), the assignment form LiveView (`assign_teacher`), and any combined-course UI. Fixtures creating subjects/contexts (e.g. `teaching_context_fixture`, catalog seeding inside `create_school`) — thread scope, or seed with `authorize?: false` where it is inside the `create_school` transaction (system seeding; note it).

**Tests:** admin manages subjects/contexts → ok; teacher → `Forbidden`; non-member → `Forbidden`.

Commit: `feat(authz): enforce subject/teaching-context/combined-course writes (admin)`.

---

## Task 8: Curriculum planning — progression & lesson plans (teacher-owned)

**Resources & policies** (ownership OR admin; **no** verification gate):

| Resource | policy |
|---|---|
| `ProgressionPlan` (`:create`, `:for_course`, `:update`, `:destroy`, `:import`, `:apply_layout`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` **and** `authorize_if Checks.OwnsAssignedContext` |
| `ProgressionEntry`, `ProgressionModule` (`:create`/`:update`/`:destroy`, `:create_default_bucket`) | same two `authorize_if` lines |
| `TeachingLogEntry` (`:create`, `:update`, `:destroy`) | same two `authorize_if` lines |
| `LessonPlan`, `LessonStep` (`:create`, `:update`, `:destroy`) | same two `authorize_if` lines |

> Two `authorize_if` lines in ONE policy = OR (admin OR owner). Nil ownership chain ⇒ `OwnsAssignedContext` returns false ⇒ only admin may write; pin with a nil-`progression_entry_id` `TeachingLogEntry` test asserting a plain teacher is `Forbidden` and an admin succeeds.

**Context plumbing (`lib/teacher_assistant/curriculum.ex`):** `log_teaching` (TeachingLogEntry), progression plan create/update/import/apply_layout, entry/module writes, lesson plan/step writes — scope first, actor+authorize?.

**Call sites:** the progression/fiche/coverage LiveViews and the teaching-log write path (`teacher/…` LiveViews). Fixtures building progression data — thread scope (owner = the assigned teacher).

**Tests:** the assigned teacher edits their plan/log → ok; a different teacher → `Forbidden`; admin override → ok; non-member → `Forbidden`; nil-entry `TeachingLogEntry` → teacher `Forbidden`, admin ok.

Commit: `feat(authz): enforce progression/lesson/teaching-log writes (owner or admin)`.

---

## Task 9: Assessment — assessments & marks (verified + owner/admin)

**Resources & policies** (operational — verification-gated):

| Resource | policy |
|---|---|
| `Assessment` (`:create`, `:update`, `:destroy`, `:create_combined`) | `forbid_unless Checks.SchoolVerified` · `authorize_if Checks.HasSchoolRole(roles: :admin)` · `authorize_if Checks.OwnsAssignedContext` |
| `Mark` (`:create`, `:update`, `:destroy`, `:upsert_all`) | same three lines |

**Context plumbing (`lib/teacher_assistant/assessment.ex`):** `create_assessment`, assessment update/destroy, `upsert_marks` (Mark `:upsert_all`) — scope first, actor+authorize?.

**Call sites:** `teacher/marks_live.ex` (record marks), `results_live.ex` if it writes. Fixtures creating assessments/marks — thread scope; ensure the fixture school is **verified** where the test expects a write to succeed.

**Tests:** the assigned teacher records marks in a verified school → ok; another teacher → `Forbidden`; admin → ok; **unverified** school, assigned teacher records marks → `Forbidden` (pins the operate-gate Review-Focus line); non-member → `Forbidden`.

Commit: `feat(authz): enforce assessment/mark writes (verified + owner/admin)`.

---

## Task 10: Attendance — attendance entries (verified + conduct/owner)

**Resources & policies** (operational — verification-gated):

| Resource | policy |
|---|---|
| `AttendanceEntry` (`:create`, `:update`, `:destroy`, `:record`, `:period_roll`, `:combined_period_roll`, `:record_combined_period`) | `forbid_unless Checks.SchoolVerified` · `authorize_if Checks.HasSchoolRole(roles: :conduct)` · `authorize_if Checks.OwnsAssignedContext` |
| `Period` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` — config, no verification gate |

> `AttendanceEntry.teaching_context_id` is nullable (whole-class rolls). `OwnsAssignedContext` returns false when it is nil, so a nil-context entry is writable only by `:conduct`. Pin with a nil-context test.

**Context plumbing (`lib/teacher_assistant/attendance.ex`):** `record_period`, `build_default_periods` (Period create — admin), `justify_day`/`unjustify_day`, the roll actions — scope first, actor+authorize?.

**Call sites:** `attendance_live.ex`, `register_live.ex`, `periods_live.ex` (period writes). Fixtures — verified school + scope; period fixtures use an admin scope.

**Tests:** owner (assigned teacher) records attendance in a verified school → ok; conduct manager → ok; unrelated teacher with a non-nil context → `Forbidden`; nil-context entry: teacher `Forbidden`, conduct ok; unverified school blocks even the owner → `Forbidden`; non-member → `Forbidden`; `Period` write by admin → ok, by teacher → `Forbidden`.

Commit: `feat(authz): enforce attendance/period writes (verified + conduct/owner; period admin)`.

---

## Task 11: Discipline — sanctions & conduct marks (conduct axis)

**Resources & policies** (mirroring today — NOT verification-gated):

| Resource | policy |
|---|---|
| `SanctionEntry` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :conduct)` |
| `ConductMark` (`:create`, `:set`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :conduct)` |

**Context plumbing (`lib/teacher_assistant/discipline.ex`):** `add_sanction`, `set_conduct_mark`, `clear_conduct_mark`, sanction update — scope first, actor+authorize?. (The `issued_by_user_id`/`recorded_by_user_id` plain args stay; they are audit fields, not the actor.)

**Call sites:** `discipline_live.ex`, `register_live.ex` (conduct writes). Fixtures — conduct-capable scope.

**Tests:** discipline master (or admin) records a sanction → ok; a plain teacher → `Forbidden`; non-member → `Forbidden`.

Commit: `feat(authz): enforce sanction/conduct-mark writes (conduct)`.

---

## Task 12: Fees — payments, tranches, adjustments (fees axis)

**Resources & policies** (mirroring today — NOT verification-gated):

| Resource | policy |
|---|---|
| `FeeTranche` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :fees)` |
| `Payment` (`:create`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :fees)` |
| `FeeAdjustment` (`:create`, `:set`, `:update`, `:destroy`) | `authorize_if Checks.HasSchoolRole(roles: :fees)` |

**Context plumbing (`lib/teacher_assistant/fees.ex`):** `add_tranche`, `record_payment`, `set_adjustment`, `clear_adjustment`, updates — scope first, actor+authorize?.

**Call sites:** `fees_live.ex` (all fee/payment write handlers). Fixtures — bursar/admin scope.

**Tests:** bursar (or admin) records a payment / sets a tranche → ok; a plain teacher → `Forbidden`; non-member → `Forbidden`.

Commit: `feat(authz): enforce fee/payment/adjustment writes (fees)`.

---

## Task 13: Timetabling — timetable slots (admin)

**Resources & policies** (config; no verification gate):

| Resource | policy |
|---|---|
| `TimetableSlot` (`:create`, `:place`, `:update`, `:destroy`, `:place_combined`, `:clear_combined`) | `authorize_if Checks.HasSchoolRole(roles: :admin)` |

> `Period` was policed in Task 10 — do not double-add.

**Context plumbing (`lib/teacher_assistant/timetabling.ex`):** `place_slot`, `clear_slot`, combined place/clear, updates — scope first, actor+authorize?.

**Call sites:** `timetable_live.ex` (slot writes). Fixtures — admin scope.

**Tests:** admin places/clears a slot → ok; teacher → `Forbidden`; non-member → `Forbidden`.

Commit: `feat(authz): enforce timetable-slot writes (admin)`.

---

## Final: whole-branch review

After Task 13, run the whole-branch review (subagent-driven-development handles this). Focus the reviewer on: (1) any context write still actor-less (a silent bypass), grep `Ash.create\|Ash.update\|Ash.destroy` in `lib/teacher_assistant/*.ex` for calls lacking `authorize?: true`; (2) reads accidentally policed; (3) the two `authorize?: false` sites in `accept_invitation` correctly justified and no others introduced; (4) `mix test` green and `mix compile --warnings-as-errors` clean.

## Self-review notes (author)

- **Spec coverage:** foundation (Tasks 1–3) = spec §1; matrix tiers map to Tasks 4–13 (config→4/5/6/7/11/12/13; verification-gated operational→9/10; teacher-owned→8; bootstrap/operator→4/5). Consolidation (web unchanged, `roles_for`) = Task 1. `authorize?: false` removal = Task 4. Plumbing = every domain task.
- **Type consistency:** `Checks.<Name>` referenced in every policy table matches the modules created in Task 3; `HasSchoolRole(roles: :admin|:conduct|:fees|:head)` axes match `Permissions.roles_for/1`; `membership_roles/2`/`active_member?/2` signatures consistent across Task 3 and the checks.
- **Review Focus:** all six lines pinned to owning tasks (4–13, esp. 6/8/9/10) as negative/edge tests.
- **Deferred to a C2 (not this plan):** none — full breadth chosen. `LessonPlan`/`LessonStep` folded into Task 8.
