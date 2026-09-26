# Authorization (Increment C) — design

**Date:** 2026-09-24
**Status:** implemented (plan `docs/superpowers/plans/2026-09-25-authorization.md`)
**Supersedes:** `docs/superpowers/specs/2026-09-23-authorization-hardening-design.md` and its plan
`docs/superpowers/plans/2026-09-23-authorization-hardening.md` (both written before the schema pass
and multitenancy; audit README §8 lists what changed).
**Builds on:** Increment 3, schema pass + multitenancy (`2026-09-23-schema-pass-multitenancy-design.md`,
merged at `cad709f`).

## 1. Goal

Make the Ash data layer the only place that decides who may read and write what inside a school:

1. Thread `scope` (actor + tenant) through every domain call, replacing the transitional tenant taken
   from `struct.workspace_id`.
2. Real policies on every resource, every domain `authorize :by_default`, and the
   `TeacherAssistant.Accounts.Permissions` module retired in favour of `can_*?` questions answered by
   those policies.
3. Composite foreign keys that tie every tenant-to-tenant reference to the tenant at the DB level.
4. Two fee tickets from audit README §9: a non-positive fee adjustment is a clean domain error, and the
   DB and the domain agree on what an adjustment may be.

Behaviour mirrors today's web-layer gates except where this spec says it tightens them (§4.3).

## 2. Decisions carried forward (not reopened)

From the 2026-09-23 spec and audit README §8:

- Three-axis role model (pedagogical / disciplinary / financial) plus the coarse admin gate. No
  capability matrix, no delegation or acting-head construct; granting authority stays "add a role to a
  membership".
- Pedagogical ownership is enforced: marks and progression writes require the assigned teacher or an
  admin.
- The verification ("operate") gate covers marks and attendance only.
- Display-only roles (`:hod`, `:guidance_counsellor`, `:librarian`, `:teacher`) carry no authority
  beyond membership.
- Domain-by-domain rollout, each step leaving the suite green, each domain with a non-member
  `Forbidden` test.
- Pinned versions: Ash 3.33.9, AshPostgres 2.13.1, AshPhoenix 2.3.25, LiveView 1.2.12.

## 3. Non-goals

- Least-privilege reads beyond the two sensitive areas in §4.2 (teachers still read the whole school's
  non-sensitive data; the web layer decides what each role is shown).
- Operator (global `UserRole == :admin`) access to school data. The operator keeps only the school
  list and the verification actions.
- Verification onboarding (G4), role-aware navigation redesign (E), fee surcharges.
- Layout performance (audit WEB-19), untranslated-copy debt.

## 4. Design

### 4.1 Authorization primitives

**Role sets live on the enum.** `TeacherAssistant.Accounts.SchoolRole.axis/1` is the single
definition of who counts as what:

| Axis | Roles |
|---|---|
| `:member` | any role (the membership must be active) |
| `:admin` | `:head`, `:vice_principal` |
| `:head` | `:head` |
| `:conduct` | `:head`, `:vice_principal`, `:discipline_master` |
| `:fees` | `:head`, `:vice_principal`, `:bursar` |

**Two checks** under `TeacherAssistant.Accounts.Checks`, both `Ash.Policy.SimpleCheck`:

- `SchoolRole, any_of: axis` — resolves the workspace from the subject's tenant; for the two
  non-tenant school resources it reads it from the record (`Workspace.id`,
  `SchoolProfile.workspace_id`). Loads the actor's **active** `SchoolMembership` in that workspace
  (one read on the existing `(workspace_id, user_id)` index) and passes when the membership's roles
  intersect `SchoolRole.axis(axis)`. No actor, no resolvable workspace or no active membership →
  `false`. Its internal read uses `authorize?: false` (a check must not recurse into policies), with
  a comment saying so. The same logic is exposed as a plain function for the one navigation gate in
  §4.6.
- `SchoolVerified` — the workspace's `SchoolProfile.verification_status == :verified`, resolved the
  same way.

Because both are static checks, `Ash.can?` answers role gates exactly, creates need no post-insert
query for them, and membership is read fresh on every authorization (a revoked member is refused on
the next call even inside an open LiveView).

