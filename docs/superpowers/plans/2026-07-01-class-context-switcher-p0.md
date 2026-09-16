# Class-context Switcher + Component Kit (P0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a session-backed "current class" to the authenticated shell so every per-class page is reachable from a class switcher, and ship the shared component kit + accessibility fixes alongside.

**Architecture:** Extend `TeacherAssistant.Scope` with `current_context`, resolved from `session["context_id"]` during scope assembly (mirroring the shipped `workspace_id` pattern). A GET controller route persists the selection and redirects context-aware. `Layouts.app` renders a class switcher, class-independent tabs, per-class tabs, and a mobile bottom nav from the scope. A component kit (`page_header`, `stat`, `empty_state`, `setup_gate`, `mention_badge`) lands in `core_components.ex`.

**Tech Stack:** Elixir, Ash 3.26, Phoenix LiveView, daisyUI/Tailwind v4, gettext, ExUnit.

## Global Constraints

- **Reuse the shipped session→scope pattern.** Selection persists in the session only (`session["context_id"]`) — **no new persistence table**. Mirror `WorkspaceController` / `LocaleController` and `LiveUserAuth.assign_scope/2`.
- **Owner + active-year scoped; no IDOR.** `current_context` is resolved only from the workspace's own `TeachingContext`s for the active year. A foreign/invalid/stale id silently falls back to the default (first class) — never leaks or crashes.
- **Fallback order:** valid `session["context_id"]` → else first `TeachingContext` (alphabetical by subject) → else `nil` ("Set up a class").
- **Context-aware redirect after select:** if `return_to` matches `/teacher/contexts/<id>/...`, rewrite the id segment; else return to `return_to` unchanged. `return_to` must be a local `/teacher` path (open-redirect guard).
- **Apply Tableau** — no new colors/fonts; use existing `ta-*` classes, daisyUI tokens, `<.icon>` heroicons, `gettext` for all copy.
- **Preserve stable DOM IDs** on existing pages so current LiveView tests keep passing; add IDs for new shell elements.
- **a11y:** mark score inputs get `aria-label`; mentions show word+icon (never color alone); numeric columns use `ta-num`.
- **`mix precommit` green** (compile `--warning-as-errors`, format, test) before each commit; pristine output.
- **FR/EN mention labels** (design-pass spec Appendix B): `:excellent`→Excellent, `:tres_bien`→Très bien, `:bien`→Bien, `:assez_bien`→Assez bien, `:passable`→Passable, `nil`→Insuffisant.
- Commit messages end with the project `Co-Authored-By` trailer.

---

### Task 1: `current_context` in scope + resolution

**Files:**
- Modify: `lib/teacher_assistant/scope.ex` (add `:current_context` to defstruct)
- Modify: `lib/teacher_assistant/academics.ex` (add `resolve_current_context/3`)
- Modify: `lib/teacher_assistant/accounts/workspaces.ex` (`scope_for/3`)
- Modify: `lib/teacher_assistant_web/live_user_auth.ex` (session plumbing)
- Test: `test/teacher_assistant/accounts/workspaces_test.exs` (create if absent)
- Test: `test/teacher_assistant/academics/resolve_context_test.exs`

**Interfaces:**
- Produces:
  - `%TeacherAssistant.Scope{current_context: %TeachingContext{} | nil}` (new field)
  - `Academics.resolve_current_context(ws, year, context_id) :: %TeachingContext{} | nil`
  - `Workspaces.scope_for(user, workspace_id, context_id \\ nil) :: {:ok, %Scope{}} | {:error, term}`

- [ ] **Step 1: Write the failing test for `resolve_current_context/3`**

```elixir
# test/teacher_assistant/academics/resolve_context_test.exs
defmodule TeacherAssistant.Academics.ResolveContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
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

    {:ok, maths} =
      Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})

    {:ok, pct} =
      Academics.create_teaching_context(ws, year, %{subject: "PCT", level: "3ème", subsystem: :francophone, weekly_hours: 4})

    %{ws: ws, year: year, maths: maths, pct: pct}
  end

  test "returns the requested context when valid", %{ws: ws, year: year, pct: pct} do
    assert %{id: id} = Academics.resolve_current_context(ws, year, pct.id)
    assert id == pct.id
  end

  test "falls back to first (alphabetical) when id is nil/invalid/foreign", %{ws: ws, year: year, maths: maths} do
    assert Academics.resolve_current_context(ws, year, nil).id == maths.id
    assert Academics.resolve_current_context(ws, year, Ecto.UUID.generate()).id == maths.id

    other = TeacherFixtures.workspace_fixture()
    {:ok, oyear} = Academics.create_academic_year(other, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, foreign} = Academics.create_teaching_context(other, oyear, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
    assert Academics.resolve_current_context(ws, year, foreign.id).id == maths.id
  end

  test "returns nil when there is no active year or no contexts", %{ws: ws} do
    assert Academics.resolve_current_context(ws, nil, nil) == nil
    empty = TeacherFixtures.workspace_fixture()
    {:ok, y} = Academics.create_academic_year(empty, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    assert Academics.resolve_current_context(empty, y, nil) == nil
  end
end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/teacher_assistant/academics/resolve_context_test.exs`
Expected: FAIL — `resolve_current_context/3 undefined`.

