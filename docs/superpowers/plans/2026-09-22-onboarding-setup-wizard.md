# School Onboarding Setup Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block a new school head behind a stepped setup wizard until the school has an active academic year and ≥1 class; walk them through Identity → Academic year → Classes → Invite (optional).

**Architecture:** A single `SetupWizardLive` at `/school/setup` with a 4-step progress header and per-step panels, each reusing an existing action (`create_academic_year`, `create_class_group`/`Seeding`, `invite_member`). A new `on_mount :require_school_setup` hook redirects every other school screen to the wizard until setup is complete. Progress is derived from data — no new schema.

**Tech Stack:** Elixir/OTP, Phoenix 1.8 + LiveView 1.1, Ash 3 + AshPhoenix, daisyUI/Tailwind v4 (Tableau tokens), Gettext (FR-default).

**Spec:** `docs/superpowers/specs/2026-09-22-onboarding-setup-wizard-design.md`

## Global Constraints

- Forms use `AshPhoenix.Form` with build-time `prepare_source` for server-controlled fields (`workspace_id`, `academic_year_id`, `active`) — never param-merging.
- Setup actions stay head/admin-gated via existing `Permissions.head?/1` / `admin?/1`. No authorization/policy changes.
- No new persisted onboarding state — progress derives from `scope.current_academic_year` and `Enrollment.list_class_groups(ws, year)`.
- Enums via `Ash.Type.Enum`; Gettext FR-default, all copy translatable.
- Tableau tokens only (`.ta-board`/`.ta-leaf`/`.ta-field`/`.ta-eyebrow`/`.ta-num`); no theme-color changes.
- `mix precommit` does NOT gate on warnings — verify with `mix test`.

## Layout (Tableau tokens — applies to every step)

Inside `Layouts.app`, a centered container with a 4-step progress header above a single panel:

```heex
<section id="setup-wizard" class="mx-auto max-w-3xl space-y-6">
  <.wizard_progress step={@step} />
  <div class="ta-board space-y-5 p-5 sm:p-6">
    <!-- current step's title + helper + content + actions -->
  </div>
</section>
```

`wizard_progress/1` renders four labelled markers (Identity · Academic year · Classes · Invite team); a step is `:done` (check), `:current` (accent), or `:upcoming` (muted). Numbers use `.ta-num`, labels `.ta-eyebrow`. Keep it a simple flex row with a connecting hairline (`border-base-300`); no external component required.

**Mockup fidelity (see `.superpowers/sdd/2026-09-22-onboarding-setup-wizard/mockup-layout-notes.md`):** the `Onboarding` mockup uses a **two-column** layout — left: the step's form card; right: a persistent **"Récapitulatif" checklist aside** (one row per domain: Identité/Année/Classes/Équipe(/Vérification), done-vs-todo) plus a dashed **"Bon à savoir" tip** card. Task 1 built a single-column scaffold; **Task 7** upgrades the shell to this two-column form-card + Récapitulatif aside (in Tableau tokens). The functional step tasks (3–5) build the left-column form-card content; per-step field/copy structure follows the mockup notes.

## File Structure

**Create**
- `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex` — the wizard (all steps).
- `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`
- `test/teacher_assistant_web/live/onboarding/setup_gate_test.exs`

**Modify**
- `lib/teacher_assistant/scope.ex` — add `setup_complete?/1`.
- `lib/teacher_assistant_web/live_user_auth.ex` — add `on_mount(:require_school_setup, …)`.
- `lib/teacher_assistant_web/router.ex` — add `/school/setup`; wire the gate into the `:school_workspace` session on_mount chain.
- `lib/teacher_assistant_web/live/school/dashboard_live.ex` — drop the now-unreachable `year==nil`/`classes==[]` blocking gates (keep the checklist).

---

## Task 1: Scope helper + wizard scaffold + route

