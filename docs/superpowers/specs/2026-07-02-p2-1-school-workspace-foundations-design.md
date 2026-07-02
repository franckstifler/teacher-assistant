# P2.1 — School layer foundations: workspace, membership, roles, invitations — Design

> Design spec. Written 2026-07-02. First sub-project of **Phase 2 (the school layer)**, per
> [`docs/PRODUCT.md`](../../PRODUCT.md) Phase 2 and [`docs/domain/05-school-roles-and-fees.md`](../../domain/05-school-roles-and-fees.md).
> Deliverable = spec first; no code until the plan is approved.

## 0. Premise & phase decomposition

Phase 2 turns the independent-teacher product into a school-aware one. It is too large for one spec,
so it is decomposed into four sub-projects with a dependency chain **P2.1 → P2.2 → {P2.3, P2.4}**:

- **P2.1 (this spec) — Foundations:** polymorphic workspace (personal | school), school membership +
  roles + status, teacher↔school email invitations, scope/switcher support, coarse role gating.
- **P2.2 — School enrollment & shared classes** (school academic year, classes with série, student
  enrollment + matricule unique).
- **P2.3 — Official bulletins & statistics** (cross-subject moyenne générale, Conseil de Classe
  decisions, printed bulletin).
- **P2.4 — Fees, tranches & access control** (fee types, multi-tranche schedules, audited gating).

P2.1 builds the on-ramp everything else needs and **changes no Phase-1 behavior**. A school workspace
in P2.1 is deliberately thin: members, invitations, settings, and a stub dashboard — no academic data
yet (that is P2.2).

Grounding decisions (confirmed in brainstorm):
- **Workspace model = unified polymorphic `Workspace`** (not an additive second FK). Polymorphism is
  quarantined to scope resolution; academic queries stay a flat `workspace_id == ^ws_id`.
- **Coarse role gating** only (head?/member?/bursar? helpers); the fine-grained
  pedagogical/disciplinary/financial matrix arrives with the features it protects (P2.3/P2.4).
- **Email invitations** (school invites teacher), keyed by email so they survive account creation.
- Roles are **multi-valued** per membership (the decree has people wearing several hats).

## 1. Scope

**In scope:** unified `Workspace` (rename of `PersonalWorkspace`); `SchoolMembership`;
`SchoolInvitation` + email + accept flow; four `Ash.Type.Enum`s; `Scope`/`Workspaces.scope_for`
branching by workspace kind; the workspace switcher listing personal + schools and a "Create a school"
action; a thin school shell (Members · Settings · stub dashboard) with Head-only gating; a coarse
`Permissions` helper; bilingual FR/EN.

**Out of scope (later sub-projects):** school academic years/classes/enrollment/matricule (P2.2);
bulletins/statistics (P2.3); fees/access control (P2.4); the fine-grained permission matrix;
teacher-initiated join requests; in-app notifications.

## 2. Data model

New/changed resources follow existing `Academics`/`Accounts` patterns (`AshPostgres`,
`policy always()`, `uuid_v7_primary_key`, `timestamps()`). Enums are dedicated `Ash.Type.Enum`
modules (never bare `:atom`), matching `TeacherAssistant.Academics.Sex`.

### 2.1 `Workspace` (generalize `PersonalWorkspace`)

Rename module `TeacherAssistant.Academics.PersonalWorkspace` → `Workspace`, table
`personal_workspaces` → `workspaces`.

| Attribute | Type | Notes |
|---|---|---|
| `kind` | `WorkspaceKind` enum (`:personal | :school`) | `allow_nil? false` |
| `name` | `:string`, `allow_nil? false` | personal defaults to "Espace personnel"; school = its name |
| `owner_user_id` | FK → User, **nil-able** | set for `:personal`, nil for `:school` |

- Identity `unique_owner_user` on `[:owner_user_id]` stays (Postgres excludes NULLs, so many schools
  with nil owner coexist while a user still has exactly one personal workspace).
- `has_many :school_memberships` (used for `:school` kind).
- **FK rename:** the 5 academic resources referencing `personal_workspace_id`
  (`academic_year`, `class_group`, `teaching_context`, `progression_plan`, `teaching_log_entry`)
  change their `belongs_to`/`source_attribute` to **`workspace_id`**.

### 2.2 `SchoolMembership`

