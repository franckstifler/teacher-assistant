# E — Role-aware navigation and home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each school member gets the menu and home screen of their role's "space" (Proviseur, Censeur, Surveillant général, Intendant, Enseignant, École). A member with several spaces switches between them at the top of the menu, and the choice is remembered for the session.

**Architecture:**
- `TeacherAssistantWeb.Spaces` defines the spaces as data and computes a member's spaces from their roles plus two facts: they teach, they are a form master.
- An `:assign_space` on_mount resolves the current space from the session and stores it in `scope.capabilities`.
- `GET /school/space/:key` switches space.
- The layout renders the school menu from the space's sections, and `/school` sends each member to their space's home.
- No permission changes.

**Tech Stack:** Elixir 1.20, Phoenix LiveView 1.x, Ash 3.33, daisyUI, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` § E

## Plan rulings

- **The Enseignant menu shows "Classes" when the member is a form master.** Form masters used to reach their class through the dashboard, which they no longer land on. It shows "Mes cours" only when the member teaches.
- **The current space is kept in `scope.capabilities`** (`:spaces`, `:space`) rather than new `Scope` fields. That map already carries navigation-only data computed at mount.
- **Existing nav element ids and msgids stay the same:** `nav-school-dashboard`, `-courses`, `-classes`, `-timetable-me`, `-members`, `-settings`, with msgids "Dashboard", "Mes cours", "Classes", "Mon emploi du temps", "Members", "Settings". Existing tests and translations keep working. New items use new ids and French msgids.
- **The layout computes the space itself when `:assign_space` did not run,** for any LiveView outside the two school live sessions. The menu is therefore never missing.

## Global Constraints

- The menu is not a security boundary. No policy, `can_*?` check or screen-level guard is removed or weakened.
- Space keys are parsed from an explicit map (`"proviseur" => :proviseur`, …), never with `String.to_atom`.
- Priority, which is also the default space: Proviseur > Censeur > Surveillant général > Intendant > Enseignant > École.
- UI copy is French gettext msgids, except the existing English msgids listed above, which are kept. Every new msgid gets an English msgstr after `mix gettext.extract --merge`. Un-fuzzy any fuzzy entry that matches a new msgid; **fuzzy entries are used at runtime**.
- Run only each task's own test files, plus the files it says it touches. `mix precommit` and `mix compile --warnings-as-errors` run once, in Task 5.

## Review Focus

1. **A teacher requesting `/school/space/proviseur`.** It is ignored: no session change, and a redirect to `/school`, which lands on their own home. Tested in Task 2.
2. **A stored space whose role was removed since.** It falls back to the highest remaining space and does not crash. Tested in Task 2.
3. **A member with no role-specific space who neither teaches nor masters a class.** They get the École space and land on Classes. Tested in Tasks 1 and 4.
4. **A hidden screen typed directly** (a teacher opening `/school/settings`). It stays refused exactly as before. Tested in Task 3.
5. **Inside a course,** the per-course menu (Liste, Notes, Résultats) still appears under the space menu. Tested in Task 3.

---

### Task 1: `Spaces`: spaces as data

**Files:**
- Create: `lib/teacher_assistant_web/spaces.ex`
- Test: `test/teacher_assistant_web/spaces_test.exs`

**Interfaces:**
- Produces:
  - `Spaces.keys_for(%{roles: [atom], teaches?: boolean, form_master?: boolean}) :: [key]`, in priority order and never empty.
  - `key :: :proviseur | :censeur | :surveillant | :intendant | :enseignant | :ecole`.
  - `Spaces.resolve(keys, stored :: key | nil) :: key`: `stored` if it's in `keys`, otherwise `hd(keys)`.
  - `Spaces.parse_key(String.t()) :: key | nil`.
  - `Spaces.space(key, facts) :: %{key, label, home, sections: [%{label, items: [%{id, label, icon, path}]}]}`.
  - `Spaces.facts(scope) :: facts`, computed from the DB: `scope.current_roles`, units, and the form-master classes of the current year.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.SpacesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistantWeb.Spaces

  defp facts(roles, opts \\ []),
    do: %{roles: roles, teaches?: Keyword.get(opts, :teaches?, false), form_master?: Keyword.get(opts, :form_master?, false)}

  defp item_ids(key, facts),
    do: for(section <- Spaces.space(key, facts).sections, item <- section.items, do: item.id)

  test "spaces follow the roles, in priority order" do
    assert Spaces.keys_for(facts([:head])) == [:proviseur]
    assert Spaces.keys_for(facts([:teacher, :vice_principal], teaches?: true)) == [:censeur, :enseignant]
    assert Spaces.keys_for(facts([:discipline_master, :bursar])) == [:surveillant, :intendant]
    assert Spaces.keys_for(facts([:teacher], teaches?: true)) == [:enseignant]
  end

  test "a member with no role-specific space who does not teach gets École" do
    assert Spaces.keys_for(facts([:hod])) == [:ecole]
    assert Spaces.keys_for(facts([:librarian])) == [:ecole]
    assert Spaces.keys_for(facts([:teacher])) == [:ecole]
    assert Spaces.keys_for(facts([:teacher], form_master?: true)) == [:enseignant]
  end

  test "resolve keeps an allowed stored space and falls back otherwise" do
    assert Spaces.resolve([:censeur, :enseignant], :enseignant) == :enseignant
    assert Spaces.resolve([:censeur, :enseignant], :proviseur) == :censeur
    assert Spaces.resolve([:enseignant], nil) == :enseignant
  end

  test "space keys are parsed from a closed list" do
    assert Spaces.parse_key("censeur") == :censeur
    assert Spaces.parse_key("admin") == nil
  end

  test "homes and menus" do
    assert Spaces.space(:proviseur, facts([:head])).home == "/school"
    assert Spaces.space(:surveillant, facts([:discipline_master])).home == "/school/classes"
    assert Spaces.space(:enseignant, facts([:teacher], teaches?: true)).home == "/school/courses"
    assert Spaces.space(:ecole, facts([:hod])).home == "/school/classes"

    assert "nav-school-members" in item_ids(:proviseur, facts([:head]))
    assert "nav-school-members" in item_ids(:censeur, facts([:vice_principal]))
    refute "nav-school-periods" in item_ids(:censeur, facts([:vice_principal]))
    assert item_ids(:enseignant, facts([:teacher], teaches?: true)) == ["nav-school-courses", "nav-school-timetable-me"]

    assert item_ids(:enseignant, facts([:teacher], teaches?: true, form_master?: true)) ==
             ["nav-school-courses", "nav-school-classes", "nav-school-timetable-me"]
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/spaces_test.exs`
Expected: FAIL (`Spaces` undefined).