**Row-dependent rules are inline `expr` checks**, evaluated as filters on reads, against the original
record on update/destroy, and post-insert inside the transaction on create (Ash 3.33.9 behaviour):

- ownership ("owner" in §4.3): the actor is the teacher of the row's teaching context —
  `teaching_context.teacher_user_id == ^actor(:id)`, or for a unit owned through a combined course
  `exists(combined_course.teaching_contexts, teacher_user_id == ^actor(:id))`. Deep rows reach the
  context through their own path: `Mark` via `assessment`, `ProgressionModule`/`ProgressionEntry`/
  `TeachingLogEntry` via their plan, `LessonPlan`/`LessonStep` via entry → plan;
- form master: `class_group.form_master_user_id == ^actor(:id)`, reached through the row's own path
  (`enrollment.class_group…` for enrollment-owned rows);
- invitation recipient: `email == ^actor(:email)`.

Operator gates use the built-in `actor_attribute_equals(:role, :admin)`. The AshAuthentication
bypasses on `User` and `Token` are kept unchanged.

**Standard policy shape:**

```elixir
policies do
  policy action_type(:read) do
    authorize_if {Checks.SchoolRole, any_of: :member}
  end

  policy action_type([:create, :update, :destroy]) do
    forbid_unless Checks.SchoolVerified                                   # operate-gated only
    authorize_if {Checks.SchoolRole, any_of: :admin}
    authorize_if expr(teaching_context.teacher_user_id == ^actor(:id))   # where ownership applies
  end
end
```

**Generic actions.** Ash evaluates `expr` checks on generic actions in memory, so a relationship rule
cannot decide them. Generic actions therefore carry static checks only: `SchoolRole(:member)` (plus
`SchoolVerified` where operate-gated), or the role axis when the action is purely role-gated
(`CombinedCourse.combine/split`, `TimetableSlot.place_combined/clear_combined` → `:admin`). Their
inner writes carry the scope and are authorized by their own resource's policy inside the action's
transaction, so one forbidden row rolls the whole action back. Bulk inner writes subject to
post-insert checks run with `transaction: :all` or `:batch`.

**`authorize?: false` in `lib/`** is allowed in exactly these places, each with a comment:

1. the internal membership/profile reads of the two checks;
2. bootstrap nested writes: `Workspace.create_school` seeding (the creator is not yet a member) and
   the membership created by invitation accept (§4.4);
3. the new `Student` inside `Enrollment.enroll_new`, which has no class yet; its sibling
   `Enrollment` create is authorized (admin or form master of the class) and rolls the transaction
   back if refused.

### 4.2 Reads

Every tenant resource: `SchoolRole(:member)`.

Sensitive areas (the rest stays membership-only):

| Resources | Readable by |
|---|---|
| `Payment`, `FeeAdjustment`, `FeeTranche` | `:fees` axis, or form master of the row's class |
| `SanctionEntry`, `ConductMark` | `:conduct` axis, or form master of the row's class |

Form-master read access mirrors today: `FeesLive` and `DisciplineLive` already admit
`admin_or_form_master?`, and bulletins/results read conduct through that path.

Special reads:

| Read | Rule |
|---|---|
| `SchoolInvitation.by_token` | `always()` — the token is the credential; the accept page works signed-out |
| `SchoolInvitation.pending_for_workspace` | `:head` |
| `SchoolMembership.active_for_user` (global) | `user_id == ^actor(:id)` |
| `Workspace`, `SchoolProfile` | member of that workspace, or operator |
| `SchoolProfile.unverified` | operator |
| `User` (non-authentication reads) | self, or an active co-member of one of the actor's schools |

Reads a policy refuses come back filtered (empty list, not-found on get); screens treat that like a
missing record.

### 4.3 Writes