| Attribute | Type | Notes |
|---|---|---|
| `workspace_id` | FK → Workspace (a school) | `allow_nil? false` |
| `user_id` | FK → User | `allow_nil? false` |
| `roles` | `{:array, SchoolRole}` | ≥1 role; a member may hold several |
| `status` | `MembershipStatus` enum, nil-able | `:titulaire | :contractuel | :vacataire` |
| `active` | `:boolean`, default `true` | deactivation instead of hard delete |

Identity `unique_member` on `[:workspace_id, :user_id]`.

### 2.3 `SchoolInvitation`

| Attribute | Type | Notes |
|---|---|---|
| `workspace_id` | FK → Workspace (a school) | `allow_nil? false` |
| `email` | `:ci_string`, `allow_nil? false` | keyed by email; survives account creation |
| `roles` | `{:array, SchoolRole}` | roles the invitee will receive |
| `invited_by_user_id` | FK → User | audit |
| `status` | `InvitationStatus` enum | `:pending | :accepted | :revoked` |
| `token` | `:string`, `allow_nil? false` | random, single-use; unique index |
| `expires_at` | `:utc_datetime` | e.g. +14 days |

### 2.4 Enums (`Ash.Type.Enum` modules under `TeacherAssistant.Accounts`)

- `WorkspaceKind` — `[:personal, :school]`
- `SchoolRole` — `[:head, :vice_principal, :discipline_master, :bursar, :hod, :form_master,
  :teacher, :guidance_counsellor, :librarian]` (Décret 2001/041, doc 05 §1)
- `MembershipStatus` — `[:titulaire, :contractuel, :vacataire]`
- `InvitationStatus` — `[:pending, :accepted, :revoked]`

FR/EN labels for `SchoolRole`/`MembershipStatus` live in a small `SchoolRoles` reference helper
(bilingual, via gettext), mirroring the `Reference` module — labels are display concerns, not stored.

## 3. Context API (`TeacherAssistant.Accounts`)

A new `Accounts.Schools` context module (school/membership logic lives in `Accounts` alongside users
and workspaces, separate from `Academics`):

- `create_school(user, %{name})` → creates `Workspace{kind: :school}` + `SchoolMembership{user,
  roles: [:head]}`; returns the workspace. Creator becomes Head.
- `list_workspaces_for(user)` → the user's one personal workspace + every school where they have an
  `active` membership (for the switcher).
- `fetch_school_membership(workspace, user)` → active membership or `:error` (drives scope).
- `list_members(school)` / `list_pending_invitations(school)`.
- `invite_member(school, inviter, %{email, roles})` → `{:ok, invitation}` + enqueues the email; rejects
  an email already an active member.
- `accept_invitation(token, user)` → validates status `:pending`, not expired, and
  `user.email == invitation.email`; creates the membership, flips to `:accepted`; returns the school.
  Idempotent no-op with a reason on already-accepted/expired/revoked/mismatch.
- `revoke_invitation(invitation)` → `:revoked`.
- `update_member_roles(membership, roles)` / `deactivate_member(membership)` — with **last-Head
  protection**: refuse to remove the `:head` role from, or deactivate, the school's only remaining Head.

Ownership/authorization for these calls is checked against the caller's scope (Head-only mutations),
see §5.

## 4. Scope & workspace switching

- **`Scope`** gains `current_roles` (list; schools) and `current_membership` (schools);
  `current_workspace_type` becomes `:personal_teacher | :school`. Personal scopes are unchanged
  (`current_role: :teacher`, `current_roles: [:teacher]`).
- **`Workspaces.scope_for/3`** branches on the resolved workspace's `kind`:
  - `:personal` → existing owner check; academic year/context resolved as today.
  - `:school` → `Accounts.Schools.fetch_school_membership(ws, user)`; if none → `{:error,
    :not_a_member}`. Set `current_roles` from the membership. `current_academic_year` and
    `current_context` are `nil` in P2.1 (school academic structure is P2.2).
- Academic `fetch_owned_*` helpers are **unchanged** — they filter `workspace_id == ^ws_id`; the
  access decision was made at resolution.
- **Switcher:** `WorkspaceController.select/:id` + `session.workspace_id` already drive selection.
  Extend the top-bar switcher to list `list_workspaces_for(user)` (personal + schools), each labelled;
  schools carry a small "École" chip. Selecting a school sets `session.workspace_id`. **Guard:** if the
  session points at a school the user is no longer an active member of, `scope_for` fails and the app
  falls back to the personal workspace (clears the stale session id).
