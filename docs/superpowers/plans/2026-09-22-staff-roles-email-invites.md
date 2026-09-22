# Staff & roles (B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing invitation/membership flow real end-to-end: emails actually send, an invitee can accept without an account, and employment type is captured and shown.

**Architecture:** Three independent slices on one branch. Slice 1 adds a Swoosh `Mailer` + email builders and rewires the stub senders. Slice 2 branches the public accept page on auth state and reuses the existing session `return_to`. Slice 3 adds an employment-type field to the invitation, carries it onto the membership, and surfaces it in the head-gated members UI. Authorization is unchanged.

**Tech Stack:** Elixir/OTP, Phoenix 1.8 + LiveView 1.1, Ash 3 + AshPostgres + AshPhoenix + AshAuthentication, Swoosh 1.16, Gettext (FR-default), daisyUI/Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-09-22-staff-roles-email-invites-design.md`

## Global Constraints

- Resources use `Ash.Type.Enum` (never bare `:atom`). Forms use `AshPhoenix.Form` with build-time `prepare_source` for server-controlled fields (never param-merging).
- Ash resources keep the house `policy always() -> authorize_if always()`; context modules call `Ash.*(authorize?: false)`. **No authorization behavior changes in this increment** (that is roadmap C).
- Every mutating staff action stays head-gated via `Accounts.Permissions.head?/1`, exactly as today.
- All user-facing copy (incl. email subjects/bodies) is translatable via the project's Gettext backend; FR is the default locale.
- `mix precommit` does NOT gate on warnings — verify each task with `mix test` (and targeted test runs).
- The accept email-match boundary stays server-side in `Accounts.accept_invitation/2` (`:email_mismatch`); UI never weakens it.
- `return_to` is only ever set to an app-controlled invite path (no open-redirect).

## File Structure

**Create**
- `lib/teacher_assistant/mailer.ex` — Swoosh mailer.
- `lib/teacher_assistant/accounts/emails.ex` — `Swoosh.Email` builders (invitation, password reset, magic link).
- `priv/repo/migrations/<ts>_add_membership_status_to_school_invitations.exs`
- `priv/resource_snapshots/repo/school_invitations/<ts>.json`
- `test/teacher_assistant/accounts/emails_test.exs`
- Fixtures: `school_fixture/1`, `membership_fixture/2` in `test/support/fixtures/teacher_fixtures.ex`.

**Modify**
- `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex`
- `lib/teacher_assistant/accounts/user/senders/send_password_reset_email.ex`
- `lib/teacher_assistant/accounts/user/senders/send_magic_link_email.ex`
- `lib/teacher_assistant/accounts/school_invitation.ex`
- `lib/teacher_assistant/accounts.ex`
- `lib/teacher_assistant_web/router.ex`
- `lib/teacher_assistant_web/controllers/school_invitation_controller.ex`
- `lib/teacher_assistant_web/controllers/school_invitation_html/show.html.heex`
- `lib/teacher_assistant_web/live/school/members_live.ex`
- `config/config.exs`
- Tests: `school_invitations_test.exs`, `school_invitation_controller_test.exs`, `members_live_test.exs`

---

## Task 1: Mailer module + email builders

**Files:**
- Create: `lib/teacher_assistant/mailer.ex`
- Create: `lib/teacher_assistant/accounts/emails.ex`
- Modify: `config/config.exs` (add `from` for `Emails`)
- Test: `test/teacher_assistant/accounts/emails_test.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Mailer` (`use Swoosh.Mailer, otp_app: :teacher_assistant`); `TeacherAssistant.Accounts.Emails.school_invitation(email, school_name, accept_url) :: Swoosh.Email`, `.password_reset(user, reset_url)`, `.magic_link(user, magic_url)`. Each sets `from` from config, a non-empty subject, and puts the URL in both text and HTML bodies.

**Pre-flight:** Confirm the project's Gettext backend module name (grep `use Gettext` / `defmodule *.Gettext`) and use it in `Emails`. Confirm the `from` config key style matches the rest of `config/config.exs`.

- [ ] **Step 1: Write the failing test** — `test/teacher_assistant/accounts/emails_test.exs`

```elixir
defmodule TeacherAssistant.Accounts.EmailsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Emails

  test "school_invitation/3 addresses the invitee, sets from + subject, embeds the URL" do
    url = "http://localhost:4000/schools/invitations/tok123"
    email = Emails.school_invitation("prof@example.com", "Lycée de Test", url)

    assert {_, "prof@example.com"} = hd(email.to)
    assert {_name, _addr} = email.from
    assert email.subject not in [nil, ""]
    assert email.text_body =~ url
    assert email.html_body =~ url
  end

  test "password_reset/2 embeds the reset URL" do
    user = %{email: "u@example.com"}
    email = Emails.password_reset(user, "http://localhost:4000/reset/abc")
    assert email.text_body =~ "http://localhost:4000/reset/abc"
  end
