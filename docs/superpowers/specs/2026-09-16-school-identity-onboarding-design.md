# School Identity & Onboarding — Design (School Workspace, Increment 1)

*Date: 2026-09-16 · Status: approved design, pending spec review → plan*

## Context

The product is repositioning around the **school workspace** as the primary product
(previously teacher-first). Today the school side is Phase-2 scaffolding: a school is a
`Academics.Workspace` with `kind: :school` whose **only attribute is `name`**; ownership is
implicit (a single `:head` membership, no `owner_user_id`, no transaction on creation); there is
no verification concept; creation is an inline name field in the header dropdown; and there are no
real authorization policies (`authorize?: false` throughout).

This is **Increment 1** of a five-increment build-out:

1. **School identity & onboarding (this spec)**
2. Staff & roles (invite/email/accept-with-signup, employment type, delegation, role model)
3. Permissions & authorization hardening (capability matrix, real Ash policies, school-scope route guard)
4. School settings & configuration (grading scale, term structure, year CRUD, archive/transfer/delete)
5. Dashboard & navigation (role-aware nav, admin dashboard)

Domain grounding: `docs/domain/01-education-system.md` (school types, subsystems, sectors,
regions, calendar).

## Goals

- Give a school a real, Cameroon-appropriate **identity** (profile), stored cleanly.
- Establish **ownership** (a founding head) with **atomic creation** (no orphan schools).
- Introduce **verification**: a school is created **unverified**; the head may **configure**
  everything but **operating features are locked** until an operator verifies it
  ("set up now, go live on approval").
- Replace the dropdown name-field with a real **self-serve creation → onboarding** flow.
- Provide an **in-app operator screen** (global `:admin`) to verify/reject schools.

## Non-goals (deferred to later increments)

- Staff invitation email delivery, accept-with-signup, employment-type UI, role delegation (Inc 2).
- Real Ash policies replacing `authorize?: false`; school-scope `on_mount` route guard (Inc 3).
- Grading scale, term structure, year CRUD, ownership **transfer**, archive/delete school (Inc 4).
- Role-aware nav, admin dashboard widgets (Inc 5).
- Applying the identity to the **report-card header** (consumes these fields; lands with Inc 4/5).
- Object-storage for logos (local dir now; migrate later).
- A fuller operator console (list is minimal in Inc 1).

## Key decisions (from brainstorm)

| Decision | Choice | Rationale |
|---|---|---|
| Where school attributes live | **Dedicated `SchoolProfile` resource, 1:1 with the school workspace** | Keeps `Workspace` a lean tenant/identity anchor; isolates school concerns; gives the school its own resource to attach real policies to in Inc 3. |
| Ownership field | `owner_user_id` **on `SchoolProfile`** (not `Workspace`) | `Workspace` has a `unique_owner_user` identity enforcing one *personal* workspace per user; reusing it for schools would forbid owning both a personal workspace and a school. |
| Onboarding model | **Self-serve + verification** | Heads self-create; a school is limited until the operator approves it. |
| What "unverified" limits | **Setup yes, operating no** | Configure freely (profile, year, classes, staff); marks/attendance/bulletins locked until verified. |
| Verifier | **In-app operator screen**, gated to the global `:admin` user role | Self-contained; operator becomes `:admin` via seed/console in Inc 1. |
| Logo storage | **Local uploads dir** (LiveView upload → configured dir; DB stores reference) | Simplest on a single server; swap to object storage later. |
| Optional fields | **All included**: logo, motto, registration number, department | Per product owner. |
| Creation form scope | **Identity essentials at creation** (name, type, subsystem, sector, region, town); rest in Settings | Avoids a wall of fields up front while capturing identity. |

## Data model

### New resource: `TeacherAssistant.Accounts.SchoolProfile`

`AshPostgres` resource in the **Accounts** domain, table `school_profiles`, 1:1 with the school
workspace.

**Relationships**
- `belongs_to :workspace, Academics.Workspace` — `source_attribute :workspace_id`, `allow_nil? false`.
  Identity `unique_workspace` on `workspace_id` enforces the 1:1.
- `belongs_to :owner_user, Accounts.User` — `source_attribute :owner_user_id`, `allow_nil? false`.
- `belongs_to :verified_by, Accounts.User` — `source_attribute :verified_by_user_id`, `allow_nil? true`.

