# Operator console, school modules, suspension and password resets — design

Date: 2026-10-15
Status: approved in conversation, awaiting spec review

## Problem

The platform operator (the product owner) has one screen today, `/admin/schools`, which lists
schools awaiting verification. There is no way to:

- see every school, its staff and its activity;
- suspend a school (unpaid, abusive, left) without deleting anything;
- give a school only part of the product — every school gets every screen;
- help someone who forgot their password. Heads can reset only the phone accounts their school
  created; email users have self-service reset by email, but no production mailer is configured.
  An email user who forgets their password is stuck.

The operator role exists (`User.role == :admin`, checked by `LiveUserAuth :require_operator`) but
can only be granted from `priv/repo/seeds.exs`.

## Decisions

| Question | Decision |
|---|---|
| Who controls a school's modules | The operator only. Heads see which modules are active, read only. |
| Granularity | Six switchable modules plus an always-on core (§1). |
| Defaults | Existing schools: all six on. New schools: none; the operator enables them. |
| Password reset | Temporary password (existing mechanism). The operator may reset anyone but another operator; heads may reset any active member of their school, with the guards in §3. |
| Enforcement | A `modules` list on the school, checked at the web entry points (LiveView `on_mount`, controller plug), in menus and in background jobs — not in every Ash resource policy. |
| Suspension | Reversible operator action; members are held on a « suspended » page; nothing deleted. Separate from verification. |
| Audit | Every operator action and every password reset (operator or head) is journaled. |

## 1. Modules

### Catalogue

`TeacherAssistant.Modules` holds the catalogue as data: key, FR/EN label, the LiveViews and
controller actions it owns. Everything not listed is the always-on **core**.

| Key | Label | LiveViews / controllers |
|---|---|---|
| `:notes` | Notes et bulletins | `Teacher.RosterLive`, `Teacher.MarksLive`, `Teacher.MarksSummaryLive`, `School.ResultsLive`, `School.BulletinLive` (student bulletin), `School.BulletinsLive`, `School.CouncilsLive`, `School.CouncilLive`, `School.CorrectionsLive`, `School.CorrectionReviewLive`, `School.SequenceTrackingLive`, `School.EvaluationsLive`, `School.CoefficientsLive`, `School.AppreciationsLive`, `School.PassageLive`, `School.BulletinTemplateLive`; `BulletinPrintController`, `CouncilPrintController`, `StudentPhotoController :frozen` |
| `:appel` | Appel et absences | `School.AttendanceLive`, `School.RegisterLive`, `School.DayLive`, `School.AbsencesLive` |
| `:discipline` | Discipline | `School.DisciplineLive`, `School.ConductLive`, `School.SanctionsLive`, `School.SchoolLifeSettingsLive` |
| `:emploi_du_temps` | Emploi du temps | `School.TimetableLive`, `School.TimetableEditorLive`, `School.MyTimetableLive`; `TimetablePrintController` |
| `:frais` | Frais de scolarité | `School.FeesLive` |
| `:photos` | Photos et cartes | `School.ClassPhotosLive`; `CardPrintController` |

**Core** (always on): dashboard, courses, classes and class page, teachings, students and student
profile, enrolment import, members, settings (profile, year, subjects, header, roles, holidays,
assignments, new year), years, periods (the bell schedule both `:appel` and `:emploi_du_temps`
use), notifications, setup wizard, Ma journée (`School.MyDayLive`), logo and student photo
(`StudentPhotoController :show`).

`BulletinVerifyController` (`/verify/bulletin/:token`) is public and never gated: printed bulletins
must stay verifiable whatever the issuing school's modules or status.

The exact LiveView → module map lives in `TeacherAssistant.Modules` and is the single source for
every check below. Names above are checked against `router.ex` during planning.

### Storage

- `Workspace.modules` — `{:array, TeacherAssistant.Modules.Key}` (an `Ash.Type.Enum` of the six
  keys), `allow_nil? false`, default `[]`.
- Migration: existing workspaces set to all six keys.
- `:create_school` does not accept `modules`, so new schools start with `[]`.
- New update action `:set_modules` (accepts `modules`), policy: operator only. Journaled (§4).

### Enforcement

- **Scope.** `Scope.module?(scope, key)` reads `scope.current_workspace.modules` (already loaded
  with the scope; no extra query). True for any key when there is no workspace (operator pages).