- [ ] **Step 3: Implement `resolve_current_context/3`**

In `lib/teacher_assistant/academics.ex`, add (near `list_teaching_contexts`):

```elixir
  @doc """
  Resolves the active TeachingContext for the shell's class switcher.
  Owner + active-year scoped: only the workspace's own contexts are searched, so a
  foreign/invalid/stale id simply falls back to the first (alphabetical) context.
  Returns nil when there is no active year or no contexts.
  """
  def resolve_current_context(_ws, nil, _context_id), do: nil

  def resolve_current_context(%PersonalWorkspace{} = ws, %AcademicYear{} = year, context_id) do
    contexts = list_teaching_contexts(ws, year)
    Enum.find(contexts, fn c -> c.id == context_id end) || List.first(contexts)
  end
```

- [ ] **Step 4: Run it — expect pass**

Run: `mix test test/teacher_assistant/academics/resolve_context_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Add `:current_context` to the scope struct**

In `lib/teacher_assistant/scope.ex`, extend the defstruct:

```elixir
  defstruct [
    :current_user,
    :current_workspace,
    :current_workspace_type,
    :current_role,
    :current_academic_year,
    :current_context,
    :locale
  ]
```

- [ ] **Step 6: Write the failing test for `scope_for/3`**

```elixir
# test/teacher_assistant/accounts/workspaces_test.exs
defmodule TeacherAssistant.Accounts.WorkspacesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
    %{user: user, ws: ws, ctx: ctx}
  end

  test "scope_for/3 resolves current_context from a valid id", %{user: user, ws: ws, ctx: ctx} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id, ctx.id)
    assert scope.current_context.id == ctx.id
  end

  test "scope_for/3 defaults current_context when id is nil", %{user: user, ws: ws, ctx: ctx} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id, nil)
    assert scope.current_context.id == ctx.id
  end

  test "scope_for/2 still works (context nil)", %{user: user, ws: ws} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id)
    assert scope.current_workspace.id == ws.id
  end
end
```

- [ ] **Step 7: Run it — expect failure**

Run: `mix test test/teacher_assistant/accounts/workspaces_test.exs`
Expected: FAIL — `scope_for/3 undefined`.

- [ ] **Step 8: Implement `scope_for/3`**

Replace the body of `lib/teacher_assistant/accounts/workspaces.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Academics, Scope}

  def ensure_personal_workspace!(user), do: Academics.ensure_personal_workspace!(user)

  def scope_for(user, workspace_id, context_id \\ nil)

  def scope_for(user, nil, context_id) do
    ws = ensure_personal_workspace!(user)
    scope_for(user, ws.id, context_id)
  end

  def scope_for(user, workspace_id, context_id) do
    with {:ok, ws} <- Academics.get_personal_workspace(workspace_id),
         true <- ws.owner_user_id == user.id do
      year = Academics.current_academic_year(ws)

      {:ok,
       %Scope{
         current_user: user,
         current_workspace: ws,
         current_workspace_type: :personal_teacher,
         current_role: :teacher,
         current_academic_year: year,
         current_context: Academics.resolve_current_context(ws, year, context_id)
       }}
    else
      _ -> {:error, :workspace_not_found}
    end
  end
end
```

- [ ] **Step 9: Wire the session in `LiveUserAuth`**

In `lib/teacher_assistant_web/live_user_auth.ex`:

Add `context_id` to `session_context/1`:

```elixir
  def session_context(conn) do
    %{
      "workspace_id" => Plug.Conn.get_session(conn, :workspace_id),
      "user_id" => Plug.Conn.get_session(conn, :user_id),
      "context_id" => Plug.Conn.get_session(conn, :context_id),
      "locale" => Plug.Conn.get_session(conn, :locale)
    }
  end
