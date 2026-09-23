# TeacherAssistant — full audit & school-focus decision (2026-09-23)

**Repo state:** `main` @ `1fc5547` (deps updated, usage_rules installed, 674 tests green).
**Method:** four independent read-only audits against the project's `.claude/skills`
(`ash-framework`, `phoenix-framework`) and `AGENTS.md`, plus a functional inventory and an
architectural review. Key numbers were re-verified by hand. Detailed reports:

| File | What it holds |
|---|---|
| [A-ash-usage-rules-audit.md](A-ash-usage-rules-audit.md) | 33 findings (ASH-01…33) vs the Ash / AshPhoenix / AshPostgres / AshAuthentication / AshOban rules, per-resource status table |
| [B-phoenix-liveview-audit.md](B-phoenix-liveview-audit.md) | 45 findings (WEB-01…45) vs the Phoenix / LiveView / HEEx rules and `AGENTS.md`, full route map, LiveView size table |
| [C-feature-inventory-and-pause-plan.md](C-feature-inventory-and-pause-plan.md) | user journeys, feature table with classification, shared-resource analysis, pause plan, gaps |
| [D-architecture-analysis.md](D-architecture-analysis.md) | domains, ER model, tenancy, authorization model, teacher/school duality, code health, risks |

This README is the synthesis and the decision record.

---

## 1. Executive summary

- **The deterministic core is good.** Marks, bulletins, coverage, fee balances, conduct and
  quotas are pure Decimal modules, each with its own test file. The transactional Ash generic
  actions (`Enrollment.:enroll_new`, `Mark.:upsert_all`, `CombinedCourse.:combine/:split`,
  `TimetableSlot.:place_combined`, `AttendanceEntry.:record_combined_period`) are idiomatic.
- **The security posture is not.** All 32 resources carry `policy always() → authorize_if always()`,
  no domain call passes an actor (1 hit in `lib/`, in auth overrides), and tenant isolation is
  caller discipline in ~15 LiveViews and 8 controllers. Several domain functions accept a bare
  enrollment id with no workspace check (`Fees.record_payment`, `Discipline.add_sanction`,
  `Attendance.justify_day`). The 2026-09-23 hardening spec is the right fix and is at step 0.
- **The school flow has one blocking functional hole:** a year created through the school wizard
  or Settings has **no terms and no séquences**. Only the personal teacher wizard calls
  `Organization.build_default_calendar/1`. Marks, results and bulletins are unusable for a school
  set up through the real UI; 20 test files mask this by building the calendar by hand.
- **Marks entry for school teachers lives in the "teacher" area.** `Teacher.MarksLive`,
  `MarksSummaryLive`, `RosterLive` and `TeacherContextController` are the only way a school
  teacher enters marks. They must **not** be paused; everything else under `/teacher/*` can be.
- **Data-layer hygiene debt:** 0 foreign-key indexes anywhere, 7 resources with raw `:uuid`
  `workspace_id` columns (no FK), 8 resources with no workspace column at all, 3 bare `:atom`
  attributes, unused deps (`ash_oban`, `ash_archival`, `ash_state_machine`, `oban_web`,
  `cinder`) and an Oban config with no Oban in the supervision tree.
- **Web-layer debt:** ~29 raw `<form>` / ~56 raw inputs instead of `<.form>`/`<.input>`, 0 LiveView
  streams, `Layouts.app` runs two DB queries on every render of every page, 15
  `String.to_existing_atom` on user input (crash on unknown value), 8 copies of the controller
  scope preamble, stale gettext `.pot` and 211/652 untranslated EN strings.

## 2. Product decision: school first

| Bucket | Content | Action |
|---|---|---|
| **SCHOOL-CORE (keep, finish)** | create school · setup wizard · members/roles/invitations · settings (profile, years, subject catalog) · classes + starter seeding · teacher assignments (TeachingContext) · combined courses · form master · enrollment + CSV import · periods + timetables + print · attendance roll call + SG register · sanctions/conduct · **marks entry (`/teacher/contexts/:id/*`)** · results/bulletins/print · operator verification | Focus of the next increments |
| **SCHOOL-LATER (park, keep reachable only for admins or hide)** | fees: `School.FeesLive`, `FeeTranche/Payment/FeeAdjustment/FeeBalance`, 61 tests | Hide the class-page link; no other inbound path |
| **TEACHER-PERSONAL (pause)** | personal workspace auto-creation · `Teacher.SetupLive` · `Teacher.DashboardLive` (`/teacher` landing) · fiche builder `FicheLive` + DnD hook · PDF import `ImportLive` · lesson plan `LessonPlanLive` + `FichePrintController` · `LogLive` · `CoverageLive` · personal roster writes | Router-level removal behind a compile-time flag, redirects moved to `/school` |
| **SHARED infra** | auth, locale, landing, Workspace/Scope, component kit, `/admin/schools` | Keep |

