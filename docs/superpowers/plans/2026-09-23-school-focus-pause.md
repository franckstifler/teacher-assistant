# School-Focus Pause (Increment 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the school the only reachable product surface: park every teacher-personal feature behind a compile-time flag, make `/school` the default landing, stop auto-creating personal workspaces, and hide the fees entry point, without deleting code or changing the schema.

**Architecture:** Router-level removal behind `Application.compile_env(:teacher_assistant, :teacher_personal_routes, false)` (same pattern as `:dev_routes`). The marks/roster/summary LiveViews under `/teacher/contexts/:id/*` and `TeacherContextController` stay because they are the school teacher's marks surface. `Workspaces.scope_for/3` with no workspace id resolves the user's first active school membership instead of creating a personal workspace; every `/teacher` redirect becomes `/school`, and `/school` sends a user with no school to `/schools/new`. Paused LiveViews, controllers and Ash resources stay compiled but unreachable; their web tests are tagged `:teacher_personal` and excluded.

**Tech Stack:** Elixir 1.20, Phoenix 1.8.14, LiveView 1.2.12, Ash 3.33.9, AshPhoenix 2.3.25, ExUnit, gettext.

**Spec:** `docs/audits/2026-09-23-school-focus/README.md` §2 and §6, and `docs/audits/2026-09-23-school-focus/C-feature-inventory-and-pause-plan.md` §4 (read both).

## Global Constraints

- Flag name and default, verbatim: `config :teacher_assistant, teacher_personal_routes: false` in `config/config.exs`; router reads it with `Application.compile_env(:teacher_assistant, :teacher_personal_routes, false)`. Never set it to `true` in `config/test.exs`.
- **No schema change, no migration.** `mix ash.codegen --check` must stay clean; if it reports drift, stop.
- Do not delete LiveViews, controllers, hooks or Ash resources. Only routes, redirects, nav markup, one orphaned controller action and the fees link change.
- Do NOT touch: `Teacher.MarksLive`, `Teacher.MarksSummaryLive`, `Teacher.RosterLive` (beyond the one fallback path each), `TeacherContextController` (beyond fallback paths), `on_mount :require_teaching_scope`, `Curriculum.fetch_assigned_teaching_context/2`, `Curriculum.list_units_for_scope/1`, the class switcher and `#per-class-nav` in `layouts.ex`.
- Keep `Organization.ensure_personal_workspace!/1`, `Workspace.:for_owner` and the `kind: :personal` branch of `Workspaces.scope_for/3` (explicit id): test fixtures (`register_and_log_in_user`, `workspace_fixture/1`) and 21 kept test files depend on them. Retiring `Workspace.kind` is the schema-pass increment, not this one.
- User-facing copy goes through `gettext/1`, French msgids; run `mix gettext.extract --merge` once at the end of Task 7 only if a new msgid was added (Task 5 adds none).
- Key elements keep or get DOM ids; tests assert with `has_element?/element` on ids, not raw HTML, except where the surrounding file already does otherwise.
- `mix precommit` does NOT gate on warnings (alias flag is misspelled). Gate every commit on `mix test` green AND `mix compile --warnings-as-errors` clean.
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## Review Focus

1. A signed-in user with zero school memberships must land on `/schools/new` from sign-in, from `/school`, from `/locale/:l` and from an invitation error, never on a 404 or in a redirect loop. (Pinned in Task 2 and Task 3.)
2. A session that still carries a personal `workspace_id` (existing browser sessions, and every test using `register_and_log_in_user`) must still resolve a scope and, on `/school`, be sent to `/schools/new` rather than crash. (Pinned in Task 3.)
3. `/teacher/select-context/:id?return_to=/teacher/log` (a now-paused path) must redirect to a live path, never to a route that no longer exists. (Pinned in Task 2.)
4. The locale switch from any school page must redirect to `/school`, not to a missing route. (Pinned in Task 2.)
5. Paused routes must be genuinely absent (raise `Phoenix.Router.NoRouteError`), while `/teacher/contexts/:id/marks|roster|marks/summary` and `/teacher/select-context/:id` still resolve. (Pinned in Task 4.)

---

### Task 1: Tag paused web tests and exclude them by default