```

Update `assign_scope/2` to pass it and default `:current_path`:

```elixir
  defp assign_scope(socket, session) do
    user = socket.assigns[:current_user] || load_user(session["user_id"])
    locale = session["locale"] || "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)
    scope = %{resolve_scope(user, session["workspace_id"], session["context_id"]) | locale: locale}

    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
    |> assign_new(:current_path, fn -> nil end)
  end
```

Replace `resolve_scope/2` with `resolve_scope/3`:

```elixir
  defp resolve_scope(nil, _workspace_id, _context_id), do: %Scope{}

  defp resolve_scope(user, workspace_id, context_id) do
    case Workspaces.scope_for(user, workspace_id, context_id) do
      {:ok, scope} -> scope
      {:error, _} -> %Scope{current_user: user}
    end
  end
```

- [ ] **Step 10: Run the focused tests + full suite**

Run:
```bash
mix test test/teacher_assistant/academics/resolve_context_test.exs test/teacher_assistant/accounts/workspaces_test.exs
mix test
```
Expected: focused green; full suite green (was 88 tests; now higher), pristine.

- [ ] **Step 11: Commit**

```bash
git add lib/teacher_assistant/scope.ex lib/teacher_assistant/academics.ex lib/teacher_assistant/accounts/workspaces.ex lib/teacher_assistant_web/live_user_auth.ex test/teacher_assistant/academics/resolve_context_test.exs test/teacher_assistant/accounts/workspaces_test.exs
git commit -m "feat: resolve current_context in scope from session (owner+active-year scoped)"
```

---

### Task 2: Class-selection controller + route

**Files:**
- Create: `lib/teacher_assistant_web/controllers/teacher_context_controller.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (add GET route)
- Test: `test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`

**Interfaces:**
- Consumes: `Workspaces.scope_for/3` (Task 1).
- Produces: route `GET /teacher/select-context/:id` → `TeacherContextController.select/2`; sets `session["context_id"]` and redirects context-aware.

- [ ] **Step 1: Write the failing controller test**

```elixir
# test/teacher_assistant_web/controllers/teacher_context_controller_test.exs
defmodule TeacherAssistantWeb.TeacherContextControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
    %{ws: ws, ctx: ctx}
  end

  test "selecting a valid class stores it and honors return_to", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=/teacher/log")
    assert redirected_to(conn) == "/teacher/log"
    assert get_session(conn, :context_id) == ctx.id
  end

  test "rewrites the id segment of a per-class return_to", %{conn: conn, ctx: ctx} do
    other = Ecto.UUID.generate()
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=/teacher/contexts/#{other}/marks")
    assert redirected_to(conn) == "/teacher/contexts/#{ctx.id}/marks"
  end

  test "rejects a foreign id without writing the session", %{conn: conn} do
    conn = get(conn, ~p"/teacher/select-context/#{Ecto.UUID.generate()}?return_to=/teacher/log")
    assert redirected_to(conn) == "/teacher/setup"
    assert get_session(conn, :context_id) == nil
  end

  test "ignores a non-local return_to", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=https://evil.example/x")
    assert redirected_to(conn) == "/teacher"
  end
end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Create the controller**

```elixir
# lib/teacher_assistant_web/controllers/teacher_context_controller.ex
defmodule TeacherAssistantWeb.TeacherContextController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(conn, %{"id" => context_id} = params) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))
    return_to = safe_return_to(params["return_to"])

    case user && Workspaces.scope_for(user, get_session(conn, :workspace_id), context_id) do
      {:ok, %{current_context: %{id: ^context_id}}} ->
        conn
        |> put_session(:context_id, context_id)
        |> redirect(to: rewrite_return_to(return_to, context_id))

      _ ->
        redirect(conn, to: ~p"/teacher/setup")
    end
  end

  # only local /teacher paths are allowed; anything else defaults to the dashboard
  defp safe_return_to("/teacher" <> _ = path), do: path
  defp safe_return_to(_), do: "/teacher"

  # if the path targets a specific class, swap its id segment to the newly selected class
  defp rewrite_return_to(path, id),
    do: Regex.replace(~r{^(/teacher/contexts/)[^/]+}, path, "\\1#{id}")

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
```

- [ ] **Step 4: Add the route**

In `lib/teacher_assistant_web/router.ex`, in the first `scope "/", TeacherAssistantWeb do` block, next to the existing `get "/workspaces/select/:id" ...`:

```elixir
    get "/teacher/select-context/:id", TeacherContextController, :select
