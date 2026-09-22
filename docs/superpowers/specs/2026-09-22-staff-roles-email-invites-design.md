# Staff & roles (B): real email delivery, accept-with-signup, employment type

**Status:** Design / spec — awaiting user review
**Date:** 2026-09-22
**Increment:** Roadmap item **B — Staff & roles** (see `project-school-workspace-reposition` memory)
**Branch:** `feat/staff-roles-email-invites`

## Overview

Staff, memberships, roles, and invitations already exist as a working v1 in the
`Accounts` domain (resources, orchestration, and a head-gated `MembersLive`).
This increment closes the **three concrete gaps** that keep the flow from being
real end-to-end, and nothing more:

1. **Email actually sends.** Today there is no `Mailer` and every sender is a
   `:ok`/`Logger.debug` stub, so invitations (and password resets) are silently
   dropped.
2. **You can accept an invite without an account.** Today `accept` requires an
   already-signed-in user whose email matches; there is no register-from-invite
   or sign-in-from-invite path.
3. **Employment type is captured and shown.** The `MembershipStatus` enum
   (`:titulaire | :contractuel | :vacataire`) exists but is ignored by the invite
   form and members table.

**Explicitly out of scope (→ roadmap C):** replacing the imperative
`Accounts.Permissions.*` checks with Ash policies, a capability matrix, route
guards, or any delegation model. This increment leaves authorization exactly as
it is.

## Goals / non-goals

**Goals**
- An invited email address receives a real, bilingual (FR-default) invitation
  email with a working accept link, viewable in dev via a mailbox preview.
- A person with no account can follow an invite link, create an account (or sign
  in), and land inside the school as a member with the invited roles.
- The head can set an employee's employment type when inviting, and edit it
  afterward; the members table shows the real status.
- The password-reset and magic-link emails (features whose UI already ships)
  actually send, now that a `Mailer` exists.

**Non-goals**
- No production email provider is chosen or configured (deferred; dev uses the
  Swoosh Local mailbox, test uses the Swoosh Test adapter).
- No change to who is allowed to do what (authorization stays imperative).
- No new role values, no delegation, no policy rework.

## Global constraints

- Elixir/Ash house patterns: resources use `Ash.Type.Enum` (never bare `:atom`);
  forms use `AshPhoenix.Form` with build-time `prepare_source` for
  server-controlled fields (never param-merging); Ash resources keep the
  `policy always() -> authorize_if always()` house pattern and context modules
  call `Ash.*(authorize?: false)` until C lands.
- Gettext FR-default; all user-facing copy (incl. email bodies) is translatable.
- `mix precommit` does **not** gate on warnings — verify with `mix test`.
- Every mutating staff action stays head-gated exactly as today
  (`Accounts.Permissions.head?/1`), unchanged.

## Current state (verified)

- `Accounts.SchoolMembership` — `roles :: {:array, SchoolRole}`,
  `status :: MembershipStatus` (nullable, unused), `active`, last-head guard via
  the `other_active_heads` aggregate + domain wrappers
  (`Accounts.update_member_roles/2`, `deactivate_member/1`).
- `Accounts.SchoolInvitation` — `email`, `roles`, `status :: InvitationStatus`
  (`:pending|:accepted|:revoked`), `token`, `expires_at`. Orchestrated by
  `Accounts.invite_member/3`, `accept_invitation/2` (enforces email match →
  `:email_mismatch`), `revoke_invitation`, `list_pending_invitations/1`.
- `SendSchoolInvitationEmail` — stub: `Logger.debug` then `:ok`. Signature
  `(email, school_name, token)`. Its accept link is `/schools/invitations/<token>`.
- Auth — AshAuthentication password strategy on `Accounts.User`
  (`register_with_password`, exposed as `Accounts.create_user`), `resettable`,
  hidden magic-link. `AuthController.success/4` redirects to
  `get_session(conn, :return_to) || ~p"/teacher"`. `PageController` already sets
  `put_session(:return_to, ~p"/schools/new")` for `/schools/start` — the pattern
  this increment reuses.
- `SchoolInvitationController` — `show` (renders accept page, computes
  `email_match?`, `current_user`), `accept` (POST; requires signed-in matching
  user). Public routes at `GET/POST /schools/invitations/:token[/accept]`.
- `School.MembersLive` at `/school/members` — head-gated invite form + role
  checkboxes + pending list w/ revoke; status column hardcoded to "Actif".