| Tier | Resources / actions | Rule |
|---|---|---|
| Config | `AcademicYear` (+ `activate`, default calendar), `Term`, `Sequence`, `ClassGroup` (incl. form master), `Subject` (+ `deactivate`), `TeachingContext` (assign, unassign, reassign, coefficient), `CombinedCourse.combine/split`, `Period`, `TimetableSlot` (+ `place_combined/clear_combined`), `SchoolProfile` update and logo | `:admin` |
| | `Workspace` rename | `:head` |
| Staff | `SchoolMembership` (roles, status, deactivate), `SchoolInvitation` create and revoke | `:head`; the "last active head" guard stays in the domain |
| Class roster | `Enrollment` create/update/destroy (enrol existing, transfer, withdraw), `Student` update, `Enrollment.enroll_new` | `:admin`, or form master of the class — for `Enrollment` update/destroy, the class on the original record (a transfer is decided by the source class); for `Student` update, a class the student is enrolled in (`exists(enrollments, class_group.form_master_user_id == ^actor(:id))`) |
| | `Student` create outside `enroll_new` (bulk import) | `:admin` |
| Pedagogy | `ProgressionPlan`, `ProgressionModule`, `ProgressionEntry`, `LessonPlan`, `LessonStep`, `TeachingLogEntry` (+ `import`, `apply_layout`) | `:admin`, or owner |
| Operate-gated | `Assessment` (+ `create_combined`), `Mark` (+ `upsert_all`) | `SchoolVerified` **and** (`:admin` or owner) |
| | `AttendanceEntry` (+ `record_combined_period`, justify/unjustify day) | `SchoolVerified` **and** (`:conduct` or owner); a nil `teaching_context_id` means conduct only |
| Axis | `SanctionEntry`, `ConductMark` | `:conduct` |
| | `Payment`, `FeeTranche`, `FeeAdjustment` | `:fees` |
| Bootstrap | `Workspace.create_school` | `actor_present()` |
| | `SchoolInvitation.accept` (§4.4) | `email == ^actor(:email)` |
| Operator | `SchoolProfile.verify/reject`, `User.promote_to_admin` | operator |
| Auth | other `User` writes | only through AshAuthentication's own actions (existing bypass); the generic `:create` stops accepting `role` (audit ASH-16) |

**Intended tightening:** marks and progression writes now require ownership at the data layer; today
only navigation stops a teacher from reaching another teacher's context.

### 4.4 Invitation accept becomes an action

Today `Accounts.accept_invitation/2` performs two writes (membership create, invitation update)
outside a transaction, and the membership create would be refused by the head-only rule. It becomes
`SchoolInvitation` `update :accept`:

- validations: status `:pending`, not expired, `email` matches the actor (defence in depth next to
  the policy);
- a change that creates the membership (idempotent when the user is already an active member) as a
  bootstrap nested write, in the same transaction as the status update;
- policy: `authorize_if expr(email == ^actor(:email))`.

`Accounts.accept_invitation(scope, token)` becomes a thin wrapper: read by token, run `:accept`,
return the workspace. Its error atoms (`:invalid`, `:expired`, `:email_mismatch`) are preserved for the
controller.

### 4.5 Scope plumbing

**Signature convention (Phoenix 1.8 contexts).** Every public domain function that touches tenant
data takes `%TeacherAssistant.Scope{}` as its first argument:

- it replaces `%Workspace{}`: `list_class_groups(scope, year)`;
- functions that took only child structs gain it: `delete_class_group(scope, cg)`;
- pre-tenant entry points take a scope carrying only the user: `create_school(scope, attrs)`,
  `accept_invitation(scope, token)`;
- `Workspaces.scope_for/3` builds the scope and stays scope-free; pure helpers with no DB access are
  unchanged.

**Inside domains:** every Ash call passes `scope: scope` (actor, tenant and locale context through the
existing `Ash.Scope.ToOpts` impl); every struct-derived `set_tenant(x.workspace_id)` /
`tenant: x.workspace_id` is removed (≈160 in domains, 18 in the web layer); AshPhoenix forms take
`scope:` instead of `tenant:` so `submit` carries the actor; cross-domain calls pass the scope along.
`Scope.get_authorize?/1` stays `:error` — each domain's `authorize` setting decides.