```

- [ ] **Step 5: Run it — expect pass**

Run: `mix test test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/controllers/teacher_context_controller.ex lib/teacher_assistant_web/router.ex test/teacher_assistant_web/controllers/teacher_context_controller_test.exs
git commit -m "feat: TeacherContextController.select — persist class choice, context-aware redirect"
```

---

### Task 3: Shell — current-path hook, class switcher, tabs, bottom nav

**Files:**
- Modify: `lib/teacher_assistant_web/live_user_auth.ex` (attach `current_path` hook)
- Modify: `lib/teacher_assistant_web/components/layouts.ex` (switcher + tabs + bottom nav)
- Test: `test/teacher_assistant_web/live/teacher/shell_test.exs`

**Interfaces:**
- Consumes: `scope.current_context`, `scope.current_academic_year`, `scope.current_workspace` (Task 1); `Academics.list_teaching_contexts/2`; `@current_path`.
- Produces: shell DOM — `#class-switcher`, `#class-switcher-item-<id>`, `#per-class-nav`, `#mobile-nav`, `#nav-marks`, `#nav-coverage`.

- [ ] **Step 1: Write the failing shell test**

```elixir
# test/teacher_assistant_web/live/teacher/shell_test.exs
defmodule TeacherAssistantWeb.Teacher.ShellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
    %{ws: ws, year: year, ctx: ctx}
  end

  test "shell shows the class switcher with the active class and per-class tabs", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#class-switcher", "Maths")
    assert has_element?(view, "#class-switcher-item-#{ctx.id}")
    assert has_element?(view, "#per-class-nav")
    # per-class links point at the active context
    assert has_element?(view, "#per-class-nav a[href='/teacher/contexts/#{ctx.id}/marks']")
  end

  test "switcher items link through select-context carrying the current path", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(
             view,
             "#class-switcher-item-#{ctx.id} a[href*='/teacher/select-context/#{ctx.id}']"
           )
  end

  test "with no class, the switcher invites setup and hides per-class tabs", %{conn: conn, ws: ws} do
    # a workspace whose only class is removed → resolve returns nil
    for c <- Academics.list_teaching_contexts(ws, Academics.current_academic_year(ws)),
        do: Ash.destroy!(c, authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#class-switcher", "Set up a class") or
             has_element?(view, "#class-switcher", "Configurer")
    refute has_element?(view, "#per-class-nav")
  end
end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/teacher_assistant_web/live/teacher/shell_test.exs`
Expected: FAIL — no `#class-switcher`.

- [ ] **Step 3: Attach the `current_path` hook**

In `lib/teacher_assistant_web/live_user_auth.ex`, in `on_mount(:live_user_required, ...)`, attach a handle_params hook before returning `{:cont, socket}`:

```elixir
  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      socket =
        Phoenix.LiveView.attach_hook(socket, :current_path, :handle_params, fn _params, uri, socket ->
          {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
        end)

      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end
```

- [ ] **Step 4: Render the switcher + tabs in `layouts.ex`**

In `lib/teacher_assistant_web/components/layouts.ex`, compute the class list and active context inside `app/1` (extend the `assigns` block), then render them. Add to the `assign(...)` pipeline in `app/1`:

```elixir
    contexts =
      case current_scope do
        %{current_workspace: %{} = ws, current_academic_year: %{} = year} ->
          TeacherAssistant.Academics.list_teaching_contexts(ws, year)

        _ ->
          []
      end

    assigns =
      assigns
      |> assign(:current_user, current_user)
      |> assign(:workspace_name, workspace_name(current_scope))
      |> assign(:role_label, role_label(current_scope))
      |> assign(:workspace_type_label, workspace_type_label(current_scope))
      |> assign(:contexts, contexts)
      |> assign(:current_context, current_scope && current_scope.current_context)
      |> assign(:current_path, assigns[:current_path] || "/teacher")
```

Replace the existing `<nav :if={@current_user} id="main-nav" ...>` block with a class-independent tab row plus the switcher, then a per-class row. Use this markup:

```heex
        <nav
          :if={@current_user}
          id="main-nav"
          class="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-2 px-3 pb-2 sm:px-5"
          aria-label={gettext("Main navigation")}
        >
          <div :if={@contexts != []} id="class-switcher" class="dropdown">
            <div
              tabindex="0"
              role="button"
              class="inline-flex items-center gap-2 rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-sm font-semibold"
            >
              <.icon name="hero-users" class="size-4 text-primary" />
              <span>{context_label(@current_context)}</span>
              <.icon name="hero-chevron-down" class="size-3.5 text-base-content/50" />
            </div>
            <ul tabindex="0" class="dropdown-content menu z-50 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 shadow">
              <li :for={c <- @contexts} id={"class-switcher-item-#{c.id}"}>
                <.link href={~p"/teacher/select-context/#{c.id}?return_to=#{@current_path}"}>
                  {c.level} · {c.subject}
                </.link>
              </li>
            </ul>
          </div>

          <.link
            :if={@contexts == []}
            id="class-switcher"
            navigate={~p"/teacher/setup"}
            class="inline-flex items-center gap-2 rounded-md border border-dashed border-base-300 px-3 py-1.5 text-sm font-semibold text-base-content/70"
          >
            <.icon name="hero-plus" class="size-4" />
            {gettext("Set up a class")}
          </.link>

          <span class="mx-1 hidden h-5 w-px bg-base-300 sm:block"></span>

          <.tab_link id="nav-dashboard" href={~p"/teacher"} icon="hero-squares-2x2" current_path={@current_path}>
            {gettext("Dashboard")}
          </.tab_link>
          <.tab_link id="nav-log" href={~p"/teacher/log"} icon="hero-pencil-square" current_path={@current_path}>
            {gettext("Log")}
          </.tab_link>
          <.tab_link id="nav-import" href={~p"/teacher/import"} icon="hero-arrow-up-tray" current_path={@current_path}>
            {gettext("Import")}
          </.tab_link>

          <div id="locale-switch" class="ml-auto flex items-center gap-1">
            <.link navigate={~p"/locale/fr"} class="btn btn-ghost btn-xs ta-num">FR</.link>
            <span class="text-base-content/30">·</span>
            <.link navigate={~p"/locale/en"} class="btn btn-ghost btn-xs ta-num">EN</.link>
          </div>
        </nav>

        <nav
          :if={@current_user && @current_context}
          id="per-class-nav"
          class="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-1 border-t border-base-300 px-3 py-1.5 sm:px-5"
          aria-label={gettext("Class navigation")}
        >
          <.tab_link id="nav-roster" href={~p"/teacher/contexts/#{@current_context.id}/roster"} icon="hero-user-group" current_path={@current_path}>
            {gettext("Roster")}
          </.tab_link>
          <.tab_link id="nav-marks" href={~p"/teacher/contexts/#{@current_context.id}/marks"} icon="hero-pencil-square" current_path={@current_path}>
            {gettext("Marks")}
          </.tab_link>
          <.tab_link id="nav-results" href={~p"/teacher/contexts/#{@current_context.id}/marks/summary"} icon="hero-trophy" current_path={@current_path}>
            {gettext("Results")}
          </.tab_link>
        </nav>
```

> Coverage is intentionally **not** in `#per-class-nav`: today coverage is routed by *plan* id
> (`/teacher/plans/:id/coverage`), not context id, so a context→coverage link can't be built cleanly
> yet. The per-class row is Roster · Marks · Results for P0; Coverage joins it in P2 once a
> context-addressable coverage route exists. (Coverage stays reachable from the dashboard card.)

- [ ] **Step 5: Extend `tab_link/1` for active state + add `context_label/1`**

Update the private `tab_link/1` in `layouts.ex` to accept `current_path` and mark the active tab:

```elixir
  attr :id, :string, default: nil
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  slot :inner_block, required: true

  defp tab_link(assigns) do
    assigns = assign(assigns, :active, assigns.current_path == assigns.href)

    ~H"""
    <.link
      id={@id}
      navigate={@href}
      aria-current={@active && "page"}
      class={[
        "group inline-flex items-center gap-2 rounded-md px-3 py-1.5 text-sm font-semibold transition",
        @active && "bg-base-200 text-base-content",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-4 text-base-content/45 transition group-hover:text-primary" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp context_label(%{level: level, subject: subject}), do: "#{level} · #{subject}"
  defp context_label(_), do: Gettext.gettext(TeacherAssistantWeb.Gettext, "Select a class")
```

- [ ] **Step 6: Add the mobile bottom nav**

At the end of `app/1`'s markup, before `<.flash_group .../>`, add a bottom bar (mobile only) and reserve body padding. Change the `<main>` class to include `pb-20 sm:pb-6` when a user is present, and append:

```heex
    <nav
      :if={@current_user}
      id="mobile-nav"
      class="fixed inset-x-0 bottom-0 z-40 flex border-t border-base-300 bg-base-100/95 pb-[env(safe-area-inset-bottom)] backdrop-blur sm:hidden"
      aria-label={gettext("Bottom navigation")}
    >
      <.link navigate={~p"/teacher"} class="flex flex-1 flex-col items-center gap-0.5 py-2 text-[0.65rem] text-base-content/70">
        <.icon name="hero-squares-2x2" class="size-5" />{gettext("Dashboard")}
      </.link>
      <.link
        :if={@current_context}
        navigate={~p"/teacher/contexts/#{@current_context.id}/marks"}
        class="flex flex-1 flex-col items-center gap-0.5 py-2 text-[0.65rem] text-base-content/70"
      >
        <.icon name="hero-pencil-square" class="size-5" />{gettext("Marks")}
      </.link>
      <.link navigate={~p"/teacher/log"} class="flex flex-1 flex-col items-center gap-0.5 py-2 text-[0.65rem] text-base-content/70">
        <.icon name="hero-book-open" class="size-5" />{gettext("Log")}
      </.link>
      <.link navigate={~p"/teacher/import"} class="flex flex-1 flex-col items-center gap-0.5 py-2 text-[0.65rem] text-base-content/70">
        <.icon name="hero-arrow-up-tray" class="size-5" />{gettext("Import")}
      </.link>
    </nav>
```

Update the `<main ...>` line to:

```heex
      <main class={[
        "flex-1",
        if(@current_user, do: "mx-auto w-full max-w-6xl px-4 py-6 pb-20 sm:px-6 sm:pb-6", else: "w-full")
      ]}>
```

- [ ] **Step 7: Run the shell test + full suite**

Run:
```bash
mix test test/teacher_assistant_web/live/teacher/shell_test.exs
mix test
```
Expected: green, pristine. (Existing dashboard/nav tests still pass — the `#main-nav` id and Dashboard/Log links are preserved.)

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/live_user_auth.ex lib/teacher_assistant_web/components/layouts.ex test/teacher_assistant_web/live/teacher/shell_test.exs
git commit -m "feat: shell class switcher + per-class tabs + mobile bottom nav + active state"
```

---

### Task 4: Component kit + mention badge

**Files:**
- Modify: `lib/teacher_assistant_web/components/core_components.ex` (add 5 function components)
- Test: `test/teacher_assistant_web/components/kit_test.exs`

**Interfaces:**
- Produces (in `TeacherAssistantWeb.CoreComponents`):
  - `page_header/1` — `attr :eyebrow, :title`; slot `:actions`
  - `stat/1` — `attr :label, :value, :suffix, :tone`
  - `empty_state/1` — `attr :icon, :title, :message`; slot `:action`
  - `setup_gate/1` — `attr :icon, :eyebrow, :title, :message`; slot `:action`
  - `mention_badge/1` — `attr :mention` (`:excellent | :tres_bien | :bien | :assez_bien | :passable | nil`)

- [ ] **Step 1: Write the failing kit test**

```elixir
# test/teacher_assistant_web/components/kit_test.exs
defmodule TeacherAssistantWeb.KitTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistantWeb.CoreComponents

  test "page_header renders eyebrow, title, and actions" do
    html =
      render_component(&page_header/1, %{eyebrow: "Séquence 2", title: "Maths · 3e M2", actions: [%{inner_block: fn _, _ -> "ACT" end}]})

    assert html =~ "Séquence 2"
    assert html =~ "Maths · 3e M2"
    assert html =~ "ACT"
  end

  test "stat renders label, value, suffix" do
    html = render_component(&stat/1, %{label: "Moyenne", value: "12,4", suffix: "/20"})
    assert html =~ "Moyenne"
    assert html =~ "12,4"
    assert html =~ "/20"
    assert html =~ "ta-num"
  end

  test "empty_state renders icon title and action" do
    html = render_component(&empty_state/1, %{icon: "hero-inbox", title: "Nothing yet", action: [%{inner_block: fn _, _ -> "GO" end}]})
    assert html =~ "Nothing yet"
    assert html =~ "GO"
  end

  test "setup_gate renders message and action" do
    html = render_component(&setup_gate/1, %{icon: "hero-academic-cap", eyebrow: "Get started", title: "Welcome", message: "Set up your year", action: [%{inner_block: fn _, _ -> "START" end}]})
    assert html =~ "Welcome"
    assert html =~ "Set up your year"
    assert html =~ "START"
  end

  test "mention_badge shows word + a check for passing, x for failing, dash for nil" do
    assert render_component(&mention_badge/1, %{mention: :bien}) =~ "Bien"
    assert render_component(&mention_badge/1, %{mention: :bien}) =~ "hero-check-circle"
    assert render_component(&mention_badge/1, %{mention: nil}) =~ "Insuffisant"
    assert render_component(&mention_badge/1, %{mention: nil}) =~ "hero-x-circle"
  end
