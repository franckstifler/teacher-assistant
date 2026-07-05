# P2.5 — Form master (professeur principal)

**Status:** Approved design
**Date:** 2026-07-05
**Builds on:** P2.1 (school workspaces, roles, permissions), P2.2 (enrollment, class assignments), P2.3 (bulletins & statistics)

## Purpose

Let the *professeur principal* (form master / titulaire) of a class see and manage
that class's academic picture without being a school administrator. Today results,
bulletins, and the print controllers are all admin-only (Head / Vice-Principal).
This increment introduces a per-class form master with scoped read + roster-management
access, a discovery surface, and the titulaire's name on the printed bulletin.

The `:form_master` value already exists in `TeacherAssistant.Accounts.SchoolRole`
(defined in P2.1) but is wired nowhere. This increment gives it meaning — though
access derives from a foreign key, not from that role (see §3).

## Scope

In scope:

- One form master per class, assigned by an admin.
- Form master gets, **for their own class(es) only**: read access to results,
  individual bulletins, and both print routes; and roster management (enroll /
  withdraw / transfer).
- A "Mes classes" discovery section on the school dashboard.
- The form master's name printed on the bulletin (visa block) and shown on the
  results page header.

Out of scope (deferred):

- Assignments panel and coefficient editing remain **admin-only** — a form master
  cannot assign subject teachers or change coefficients.
- Marks remain owned by each subject teacher, unchanged.
- Co-form-masters, form-master history, conduct capture (later increments).

## 1. Data model

Add a nullable form master foreign key to `ClassGroup`:

- `form_master_user_id` — FK → `TeacherAssistant.Accounts.User`, `allow_nil? true`,
  `on_delete: :nilify` (a departing user must not delete classes).
- `belongs_to :form_master, User` relationship on `ClassGroup`.
- `:form_master_user_id` added to the class-group `update` accept list (set/clear).

This FK is the **single source of truth** for all form-master access. We do not
gate on the `:form_master` role in the membership list — that would require keeping
a denormalized role in sync with the FK.

Cardinality: one form master per class; a teacher may be titulaire of several classes.

Additive migration, no backfill (`mix ash.codegen p2_5_form_master` + `mix ecto.migrate`).

## 2. Assignment (admin)

On the admin class-detail page (`class_live`), a small "Professeur principal" control:

- A `<select>` listing active school members (option to clear → blank).
- Eligible = any active member of the school. A titulaire is normally a teacher,
  but we do not hard-restrict the list.
- Shown only to admins (`:if={@is_admin?}`) **and** re-checked server-side in the
  `set_form_master` handler. The target user id is validated against the socket-loaded
  member list (never a raw client id); the class is the workspace-scoped resolved class.
- Selecting the blank option clears `form_master_user_id`.

## 3. Access scoping (authz)

New permission helpers in `TeacherAssistant.Accounts.Permissions`:

```elixir
def form_master?(%Scope{current_workspace_type: :school, current_user: %{id: uid}},
      %ClassGroup{form_master_user_id: fm_id}),
    do: fm_id == uid
def form_master?(_, _), do: false

def admin_or_form_master?(scope, class_group),
    do: admin?(scope) or form_master?(scope, class_group)
```

Rewire the class-detail surfaces to gate on `admin_or_form_master?/2` **for the
resolved class**, keeping the double-gating + workspace-scoping pattern used
throughout P2.2/P2.3 (UI `:if` gate + server-side re-check in every handler;
class re-resolved via the existing workspace-scoped fetch; never trust client ids):

| Surface | Before | After |
|---|---|---|
| Class list route | `admin?` | **unchanged — admin only** |
| Class detail mount | `admin?` | `admin_or_form_master?` |
| Roster mutations (enroll / withdraw / transfer) | `admin?` | `admin_or_form_master?` |
| Assignments panel + coefficient edit | `admin?` | **unchanged — admin only** |
| Results page (`results_live`) | `admin?` | `admin_or_form_master?` |
| Individual bulletin (`bulletin_live`) | `admin?` | `admin_or_form_master?` |
| Print routes (single + whole-class) | `admin?` | `admin_or_form_master?` |

Cross-school class id or a class you are neither admin nor form master of → the
same redirects as today (`/school` or `/school/classes`).

The class-detail template must branch the **assignments panel** on `@is_admin?`
(not on the new mount gate) so a form master sees roster controls but not the
assignments/coefficient controls.

## 4. Discovery — "Mes classes"

On the school dashboard, a "Mes classes" section shown when the current user is
form master of ≥1 class in the active academic year. Lists those classes, each
linking to its class-detail page (which now branches access). Admins' existing
dashboard and classes list are unchanged. A new context function
`Academics.list_form_master_classes(workspace, user, year)` returns the classes
where `form_master_user_id == user.id` in the active year.

## 5. Bulletin display

When a class has a form master, print their name on a "Professeur principal" line
in the bulletin's visa block, for both the single and whole-class print. When
unset, the line stays blank as today. The form master name is resolved once (loaded
with the class) and threaded to the print template. The results page header also
shows the titulaire's name when set.

## 6. Testing

- **Permissions unit:** `form_master?/2` (matching/non-matching user, non-school
  scope), `admin_or_form_master?/2`.
- **Assignment:** admin sets then clears `form_master_user_id`; non-admin forged
  `set_form_master` event rejected; blank clears.
- **Scoped access (LiveView + controller):** form master can view results / bulletin
  / print for own class; is redirected from a class they are not titulaire of;
  can enroll/withdraw on own class; cannot use the assignments panel (no controls +
  forged assign/coefficient events rejected).
- **Discovery:** "Mes classes" appears for a form master with a class, absent otherwise.
- **Bulletin render:** titulaire's name appears on the printed bulletin when set;
  line blank when unset.
- **i18n / gate:** gettext extract + FR/EN msgstrs for every new msgid; `mix precommit`
  (compile --warnings-as-errors, deps.unlock --unused, format, full test) green.

## Notes / risks

- Widening the class-detail mount from `admin?` to `admin_or_form_master?` is the
  main authz change; every mutation handler must re-check, and the assignments panel
  must stay admin-branched in the template. This is the primary review focus.
- `on_delete: :nilify` on the form-master FK keeps user deletion from cascading into
  classes.