end
```

- [ ] **Step 2: Run the test, verify it fails** — `mix test test/teacher_assistant/accounts/emails_test.exs` → fails (module undefined).

- [ ] **Step 3: Create the Mailer**

```elixir
defmodule TeacherAssistant.Mailer do
  use Swoosh.Mailer, otp_app: :teacher_assistant
end
```

- [ ] **Step 4: Create the Emails builder** — `lib/teacher_assistant/accounts/emails.ex`

```elixir
defmodule TeacherAssistant.Accounts.Emails do
  @moduledoc "Builds Swoosh emails for account/invitation flows. Delivery is via TeacherAssistant.Mailer."
  import Swoosh.Email
  # Use the project's Gettext backend (confirm the module in pre-flight):
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def school_invitation(email, school_name, accept_url) do
    base()
    |> to(to_string(email))
    |> subject(gettext("Invitation à rejoindre %{school}", school: school_name))
    |> text_body(
      gettext(
        "Vous avez été invité(e) à rejoindre %{school} sur Teacher Assistant.\n\nAcceptez l'invitation ici : %{url}",
        school: school_name,
        url: accept_url
      )
    )
    |> html_body(
      gettext(
        "<p>Vous avez été invité(e) à rejoindre <strong>%{school}</strong>.</p><p><a href=\"%{url}\">Accepter l'invitation</a></p>",
        school: school_name,
        url: accept_url
      )
    )
  end

  def password_reset(user, reset_url) do
    base()
    |> to(to_string(user.email))
    |> subject(gettext("Réinitialisation de votre mot de passe"))
    |> text_body(gettext("Réinitialisez votre mot de passe ici : %{url}", url: reset_url))
    |> html_body(gettext("<p><a href=\"%{url}\">Réinitialiser mon mot de passe</a></p>", url: reset_url))
  end

  def magic_link(user, magic_url) do
    base()
    |> to(to_string(user.email))
    |> subject(gettext("Votre lien de connexion"))
    |> text_body(gettext("Connectez-vous ici : %{url}", url: magic_url))
    |> html_body(gettext("<p><a href=\"%{url}\">Se connecter</a></p>", url: magic_url))
  end

  defp base do
    new() |> from(from_address())
  end

  defp from_address do
    Application.get_env(:teacher_assistant, __MODULE__)[:from] ||
      {"Teacher Assistant", "no-reply@teacherassistant.cm"}
  end
end
```

- [ ] **Step 5: Add `from` config** — in `config/config.exs`, near the existing `TeacherAssistant.Mailer` config:

```elixir
config :teacher_assistant, TeacherAssistant.Accounts.Emails,
  from: {"Teacher Assistant", "no-reply@teacherassistant.cm"}
```

- [ ] **Step 6: Run the test, verify it passes** — `mix test test/teacher_assistant/accounts/emails_test.exs`.

- [ ] **Step 7: Commit** — `git add ... && git commit -m "feat: Mailer + Accounts.Emails builders"`

---

## Task 2: Deliver the invitation email + dev mailbox + fixtures

**Files:**
- Modify: `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (dev mailbox forward)
- Modify: `test/support/fixtures/teacher_fixtures.ex` (add `school_fixture/1`, `membership_fixture/2`)
- Test: `test/teacher_assistant/accounts/school_invitations_test.exs` (add delivery assertion)