end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/teacher_assistant_web/components/kit_test.exs`
Expected: FAIL — `page_header/1 undefined`.

- [ ] **Step 3: Implement the components**

Append to `lib/teacher_assistant_web/components/core_components.ex` (inside the module, before the closing `end`):

```elixir
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <p class="ta-eyebrow">{@eyebrow}</p>
        <h1 class="mt-1 text-2xl font-bold sm:text-3xl">{@title}</h1>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :suffix, :string, default: nil
  attr :tone, :atom, default: :neutral

  def stat(assigns) do
    ~H"""
    <div class="ta-leaf">
      <p class="ta-eyebrow">{@label}</p>
      <p class={[
        "ta-num mt-1 text-2xl font-semibold leading-none",
        @tone == :primary && "text-primary",
        @tone == :behind && "text-warning"
      ]}>
        {@value}<span :if={@suffix} class="text-base font-normal text-base-content/55">{@suffix}</span>
      </p>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="ta-leaf flex flex-col items-start gap-3 text-sm">
      <span class="grid size-10 place-items-center rounded-xl bg-primary/10 text-primary">
        <.icon name={@icon} class="size-5" />
      </span>
      <div>
        <p class="font-semibold">{@title}</p>
        <p :if={@message} class="text-base-content/70">{@message}</p>
      </div>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  slot :action, required: true

  def setup_gate(assigns) do
    ~H"""
    <section class="mx-auto flex max-w-md flex-col items-center gap-4 py-10 text-center">
      <span class="grid size-14 place-items-center rounded-2xl bg-primary/10 text-primary">
        <.icon name={@icon} class="size-7" />
      </span>
      <p class="ta-eyebrow">{@eyebrow}</p>
      <h1 class="text-2xl font-bold sm:text-3xl">{@title}</h1>
      <p class="text-base-content/70">{@message}</p>
      <div>{render_slot(@action)}</div>
    </section>
    """
  end

  attr :mention, :atom, default: nil

  def mention_badge(assigns) do
    assigns = assign(assigns, :label, mention_label(assigns.mention))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 text-sm font-semibold",
      @mention == nil && "text-accent",
      @mention == :passable && "text-warning",
      @mention not in [nil, :passable] && "text-primary"
    ]}>
      <.icon name={if @mention, do: "hero-check-circle", else: "hero-x-circle"} class="size-4" />
      {@label}
    </span>
    """
  end

  defp mention_label(:excellent), do: gettext("Excellent")
  defp mention_label(:tres_bien), do: gettext("Très bien")
  defp mention_label(:bien), do: gettext("Bien")
  defp mention_label(:assez_bien), do: gettext("Assez bien")
  defp mention_label(:passable), do: gettext("Passable")
  defp mention_label(nil), do: gettext("Insuffisant")
```

- [ ] **Step 4: Run it — expect pass**

Run: `mix test test/teacher_assistant_web/components/kit_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/components/core_components.ex test/teacher_assistant_web/components/kit_test.exs
git commit -m "feat: shared component kit (page_header, stat, empty_state, setup_gate, mention_badge)"
```

---

### Task 5: Adopt the kit + accessibility fixes across pages

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex` (setup_gate + empty_state + page_header)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex` (aria-label on score inputs)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex` (page_header + mention_badge + ta-num)
- Modify: `lib/teacher_assistant_web/live/teacher/{setup,roster,coverage,log,fiche,import}_live.ex` (page_header only)
- Test: existing page tests must still pass; add one a11y assertion.

**Interfaces:**
- Consumes: the kit + `mention_badge` (Task 4).

- [ ] **Step 1: Write the failing a11y assertion**

Add to `test/teacher_assistant_web/live/teacher/marks_live_test.exs` (mirror its existing setup that builds ctx/class/assessment/student `s1`):

```elixir
  test "each score input has the student name as its accessible label", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#mark-input-#{s1.id}[aria-label='#{s1.full_name}']")
  end
```

- [ ] **Step 2: Run it — expect failure**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: FAIL — input has no `aria-label`.

- [ ] **Step 3: Add `aria-label` to the mark inputs**