- **"Create a school"** action in the switcher → `create_school/2` → switches into the new school.

## 5. UI surface & coarse role gating

The app shell (`layouts.ex`) adapts to `current_workspace_type`:

- **Personal:** the existing teacher nav (Dashboard · Log · Import · per-class tabs) — unchanged.
- **School:** nav shows **Members**, **Settings** (Head only), and a **stub dashboard** ("Classes &
  enrollment coming next" — the P2.2 hook). The switcher label shows the school name + "École" chip.
- **Members page** (`/school/members`, LiveView): active-members table (Nom · Rôles · Statut ·
  actions) using the Tableau kit (`page_header`, responsive table, `empty_state`); the "Invite staff"
  form (email + role checkboxes, Head only); the pending-invitations list with revoke (Head only);
  role-edit / deactivate per member (Head only, last-Head-protected).
- **Settings page** (`/school/settings`, Head only): edit the school name.
- **Invitation accept page** (`/schools/invitations/:token`): the join screen (existing user, matching
  email) or a clear rejection (mismatch/expired/revoked); a not-signed-in visitor is routed through
  registration (magic-link infra) and returns to the token.
- **Coarse gating** — `TeacherAssistant.Accounts.Permissions` reads the scope: `head?/1`, `member?/1`,
  `bursar?/1` (bursar unused in P2.1 but seeds the financial axis). Enforced at LiveView mount
  (school-only / head-only pages redirect a non-member / non-head to the school dashboard or
  `/teacher`) **and** in templates (hide Head-only controls). The three permission **axes**
  (pedagogical / disciplinary / financial) are documented in `Permissions` as a comment; only coarse
  role checks are implemented in P2.1.
- **Empty-academic guard:** the personal-only teacher pages (roster/marks/fiche/setup) are not in the
  school nav; typed while in a school scope, they redirect to the school dashboard (a school has no
  academic year in P2.1).

## 6. Migration

The one heavy step — its own first plan task with its own review gate:

- Generalize `PersonalWorkspace` → `Workspace` (add `kind`, keep/relax `owner_user_id` to nil-able,
  add nothing else beyond `name`), rename table `personal_workspaces` → `workspaces` and the
  `personal_workspace_id` FK → `workspace_id` across the 5 academic resources; backfill existing rows
  to `kind: :personal`. Generated via `mix ash.codegen`.
- New tables: `school_memberships`, `school_invitations`; four enum types.
- The rename is mechanical: `ensure_personal_workspace!/1` (finds/creates the user's `kind: :personal`
  workspace) and `scope_for` preserve the personal path. **All existing 150 tests stay green.**

## 7. Testing

- **Resource/context:** workspace kinds; membership uniqueness + roles list; invitation lifecycle
  (pending → accepted / revoked / expired); `create_school` makes the creator Head; last-Head
  protection on role-removal and deactivation; `invite_member` rejects an existing active member.
- **Scope:** personal path unchanged; school resolution via active membership; `:not_a_member`
  rejection; removed-member switch → personal fallback.
- **Invitation flow:** email enqueued on invite; accept-as-existing-user creates the membership;
  email-mismatch / expired / revoked rejected; token single-use.
- **LiveView:** members page (Head sees invite/revoke/role-edit; non-Head does not); settings Head-only
  gate; school stub dashboard; switcher lists personal + schools; "Create a school" flow; typed
  personal-only URL under a school scope redirects.
- Bilingual FR/EN for all new strings (extracted + FR filled in the final task); `mix precommit` green.

## 8. Definition of done

- A user creates a school (becoming Head) **or** accepts an email invitation to one, switches into it
  via the existing switcher, and sees the thin school shell (Members · Settings · stub dashboard) with
  Head-only controls gated.
- The personal workspace and **all Phase-1 features are unaffected** (150 tests green through the
  rename).
- The workspace abstraction is unified so P2.2 can hang school classes/enrollment off `workspace_id`.

## 9. Guardrails

Unchanged from prior phases: Tableau kit, no new colors/fonts; stable DOM ids; bilingual FR/EN;
`Ash.Type.Enum` for every enum (never bare `:atom`); mobile-first; deterministic (no AI); every change
behind test selectors. Role catalog and labels come from **Décret 2001/041** (doc 05 §1); no fee,
enrollment, or bulletin logic leaks into P2.1.