Pausing the personal surfaces also closes a real leak: in school scope, plans, logs, imports,
fiches and lesson plans are **workspace**-scoped, not teacher-scoped, so any member can read and
edit any colleague's plan (`Curriculum.fetch_owned_plan/2` checks workspace only).

## 3. Functional state of the school product

### Journeys that work today
1. Register / sign in → workspace resolution (personal workspace auto-created; school via
   membership) → header switcher.
2. `/schools/start` → `/schools/new` → transactional `Workspace.:create_school` (profile + head
   membership + subject catalog seeded from `SchoolTemplates`) → `/school`.
3. Blocking wizard (`:require_school_setup`): identity → year (+ starter classes) → classes →
   invite → `/school`.
4. Invitations with real Swoosh email, accept-with-signup, employment type.
5. Admin daily use: dashboard, classes, class page (enroll/transfer/withdraw, assign teacher
   per subject with coefficient, form master, combine/split), settings, periods, timetable, members.
6. Teacher in a school: class switcher → per-class rail → roster / marks / summary; attendance
   from "Mon emploi du temps" slot links.
7. Operator: `/admin/schools` verify/reject.

### Gaps blocking "create school, set subjects/classes/teachers; teachers do roll call and marks"
| # | Gap | Evidence | Severity |
|---|---|---|---|
| G1 | ~~School year has no terms/séquences~~ **Closed 2026-09-23** (`feat/school-calendar-courses`: proportional calendar template built on year creation) | wizard `create_year` and Settings submit `AcademicYear.:create_for_workspace` (no calendar); only `teacher/setup_live.ex:44` calls `build_default_calendar` | Blocking |
| G2 | ~~Roll call requires a placed slot~~ **Closed 2026-09-23** (periods seeded at school creation; assignment-based roll call). Was: requires periods **and** a placed timetable slot; wizard never calls `Attendance.build_default_periods/1`; `/school/periods` reachable only from Settings | Blocking for roll call |
| G3 | ~~No teacher entry point~~ **Closed 2026-09-23** (`/school/courses` hub, "Mes cours" rail item, plain-teacher landing). Was: no `/school/*` marks route, no "Notes" nav item, no "my assignments" on dashboard; `MarksLive` fallbacks push to `/teacher/setup` which bounces to `/school` (silent loop) | High |
| G4 | Operate gate (marks/attendance/print) needs a platform `:admin` to verify; no in-product promotion (`User.:promote_to_admin` unused) | High for onboarding |
| G5 | Config thin: no terms/séquences UI, mention thresholds hard-coded (`marks.ex:15-16`), no year edit/delete/archive | Medium |
| G6 | Roles coarse; `:hod`, `:guidance_counsellor`, `:librarian` grant nothing; plain teachers see members page and wizard | Medium |
| G7 | Cross-teacher leak on plan/log/import/fiche in school scope (closed by the pause) | High until paused |
| G8 | `TeachingContext.subject` is a string copy of `Subject.name`; spécialité stored in `serie` | Medium (deliberate, see 2026-09-17 spec) |
| G9 | Non-admin members of an unconfigured school are trapped on a wizard they cannot act on | Medium |
| G10 | Production mailer unconfigured; `POST /workspaces` orphaned; locale switch always redirects to `/teacher` | Low |

Test coverage by area (674 total): school identity/wizard/scope 87 · members/invites 20 ·
settings/years/subjects 24 · classes/assignments/enrollment/combined 89 · periods/timetable 35 ·
attendance/register 46 · discipline 49 · marks 67 · results/bulletins 36 · fees 61 ·
shared/auth/kit 22 · teacher-personal-only ≈116. Almost no negative-authorization or
cross-tenant tests.