**Interfaces:**
- Consumes: `TeacherAssistant.Mailer`, `Accounts.Emails.school_invitation/3` (Task 1).
- Produces: `SendSchoolInvitationEmail.send(email, school_name, token)` now builds + delivers (signature unchanged; `Accounts.invite_member/3` already calls it). Fixtures: `TeacherAssistant.TeacherFixtures.school_fixture(attrs \\ %{})` returns `%{workspace, head_user}` (via `Organization.create_school/2`); `membership_fixture(workspace, attrs)` returns a `SchoolMembership`.

**Pre-flight:** Read `send_school_invitation_email.ex` for the current arg order + how it composes the accept path. Confirm the accept URL: `TeacherAssistantWeb.Endpoint.url() <> ~p"/schools/invitations/#{token}"`. Check `test.exs` uses `Swoosh.Adapters.Test`.

- [ ] **Step 1: Add fixtures** (needed by the delivery test and later tasks). In `teacher_fixtures.ex`:

```elixir
def school_fixture(attrs \\ %{}) do
  user = attrs[:head_user] || user_fixture()
  name = attrs[:name] || "Lycée #{System.unique_integer([:positive])}"
  {:ok, workspace} = TeacherAssistant.Organization.create_school(user, %{name: name})
  %{workspace: workspace, head_user: user}
end

def membership_fixture(workspace, attrs \\ %{}) do
  user = attrs[:user] || user_fixture()
  roles = attrs[:roles] || [:teacher]
  {:ok, m} =
    TeacherAssistant.Accounts.SchoolMembership
    |> Ash.Changeset.for_create(:create, %{
      workspace_id: workspace.id,
      user_id: user.id,
      roles: roles,
      status: attrs[:status],
      active: true
    })
    |> Ash.create(authorize?: false)
  m
end
```

- [ ] **Step 2: Write the failing delivery test** — in `school_invitations_test.exs`, add `import Swoosh.TestAssertions` and:

```elixir
test "invite_member delivers an email to the invited address with the accept link" do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = TeacherAssistant.Accounts.invite_member(head, ws, %{email: "new@example.com", roles: [:teacher]})

  assert_email_sent(fn email ->
    assert {_, "new@example.com"} = hd(email.to)
    assert email.text_body =~ inv.token
  end)
end
```

(Confirm the real `invite_member/3` arity/shape in pre-flight; adapt the call to match.)

- [ ] **Step 3: Run the test, verify it fails** — the stub sends nothing, so `assert_email_sent` fails.

- [ ] **Step 4: Rewire the sender**

```elixir
defmodule TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail do
  @moduledoc "Delivers the school invitation email."
  alias TeacherAssistant.{Mailer, Accounts.Emails}
  use TeacherAssistantWeb, :verified_routes

  def send(email, school_name, token) do
    accept_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/schools/invitations/#{token}"

    email
    |> Emails.school_invitation(school_name, accept_url)
    |> Mailer.deliver()

    :ok
  end
end
```

(Match the existing arg names/order exactly from pre-flight.)

- [ ] **Step 5: Add the dev mailbox route** — inside the existing `if Application.compile_env(:teacher_assistant, :dev_routes)` block in `router.ex`:

```elixir
scope "/dev" do
  pipe_through :browser
  forward "/mailbox", Plug.Swoosh.MailboxPreview
end
```

(If a `/dev` dev-routes scope already exists, add the `forward` there instead of a second scope.)

- [ ] **Step 6: Run the tests** — `mix test test/teacher_assistant/accounts/school_invitations_test.exs` → pass. Then `mix test` to confirm nothing else broke.

- [ ] **Step 7: Commit** — `feat: deliver school invitation email + dev mailbox + fixtures`

---

## Task 3: Deliver password-reset & magic-link emails

**Files:**
- Modify: `lib/teacher_assistant/accounts/user/senders/send_password_reset_email.ex`
- Modify: `lib/teacher_assistant/accounts/user/senders/send_magic_link_email.ex`
- Test: add to `test/teacher_assistant/accounts/` (new `senders_test.exs` or extend an existing accounts test)