- **LiveViews.** New `on_mount {LiveUserAuth, :require_module}` in the `:teaching` and
  `:school_workspace` live sessions. It looks up `socket.view` in the catalogue; when the module is
  off it halts with `push_navigate` to `/school` and the flash « Ce module n'est pas activé pour
  votre établissement. »
- **Controllers.** New plug `TeacherAssistantWeb.Plug.RequireModule` on the school controller
  routes, same lookup by `{controller, action}`, redirect + flash on refusal.
- **Menus.** `Spaces` drops menu items whose target belongs to an off module, and computes
  badge counts (`counts/2`, `facts/1`) only for enabled modules.
- **Shared screens.** Screens that span modules hide the off module's parts rather than fail:
  - class page: no Résultats / Appel / Discipline / Emploi du temps / Frais / Photos tabs for
    off modules;
  - bulletin print: no absence block without `:appel`, no conduct/sanction block without
    `:discipline`;
  - student profile: no discipline section without `:discipline`;
  - Ma journée and dashboards: no roll-call, marks or timetable cards for off modules.
- **Jobs.** `Workers.MissedRollCalls` skips schools without `:appel`.
- **Heads.** `School.SettingsLive` shows a read-only « Modules » card listing active modules and
  « Contactez l'administrateur pour en activer d'autres. »

### Guard test

A test walks `TeacherAssistantWeb.Router.__routes__()` and asserts every `/school` and `/teacher`
route's LiveView or `{controller, action}` is either in the core list or mapped to a module, so a
new screen cannot escape the switch silently.

## 2. Suspension

- `Workspace.suspended_at` (`:utc_datetime`, nullable) and `Workspace.suspension_reason`
  (`:string`, nullable).
- Actions `:suspend` (argument `reason`, required, trimmed, max 500) and `:reactivate` (clears
  both). Policy: operator only. Both journaled.
- `Scope.suspended?(scope)` from the loaded workspace.
- New `on_mount {LiveUserAuth, :require_active_school}` in the `:teaching` and `:school_workspace`
  sessions, and the same check in the school controller plug: a suspended school's members go to
  `/school/suspended`, a page (outside those sessions, user required) showing « Établissement
  suspendu », the reason, and that they should contact the administrator. From there they can
  switch to another school they belong to, or sign out.