- [ ] **Step 3: Implement** `lib/teacher_assistant_web/spaces.ex`:

```elixir
defmodule TeacherAssistantWeb.Spaces do
  @moduledoc """
  Role spaces (spec E): what each school member sees in the menu and where they land.
  A space is data — label, home, menu sections. This never grants anything: every
  screen keeps its own policy checks, and a link missing from a menu stays refused
  when typed directly.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{Curriculum, Enrollment}

  @order [:proviseur, :censeur, :surveillant, :intendant, :enseignant, :ecole]
  @by_role %{head: :proviseur, vice_principal: :censeur, discipline_master: :surveillant, bursar: :intendant}
  @by_param Map.new(@order, &{Atom.to_string(&1), &1})

  @doc "The member's spaces, in priority order (never empty)."
  def keys_for(%{roles: roles, teaches?: teaches?, form_master?: form_master?}) do
    keys = MapSet.new(for role <- roles, key = @by_role[role], key != nil, do: key)
    keys = if teaches? or form_master?, do: MapSet.put(keys, :enseignant), else: keys

    case Enum.filter(@order, &MapSet.member?(keys, &1)) do
      [] -> [:ecole]
      ordered -> ordered
    end
  end

  @doc "The stored space when it is still one of the member's, otherwise their first."
  def resolve([first | _] = keys, stored), do: if(stored in keys, do: stored, else: first)

  def parse_key(param) when is_binary(param), do: Map.get(@by_param, param)
  def parse_key(_), do: nil

  @doc "What the space-deciding facts are for a school scope (DB reads, once per mount)."
  def facts(%{current_workspace: %{}} = scope) do
    year = scope.current_academic_year

    %{
      roles: scope.current_roles || [],
      teaches?: Curriculum.list_units_for_scope(scope) != [],
      form_master?: year != nil and Enrollment.list_form_master_classes(scope, year) != []
    }
  end

  def space(:proviseur, _facts) do
    %{
      key: :proviseur,
      label: gettext("Proviseur"),
      home: ~p"/school",
      sections: [
        section(gettext("Pilotage"), [dashboard(), classes(), members()]),
        section(gettext("Paramètres"), [settings(), coefficients(), evaluations(), periods()])
      ]
    }
  end

  def space(:censeur, _facts) do
    %{
      key: :censeur,
      label: gettext("Censeur"),
      home: ~p"/school",
      sections: [
        section(gettext("Suivi pédagogique"), [dashboard(), classes(), members()]),
        section(gettext("Paramètres"), [settings(), coefficients(), evaluations()])
      ]
    }
  end

  def space(:surveillant, _facts) do
    %{
      key: :surveillant,
      label: gettext("Surveillant général"),
      home: ~p"/school/classes",
      sections: [section(gettext("Vie scolaire"), [classes()])]
    }
  end

  def space(:intendant, _facts) do
    %{
      key: :intendant,
      label: gettext("Intendant"),
      home: ~p"/school/classes",
      sections: [section(gettext("Intendance"), [classes()])]
    }
  end

  def space(:enseignant, facts) do
    items =
      [facts.teaches? && courses(), facts.form_master? && classes(), timetable()]
      |> Enum.filter(& &1)

    %{
      key: :enseignant,
      label: gettext("Enseignant"),
      home: if(facts.teaches?, do: ~p"/school/courses", else: ~p"/school/classes"),
      sections: [section(gettext("Enseignement"), items)]
    }
  end

  def space(:ecole, _facts) do
    %{
      key: :ecole,
      label: gettext("École"),
      home: ~p"/school/classes",
      sections: [section(gettext("École"), [classes(), timetable()])]
    }
  end

  defp section(label, items), do: %{label: label, items: items}

  defp item(id, label, icon, path), do: %{id: "nav-school-#{id}", label: label, icon: icon, path: path}

  defp dashboard, do: item("dashboard", gettext("Dashboard"), "hero-squares-2x2", ~p"/school")
  defp courses, do: item("courses", gettext("Mes cours"), "hero-academic-cap", ~p"/school/courses")
  defp classes, do: item("classes", gettext("Classes"), "hero-rectangle-group", ~p"/school/classes")

  defp timetable,
    do: item("timetable-me", gettext("Mon emploi du temps"), "hero-calendar-days", ~p"/school/timetable/me")

  defp members, do: item("members", gettext("Members"), "hero-user-group", ~p"/school/members")
  defp settings, do: item("settings", gettext("Settings"), "hero-cog-6-tooth", ~p"/school/settings")

  defp coefficients,
    do: item("coefficients", gettext("Matières & coefficients"), "hero-table-cells", ~p"/school/settings/coefficients")

  defp evaluations,
    do: item("evaluations", gettext("Évaluations & moyennes"), "hero-calculator", ~p"/school/settings/evaluations")

  defp periods, do: item("periods", gettext("Périodes"), "hero-clock", ~p"/school/periods")
end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/spaces_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/spaces.ex test/teacher_assistant_web/spaces_test.exs
git commit -m "feat: role spaces as data

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Current space: session, on_mount, switch route

**Files:**
- Modify: `lib/teacher_assistant_web/live_user_auth.ex` (`session_context/1` gains `"space"`; new `on_mount(:assign_space, …)`)
- Modify: `lib/teacher_assistant_web/router.ex` (route; `:assign_space` after `:assign_capabilities` in the `:school_workspace` and `:teaching` live sessions)
- Create: `lib/teacher_assistant_web/controllers/space_controller.ex`
- Test: `test/teacher_assistant_web/controllers/space_controller_test.exs`

**Interfaces:**
- Consumes: `Spaces.facts/1`, `keys_for/1`, `resolve/2`, `parse_key/1`, `space/2` (Task 1).
- Produces:
  - `scope.capabilities[:spaces] :: [key]` and `scope.capabilities[:space] :: space map`, set by `:assign_space`.
  - `GET /school/space/:key` stores `:space` in the session (as a string) only for one of the member's spaces, then redirects to that space's home. Otherwise it redirects to `/school` without changing the session.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.SpaceControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée S"})
    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    %{school: school, scope: scope, year: year}
  end

  defp conn_for(school, user) do
    build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  defp censeur_who_teaches(%{school: school, scope: scope, year: year}) do
    member = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal, :teacher]})
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, _} = Curriculum.assign_teacher(scope, cg, member.current_user, %{subject: "Maths"})
    conn_for(school, member.current_user)
  end

  test "a member switches to one of their spaces and lands on its home", ctx do
    conn = censeur_who_teaches(ctx) |> get(~p"/school/space/enseignant")
    assert redirected_to(conn) == "/school/courses"
    assert get_session(conn, :space) == "enseignant"
  end

  test "a space the member does not have is ignored", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    conn = conn_for(ctx.school, teacher.current_user) |> get(~p"/school/space/proviseur")
    assert redirected_to(conn) == "/school"
    assert get_session(conn, :space) == nil

    conn = conn_for(ctx.school, teacher.current_user) |> get(~p"/school/space/whatever")
    assert redirected_to(conn) == "/school"
  end

  test "a stored space whose role was removed falls back to the highest remaining one", ctx do
    member = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:vice_principal, :discipline_master]})
    conn = conn_for(ctx.school, member.current_user) |> Plug.Conn.put_session(:space, "censeur")

    {:ok, membership} = Accounts.fetch_school_membership(ctx.scope, member.current_user)
    {:ok, _} = Accounts.update_member_roles(ctx.scope, membership, [:discipline_master])

    {:ok, view, _} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-classes")
  end
end
```