**Files:**
- Modify: `lib/teacher_assistant/scope.ex`
- Create: `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route only, not the gate yet)
- Test: `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`

**Interfaces:**
- Consumes: `scope.current_academic_year`, `Enrollment.list_class_groups(ws, year)`, `scope.current_workspace`.
- Produces: `TeacherAssistant.Scope.setup_complete?(scope) :: boolean`; `SetupWizardLive` at `/school/setup` deriving `@step ∈ [:identity,:year,:classes,:invite]` from data; `wizard_progress/1` header component.

**Pre-flight:** Read `scope.ex` (`academic_year_ready?/1` to mirror), the `:school_workspace` live_session in `router.ex` (its on_mount + members), and a school LiveView (e.g. `classes_live.ex`) for the mount/scope-access pattern. Confirm `Enrollment.list_class_groups/2` arity.

- [ ] **Step 1: Write the failing test** (`setup_wizard_live_test.exs`)

```elixir
defmodule TeacherAssistantWeb.Onboarding.SetupWizardLiveTest do
  use TeacherAssistantWeb.ConnCase
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  setup %{conn: conn} do
    %{workspace: ws, head_user: head} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    %{conn: conn, ws: ws, head: head}
  end

  test "renders the wizard on the academic-year step for a fresh school", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school/setup")
    assert html =~ "setup-wizard"
    assert html =~ "Académique" or html =~ "Année"  # year step is first for a fresh school
  end
end
```

(Confirm the sign-in helper name + how `workspace_id` gets into the session from `setup_gate_test`/existing school LiveView tests during pre-flight; reuse them.)

- [ ] **Step 2: Run it, verify it fails** (module/route undefined).

- [ ] **Step 3: Add `Scope.setup_complete?/1`**

```elixir
def setup_complete?(%__MODULE__{current_workspace_type: :school} = scope) do
  year = scope.current_academic_year
  year != nil and TeacherAssistant.Enrollment.list_class_groups(scope.current_workspace, year) != []
end
def setup_complete?(_), do: true
```

(Confirm `Enrollment.list_class_groups/2` arg order in pre-flight.)

- [ ] **Step 4: Create `SetupWizardLive`** — mount assigns scope, derives `@step`, renders `wizard_progress/1` + a per-step panel (year/classes/invite panels are stubs filled by later tasks; identity is a recap):

```elixir
defmodule TeacherAssistantWeb.Onboarding.SetupWizardLive do
  use TeacherAssistantWeb, :live_view
  alias TeacherAssistant.{Organization, Enrollment}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    {:ok, assign(socket, step: initial_step(scope), ws: scope.current_workspace, year: scope.current_academic_year)}
  end

  defp initial_step(scope) do
    cond do
      scope.current_academic_year == nil -> :year
      Enrollment.list_class_groups(scope.current_workspace, scope.current_academic_year) == [] -> :classes
      true -> :invite
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="setup-wizard" class="mx-auto max-w-3xl space-y-6">
        <.wizard_progress step={@step} />
        <div class="ta-board space-y-5 p-5 sm:p-6">
          <%= case @step do %>
            <% :year -> %><.year_panel {assigns} />
            <% :classes -> %><.classes_panel {assigns} />
            <% :invite -> %><.invite_panel {assigns} />
            <% _ -> %><.identity_panel {assigns} />
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # wizard_progress/1 + step panel stubs here (panels completed in Tasks 3-5)
end
```

Include a working `wizard_progress/1` (the 4-marker header) and minimal placeholder panels so the page renders. Real panel bodies come in later tasks.

- [ ] **Step 5: Add the route** — in the `:school_workspace` live_session in `router.ex`:

```elixir
live "/school/setup", Onboarding.SetupWizardLive, :index
```

- [ ] **Step 6: Run tests, verify pass;** then `mix test`.

- [ ] **Step 7: Commit** — `feat: setup wizard scaffold + Scope.setup_complete?`

---

## Task 2: The blocking gate (on_mount)

**Files:**
- Modify: `lib/teacher_assistant_web/live_user_auth.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (wire the hook into the `:school_workspace` on_mount chain)
- Test: `test/teacher_assistant_web/live/onboarding/setup_gate_test.exs`