- Nothing is deleted. Reactivating restores everything as it was.
- Jobs skip suspended schools (`MissedRollCalls`; `ExpiredTemporaryPasswords` too, since it
  notifies the school's heads).
- `BulletinVerifyController` keeps working for suspended schools.
- The operator keeps full access to a suspended school in the console.
- Suspension and verification are independent: a school may be verified and suspended.

## 3. Password resets

The existing `User :reset_temporary_password` action stays as it is: 7-day temporary password,
clear value returned once in metadata, change forced at next sign-in, all sessions revoked by
`Accounts.reset_member_password/2`. `AuthController` already refuses an expired temporary password
for every strategy, email included, and `Plug.RequirePasswordChange` applies to every user.

### Policy (in this order)

1. `forbid_if expr(role == :admin)` — never an operator's account.
2. `authorize_if actor_attribute_equals(:role, :admin)` — the operator may reset anyone else.
3. `forbid_if expr(id == ^actor(:id))` — never yourself.
4. `forbid_if Checks.ActiveInAnotherSchool` — someone active in another school is reset only by
   the operator (unchanged guard).
5. `forbid_if Checks.HeadOfActingSchool` (new; target holds the `:head` axis in the school the
   actor is acting in) — a head never resets another head.
6. `authorize_if Checks.HeadOfMembersSchool` (new; actor is an active head of the school they are
   acting in, and the target is an active member of that school).

`create_by_school` keeps `HeadOfCreatingSchool`.

### Screens

- **Members page (heads).** The reset button already uses `Accounts.can_reset_member_password?/2`;
  it now appears for every member the policy allows. Confirm modal and one-time display unchanged.
- **Operator.** `Accounts.operator_reset_password(scope, user)` (same steps as
  `reset_member_password/2`, without a membership) used by `/admin/users` and the school detail
  page: confirm modal, then the password shown once with a copy button and a ready-to-send text:
  « Votre mot de passe temporaire Teacher Assistant : XXXX. Il est valable 7 jours ; vous en
  choisirez un nouveau à la connexion. »

### Journal

Every reset, by the operator or a head, writes `password_reset` (§4) with actor, target and
school. The password is never stored or logged.

## 4. Audit journal

New resource `TeacherAssistant.Accounts.AuditEvent` (table `audit_events`), **not** multitenant
(operator events span schools):

| Field | Type |
|---|---|
| `id` | uuid v7 |
| `actor_user_id` | uuid, reference to users, `on_delete: :nilify` |
| `action` | enum `school_verified`, `school_rejected`, `school_suspended`, `school_reactivated`, `modules_changed`, `password_reset` |
| `workspace_id` | uuid, nullable, reference, `on_delete: :delete` |
| `target_user_id` | uuid, nullable, reference to users, `on_delete: :nilify` |
| `details` | map (`%{before: [...], after: [...]}` for modules, `%{reason: ...}` for suspend/reject) |
| `inserted_at` | utc_datetime_usec |

- Written by a shared change (`AuditEvent.Record`, `after_action`) on the journaled actions, in
  the same transaction. A failed journal write fails the action.
- Actions: `:record` (create, internal — called with `authorize?: false` from the change),
  `:read` with filters by workspace and by action. No update, no destroy.
- Read policy: operator only.
- Indexes: `(inserted_at)`, `(workspace_id, inserted_at)`.

## 5. Operator console

All pages in the existing `:operator` live session (`require_operator`), rendered in
`Layouts.app`. The rail shows an « Administration » group (Vue d'ensemble, Établissements,
Utilisateurs, Journal) to operators only.

### `/admin` — Vue d'ensemble

- Schools by status: à vérifier, vérifiés, rejetés, suspendus (each links to the filtered list).
- Totals: active memberships, students enrolled in an active year.
- Last 7 days, all schools: roll calls taken (attendance entries), marks entered (mark events).
- The 10 latest audit events.

Counts are read with `authorize?: false` inside a dedicated `TeacherAssistant.Operator` domain
module, called only from operator pages; every function asserts the actor is an operator.

### `/admin/schools` — Établissements

Search by name or town; filters: verification status, suspended, module. Row: name, type ·
subsystem · region · town, owner contact, verification badge, suspended badge, module chips,
created date. The current verification queue is the « À vérifier » filter (replaces today's page).

### `/admin/schools/:id` — one school

- Profile summary.
- Verify / reject (moved from today's list, same actions).
- Suspend (reason required) / reactivate.
- Modules: one checkbox per module, « Enregistrer » → `:set_modules`.
- Counts: classes, students, staff; last activity (latest attendance entry or mark event).
- Members: name, roles, phone/email, last temporary-password state, reset button.
- This school's audit events.

### `/admin/users` — Utilisateurs

Search across all users by name, phone (normalised with `Accounts.Phone`) or email; result: name,
contact, schools and roles, temporary-password state, reset button (§3). Operators are listed but
cannot be reset.

### `/admin/journal` — Journal

The audit journal, newest first, filter by action and school, paginated by 50.

### Making an operator

`mix teacher_assistant.make_operator <email|phone>` runs `User :promote_to_admin` (with
`authorize?: false`, as a release-time admin task). Seeds unchanged.

## 6. Testing

- Catalogue guard: every `/school` and `/teacher` route is core or mapped (§1).
- Module guard: a LiveView and a print route of an off module refuse a typed URL; menus drop the
  items; Spaces counts are skipped; the class page hides the tabs.
- New school has no modules; existing schools have all six after migration.
- Suspension: member redirected to `/school/suspended`, a member of two schools still works in the
  other; jobs skip; bulletin verification still works; reactivation restores access.
- Reset policy, one test per rule: operator resets a head and a teacher; operator cannot reset an
  operator; head resets an email member and a phone member of their school; head cannot reset
  themself, another head, a member active in another school, or a member of another school.
- Audit rows written for each journaled action, with details; non-operators cannot read them.
- Each admin page renders for an operator and redirects a non-operator.
- `make_operator` task promotes by email and by phone.

## Out of scope

- Several operator roles or support staff with partial rights.
- Billing, invoices, plan names or per-module pricing.
- Sending the temporary password by SMS or email (needs a provider; the console gives a text to
  paste).
- Module enforcement inside Ash resource policies (revisit if a public API is added).
- Impersonating a user.
- Deleting a school or a user.
