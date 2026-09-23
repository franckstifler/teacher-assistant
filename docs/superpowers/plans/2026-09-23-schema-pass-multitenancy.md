# Schema Pass & Multitenancy (Increment 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the school the tenant at the data layer: every tenant-owned row carries an indexed `workspace_id` foreign key, Ash attribute multitenancy scopes every read and write, and personal workspaces plus the paused teacher-personal code are gone.

**Architecture:** Two phases on one branch with a review gate between them. Phase 1 (Tasks 1–7) deletes the paused surfaces, moves every test onto school fixtures, retires `Workspace.kind`, adds `belongs_to :workspace` everywhere, indexes, constraints, non-null pivots and enums, all through generated migrations (dev-only databases are reset). Phase 2 (Tasks 8–15) turns on `multitenancy do strategy :attribute; attribute :workspace_id end` domain by domain; each domain function sets the tenant from the workspace or child struct it already receives, so LiveViews and controllers do not change yet. `Scope.get_tenant/1` is wired for the authorization increment.

**Tech Stack:** Elixir 1.20, Phoenix 1.8.14, LiveView 1.2.12, Ash 3.33.9, AshPostgres 2.13.1, AshPhoenix 2.3.25, Postgres, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-23-schema-pass-multitenancy-design.md` (read it alongside this plan). One deviation recorded here: `Enrollment.add_student/2` is kept (school code and ~30 tests use it as the simple enroll path); only the personal roster write events are deleted.

## Global Constraints

- **Migrations are generated only.** Every schema task runs `mix ash.codegen --dev` after its resource edits, then `mix ash.reset` (dev-only data) and `mix test`. Task 7 squashes the dev migrations with `mix ash.codegen schema_pass`. Never hand-edit a migration; `mix ash.codegen --check` must be clean at every commit.
- Multitenancy block, verbatim, on every tenant-owned resource: `multitenancy do\n  strategy :attribute\n  attribute :workspace_id\nend`. `SchoolMembership` and `SchoolInvitation` add `global? true`. `Workspace`, `SchoolProfile`, `User`, `Token` never get the block.
- Tenant values are workspace ids (`workspace.id`, a UUID string). Set with `Ash.Query.set_tenant/2`, `Ash.Changeset.set_tenant/2`, or `tenant:` on code-interface calls. Inside a resource action hook use `changeset.tenant` / `query.tenant`; inside `Workspace.:create_school`'s after_action use `workspace.id`.
- `accept [:workspace_id]` (and `:workspace_id` in `defaults create: [...]`) is removed from every create when its resource becomes multitenant; Ash sets the attribute from the tenant.
- Never bare `:atom` attributes; `Ash.Type.Enum` modules with `label/1`.
- `mix precommit` does NOT gate on warnings; gate every commit on `mix compile --warnings-as-errors` clean AND `mix test` 0 failures (no excluded tags remain after Task 1).
- Tests assert on DOM ids / redirect tuples / returned structs, never raw HTML. Fixtures come from `TeacherAssistant.TeacherFixtures` and `TeacherAssistantWeb.ConnCase` (Task 2 defines the new helpers every later task uses).
- Commit after every task; trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Deleted code is deleted (git history keeps it); no `@deprecated` shims, no commented-out blocks.

## Review Focus

1. A create of a tenant-owned row without a tenant must raise `Ash.Error.Invalid` ("requires a tenant"), never silently write a row with `workspace_id` nil. (Pinned in Task 8 and re-asserted per domain in Tasks 9–15.)
2. A read under tenant A must never return tenant B's rows for any multitenant resource, including through `Ash.get` by a known foreign id inside bare-id domain functions (`Fees.record_payment`, `Discipline.add_sanction`, `Attendance.justify_day`). (Pinned in Task 14 with a cross-tenant bare-id test.)
3. `create_school` must seed profile, head membership, subject catalog and periods under the NEW workspace's tenant inside the same transaction, and an invalid profile must still roll everything back. (Pinned in Task 8.)
4. A second active academic year for the same workspace must be rejected at the database, and `activate` must still succeed because it deactivates siblings first. (Pinned in Task 6.)
5. An invitation accept by token must work before any tenant is known, and listing a user's schools must work with no tenant. (Pinned in Task 15.)

---

# Phase 1 — Schema

### Task 1: Delete the teacher-personal surfaces

**Files:**
- Delete: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`, `setup_live.ex`, `import_live.ex`, `log_live.ex`, `fiche_live.ex`, `coverage_live.ex`, `lesson_plan_live.ex`; `lib/teacher_assistant_web/controllers/fiche_print_controller.ex`, `fiche_print_html.ex`, `fiche_print_html/show.html.heex`; `assets/js/hooks/module_layout.js`; `lib/teacher_assistant/academics/quota.ex`, `fiche_parser.ex`, `fiche_extractor.ex`
- Delete tests: `test/teacher_assistant_web/live/teacher/{dashboard,setup,import,log,fiche,coverage,lesson_plan}_live_test.exs`, `navigation_test.exs`, `shell_test.exs`, `test/teacher_assistant_web/controllers/fiche_print_controller_test.exs`, `test/teacher_assistant/academics/{quota,fiche_parser,fiche_extractor}_test.exs`
- Modify: `lib/teacher_assistant_web/router.ex` (both `if Application.compile_env(:teacher_assistant, :teacher_personal_routes, false)` blocks), `config/config.exs:13-15`, `assets/js/app.js:27,50`, `test/test_helper.exs`, `test/teacher_assistant_web/router_pause_test.exs`, `test/teacher_assistant_web/live/onboarding/setup_gate_test.exs` (the one `@tag :teacher_personal` test), `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs` (the `@tag :teacher_personal` test), `lib/teacher_assistant_web/live/teacher/roster_live.ex` (personal write events), `lib/teacher_assistant/curriculum.ex` (`Quota`/`FicheParser` references, if any)

**Interfaces:**
- Produces: no `:teacher_personal` tag anywhere; `mix test` runs everything; `/teacher/contexts/:id/roster|marks|marks/summary` and `/teacher/select-context/:id` are the only `/teacher` routes.

- [ ] **Step 1: Write the failing route test**

Replace `test/teacher_assistant_web/router_pause_test.exs` with:

```elixir
defmodule TeacherAssistantWeb.RouterPauseTest do
  use TeacherAssistantWeb.ConnCase, async: true

  test "the personal teacher routes no longer exist, even with a flag" do
    refute Application.get_env(:teacher_assistant, :teacher_personal_routes)

    routes =
      TeacherAssistantWeb.Router.__routes__()
      |> Enum.map(& &1.path)
      |> Enum.filter(&String.starts_with?(&1, "/teacher"))
      |> Enum.sort()

    assert routes == [
             "/teacher/contexts/:id/marks",
             "/teacher/contexts/:id/marks/summary",
             "/teacher/contexts/:id/roster",
             "/teacher/select-context/:id"
           ]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/teacher_assistant_web/router_pause_test.exs`
Expected: PASS already — the four routes are what survives today and the flag is off. This test is the regression guard for the end state; the deletions below are the deliverable.

- [ ] **Step 3: Delete the surfaces**

```bash
git rm -q lib/teacher_assistant_web/live/teacher/{dashboard,setup,import,log,fiche,coverage,lesson_plan}_live.ex \
  lib/teacher_assistant_web/controllers/fiche_print_controller.ex \
  lib/teacher_assistant_web/controllers/fiche_print_html.ex \
  lib/teacher_assistant_web/controllers/fiche_print_html/show.html.heex \
  assets/js/hooks/module_layout.js \
  lib/teacher_assistant/academics/quota.ex \
  lib/teacher_assistant/academics/fiche_parser.ex \
  lib/teacher_assistant/academics/fiche_extractor.ex \
  test/teacher_assistant_web/live/teacher/{dashboard,setup,import,log,fiche,coverage,lesson_plan}_live_test.exs \
  test/teacher_assistant_web/live/teacher/navigation_test.exs \
  test/teacher_assistant_web/live/teacher/shell_test.exs \
  test/teacher_assistant_web/controllers/fiche_print_controller_test.exs \
  test/teacher_assistant/academics/{quota,fiche_parser,fiche_extractor}_test.exs
```

In `lib/teacher_assistant_web/router.ex` delete both `if Application.compile_env(:teacher_assistant, :teacher_personal_routes, false) do ... end` blocks entirely (the one holding `get "/teacher/entries/:entry_id/fiche/print"` and the one holding the `:teacher_workspace` live_session). Keep the `:teaching` live_session and `get "/teacher/select-context/:id"`.

In `config/config.exs` delete the three lines (two comment lines + `config :teacher_assistant, teacher_personal_routes: false`).

In `assets/js/app.js` delete `import ModuleLayout from "./hooks/module_layout.js"` and change `hooks: {...colocatedHooks, ModuleLayout},` to `hooks: {...colocatedHooks},`.

`test/test_helper.exs` becomes:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TeacherAssistant.Repo, :manual)
```

Delete the `@tag :teacher_personal` test in `test/teacher_assistant_web/live/onboarding/setup_gate_test.exs` and the `@tag :teacher_personal` test ("dashboard shows exactly one coverage KPI …") in `test/teacher_assistant_web/live/teacher/context_switcher_combined_test.exs`.

In `lib/teacher_assistant_web/live/teacher/roster_live.ex` delete the personal write path: the `handle_event` clauses for `"create_class"`, `"add_student"`, `"delete_student"`, `"undo_delete"`, the guard clause that rejects them under school scope, the `phx-submit="add_student"` form and any "add student / create class" markup and helper functions they alone use (`blank_to/2` if unused afterwards). The roster page becomes read-only for everyone (it already was in school scope). Delete the roster tests that exercised those events in `test/teacher_assistant_web/live/teacher/roster_live_test.exs` (keep the read-only, redirect and isolation tests).

Run `grep -rn "Quota\|FicheParser\|FicheExtractor\|ModuleLayout\|teacher_personal" lib assets/js test config` and remove every remaining reference (in `curriculum.ex` the `Quota` helpers, if any, and their callers).

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2`
Expected: compile clean; `N tests, 0 failures` with **no** "excluded" suffix. `mix phx.routes | grep /teacher` lists exactly the four routes of the test.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete the paused teacher-personal surfaces

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: School-only fixtures for web tests