**Interfaces:**
- Consumes: `Scope.setup_complete?/1` (Task 1), `socket.assigns.current_scope`.
- Produces: `on_mount(:require_school_setup, params, session, socket)` that redirects incomplete school scopes to `/school/setup`.

**Pre-flight:** Read `live_user_auth.ex` fully — find the hook that assigns `current_scope` (`assign_scope/2`) and confirm it runs as/within an on_mount BEFORE where this new hook will sit. The gate MUST see `current_scope` already assigned. Determine whether to add `:require_school_setup` to the `:school_workspace` `on_mount [...]` list (after the scope hook) or chain it inside the existing hook. Confirm `SetupWizardLive`'s module name for the exemption check.

- [ ] **Step 1: Write failing gate tests**

```elixir
test "an incomplete school head is redirected from /school to the wizard", %{conn: conn} do
  %{workspace: ws, head_user: head} = school_fixture()
  conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
  assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
end

test "a complete school head reaches /school", %{conn: conn} do
  %{workspace: ws, head_user: head} = setup_complete_school_fixture()  # year + ≥1 class
  conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
  assert {:ok, _view, _html} = live(conn, ~p"/school")
end

test "the wizard route itself is not redirected", %{conn: conn} do
  %{workspace: ws, head_user: head} = school_fixture()
  conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
  assert {:ok, _view, _html} = live(conn, ~p"/school/setup")
end

test "a teacher (personal) scope is never gated", %{conn: conn} do
  user = user_fixture()
  conn = log_in_user(conn, user)
  assert {:ok, _view, _html} = live(conn, ~p"/teacher")
end
```

Add a `setup_complete_school_fixture/0` (or inline helper) that creates a school, an active year (`Organization.create_academic_year/2`) — which seeds classes — so `setup_complete?` is true. Put it in `TeacherFixtures` if reused.

- [ ] **Step 2: Run them, verify they fail** (no gate yet — the incomplete head currently reaches `/school`).

- [ ] **Step 3: Add the hook** (`live_user_auth.ex`)

```elixir
def on_mount(:require_school_setup, _params, _session, socket) do
  scope = socket.assigns.current_scope
  cond do
    scope == nil or scope.current_workspace_type != :school -> {:cont, socket}
    socket.view == TeacherAssistantWeb.Onboarding.SetupWizardLive -> {:cont, socket}
    TeacherAssistant.Scope.setup_complete?(scope) -> {:cont, socket}
    true -> {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school/setup")}
  end
end
```