Check the actual name and signature of the function that changes a member's roles in `TeacherAssistant.Accounts` (`grep -n "roles" lib/teacher_assistant/accounts.ex`) and use it. If it's not `update_member_roles/3`, adapt the call; the assertion stays the same.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/controllers/space_controller_test.exs`
Expected: FAIL (no route).

- [ ] **Step 3: Implement.**

`live_user_auth.ex`:
- Add `"space" => Plug.Conn.get_session(conn, :space)` to `session_context/1`.
- Add, after `on_mount(:assign_capabilities, …)`:

```elixir
  # The member's role spaces and the current one (spec E), for the layout and the
  # /school landing. Navigation only — never an authorization input.
  def on_mount(:assign_space, _params, session, socket) do
    case socket.assigns.current_scope do
      %{current_workspace: %{}} = scope ->
        facts = TeacherAssistantWeb.Spaces.facts(scope)
        keys = TeacherAssistantWeb.Spaces.keys_for(facts)
        key = TeacherAssistantWeb.Spaces.resolve(keys, TeacherAssistantWeb.Spaces.parse_key(session["space"]))

        capabilities =
          Map.merge(scope.capabilities || %{}, %{
            spaces: keys,
            space: TeacherAssistantWeb.Spaces.space(key, facts)
          })

        scope = %{scope | capabilities: capabilities}
        {:cont, socket |> Phoenix.Component.assign(:current_scope, scope) |> Phoenix.Component.assign(:scope, scope)}

      _ ->
        {:cont, socket}
    end
  end
