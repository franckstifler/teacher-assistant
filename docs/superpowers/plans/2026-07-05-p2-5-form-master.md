# P2.5 Form Master (Professeur Principal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each class an optional form master (professeur principal) who can view results/bulletins/print and manage the roster for their own class, discover their classes from the dashboard, and be named on the printed bulletin.

**Architecture:** Add a nullable `form_master_user_id` FK on `ClassGroup` as the single source of truth for form-master access. Two new `Permissions` helpers (`form_master?/2`, `admin_or_form_master?/2`) gate the class-detail surfaces (detail page, results, bulletin, print) per-resolved-class, keeping the assignments/coefficient controls admin-only. A dashboard "Mes classes" section and a bulletin visa-line name complete the feature.

**Tech Stack:** Elixir, Ash 3 + AshPostgres, Phoenix LiveView, gettext (FR source + EN translations).

## Global Constraints

- Enums must be `Ash.Type.Enum` modules — never bare `:atom` attributes. (No new enum here; the `:form_master` role already exists in `TeacherAssistant.Accounts.SchoolRole`.)
- Ash resources use `use Ash.Resource, otp_app: :teacher_assistant, domain:, data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`.
- Context functions call Ash with `authorize?: false` and return tagged tuples; never leak raw Ash errors to callers.
- Access derives from `ClassGroup.form_master_user_id`, NOT from the `:form_master` role in the membership list.
- Double-gating: every mutating/print surface gates in the UI (`:if=`) AND re-checks server-side per handler; targets resolved from socket/conn-loaded collections, never raw client ids; class resolved via `Academics.fetch_owned_class_group/2`.
- Migrations are additive (`mix ash.codegen <name>` then `mix ecto.migrate`); no backfill.
- Every new gettext msgid needs a non-empty msgstr in BOTH `fr` and `en`.
- Final gate: `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, full test) green.
- Display a user by their `email` (matching the existing assignments-panel convention `tc.teacher.email`).

---

### Task 1: `form_master_user_id` on ClassGroup + migration

**Files:**
- Modify: `lib/teacher_assistant/academics/class_group.ex`
- Test: `test/teacher_assistant/academics/class_group_form_master_test.exs` (create)
- Generated: `priv/repo/migrations/*_p2_5_form_master.exs`, `priv/resource_snapshots/repo/class_groups/*.json`

**Interfaces:**
- Produces: `ClassGroup.form_master_user_id` (uuid, nullable); `belongs_to :form_master` relationship; `:form_master_user_id` accepted by the `:update` action.

- [ ] **Step 1: Write the failing test**

Create `test/teacher_assistant/academics/class_group_form_master_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.ClassGroupFormMasterTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Accounts.Schools

  setup do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, %{name: "Lycée FM"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    %{user: user, cg: cg}
  end

  test "form_master_user_id can be set and cleared", %{user: user, cg: cg} do
    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: user.id})
      |> Ash.update(authorize?: false)

    assert cg.form_master_user_id == user.id

    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: nil})
      |> Ash.update(authorize?: false)

    assert cg.form_master_user_id == nil
  end

  test "form_master relationship loads the user", %{user: user, cg: cg} do
    {:ok, cg} =
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: user.id})
      |> Ash.update(authorize?: false)

    cg = Ash.load!(cg, :form_master, authorize?: false)
    assert cg.form_master.id == user.id
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/class_group_form_master_test.exs`
Expected: FAIL — `form_master_user_id` is not an accepted attribute / relationship undefined.

- [ ] **Step 3: Add the attribute, relationship, and accept entry**

In `lib/teacher_assistant/academics/class_group.ex`:

In the `actions` block, add `:form_master_user_id` to the `update` accept list:

```elixir
      update: [:label, :level, :serie, :subsystem, :form_master_user_id]
```

In `attributes`, after the `subsystem` attribute, add:

```elixir
    attribute :form_master_user_id, :uuid, allow_nil?: true, public?: true
```

In `relationships`, after the `academic_year` belongs_to, add:

```elixir
    belongs_to :form_master, TeacherAssistant.Accounts.User do
      source_attribute :form_master_user_id
      define_attribute? false
      allow_nil? true
      public? true
    end
```

- [ ] **Step 4: Generate the migration and migrate**

Run:
```bash
mix ash.codegen p2_5_form_master
mix ecto.migrate
```
Expected: a new migration adding a nullable `form_master_user_id` column (no NOT NULL, no default). Open the generated migration and confirm it only adds the column (and optionally a FK reference) — additive, no data changes.

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant/academics/class_group_form_master_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/class_group.ex test/teacher_assistant/academics/class_group_form_master_test.exs priv/repo/migrations priv/resource_snapshots
git commit -m "feat(school): form_master_user_id on class group (P2.5)"
```

---

### Task 2: Permissions helpers + context functions

**Files:**
- Modify: `lib/teacher_assistant/accounts/permissions.ex`
- Modify: `lib/teacher_assistant/academics.ex`
- Test: `test/teacher_assistant/accounts/permissions_test.exs` (create if absent, else extend)
- Test: `test/teacher_assistant/academics/form_master_context_test.exs` (create)

**Interfaces:**
- Consumes: `ClassGroup.form_master_user_id` (Task 1).
- Produces:
  - `Permissions.form_master?(scope, %ClassGroup{})` → boolean
  - `Permissions.admin_or_form_master?(scope, %ClassGroup{})` → boolean
  - `Academics.set_form_master(%ClassGroup{}, user_id_or_nil)` → `{:ok, %ClassGroup{}} | {:error, term}`
  - `Academics.form_master(%ClassGroup{})` → `%User{} | nil`
  - `Academics.list_form_master_classes(%Workspace{}, %{id: uid}, %AcademicYear{})` → `[%ClassGroup{}]`

- [ ] **Step 1: Write the failing permissions test**

Create/extend `test/teacher_assistant/accounts/permissions_test.exs`:

```elixir
defmodule TeacherAssistant.Accounts.PermissionsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Scope

  defp scope(uid, roles) do
    %Scope{
      current_user: %{id: uid},
      current_workspace_type: :school,
      current_roles: roles
    }
  end

  test "form_master? is true only for the class's form master" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    assert Permissions.form_master?(scope("u1", [:teacher]), cg)
    refute Permissions.form_master?(scope("u2", [:teacher]), cg)
  end

  test "form_master? is false when class has no form master" do
    refute Permissions.form_master?(scope("u1", [:teacher]), %ClassGroup{form_master_user_id: nil})
  end

  test "form_master? is false outside a school scope" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    refute Permissions.form_master?(%Scope{current_workspace_type: :personal}, cg)
  end

  test "admin_or_form_master? true for admin regardless of form master" do
    cg = %ClassGroup{form_master_user_id: "u2"}
    assert Permissions.admin_or_form_master?(scope("u1", [:head]), cg)
  end

  test "admin_or_form_master? true for the form master who is not admin" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    assert Permissions.admin_or_form_master?(scope("u1", [:teacher]), cg)
  end

  test "admin_or_form_master? false for an unrelated teacher" do
    cg = %ClassGroup{form_master_user_id: "u2"}
    refute Permissions.admin_or_form_master?(scope("u1", [:teacher]), cg)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs`
Expected: FAIL — `form_master?/2` undefined.

- [ ] **Step 3: Add the permission helpers**

In `lib/teacher_assistant/accounts/permissions.ex`, add an alias and the two functions (place before the final `def admin?(_)`):

```elixir
  alias TeacherAssistant.Academics.ClassGroup
```

```elixir
  def form_master?(
        %Scope{current_workspace_type: :school, current_user: %{id: uid}},
        %ClassGroup{form_master_user_id: fm_id}
      ),
      do: not is_nil(fm_id) and fm_id == uid

  def form_master?(_, _), do: false

  def admin_or_form_master?(scope, %ClassGroup{} = cg),
    do: admin?(scope) or form_master?(scope, cg)
```

- [ ] **Step 4: Write the failing context test**

Create `test/teacher_assistant/academics/form_master_context_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.FormMasterContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Schools

  setup do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, %{name: "Lycée FMC"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    %{user: user, school: school, year: year, cg: cg, cg2: cg2}
  end

  test "set_form_master sets, resolves, and lists", ctx do
    %{user: user, school: school, year: year, cg: cg} = ctx
    {:ok, cg} = Academics.set_form_master(cg, user.id)
    assert cg.form_master_user_id == user.id
    assert Academics.form_master(cg).id == user.id

    classes = Academics.list_form_master_classes(school, user, year)
    assert Enum.map(classes, & &1.id) == [cg.id]
  end

  test "set_form_master with nil clears it", %{user: user, cg: cg} do
    {:ok, cg} = Academics.set_form_master(cg, user.id)
    {:ok, cg} = Academics.set_form_master(cg, nil)
    assert cg.form_master_user_id == nil
    assert Academics.form_master(cg) == nil
  end

  test "list_form_master_classes excludes classes of other form masters", ctx do
    %{user: user, school: school, year: year, cg: cg, cg2: cg2} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, _} = Academics.set_form_master(cg, user.id)
    {:ok, _} = Academics.set_form_master(cg2, other.id)
    assert Enum.map(Academics.list_form_master_classes(school, user, year), & &1.id) == [cg.id]
  end
end
```

- [ ] **Step 5: Run to verify it fails**

Run: `mix test test/teacher_assistant/academics/form_master_context_test.exs`
Expected: FAIL — `set_form_master/2` undefined.

- [ ] **Step 6: Add the context functions**

In `lib/teacher_assistant/academics.ex`, add (near the other `ClassGroup` helpers around `list_class_groups`/`fetch_owned_class_group`). Ensure `alias TeacherAssistant.Accounts.User` is present at the top (add if missing):

```elixir
  def set_form_master(%ClassGroup{} = cg, user_id) do
    cg
    |> Ash.Changeset.for_update(:update, %{form_master_user_id: user_id})
    |> Ash.update(authorize?: false)
  end

  def form_master(%ClassGroup{form_master_user_id: nil}), do: nil

  def form_master(%ClassGroup{form_master_user_id: uid}) do
    case Ash.get(TeacherAssistant.Accounts.User, uid, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  def list_form_master_classes(%Workspace{id: ws_id}, %{id: uid}, %AcademicYear{id: year_id}) do
    ClassGroup
    |> Ash.Query.filter(
      workspace_id == ^ws_id and academic_year_id == ^year_id and form_master_user_id == ^uid
    )
    |> Ash.Query.sort(label: :asc)
    |> Ash.read!(authorize?: false)
  end
```

- [ ] **Step 7: Run both test files to verify they pass**

Run: `mix test test/teacher_assistant/accounts/permissions_test.exs test/teacher_assistant/academics/form_master_context_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/accounts/permissions.ex lib/teacher_assistant/academics.ex test/teacher_assistant/accounts/permissions_test.exs test/teacher_assistant/academics/form_master_context_test.exs
git commit -m "feat(school): form-master permission helpers + context fns (P2.5)"
```

---

### Task 3: Assign/clear form master on the class page (admin)

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex`
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs` (extend — add a `describe "form master"` block)

**Interfaces:**
- Consumes: `Academics.set_form_master/2`, `Permissions.admin?/1`, socket-loaded `@members`, `@cg`.
- Produces: `set_form_master` LiveView event; `@cg.form_master_user_id` reflected in a `#form-master-form` select.

- [ ] **Step 1: Write the failing tests**

Add to `test/teacher_assistant_web/live/school/class_live_test.exs` inside the module (new describe block):

```elixir
  describe "form master" do
    test "admin assigns then clears the form master", %{conn: conn, cg: cg, school: school, user: head} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> element("#form-master-form")
      |> render_change(%{"user_id" => head.id})

      assert TeacherAssistant.Academics.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == head.id

      view |> element("#form-master-form") |> render_change(%{"user_id" => ""})

      assert TeacherAssistant.Academics.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == nil
    end

    test "a non-admin cannot set the form master (forged event)", ctx do
      %{school: school, cg: cg, user: head} = ctx
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

      {:ok, _} = Schools.accept_invitation(inv.token, other)
      {:ok, _} = TeacherAssistant.Academics.set_form_master(cg, other.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, other.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "set_form_master", %{"user_id" => head.id})

      assert TeacherAssistant.Academics.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == other.id
    end
  end
```

Note: `Schools` and `Ash` are already aliased/available in the test module. The `cg_ws/1` helper loads the workspace for the scoped fetch.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs -k "form master"` (or run the file)
Expected: FAIL — no `#form-master-form` element / `set_form_master` event.

- [ ] **Step 3: Add the select control to the template**

In `lib/teacher_assistant_web/live/school/class_live.ex`, add — inside the assignments `ta-leaf` block, directly under `<h2>...Enseignements...</h2>`, and gated on `@admin?`:

```elixir
          <form :if={@admin?} id="form-master-form" phx-change="set_form_master" class="text-sm">
            <label class="ta-eyebrow block mb-1">{gettext("Professeur principal")}</label>
            <select name="user_id" class="select select-bordered select-sm w-full sm:w-80">
              <option value="">{gettext("Aucun")}</option>
              <option
                :for={m <- @members}
                value={m.user_id}
                selected={m.user_id == @cg.form_master_user_id}
              >
                {m.user.email}
              </option>
            </select>
          </form>
```

- [ ] **Step 4: Add the handler and reload cg**

In the same module, add the handler (near the other `handle_event`s):

```elixir
  def handle_event("set_form_master", %{"user_id" => uid}, socket) do
    with true <- socket.assigns.admin? do
      target = if uid == "", do: :clear, else: Enum.find(socket.assigns.members, &(&1.user_id == uid))

      case target do
        :clear ->
          {:ok, cg} = Academics.set_form_master(socket.assigns.cg, nil)
          {:noreply, socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master cleared."))}

        %{user_id: user_id} ->
          {:ok, cg} = Academics.set_form_master(socket.assigns.cg, user_id)
          {:noreply, socket |> assign(cg: cg) |> put_flash(:info, gettext("Form master assigned."))}

        _ ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end
```

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS (existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/class_live.ex test/teacher_assistant_web/live/school/class_live_test.exs
git commit -m "feat(school): assign/clear form master on class page (P2.5)"
```

---

### Task 4: Widen class-detail access to admin-or-form-master (roster only)

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex`
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Permissions.admin_or_form_master?/2` (Task 2).
- Produces: `@manage?` assign (true iff admin or form master of this class); roster UI + handlers gate on `@manage?`; assignments/coefficient/form-master controls stay on `@admin?`.

- [ ] **Step 1: Write the failing tests**

Add to `test/teacher_assistant_web/live/school/class_live_test.exs`:

```elixir
  describe "form master access" do
    setup ctx do
      %{school: school, cg: cg, user: head} = ctx
      fm = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

      {:ok, _} = Schools.accept_invitation(inv.token, fm)
      {:ok, _} = TeacherAssistant.Academics.set_form_master(cg, fm.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, fm.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{fm_conn: conn, fm: fm}
    end

    test "form master reaches the class and can enroll", %{fm_conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#enroll-form")

      view
      |> form("#enroll-form", %{"student" => %{"full_name" => "Zoe", "sex" => "f"}})
      |> render_submit()

      assert Enum.any?(Academics.list_roster(cg), &(&1.student.full_name == "Zoe"))
    end

    test "form master sees no assignments/form-master controls", %{fm_conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      refute has_element?(view, "#assign-form")
      refute has_element?(view, "#form-master-form")
    end

    test "form master cannot assign a teacher (forged event)", %{fm_conn: conn, cg: cg, fm: fm} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "assign", %{"assignment" => %{"user_id" => fm.id, "subject" => "X"}})
      assert TeacherAssistant.Academics.Assignments.list_for_class(cg) == []
    end

    test "a form master of another class is redirected", ctx do
      %{school: school, cg2: cg2, fm_conn: conn} = ctx
      # fm is form master of cg, not cg2
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg2.id}")
    end
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: FAIL — form master currently cannot mount (mount gate not yet widened); redirect assertions and `#enroll-form` visibility fail.

- [ ] **Step 3: Widen the mount gate and add `@manage?`**

In `lib/teacher_assistant_web/live/school/class_live.ex`, replace the `mount/3` `with`:

```elixir
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      {:ok,
       socket
       |> assign(
         cg: cg,
         admin?: Permissions.admin?(scope),
         manage?: true,
         search_results: [],
         q: ""
       )
       |> load_roster()}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end
```

(`manage?: true` is safe: mount only completes when the viewer is admin or this class's form master.)

- [ ] **Step 4: Switch roster UI + handlers from `@admin?` to `@manage?`**

In the template, change the roster-only gates from `:if={@admin?}` to `:if={@manage?}` at these locations ONLY (leave assignments panel, coefficient, and form-master controls on `@admin?`):
- the results/import action bar `<div :if={@admin?} class="flex justify-end gap-2">` → `:if={@manage?}` (form master should reach results & import for their class)
- the roster table actions `<th :if={@admin?}>` and `<td :if={@admin?}>` (transfer/withdraw cell)
- the "Inscrire un nouvel élève" / search block `<div :if={@admin?} class="ta-leaf space-y-3">`

In the roster mutation handlers, change the guard `with true <- socket.assigns.admin?` → `with true <- socket.assigns.manage?` for these four handlers ONLY: `enroll_new`, `search`, `enroll_existing`, `transfer`, `withdraw`. (Note: `search` uses `if socket.assigns.admin?` — change it to `socket.assigns.manage?`.) Leave `assign`, `unassign`, `set_coefficient`, `reassign`, and `set_form_master` gated on `@admin?`.

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS (all, including the non-admin-member test which now hits the `false ->` redirect because a plain teacher who is not the form master fails `admin_or_form_master?`).

- [ ] **Step 6: Verify the pre-existing non-admin test still holds**

The existing `"non-admin member: no mutation controls, forged events rejected"` test uses a `:teacher` who is NOT the form master. Confirm it now expects a redirect (mount fails `admin_or_form_master?`). Update that test: it previously asserted `refute has_element?(view, "#enroll-form")` after a successful `live/2`; now `live/2` returns `{:error, {:live_redirect, %{to: "/school"}}}`. Change it to:

```elixir
  test "non-admin non-form-master member is redirected", ctx do
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

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}")
  end
```

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/class_live.ex test/teacher_assistant_web/live/school/class_live_test.exs
git commit -m "feat(school): form master gets scoped roster access on class page (P2.5)"
```

---

### Task 5: Widen results, bulletin, and print access to admin-or-form-master

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`
- Test: `test/teacher_assistant_web/live/school/results_live_test.exs`, `bulletin_live_test.exs`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (extend each)

**Interfaces:**
- Consumes: `Permissions.admin_or_form_master?/2`.
- Produces: results/bulletin/print surfaces reachable by the class's form master; unrelated users still redirected.

- [ ] **Step 1: Write failing access tests**

Add to `test/teacher_assistant_web/live/school/results_live_test.exs`:

```elixir
  test "the form master can view results for their class", %{conn: conn, cg: cg, head: head, school: school} do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ "Awa"
  end
```

Add to `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`:

```elixir
  test "the form master can print their class", %{conn: conn, cg: cg, seq: seq, head: head, school: school} do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    assert html_response(conn, 200) =~ "Awa Ngo"
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: FAIL — form master is redirected (still admin-only).

- [ ] **Step 3: Widen `results_live` mount**

In `lib/teacher_assistant_web/live/school/results_live.ex`, replace the `mount/3` `with`:

```elixir
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      {:ok, socket |> assign(cg: cg, sequences: sequences) |> select_seq(nil)}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end
```

- [ ] **Step 4: Widen `bulletin_live` mount**

In `lib/teacher_assistant_web/live/school/bulletin_live.ex`, replace the `with` head so the class is fetched before the authz check:

```elixir
  def mount(%{"id" => id, "enrollment_id" => eid} = params, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         roster = Academics.list_roster(cg),
         %{student: student, enrollment: enrollment} <-
           Enum.find(roster, &(&1.enrollment.id == eid)) do
      year = scope.current_academic_year
      sequences = if year, do: Academics.list_sequences(year), else: []
      seq = Enum.find(sequences, &(&1.id == params["seq"])) || List.first(sequences)
      results = if seq, do: Academics.class_results(cg, seq)
      data = results && results.per_student[student.id]

      {:ok,
       assign(socket,
         cg: cg,
         student: student,
         enrollment: enrollment,
         seq: seq,
         effectif: (results && results.effectif) || 0,
         data: data
       )}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      nil -> {:ok, push_navigate(socket, to: ~p"/school/classes/#{id}/results")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end
```

(The `nil` clause catches a not-found enrollment; the `_` clause catches a failed class fetch.)

- [ ] **Step 5: Widen the print controller `with_class`**

In `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`, replace the authz line so the class is fetched first, then checked:

```elixir
  defp with_class(conn, id, params, fun) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    with %{} = user <- user,
         {:ok, scope} <- Workspaces.scope_for(user, get_session(conn, :workspace_id), nil),
         :school <- scope.current_workspace_type,
         {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         true <- Permissions.admin_or_form_master?(scope, cg),
         year when not is_nil(year) <- scope.current_academic_year,
         seq when not is_nil(seq) <-
           Enum.find(Academics.list_sequences(year), &(&1.id == params["seq"])) do
      fun.(scope, cg, seq, Academics.class_results(cg, seq))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
```

- [ ] **Step 6: Run to verify they pass**

Run: `mix test test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`
Expected: PASS (existing cross-school + non-admin redirects still hold — an unrelated `:teacher` is neither admin nor form master, so `admin_or_form_master?` is false → redirect).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant_web/live/school/results_live.ex lib/teacher_assistant_web/live/school/bulletin_live.ex lib/teacher_assistant_web/controllers/bulletin_print_controller.ex test/teacher_assistant_web/live/school/results_live_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs
git commit -m "feat(school): form master gets scoped results/bulletin/print access (P2.5)"
```

---

### Task 6: "Mes classes" dashboard section

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs` (create if absent, else extend)

**Interfaces:**
- Consumes: `Academics.list_form_master_classes/3`.
- Produces: `@my_classes` assign; a `#my-classes` section listing the current user's form-master classes.

- [ ] **Step 1: Write the failing test**

Create/extend `test/teacher_assistant_web/live/school/dashboard_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Dash"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, head: head}
  end

  test "shows Mes classes when the user is a form master", %{conn: conn, cg: cg, head: head} do
    {:ok, _} = Academics.set_form_master(cg, head.id)
    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "Mes classes"
    assert html =~ "6e A"
  end

  test "no Mes classes section when the user is not a form master", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school")
    refute html =~ "Mes classes"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs`
Expected: FAIL — no "Mes classes" markup.

- [ ] **Step 3: Load the classes in mount/load_stats**

In `lib/teacher_assistant_web/live/school/dashboard_live.ex`, in `load_stats/1`, compute and assign `my_classes` (add before the final assign chain):

```elixir
    my_classes =
      if year,
        do: Academics.list_form_master_classes(scope.current_workspace, scope.current_user, year),
        else: []
```

and add `|> assign(:my_classes, my_classes)` to the returned socket chain.

- [ ] **Step 4: Render the section**

In `render/1`, add — right after the closing `</%= cond do %>` block's `<% end %>` and before `</section>`:

```elixir
        <div :if={@my_classes != []} id="my-classes" class="ta-leaf space-y-2">
          <h2 class="text-sm font-semibold">{gettext("Mes classes")}</h2>
          <ul class="space-y-1">
            <li :for={c <- @my_classes}>
              <.link navigate={~p"/school/classes/#{c.id}"} class="link">
                {c.label} — {c.level}
              </.link>
            </li>
          </ul>
        </div>
```

- [ ] **Step 5: Run to verify it passes**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/dashboard_live.ex test/teacher_assistant_web/live/school/dashboard_live_test.exs
git commit -m "feat(school): Mes classes dashboard section for form masters (P2.5)"
```

---

### Task 7: Name the form master on the bulletin + results header

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex`
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`, `results_live_test.exs` (extend)

**Interfaces:**
- Consumes: `Academics.form_master/1`.
- Produces: `professeur_principal` assign passed to the print template; the visa "Professeur Principal" line shows the name when set; the results header shows the titulaire.

- [ ] **Step 1: Write the failing tests**

Add to `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`:

```elixir
  test "the bulletin names the form master when set", %{conn: conn, cg: cg, seq: seq, head: head} do
    {:ok, _} = Academics.set_form_master(cg, head.id)
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    assert html_response(conn, 200) =~ to_string(head.email)
  end
```

Add to `test/teacher_assistant_web/live/school/results_live_test.exs`:

```elixir
  test "results header shows the form master when set", %{conn: conn, cg: cg, head: head} do
    {:ok, _} = Academics.set_form_master(cg, head.id)
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ to_string(head.email)
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: FAIL — form master name not rendered.

- [ ] **Step 3: Pass the form master name from the print controller**

In `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex`, in `render_bulletins/6`, add a `professeur_principal` render assign:

```elixir
    fm = Academics.form_master(cg)

    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show,
      etablissement: scope.current_workspace.name,
      annee: scope.current_academic_year && scope.current_academic_year.name,
      professeur_principal: fm && fm.email,
      cg: cg,
      seq: seq,
      effectif: (results && results.effectif) || 0,
      bundles: bundles
    )
```

- [ ] **Step 4: Render the name in the visa block**

In `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex`, replace the "Visa Professeur Principal" slot (lines ~127-129):

```elixir
        <div class="slot">
          <div :if={@professeur_principal} class="pp-name">{@professeur_principal}</div>
          <div class="line">{gettext("Visa Professeur Principal")}</div>
        </div>
```

The template iterates bundles; `@professeur_principal` is a top-level assign, valid in every page section. If the template renders each page via a comprehension over `@bundles`, ensure `@professeur_principal` is referenced from the outer assigns (it is a controller assign, always available).

- [ ] **Step 5: Show the titulaire on the results header**

In `lib/teacher_assistant_web/live/school/results_live.ex`, in `select_seq/2` (or `mount`), resolve and assign the form master once. Simplest: in `mount`, after fetching `cg`, add `form_master: Academics.form_master(cg)` to the first `assign`. Then in `render/1`, add a subtitle line under the `page_header` title, e.g. inside the header block:

```elixir
        <p :if={@form_master} class="text-sm text-base-content/70">
          {gettext("Professeur principal")}: {@form_master.email}
        </p>
```

Place this `<p>` immediately after `</.page_header>` opening content — put it right below the `<.page_header ...>` element, before `<.empty_state ...>`. Add `form_master: Academics.form_master(cg)` to the mount assign:

```elixir
      {:ok, socket |> assign(cg: cg, form_master: Academics.form_master(cg), sequences: sequences) |> select_seq(nil)}
```

- [ ] **Step 6: Add the `.pp-name` print style (optional, for legibility)**

In the `<style>` block of `show.html.heex`, near the `.visa` rules, add:

```css
      .visa .pp-name { font-size: 11px; margin-bottom: 2px; }
```

- [ ] **Step 7: Run to verify they pass**

Run: `mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/results_live_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/controllers/bulletin_print_controller.ex lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex lib/teacher_assistant_web/live/school/results_live.ex test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/results_live_test.exs
git commit -m "feat(school): name the professeur principal on bulletin + results (P2.5)"
```

---

### Task 8: gettext extract + FR/EN translations + final gate

**Files:**
- Modify: `priv/gettext/fr/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/default.pot`

**Interfaces:**
- Consumes: all msgids added in Tasks 3–7 (`"Professeur principal"`, `"Aucun"`, `"Form master assigned."`, `"Form master cleared."`, `"Mes classes"`, `"Visa Professeur Principal"` if newly touched).

- [ ] **Step 1: Extract and merge**

Run:
```bash
mix gettext.extract --merge
```

- [ ] **Step 2: Fill every new msgid in BOTH locales**

Open `priv/gettext/fr/LC_MESSAGES/default.po` and `priv/gettext/en/LC_MESSAGES/default.po`. For every new msgid with an empty `msgstr`, provide a translation. Source strings are French, so:
- FR msgstrs mirror the msgid (e.g. `"Professeur principal"` → `"Professeur principal"`, `"Aucun"` → `"Aucun"`, `"Mes classes"` → `"Mes classes"`).
- For the English-source flash strings (`"Form master assigned."`, `"Form master cleared."`), FR msgstrs are `"Professeur principal affecté."` and `"Professeur principal retiré."`; EN msgstrs equal the msgid.
- EN msgstrs for French-source strings: `"Professeur principal"` → `"Form master"`, `"Aucun"` → `"None"`, `"Mes classes"` → `"My classes"`, `"Visa Professeur Principal"` → `"Form master's signature"`.

Verify no empty `msgstr ""` remains for any newly added msgid in either file:
```bash
grep -n "Professeur principal\|Mes classes\|Form master\|Aucun" priv/gettext/en/LC_MESSAGES/default.po
```

- [ ] **Step 3: Run the full precommit gate**

Run:
```bash
mix precommit
```
Expected: compile (no warnings), deps.unlock --unused clean, format clean, full test suite green.

If the email-fixture flake (`users_unique_email_index`) trips a single unrelated failure, re-run at a fixed seed to confirm it is the known flake:
```bash
mix test --seed 0
```

- [ ] **Step 4: Commit**

```bash
git add priv/gettext
git commit -m "chore(i18n): extract + FR/EN for P2.5 form master"
```

---

## Self-Review

**Spec coverage:**
- §1 Data model → Task 1 ✓
- §2 Assignment (admin) → Task 3 ✓
- §3 Access scoping (all surfaces) → Tasks 4 (class detail + roster) & 5 (results/bulletin/print); assignments/coefficient stay admin-only (Task 4 Step 4); classes list route untouched ✓
- §4 Discovery "Mes classes" → Task 6 ✓
- §5 Bulletin display + results header → Task 7 ✓
- §6 Testing → each task is TDD; i18n + gate → Task 8 ✓

**Placeholder scan:** No TBD/TODO; all steps carry concrete code and commands.

**Type consistency:** `form_master?/2`, `admin_or_form_master?/2`, `set_form_master/2`, `form_master/1`, `list_form_master_classes/3` are defined in Tasks 1–2 and consumed with matching arities/signatures in Tasks 3–7. `@manage?`/`@admin?` assigns are introduced in Task 4 and used consistently. `professeur_principal` render assign defined and consumed in Task 7.

**Known risks flagged in spec:** the mount-gate widening (admin? → admin_or_form_master?) with the assignments panel staying admin-branched is handled explicitly in Task 4 Step 4; every mutation handler re-checks (`@manage?` for roster, `@admin?` for assignments/form-master).