(Use the module's real verified-route helper for `~p`; match how other redirects in this file are written.)

- [ ] **Step 4: Wire it into the router** — add `:require_school_setup` to the `:school_workspace` live_session's `on_mount` list, AFTER the scope-assigning hook (confirmed in pre-flight). It applies to every school LiveView incl. the wizard; the wizard is exempt via the `socket.view` check.

- [ ] **Step 5: Run tests, verify pass;** then `mix test` (watch for other school LiveView tests that now need a setup-complete school or a `workspace_id`; fix any that regressed by making their fixture setup-complete — note these in the report).

- [ ] **Step 6: Commit** — `feat: block school screens until setup complete (on_mount gate)`

---

## Task 3: Academic-year step

**Files:**
- Modify: `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- Test: `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`

**Interfaces:**
- Consumes: `Organization.create_academic_year/2`, `AcademicYear.:create_for_workspace`, `Seeding.seed_starter_classes` (runs inside the year-create call site pattern — mirror settings_live).
- Produces: `year_panel/1` + `handle_event("create_year", …)` advancing `@step` to `:classes`.

**Pre-flight:** Read `settings_live.ex` `year_form/2` (~line 624) + `handle_event("create_year", …)` (~line 373) — mirror its `AshPhoenix.Form` build (prepare_source sets `workspace_id` + `active`), submit, and the `Seeding.seed_starter_classes(ws, year)` call. Reuse that exact shape; the wizard is head-gated (the head reached it), but keep the `Permissions` check consistent with settings if present.

- [ ] **Step 1: Write the failing test**

```elixir
test "creating the academic year seeds classes and advances to the classes step", %{conn: conn, ws: ws} do
  {:ok, view, _} = live(conn, ~p"/school/setup")
  view
  |> form("#year-form", %{"academic_year" => %{"name" => "2026-2027", "start_date" => "2026-09-01", "end_date" => "2027-07-05"}})
  |> render_submit()
  assert TeacherAssistant.Organization.current_academic_year(ws) != nil
  assert render(view) =~ "classes"  # now on the classes step
end
```

(Adapt field names to the real `year_form` inputs found in pre-flight.)

- [ ] **Step 2: Run it, verify it fails.**

- [ ] **Step 3: Implement `year_panel/1`** — the year form (mirroring `settings_live` `year_form/2`: `AshPhoenix.Form.for_create(AcademicYear, :create_for_workspace, prepare_source: set workspace_id + active=true)`), a title + helper, and a "Créer l'année" submit.

- [ ] **Step 4: Implement `handle_event("create_year", …)`** — submit the form; on success call `Seeding.seed_starter_classes(ws, year)` (mirror settings), then re-derive and assign `@step` (`:classes`), reloading `@year`. On error, re-assign the form with errors.

- [ ] **Step 5: Run tests, verify pass;** then `mix test`.

- [ ] **Step 6: Commit** — `feat: wizard academic-year step`

---

## Task 4: Classes step

**Files:**
- Modify: `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- Test: `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`

**Interfaces:**
- Consumes: `Enrollment.list_class_groups/2`, `Enrollment.create_class_group/3`, `Enrollment.delete_class_group/1`, `SchoolTemplates.streams_for/2` (for série/level options).
- Produces: `classes_panel/1` + `handle_event("add_class"|"delete_class"|"continue_classes", …)`. "Continue" only advances (`@step = :invite`) when ≥1 class.

**Pre-flight:** Read `classes_live.ex` — `class_form/2` (prepare_source workspace_id + academic_year_id), the streams/levels loading (`SchoolTemplates.streams_for`), `handle_event("delete_class")` (handles `:has_data`). Mirror these. The panel lists the (usually auto-seeded) classes with add/remove.

- [ ] **Step 1: Write failing tests**

```elixir
test "continue is blocked with zero classes and enabled after adding one", %{conn: conn, ws: ws} do
  %{} = create_active_year(ws)  # year but delete seeded classes to force empty, OR use a type with no template
  {:ok, view, _} = live(conn, ~p"/school/setup")
  # on :classes step; with 0 classes, continue is disabled
  refute render(view) =~ ~s(phx-click="continue_classes") and (has enabled continue)
  view |> form("#class-form", %{"class_group" => %{"label" => "6e A", "level" => "6e"}}) |> render_submit()
  assert Enrollment.list_class_groups(ws, year) != []
end

test "continue advances to the invite step once a class exists", %{conn: conn} do
  # setup-complete-ish (year + ≥1 class); render, click continue → invite panel
end
```

(Flesh out against the real class-form field names + the enabled/disabled continue markup from pre-flight. Use a school with an empty class template, or delete the seeded classes, to exercise the 0-class branch.)

- [ ] **Step 2: Run them, verify they fail.**

- [ ] **Step 3: Implement `classes_panel/1`** — list `@classes` (label · level · série), an inline add form (mirror `class_form/2`), a delete button per row, and a "Continuer" button disabled when `@classes == []`.

- [ ] **Step 4: Implement the handlers** — `add_class` (create + reload list), `delete_class` (delete, handle `:has_data` with a flash), `continue_classes` (guard ≥1 → `@step = :invite`).

- [ ] **Step 5: Run tests, verify pass;** then `mix test`.

- [ ] **Step 6: Commit** — `feat: wizard classes step`

---

## Task 5: Identity recap + Invite step + Finish

**Files:**
- Modify: `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- Test: `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`

**Interfaces:**
- Consumes: `Accounts.invite_member/3` (`(ws, head, %{email, roles, membership_status})`), `Accounts.list_pending_invitations/1`, `Accounts.fetch_school_profile/1` (recap), `SchoolRole`/`MembershipStatus` for options.
- Produces: `identity_panel/1` (recap), `invite_panel/1` + `handle_event("invite"|"finish", …)`. "Finish" redirects to `/school`.

**Pre-flight:** Read `members_live.ex` `invite_form/0` (~line 287) + `handle_event("invite", …)` (~line 168) — mirror the form + `Accounts.invite_member(scope.current_workspace, scope.current_user, attrs)` call and the pending-list rendering. Read `Accounts.fetch_school_profile/1` for the recap fields. Do NOT link to `/school/settings` from the identity panel (it is gated → would loop).

- [ ] **Step 1: Write failing tests**

```elixir
test "inviting a teammate sends an email and lists them as pending", %{conn: conn} do
  import Swoosh.TestAssertions
  # setup-complete school so the wizard shows the invite step
  {:ok, view, _} = live(conn, ~p"/school/setup")
  view |> form("#invite-form", %{"invite" => %{"email" => "prof@example.com", "roles" => ["teacher"]}}) |> render_submit()
  assert_email_sent(fn e -> assert {_, "prof@example.com"} = hd(e.to) end)
  assert render(view) =~ "prof@example.com"
end

test "finish redirects to the dashboard", %{conn: conn} do
  # setup-complete school; on invite step; click finish
  {:ok, view, _} = live(conn, ~p"/school/setup")
  assert {:error, {:live_redirect, %{to: "/school"}}} = render_click(element(view, "#finish-setup"))
end
```

(Adapt to the real invite-form field names from pre-flight.)

- [ ] **Step 2: Run them, verify they fail.**

- [ ] **Step 3: Implement `identity_panel/1`** — a recap card of the profile (name, type, subsystem, région) from `fetch_school_profile/1`. Read-only; no link to Settings. (This panel is only reached if a head navigates back; the derived initial step is never `:identity`.)

- [ ] **Step 4: Implement `invite_panel/1`** — mirror `members_live` invite form (email + roles + employment-type select), an "Inviter" submit, a pending-invitations list, plus `#finish-setup` ("Terminer") and a "Passer pour l'instant" — both redirecting to `/school`.

- [ ] **Step 5: Implement `handle_event("invite", …)`** (call `Accounts.invite_member/3`, reload pending) and `handle_event("finish", …)` (`push_navigate` to `~p"/school"`).

- [ ] **Step 6: Run tests, verify pass;** then `mix test`.

- [ ] **Step 7: Commit** — `feat: wizard identity recap + invite step + finish`

---

## Task 6: Dashboard cleanup

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs` (adjust)

**Interfaces:**
- Consumes: the gate (Task 2) — a school reaching the dashboard is guaranteed to have year + classes.
- Produces: dashboard without the unreachable `year == nil` / `classes == []` blocking `setup_gate` branches; the completed-state checklist stays.

**Pre-flight:** Read `dashboard_live.ex` — the `setup_gate` branches (~lines 87-118) and the `#setup-checklist` (~lines 50-84). Remove ONLY the blocking `year == nil` / `classes == []` gate branches; keep the checklist (Profile/Year/Classes/Staff at-a-glance + edit links). Read `dashboard_live_test.exs` for any test asserting those gate branches — such a test now belongs to the gate (Task 2), so update/remove it here.

- [ ] **Step 1: Update the dashboard tests** — remove/adjust assertions that expected the `year==nil`/`classes==[]` blocking gates on the dashboard (those states now redirect). Keep/confirm the checklist assertions for a setup-complete school.

- [ ] **Step 2: Run them, verify the old-gate assertions fail** (or are removed) and checklist ones pass/fail appropriately.

- [ ] **Step 3: Remove the dead branches** — delete the `year == nil` and `classes == []` `<.setup_gate>` blocks; keep the checklist and the verified-state banner.

- [ ] **Step 4: Run tests, verify pass;** then `mix test`.

- [ ] **Step 5: Commit** — `refactor: drop unreachable dashboard setup gates (wizard owns setup)`

---

## Task 7: Mockup layout — two-column shell + Récapitulatif aside

**Files:**
- Modify: `lib/teacher_assistant_web/live/onboarding/setup_wizard_live.ex`
- Test: `test/teacher_assistant_web/live/onboarding/setup_wizard_live_test.exs`

**Interfaces:**
- Consumes: the four data signals (`scope.current_academic_year`, `Enrollment.list_class_groups/2`, `Accounts.fetch_school_profile/1`, staff count / pending invites) and `scope.school_verification_status`.
- Produces: the wizard render wrapped in a two-column grid — left = the current step's form card (the panels from Tasks 3–5, unchanged in content), right = a persistent `recap_aside/1` (Récapitulatif checklist: Identité/Année/Classes/Équipe/Vérification with done/todo state) + a "Bon à savoir" tip card.

**Reference:** `.superpowers/sdd/2026-09-22-onboarding-setup-wizard/mockup-layout-notes.md` for the aside's rows, copy, and arrangement. Render in Tableau tokens (`.ta-board`/`.ta-leaf`/`.ta-eyebrow`), NOT the mockup's paper palette. Keep it responsive: two columns on `lg`, single column (aside below) on mobile.

- [ ] **Step 1: Write the failing test** — assert the wizard renders the Récapitulatif aside with the four checklist rows and their done/todo state for a given data setup (e.g. year present → Année done; no classes → Classes todo).
- [ ] **Step 2: Run it, verify it fails.**
- [ ] **Step 3: Implement `recap_aside/1`** — the checklist card (rows derived from the same signals `setup_complete?`/the dashboard checklist use; `MembershipStatus`/label not needed here) + the "Bon à savoir" tip card.
- [ ] **Step 4: Wrap the render** — replace the single-column `#setup-wizard` container with a `lg:grid-cols-[minmax(0,1fr)_18rem]` grid: progress header spans the top, left column holds the `.ta-board` step panel, right column holds `recap_aside/1`. Panels' inner content is unchanged.
- [ ] **Step 5: Run tests, verify pass;** then `mix test`.
- [ ] **Step 6: Commit** — `feat: wizard two-column layout + Récapitulatif aside (mockup)`

## Self-review notes

- **Spec coverage:** gate → Task 2; wizard scaffold/progress → Task 1; year → Task 3; classes → Task 4; identity+invite+finish → Task 5; dashboard cleanup → Task 6. All spec deliverables mapped.
- **Ordering/dependencies:** Task 2 needs Task 1's `/school/setup` route (else the gate redirects to a 404). Tasks 3–5 fill panels declared in Task 1. Task 6 last (needs the gate live so the branches are truly unreachable).
- **Cross-task risk (flagged for Task 2):** adding the gate may break existing school-LiveView tests that use an incomplete school or omit `workspace_id`; Task 2 fixes those by making their fixtures setup-complete and records each change. This is the one broad-reach change — its tests pin school-only scope, wizard exemption, and the exact open condition (year + ≥1 class).
- **Framework unknowns flagged for pre-flight (not guessed):** the exact on_mount chain + scope-assign hook in `live_user_auth.ex`/router; the real field names of `year_form`/`class_form`/`invite_form`; `Enrollment.list_class_groups/2` arity; the sign-in + `workspace_id`-session test helpers.
- **No new schema, no authorization change, no verification change.** Reversible by removing the on_mount entry.