```

Router:
- In both `ash_authentication_live_session :teaching` and `:school_workspace`, add `{TeacherAssistantWeb.LiveUserAuth, :assign_space}` right after `:assign_capabilities`. Add `:assign_capabilities` too if a session lacks it; check the `:teaching` session's `on_mount` list.
- In the `scope "/", TeacherAssistantWeb do pipe_through [:browser, :school]` block, next to `get "/teacher/select-context/:id"`, add `get "/school/space/:key", SpaceController, :select`.

`lib/teacher_assistant_web/controllers/space_controller.ex`:

```elixir
defmodule TeacherAssistantWeb.SpaceController do
  @moduledoc "Switches the member's role space (spec E, R02). Only their own spaces are accepted."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistantWeb.Spaces

  def select(%{assigns: %{current_user: nil}} = conn, _params), do: redirect(conn, to: ~p"/sign-in")

  def select(conn, %{"key" => param}) do
    scope =
      Workspaces.session_scope(
        conn.assigns.current_user,
        get_session(conn, :workspace_id),
        get_session(conn, :context_id)
      )

    with %{current_workspace: %{}} <- scope,
         key when not is_nil(key) <- Spaces.parse_key(param),
         facts = Spaces.facts(scope),
         true <- key in Spaces.keys_for(facts) do
      conn
      |> put_session(:space, Atom.to_string(key))
      |> redirect(to: Spaces.space(key, facts).home)
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
```

`Workspaces.session_scope/3` is what `LiveUserAuth.assign_scope/2` uses. If it's private or takes different arguments, use the public entry point `assign_scope` relies on (read `lib/teacher_assistant/accounts/workspaces.ex`).

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/controllers/space_controller_test.exs test/teacher_assistant_web/live/school_shell_test.exs`
Expected: PASS. The fallback test's nav assertions depend on Task 3's menu; the current hard-coded menu already hides Members from non-heads, so it passes now and keeps passing after Task 3.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web/controllers/space_controller_test.exs
git commit -m "feat: current role space in the session, with a switch route

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The layout renders the space's menu and the switcher