**Files:**
- Modify: `test/support/conn_case.ex:45-56` (`register_and_log_in_user/1`), `test/support/fixtures/teacher_fixtures.ex`
- Modify (convert): `test/teacher_assistant_web/live/teacher/{roster_live,marks_live,marks_summary_live}_test.exs`, `test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`, `test/teacher_assistant_web/live/school/settings_live_test.exs` (only the `get_personal_workspace` call), and every web test whose `setup` relies on `workspace:` being a personal workspace (find with `grep -rln "workspace: ws\|%{workspace:" test/teacher_assistant_web`)

**Interfaces:**
- Produces:
  - `register_and_log_in_user/1` → `{:ok, conn: conn, workspace: school, actor: head, year: year}`; the school is setup-complete (active year with calendar, starter classes, periods) and its id is in the session.
  - `TeacherFixtures.school_teacher_fixture(school, head, attrs \\ %{})` → `%{teacher: %User{}, membership: %SchoolMembership{}, class_group: %ClassGroup{}, teaching_context: %TeachingContext{}}` (invites + accepts a `:teacher`, assigns `attrs[:subject] || "Maths"` on `attrs[:class_group] || first class of the active year`).
  - `TeacherFixtures.assigned_context_fixture(school, year, attrs \\ %{})` → `%TeachingContext{}` for `attrs[:teacher] || a new member teacher` on `attrs[:class_group] || a new class group "#{level} X"` with `attrs[:subject] || "Maths"`, `attrs[:level] || "3ème"`.

- [ ] **Step 1: Write the failing fixture test**

Create `test/support_fixtures_test.exs`:

```elixir
defmodule TeacherAssistant.SupportFixturesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "register_and_log_in_user logs a school head into a setup-complete school", %{
    conn: conn,
    workspace: school,
    actor: head,
    year: year
  } do
    assert {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert :head in m.roles
    assert Organization.current_academic_year(school).id == year.id
    assert length(Organization.list_sequences(year)) == 6
    assert Attendance.list_periods(school) != []
    assert Plug.Conn.get_session(conn, :workspace_id) == school.id
  end

  test "school_teacher_fixture assigns a plain teacher to a class", %{workspace: school, actor: head} do
    %{teacher: t, membership: m, class_group: cg, teaching_context: tc} =
      TeacherFixtures.school_teacher_fixture(school, head, %{subject: "Anglais"})

    assert m.roles == [:teacher]
    assert tc.teacher_user_id == t.id
    assert tc.class_group_id == cg.id
    assert tc.subject == "Anglais"
  end

  test "assigned_context_fixture builds a context with a real teacher and class", %{
    workspace: school,
    year: year
  } do
    tc = TeacherFixtures.assigned_context_fixture(school, year, %{subject: "SVT"})
    assert tc.subject == "SVT"
    assert tc.teacher_user_id
    assert tc.class_group_id
    assert [_ | _] = Curriculum.list_assignments_for_class(%{id: tc.class_group_id})
  end
end
```

(If `list_assignments_for_class/1` pattern-matches on `%ClassGroup{}`, load the class group with `Enrollment.fetch_owned_class_group(tc.class_group_id, school)` instead.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/support_fixtures_test.exs`
Expected: FAIL — `fetch_school_membership` returns `{:error, :not_a_member}` (personal workspace), `school_teacher_fixture/3` undefined.

- [ ] **Step 3: Implement the helpers**

In `test/support/conn_case.ex` replace `register_and_log_in_user/1` with:

```elixir
  @doc """
  Logs in a fresh user as the head of a fresh, setup-complete school and puts
  the school in the session. `workspace` is the school; `year` its active year.
  """
  def register_and_log_in_user(%{conn: conn}) do
    %{workspace: school, head_user: head, year: year} =
      TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, head.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, conn: conn, workspace: school, actor: head, year: year}
  end