**Files:**
- Modify: `test/test_helper.exs`
- Modify (add `@moduletag :teacher_personal` after `use TeacherAssistantWeb.ConnCase, async: true`):
  - `test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/setup_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/import_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/lesson_plan_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/log_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/coverage_live_test.exs`
  - `test/teacher_assistant_web/live/teacher/navigation_test.exs`
  - `test/teacher_assistant_web/live/teacher/shell_test.exs`
  - `test/teacher_assistant_web/controllers/fiche_print_controller_test.exs`
- Modify: `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs` (tag only the second test)

**Interfaces:**
- Produces: the ExUnit tag `:teacher_personal`, excluded by default, runnable with `mix test --include teacher_personal`.

Domain-level tests for progression plans, lesson plans, log entries, coverage, quotas and fiche parsing are **not** tagged: that code stays compiled and `CombinedCourse.:combine` still creates a progression plan, so those tests keep guarding it.

- [ ] **Step 1: Exclude the tag in the test helper**

Replace the contents of `test/test_helper.exs` with:

```elixir
# Teacher-personal surfaces are paused (see docs/audits/2026-09-23-school-focus/README.md §6).
# Their web tests stay in the repo and run with: mix test --include teacher_personal
ExUnit.start(exclude: [:teacher_personal])
Ecto.Adapters.SQL.Sandbox.mode(TeacherAssistant.Repo, :manual)
```

- [ ] **Step 2: Tag the ten paused web test modules**

In each of the ten files listed above, directly under the `use TeacherAssistantWeb.ConnCase, async: true` line, add:

```elixir
  @moduletag :teacher_personal
```

- [ ] **Step 3: Tag only the dashboard test in the combined switcher file**

In `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs`, directly above the line `test "dashboard shows exactly one coverage KPI for a combined course over two classes", %{`, add:

```elixir
  @tag :teacher_personal
```

Leave the first test (`"the class switcher shows one row for a combined course, not one per class"`) untagged; Task 2 rewrites its URL.

- [ ] **Step 4: Verify exclusion counts**

Run: `mix test 2>&1 | tail -3`
Expected: `674 tests, 0 failures, N excluded` where N is greater than 100 (the ten modules plus one test).

Run: `mix test --include teacher_personal 2>&1 | tail -3`
Expected: `674 tests, 0 failures` (nothing has been paused yet, so everything still passes when included).

- [ ] **Step 5: Commit**

```bash
git add test/test_helper.exs test/teacher_assistant_web
git commit -m "test: tag teacher-personal web tests and exclude them by default

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `/school` becomes the default landing everywhere

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/auth_controller.ex:6`
- Modify: `lib/teacher_assistant_web/live_user_auth.ex:78`
- Modify: `lib/teacher_assistant_web/controllers/locale_controller.ex:10`
- Modify: `lib/teacher_assistant_web/controllers/workspace_controller.ex:12,23`
- Modify: `lib/teacher_assistant_web/controllers/school_invitation_controller.ex:34,51`
- Modify: `lib/teacher_assistant_web/controllers/teacher_context_controller.ex:17,21-23`
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex:21,54,88`
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex:36`
- Modify: `lib/teacher_assistant_web/live/teacher/roster_live.ex:18`
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex:17`
- Modify: `lib/teacher_assistant_web/live/school/classes_live.ex:15`, `members_live.ex:18`, `my_timetable_live.ex:14`, `periods_live.ex:13`
- Test (update): `test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`, `test/teacher_assistant_web/live/teacher/roster_live_test.exs`, `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`, `test/teacher_assistant_web/live/school/dashboard_live_test.exs`, `test/teacher_assistant_web/live/teacher/school_scope_ux_test.exs`, `test/teacher_assistant_web/controllers/school_invitation_controller_test.exs`, `test/teacher_assistant_web/locale_test.exs`, `test/teacher_assistant_web/live/school_teaching_scope_test.exs`, `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs`, `test/teacher_assistant_web/components/workspace_switcher_test.exs`

**Interfaces:**
- Produces: the convention "any fallback goes to `/school`; only `School.DashboardLive` decides between the school shell and `/schools/new`". Task 3 relies on `School.DashboardLive` sending a scope with no school workspace to `/schools/new`.

- [ ] **Step 1: Update the tests that pin the redirects (they fail first)**

`test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`:
- line 28-29: change `?return_to=/teacher/log` to `?return_to=/teacher/contexts/#{ctx.id}/roster` and the assertion to `assert redirected_to(conn) == "/teacher/contexts/#{ctx.id}/roster"`.
- line 43-44 (unknown context): keep the request, change the assertion to `assert redirected_to(conn) == "/school"`.
- line 49-50 (evil return_to): change the assertion to `assert redirected_to(conn) == "/school"`.
- Add this test at the end of the module (Review Focus 3):