**Files:**
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (the `#school-nav` block; assigns in `app/1`)
- Test: `test/teacher_assistant_web/live/role_spaces_test.exs`; update `test/teacher_assistant_web/live/school_shell_test.exs` only if an id or label assertion no longer holds
- Modify: gettext files

**Interfaces:**
- Consumes: `scope.capabilities[:space]` and `[:spaces]` (Task 2); `Spaces.facts/keys_for/resolve/space` for the fallback.
- Produces:
  - DOM: `#school-nav` with one `<p class="ta-rail__label">` per section and the items' ids.
  - `#space-switcher`, only when the member has more than one space, with links `#space-switch-<key>` to `/school/space/<key>` and `aria-current="true"` on the current one.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.RoleSpacesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{actor: head} do
    {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée R"})
    scope = school_scope(head, school)
    year = TeacherFixtures.complete_school_setup!(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    %{school: school, scope: scope, cg: cg}
  end

  defp member_conn(ctx, roles, opts \\ []) do
    member = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: roles})

    tc =
      if opts[:teaches?],
        do: elem(Curriculum.assign_teacher(ctx.scope, ctx.cg, member.current_user, %{subject: "Maths"}), 1)

    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, member.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ctx.school.id)

    {conn, tc}
  end

  test "a teacher sees only their teaching menu, without a switcher", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-courses")
    assert has_element?(view, "#nav-school-timetable-me")
    refute has_element?(view, "#nav-school-dashboard")
    refute has_element?(view, "#nav-school-settings")
    refute has_element?(view, "#space-switcher")
  end

  test "a censeur who teaches switches between Censeur and Enseignant", ctx do
    {conn, _} = member_conn(ctx, [:vice_principal, :teacher], teaches?: true)
    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#space-switch-censeur[aria-current]")
    assert has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-coefficients")

    conn = get(conn, ~p"/school/space/enseignant")
    {:ok, view, _} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#space-switch-enseignant[aria-current]")
    refute has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-courses")
  end

  test "a hidden screen stays refused when typed directly", ctx do
    {conn, _} = member_conn(ctx, [:teacher], teaches?: true)
    assert {:error, {_kind, %{to: to}}} = live(conn, ~p"/school/settings")
    refute to == "/school/settings"
  end

  test "inside a course the per-course menu still shows", ctx do
    {conn, tc} = member_conn(ctx, [:teacher], teaches?: true)
    conn = get(conn, ~p"/teacher/select-context/#{tc.id}")
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/marks")
    assert has_element?(view, "#per-class-nav")
    assert has_element?(view, "#nav-school-courses")
  end