**Identity attributes**
| Field | Type | Nullable | Notes |
|---|---|---|---|
| `short_name` | string | yes | Acronym (e.g. "GBHS Molyko"); full official name stays on `Workspace.name`. |
| `school_type` | `SchoolType` enum | no | Lycée / CES-CEG / Lycée Technique / CETIC / GSS / GHS / GBSS / GBHS / GTC / GTHS / SAR-SM. Encodes cycle. |
| `subsystem` | `SchoolSubsystem` enum | no | `:francophone` / `:anglophone` / `:bilingual`. **Distinct** from the class-level `Subsystem` (which has no `:bilingual`). |
| `sector` | `SchoolSector` enum | no | `:public` / `:private_lay` / `:private_confessional` / `:community`. |
| `region` | `CameroonRegion` enum | no | The 10 regions. |
| `department` | string | yes | Finer than region + town. |
| `town` | string | no | |
| `phone` | string | yes | |
| `email` | string | yes | |
| `address` | string | yes | |
| `head_name` | string | yes | Chef d'établissement / Principal, for document headers. |
| `motto` | string | yes | School devise (national "Paix – Travail – Patrie" is constant, not stored). |
| `registration_number` | string | yes | Matricule / arrêté d'ouverture. |
| `logo_path` | string | yes | Reference to the uploaded file (see Logo storage). |

**Verification attributes**
| Field | Type | Nullable | Notes |
|---|---|---|---|
| `verification_status` | `SchoolVerificationStatus` enum | no | `:unverified` (default) / `:verified` / `:rejected`. |
| `verified_at` | utc_datetime_usec | yes | Set on verify. |
| `verified_by_user_id` | uuid | yes | Operator who verified/rejected. |
| `rejection_reason` | string | yes | Set on reject. |

Plus `timestamps()`. Policies: `authorize_if always()` for now (house pattern; real policies in Inc 3).

**Actions**
- `create` (accepts identity fields + `workspace_id` + `owner_user_id`); `verification_status`
  defaults to `:unverified`, verification fields not accepted on create.
- `update` (accepts identity fields only — not verification).
- `verify` (update action): sets `verification_status: :verified`, `verified_at: now()`,
  `verified_by_user_id`, clears `rejection_reason`.
- `reject` (update action): sets `verification_status: :rejected`, `verified_at: now()`,
  `verified_by_user_id`, `rejection_reason`.
- `read`, `destroy` defaults.

### Reference-data enums (proper `Ash.Type.Enum`, per the no-bare-`:atom` rule)

Each with bilingual (FR/EN) labels via a companion helper module, matching the app's convention
(cf. `SchoolRoles`, `SanctionLabels`).

- `SchoolType` — `:lycee`, `:ces_ceg`, `:lycee_technique`, `:cetic`, `:gss`, `:ghs`, `:gbss`,
  `:gbhs`, `:gtc`, `:gths`, `:sar_sm`. (Cycle is implied by type; not a separate field.)
- `SchoolSubsystem` — `:francophone`, `:anglophone`, `:bilingual`.
- `SchoolSector` — `:public`, `:private_lay`, `:private_confessional`, `:community`.
- `CameroonRegion` — `:adamawa`, `:centre`, `:east`, `:far_north`, `:littoral`, `:north`,
  `:northwest`, `:south`, `:southwest`, `:west`.
- `SchoolVerificationStatus` — `:unverified`, `:verified`, `:rejected`.

### `Workspace` — unchanged schema

No new columns; `owner_user_id` semantics stay personal-only (its `unique_owner_user` identity is
untouched). School ownership lives on `SchoolProfile`.

### Atomic creation