```elixir
  test "a paused personal return_to falls back to /school", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=/teacher/log")
    assert redirected_to(conn) == "/school"
  end
```

(If the module's setup names the context differently from `ctx`, use that name.)

`test/teacher_assistant_web/live/teacher/roster_live_test.exs:44`: `%{to: "/teacher/setup"}` → `%{to: "/school"}`.

`test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs:144`: `%{to: "/teacher/setup"}` → `%{to: "/school"}`.

`test/teacher_assistant_web/live/school/dashboard_live_test.exs:22`: replace `live(conn, ~p"/teacher/setup")` with `live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")` (still asserts redirect to `/school`; the guard is `:require_teaching_scope`).

`test/teacher_assistant_web/live/teacher/school_scope_ux_test.exs`: line 45 same replacement as above; delete the whole test `"fiche print shows the school name"` (the print route is paused and `fiche_print_controller_test` is tagged). Remove any alias that becomes unused.

`test/teacher_assistant_web/controllers/school_invitation_controller_test.exs:28`: `"/teacher"` → `"/school"`.

`test/teacher_assistant_web/live/school_teaching_scope_test.exs`:
- test at line 26: `live(conn, ~p"/teacher")` → `live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")`, keep the `/school` assertion, rename to `"a member without assignments is bounced from teaching pages to /school"`.
- test at line 30: `live(conn, ~p"/teacher")` → `live(conn, ~p"/teacher/contexts/#{tc.id}/roster")` where `tc` is the result of the `assign_teacher` call on line 32 (bind it: `{:ok, tc} = ...`), rename to `"an assigned teacher reaches the roster under school scope"`.
- delete the test `"personal scope still reaches /teacher"` (lines 37-40).

`test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs`, first test: `live(conn, ~p"/teacher")` → `live(conn, ~p"/teacher/contexts/#{tc_a.id}/roster")` and add `tc_a: tc_a` to the test's pattern (`%{conn: conn, course: course, tc_a: tc_a}`).

`test/teacher_assistant_web/components/workspace_switcher_test.exs`, replace the test body with:

```elixir
  test "the switcher lists member schools only", %{conn: conn, actor: user, workspace: personal} do
    {:ok, school} = Organization.create_school(user, %{name: "École Deux"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#workspace-switcher")
    assert has_element?(view, "#workspace-switcher-item-#{school.id}", "École Deux")
  end
```

(Task 3 adds the `refute` on the personal workspace item once it stops being listed. The `personal` binding is used there.)

`test/teacher_assistant_web/locale_test.exs`, replace the file with:

```elixir
defmodule TeacherAssistantWeb.LocaleTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Locale"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn}
  end

  test "defaults to french and switches to english", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Tableau de bord")

    conn = get(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/school"
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Dashboard")
  end
end
```

- [ ] **Step 2: Run the updated tests to see them fail**

Run: `mix test test/teacher_assistant_web/controllers/teacher_context_controller_test.exs test/teacher_assistant_web/locale_test.exs test/teacher_assistant_web/live/teacher/roster_live_test.exs`
Expected: failures on the `/school` assertions (code still redirects to `/teacher` or `/teacher/setup`).

- [ ] **Step 3: Change the redirects**

Make each edit exactly:

`auth_controller.ex:6`: `get_session(conn, :return_to) || ~p"/teacher"` → `get_session(conn, :return_to) || ~p"/school"`.

`live_user_auth.ex:78`: `redirect(socket, to: ~p"/teacher")` → `redirect(socket, to: ~p"/school")`.

`locale_controller.ex:10`: `redirect(to: ~p"/teacher")` → `redirect(to: ~p"/school")`.

`workspace_controller.ex:12`: `to = if scope.current_workspace_type == :school, do: ~p"/school", else: ~p"/teacher"` → `to = ~p"/school"` (a personal workspace can no longer be selected from the UI; `/school` routes a non-school scope onward). Line 23: `~p"/teacher"` → `~p"/school"`.

`school_invitation_controller.ex:34` and `:51`: `~p"/teacher"` → `~p"/school"`.

`teacher_context_controller.ex`: line 17 `redirect(conn, to: ~p"/teacher/setup")` → `redirect(conn, to: ~p"/school")`; replace the two `safe_return_to` clauses and their comment with:

```elixir
  # only local teaching/school paths are allowed; anything else defaults to the school dashboard
  defp safe_return_to("/teacher/contexts/" <> _ = path), do: path
  defp safe_return_to("/school" <> _ = path), do: path
  defp safe_return_to(_), do: "/school"
```

`marks_live.ex` lines 21, 54, 88; `marks_summary_live.ex:36`; `roster_live.ex:18`: `~p"/teacher/setup"` → `~p"/school"`. Update the comment on `marks_live.ex:49-50` to read `# true => context owned but has no class group (go to the roster); anything else => not found / not owned`.

`school/dashboard_live.ex:17`: `push_navigate(socket, to: ~p"/teacher")` → `push_navigate(socket, to: ~p"/schools/new")`.

`school/classes_live.ex:15`, `members_live.ex:18`, `my_timetable_live.ex:14`, `periods_live.ex:13`: `~p"/teacher"` → `~p"/school"`.

- [ ] **Step 4: Run the suite**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -5`
Expected: 0 failures (the `/teacher` routes still exist at this point; the tests simply stop using them).

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat: /school is the default landing; teaching fallbacks no longer point at paused routes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Stop auto-creating personal workspaces

**Files:**
- Modify: `lib/teacher_assistant/accounts/workspaces.ex:6-13`
- Modify: `lib/teacher_assistant/organization.ex:59-73` (`list_workspaces_for/1`)
- Modify: `lib/teacher_assistant/accounts.ex:40-41` (delete `ensure_personal_workspace!/1`, no callers)
- Test: `test/teacher_assistant/accounts/workspaces_test.exs`, `test/teacher_assistant/academics/workspace_test.exs` (only if it asserts `list_workspaces_for` includes the personal workspace), `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `School.DashboardLive` non-school fallback → `/schools/new` (Task 2).
- Produces: `Workspaces.scope_for(user, nil, ctx)` returns `{:ok, scope}` for the first active school membership or `{:error, :no_workspace}`; `Organization.list_workspaces_for/1` returns school workspaces only; `Workspaces.scope_for(user, explicit_id, ctx)` is unchanged (still resolves `kind: :personal` by id for fixtures).

- [ ] **Step 1: Write the failing domain tests**

Append to `test/teacher_assistant/accounts/workspaces_test.exs`, inside the module but outside the existing `describe`:

```elixir
  describe "default workspace (school-only product)" do
    test "scope_for with nil workspace resolves the first active school membership", %{user: user} do
      {:ok, school} = Organization.create_school(user, %{name: "École Défaut"})
      assert {:ok, scope} = Workspaces.scope_for(user, nil)
      assert scope.current_workspace.id == school.id
      assert scope.current_workspace_type == :school
    end

    test "scope_for with nil workspace and no membership returns an error" do
      user = TeacherFixtures.user_fixture()
      assert {:error, :no_workspace} = Workspaces.scope_for(user, nil)
    end

    test "list_workspaces_for returns schools only", %{user: user} do
      {:ok, school} = Organization.create_school(user, %{name: "École Liste"})
      ids = user |> Organization.list_workspaces_for() |> Enum.map(& &1.id)
      assert ids == [school.id]
    end
  end
```

Note the existing `setup` in that file already creates a personal workspace for `user` via `ensure_personal_workspace!`; the third test proves it is no longer listed.

In `test/teacher_assistant_web/components/workspace_switcher_test.exs`, add as the last line of the test body (before `end`):

```elixir
    refute has_element?(view, "#workspace-switcher-item-#{personal.id}")
```

Append to `test/teacher_assistant_web/live/school/dashboard_live_test.exs` (Review Focus 1 and 2):

```elixir
  test "a user with no school is sent to /schools/new from /school", %{conn: conn} do
    # session still carries the personal workspace id from register_and_log_in_user
    assert {:error, {:live_redirect, %{to: "/schools/new"}}} = live(conn, ~p"/school")
  end

  test "a user with no workspace in session and no school is sent to /schools/new" do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
    assert {:error, {:live_redirect, %{to: "/schools/new"}}} = live(conn, ~p"/school")
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/accounts/workspaces_test.exs test/teacher_assistant_web/live/school/dashboard_live_test.exs test/teacher_assistant_web/components/workspace_switcher_test.exs`
Expected: `list_workspaces_for` test fails (personal workspace listed first); `scope_for nil` tests fail (a personal scope is returned); the switcher `refute` fails.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/accounts/workspaces.ex`: replace lines 6-13 with

```elixir
  def scope_for(user, workspace_id, context_id \\ nil)

  # No workspace chosen yet: default to the first school the user belongs to.
  # Personal workspaces are paused (docs/audits/2026-09-23-school-focus/README.md §6).
  def scope_for(user, nil, context_id) do
    case Organization.list_workspaces_for(user) do
      [ws | _] -> scope_for(user, ws.id, context_id)
      [] -> {:error, :no_workspace}
    end
  end
```

(`ensure_personal_workspace!/1` on `Workspaces` is removed; keep `Organization.ensure_personal_workspace!/1`, fixtures use it.)

`lib/teacher_assistant/organization.ex`: replace `list_workspaces_for/1` and its doc with

```elixir
  @doc """
  Every school the user is an active member of, in membership order.
  Personal workspaces are paused and never listed.
  """
  def list_workspaces_for(%User{} = user) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
    |> Ash.read!()
    |> Enum.map(& &1.workspace)
  end
```

`lib/teacher_assistant/accounts.ex`: delete the two-line `def ensure_personal_workspace!(...)` function at lines 40-41.

Run `grep -rn "Workspaces.ensure_personal_workspace!\|Accounts.ensure_personal_workspace!" lib test` and fix any caller by pointing it at `Organization.ensure_personal_workspace!/1` (expected: none).

- [ ] **Step 4: Run the suite**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -3`
Expected: 0 failures. If `test/teacher_assistant/academics/workspace_test.exs` asserts the personal workspace is listed by `list_workspaces_for`, change that assertion to expect schools only.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat: default scope is the first school membership; personal workspaces no longer auto-created

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Compile-time flag and router split

**Files:**
- Modify: `config/config.exs` (add one config line after `config :ash_oban, pro?: false`)
- Modify: `lib/teacher_assistant_web/router.ex:36-41` (public scope) and `:84-100` (`live_session :teacher_workspace`)
- Modify: `lib/teacher_assistant_web/controllers/workspace_controller.ex:27-38` (delete `create/2`)
- Create: `test/teacher_assistant_web/router_pause_test.exs`

**Interfaces:**
- Produces: routes `/teacher`, `/teacher/setup`, `/teacher/import`, `/teacher/log`, `/teacher/plans/:id`, `/teacher/plans/:id/coverage`, `/teacher/entries/:entry_id/fiche`, `/teacher/entries/:entry_id/fiche/print` and `POST /workspaces` exist only when `teacher_personal_routes: true`. Routes `/teacher/contexts/:id/roster`, `/teacher/contexts/:id/marks`, `/teacher/contexts/:id/marks/summary`, `/teacher/select-context/:id` always exist.

- [ ] **Step 1: Write the failing router test**

Create `test/teacher_assistant_web/router_pause_test.exs`:

```elixir
defmodule TeacherAssistantWeb.RouterPauseTest do
  use TeacherAssistantWeb.ConnCase, async: true

  @paused ~w(/teacher /teacher/setup /teacher/import /teacher/log)

  setup :register_and_log_in_user

  test "teacher-personal routes are absent", %{conn: conn} do
    for path <- @paused do
      assert_raise Phoenix.Router.NoRouteError, fn -> get(conn, path) end
    end

    id = Ecto.UUID.generate()

    for path <- [
          "/teacher/plans/#{id}",
          "/teacher/plans/#{id}/coverage",
          "/teacher/entries/#{id}/fiche",
          "/teacher/entries/#{id}/fiche/print"
        ] do
      assert_raise Phoenix.Router.NoRouteError, fn -> get(conn, path) end
    end

    assert_raise Phoenix.Router.NoRouteError, fn ->
      post(conn, "/workspaces", %{"school" => %{"name" => "X"}})
    end
  end

  test "school teaching routes still resolve", %{conn: conn} do
    id = Ecto.UUID.generate()

    for path <- [
          "/teacher/contexts/#{id}/roster",
          "/teacher/contexts/#{id}/marks",
          "/teacher/contexts/#{id}/marks/summary",
          "/teacher/select-context/#{id}"
        ] do
      # any response other than NoRouteError proves the route exists
      conn = get(conn, path)
      assert conn.status in [200, 302]
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/teacher_assistant_web/router_pause_test.exs`
Expected: FAIL on the first test (`/teacher` currently renders, no `NoRouteError` raised).

- [ ] **Step 3: Add the flag to config**

In `config/config.exs`, after the line `config :ash_oban, pro?: false`, add:

```elixir
# Teacher-personal surfaces are paused; see docs/audits/2026-09-23-school-focus/README.md §6.
# Flip to `true` in a config file to re-enable the /teacher/* personal routes.
config :teacher_assistant, teacher_personal_routes: false
```

- [ ] **Step 4: Split the router**

In `lib/teacher_assistant_web/router.ex`, replace the two lines

```elixir
    post "/workspaces", WorkspaceController, :create
    get "/teacher/select-context/:id", TeacherContextController, :select
    get "/teacher/entries/:entry_id/fiche/print", FichePrintController, :show
```

with

```elixir
    get "/teacher/select-context/:id", TeacherContextController, :select

    if Application.compile_env(:teacher_assistant, :teacher_personal_routes, false) do
      post "/workspaces", WorkspaceController, :create
      get "/teacher/entries/:entry_id/fiche/print", FichePrintController, :show
    end
```

Then replace the whole `ash_authentication_live_session :teacher_workspace, ... do ... end` block with:

```elixir
    # School teachers' marks surface. Every teacher page that is NOT about an
    # assigned class (dashboard, personal setup, fiche, import, log, coverage,
    # lesson plans) is teacher-personal and paused behind the compile flag.
    ash_authentication_live_session :teaching,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [
        {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
        {TeacherAssistantWeb.LiveUserAuth, :require_teaching_scope}
      ] do
      live "/teacher/contexts/:id/roster", Teacher.RosterLive, :index
      live "/teacher/contexts/:id/marks", Teacher.MarksLive, :index
      live "/teacher/contexts/:id/marks/summary", Teacher.MarksSummaryLive, :index
    end

    if Application.compile_env(:teacher_assistant, :teacher_personal_routes, false) do
      ash_authentication_live_session :teacher_workspace,
        session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
        on_mount: [
          {TeacherAssistantWeb.LiveUserAuth, :live_user_required},
          {TeacherAssistantWeb.LiveUserAuth, :require_teaching_scope}
        ] do
        live "/teacher", Teacher.DashboardLive, :index
        live "/teacher/setup", Teacher.SetupLive, :index
        live "/teacher/import", Teacher.ImportLive, :new
        live "/teacher/log", Teacher.LogLive, :index
        live "/teacher/plans/:id", Teacher.FicheLive, :show
        live "/teacher/plans/:id/coverage", Teacher.CoverageLive, :show
        live "/teacher/entries/:entry_id/fiche", Teacher.LessonPlanLive, :edit
      end
    end
```

- [ ] **Step 5: Delete the orphaned workspace create action**

In `lib/teacher_assistant_web/controllers/workspace_controller.ex`, delete the whole `def create(conn, %{"school" => %{"name" => name}}) do ... end` function (lines 27-38). The route was never linked from any template; `/schools/new` is the creation path. If the module now has an unused alias or import, remove it so `mix compile --warnings-as-errors` stays clean.

- [ ] **Step 6: Run the router test and the full suite**

Run: `mix test test/teacher_assistant_web/router_pause_test.exs`
Expected: 2 tests, 0 failures.

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -3`
Expected: compile clean, 0 failures (Tasks 2 and 3 already moved every kept test off the paused routes; the paused modules' own tests are excluded by Task 1).

- [ ] **Step 7: Commit**

```bash
git add config/config.exs lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/controllers/workspace_controller.ex test/teacher_assistant_web/router_pause_test.exs
git commit -m "feat: pause teacher-personal routes behind teacher_personal_routes flag

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Remove the personal navigation from the shell

**Files:**
- Modify: `lib/teacher_assistant_web/components/layouts.ex:77` (`current_path` default), `:190-199` ("Set up a class" callout), `:201-232` (`#main-nav`)
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

**Interfaces:**
- Consumes: nothing new. `#school-nav`, `#class-switcher`, `#per-class-nav` and the workspace switcher are untouched.

- [ ] **Step 1: Write the failing test**

Append to `test/teacher_assistant_web/live/school/dashboard_live_test.exs`:

```elixir
  test "the shell shows no personal navigation", %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Nav"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-nav")
    refute has_element?(view, "#main-nav")
    refute has_element?(view, "a[href='/teacher/setup']")
    refute has_element?(view, "a[href='/teacher']")
  end
```

- [ ] **Step 2: Run it**

Run: `mix test test/teacher_assistant_web/live/school/dashboard_live_test.exs`
Expected: PASS already for `#main-nav` (it is `:if={!@in_school?}`) but this test still documents the contract; proceed to remove the markup so the paused links cannot appear for a scope with no school either.

- [ ] **Step 3: Remove the markup**

In `lib/teacher_assistant_web/components/layouts.ex`:
- Delete the whole `<.link :if={@units == [] && !@in_school?} id="class-switcher" navigate={~p"/teacher/setup"} ...>...</.link>` block (the "Set up a class" callout, lines ~190-199).
- Delete the whole `<nav :if={!@in_school?} id="main-nav" ...> ... </nav>` block (Dashboard `/teacher`, Log `/teacher/log`, Import `/teacher/import`, lines ~201-232).
- Change `|> assign(:current_path, assigns[:current_path] || "/teacher")` to `|> assign(:current_path, assigns[:current_path])`.
- Compile: if `gettext("Log")` / `gettext("Import")` / `gettext("Set up a class")` were the only uses of those msgids, nothing else changes (stale msgids in `.po` files are harmless; do not run `gettext.extract` here).

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -3`
Expected: 0 failures. Then run `grep -n '~p"/teacher' lib/teacher_assistant_web/components/layouts.ex` and confirm every remaining hit is under `/teacher/contexts/` or `/teacher/select-context/`.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/components/layouts.ex test/teacher_assistant_web/live/school/dashboard_live_test.exs
git commit -m "feat: drop personal navigation and setup callout from the shell

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Hide the fees entry point

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex:33-34` (assign) and `:98-106` (link)
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs`

**Interfaces:**
- Produces: `School.FeesLive` and `/school/classes/:id/fees` stay routed and tested (`fees_live_test` navigates by URL); no template links to them.

- [ ] **Step 1: Write the failing test**

Append to `test/teacher_assistant_web/live/school/class_live_test.exs`, inside a describe/setup that mounts the class page as the head (reuse the file's existing setup that yields `conn` and a class group; name below assumes `cg`):

```elixir
  test "the class page has no fees link (fees deferred)", %{conn: conn, cg: cg} do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#go-to-fees")
  end
```

- [ ] **Step 2: Run it**

Run: `mix test test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: the new test FAILS (the head sees `#go-to-fees`).

- [ ] **Step 3: Remove the link and its assign**

In `class_live.ex` delete the two lines

```elixir
         fees_link?:
           Permissions.fees_manager?(scope) or Permissions.admin_or_form_master?(scope, cg),
```

and the whole `<.link :if={@fees_link?} navigate={~p"/school/classes/#{@cg.id}/fees"} id="go-to-fees" ...> ... </.link>` block. Add above the discipline link a HEEx comment:

```heex
          <%!-- Fees link removed: bursar features are deferred (docs/audits/2026-09-23-school-focus/README.md §2). Route /school/classes/:id/fees stays. --%>
```

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test test/teacher_assistant_web/live/school/class_live_test.exs test/teacher_assistant_web/live/school/fees_live_test.exs`
Expected: 0 failures (fees LiveView still works by URL).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/class_live.ex test/teacher_assistant_web/live/school/class_live_test.exs
git commit -m "feat: hide the class-page fees link (bursar features deferred)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Mark paused modules and update the product docs

**Files:**
- Modify (add a paused note at the top of `@moduledoc`, creating one if absent): `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`, `setup_live.ex`, `import_live.ex`, `log_live.ex`, `fiche_live.ex`, `coverage_live.ex`, `lesson_plan_live.ex`, `lib/teacher_assistant_web/controllers/fiche_print_controller.ex`
- Modify: `docs/PRODUCT.md:21-24` (principle), `docs/PRODUCT.md` "Phased roadmap" intro, `docs/DESIGN.md:140-148` (Personal Teacher Workspace)
- Modify: `docs/audits/2026-09-23-school-focus/README.md` §6 heading

**Interfaces:** none.

- [ ] **Step 1: Add the paused note to the eight modules**

At the top of each listed module's `@moduledoc` (or add `@moduledoc """ ... """` right after `use TeacherAssistantWeb, :live_view` / `:controller` if there is none), insert as the first paragraph:

```
PAUSED (teacher-personal surface). Not routed unless
`config :teacher_assistant, teacher_personal_routes: true`.
See docs/audits/2026-09-23-school-focus/README.md §6.

```

- [ ] **Step 2: Update PRODUCT.md**

Replace the `- **Teacher-first, then school.** ...` principle bullet (lines 21-24) with:

```markdown
- **School-first (since 2026-09-23).** The school workspace is the product: identity, staff and
  roles, classes, subjects, timetables, roll call, marks and report cards. The independent-teacher
  workspace (personal progression plans, fiche import, lesson plans, teaching log, coverage) is
  **paused**, kept in the codebase behind `teacher_personal_routes: false`. Teacher↔school stays
  many-to-many; a teacher works inside the schools that invited them.
```

Under `## Phased roadmap`, before `### Phase 1`, add:

```markdown
> **Status 2026-09-23:** Phase 1 (independent teacher) is paused, not removed. Phase 2 (school)
> is the active track. Fees and fee-based access are deferred inside Phase 2. Audit and roadmap:
> [`docs/audits/2026-09-23-school-focus/`](../docs/audits/2026-09-23-school-focus/README.md).
```

(Fix the relative link so it resolves from `docs/PRODUCT.md`: `audits/2026-09-23-school-focus/README.md`.)

- [ ] **Step 3: Update DESIGN.md**

Replace the `### Personal Teacher Workspace` section (lines 140-148) with:

```markdown
### Personal Teacher Workspace (paused)

Paused on 2026-09-23; the shell no longer renders the personal navigation and `/teacher/*`
personal routes are compiled out (`teacher_personal_routes: false`). The only `/teacher/*`
pages that remain are the per-class roster, marks and results of a school assignment, reached
through the class switcher. If the personal workspace returns, it should be modelled as a
school-of-one, not a second workspace shape.
```

- [ ] **Step 4: Mark the audit README pause plan as done**

In `docs/audits/2026-09-23-school-focus/README.md`, change the heading `## 6. Pause plan (proposal, not yet executed)` to `## 6. Pause plan (executed 2026-09-23, plan: docs/superpowers/plans/2026-09-23-school-focus-pause.md)`.

- [ ] **Step 5: Full verification**

Run, in order:

```bash
mix compile --warnings-as-errors
mix ash.codegen --check
mix test
mix test --include teacher_personal 2>&1 | tail -3
mix precommit 2>&1 | tail -3
```

Expected: compile clean; codegen reports no changes; `mix test` 0 failures with the excluded count; the included run may show failures **only** in tagged files hitting now-absent routes (that is expected and documents the pause; note the count in the commit message); `mix precommit` green. `precommit`'s format step may rewrite files: include them in the commit.

- [ ] **Step 6: Commit**

```bash
git add lib docs
git commit -m "docs: mark teacher-personal surfaces paused; school-first positioning

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Final: whole-branch review

- Diff `main..feat/school-focus-pause` and check every item of the Global Constraints list.
- Confirm `grep -rn '~p"/teacher"' lib` returns nothing and `grep -rn '/teacher/setup' lib` returns only the paused modules.
- Confirm no Ash resource, migration or snapshot changed: `git diff main --stat -- lib/teacher_assistant priv` shows only `workspaces.ex`, `organization.ex`, `accounts.ex`.
- Open a PR against `main` titled "School focus: pause teacher-personal surfaces, hide fees" whose body links the audit README and this plan and lists the excluded test count, ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
