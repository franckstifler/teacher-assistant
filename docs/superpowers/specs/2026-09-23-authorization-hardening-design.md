# Authorization hardening (Increment C) — design

**Date:** 2026-09-23
**Status:** approved for planning
**Increment:** C — Permissions & authorization hardening

## Problem

Authorization in TeacherAssistant lives **entirely in the presentation layer**. A single
coarse module, `TeacherAssistant.Accounts.Permissions`, performs role checks off
`scope.current_roles` and is invoked only in LiveView `on_mount` gates, `can_edit`/`can_view`
assigns, and write-handler `if` guards. Every one of the 32 Ash resources carries an allow-all
policy — uniformly `policy always() do authorize_if always() end` — so the data layer enforces
nothing. A write succeeds for any actor because the policy is open.

The consequence: any code path that is not a gated LiveView — a forged LiveView event, a future
API, a `mix` task, a stray `Ash.update` from a context module — bypasses authorization entirely.
Allow-all is worse than "authenticated": it lets a **non-member**, or any signed-in user, mutate
another school's data at the data layer.

> **Framing correction.** The roadmap described the house pattern as an app-wide
> `authorize?: false`. That is inaccurate: there is exactly **one** `authorize?: false` call in
> `lib/` (`accounts.ex:89`, and it is redundant). The real pattern is allow-all *policies*. C
> replaces those policies with real ones; the single `authorize?: false` is removed as a cleanup.

## Goal & scope

Make the **data layer** the enforced source of truth for **writes**, and consolidate the role
definitions so there is exactly one place that says "who is an admin." Mirror today's behavior
except where hardening intentionally tightens it (marks ownership, below).

**In scope (decided):**

- **Harden + consolidate**, not a capability matrix and not delegation. Keep today's axis model
  (pedagogical / disciplinary / financial + the coarse admin gate). *(Decision, 2026-09-23.)*
- **Writes only.** Every create/update/destroy resolves through a real policy. Reads stay
  `authorize_if always()` at the data layer; the web layer keeps controlling visibility. *(Decision.)*
- **Mechanism: self-contained checks (Approach A).** Each policy check resolves the record's
  owning `workspace_id` from persisted data and loads the `(actor, workspace)` membership at eval
  time — authority is derived from data, never from caller-supplied context. *(Decision.)*
- **Enforce pedagogical ownership.** Marks/progression writes require the assigned teacher (or an
  admin), tightening beyond today's nav-only limitation. *(Decision.)*
- **Verification operate-gate: mirror exactly** — marks + attendance only, as today. *(Decision.)*

**Out of scope (deferred, explicitly):**

- **A capability matrix** (named per-action capabilities). The 3-axis model expresses today's
  distinctions; a matrix is speculative until a real per-action distinction appears.
- **Delegation / temporary grants / acting-head.** No such construct exists; adding one is a
  feature, not hardening. The only way to grant extra authority remains adding a role to a
  membership's `roles` array. (This is the "role model + delegation" line inherited from B — it
  stays deferred.)