- Mailer/config — `swoosh ~> 1.16` dep; config points at
  `TeacherAssistant.Mailer` (Local dev / Test test) but **the module does not
  exist**. No `Swoosh.Email` is built anywhere.

---

## Slice 1 — Real email delivery

**Deliverable:** invitation, password-reset, and magic-link emails are built as
real `Swoosh.Email` structs and delivered through a `Mailer`; dev shows them at
`/dev/mailbox`; test asserts them via the Swoosh Test adapter.

### Components
- **`TeacherAssistant.Mailer`** — `use Swoosh.Mailer, otp_app: :teacher_assistant`.
  Config already references it; no config change needed for dev/test.
- **`TeacherAssistant.Accounts.Emails`** — pure builders returning `Swoosh.Email`:
  - `school_invitation(email, school_name, accept_url)`
  - `password_reset(user, reset_url)`
  - `magic_link(user, magic_url)` (magic-link is hidden in the UI but the sender
    exists; wiring it keeps senders consistent)
  Each sets `from` from config, a bilingual subject + text/HTML body, and the
  absolute URL. FR-default copy via Gettext.
- **`from` config** — add `config :teacher_assistant, TeacherAssistant.Accounts.Emails,
  from: {"Teacher Assistant", "no-reply@teacherassistant.cm"}` (dev/test value;
  prod value chosen when a provider is picked).
- **URL building** — absolute links via `TeacherAssistantWeb.Endpoint.url()` +
  the verified-route path (`/schools/invitations/<token>` for invites; the
  `reset_route` path for resets). Senders receive only a token/user, so the
  builder composes the full URL.
- **Rewire senders** (each currently a stub):
  - `SendSchoolInvitationEmail.send/3` → build via `Emails.school_invitation/3`
    and `Mailer.deliver/1`. Signature unchanged (`invite_member` already calls it).
  - `SendPasswordResetEmail` (`AshAuthentication.Sender`) → build + deliver.
  - `SendMagicLinkEmail` (`AshAuthentication.Sender`) → build + deliver.
- **Dev mailbox** — in the `dev_routes` block of `router.ex`, mount
  `forward "/dev/mailbox", Plug.Swoosh.MailboxPreview` (ships with Swoosh).
  Confirm the Local storage process is available (Swoosh starts it; add to the
  supervision tree only if a boot check shows it missing).

### Testing (Swoosh Test adapter)
- `invite_member` delivers exactly one email to the invited address whose body
  contains the accept URL with the invitation token.
- Password-reset request delivers one email to the user containing the reset URL.
- `Accounts.Emails` builders set `from`, a non-empty subject, and the exact URL
  (unit tests, no delivery).
- `use Swoosh` test helpers with `assert_email_sent/1`.

---

## Slice 2 — Accept-with-signup

**Deliverable:** a signed-out visitor can accept an invite by creating an account
or signing in, and ends up a member; a signed-in visitor sees the right action
for whether their email matches.

### Approach (reuses existing `return_to`, no custom signup form)
The app already funnels post-auth redirects through the session `:return_to` that
`AuthController.success/4` honors. This increment reuses it rather than building a
bespoke registration form (a deliberate simplification from the initial sketch;
the email-match guarantee stays server-side via `accept_invitation`'s
`:email_mismatch`).

`SchoolInvitationController.show/2` branches on auth state (page copy per branch):

| Visitor state | UI shown |
|---|---|
| Signed in, email matches | **"Join {school}"** button → POST `accept` (existing path) |
| Signed in, email differs | Message: this invite is for `x@…`; sign out to accept as that address. No join button. |
| Not signed in | Two actions: **Create account & join** and **Sign in & join** |

- When rendering the signed-out branch, `show` stashes the invite path in the
  session: `put_session(:return_to, ~p"/schools/invitations/#{token}")`. The two
  actions are plain links to `~p"/register"` and `~p"/sign-in"`. After the user
  authenticates, `AuthController.success` returns them to the invite page.
- Back on the invite page, now signed in: if the email matches they get the
  **Join** button; one click POSTs `accept` (idempotent — creates the membership
  if absent, marks the invitation accepted) and redirects into the school. If the
  freshly-created account used a different email, they get the mismatch message
  (server-side truth), so no invalid membership can be created.