**Web layer:** LiveViews pass `@current_scope`; async work (`start_async`, tasks) captures it
explicitly. Controllers get it from a new `TeacherAssistantWeb.Plug.Scope` in the school pipeline,
which assigns `current_scope` via `Workspaces.scope_for/3` and replaces the copied preambles (audit
WEB-02).

**Guards after §4.7:** `Tenancy.same_workspace/1` and its call sites are deleted — every struct now
comes from a read under the scope's tenant, and the composite FKs reject a mismatch at the DB. Tests
that asserted `{:error, :workspace_mismatch}` assert the resulting error instead. Kept: the
membership checks on `User` references (`teacher_user_id`, `form_master_user_id`, combined course
teacher), because `User` is not multitenant; and `Tenancy.require_tenant/1` on the two `global?`
resources.

**Phase 1 is inert:** while domains stay `:when_requested` with allow-all policies, passing the actor
runs authorization against policies that always pass. Phase 2 bites as soon as a domain's policies
change, and `:by_default` makes an actor-less call fail closed.

**Conversion order:** a calling domain converts before the domains it calls (a converted caller can
still call an unconverted callee's old signature); domains that call each other convert in one task.

**Tests and seeds:** `DataCase.school_scope(user, school)` returns the real `Workspaces.scope_for/3`
result; `ConnCase.register_and_log_in_user/1` adds `scope` to its map; fixtures take the acting scope
(the head's by default) and stop using `authorize?: false` as each domain flips; `priv/repo/seeds.exs`
runs as the seeded head.

### 4.6 Retiring `Permissions`

- **Write handlers stop pre-checking.** The `with true <- Permissions.x?(scope)` guards in
  `handle_event` callbacks go; the handler calls the domain function, and
  `{:error, %Ash.Error.Forbidden{}}` renders one shared "not allowed" flash. Forged-event tests keep
  passing; the policy is now what refuses.
- **Visibility uses `can_*?`.** Buttons, forms and nav ask the domain's `can_*?` functions — generated
  from code-interface `define`s where the action has one, otherwise a thin
  `def can_x?(scope, …), do: Ash.can?({Resource, :action}, scope, …)` in the domain. They are computed
  once per mount into assigns, never in render. The layout nav reads a capability map built by an
  `on_mount` hook. Limit: ownership on *create* is a post-insert filter, so `can?` is optimistic
  there; screens keep reaching owned records by navigation, as today.
- **Page-access gate:** `admin_or_form_master?(scope, cg)` guards class, bulletin, results, timetable
  and register pages whose data is membership-readable, so no policy answers it. It becomes
  `Enrollment.class_manager?(scope, cg)`, built from the `Checks.SchoolRole` function (fresh
  membership) plus `cg.form_master_user_id`, documented as a navigation gate, not a security
  boundary. The sensitive reads on those pages are policy-enforced regardless.
- `member?` call sites are removed (the read itself is policy-checked; refused → 404 or redirect).
  `operating_allowed?` banners and flashes use the existing `Scope.school_verified?/1`.
  `Scope.current_roles` stays for display (the header role label).
- End state: `TeacherAssistant.Accounts.Permissions` and its test are deleted; the final gate greps
  for leftovers.

### 4.7 Composite foreign keys

Every reference from one tenant-owned resource to another (≈37) is tied to the tenant:

- **Parents:** every referenced tenant resource gets `custom_indexes do index [:id], unique: true end`;
  attribute multitenancy prefixes it to `(workspace_id, id)`, the unique index Postgres requires as a
  composite FK target.
- **Non-null references:** `reference :x, match_tenant?: true` →
  `(x_id, workspace_id) REFERENCES (id, workspace_id) MATCH FULL`.
- **Nullable references** (`AttendanceEntry.teaching_context`, `ProgressionPlan.teaching_context`,
  `ProgressionPlan.combined_course`, `ProgressionEntry.sequence`, `TeachingLogEntry.progression_entry`,
  and any other `allow_nil? true` reference the plan's inventory finds):
  `match_with: [workspace_id: :workspace_id], match_type: :simple` — `MATCH FULL` would reject a null
  FK next to the non-null `workspace_id`; `MATCH SIMPLE` allows the null and checks a non-null value.
- Existing `on_delete` and `index?` options are kept. References to `User` are unchanged.
- One named migration (`mix ash.codegen tenant_composite_fks`). A row that already crosses tenants
  makes the migration fail loudly rather than be skipped; dev and test data are clean (backfilled from
  parents, guarded since).

### 4.8 Fee adjustments

A positive `FeeAdjustment.amount` is a discount (`FeeBalance`: `total_due = total_tranches -
adjustment`). Decision: **discounts only**.

- The DB check becomes `amount > 0` (`fee_adjustments_amount_positive_check`), generated with the
  Fees task's migration.
- `Fees.set_adjustment/3` rejects `amount <= 0` with `{:error, :invalid_amount}` before any write, so
  zero never reaches the DB check. The shared `validate_amount/1` is split: tranches keep `>= 0`
  (matching their DB check), adjustments require `> 0`, payments already require `> 0`.
- `clear_adjustment` stays the way to remove an adjustment.

## 5. Rollout

**Phase 1 — foundations and plumbing** (inert; suite green after every task)

1. Foundations: `SchoolRole.axis/1`; `Checks.SchoolRole` and `Checks.SchoolVerified` with unit tests
   (no actor, no workspace, inactive membership, each axis, verified/unverified);
   `DataCase.school_scope/2`; the `ConnCase` scope; `Plug.Scope`.
2. Composite FKs (§4.7) and deletion of `Tenancy.same_workspace/1`.
3. Scope plumbing in about four tasks grouped by the cross-domain call graph (§4.5), each converting
   its domains' signatures and every web, test and cross-domain call site.

Whole-phase review.

**Phase 2 — policies, one task per domain:** Organization → Enrollment → Curriculum → Assessment →
Attendance → Timetabling → Discipline → Fees → Accounts. Each task:

- writes the domain's policies (§4.2–4.4) and flips it to `authorize :by_default`;
- deletes that domain's `authorize?: false` from tests (fixtures act as the head);
- replaces that domain's `Permissions` call sites (§4.6);
- adds a boundary test table calling the real domain functions: authorized role ✓, wrong role ✗,
  non-member ✗ (a user of school B holding a scope for school A), actor-less call ✗, owner ✓ / other
  teacher ✗ where ownership applies, and for the sensitive areas a plain teacher gets empty/not-found
  while that class's form master reads;
- Fees also carries §4.8; Accounts also carries §4.4 and the `User` rules.

Whole-phase review.

**Phase 3 — cleanup:** capability map in the layout, `Enrollment.class_manager?/2`, deletion of
`Permissions`, seeds as the head, audit README §8 and §10 marked executed. Final whole-branch review.

**Per-task gate:** `mix ash.codegen --check`, `mix compile --warnings-as-errors`, `mix test`, then
`mix precommit` (which does not gate on warnings on its own).

**Migrations:** AGENTS.md's `mix ash.codegen --dev` while iterating; each task that changes schema
finishes with `mix ash.codegen <slug>`, which rolls back and squashes the `_dev` migrations, so no
`_dev` file is committed and `--check` stays clean. No hand-written migrations.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Fixture churn: ≈1,670 test call sites need a scope | Mechanical, per task; `school_scope/2` and scope-returning fixtures land in task 1 so later tasks only thread them |
| A generic action whose inner write lacks the scope | Under `:by_default` it is forbidden, so it fails loudly; boundary tests exercise every generic action |
| Post-insert checks on bulk inner writes | `transaction: :all`/`:batch` pinned in the plan; Ash raises `CannotFilterCreates` otherwise |
| A nested or bootstrap write escaping authorization | `authorize?: false` limited to the three cases in §4.1, each commented; the final gate greps for any other |
| Navigation gate drifting from the data rules | Built on the same `Checks.SchoolRole` function; `class_manager?/2` is the only non-policy gate and is named as such |
| Composite FK migration meets a cross-tenant row | Fails loudly; data is clean today |
| Behaviour change on marks/progression ownership | Intended (§4.3); covered by owner/other-teacher tests |
