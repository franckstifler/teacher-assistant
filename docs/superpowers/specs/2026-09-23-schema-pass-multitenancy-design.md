# Schema pass & multitenancy — design (Increment 3)

**Date:** 2026-09-23 · **Status:** approved in chat, written spec for review
**Depends on:** `docs/audits/2026-09-23-school-focus/README.md` §9 (resource field gaps) and §10 (multitenancy design); the teacher-personal pause (merged 2026-09-23) and the calendar/courses increment (merged 2026-09-23).
**Decisions taken with the product owner (2026-09-23):** no production data exists (dev-only databases); the paused teacher-personal code is **deleted**, not adapted; approach **A** (one increment, two phases) with denormalised `workspace_id` on deep resources and school-only fixtures.

## 1. Goal

Make the school the tenant at the data layer:

- every tenant-owned row carries a real `workspace_id` foreign key, indexed;
- reads and writes are tenant-scoped by Ash attribute multitenancy, with the tenant taken from the current `Scope` (or, transitionally, from the data a domain function already receives);
- personal workspaces and the paused teacher-personal code no longer exist;
- the data model no longer has the nullable "pivot" columns that the authorization increment would otherwise have to special-case.

## 2. Non-goals

- Passing `scope:` (actor + tenant) through LiveViews and controllers: the authorization increment does that when it threads the actor.
- Read or write policies, `authorize :by_default`, retiring `Permissions`: authorization increment.
- Any UI change beyond what the deletions force (nav item removal is already done by the pause).
- Backfill migrations for existing data: none exists.
- Séquence date editing, grading config, HOD/department link.

## 3. Phase 1 — Schema

### 3.1 Workspace foreign keys

| Resource | Today | Change |
|---|---|---|
| AttendanceEntry, TimetableSlot, SanctionEntry, ConductMark, FeeTranche, Payment, FeeAdjustment | `attribute :workspace_id, :uuid` (no FK) | replace with `belongs_to :workspace, Workspace, allow_nil?: false` + `reference :workspace, index?: true, on_delete: :delete` |
| Term, Sequence, Assessment, Mark, ProgressionModule, ProgressionEntry, LessonPlan, LessonStep | no workspace column | add the same `belongs_to :workspace` |
| Every existing `belongs_to :workspace` | FK, no index | `reference :workspace, index?: true` |

`workspace_id` is **denormalised** on deep resources on purpose: one indexed tenant column per table, uniform multitenancy, no three-hop joins. Ash fills it from the tenant on create (§4), so no caller sets it.

### 3.2 Indexes and constraints

- `index?: true` on every `belongs_to` reference in every resource (today none are indexed).
- `custom_indexes`: `AttendanceEntry [:enrollment_id, :date]`, `AttendanceEntry [:workspace_id, :date]`, `ProgressionEntry [:progression_plan_id, :position]` (or the module id if entries hang off modules — the plan verifies the actual FK), `TimetableSlot [:workspace_id, :teaching_context_id]`.
- One active year per workspace: `custom_indexes` unique partial index on `AcademicYear [:workspace_id] where: "active"`; the `:activate` action keeps deactivating siblings first.
- `check_constraints` (AshPostgres): `Mark.score >= 0` (the `score <= max_score` rule needs the assessment row, so it stays a resource validation on `Mark`, added in the same task), `Payment.amount > 0`, `FeeTranche.amount > 0`, `FeeAdjustment.amount <> 0`, `ConductMark.value between 0 and 20`, `Sequence end_date >= start_date`, `AcademicYear end_date > start_date` (mirrors the resource validation added on 2026-09-23).

### 3.3 Nullable pivots and duplicates

- `TeachingContext`: `teacher` and `class_group` become `allow_nil? false`; drop the personal partial unique index and keep the school one (teacher × subject × class × year); remove the duplicate `attribute :combined_course_id` (keep the `belongs_to`); drop the personal quota fields `annual_hours`, `target_module_count`, `target_lesson_count` (only the paused fiche used them; `Quota` module deleted with it).
- `ClassGroup`: remove the duplicate `attribute :form_master_user_id` (keep the `belongs_to :form_master`); `:form_master` is removed from the `SchoolRole` enum values (the FK on the class is the one source).
- `AttendanceEntry.teaching_context` stays nullable (conduct managers record without a context).
- `ProgressionPlan`: keeps the `ExactlyOneOwner` validation (context XOR combined course) — unchanged.

### 3.4 Workspace becomes the tenant record

- `Workspace` loses `kind`, `owner_user_id`, `belongs_to :owner_user`, identity `unique_owner_user`, read `:for_owner`, the default `:create` accept of `kind`/`owner_user_id`. `WorkspaceKind` enum deleted. `create_school` unchanged in behaviour (profile + head membership + catalog + periods).
- `SchoolProfile.owner_user_id` stays (school ownership).
- `Organization.get_personal_workspace` renamed `get_workspace`.

### 3.5 Bare atoms

`ProgressionPlan.status`, `ProgressionEntry.entry_type`, `TeachingLogEntry.status` become `Ash.Type.Enum` modules (`mix ash.gen.enum`), values unchanged, with `label/1` like the other enums.

### 3.6 Migrations

Generated only (`mix ash.codegen --dev` then `mix ash.codegen <name>` to squash the dev migrations at the end of the phase). Dev databases are reset (`mix ash.reset`). The stale `priv/resource_snapshots/repo/personal_workspaces/` directory is deleted. No hand-written migration.

## 4. Phase 2 — Tenancy

### 4.1 Resource DSL

```elixir
multitenancy do
  strategy :attribute
  attribute :workspace_id
end
```
on every resource of §3.1 plus the ones that already had the FK: AcademicYear, Subject, Period, ClassGroup, Student, Enrollment, TeachingContext, CombinedCourse, ProgressionPlan, TeachingLogEntry.