## 4. Architecture assessment

- **Domains are a file split, not a boundary.** Nine Ash domains, but every resource still lives
  under `TeacherAssistant.Academics.*` (the 2026-09-18 sweep never moved them); domain names
  collide with resource names (`TeacherAssistant.Assessment` vs `Academics.Assessment`);
  cross-domain calls go in every direction.
- **Domain modules are hand-rolled context modules** (240–960 lines) of `Ash.Changeset.for_create
  |> Ash.create` wrappers, validations and multi-step orchestration outside transactions
  (`accept_invitation`, `duplicate_progression_plan`, term/sequence creation). ~45 `define`s
  exist; 0 resource `code_interface` blocks; `AshPhoenix` domain forms unused.
- **Tenancy:** no Ash multitenancy; `workspace_id` is accepted from input on every create;
  `:owned` read actions + `fetch_owned_*` wrappers are the only isolation. 7 resources have raw
  `:uuid` workspace columns, 8 have none (Term, Sequence, Assessment, Mark, ProgressionEntry,
  ProgressionModule, LessonPlan, LessonStep).
- **Authorization:** three overlapping mechanisms (inert Ash policies, the `Permissions` module
  with 72 web call sites, per-view `authorized?` helpers with divergent composition). The
  `Permissions` module is de facto authoritative. `Scope` already implements `Ash.Scope.ToOpts`
  but is never passed.
- **Teacher/school duality is woven into the model:** `Workspace.kind` + `owner_user_id`,
  `TeachingContext.teacher_user_id`/`class_group_id` nullable only for personal mode,
  `ProgressionPlan` dual owner, `Enrollment.add_student` vs `enroll_new`, `Scope.current_workspace_type`
  branches. It can be parked at router/nav level without touching the schema, but the nullable
  pivot FKs are exactly what the hardening policies would have to special-case. Decide now: if
  school-first is permanent, make them `allow_nil? false` and retire `Workspace.kind`.
- **Code health:** `curriculum.ex` 961 lines; six LiveViews > 600 lines; `load_user/1` defined
  16 times; mount preamble copied 14 times; period selector, print link, invite form and
  timetable grid copy-pasted; `Layouts.app` is ~300 lines with three hand-written nav rails.

## 5. Skill / usage-rule problems (consolidated top list)

Full detail with `file:line` in reports A and B. Ranked by impact for a multi-school product.

| Rank | Problem | IDs |
|---|---|---|
| 1 | Allow-all policies on all 32 resources; no actor threaded; `authorize :when_requested` everywhere | ASH-07, ASH-08, ASH-09, WEB-01 |
| 2 | Tenant isolation by convention; bare-id domain functions (`Fees`, `Discipline`, `Attendance`); unscoped `get_by: [:id]` defines; no multitenancy | ASH-10, ASH-24 |
| 3 | No FK indexes at all; 7 raw `workspace_id` uuids; no check constraints | ASH-25, ASH-19, ASH-28 |
| 4 | Business logic in domain functions instead of actions/validations; multi-write orchestration without transactions; notifications inside transactions in `CombinedCourse` | ASH-01, ASH-02, ASH-13, ASH-14 |
| 5 | Forms: raw `<form>`/`<input>` (29/56), `<.form :let>` and forms built in templates, submit bypassing `AshPhoenix.Form.submit`, `String.to_existing_atom` on user input (15 sites) | WEB-08, WEB-09, WEB-16, WEB-17 |
| 6 | `Layouts.app` runs 2 DB queries per render; double loads in mount + handle_params; N+1 loops; 0 streams | WEB-19, WEB-20, WEB-21, WEB-22, ASH-22, ASH-23 |
| 7 | 3 bare `:atom` attributes (project rule) | ASH-18 |
| 8 | Unused deps/config: `ash_oban`, `ash_archival`, `ash_state_machine`, `oban_web`, `cinder`; Oban configured but not supervised | ASH-32, WEB-29 |
| 9 | Resource namespace / domain naming collisions; no dependency direction | ASH-04 |
| 10 | i18n: stale `default.pot` (extract check fails), 211 untranslated EN msgids, mixed FR/EN msgids, auth/landing copy outside gettext, `<html lang="en">` | WEB-34, WEB-35, WEB-36, WEB-14 |
| 11 | Duplication: 8 controller scope preambles, helpers redefined 2–8×, UI fragments copy-pasted | WEB-02, WEB-27, WEB-28 |
| 12 | Tests: 261 raw `=~` assertions, no `Ash.Generator`, no `Ash.can?` tests, 131 `authorize?: false` in tests, one raw `Repo.delete` | WEB-37, ASH-29, ASH-30, ASH-31 |
| 13 | Hand-written migration importing app code (`20260811220000_backfill_progression_modules.exs`); stale `personal_workspaces` snapshot | ASH-26, ASH-27 |
| 14 | `User.:create` accepts `hashed_password` and `role`; no field policy on `hashed_password` | ASH-16, ASH-33 |