**Interfaces:**
- Consumes: `Mailer`, `Emails.password_reset/2`, `Emails.magic_link/2`.
- Produces: both `AshAuthentication.Sender` modules build + deliver instead of returning `:ok` no-op.

**Pre-flight:** These are `use AshAuthentication.Sender`; read both for their exact `send/3` signature (`send(user_or_email, token, opts)`). **Find the reset route path** in `router.ex` (the `reset_route`/token live route) and the magic-link path, so the URLs are correct. Confirm whether `send` receives a `user` struct or an email string for each.

- [ ] **Step 1: Write the failing test** — trigger a password reset request and assert an email is sent:

```elixir
test "requesting a password reset delivers an email with a reset link" do
  user = user_fixture()  # confirm fixture creates a known email
  # Trigger the reset request action (confirm the action name in pre-flight,
  # e.g. Accounts request_password_reset / the AshAuthentication reset request).
  ...
  assert_email_sent(fn email ->
    assert {_, ^user_email} = hd(email.to)
    assert email.text_body =~ "/reset"
  end)
end
```

Resolve the exact reset-request entry point during pre-flight (AshAuthentication password `resettable` request action); if triggering it in a unit test is impractical, instead unit-test the sender module directly by calling `send/3` with a token and asserting delivery.

- [ ] **Step 2: Run the test, verify it fails.**

- [ ] **Step 3: Rewire `SendPasswordResetEmail`**

```elixir
defmodule TeacherAssistant.Accounts.User.Senders.SendPasswordResetEmail do
  use AshAuthentication.Sender
  use TeacherAssistantWeb, :verified_routes
  alias TeacherAssistant.{Mailer, Accounts.Emails}

  @impl true
  def send(user, token, _opts) do
    reset_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/reset/#{token}"  # confirm path
    user |> Emails.password_reset(reset_url) |> Mailer.deliver()
    :ok
  end
end
```

- [ ] **Step 4: Rewire `SendMagicLinkEmail`** analogously (build via `Emails.magic_link/2`, deliver). Use the correct magic-link path from pre-flight.

- [ ] **Step 5: Run the tests, verify they pass.**

- [ ] **Step 6: Commit** — `feat: deliver password-reset and magic-link emails`

---

## Task 4: Accept-with-signup (public accept page branching)

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/school_invitation_controller.ex`
- Modify: `lib/teacher_assistant_web/controllers/school_invitation_html/show.html.heex`
- Test: `test/teacher_assistant_web/controllers/school_invitation_controller_test.exs`

**Interfaces:**
- Consumes: existing `Accounts.accept_invitation/2` (`:email_mismatch` boundary), `AuthController.success/4` (honors session `:return_to`), fixtures from Task 2.
- Produces: `show/2` renders three auth-state branches and, when signed out, sets `put_session(conn, :return_to, ~p"/schools/invitations/#{token}")`.

**Pre-flight:** Read the current `show/2` + `show.html.heex` (it already computes `email_match?` and passes `current_user`). Read how `current_user`/session `user_id` is resolved in this controller. Confirm the `/register` and `/sign-in` route paths.

- [ ] **Step 1: Write failing controller tests** — the three branches:

```elixir
test "signed-out visitor is offered register + sign-in and return_to is set", %{conn: conn} do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = Accounts.invite_member(head, ws, %{email: "new@example.com", roles: [:teacher]})

  conn = get(conn, ~p"/schools/invitations/#{inv.token}")
  html = html_response(conn, 200)
  assert html =~ ~p"/register"
  assert html =~ ~p"/sign-in"
  assert get_session(conn, :return_to) == ~p"/schools/invitations/#{inv.token}"
end

test "signed-in matching user sees a Join action", %{conn: conn} do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = Accounts.invite_member(head, ws, %{email: "match@example.com", roles: [:teacher]})
  user = user_fixture(email: "match@example.com")
  conn = conn |> log_in_user(user) |> get(~p"/schools/invitations/#{inv.token}")
  assert html_response(conn, 200) =~ "phx-submit" or html_response(conn, 200) =~ "accept"
end