`SchoolMembership` and `SchoolInvitation`: same block plus `global? true` (a user's memberships are listed before a tenant is chosen; an invitation is looked up by token on accept). `SchoolInvitation.unique_token` gets `all_tenants?: true`.

Not multitenant: `Workspace`, `SchoolProfile`, `User`, `Token`.

Identities: Ash appends the tenant attribute to every identity of a multitenant resource; the declared identities stay as they are.

### 4.2 Tenant source

- `TeacherAssistant.Scope` implements `Ash.Scope.ToOpts`; `get_tenant/1` returns `{:ok, scope.current_workspace.id}` (or `:error` when no workspace).
- **Transitional rule (this increment):** every domain function that receives a `%Workspace{}` or a child struct sets the tenant from that data on the query or changeset it builds (`Ash.Query.set_tenant/2`, `Ash.Changeset.set_tenant/2`, or `tenant:` on code-interface calls). Callers (LiveViews, controllers, fixtures) do not change. The authorization increment replaces this with `scope:` when it threads the actor.
- Generic and nested actions (`Enrollment.:enroll_new`, `Mark.:upsert_all`, `CombinedCourse.:combine/:split`, `TimetableSlot.:place_combined`, `AttendanceEntry.:record_combined_period`, `ProgressionPlan.:import/:apply_layout`, `Workspace.:create_school` seeding) pass `tenant:` explicitly to each nested changeset/query they build; inside hooks the tenant is `changeset.tenant` or, for `create_school`, the new workspace's id.
- Reads that must span tenants (operator listing schools) target non-multitenant resources only.

### 4.3 What the tenant replaces

- `accept [:workspace_id]` is removed from every create; `workspace_id` is set by Ash from the tenant.
- The `:owned` / `:assigned_in_school` read actions and the `fetch_owned_*` wrappers keep only the non-tenancy part of their filter (assignment ownership, class membership); the `workspace_id == ^arg` clauses go.
- Bare-id domain functions (`Fees.record_payment/3`, `Discipline.add_sanction/3`, `Attendance.justify_day/3`, `student_balance/2`, …) become safe by construction because the `Ash.get` inside them is tenant-filtered; their signatures do not change in this increment.

### 4.4 Rollout

Domain by domain, each step leaving the suite green: Organization → Enrollment → Curriculum → Assessment → Attendance → Timetabling → Discipline → Fees → Accounts (memberships/invitations). A resource flips only when every domain function that touches it sets the tenant.

## 5. Deletions (teacher-personal mode)

- LiveViews: `Teacher.DashboardLive`, `SetupLive`, `ImportLive`, `LogLive`, `FicheLive`, `CoverageLive`, `LessonPlanLive`; `FichePrintController` + `FichePrintHtml` + template; `assets/js/hooks/module_layout.js` and its registration; the `:teacher_personal_routes` flag, its config line and router block; the `@moduledoc` "PAUSED" notices become moot.
- Tests: the 53 `:teacher_personal`-tagged tests and the tag exclusion in `test_helper.exs`.
- Domain: `Enrollment.add_student/2`, `Curriculum.create_teaching_context/3` (and the free-typed personal context read), `Organization.ensure_personal_workspace!/1`, `Workspaces.personal_scope/3`, `Scope.personal_context?/1`, `current_workspace_type` (always `:school`; remove the field and every branch on it), `Reference.default_calendar_preset/0`, `Academics.{Quota, FicheParser, FicheExtractor}` and their tests, `Curriculum` functions with no remaining caller after the LiveView deletions (the plan lists them from a grep).
- Kept: `ProgressionPlan/Module/Entry`, `LessonPlan/Step`, `TeachingLogEntry`, `Coverage`, `ModuleGrouping` resources and domain functions (combined courses create plans; a school progression UI may return), with their domain tests.

## 6. Tests and fixtures

- `TeacherAssistantWeb.ConnCase.register_and_log_in_user/1` creates a school with the user as head (`school_fixture` + `complete_school_setup!`) and puts the school id in the session; it returns `%{conn, workspace: school, actor: head, year}`.
- New `TeacherFixtures.school_teacher_fixture(school, head, attrs)` invites, accepts and assigns a plain teacher to a class; returns `%{teacher, membership, teaching_context}`.
- Files on the personal fixture are converted to school fixtures (marks_live, marks_summary_live, roster_live, marks_combined, marks_isolation, context_switcher_combined, teacher_context_controller, workspaces, calendar, school_shell, courses, and any other the plan's grep finds).
- New tests: (a) tenant isolation — for each multitenant resource, a row created under tenant A is not returned by a read under tenant B (table-driven); (b) a create without a tenant raises `Ash.Error.Invalid` for a non-global resource; (c) invitation token lookup works without a tenant; (d) `create_school` seeding rows carry the new workspace id; (e) one-active-year index rejects a second active year at the DB level; (f) each check constraint rejects an invalid value.

## 7. Verification gates (every task)

`mix ash.codegen --check` clean (after the task's own `--dev` codegen), `mix compile --warnings-as-errors`, `mix test` (no excluded tags remain), `mix precommit`. Whole-branch review at the end of each phase.

## 8. Risks

- A nested create inside a generic action without a tenant: Ash raises "requires a tenant"; test (b) and the domain tests catch it.
- Identity semantics change (tenant appended): existing uniqueness tests cover the intended behaviour; `SchoolInvitation.unique_token` explicitly global.
- Large mechanical fixture rewrite: per-task review; the login helper change is done first so every later task builds on it.
- Deleting `current_workspace_type` touches `Layouts.app` and several LiveViews' fallbacks (`if scope.current_workspace_type == :school`): those become "workspace present?" checks.
