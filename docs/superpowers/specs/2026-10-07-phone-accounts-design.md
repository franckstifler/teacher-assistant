# Phone accounts created by the school — design

Date: 2026-10-07
Status: approved in conversation, awaiting spec review

## Problem

Staff join a school today only through an email invitation (`SchoolInvitation`).
Many teachers forget which email they use, or cannot open it. The person who
manages staff should be able to create a teacher's account directly, with the
teacher's **phone number** as the sign-in identifier and a **temporary
password**, and hand both over (in person, WhatsApp, SMS).

Email invitations stay as they are.

## Decisions

| Question | Decision |
|---|---|
| Sign-in identifier | Phone number, normalised to `+237XXXXXXXXX` |
| Number already has an account (other school) | Link it to this school; never touch its password or name |
| First password | Generated temporary password, shown once, 7-day validity, change forced at first sign-in |

## 1. Accounts and sign-in

### `User` changes

- `phone` — `:string`, `allow_nil? true`, `public? true`; identity
  `:unique_phone` (Postgres treats NULLs as distinct).
- `email` — becomes `allow_nil? true`. Identity `:unique_email` unchanged.
- Validation: at least one of `email` / `phone` is present.
- `must_change_password` — `:boolean`, default `false`.
- `temporary_password_expires_at` — `:utc_datetime`, nil unless a temporary
  password is active.
- `created_in_workspace_id` — nullable reference to the workspace whose staff
  manager created the account (nil for self-registered/invited accounts).
  Used only to authorise password resets (§2).
- Migration generated with `mix ash.codegen --dev`.

### Phone normalisation

One module, `TeacherAssistant.Accounts.Phone`, with `normalize/1` returning
`{:ok, "+237XXXXXXXXX"} | {:error, :invalid}`. Accepts spaces, dots, dashes,
optional `+237` / `00237` / `237` prefix; requires 9 national digits starting
with `6` or `2`. Used by the `User` change, the head's form, and sign-in (so a
teacher may type `6 77 12 34 56`).

### Sign-in

- Add a second AshAuthentication password strategy `:phone` with
  `identity_field :phone` and the same `hashed_password_field
  :hashed_password` (one password per person, whichever identifier is used).
  No registration through this strategy (`registration_enabled? false`);
  phone accounts are created only by a school (§2). Not resettable by
  self-service.
- The sign-in action normalises the typed phone before lookup.
- Sign-in with an expired temporary password
  (`must_change_password and temporary_password_expires_at < now`) is refused
  with « Mot de passe temporaire expiré — demandez-en un nouveau à
  l'établissement ». A wrong password yields the same generic error whether
  the number exists or not.
- Sign-in page: phone form first, « ou », then the email form. Done with the
  existing `sign_in_route` `overrides` if they allow ordering and labels;
  otherwise a custom sign-in LiveView composed from AshAuthentication.Phoenix
  form components (never hand-written credential checks).
- Email password reset and magic link remain email-only and unchanged; a
  phone-only user cannot reach them (lookup is by email).

### Forced password change

- `LiveUserAuth` (where the current user is loaded) redirects every signed-in
  live session to `/account/password` while `must_change_password` is true;
  the equivalent plug guards controller routes (prints).
- `/account/password` form: new password + confirmation, via a `User`
  update action `:set_own_password` (actor must be the user). It clears
  `must_change_password` and `temporary_password_expires_at`.
- Sign-out stays reachable from that screen.

## 2. Head's side — Members page

Authorisation: same as invitations (`can_manage_staff?`), enforced by Ash
policies; the UI only hides controls.

### « Créer un compte »

Form next to « Inviter »: name (required), phone, roles, membership status.
Submits to `Accounts.add_member_by_phone(scope, attrs)`, one transaction:

1. Normalise phone → field error if invalid.
2. Active member of this school with that phone → `{:error, :already_member}`
   (« Déjà membre de l'établissement »).
3. A user with that phone exists → create or reactivate the membership with
   the same code path the invitation `:accept` uses (extract it into a shared
   function if it is inline today). Name and password untouched. Flash
   « Compte existant ajouté : *Nom* ».
4. New phone → create the user (`role: :teacher`, name, phone,
   `created_in_workspace_id`, hashed temporary password,
   `must_change_password: true`, expiry now + 7 days) and the membership.
   Return `{:ok, %{membership: m, temporary_password: pw}}`.

Concurrency: if the user insert hits `:unique_phone`, retry once as case 3.

### Temporary password

- `TeacherAssistant.Accounts.TemporaryPassword.generate/0`: two pronounceable
  4-letter words (consonant-vowel-consonant-vowel, no letters easily confused
  when dictated) + 4 digits, e.g. `kola-mabu-4827` (~38 bits). Uses `:crypto`.
- Shown once in a dialog with « Copier » and a hint to send it by WhatsApp/SMS.
  Never stored in clear, never put in a flash, URL or log.

### « Réinitialiser le mot de passe »

On a member row. Allowed only when the target user's
`created_in_workspace_id` is the current workspace and the target is not
`:admin` (policy on a `User` update action `:reset_temporary_password`).
Generates a new temporary password, sets `must_change_password` and a fresh
7-day expiry, revokes all the user's tokens (sign out everywhere), and shows
the password in the same dialog.

Linked-only accounts cannot be reset by this school; the teacher goes to the
creating school, or uses email reset if they have an email.

### Displaying people

Add `User.display_name/1` (`name`, else `email`, else formatted phone) and
replace the `name || email` patterns with it:

- `assessment.ex:481`, `layouts.ex:67`, `layouts.ex:295`
- `correction_review_live.ex:146`, `assignments_live.ex:125,139`,
  `class_live.ex:263,427,470`, `sanctions_live.ex:154`,
  `bulletins_live.ex:201`, `members_live.ex:44`,
  `timetable_print_controller.ex:42`

Members list secondary line: email if present, else formatted phone.
`admin/schools_live.ex:39`: same rule.

Code that compares emails must tolerate nil:
`accounts.ex:247` (`active_member_email?`), `school_invitation_controller.ex:16`.
`emails.ex` senders are only reached via email lookup, so unchanged.

## 3. Errors and tests

### Errors

- Invalid phone: translated field error.
- Transaction failure: nothing created, no password shown, flash
  « Impossible de créer le compte. »
- All new strings in FR + EN `.po`, no fuzzy entries left.

### Tests

- `Phone.normalize/1`: accepted formats → same value; invalid inputs rejected.
- `add_member_by_phone/2`: new account (user + membership + must change),
  existing account linked (password hash and name unchanged), already member,
  non-staff-manager refused by policy, unique-index race → linked.
- Reset: allowed for accounts created here; refused for linked accounts,
  other schools, admins; tokens revoked.
- Sign-in by phone (any typed format); expired temporary password refused;
  forced-change redirect on live and controller routes, cleared after
  `:set_own_password`; email sign-in and email reset unchanged.
- LiveView: Members « Créer un compte » → dialog shows password → row
  appears; reset button only where allowed.
- `mix precommit`.

## Out of scope

- SMS/WhatsApp delivery or OTP reset (possible later on the phone field).
- Adding an email to a phone account from the teacher's profile.
- Phone numbers outside Cameroon.