In `lib/teacher_assistant_web/live/teacher/marks_live.ex`, on the score `<input id={"mark-input-#{s.id}"} ...>`, add `aria-label={s.full_name}` and `inputmode="decimal"`.

- [ ] **Step 4: Adopt the kit on the pages (behavior unchanged, DOM IDs preserved)**

Replace each page's hand-rolled header block with `<.page_header eyebrow={...} title={...}>` (keeping any right-aligned action inside `<:actions>`), e.g. in `dashboard_live.ex`:

```heex
<.page_header eyebrow={gettext("Programme coverage")} title={gettext("Teacher dashboard")}>
  <:actions>
    <span class="ta-num rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs font-semibold text-base-content/70">
      {@year.name}
    </span>
  </:actions>
</.page_header>
```

Replace the dashboard's no-year gate with `<.setup_gate>`:

```heex
<.setup_gate
  icon="hero-academic-cap"
  eyebrow={gettext("Get started")}
  title={gettext("Welcome")}
  message={gettext("Set up your academic year to get started.")}
>
  <:action>
    <.link navigate={~p"/teacher/setup"} class="btn btn-primary">{gettext("Start setup")}</.link>
  </:action>
</.setup_gate>
```

Replace the dashboard "No progression plan yet" block with `<.empty_state icon="hero-document-text" title={gettext("No progression plan yet.")}>` keeping the two links inside `<:action>`. Keep the outer `id="academic-year-setup-gate"` / `id="teacher-dashboard"` wrappers so existing tests match. For the other pages (`setup, roster, coverage, log, fiche, import, marks, marks_summary`), swap only the `<header><p class="ta-eyebrow">…</p><h1>…</h1></header>` block for `<.page_header>` — do not touch their forms, lists, or DOM IDs.

- [ ] **Step 5: Use `mention_badge` + `ta-num` in the summary**

In `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex`, in the per-student list, render the moyenne with `class="ta-num"` and replace any ad-hoc mention text with `<.mention_badge mention={@summary.per_student[s.id].mention} />`.

- [ ] **Step 6: Run the full suite**

Run: `mix test`
Expected: all green, pristine. Existing page tests pass unchanged (IDs preserved); the new a11y test passes.

- [ ] **Step 7: `mix precommit` + commit**

Run: `mix precommit`
Expected: fully green.

```bash
git add lib/teacher_assistant_web/live/teacher/ test/teacher_assistant_web/live/teacher/marks_live_test.exs
git commit -m "feat: adopt component kit across pages + mark-input aria-labels + summary mention badges"
```

---

## Self-Review

**Spec coverage** (against `2026-07-01-class-context-switcher-p0-design.md`):
- §2.1 state model + fallback → Task 1 (`resolve_current_context/3`, `scope_for/3`, session plumbing). ✅
- §2.2 selection route (owner-validate, context-aware redirect, open-redirect guard) → Task 2. ✅
- §2.3 shell (switcher, class-independent tabs, per-class tabs, mobile bottom nav, active state, no-class → setup) → Task 3. ✅
- §2.4 data flow → Tasks 1–3 compose it. ✅
- §3.1 component kit → Task 4. ✅
- §3.2 a11y (aria-label, mention word+icon, ta-num) → Task 4 (`mention_badge`) + Task 5. ✅
- §4 error handling (invalid/foreign/stale → fallback; non-local return_to; deleted class) → Task 1 tests + Task 2 tests. ✅
- §5 testing → each task carries its tests. ✅

**Placeholder scan:** none. The Task 3 Step 4 note resolves the one open UI question (Coverage tab routes by *plan* id, not context id) by **deciding**: omit the Coverage per-class tab in P0 (Roster/Marks/Results only), add it in P2 — and instructs removing the `#nav-coverage` line and its assertion. No "TBD" remains.

**Type consistency:** `scope_for/3` (default `context_id \\ nil`) is called as `scope_for(user, ws.id, ctx.id)` (Task 1/2) and `scope_for(user, workspace_id)` still works via the default. `resolve_current_context/3` returns `%TeachingContext{} | nil`, consumed as `scope.current_context` in the shell (Task 3) and controller pattern-match `%{current_context: %{id: ^context_id}}` (Task 2). `mention_badge/1`'s `:mention` values match `Academics.Marks.mention/1`'s atoms. `page_header`/`stat`/`empty_state`/`setup_gate` slot/attr names match their Task 5 call sites.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-01-class-context-switcher-p0.md`.