- **Email pre-fill** on `/register` is best-effort only (nice-to-have); the
  security boundary is `accept_invitation`, not the form. If pre-fill needs an
  auth override, it can be a follow-up — it is not required for correctness.

### Testing (controller + conn)
- Signed-out visitor to `show` → page offers register + sign-in and sets
  `return_to` to the invite path.
- Register-then-return with the invited email → Join → membership exists with the
  invited roles; invitation is `:accepted`.
- Sign-in-then-return (existing user, matching email) → Join → member.
- Signed-in, mismatched email → mismatch message, no membership, `accept` refuses
  with `:email_mismatch`.
- Expired/revoked token → the existing not-acceptable handling still holds.

---

## Slice 3 — Employment type surfaced

**Deliverable:** employment type is captured at invite time, carried onto the
membership at accept, and editable afterward; the members table shows it.

### Data model
- Add `membership_status :: MembershipStatus` (nullable) to
  `Accounts.SchoolInvitation` (accepted by `create`). Named `membership_status`
  to avoid colliding with the invitation's own `status :: InvitationStatus`.
  Migration + resource snapshot.
- `Accounts.invite_member/3` accepts an optional employment type and writes it to
  the invitation.
- `Accounts.accept_invitation/2` copies `invitation.membership_status` onto the
  created `SchoolMembership.status`.

### UI (`School.MembersLive`, head-gated as today)
- Invite form: add an employment-type `select`
  (`MembershipStatus.values()` + bilingual `label/1`; blank allowed).
- Members table: replace the hardcoded "Actif" with the real `status`
  (via `MembershipStatus.label/1`, em-dash when nil) and a head-only inline editor
  that calls a new domain wrapper `Accounts.update_member_status/2` (mirrors
  `update_member_roles/2`; no policy change).

### Testing
- `invite_member` with an employment type stores it on the invitation; `accept`
  carries it onto the membership.
- `invite_member` without one → membership status nil (renders em-dash).
- `MembersLive`: head can change a member's employment type; non-head cannot
  (event refused, unchanged gating).
- Enum label rendering (FR) for each value.

---

## Files (map)

**Create**
- `lib/teacher_assistant/mailer.ex`
- `lib/teacher_assistant/accounts/emails.ex`
- `priv/repo/migrations/<ts>_add_membership_status_to_invitations.exs`
- `priv/resource_snapshots/repo/school_invitations/<ts>.json`
- `test/teacher_assistant/accounts/emails_test.exs`
- `test/support/fixtures/` — add `school_fixture/1` + `membership_fixture/2`
  (the map found none exist; several new tests need them)

**Modify**
- `lib/teacher_assistant/accounts/user/senders/send_school_invitation_email.ex`
- `lib/teacher_assistant/accounts/user/senders/send_password_reset_email.ex`
- `lib/teacher_assistant/accounts/user/senders/send_magic_link_email.ex`
- `lib/teacher_assistant/accounts/school_invitation.ex` (add `membership_status`)
- `lib/teacher_assistant/accounts.ex` (`invite_member/3` arg; `accept_invitation/2`
  carry-through; new `update_member_status/2`)
- `lib/teacher_assistant_web/router.ex` (dev mailbox forward)
- `lib/teacher_assistant_web/controllers/school_invitation_controller.ex`
  (`show` branching + `return_to`)
- `lib/teacher_assistant_web/controllers/school_invitation_html/show.html.heex`
  (three-branch accept UI)
- `lib/teacher_assistant_web/live/school/members_live.ex` (employment type)
- `config/config.exs` (Emails `from`)
- Tests: `school_invitations_test.exs`, `school_invitation_controller_test.exs`,
  `members_live_test.exs`

## Security / safety notes
- The accept email-match boundary is unchanged and remains server-side
  (`accept_invitation` → `:email_mismatch`); the signed-out UI never weakens it.
- Invitation tokens stay single-use-ish via status + 14-day expiry (unchanged).
- `return_to` is only ever set to the invite path this app controls; it is not
  taken from user input (no open-redirect surface).
- No authorization behavior changes; all head-gating stays as-is.

## Rollout
- New migration adds one nullable column — safe, no backfill.
- Dev/test email adapters need no credentials. Production provider is a separate,
  later step (a single config change + choosing an adapter); until then prod would
  use the Local adapter (emails not actually sent), which is acceptable because no
  production deployment depends on this yet.