test "signed-in mismatched user is told to sign out", %{conn: conn} do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = Accounts.invite_member(head, ws, %{email: "match@example.com", roles: [:teacher]})
  other = user_fixture(email: "other@example.com")
  conn = conn |> log_in_user(other) |> get(~p"/schools/invitations/#{inv.token}")
  html = html_response(conn, 200)
  refute html =~ ~p"/schools/invitations/#{inv.token}/accept"
end
```

(Confirm the sign-in test helper name — `log_in_user` or the project's equivalent — in pre-flight; the existing controller test file will show it.)

- [ ] **Step 2: Run the tests, verify they fail.**

- [ ] **Step 3: Update `show/2`** to set `return_to` when signed out and pass an `auth_state` assign (`:match | :mismatch | :signed_out`) to the template:

```elixir
def show(conn, %{"token" => token}) do
  # ... existing invitation lookup ...
  current_user = current_user(conn)

  {auth_state, conn} =
    cond do
      is_nil(current_user) ->
        {:signed_out, put_session(conn, :return_to, ~p"/schools/invitations/#{token}")}

      email_match?(current_user, invitation) ->
        {:match, conn}

      true ->
        {:mismatch, conn}
    end

  render(conn, :show, invitation: invitation, current_user: current_user, auth_state: auth_state, token: token)
end
```

- [ ] **Step 4: Rewrite `show.html.heex`** with the three branches: `:match` → the existing Join `<.form ... action=accept>`; `:mismatch` → a message naming `@invitation.email`; `:signed_out` → two links (`~p"/register"`, `~p"/sign-in"`) with FR copy. Use Tableau/daisyUI classes consistent with the auth pages.

- [ ] **Step 5: Run the tests, verify they pass;** then `mix test` broadly.

- [ ] **Step 6: Add an integration test** (register-from-invite): a signed-out visitor whose session has `return_to` set, after `create_user` + `store_in_session`, lands on the invite page and Join creates the membership with the invited roles. (Drive it at the controller level using the auth session helper; assert `Accounts.fetch_school_membership/2` returns the member with `[:teacher]` and the invitation is `:accepted`.)

- [ ] **Step 7: Commit** — `feat: accept invitation with register/sign-in (return_to)`

---

## Task 5: Carry employment type through invite → membership

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_invitation.ex` (add `membership_status`)
- Modify: `lib/teacher_assistant/accounts.ex` (`invite_member/3`, `accept_invitation/2`, new `update_member_status/2`)
- Create: migration + resource snapshot
- Test: `test/teacher_assistant/accounts/school_invitations_test.exs`

**Interfaces:**
- Consumes: `Accounts.MembershipStatus` enum (`:titulaire|:contractuel|:vacataire`), fixtures.
- Produces: `SchoolInvitation.membership_status :: MembershipStatus` (nullable, in `create` accept-list). `Accounts.invite_member/3` accepts an optional employment type and stores it. `Accounts.accept_invitation/2` copies it onto `SchoolMembership.status`. `Accounts.update_member_status/2` (membership, status) updates a member's employment type (mirrors `update_member_roles/2`, `authorize?: false`).

**Pre-flight:** Read `school_invitation.ex` (attributes + `create` accept list), `accounts.ex` `invite_member/3` and `accept_invitation/2`, and `update_member_roles/2` (to mirror it). Confirm the enum module path `TeacherAssistant.Accounts.MembershipStatus`.

- [ ] **Step 1: Write failing tests**

```elixir
test "invite with employment type carries onto the membership on accept" do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = Accounts.invite_member(head, ws, %{email: "t@example.com", roles: [:teacher], membership_status: :contractuel})
  assert inv.membership_status == :contractuel

  user = user_fixture(email: "t@example.com")
  {:ok, _ws} = Accounts.accept_invitation(user, inv.token)
  {:ok, m} = Accounts.fetch_school_membership(ws, user)
  assert m.status == :contractuel
end

test "invite without employment type leaves membership status nil" do
  %{workspace: ws, head_user: head} = school_fixture()
  {:ok, inv} = Accounts.invite_member(head, ws, %{email: "u@example.com", roles: [:teacher]})
  user = user_fixture(email: "u@example.com")
  {:ok, _} = Accounts.accept_invitation(user, inv.token)
  {:ok, m} = Accounts.fetch_school_membership(ws, user)
  assert m.status == nil
end

test "update_member_status changes a member's employment type" do
  %{workspace: ws} = school_fixture()
  m = membership_fixture(ws, roles: [:teacher])
  {:ok, m2} = Accounts.update_member_status(m, :titulaire)
  assert m2.status == :titulaire
end
```