end
```

The "hidden screen" test must pass both before and after this task, since that's the point. Check how `/school/settings` refuses a teacher today: its section guards, or a redirect from the page. If a teacher can mount the page but sees nothing editable, assert instead that `#year-form` and `#subject-form` are absent, and name the test "…stays read-only". Keep the test either way; don't change the settings page.

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/role_spaces_test.exs`
Expected: the teacher-menu and censeur tests FAIL (the rail still shows Dashboard, and there's no switcher).

- [ ] **Step 3: Implement** in `layouts.ex`:
- In `app/1`, compute the space:

```elixir
    space_info =
      case current_scope do
        %{current_workspace: %{}, capabilities: %{space: space, spaces: keys}} ->
          {space, keys}

        %{current_workspace: %{}} ->
          facts = TeacherAssistantWeb.Spaces.facts(current_scope)
          keys = TeacherAssistantWeb.Spaces.keys_for(facts)
          {TeacherAssistantWeb.Spaces.space(hd(keys), facts), keys}

        _ ->
          {nil, []}
      end
```

  Then `|> assign(:space, elem(space_info, 0)) |> assign(:space_keys, elem(space_info, 1))`. Remove the now-unused `:is_head?`/`:is_admin?` assigns if nothing else in the template uses them.

- Replace the whole `<nav :if={@in_school?} id="school-nav" …>…</nav>` with:

```heex
            <div
              :if={@in_school? and length(@space_keys) > 1}
              id="space-switcher"
              class="flex flex-wrap gap-1 px-1"
              role="navigation"
              aria-label={gettext("Espaces")}
            >
              <.link
                :for={key <- @space_keys}
                id={"space-switch-#{key}"}
                href={~p"/school/space/#{key}"}
                aria-current={@space && @space.key == key && "true"}
                class={[
                  "btn btn-xs rounded-full",
                  if(@space && @space.key == key, do: "btn-primary", else: "btn-ghost")
                ]}
              >
                {TeacherAssistantWeb.Spaces.space(key, %{roles: [], teaches?: true, form_master?: true}).label}
              </.link>
            </div>

            <nav
              :if={@in_school? and @space}
              id="school-nav"
              class="flex flex-col gap-0.5"
              aria-label={gettext("School navigation")}
            >
              <%= for section <- @space.sections do %>
                <p class="ta-rail__label px-1.5 pb-1 pt-2">{section.label}</p>
                <.rail_link
                  :for={item <- section.items}
                  id={item.id}
                  href={item.path}
                  icon={item.icon}
                  current_path={@current_path}
                >
                  {item.label}
                </.rail_link>
              <% end %>
            </nav>
```

  The switcher only needs each space's `label`, which doesn't depend on facts, hence the dummy facts. To avoid that, add `Spaces.label/1` returning `space(key, …).label`, and use it here and in `space/2`. Prefer that; it's a 6-clause function.

Run `mix gettext.extract --merge`, and add English msgstrs:

| French msgid | English msgstr |
|---|---|
| Proviseur | Principal |
| Censeur | Vice-principal (existing msgid; check it's translated) |
| Surveillant général | Discipline master (existing) |
| Intendant | Bursar (existing) |
| Enseignant | Teacher (existing) |
| École | School |
| Pilotage | Management |
| Paramètres | Settings (existing) |
| Suivi pédagogique | Academic follow-up |
| Vie scolaire | School life |
| Intendance | Finance |
| Enseignement | Teaching |
| Matières & coefficients | Subjects & coefficients (existing) |
| Évaluations & moyennes | Assessments & averages (existing) |
| Périodes | Periods |
| Espaces | Spaces |

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/role_spaces_test.exs test/teacher_assistant_web/live/school_shell_test.exs test/teacher_assistant_web/live/school/courses_live_test.exs test/teacher_assistant_web/locale_test.exs test/teacher_assistant_web/controllers/space_controller_test.exs`
Expected: PASS.