## 6. Pause plan (executed 2026-09-23, plan: docs/superpowers/plans/2026-09-23-school-focus-pause.md)

**Mechanism:** router-level removal behind `Application.compile_env(:teacher_assistant,
:teacher_personal_routes, false)` (same pattern as `:dev_routes`), not deletion (≈2,500 lines and
≈150 tests of working code the owner wants parked) and not a runtime flag (no infra, keeps dead
UI in the hot path).

**Do not pause:** `Teacher.MarksLive`, `MarksSummaryLive`, `RosterLive`, `TeacherContextController`,
class switcher + per-class rail in `Layouts`, `:require_teaching_scope`,
`Curriculum.fetch_assigned_teaching_context/2`, `list_units_for_scope/1`, Assessment/Mark,
Term/Sequence, `Reference.default_calendar_preset/0`, `Organization.build_default_calendar/1`.

**Steps:**
1. Split `live_session :teacher_workspace`: keep roster/marks/summary; flag off `/teacher`,
   `/teacher/setup`, `/teacher/import`, `/teacher/log`, `/teacher/plans/:id`,
   `/teacher/plans/:id/coverage`, `/teacher/entries/:id/fiche`, the fiche print route and the
   orphaned `POST /workspaces`.
2. Move every default redirect from `/teacher` to `/school` (or `/schools/new` when the user has no
   membership): `AuthController.success`, `live_no_user`, `LocaleController`,
   `WorkspaceController`, `SchoolInvitationController`, `TeacherContextController`, marks/summary/
   roster fallbacks, school LiveView non-school fallbacks.
3. Stop auto-creating personal workspaces in `Workspaces.scope_for/3`; `list_workspaces_for/1`
   returns schools only; keep `ensure_personal_workspace!` for fixtures until tests are migrated.
4. Nav: remove the personal `#main-nav` rail and the `/teacher/setup` callout; add a "Notes"
   rail item and a "no school yet" landing → `/schools/new`.
5. Hide the fees link on the class page (fees stay compiled and tested).
6. Tests: `@moduletag :teacher_personal` on the ≈25 personal-only files, excluded in
   `test_helper.exs`; convert the personal-mode cases of marks/roster/scope tests to school
   fixtures rather than skipping them.
7. Update `docs/PRODUCT.md` and `docs/DESIGN.md` to the school-first positioning.

## 7. Recommended order of work

1. **Pause teacher-personal + fees links** (section 6). Small, mechanical, closes G7, shrinks the
   surface the hardening work has to cover.
2. **Close G1 + G2 in the wizard**: `create_year` builds the default calendar and default periods;
   add a terms/séquences panel to Settings. Without this no school can enter a mark.
3. **G3 teacher surface**: `/school/marks` (or a "Notes" rail item) listing the teacher's
   assignments → existing marks LiveViews; fix the `/teacher/setup` fallback loop.
4. **Schema decisions before policies**: FK-backed `workspace_id` on the 7 raw-uuid resources,
   add FK indexes (`mix ash.codegen`), make `TeachingContext.teacher_user_id`/`class_group_id`
   non-null once teacher mode is retired, remove `Workspace.kind`. Evaluate Ash attribute
   multitenancy on `workspace_id`.
5. **Execute the authorization hardening spec (C)** with actor plumbing first
   (`scope: scope` on every write, `Scope.ToOpts` is ready), one negative `Forbidden` test per
   domain, then flip policies; remove bare-id domain functions.
6. **G4 verification onboarding** (operator promotion path, or relax the operate gate for
   self-verified pilots).