- [ ] **Step 2: Run the tests, verify they fail.**

- [ ] **Step 3: Add the attribute** to `SchoolInvitation` (nullable) and add `:membership_status` to the `create` action accept list.

- [ ] **Step 4: Generate the migration + snapshot** — `mix ash_postgres.generate_migrations add_membership_status_to_school_invitations` (confirm the exact mix task the repo uses; check existing migration commits). Review the generated migration (single nullable column, no backfill).

- [ ] **Step 5: Wire the domain functions** — `invite_member/3` writes `membership_status` from its attrs; `accept_invitation/2` sets `status: inv.membership_status` when creating the membership; add `update_member_status/2` mirroring `update_member_roles/2`.

- [ ] **Step 6: Migrate + run tests** — `mix ecto.migrate` then `mix test test/teacher_assistant/accounts/school_invitations_test.exs`; then `mix test`.

- [ ] **Step 7: Commit** — `feat: carry employment type from invitation onto membership`

---

## Task 6: Employment type in the members UI

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/members_live.ex`
- Test: `test/teacher_assistant_web/live/school/members_live_test.exs`

**Interfaces:**
- Consumes: `Accounts.MembershipStatus` (`values/0`, `label/1`), `Accounts.invite_member/3` (now takes employment type), `Accounts.update_member_status/2` (Task 5).
- Produces: invite form has an employment-type select; members table shows the real status + a head-only inline editor.

**Pre-flight:** Read `members_live.ex` — the invite form (`invite` event), the role-checkbox pattern (`set_roles`), the members table (the hardcoded "Actif" cell), and how head-gating wraps events (`Permissions.head?/1`). Mirror the existing patterns exactly.

- [ ] **Step 1: Write failing LiveView tests**

```elixir
test "head can set a member's employment type", %{conn: conn} do
  # build school, head, a member; log in as head; render /school/members
  # trigger the employment-type change event; assert the row now shows the label
end

test "non-head cannot change employment type", %{conn: conn} do
  # log in as a non-head member; assert the control is absent / event refused
end

test "invite form includes the employment-type options" do
  # assert the rendered invite form contains the MembershipStatus labels
end
```

(Flesh these out against the existing `members_live_test.exs` patterns found in pre-flight — reuse its setup/log-in helpers.)

- [ ] **Step 2: Run the tests, verify they fail.**

- [ ] **Step 3: Add the invite-form select** — `MembershipStatus.values()` → `{label, value}` options, blank allowed; pass the chosen value into the `invite` event's call to `Accounts.invite_member/3`.

- [ ] **Step 4: Replace the hardcoded status cell** — show `MembershipStatus.label(m.status)` (em-dash when nil); add a head-only inline editor (select or menu) firing an event that calls `Accounts.update_member_status/2`, guarded by `Permissions.head?/1` like the other mutating events.

- [ ] **Step 5: Run the tests, verify they pass;** then `mix test`.

- [ ] **Step 6: Commit** — `feat: surface + edit employment type in members UI`

---

## Self-review notes

- **Spec coverage:** Slice 1 → Tasks 1–3; Slice 2 → Task 4; Slice 3 → Tasks 5–6. Fixtures (spec gap) added in Task 2. All spec deliverables mapped.
- **Type consistency:** `membership_status` (invitation) is distinct from `status :: InvitationStatus` (also on the invitation) and maps onto `SchoolMembership.status :: MembershipStatus`. `update_member_status/2` mirrors the existing `update_member_roles/2` shape.
- **Framework unknowns flagged for pre-flight rather than guessed:** Gettext backend module, exact reset/magic-link route paths, `invite_member/3` real arity, the sign-in test helper name, and the repo's migration-generation mix task. Each task's pre-flight resolves its own before code.
- **No authorization change** anywhere; head-gating reused verbatim.