- The shell test "the rail marks the current page as active" visits `/school/courses` as the head. The head teaches Maths in that setup, so their default space is Proviseur, whose menu has no "Mes cours". If that test now fails because `#nav-school-courses` is absent, switch the test's conn to the Enseignant space first (`get(conn, ~p"/school/space/enseignant")`), keeping its assertion.
- In "staff and settings nav items show for the head only", the head's Proviseur menu has Members and Settings, and the teacher's doesn't. It passes unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web test/teacher_assistant_web priv/gettext
git commit -m "feat: the school menu follows the member's role space, with a switcher

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `/school` lands on the space's home

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex` (`mount/3`; remove `plain_teacher?/1` and `form_master_classes/1` if unused)
- Test: append to `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `scope.capabilities[:space]` (Task 2).
- Produces: `/school` shows the dashboard for the Proviseur and Censeur spaces. Any other space is `push_navigate`d to `space.home`.

- [ ] **Step 1: Write the failing tests** (append; reuse the file's setup and helpers for conns of other members, or build one inline as in Task 3's `member_conn`):

```elixir
  describe "landing by role space" do
    setup %{actor: head} do
      {:ok, school} = Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée L"})
      scope = school_scope(head, school)
      TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
      %{school: school, lscope: scope}
    end

    defp conn_with_roles(school, scope, roles) do
      member = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: roles})

      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, member.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)
    end

    test "a surveillant général lands on the classes", %{school: school, lscope: scope} do
      conn = conn_with_roles(school, scope, [:discipline_master])
      assert {:error, {:live_redirect, %{to: "/school/classes"}}} = live(conn, ~p"/school")
    end

    test "a member with no space of their own lands on the classes (École)", %{school: school, lscope: scope} do
      conn = conn_with_roles(school, scope, [:librarian])
      assert {:error, {:live_redirect, %{to: "/school/classes"}}} = live(conn, ~p"/school")
    end

    test "a censeur stays on the dashboard", %{school: school, lscope: scope} do
      conn = conn_with_roles(school, scope, [:vice_principal])
      assert {:ok, _view, _html} = live(conn, ~p"/school")
    end
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs`
Expected: the surveillant and École tests FAIL (the dashboard renders for them today).

- [ ] **Step 3: Implement.** In `dashboard_live.ex`, replace the first `cond` branch:

```elixir
      scope.current_workspace != nil and landing_elsewhere(scope) != nil ->
        {:ok, push_navigate(socket, to: landing_elsewhere(scope))}
```

and add:

```elixir
  # Proviseur and Censeur use the dashboard as their home; every other space lands
  # on its own home (spec E).
  defp landing_elsewhere(%{capabilities: %{space: %{key: key}}}) when key in [:proviseur, :censeur],
    do: nil

  defp landing_elsewhere(%{capabilities: %{space: %{home: home}}}), do: home
  defp landing_elsewhere(_scope), do: nil
```

Delete `plain_teacher?/1` and `form_master_classes/1` if nothing else uses them (`grep` first). The existing "a plain teacher lands on their courses from /school" test (`courses_live_test.exs`) still passes: a teacher with an assignment is in the Enseignant space, whose home is `/school/courses`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs test/teacher_assistant_web/live/school/courses_live_test.exs test/teacher_assistant_web/live/role_spaces_test.exs`
Expected: PASS.

A form master who doesn't teach and has no other role is now in the Enseignant space, whose home is `/school/classes` (Spaces rule). Before, they got the dashboard. If an existing test asserts that such a member sees the dashboard, update it to the Classes landing. That's the spec's change, not a regression.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/dashboard_live.ex test/teacher_assistant_web/live/school/dashboard_live_test.exs
git commit -m "feat: /school lands on each member's space home

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Full gate

- [ ] **Step 1:** Run `mix compile --warnings-as-errors && mix precommit`.
  Expected: no warnings; the whole suite is green (872 + the new tests). Nav tests elsewhere that break because an item moved spaces get their assertions updated to the space the test's member is actually in. Never change `Spaces` to make them pass.
- [ ] **Step 2:** Commit any formatter rewrites:

```bash
git add -A lib test priv/gettext
git commit -m "chore: formatter

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