7. Hygiene batches in the background: 3 bare atoms → enums, unused deps, gettext extract +
   EN translation, controller scope plug, helper consolidation, form rules, streams for rosters.

---

## 8. Authorization end-state (decision discussion, 2026-09-23)

Agreed direction: **Ash policies are the single source of truth; the `Permissions` predicate
module is retired.** This amends the pending spec/plan
(`docs/superpowers/specs/2026-09-23-authorization-hardening-design.md`,
`docs/superpowers/plans/2026-09-23-authorization-hardening.md`) as follows.

| Pending plan says | Change to |
|---|---|
| `Permissions.*` stays as the "UX layer", bodies delegate to role constants | Replace each call site with the domain's generated `can_*?` function (or `Ash.can?`); delete each predicate when its last caller goes. Role sets per axis live on the `SchoolRole` enum (`SchoolRole.admin_roles/0`), not in a predicates module. |
| Six `Ash.Policy.SimpleCheck` modules + an `OwningWorkspace` resolver that loads membership at eval time | `expr` filter checks through real relationships (`exists(workspace.school_memberships, user_id == ^actor(:id) and active == true and ^:head in roles)`, `teaching_context.teacher_id == ^actor(:id)`). The resolver exists only because 7 resources have raw-uuid `workspace_id` and 8 have none; fix the schema instead (section 10). |
| Domains stay `authorize :when_requested`, every write passes `authorize?: true` by hand | `authorize :by_default` per domain once its writes are plumbed, so a forgotten actor fails closed instead of silently bypassing (the spec's own top risk). |
| Reads stay `authorize_if always()` | Read policies too (membership filter), or structural isolation via multitenancy (section 10). Listing another school's students is as bad as writing them. |
| "No schema, no migration" | Preceded by a schema pass: `belongs_to :workspace` everywhere, FK indexes, check constraints. |
| Nil `teacher_id` / `class_group_id` / dual-owner plan special-cased in every ownership check | Pause teacher-personal mode first (section 6); the nils disappear with it. |

Order: pause → schema pass → C (rewritten on `expr` checks) → verification onboarding.
Keep from the plan: tiered matrix, domain-by-domain rollout gated on green tests, non-member
negative test per domain, operate gate on marks + attendance only. Update the plan's pinned
versions (Ash 3.33.9, LiveView 1.2).

## 9. Resource field gaps (school scope)

The resource set is complete for "create school, subjects, classes, teachers, roll call, marks".
Field/constraint gaps:

| Resource | Gap | Priority |
|---|---|---|
| `Student` | no `birth_date`, `birth_place`, `guardian_name`, `guardian_phone` (bulletin header per `docs/domain/04 §4`) | Now |
| `AcademicYear` | no "one active year per workspace" constraint → partial unique index on `[:workspace_id]` where `active` | Now |
| `TeachingContext` | add `subject_id` beside the denormalised string; `combined_course_id` declared twice (attribute + `belongs_to`); personal quota fields (`annual_hours`, `target_module_count`, `target_lesson_count`) become dead weight after the pause | Schema pass |
| `ClassGroup` | `form_master_user_id` declared twice; `:form_master` also exists as a `SchoolRole` value → keep the FK on the class, drop the role value | Schema pass |
| `Workspace` | `kind`, `owner_user_id`, `unique_owner_user` retire with the pause; a school is identified by `SchoolProfile` | Pause |
| `Mark` | nil score doubles as "absent"; explicit `absent` boolean later | Later |
| `Term` | position only; label derived in UI (fine). Wizard never creates terms (gap G1) | G1 fix |
| `Subject` | `default_coefficient` is per school; série/level-dependent coefficients need a `(subject, level, serie)` table in the grading-config increment. Per-class coefficient on `TeachingContext` covers today | Later |
| `SchoolMembership` | `:hod` needs a department/subject link to mean anything | Later |
| all | no `check_constraints` anywhere (score in 0..max_score, positive amounts, ordered sequence dates) | Schema pass |
| `SchoolProfile`, `SchoolInvitation`, `Period`, `Sequence`, `Enrollment`, `AttendanceEntry`, `TimetableSlot` | fine as they are | — |

## 10. Multitenancy design

**Mental model:** the **school is the tenant**. The **academic year is not a tenant**; it is an
operational partition *inside* the tenant (`Scope.current_academic_year`), selected by explicit
`academic_year_id` arguments on read actions, exactly as today. Two levels:

```
School (Workspace)  ── tenant: hard isolation, data layer, never crossed by a query
  └─ AcademicYear   ── partition: a filter, switchable, archivable, crossed on purpose
       └─ ClassGroup, Enrollment, TeachingContext, Term → Sequence → Assessment → Mark, …
```

**Strategy: Ash attribute multitenancy on `workspace_id`** (`multitenancy do strategy :attribute;
attribute :workspace_id end`). Not schema-per-tenant (`:context`): hundreds of small schools,
teachers belong to several schools, the operator lists schools across tenants, and one migration
per school is operational overhead with no isolation benefit here.

What it gives structurally, replacing today's convention:
- every read is filtered by tenant automatically → `:owned` / `:assigned_in_school` read actions
  and the 14 `fetch_owned_*` wrappers stop being the isolation mechanism;
- every create sets `workspace_id` from the tenant → no more `accept [:workspace_id]` from input;
- a call without a tenant fails (`require_tenant?` default) → forgotten scoping is loud;
- bare-id domain functions (`Fees.record_payment`, `Discipline.add_sanction`,
  `Attendance.justify_day`) become safe by construction because the `Ash.get` inside them is
  tenant-filtered;
- policies then express only **roles and ownership**, never "which school".

**Where the tenant comes from:** `TeacherAssistant.Scope` already implements `Ash.Scope.ToOpts`
(`scope.ex`); `get_tenant/1` currently returns `:error`. Make it return
`{:ok, scope.current_workspace.id}` and pass `scope: scope` on every domain call (actor + tenant
+ context in one option). LiveViews already hold the scope in `@current_scope`; controllers get it
from the scope plug recommended in WEB-02.

**Per-resource classification:**

| Class | Resources | Setting |
|---|---|---|
| Tenant-owned, already FK | SchoolInvitation, AcademicYear, Subject, Period, ClassGroup, Student, Enrollment, TeachingContext, CombinedCourse, ProgressionPlan, TeachingLogEntry | add `multitenancy` block |
| Tenant-owned, raw uuid today | AttendanceEntry, TimetableSlot, SanctionEntry, ConductMark, FeeTranche, Payment, FeeAdjustment | convert to `belongs_to :workspace` + `multitenancy` |
| Tenant-owned, no column today | Term, Sequence, Assessment, Mark, ProgressionEntry, ProgressionModule, LessonPlan, LessonStep | add `belongs_to :workspace` (attribute strategy needs the column on every resource; it also gives an indexable tenant column instead of a 3-hop join) + `multitenancy`; backfill via generated migration from the parent chain |
| Tenant itself / cross-tenant | Workspace, SchoolProfile, User, Token | **no** multitenancy (operator lists schools; `scope_for` runs before a tenant is known) |
| Tenant-owned but read before tenant is known | SchoolMembership (listing a user's schools), SchoolInvitation (lookup by token on accept) | `multitenancy` with `global? true` so these two reads work without a tenant; all other actions still tenant-scoped |

**Academic year handling:** keep year as an explicit argument/preparation, not a second tenancy.
Reasons: cross-year reads are legitimate (repeaters, promotion, year archive, transfers), and Ash
has one tenant slot. Convention: read actions on year-partitioned resources take
`academic_year_id` (already the pattern); `Scope.current_academic_year` is the default the web
layer passes; the "one active year per workspace" partial unique index guards the default.

**Migration path** (fits the schema pass in section 7 step 4):
1. Add `belongs_to :workspace` to the 15 resources lacking a FK; generated migration + backfill
   from parents; FK indexes for all references.
2. Implement `Scope.get_tenant/1`; add `scope:` to every domain call (the same plumbing the C plan
   needs for the actor, done once).
3. Add the `multitenancy` block domain by domain, running the suite each time; fixtures must set
   the tenant (`Ash.Changeset.set_tenant` or `tenant:` option).
4. Delete `:owned` read actions, `fetch_owned_*` wrappers and `accept [:workspace_id]` as each
   domain flips.
5. Then write the C policies as role/ownership `expr` checks only.

Already noted before this section: README §4 "Tenancy", §7 step 4, report A ASH-10/ASH-19/ASH-24,
report D §3 and risks #2/#5.