`Schools.create_school/2` becomes a single `Repo.transaction`:
1. create `Workspace{kind: :school, name}`,
2. create `SchoolProfile{workspace_id, owner_user_id: creator, ...identity, verification_status: :unverified}`,
3. create `SchoolMembership{workspace, user: creator, roles: [:head]}`.
Any failure rolls the whole thing back (fixes today's orphan-school risk). Deferred notifications
follow the `upsert_marks` pattern if needed.

### Migrations

`mix ash.codegen` generates the `school_profiles` table + FKs + the two identities. No data
migration needed (no existing schools in the current DB lineage; if any exist, a backfill task
creates a default `SchoolProfile{verification_status: :unverified}` per school workspace — include
it in the plan as a safety step).

## Verification & the operate-gate

- **States:** `:unverified` (on create) → `:verified` or `:rejected` (operator). A rejected school
  returns to `:unverified` **automatically when its profile is next edited** (re-entering the
  operator's queue); there is no separate "resubmit" action.
- **Scope flag:** `Workspaces.school_scope/3` loads the profile and puts `school_verified?` (and
  `school_verification_status`) on the `Scope`, so gates are a cheap field read (no per-action
  query).
- **Blocked while not verified** (operating): recording marks (`MarksLive` / school marks paths),
  recording attendance (`AttendanceLive` record), printing/issuing bulletins (bulletin
  print controllers + any issue action). Each shows a clear "school pending verification" notice
  and does not persist.
- **Allowed while not verified** (setup): school profile edit, academic-year create/activate,
  class creation, staff invitations, timetable/periods.
- Personal-teacher workspaces have **no** verification concept and are unaffected.
- Enforcement lives at the operating entry points (web layer, alongside existing role checks),
  consistent with the current house pattern; real resource policies are Inc 3.

## Onboarding flow (self-serve head)

1. **Create a school** — a dedicated creation screen (replacing the header dropdown's inline
   field) collects **identity essentials**: `name`, `school_type`, `subsystem`, `sector`,
   `region`, `town`. Submit → atomic create → session switches to the new school → redirect to
   the school dashboard.
2. **Pending-verification dashboard** — the school dashboard shows a **"Pending verification"**
   banner: *"Your school is set up but not yet verified. You can configure classes and staff now;
   recording marks, attendance and bulletins unlocks once we verify it."* Plus a **setup
   checklist**: profile complete? · academic year created? · classes created? · staff invited?
3. **Complete profile** — the rest of the identity (contact, head name, logo, motto, registration
   number, department, short name) is edited in **Settings**.
4. Head proceeds through setup (year, classes, staff) — all allowed.
5. **Operator verifies** → banner clears, checklist shows verified, operating unlocks.

## Operator verification screen

- New operator-only area, e.g. `/admin/schools`, in its own `live_session` gated by an
  `on_mount` that requires the **global `UserRole == :admin`** (distinct from `SchoolRole`).
- Lists schools (default filter: `:unverified`) with a profile summary (name, type, subsystem,
  sector, region/town, owner email, submitted date).
- Actions: **Verify** and **Reject (with reason)** → `SchoolProfile` `verify` / `reject` actions,
  recording `verified_by_user_id`.
- In Inc 1 the operator sets their own account to `:admin` via seed/console; a fuller console
  (search, history, re-verify, suspend) is later.

## Logo storage

- Phoenix LiveView `allow_upload` (image, size/type constrained) on the Settings profile form.
- On save, the file is written to a **configured uploads directory** (e.g.
  `config :teacher_assistant, :uploads_dir`, default `priv/uploads/school_logos/` in dev), and
  `SchoolProfile.logo_path` stores the relative reference.
- Served via a controller route (or static path) that resolves the stored reference. Access is
  scoped to members where practical.
- Migration to object storage later is a `logo_path` → URL swap; the resource contract is stable.

## Authorization note

Increment 1 keeps the existing `authorize?: false` + web-layer-check house pattern. Two web-layer
gates are added: (a) the **verification operate-gate** above, and (b) the operator screen's global
`:admin` `on_mount`. Real Ash policies (defense-in-depth) are Increment 3; `SchoolProfile` is
shaped so they can be added there without schema change.

## Success criteria

- A user creates a school through the new flow: creation is **atomic** (no orphan on failure),
  the creator becomes **`:head` and owner**, and the school starts **`:unverified`**.
- While unverified: the head can edit profile, create/activate an academic year, create classes,
  and invite staff; and **cannot** record marks, record attendance, or print bulletins — each
  attempt shows a clear pending-verification message and persists nothing.
- An operator (`:admin`) sees the school on `/admin/schools` and **verifies** it; operating then
  unlocks for the head.
- The full identity (all fields, including a **logo upload**) round-trips through create + settings
  and is readable for later consumers.
- The **personal-teacher** workspace flow is unaffected end-to-end.

## Testing plan

- **Resource tests:** `SchoolProfile` create/update/verify/reject; the 1:1 identity; atomic
  `create_school` (rollback leaves no workspace/profile/membership); owner set correctly.
- **Verification-gate tests:** unverified school blocks marks save / attendance record / bulletin
  print with no persistence; verified school allows them; setup features allowed while unverified;
  personal workspace unaffected.
- **LiveView tests:** creation flow (atomic, redirect, becomes head/owner, unverified); dashboard
  pending banner + checklist; settings profile edit incl. logo upload; operator screen verify/reject
  (and that a non-`:admin` is denied).
- **Enum/label tests:** each enum's values + FR/EN labels.

## Relationship to later increments

`SchoolProfile` is the anchor the rest hang off: staff/roles (Inc 2) attach to the same workspace;
policies (Inc 3) attach to `SchoolProfile` and the operating gate; settings (Inc 4) edit its
fields + add config; dashboard/nav (Inc 5) surface its state (verification, checklist) and identity.

## Resolved (spec review, 2026-09-16)

1. **Rejected → re-submit:** editing a rejected school's profile automatically returns it to
   `:unverified` (re-enters the operator queue); no separate resubmit action.
2. **Operator route:** `/admin/schools`.
3. **head_name:** collected in Settings, not at creation (creation form stays to the six essentials).