```

In `test/support/fixtures/teacher_fixtures.ex` delete `workspace_fixture/1` and add:

```elixir
  @doc "Invites, accepts and assigns a plain `:teacher` member to a class of `school`."
  def school_teacher_fixture(workspace, head, attrs \\ %{}) do
    teacher = attrs[:teacher] || user_fixture()

    {:ok, inv} =
      Accounts.invite_member(workspace, head, %{email: to_string(teacher.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, teacher)
    {:ok, membership} = Accounts.fetch_school_membership(workspace, teacher)
    year = Organization.current_academic_year(workspace)

    class_group =
      attrs[:class_group] || TeacherAssistant.Enrollment.list_class_groups(workspace, year) |> List.first()

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(class_group, teacher, %{
        subject: attrs[:subject] || "Maths"
      })

    %{teacher: teacher, membership: membership, class_group: class_group, teaching_context: tc}
  end

  @doc """
  A teaching context on `workspace`/`year` for a real member teacher and a real
  class group (replaces the personal `create_teaching_context`).
  """
  def assigned_context_fixture(workspace, year, attrs \\ %{}) do
    head =
      case Accounts.fetch_school_profile(workspace) do
        {:ok, profile} -> {:ok, u} = Accounts.get_user(profile.owner_user_id); u
      end

    teacher =
      attrs[:teacher] ||
        (fn ->
           u = user_fixture()
           {:ok, inv} = Accounts.invite_member(workspace, head, %{email: to_string(u.email), roles: [:teacher]})
           {:ok, _} = Accounts.accept_invitation(inv.token, u)
           u
         end).()

    class_group =
      attrs[:class_group] ||
        (fn ->
           {:ok, cg} =
             TeacherAssistant.Enrollment.create_class_group(workspace, year, %{
               label: "#{attrs[:level] || "3ème"} #{System.unique_integer([:positive])}",
               level: attrs[:level] || "3ème",
               serie: attrs[:serie]
             })

           cg
         end).()

    {:ok, tc} =
      TeacherAssistant.Curriculum.assign_teacher(class_group, teacher, %{
        subject: attrs[:subject] || "Maths",
        coefficient: attrs[:coefficient] || Decimal.new(1)
      })

    tc
  end
```

(If `assign_teacher/3` does not accept `:coefficient`, drop that key.)

- [ ] **Step 4: Run the fixture test**

Run: `mix test test/support_fixtures_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Convert the web tests**

Run `mix test test/teacher_assistant_web 2>&1 | grep -E "^\s+[0-9]+\) test" | sort -u` and fix every failing file following these rules:
- A test that created its own school with `Organization.create_school(user, ...)` and then put it in the session: keep it, but rename the `workspace:` binding it no longer needs (or use the provided school instead if it only needed "a school").
- A test that used the personal `workspace` to call `Curriculum.create_teaching_context/3` + `Enrollment.create_class_group/3` + `Curriculum.link_class_group/2`: replace those three calls with `tc = TeacherFixtures.assigned_context_fixture(school, year, %{subject: "Maths", level: "3ème", teacher: head})` (pass `teacher: head` when the test drives the page as the logged-in user; `head` is `actor`). `cg` is `Enrollment.fetch_owned_class_group(tc.class_group_id, school)`.
- `test/teacher_assistant_web/live/teacher/marks_live_test.exs`, `marks_summary_live_test.exs`, `roster_live_test.exs`, `test/teacher_assistant_web/controllers/teacher_context_controller_test.exs`: apply the rule above; marks saving needs a verified school — add `{:ok, p} = Accounts.fetch_school_profile(school); {:ok, _} = Accounts.verify_school(p, head.id)` to their setup (as `attendance_live_test.exs` does).
- `test/teacher_assistant_web/live/school/settings_live_test.exs`: replace `Organization.get_personal_workspace(school.id)` with `Organization.get_workspace(school.id)` **after** Task 3 renames it; for now leave it (Task 3 edits it).
- Any assertion that the personal workspace appears in the switcher is deleted.

- [ ] **Step 6: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2`
Expected: 0 failures. `grep -rn "workspace_fixture" test` returns nothing.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: school-only login and teacher fixtures for web tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Domain tests off the personal workspace

**Files:**
- Modify (convert): `test/teacher_assistant/academics/{import_progression_plan,progression_plan,progression_entry,teaching_log_entry,lesson_plan_resource,mark,assessment,progression_module,lesson_step,progression_plan_unit,apply_layout,teaching_context,lesson_plan,resolve_context,calendar,enrollments,workspace,academic_year,enrollments_model,timetables_periods,conduct_mark,student,class_group,fee_adjustment}_test.exs`, `test/teacher_assistant/accounts/{workspaces,permissions,workspaces_verification}_test.exs`
- Modify: `lib/teacher_assistant/curriculum.ex` (delete `create_teaching_context/3` and the `:for_workspace_year` free-typed read on `TeachingContext` if it has no caller left; delete `list_teaching_contexts/2` and the `true ->` personal branches at `curriculum.ex:381`, `:662`, `:701`), `lib/teacher_assistant/organization.ex` (delete `ensure_personal_workspace!/1`, `personal_workspace_for_user/1`), `lib/teacher_assistant/academics/teaching_context.ex` (delete the personal partial `custom_indexes` entry at `:13` and the `:for_workspace_year` read if unused)

**Interfaces:**
- Consumes: `TeacherFixtures.setup_complete_school_fixture/1`, `assigned_context_fixture/3` (Task 2).
- Produces: no test or lib code calls `create_teaching_context`, `ensure_personal_workspace!`, `workspace_fixture`, `list_teaching_contexts`.

- [ ] **Step 1: Make the calls fail**

Delete `Curriculum.create_teaching_context/3`, `Curriculum.list_teaching_contexts/2` (and the three `true ->` personal branches that called it, keeping only the school branch's body), `Organization.ensure_personal_workspace!/1` and `personal_workspace_for_user/1`. Also delete `Reference.default_calendar_preset/0` (the 2025-2026 convenience wrapper) and change `test/teacher_assistant/academics/reference_test.exs`'s preset test to call `default_calendar_preset(~D[2025-09-08], ~D[2026-07-31])`.

Run: `mix test 2>&1 | grep -c "UndefinedFunctionError\|undefined"`
Expected: a non-zero count — every converted test file is now red for the right reason.

- [ ] **Step 2: Convert the domain tests**

For each file listed, replace its setup:

```elixir
# before
ws = TeacherFixtures.workspace_fixture()
{:ok, year} = Organization.create_academic_year(ws, %{...})
{:ok, ctx} = Curriculum.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", ...})
```

with:

```elixir
%{workspace: ws, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
ctx = TeacherFixtures.assigned_context_fixture(ws, year, %{subject: "Maths", level: "3ème", teacher: head})
```

Rules:
- Tests that needed a bare workspace only (`workspace_test`, `academic_year_test`, `calendar_test`, `timetables_periods_test`, `student_test`, `class_group_test`, `enrollments*`, `conduct_mark_test`, `fee_adjustment_test`, `permissions_test`, `workspaces*_test`): use `%{workspace: ws} = TeacherFixtures.school_fixture()` (no year) or `setup_complete_school_fixture()` when they need a year; `calendar_test`'s `year_fixture/2` creates its own year on a `school_fixture()` workspace with `active: false` when the fixture year must stay active, or `active: true` when the test reads `current_academic_year`.
- `teaching_context_test.exs`: the "personal context without class group" cases are deleted; keep uniqueness (teacher × subject × class × year) cases using `assigned_context_fixture` twice with the same `class_group:` and `teacher:`.
- `resolve_context_test.exs` and `workspaces_test.exs`: the personal-scope cases (`scope_for(user, ws.id)` on a personal workspace) are deleted; school cases stay.
- `permissions_test.exs`: any `%Scope{current_workspace_type: :personal_teacher}` case is deleted (the field goes in Task 4).
- Keep every assertion that is about the behaviour under test; only the setup changes.

- [ ] **Step 3: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2`
Expected: 0 failures. `grep -rn "create_teaching_context\|ensure_personal_workspace\|workspace_fixture\|list_teaching_contexts" lib test` returns nothing.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: domain tests use school fixtures; personal context creation removed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Workspace becomes the tenant record

**Files:**
- Modify: `lib/teacher_assistant/academics/workspace.ex` (`:36` defaults create accept, `:40-48` `read :for_owner`, `:85-99` attributes `kind`/`owner_user` relationship, `:109` identity), `lib/teacher_assistant/organization.ex` (`:26` define rename, `:53` owner arg), `lib/teacher_assistant/scope.ex` (drop `:current_workspace_type` and `personal_context?/1`), `lib/teacher_assistant/accounts/workspaces.ex` (drop `personal_scope/3`, the `kind` match), `lib/teacher_assistant/accounts/permissions.ex` (every `current_workspace_type: :school` match), `lib/teacher_assistant/curriculum.ex:375,619,656` (pattern matches on the field), `lib/teacher_assistant_web/live_user_auth.ex:49,60`, `lib/teacher_assistant_web/components/layouts.ex:72,150,382-383`, `lib/teacher_assistant_web/live/school/{classes,enroll_import,periods,settings,courses,my_timetable,dashboard,class}_live.ex`, `lib/teacher_assistant_web/live/teacher/roster_live.ex:12`, `lib/teacher_assistant_web/controllers/{school_logo,timetable_print,bulletin_print}_controller.ex`, `test/teacher_assistant_web/live/school/settings_live_test.exs` (`get_personal_workspace` → `get_workspace`)
- Delete: `lib/teacher_assistant/accounts/workspace_kind.ex`, `test/teacher_assistant/accounts/school_enums_test.exs` cases on `WorkspaceKind` (if any)
- Test: `test/teacher_assistant/academics/workspace_test.exs`, `test/teacher_assistant/accounts/workspaces_test.exs`

**Interfaces:**
- Produces: `%Scope{}` has no `current_workspace_type`; "in a school" is `scope.current_workspace != nil`. `Organization.get_workspace/1` (was `get_personal_workspace`). `Workspace` attributes: `id`, `name`, timestamps only.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant/academics/workspace_test.exs`:

```elixir
  test "a workspace has no kind or owner" do
    refute Map.has_key?(%TeacherAssistant.Academics.Workspace{}, :kind)
    refute Map.has_key?(%TeacherAssistant.Academics.Workspace{}, :owner_user_id)
  end
```

Append to `test/teacher_assistant/accounts/workspaces_test.exs`:

```elixir
  test "a scope has no workspace type; membership decides everything" do
    %{workspace: school, head_user: head} = TeacherFixtures.school_fixture()
    {:ok, scope} = Workspaces.scope_for(head, school.id)
    refute Map.has_key?(scope, :current_workspace_type)
    assert scope.current_workspace.id == school.id
    assert :head in scope.current_roles
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/academics/workspace_test.exs test/teacher_assistant/accounts/workspaces_test.exs`
Expected: both new tests FAIL (keys exist).

- [ ] **Step 3: Retire the fields**

`lib/teacher_assistant/academics/workspace.ex`: `defaults [..., create: [:name]]`; delete `read :for_owner`; delete `attribute :kind`, `belongs_to :owner_user`, `identity :unique_owner_user`; in `create_school` delete `change set_attribute(:kind, :school)`. Delete `lib/teacher_assistant/accounts/workspace_kind.ex`.

`lib/teacher_assistant/organization.ex`: rename the define to `define :get_workspace, action: :read, get_by: [:id]`; `create_school/2` no longer passes `kind`.

`lib/teacher_assistant/scope.ex`: remove `:current_workspace_type` from the struct, delete `personal_context?/1`, `setup_complete?/1` matches on `%__MODULE__{current_workspace: %{}} = scope` (falls through to `true` only when there is no workspace: change the second clause to `def setup_complete?(%__MODULE__{current_workspace: nil}), do: true`).

`lib/teacher_assistant/accounts/workspaces.ex`: `scope_for(user, workspace_id, context_id)` becomes

```elixir
  def scope_for(user, workspace_id, context_id) do
    case Organization.get_workspace(workspace_id) do
      {:ok, ws} -> school_scope(user, ws, context_id)
      _ -> {:error, :workspace_not_found}
    end
  end
```

delete `personal_scope/3`; in `school_scope/3` drop `current_workspace_type: :school`.

`lib/teacher_assistant/accounts/permissions.ex`: every `%Scope{current_workspace_type: :school, ...}` pattern becomes `%Scope{current_workspace: %{}, ...}`; `member?/1` → `def member?(%Scope{current_membership: %{}}), do: true`; `operating_allowed?/1` → `def operating_allowed?(scope), do: TeacherAssistant.Scope.school_verified?(scope)`.

`lib/teacher_assistant/curriculum.ex:375-383` and `:653-664`: the `cond` collapses to the school branch (`is_nil(ws) or is_nil(year) -> []`, else the school call); `:619` pattern drops the type key.

Web: every `scope.current_workspace_type == :school` / `!= :school` / `with :school <- scope.current_workspace_type` becomes `scope.current_workspace != nil` / `== nil` / `with %{} <- scope.current_workspace`. `live_user_auth.ex:49` → `if scope && scope.current_workspace && is_nil(scope.current_context)`; `:60` → `scope == nil or scope.current_workspace == nil ->`. `layouts.ex:72` → `assign(:in_school?, current_scope && current_scope.current_workspace != nil)`; `:150` badge `:if` removed (every workspace is a school); `:382-383` → one clause `defp workspace_type_label(_), do: gettext("School")`. `roster_live.ex:12` → `read_only? = true` (and drop it if nothing else reads it).

`test/teacher_assistant_web/live/school/settings_live_test.exs`: `get_personal_workspace` → `get_workspace`.

- [ ] **Step 4: Codegen and verify**

Run: `mix ash.codegen --dev && mix ash.reset && mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: a dev migration dropping `kind`, `owner_user_id`, the identity; 0 failures; check clean. `grep -rn "current_workspace_type\|personal_teacher\|WorkspaceKind\|get_personal_workspace" lib test` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: Workspace is the tenant record; scope has no workspace type

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `belongs_to :workspace` everywhere, every reference indexed

**Files:**
- Modify (raw uuid → FK): `lib/teacher_assistant/academics/attendance_entry.ex:220,226-241`, `timetable_slot.ex:170,176-192`, `sanction_entry.ex:81,87-90`, `conduct_mark.ex:66,72-82`, `fee_tranche.ex:59,65-68`, `payment.ex:75,81-84`, `fee_adjustment.ex:57,63-66`
- Modify (no column → FK): `term.ex:36-42`, `sequence.ex:45-48`, `assessment.ex:120-132`, `mark.ex:96-106`, `progression_module.ex:69-79`, `progression_entry.ex:100-115`, `lesson_plan.ex:68-75`, `lesson_step.ex:107-110`
- Modify (index every reference): every resource's `postgres do ... references do ... end end`
- Modify (populate the new column on create): `lib/teacher_assistant/organization.ex` (`do_build_default_calendar/1`: Term and Sequence creates), `lib/teacher_assistant/assessment.ex` (assessment/mark creates), `lib/teacher_assistant/academics/mark.ex:131`, `assessment.ex:211`, `progression_plan.ex:132,166,320,330`, `lib/teacher_assistant/curriculum.ex` (module/entry/lesson plan/step creates), `enrollment.ex:72-76` (student + enrollment already carry it)
- Test: `test/teacher_assistant/schema_test.exs` (new)

**Interfaces:**
- Produces: every tenant-owned resource has `belongs_to :workspace, TeacherAssistant.Academics.Workspace, allow_nil?: false` and a DB index on every FK column. Until Task 8 flips multitenancy, creates set `workspace_id` explicitly from the parent (`term: year.workspace_id`, `sequence: term.workspace_id`, `assessment: teaching_context.workspace_id`, `mark: assessment.workspace_id`, `module/entry: plan.workspace_id`, `lesson_plan: entry.workspace_id`, `lesson_step: lesson_plan.workspace_id`).

- [ ] **Step 1: Write the failing schema test**

Create `test/teacher_assistant/schema_test.exs`:

```elixir
defmodule TeacherAssistant.SchemaTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics, as: A

  @tenant_owned [
    A.AcademicYear, A.Term, A.Sequence, A.Subject, A.Period, A.ClassGroup, A.Student,
    A.Enrollment, A.TeachingContext, A.CombinedCourse, A.ProgressionPlan,
    A.ProgressionModule, A.ProgressionEntry, A.LessonPlan, A.LessonStep,
    A.TeachingLogEntry, A.Assessment, A.Mark, A.AttendanceEntry, A.TimetableSlot,
    A.SanctionEntry, A.ConductMark, A.FeeTranche, A.Payment, A.FeeAdjustment,
    TeacherAssistant.Accounts.SchoolMembership, TeacherAssistant.Accounts.SchoolInvitation
  ]

  test "every tenant-owned resource belongs to a workspace, not-null" do
    for resource <- @tenant_owned do
      rel = Ash.Resource.Info.relationship(resource, :workspace)
      assert rel, "#{inspect(resource)} has no :workspace relationship"
      assert rel.type == :belongs_to
      refute rel.allow_nil?, "#{inspect(resource)}.workspace allows nil"
      attr = Ash.Resource.Info.attribute(resource, :workspace_id)
      assert attr && attr.type == Ash.Type.UUID
    end
  end

  test "every foreign key column is indexed" do
    missing =
      for resource <- @tenant_owned,
          rel <- Ash.Resource.Info.relationships(resource),
          rel.type == :belongs_to,
          table = AshPostgres.DataLayer.Info.table(resource),
          not indexed?(table, rel.source_attribute) do
        {table, rel.source_attribute}
      end

    assert missing == []
  end

  defp indexed?(table, column) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        TeacherAssistant.Repo,
        "SELECT indexdef FROM pg_indexes WHERE tablename = $1",
        [table]
      )

    Enum.any?(rows, fn [def] -> String.contains?(def, "(#{column}") or String.contains?(def, "(#{column},") end)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/teacher_assistant/schema_test.exs`
Expected: both tests FAIL (Term has no `:workspace`; indexes missing).

- [ ] **Step 3: Add the relationships**

For each resource in the two "raw uuid" and "no column" lists, inside `relationships do` add (and delete any `attribute :workspace_id, :uuid, ...` line):

```elixir
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
    end
```

In every resource's `postgres do` block make sure a `references do` block lists every `belongs_to` with `index?: true`, keeping existing `on_delete` options, for example in `attendance_entry.ex`:

```elixir
    references do
      reference :enrollment, on_delete: :delete, index?: true
      reference :period, on_delete: :delete, index?: true
      reference :teaching_context, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
```

Apply the same to all 27 resources (`references` with `index?: true` on each `belongs_to`; `on_delete: :delete` for `:workspace` everywhere).

- [ ] **Step 4: Populate `workspace_id` on the creates that lacked it**

Wherever Term, Sequence, Assessment, Mark, ProgressionModule, ProgressionEntry, LessonPlan or LessonStep rows are created (files listed above), add `workspace_id: <parent>.workspace_id` to the create params, and add `:workspace_id` to that resource's create `accept` list (Tasks 8–15 remove the accepts again when the tenant takes over). Example, `organization.ex` `do_build_default_calendar/1`:

```elixir
      {:ok, term} =
        Term
        |> Ash.Changeset.for_create(:create, %{
          position: term_spec.position,
          academic_year_id: year.id,
          workspace_id: year.workspace_id
        })
        |> Ash.create()
```

and the Sequence create gets `workspace_id: year.workspace_id`. In `mark.ex` `:upsert_all` the Mark create gets `workspace_id: assessment.workspace_id` (load the assessment's `workspace_id`; it is on the struct once Assessment has the column). In `assessment.ex` `:create_combined` the Assessment create gets `workspace_id: ctx.workspace_id`. In `progression_plan.ex` `:import` / `for_course` / default bucket, modules and entries get `workspace_id: plan.workspace_id` (plan is the changeset result or `changeset.data`). In `curriculum.ex`, lesson plan and step creates get the entry's / lesson plan's `workspace_id` (load `:progression_entry` when needed).

- [ ] **Step 5: Codegen and verify**

Run: `mix ash.codegen --dev && mix ash.reset && mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: dev migration adds 15 not-null columns and ~40 indexes; schema test green; 0 failures.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: belongs_to :workspace on every tenant-owned resource, all references indexed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Constraints and composite indexes

**Files:**
- Modify: `lib/teacher_assistant/academics/academic_year.ex` (custom_indexes), `attendance_entry.ex` (custom_indexes), `progression_entry.ex` (custom_indexes), `timetable_slot.ex` (custom_indexes), `mark.ex` (check + validation), `payment.ex`, `fee_tranche.ex`, `fee_adjustment.ex`, `conduct_mark.ex`, `sequence.ex`, `academic_year.ex` (check_constraints)
- Test: `test/teacher_assistant/constraints_test.exs` (new)

**Interfaces:**
- Produces: DB-level guarantees listed in spec §3.2; `Mark` validation `score <= assessment.max_score`.

- [ ] **Step 1: Write the failing tests**

Create `test/teacher_assistant/constraints_test.exs`:

```elixir
defmodule TeacherAssistant.ConstraintsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Assessment, Discipline, Fees, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    tc = TeacherFixtures.assigned_context_fixture(ws, year, %{teacher: head})
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(tc.class_group_id, ws)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = TeacherAssistant.Enrollment.list_roster(cg)
    seq = year |> Organization.list_sequences() |> List.first()
    %{ws: ws, head: head, year: year, tc: tc, cg: cg, enrollment: enrollment, seq: seq}
  end

  test "only one active academic year per workspace at the database level", %{ws: ws} do
    assert {:error, _} =
             TeacherAssistant.Academics.AcademicYear
             |> Ash.Changeset.for_create(:create, %{
               name: "Doublon",
               start_date: ~D[2030-09-01],
               end_date: ~D[2031-06-30],
               active: true,
               workspace_id: ws.id
             })
             |> Ash.create()
  end

  test "activate still works because it deactivates siblings first", %{ws: ws} do
    {:ok, y2} =
      Organization.create_academic_year(ws, %{
        name: "Suivante",
        start_date: ~D[2030-09-01],
        end_date: ~D[2031-06-30],
        active: false
      })

    assert {:ok, %{active: true}} = Organization.activate_academic_year(y2)
    assert Organization.current_academic_year(ws).id == y2.id
  end

  test "a mark above the assessment's max score is rejected", %{tc: tc, seq: seq, cg: cg} do
    {:ok, a} = Assessment.create_assessment(tc, seq, %{label: "D1", max_score: Decimal.new(20)})
    [%{student: s}] = TeacherAssistant.Enrollment.list_roster(cg)
    assert {:error, _} = Assessment.upsert_marks(a, %{s.id => Decimal.new("21")})
    assert {:error, _} = Assessment.upsert_marks(a, %{s.id => Decimal.new("-1")})
  end

  test "non-positive fee amounts are rejected", %{cg: cg, enrollment: e, head: head} do
    assert {:error, _} = Fees.add_tranche(cg, %{label: "T1", amount: 0, due_on: ~D[2030-10-01]})
    assert {:error, _} = Fees.record_payment(e, %{amount: 0, method: :cash}, head.id)
  end

  test "a conduct mark outside 0..20 is rejected", %{enrollment: e, seq: seq, head: head} do
    assert {:error, _} = Discipline.set_conduct_mark(e, seq, 21, head.id)
  end
end
```

Adjust the four domain function names/arities to the real ones in `lib/teacher_assistant/{assessment,fees,discipline}.ex` (read the `def` lines; the behaviours are what matter).

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/teacher_assistant/constraints_test.exs`
Expected: the "one active year" test FAILS (second active year is created); the others may already pass through domain rules — that is fine, they pin the constraint layer.

- [ ] **Step 3: Add the constraints**

`academic_year.ex` `postgres do`:

```elixir
    custom_indexes do
      index [:workspace_id], unique: true, where: "active", name: "academic_years_one_active_per_workspace"
    end

    check_constraints do
      check_constraint :dates_ordered, check: "end_date > start_date", message: "must be after the start date"
    end
```

`attendance_entry.ex`: `custom_indexes do index [:enrollment_id, :date]; index [:workspace_id, :date] end`. `progression_entry.ex`: `index [:progression_module_id, :position]` (verify the FK name; entries belong to modules). `timetable_slot.ex`: `index [:workspace_id, :teaching_context_id]`.

`mark.ex`: `check_constraints do check_constraint :score_non_negative, check: "score IS NULL OR score >= 0" end` and a resource validation:

```elixir
  validations do
    validate {TeacherAssistant.Academics.Mark.ScoreWithinMax, []}, on: [:create, :update]
  end
```

Create `lib/teacher_assistant/academics/mark/score_within_max.ex` (`mix ash.gen.validation TeacherAssistant.Academics.Mark.ScoreWithinMax`) whose `validate/3` loads the assessment (`Ash.get!(Assessment, assessment_id)` with the changeset's tenant once Task 11 flips) and returns `{:error, field: :score, message: "exceeds the assessment's maximum"}` when `Decimal.compare(score, assessment.max_score) == :gt`.

`payment.ex`: `check_constraint :amount_positive, check: "amount > 0"`; `fee_tranche.ex`: same; `fee_adjustment.ex`: `check_constraint :amount_non_zero, check: "amount <> 0"`; `conduct_mark.ex`: `check_constraint :value_in_range, check: "value >= 0 AND value <= 20"`; `sequence.ex`: `check_constraint :dates_ordered, check: "end_date >= start_date"`.

- [ ] **Step 4: Codegen and verify**

Run: `mix ash.codegen --dev && mix ash.reset && mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures, check clean.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: one active year per workspace, check constraints and hot-path indexes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Non-null pivots, duplicate attributes, enums, squash

**Files:**
- Modify: `lib/teacher_assistant/academics/teaching_context.ex` (`:12-25` custom_indexes, `:178` dup attribute, `:196-206` `class_group`/`teacher` `allow_nil? false`, quota attributes), `class_group.ex:76` (dup attribute), `lib/teacher_assistant/accounts/school_role.ex` (drop `:form_master`), `lib/teacher_assistant/academics/progression_plan.ex:269-272`, `progression_entry.ex:74-88`, `teaching_log_entry.ex:66-70` (enums)
- Create: `lib/teacher_assistant/academics/progression_plan_status.ex`, `progression_entry_type.ex`, `teaching_log_status.ex`
- Delete: `priv/resource_snapshots/repo/personal_workspaces/`
- Test: `test/teacher_assistant/academics/teaching_context_test.exs`, `test/teacher_assistant/accounts/school_enums_test.exs`

**Interfaces:**
- Produces: `TeachingContext` requires `teacher_user_id` and `class_group_id`; `SchoolRole` values `[:head, :vice_principal, :discipline_master, :bursar, :hod, :teacher, :guidance_counsellor, :librarian]` (verify the current list minus `:form_master`); three new enum types.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant/academics/teaching_context_test.exs`:

```elixir
  test "a teaching context requires a teacher and a class group" do
    %{workspace: ws, year: year} = TeacherFixtures.setup_complete_school_fixture()

    assert {:error, %Ash.Error.Invalid{}} =
             TeacherAssistant.Academics.TeachingContext
             |> Ash.Changeset.for_create(:create, %{
               subject: "Maths",
               level: "3ème",
               workspace_id: ws.id,
               academic_year_id: year.id
             })
             |> Ash.create()
  end
```

Append to `test/teacher_assistant/accounts/school_enums_test.exs`:

```elixir
  test "form master is a class fact, not a role" do
    refute :form_master in TeacherAssistant.Accounts.SchoolRole.values()
  end

  test "progression and log statuses are enums" do
    assert TeacherAssistant.Academics.ProgressionPlanStatus.values() != []
    assert TeacherAssistant.Academics.ProgressionEntryType.values() != []
    assert TeacherAssistant.Academics.TeachingLogStatus.values() != []
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/academics/teaching_context_test.exs test/teacher_assistant/accounts/school_enums_test.exs`
Expected: FAIL (context created without teacher; `:form_master` present; enum modules undefined).

- [ ] **Step 3: Implement**

`teaching_context.ex`: delete the first `custom_indexes` entry (personal: `[:workspace_id, :academic_year_id, :subject, :level, :serie]`), keep the school one; delete `attribute :combined_course_id, :uuid, ...` (the `belongs_to` with `define_attribute? false` becomes `define_attribute? true`, i.e. remove that line); `belongs_to :class_group` and `belongs_to :teacher` get `allow_nil? false`; delete `annual_hours`, `target_module_count`, `target_lesson_count` attributes and every reference (`grep -rn "annual_hours\|target_module_count\|target_lesson_count" lib test`, delete the callers' use — they were only read by the deleted fiche/quota code and the `update_teaching_context` function, which goes too if it has no caller).

`class_group.ex`: delete `attribute :form_master_user_id, :uuid, ...`; remove `define_attribute? false` from `belongs_to :form_master`.

`school_role.ex`: remove `:form_master` from `values` and from `label/1`; `grep -rn ":form_master" lib test` and delete any role-based use (the class FK path `Enrollment.form_master/1`, `Permissions.form_master?/2` stay).

Enums: `mix ash.gen.enum TeacherAssistant.Academics.ProgressionPlanStatus <values>` with the values currently in `progression_plan.ex:269-272` (read them), likewise `ProgressionEntryType` from `progression_entry.ex:74-88` and `TeachingLogStatus` from `teaching_log_entry.ex:66-70`; add a `label/1` per value with `gettext` like `lib/teacher_assistant/academics/attendance_status.ex` does; change the three attributes to the new types (drop `constraints: [one_of: ...]`); the `lesson_step.ex:54` argument type becomes `ProgressionEntryType` if it lists the same atoms.

Delete the stale snapshot directory: `rm -rf priv/resource_snapshots/repo/personal_workspaces`.

- [ ] **Step 4: Codegen, squash and verify**

Run: `mix ash.codegen --dev && mix ash.reset && mix compile --warnings-as-errors && mix test 2>&1 | tail -2`
Expected: 0 failures.

Then squash every dev migration of this phase into one named migration:

Run: `mix ash.codegen schema_pass && mix ash.reset && mix test 2>&1 | tail -1 && mix ash.codegen --check && ls priv/repo/migrations | tail -3`
Expected: one new `*_schema_pass.exs`, no `*_dev_*` migrations left, 0 failures, check clean.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: non-null teaching pivots, no duplicate FK attrs, enum statuses; squash schema migrations

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Phase 1 gate:** dispatch the whole-branch reviewer on Tasks 1–7 before starting Task 8.

---

# Phase 2 — Tenancy

Every task in this phase follows the same recipe for its resources:
1. add the `multitenancy` block; delete `:workspace_id` from every `accept`/`defaults create:` list of the resource;
2. every domain function (and every hook inside the resource's own actions) that reads or writes the resource sets the tenant from the data it has: `Ash.Query.set_tenant(query, ws.id)` / `Ash.Changeset.set_tenant(changeset, ws.id)` / `tenant: ws.id` on code-interface calls, where `ws.id` is the workspace id of the `%Workspace{}` or of the child struct's `.workspace_id`;
3. remove the manual `workspace_id == ^arg(:workspace_id)` filters and the `workspace_id:` arguments that only existed for tenancy (keep arguments that are not tenancy, e.g. `academic_year_id`, `teacher_user_id`);
4. append isolation rows for the resources to `test/teacher_assistant/tenancy_isolation_test.exs` and run the whole suite.

### Task 8: Scope tenant, isolation harness, Organization domain

**Files:**
- Modify: `lib/teacher_assistant/scope.ex` (`get_tenant/1`), `lib/teacher_assistant/academics/{academic_year,term,sequence}.ex` (multitenancy), `lib/teacher_assistant/academics/workspace.ex` (`create_school` after_action: tenant on membership/subject/period creates), `lib/teacher_assistant/organization.ex` (every read/write on years, terms, sequences)
- Create: `test/teacher_assistant/tenancy_isolation_test.exs`
- Test: `test/teacher_assistant/accounts/workspaces_test.exs`, `test/teacher_assistant/accounts/schools_create_test.exs`

**Interfaces:**
- Produces: `Ash.Scope.ToOpts.get_tenant(%Scope{})` → `{:ok, workspace_id}`; the isolation test module with a `@tenant_owned` list and a `row_for(resource, school)` helper later tasks extend.

- [ ] **Step 1: Write the failing tests**

Create `test/teacher_assistant/tenancy_isolation_test.exs`:

```elixir
defmodule TeacherAssistant.TenancyIsolationTest do
  @moduledoc """
  For every multitenant resource: a row created under school A is invisible
  under school B, and a create without a tenant raises. Later tasks add
  `row_for/2` clauses as they flip domains.
  """
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics, as: A
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: a, year: year_a} = TeacherFixtures.setup_complete_school_fixture()
    %{workspace: b} = TeacherFixtures.setup_complete_school_fixture()
    %{a: a, b: b, year_a: year_a}
  end

  # One clause per resource; returns a row created under `school`.
  defp row_for(A.AcademicYear, school, _ctx), do: Organization.current_academic_year(school)
  defp row_for(A.Term, school, _ctx), do: school |> Organization.current_academic_year() |> Organization.list_terms() |> List.first()
  defp row_for(A.Sequence, school, _ctx), do: school |> Organization.current_academic_year() |> Organization.list_sequences() |> List.first()

  @flipped [A.AcademicYear, A.Term, A.Sequence]

  test "a row of school A is not readable under school B", ctx do
    for resource <- @flipped do
      row = row_for(resource, ctx.a, ctx)
      assert row, "#{inspect(resource)}: no row created"
      assert {:ok, _} = Ash.get(resource, row.id, tenant: ctx.a.id)
      assert {:error, %Ash.Error.Invalid{}} = Ash.get(resource, row.id, tenant: ctx.b.id)
    end
  end

  test "reading a flipped resource without a tenant raises", ctx do
    for resource <- @flipped do
      assert_raise Ash.Error.Invalid, fn ->
        resource |> Ash.Query.filter(id == ^row_for(resource, ctx.a, ctx).id) |> Ash.read!()
      end
    end
  end

  test "creating a flipped resource without a tenant raises", %{a: a} do
    year = Organization.current_academic_year(a)

    assert_raise Ash.Error.Invalid, ~r/tenant/, fn ->
      A.Term |> Ash.Changeset.for_create(:create, %{position: 9, academic_year_id: year.id}) |> Ash.create!()
    end
  end

  test "the scope exposes the workspace as tenant", %{a: a} do
    head = a |> TeacherAssistant.Accounts.list_members() |> List.first() |> Map.fetch!(:user)
    {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(head, a.id)
    assert Ash.Scope.ToOpts.get_tenant(scope) == {:ok, a.id}
  end
end
```

(`require Ash.Query` at the top; if `list_members/1` returns memberships without the user loaded, use `Accounts.fetch_school_profile(a)` → `owner_user_id` → `Accounts.get_user/1`.)

Append to `test/teacher_assistant/accounts/schools_create_test.exs`:

```elixir
  test "create_school seeds catalog, periods and head membership under the new tenant" do
    user = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)

    for {resource, list} <- [
          {TeacherAssistant.Academics.Subject, TeacherAssistant.Curriculum.list_subjects(school)},
          {TeacherAssistant.Academics.Period, TeacherAssistant.Attendance.list_periods(school)}
        ] do
      assert list != [], inspect(resource)
      assert Enum.all?(list, &(&1.workspace_id == school.id))
    end

    assert {:ok, %{workspace_id: wid}} = Accounts.fetch_school_membership(school, user)
    assert wid == school.id
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL — `Ash.get(..., tenant: b.id)` still returns the row (no multitenancy), `get_tenant` returns `:error`.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/scope.ex`: `def get_tenant(%{current_workspace: %{id: id}}), do: {:ok, id}` and `def get_tenant(_), do: :error`.

`academic_year.ex`, `term.ex`, `sequence.ex`: add the multitenancy block; remove `:workspace_id` from `accept`/`defaults create:` (Term and Sequence got it in Task 5; AcademicYear had it). `AcademicYear.:activate`'s `deactivate_others/2` hook: the query it builds gets `Ash.Query.set_tenant(changeset.tenant)` and the updates it issues `Ash.Changeset.set_tenant(changeset.tenant)`; in `:create_for_workspace`'s after_action use `changeset.tenant` likewise.

`organization.ex`: `create_academic_year(ws, attrs)` → `Ash.Changeset.for_create(:create_for_workspace, attrs) |> Ash.Changeset.set_tenant(ws.id)`; `list_academic_years/1`, `current_academic_year/1` → `Ash.Query.set_tenant(ws_id)` and drop the `workspace_id` argument from `:for_workspace` / `:active_for_workspace` (they become plain reads with `sort`, or keep the read names with no argument); `get_academic_year/1` (unscoped `get_by: [:id]` define) is replaced by `get_academic_year(id, %Workspace{id: ws_id})` → `Ash.get(AcademicYear, id, tenant: ws_id)` — update its callers (`settings_live.ex` `activate_year`/`generate_calendar`, which already check the workspace by hand: delete that manual check); `build_default_calendar/1` sets `tenant: year.workspace_id` on the Term and Sequence creates and drops `workspace_id:` from their params; `list_terms/1`, `list_sequences/1`, `current_sequence/2`, `period_date_range/1` → `set_tenant(year.workspace_id)`; `activate_academic_year/1` → `set_tenant(year.workspace_id)`.

`workspace.ex` `create_school` after_action: `create_head_membership/2`, `seed_catalog/3`, `seed_periods/1` pipe `Ash.Changeset.set_tenant(workspace.id)` before `Ash.create()` and drop `workspace_id:` from their params (SchoolMembership/Subject/Period flip in Tasks 15/10/12; until then keep `workspace_id:` in params AND set the tenant — Ash ignores the tenant on a non-multitenant resource, so both can coexist; the later task removes the param).

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures; check clean (multitenancy adds no schema).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: scope tenant and attribute multitenancy for years, terms and sequences

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Enrollment domain (ClassGroup, Student, Enrollment)

**Files:**
- Modify: `lib/teacher_assistant/academics/{class_group,student,enrollment}.ex`, `lib/teacher_assistant/enrollment.ex`, `lib/teacher_assistant/academics/seeding.ex` (`has_any_class?/1`), `test/teacher_assistant/tenancy_isolation_test.exs`

**Interfaces:**
- Consumes: Task 8 harness.
- Produces: `Enrollment.fetch_owned_class_group(id, ws)` and `fetch_owned_student(id, ws)` keep their signatures but are tenant-filtered `Ash.get`s; new `Enrollment.fetch_owned_enrollment(id, %Workspace{})` → `{:ok, %Enrollment{}} | {:error, :not_found}` (`Ash.get(Enrollment, id, tenant: ws.id)`); `ClassGroup.:owned`, `Student.:owned` reads lose the `workspace_id` argument; `:for_workspace_and_year` keeps only `academic_year_id`; `Enrollment.:enroll_new` nested student/enrollment creates carry `changeset.tenant`.

- [ ] **Step 1: Extend the failing isolation test**

Add clauses and list entries to `tenancy_isolation_test.exs`:

```elixir
  defp row_for(A.ClassGroup, school, _ctx), do: school |> Organization.current_academic_year() |> then(&TeacherAssistant.Enrollment.list_class_groups(school, &1)) |> List.first()
  defp row_for(A.Student, school, ctx), do: row_for(A.Enrollment, school, ctx).student
  defp row_for(A.Enrollment, school, ctx) do
    cg = row_for(A.ClassGroup, school, ctx)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(cg, %{full_name: "Iso #{System.unique_integer([:positive])}", sex: :m})
    cg |> TeacherAssistant.Enrollment.list_roster() |> List.first() |> Map.fetch!(:enrollment)
  end
```

and `@flipped [..., A.ClassGroup, A.Student, A.Enrollment]`. Also add:

```elixir
  test "a class group of school A cannot be fetched as owned by school B", %{a: a, b: b} = ctx do
    cg = row_for(A.ClassGroup, a, ctx)
    assert {:ok, _} = TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, a)
    assert {:error, :not_found} = TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, b)
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for the three new resources.

- [ ] **Step 3: Implement**

Add the multitenancy block to the three resources; remove `:workspace_id` from `defaults create:` (`class_group.ex:21`, `student.ex:25`) and from `enrollment.ex`'s create accept. `ClassGroup.:owned` → argument `:id` only, filter `id == ^arg(:id)`; `:for_workspace_and_year` → argument `academic_year_id` only; `Student.:owned`, `:by_matricule`, `:search_by_name` drop the `workspace_id` argument and clause. `Enrollment.:enroll_new` (`enrollment.ex:63-88`): both nested `for_create` calls get `|> Ash.Changeset.set_tenant(changeset.tenant)` and lose `workspace_id:`; the TeachingContext query inside it (`:66-69`) gets `Ash.Query.set_tenant(changeset.tenant)`.

`lib/teacher_assistant/enrollment.ex`: every function taking `%Workspace{id: ws_id}` sets `tenant: ws_id` / `set_tenant(ws_id)`; every function taking a `%ClassGroup{}`, `%Student{}` or `%Enrollment{}` sets the tenant from `.workspace_id`; `create_class_group(ws, year, attrs)` drops `workspace_id:` from params and sets the tenant; `add_student/2` (student + enrollment) sets tenant `cg.workspace_id` on both creates; `form_master/1` (`Ash.get(User)`) is untouched (User is not multitenant); `list_form_master_classes/3` → `set_tenant(ws.id)`; `import_csv`/`by_matricule` paths → tenant. Add `fetch_owned_enrollment/2` next to `fetch_owned_student/2`, mapping any error to `{:error, :not_found}`. `seeding.ex` `has_any_class?/1` → `Ash.Query.set_tenant(ws_id)` and `Ash.exists?`.

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for class groups, students and enrollments

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Curriculum domain

**Files:**
- Modify: `lib/teacher_assistant/academics/{subject,teaching_context,combined_course,progression_plan,progression_module,progression_entry,lesson_plan,lesson_step,teaching_log_entry}.ex`, `lib/teacher_assistant/curriculum.ex` (72 Ash calls), `lib/teacher_assistant/academics/workspace.ex` (`seed_catalog/3` drops `workspace_id:`), `lib/teacher_assistant/academics/progression_plan/exactly_one_owner.ex` (unchanged unless it queries), `test/teacher_assistant/tenancy_isolation_test.exs`

**Interfaces:**
- Produces: `Curriculum.fetch_owned_plan/2`, `fetch_owned_entry/2`, `fetch_owned_module/2`, `fetch_owned_teaching_context/2` keep signatures, tenant-filtered; `fetch_assigned_teaching_context/2` keeps the assignment filter (`teacher_user_id == ^user`) and drops the workspace clause; `list_units_for_scope/1` sets `tenant` from `scope.current_workspace.id`; `get_course/1`, `get_teaching_context/1`, `get_progression_plan/1`, `get_progression_entry/1` unscoped `get_by: [:id]` defines are replaced by 2-arity versions taking the workspace (or the parent struct) — update every caller (`grep -rn "Curriculum.get_course\|get_teaching_context\|get_progression_plan(\|get_progression_entry(" lib test`).

- [ ] **Step 1: Extend the failing isolation test**

```elixir
  defp row_for(A.Subject, school, _ctx), do: school |> TeacherAssistant.Curriculum.list_subjects() |> List.first()
  defp row_for(A.TeachingContext, school, ctx), do: TeacherFixtures.assigned_context_fixture(school, Organization.current_academic_year(school))
  defp row_for(A.CombinedCourse, school, ctx) do
    year = Organization.current_academic_year(school)
    t = TeacherFixtures.user_fixture()
    tc1 = TeacherFixtures.assigned_context_fixture(school, year, %{teacher: t, subject: "Maths"})
    tc2 = TeacherFixtures.assigned_context_fixture(school, year, %{teacher: t, subject: "Maths"})
    {:ok, course} = TeacherAssistant.Curriculum.combine_course([tc1, tc2])
    course
  end
  defp row_for(A.ProgressionPlan, school, ctx), do: row_for(A.CombinedCourse, school, ctx) |> then(&TeacherAssistant.Curriculum.plan_for_course!(&1))
  defp row_for(A.ProgressionModule, school, ctx), do: row_for(A.ProgressionPlan, school, ctx).id |> TeacherAssistant.Curriculum.list_progression_modules!() |> List.first()
  defp row_for(A.ProgressionEntry, school, ctx) do
    m = row_for(A.ProgressionModule, school, ctx)
    {:ok, e} = TeacherAssistant.Curriculum.add_progression_entry(m, %{lesson_title: "Iso", planned_hours: Decimal.new(1), entry_type: :lesson})
    e
  end
  defp row_for(A.LessonPlan, school, ctx) do
    entry = row_for(A.ProgressionEntry, school, ctx)
    {:ok, lp} = TeacherAssistant.Curriculum.ensure_lesson_plan(entry, row_for(A.TeachingContext, school, ctx))
    lp
  end
  defp row_for(A.LessonStep, school, ctx), do: row_for(A.LessonPlan, school, ctx) |> then(&TeacherAssistant.Curriculum.add_lesson_step(&1, %{title: "Iso"})) |> elem(1)
  defp row_for(A.TeachingLogEntry, school, ctx) do
    entry = row_for(A.ProgressionEntry, school, ctx)
    {:ok, log} = TeacherAssistant.Curriculum.log_teaching(school, %{progression_entry_id: entry.id, taught_on: Date.utc_today(), hours: Decimal.new(1)})
    log
  end
```

(`plan_for_course!/1` does not exist: use `TeacherAssistant.Curriculum.list_progression_plans!(school.id) |> Enum.find(&(&1.combined_course_id == course.id))`, which Task 10 changes to `list_progression_plans!(school)` when the define loses its `workspace_id` argument. The exact attrs for `add_progression_entry/2`, `add_lesson_step/2` and `log_teaching/2` are in the domain tests converted in Task 3 — copy their calls.) Add the nine resources to `@flipped`.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for the nine resources.

- [ ] **Step 3: Implement**

Resources: multitenancy block on all nine; remove `:workspace_id` from accepts/defaults (`subject.ex:17`, `combined_course.ex:21`, `teaching_context` create, `progression_plan` creates, and the accepts Task 5 added to modules/entries/lesson plans/steps/log). `TeachingContext` reads `:owned`, `:for_workspace_year`, `:assigned_in_school`, `:for_workspace_year_teacher`, `:combinable_siblings`, `:for_class_group` drop the `workspace_id` argument/clause (keep year/teacher/class arguments). `ProgressionPlan` `:unit_plans`, `:for_workspace`, `:owned`; `ProgressionModule.:owned`, `ProgressionEntry.:owned`, `LessonStep.:owned` (already lesson-plan scoped), `TeachingLogEntry.:recent` — same treatment. Hooks inside `CombinedCourse.:combine/:split` (`combined_course.ex:73,85,134,164`) and `ProgressionPlan.:import/:apply_layout/for_course/default bucket` (`progression_plan.ex:132,166,209,215,320,330`): every nested query/changeset gets `set_tenant(changeset.tenant)` (or `query.tenant` in preparations) and loses `workspace_id:` params.

`curriculum.ex`: apply the recipe to all 72 call sites: functions with a `%Workspace{}` argument set `ws.id`; functions with a plan/entry/module/context/course struct set `struct.workspace_id`; `list_units_for_scope/1` and `resolve_assigned_context`-related reads set `scope.current_workspace.id`; the four unscoped `get_by` defines become `get_course(id, %Workspace{})` etc. implemented as `Ash.get(Resource, id, tenant: ws.id)` and their callers pass the workspace they already hold (`courses_live.ex`, `dashboard_live.ex`, `combined_course` hooks use `changeset.tenant`). `workspace.ex` `seed_catalog/3` drops `workspace_id:` (tenant set in Task 8).

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for subjects, teaching contexts, courses and progression

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: Assessment domain (Assessment, Mark)

**Files:**
- Modify: `lib/teacher_assistant/academics/{assessment,mark}.ex`, `lib/teacher_assistant/academics/mark/score_within_max.ex` (tenant on the assessment load), `lib/teacher_assistant/assessment.ex` (10 calls), `test/teacher_assistant/tenancy_isolation_test.exs`

**Interfaces:**
- Produces: `Assessment.fetch_owned_assessment(id, ws)` tenant-filtered; `Mark.:upsert_all` nested reads/creates carry `changeset.tenant` (or the generic action's `context.tenant`); `Assessment.:combined_for` / `:create_combined` likewise.

- [ ] **Step 1: Extend the failing isolation test**

```elixir
  defp row_for(A.Assessment, school, ctx) do
    tc = row_for(A.TeachingContext, school, ctx)
    seq = school |> Organization.current_academic_year() |> Organization.list_sequences() |> List.first()
    {:ok, a} = TeacherAssistant.Assessment.create_assessment(tc, seq, %{label: "Iso"})
    a
  end
  defp row_for(A.Mark, school, ctx) do
    a = row_for(A.Assessment, school, ctx)
    {:ok, tc} = TeacherAssistant.Curriculum.get_teaching_context(a.teaching_context_id, school)
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(tc.class_group_id, school)
    {:ok, _} = TeacherAssistant.Enrollment.add_student(cg, %{full_name: "Marked", sex: :f})
    [%{student: s} | _] = TeacherAssistant.Enrollment.list_roster(cg)
    :ok = TeacherAssistant.Assessment.upsert_marks(a, %{s.id => Decimal.new("12")})
    a |> TeacherAssistant.Assessment.list_marks() |> List.first()
  end
```

(Use the real `upsert_marks` name/return from `assessment.ex`.) Add both to `@flipped`.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for Assessment and Mark.

- [ ] **Step 3: Implement**

Multitenancy block on both; remove the `:workspace_id` accepts added in Task 5. `mark.ex` `:upsert_all` (`:119-149`): the `:for_assessment` read and every nested create get the action's tenant (`input.tenant` / `changeset.tenant` depending on the generic action's argument shape; Ash exposes `tenant` on the input passed to `run/3`); `assessment.ex` `:combined_for`/`:create_combined` (`:202-211`) likewise. `score_within_max.ex`: `Ash.get!(Assessment, id, tenant: changeset.tenant)`.

`lib/teacher_assistant/assessment.ex`: `create_assessment(tc, seq, attrs)` → tenant `tc.workspace_id`, drop `workspace_id:`; `list_assessments/2`, `list_marks/1`, `upsert_marks/2`, `fetch_owned_assessment/2`, the per-sequence statistics readers → tenant from the struct or workspace they receive; the unscoped `Ash.get` at `:80-94` becomes `Ash.get(Assessment, id, tenant: ws.id)` with no second query.

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for assessments and marks

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Attendance domain (Period, AttendanceEntry)

**Files:**
- Modify: `lib/teacher_assistant/academics/{period,attendance_entry}.ex`, `lib/teacher_assistant/attendance.ex` (9 calls), `lib/teacher_assistant/academics/workspace.ex` (`seed_periods/1` drops `workspace_id:`), `test/teacher_assistant/tenancy_isolation_test.exs`

**Interfaces:**
- Produces: `Attendance.list_periods/1` tenant-filtered; `AttendanceEntry.:record` no longer accepts `workspace_id`; `:record_combined_period`, `:period_roll`, `:combined_period_roll` hooks carry the tenant; `justify_day/3`, `unjustify_day/2` take the tenant from the enrollment struct they receive (bare-id variants are removed: callers pass the `%Enrollment{}` they already hold).

- [ ] **Step 1: Extend the failing isolation test**

```elixir
  defp row_for(A.Period, school, _ctx), do: school |> TeacherAssistant.Attendance.list_periods() |> List.first()
  defp row_for(A.AttendanceEntry, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(e.class_group_id, school)
    p = row_for(A.Period, school, ctx)
    {:ok, _} = TeacherAssistant.Attendance.record_period(cg, p, nil, ~D[2030-10-07], [{e.id, :absent}], nil)
    A.AttendanceEntry |> Ash.Query.filter(enrollment_id == ^e.id) |> Ash.read!(tenant: school.id) |> List.first()
  end
```

Add both to `@flipped`. Also add the bare-id cross-tenant test:

```elixir
  test "justifying an absence of school A's student from school B's scope is not found", %{a: a, b: b} = ctx do
    entry = row_for(A.AttendanceEntry, a, ctx)
    {:ok, e} = TeacherAssistant.Enrollment.fetch_owned_enrollment(entry.enrollment_id, a)
    assert {:ok, _} = TeacherAssistant.Attendance.justify_day(e, entry.date, "ok")
    assert {:error, :not_found} = TeacherAssistant.Enrollment.fetch_owned_enrollment(entry.enrollment_id, b)
  end
```

(`Enrollment.fetch_owned_enrollment/2` comes from Task 9.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for Period and AttendanceEntry.

- [ ] **Step 3: Implement**

Multitenancy block on both; `period.ex:17` and `attendance_entry.ex:56-71` drop `:workspace_id` from accepts. Hooks at `attendance_entry.ex:261-266,309,347` set the tenant from the action input. `attendance.ex`: `list_periods_for_workspace_id!/1` → `tenant:`; `build_default_periods/1` → tenant `ws.id`, drop `workspace_id:`; `record_period/6` (`:258-290`) → `set_tenant(class_group.workspace_id)` on each create, drop `workspace_id: ws_id`; `slot_for/3`, `period_roll`, `class_register`, `class_conduct`, `justify_day`, `unjustify_day`, `absences_for_day` → tenant from the class group / enrollment struct; delete the bare-id clauses (`attendance.ex:428-432` `enrollment_id/1` helper accepting a binary) and update the two LiveView callers (`register_live.ex`) to pass the `%Enrollment{}` they already have in the roster.

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for periods and attendance entries

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Timetabling domain (TimetableSlot)

**Files:**
- Modify: `lib/teacher_assistant/academics/timetable_slot.ex` (`:22-23,30-31` accepts, `:100-154` hooks), `lib/teacher_assistant/timetabling.ex` (5 calls), `test/teacher_assistant/tenancy_isolation_test.exs`

- [ ] **Step 1: Extend the failing isolation test**

```elixir
  defp row_for(A.TimetableSlot, school, ctx) do
    tc = row_for(A.TeachingContext, school, ctx)
    {:ok, cg} = TeacherAssistant.Enrollment.fetch_owned_class_group(tc.class_group_id, school)
    p = row_for(A.Period, school, ctx)
    {:ok, slot} = TeacherAssistant.Timetabling.place_slot(cg, %{day: :monday, period_id: p.id, teaching_context_id: tc.id})
    slot
  end
```

Add to `@flipped`.

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for TimetableSlot.

- [ ] **Step 3: Implement**

Multitenancy block; drop `:workspace_id` from `defaults update:` (`:22-23`, the audit's ASH-10 leak) and from `:place` accept; hooks at `:143-148,205` set the tenant from the action input. `timetabling.ex`: `place_slot/2`, `clear_slot/3`, `place_combined_slot/3`, `clear_combined_slot/3`, `class_timetable/1`, `teacher_timetable/2`, `list_for_teacher!/2` → tenant from `cg.workspace_id` / `ws.id`; the clash check query (`:60-72`) → tenant; drop `workspace_id: ws_id` params (`:273`).

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for timetable slots

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: Discipline and Fees domains

**Files:**
- Modify: `lib/teacher_assistant/academics/{sanction_entry,conduct_mark,fee_tranche,payment,fee_adjustment}.ex`, `lib/teacher_assistant/discipline.ex` (6 calls, `:295-305` bare-id helper), `lib/teacher_assistant/fees.ex` (10 calls, `:272-282` bare-id helper), `lib/teacher_assistant_web/live/school/{discipline,fees}_live.ex` (pass the `%Enrollment{}` instead of an id), `test/teacher_assistant/tenancy_isolation_test.exs`

**Interfaces:**
- Produces: `Discipline.add_sanction(%Enrollment{}, attrs, user_id)`, `set_conduct_mark(%Enrollment{}, seq, value, user_id)`, `clear_conduct_mark/2`, `list_sanctions/…`, `Fees.record_payment(%Enrollment{}, attrs, user_id)`, `set_adjustment/3`, `list_payments/1`, `student_balance/2` accept only structs (the bare-id clauses are deleted); tenant from `enrollment.workspace_id`.

- [ ] **Step 1: Extend the failing isolation test**

```elixir
  defp row_for(A.SanctionEntry, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)
    {:ok, s} = TeacherAssistant.Discipline.add_sanction(e, %{type: :warning, issued_on: ~D[2030-10-07], reason: "Iso"}, nil)
    s
  end
  defp row_for(A.ConductMark, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)
    seq = school |> Organization.current_academic_year() |> Organization.list_sequences() |> List.first()
    {:ok, m} = TeacherAssistant.Discipline.set_conduct_mark(e, seq, 15, nil)
    m
  end
  defp row_for(A.FeeTranche, school, ctx) do
    cg = row_for(A.ClassGroup, school, ctx)
    {:ok, t} = TeacherAssistant.Fees.add_tranche(cg, %{label: "T1", amount: 10_000, due_on: ~D[2030-10-01]})
    t
  end
  defp row_for(A.Payment, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)
    {:ok, p} = TeacherAssistant.Fees.record_payment(e, %{amount: 5_000, method: :cash, paid_on: ~D[2030-10-02]}, nil)
    p
  end
  defp row_for(A.FeeAdjustment, school, ctx) do
    e = row_for(A.Enrollment, school, ctx)
    {:ok, adj} = TeacherAssistant.Fees.set_adjustment(e, %{amount: -1_000, reason: "Iso"}, nil)
    adj
  end
```

(Match the real attrs from `test/teacher_assistant/academics/{sanction_entry,conduct_mark,fee_tranche,payment,fee_adjustment}_test.exs`.) Add the five to `@flipped`, plus:

```elixir
  test "a payment cannot be recorded against school A's enrollment from school B's data", %{a: a, b: b} = ctx do
    e = row_for(A.Enrollment, a, ctx)
    assert {:error, :not_found} = TeacherAssistant.Enrollment.fetch_owned_enrollment(e.id, b)
    assert {:ok, _} = TeacherAssistant.Fees.record_payment(e, %{amount: 1_000, method: :cash, paid_on: ~D[2030-10-03]}, nil)
    assert TeacherAssistant.Fees.list_payments(e) |> Enum.all?(&(&1.workspace_id == a.id))
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/teacher_assistant/tenancy_isolation_test.exs`
Expected: FAIL for the five resources.

- [ ] **Step 3: Implement**

Multitenancy block on the five; drop `:workspace_id` from `conduct_mark.ex:22,27`, `fee_adjustment.ex:21,26`, `payment.ex`, `fee_tranche.ex`, `sanction_entry.ex` accepts. `discipline.ex` and `fees.ex`: delete the `fetch_enrollment`/`enrollment_id` bare-id clauses (`discipline.ex:295-305`, `fees.ex:272-282`); every function takes the `%Enrollment{}`/`%ClassGroup{}` struct and sets `tenant: struct.workspace_id`; drop `workspace_id:` params. `discipline_live.ex` and `fees_live.ex`: where they looked up an enrollment id from the mounted roster (`fees_live.ex:170-171`, `discipline_live.ex:69-70`), pass the roster row's `%Enrollment{}` to the domain instead of its id.

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors && mix test 2>&1 | tail -2 && mix ash.codegen --check`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for discipline and fees; bare-id domain entry points removed

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: Accounts (memberships, invitations) and cleanup

**Files:**
- Modify: `lib/teacher_assistant/accounts/{school_membership,school_invitation}.ex`, `lib/teacher_assistant/accounts.ex` (22 calls), `lib/teacher_assistant/accounts/workspaces.ex`, `lib/teacher_assistant/organization.ex` (`list_workspaces_for/1`), `lib/teacher_assistant/academics/workspace.ex` (`create_head_membership/2` drops `workspace_id:`), `test/teacher_assistant/tenancy_isolation_test.exs`, `test/teacher_assistant/accounts/school_invitations_test.exs`, `docs/audits/2026-09-23-school-focus/README.md` (§10 marked executed), `docs/DESIGN.md` / `docs/PRODUCT.md` (personal workspace mentions removed)

**Interfaces:**
- Produces: `SchoolMembership` and `SchoolInvitation` multitenant with `global? true`; `Accounts.accept_invitation(token, user)` works with no tenant and creates the membership under the invitation's workspace; `Organization.list_workspaces_for/1` reads memberships with no tenant.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant/accounts/school_invitations_test.exs`:

```elixir
  test "an invitation is found by token without a tenant and accepted into its school" do
    %{workspace: school, head_user: head} = TeacherFixtures.school_fixture()
    other = TeacherFixtures.user_fixture()
    {:ok, inv} = Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    assert {:ok, ^school} = Accounts.accept_invitation(inv.token, other)
    assert {:ok, m} = Accounts.fetch_school_membership(school, other)
    assert m.workspace_id == school.id
  end

  test "a user's schools are listed without a tenant" do
    %{workspace: s1, head_user: head} = TeacherFixtures.school_fixture()
    %{workspace: s2} = TeacherFixtures.school_fixture(%{head_user: head})
    ids = head |> Organization.list_workspaces_for() |> Enum.map(& &1.id)
    assert Enum.sort(ids) == Enum.sort([s1.id, s2.id])
  end
```

Extend the isolation test with `row_for(SchoolMembership, school, _)` → the head membership (`Accounts.list_members(school) |> List.first()`) and `row_for(SchoolInvitation, school, _)` → a fresh invite; add both to a separate `@global [SchoolMembership, SchoolInvitation]` list with a test asserting the tenant-B read returns not-found but a **no-tenant** read succeeds.

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/teacher_assistant/accounts/school_invitations_test.exs test/teacher_assistant/tenancy_isolation_test.exs`
Expected: the global-read test FAILS until the block is added; the cross-tenant assertions FAIL.

- [ ] **Step 3: Implement**

Add the multitenancy block with `global? true` to both; `SchoolInvitation` identity `identity :unique_token, [:token], all_tenants?: true`; drop `:workspace_id` from `school_membership.ex:17` defaults and from the invitation create. `accounts.ex`: `invite_member(school, inviter, attrs)` → tenant `school.id`; `list_members/1`, `list_pending_invitations/1`, `fetch_school_membership/2`, `update_member_roles/…`, `update_member_status/…` (remove the `authorize?: false` at `accounts.ex:86-90`), `deactivate_member/…` → tenant `school.id`; `accept_invitation(token, user)` → `SchoolInvitation |> Ash.Query.for_read(:by_token, ...)` with **no tenant** (global), then the membership create with `tenant: invitation.workspace_id`; `Organization.list_workspaces_for/1` → `:active_for_user` read with no tenant. `workspace.ex` `create_head_membership/2` drops `workspace_id:`.

Docs: in `docs/audits/2026-09-23-school-focus/README.md` change `## 10. Multitenancy design` to `## 10. Multitenancy design (executed 2026-09-23, plan: docs/superpowers/plans/2026-09-23-schema-pass-multitenancy.md)` and §9's "Now/Schema pass" rows to "Done"; in `docs/DESIGN.md` delete the "Personal Teacher Workspace (paused)" section; in `docs/PRODUCT.md` change "is **paused**, kept in the codebase behind `teacher_personal_routes: false`" to "was removed on 2026-09-23; a future teacher mode would be a school-of-one".

- [ ] **Step 4: Final verification**

Run, in order:

```bash
mix compile --warnings-as-errors
mix ash.codegen --check
grep -rn "workspace_id: ws\|workspace_id: ws_id\|workspace_id: school.id\|accept \[.*:workspace_id" lib   # expect nothing
grep -rn "authorize?: false" lib                                                                       # expect nothing
mix test
mix precommit
```

Expected: everything clean, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: multitenancy for memberships and invitations (global reads); docs updated

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

**Phase 2 gate:** dispatch the whole-branch reviewer on Tasks 8–15 (merge-base = end of Phase 1), then finish the branch.