- **Read/filter policies.** Reads stay open at the data layer. Read confidentiality (e.g. a teacher
  not being able to *load* another class's fees via a future API) is a separate, higher-regression-
  risk increment if it is ever wanted.
- **Granting authority to the display-only roles** (`:hod`, `:guidance_counsellor`, `:librarian`).
  They stay baseline-member-only, exactly as today. Giving `:hod` real pedagogical authority would
  require a HOD→department link that does not exist — that is a feature, not this consolidation.
- **Extending the verification gate** to fees/discipline writes. Mirrored exactly; not extended.

## Design

### 1. One role-set definition, a small check family, a uniform policy shape

**Single source of truth.** The role→axis mapping already lives, morally, in `Permissions`
(`admin = head|vice_principal`; `conduct = admin|discipline_master`; `fees = admin|bursar`). C makes
it the *only* definition, expressed as canonical role-set constants and consumed two ways:

- **Web layer** keeps calling `Permissions.admin?(scope)` etc. with **unchanged signatures**. Their
  bodies delegate to the constants (e.g. `Permissions.roles_for(:admin) => [:head, :vice_principal]`)
  applied to `scope.current_roles`.
- **Data layer** checks apply the *same* constants to `membership.roles`.

So "who counts as admin" is written once; the LiveView gate and the policy cannot drift.

**The check family.** All are `Ash.Policy.SimpleCheck` under `TeacherAssistant.Accounts.Checks`.
Each resolves the record's owning `workspace_id` from its belongs-to chain and **fails closed** if it
cannot resolve one.

| Check | Authorizes when… | Backs |
|---|---|---|
| `ActiveMember` | actor has an active membership in the owning school | baseline "any member" writes |
| `HasSchoolRole(roles: :admin \| :conduct \| :fees \| :head)` | membership roles intersect that axis's canonical set | the role gates |
| `OwnsAssignedContext` | actor is the teacher assigned to the teaching context the record hangs off (directly, or via its slot/assessment) | marks, progression, attendance |
| `SchoolVerified` | the owning school's `verification_status == :verified` | the operate gate, at the data layer |
| `IsOperator` | actor's **global** `UserRole == :admin` | the school-verification action |
| `IsInvitationRecipient` | actor's email matches the invitation being accepted | invitation accept (bootstrap) |

`FormMasterOfClass` is intentionally **absent** from the family: form-master authority backs only
reads (bulletin/results/timetable *pages* and *prints*, all `admin_or_form_master?` gates on
views/exports). Since reads stay open, form-master stays a purely web-layer concern.

**Workspace resolution** is the only per-resource bespoke code. Shallow resources expose
`workspace_id` directly (`ClassGroup`, `AcademicYear`, `Subject`, `SchoolMembership`,
`TeachingContext`, `Workspace`, `SchoolProfile`). Deep resources reach it via one belongs-to hop
(`Mark` → assessment → context → workspace; `AttendanceEntry` → slot/context → workspace;
`Payment`/`FeeTranche`, `SanctionEntry`/`ConductMark` → their parents). For **creates**, the parent
FK is read from the changeset and loaded; for **update/destroy**, it is read from the loaded record.
A single resolver module maps each policed resource → how to obtain its `workspace_id`.

**Uniform policy shape.** Every `policy always() do authorize_if always() end` becomes:

```elixir
policies do
  policy action_type(:read) do
    authorize_if always()                         # reads stay open (writes-only decision)
  end

  policy action_type([:create, :update, :destroy]) do
    forbid_unless Checks.SchoolVerified           # present ONLY on operational resources
    authorize_if Checks.HasSchoolRole(roles: :admin)
    authorize_if Checks.OwnsAssignedContext       # extra authorize_if = OR
  end
end
```

Ash composes for free: multiple `authorize_if` inside one policy are **OR**'d; `forbid_unless`
short-circuits to forbid, giving `SchoolVerified AND (admin OR owner)`; separate policies are
**AND**'d if ever needed. A config resource omits the `forbid_unless` line. The
AshAuthentication bypasses on `User`/`Token` are preserved as-is.

### 2. Resource → policy matrix

Reads stay open everywhere. Only writes (create/update/destroy) are listed.

**Tier 1 — Config & setup** *(role check, no verification gate — setup runs before verification):*

| Resource(s) | Write policy |
|---|---|
| `ClassGroup`, `AcademicYear`, `Subject`, `TeachingContext` (assignments), `CombinedCourse`, `TimetableSlot`, `Period` | `HasSchoolRole(:admin)` |
| `SchoolProfile` (settings, logo) | `HasSchoolRole(:admin)`; head-only danger actions → `HasSchoolRole(:head)` |
| `SchoolMembership`, `SchoolInvitation` (invite/roles/status/deactivate) | `HasSchoolRole(:head)` — the "last active head" guard in the context stays |

**Tier 2 — Operational, verification-gated** *(mirroring today's operate gate — marks + attendance only):*

| Resource(s) | Write policy |
|---|---|
| `Assessment`, `Mark` | `SchoolVerified` **and** (`HasSchoolRole(:admin)` **or** `OwnsAssignedContext`) |
| `AttendanceEntry` | `SchoolVerified` **and** (`HasSchoolRole(:conduct)` **or** `OwnsAssignedContext`) |

**Tier 2b — Pedagogical, teacher-owned** *(ownership check, **no** verification gate — planning precedes verification):*

| Resource(s) | Write policy |
|---|---|
| `ProgressionPlan` + entries, `TeachingLogEntry` | `HasSchoolRole(:admin)` **or** `OwnsAssignedContext` |

**Tier 3 — Financial & disciplinary** *(axis check, mirroring today — not verification-gated):*

| Resource(s) | Write policy |
|---|---|
| `Payment`, `FeeTranche` (+ fee structure) | `HasSchoolRole(:fees)` |
| `SanctionEntry`, `ConductMark` | `HasSchoolRole(:conduct)` |

**Tier 4 — Bootstrap & operator** *(special cases):*

| Action | Write policy |
|---|---|
| `Workspace.create_school` | `actor_present()` — any signed-in user creates their own school and becomes its head (no prior membership exists) |
| `SchoolInvitation` accept | `IsInvitationRecipient` — the action's email-match validation stays as defense-in-depth |
| `SchoolProfile` verification | `IsOperator` — global `UserRole == :admin` |

**All other resources** (no currently-guarded writes) get the baseline `ActiveMember` — already a
hard upgrade from allow-all, which lets any user, even a non-member, mutate.

> The exact resource inventory per tier is confirmed against the codebase during the foundation
> task; a resource discovered to be miscategorized is placed by the same axis rules above.

### 3. Consolidation, the web layer, and rollout

**The web gates stay.** C *adds* the data-layer backstop and *unifies* the role definition; it does
not strip the LiveView checks. Two layers, one definition:

- **Data layer (new — the enforcement):** the policies above. Unbypassable.
- **Web layer (unchanged behavior — the UX layer):** `Permissions.*` keep their exact signatures,
  so **no LiveView edits are required** for the gates to keep working; only their bodies change to
  read the canonical constants. Nav hiding and friendly flashes are preserved.

**Cleanups that fall out:**

- Remove the lone `authorize?: false` at `accounts.ex:89` (`update_member_status`) so the new
  head-only `SchoolMembership` policy governs it — consistent with its sibling `update_member_roles`.
- Every context write must thread the actor (most already do via the scope's `Ash.Scope.ToOpts`,
  which supplies `actor = current_user`). A write that omits it will **fail closed** once its
  domain's policy goes live — which is how the gaps are found and fixed.

**Rollout — domain by domain, fail-closed, suite-gated** (not a big-bang flip):

1. **Foundation task:** canonical role-sets on `Permissions` + the six checks + the per-resource
   `workspace_id` resolver, all unit-tested in isolation. No policies flipped yet, so the suite
   stays green.
2. **Then one task per domain** — accounts/organization (membership, settings), enrollment,
   curriculum, assessment, attendance, discipline, fees, timetabling. Each flips *that domain's*
   resources from allow-all to real policies, threads the actor through that domain's context
   writes, adds policy boundary tests, and must leave `mix test` green before the next domain.

**Policy test shape** (per domain): the boundary both ways — authorized role passes, wrong role
forbidden, **non-member forbidden** (the allow-all hole), and for the ownership tiers, the assigned
teacher passes / another teacher forbidden. This mirrors the wizard increment's forged-event tests.

**Expected fixture churn.** Tests that today create data as a bare user or a non-member will start
failing closed and are corrected in their domain's task — the same pattern as the setup-gate
migrating 33 tests. That is the suite doing its job, not a regression.

## Non-goals

- No capability matrix, no delegation, no read/filter policies, no multitenancy.
- No change to the two role systems' shapes (`UserRole` global vs `SchoolRole` per-school).
- No new authority for the display-only roles; no verification-gate extension to fees/discipline.
- No web-layer gate removal — the LiveView checks remain as the UX layer.

## Risks

- **Missing actor on a context write** → the action fails closed after its domain flips. Mitigated
  by the domain-by-domain rollout and the green-suite gate; each surfaces exactly where.
- **Workspace resolution for a deep resource is wrong/absent** → the check fails closed (denies).
  Mitigated by isolated resolver tests in the foundation task and per-domain boundary tests.
- **Marks ownership tightening** changes behavior: a member who could reach the marks action for a
  context they are not assigned to is now denied. This is the intended hardening, called out so it
  is not mistaken for a regression.

## House patterns honored

- Ash `Ash.Type.Enum` for roles/status (never bare `:atom`) — unchanged.
- Migrations only via `mix ash.codegen --dev` — but note **C adds no schema** (policies and checks
  are code, not data); no migration is expected.
- `mix precommit` does not gate on warnings — run `mix test`; keep warnings-as-errors clean.
