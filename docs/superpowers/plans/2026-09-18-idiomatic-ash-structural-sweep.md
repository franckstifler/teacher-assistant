# Idiomatic Ash Structural Sweep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the whole app to idiomatic Ash — `code_interface`, action transactions + generic actions, `AshPhoenix.Form`, enums-with-labels, calculations/aggregates, notifiers/PubSub — without changing observable behavior.

**Architecture:** The 12 hand-written context modules dissolve: reads/updates become `code_interface` defines, orchestration becomes resource actions with `transaction? true`. The 1440-line `academics.ex` god-domain splits into focused domains (Organization, Enrollment, Curriculum, Assessment, Attendance, Discipline, Timetabling, Fees) by reassigning each resource's `domain:`; module namespaces stay put. Authorization is centralized to a per-domain "off until requested" posture so item C can flip it on later.

**Tech Stack:** Elixir 1.20-rc/OTP 29, Phoenix 1.8, Ash 3.33 + AshPostgres, AshPhoenix, AshAuthentication, LiveView 1.1, Gettext (FR default).

**Spec:** `docs/superpowers/specs/2026-09-18-idiomatic-ash-structural-sweep-design.md`

## Global Constraints

- **Behavior-preserving.** No observable behavior changes. Existing test *assertions* are frozen; only call syntax changes when a call site modernizes.
- **Green at every commit.** `mix test` must report 0 failures (currently **632 tests**) at the end of every task. Never commit red.
- **Branch:** all work on `refactor/idiomatic-ash-sweep` (already created off merged `main`).
- **No raw `Repo`** in `lib/teacher_assistant` domain code by the end.
- **No `authorize?: false`** call-site flags by the end; authorization is domain-configured off (item C turns it on).
- **Snapshots:** after any resource change, run `mix ash.codegen <name>` and **commit** the regenerated `priv/resource_snapshots/**` and any migration. If `ash.codegen` emits an *unexpected* migration (schema change), STOP and reconcile — this sweep expects none.
- **Enums:** stored values never change (no data migration). FR is the default locale; extract new gettext strings (`mix gettext.extract && mix gettext.merge priv/gettext`), no fuzzy FR.
- **Precommit:** `mix precommit` does NOT gate on warnings and its format step rewrites files — run `mix test` as the real gate.
- **Ash enums:** never bare `:atom` attributes; always `Ash.Type.Enum`.
- **Module namespaces unchanged.** Resources keep `TeacherAssistant.Academics.*` module names even when reassigned to a focused domain (rename is a deferred follow-up, out of scope).

---

## Phase A — Enums (independent, mechanical, no behavior change)

### Task A1: Collapse the 6 parallel label/order modules into their enums

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_type.ex`, `school_subsystem.ex`, `school_sector.ex`, `school_role.ex`, `cameroon_region.ex`, `school_verification_status.ex`
- Delete: `lib/teacher_assistant/accounts/school_types.ex`, `school_subsystems.ex`, `school_sectors.ex`, `school_roles.ex`, `cameroon_regions.ex`, `school_verification_statuses.ex`
- Modify (call sites): `lib/teacher_assistant_web/live/school/members_live.ex`, `settings_live.ex`, `admin/schools_live.ex`, `onboarding/create_school_live.ex`

**Interfaces:**
- Produces: `SchoolType.label/1`, `SchoolType.values/0` (from `Ash.Type.Enum`, declaration order), and the same for the other five enums. Removes `SchoolTypes.all/0` and `SchoolTypes.label/1`.

- [ ] **Step 1: Add labels to the enum type.** In `school_type.ex`, add a gettext-backed `label/1` (and `description/1` only if the old module had one). `Ash.Type.Enum` already gives `values/0` in declaration order, replacing `@order`/`all/0`.

```elixir
defmodule TeacherAssistant.Accounts.SchoolType do
  use Ash.Type.Enum,
    values: [:lycee, :ces_ceg, :lycee_technique, :cetic, :gss, :ghs, :gbss, :gbhs, :gtc, :gths, :sar_sm]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:lycee), do: gettext("Lycée")
  def label(:ces_ceg), do: gettext("CES / CEG")
  def label(:lycee_technique), do: gettext("Lycée technique")
  def label(:cetic), do: gettext("CETIC")
  def label(:gss), do: gettext("Government Secondary School (GSS)")
  def label(:ghs), do: gettext("Government High School (GHS)")
  def label(:gbss), do: gettext("Govt Bilingual Secondary School (GBSS)")
  def label(:gbhs), do: gettext("Govt Bilingual High School (GBHS)")
  def label(:gtc), do: gettext("Government Technical College (GTC)")
  def label(:gths), do: gettext("Government Technical High School (GTHS)")
  def label(:sar_sm), do: gettext("SAR/SM")
end
```

- [ ] **Step 2: Repeat for the other five** (`school_subsystem.ex`, `school_sector.ex`, `school_role.ex`, `cameroon_region.ex`, `school_verification_status.ex`) — copy each `label/1` body verbatim from its parallel module; take value order from the parallel module's `@order`.

- [ ] **Step 3: Update call sites.** Replace every `SchoolTypes.label(x)`→`SchoolType.label(x)`, `SchoolTypes.all()`→`SchoolType.values()`, and likewise for the other five. Find them:

```bash
grep -rn "SchoolTypes\.\|SchoolSubsystems\.\|SchoolSectors\.\|SchoolRoles\.\|CameroonRegions\.\|SchoolVerificationStatuses\." lib/
```

- [ ] **Step 4: Delete the six parallel modules.**

```bash
git rm lib/teacher_assistant/accounts/school_types.ex lib/teacher_assistant/accounts/school_subsystems.ex lib/teacher_assistant/accounts/school_sectors.ex lib/teacher_assistant/accounts/school_roles.ex lib/teacher_assistant/accounts/cameroon_regions.ex lib/teacher_assistant/accounts/school_verification_statuses.ex
```

- [ ] **Step 5: Compile + extract gettext + test.**

Run: `mix compile --warnings-as-errors && mix gettext.extract && mix gettext.merge priv/gettext && mix test`
Expected: compiles clean, 632 passing.

- [ ] **Step 6: Commit.**

```bash
git add -A && git commit -m "refactor: fold enum label/order modules into their Ash.Type.Enum"
```

### Task A2: Add `label/1` to UI-surfaced label-less enums

**Files:**
- Modify: `lib/teacher_assistant/academics/subject_category.ex`, `attendance_status.ex`, `payment_method.ex`, `day_of_week.ex`, `period_kind.ex`, `sanction_type.ex`, `enrollment_status.ex`, `sex.ex`, `subsystem.ex`
- Modify (call sites): any LiveView/HEEx that hand-maps these atoms to display text.

**Interfaces:**
- Produces: `SubjectCategory.label/1` (+ the other eight). No signature elsewhere depends on this yet.

- [ ] **Step 1: Add gettext `label/1` to each enum.** Example (`subject_category.ex`):

```elixir
defmodule TeacherAssistant.Academics.SubjectCategory do
  use Ash.Type.Enum, values: [:general, :language, :technical]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:general), do: gettext("General")
  def label(:language), do: gettext("Language")
  def label(:technical), do: gettext("Technical")
end
```

- [ ] **Step 2: Replace hand-mapped label logic in the web layer** with `<Enum>.label/1`. Find inline maps:

```bash
grep -rn "case .*category\|:general ->\|:technical ->\|attendance_status\|payment_method" lib/teacher_assistant_web/ | grep -i "label\|->"
```

Convert any `case cat do :general -> "General" ...` to `SubjectCategory.label(cat)`. If none exists (labels were built ad hoc at the call), just make the call use `label/1`.

- [ ] **Step 3: Extract gettext + test.**

Run: `mix gettext.extract && mix gettext.merge priv/gettext && mix test`
Expected: 632 passing.

- [ ] **Step 4: Commit.**

```bash
git add -A && git commit -m "refactor: expose gettext label/1 on UI-surfaced enums"
```

---

## Phase B — Domain scaffolding

### Task B1: Create the focused domains, reassign resources, centralize auth

**Files:**
- Create: `lib/teacher_assistant/organization.ex`, `enrollment.ex`, `curriculum.ex`, `assessment.ex`, `attendance.ex`, `discipline.ex`, `timetabling.ex`, `fees.ex` (each a `TeacherAssistant.<Name>` domain)
- Modify: every resource file's `domain:` option (27 resources) to point at its new domain
- Modify: `config/config.exs` (`ash_domains` list)
- Modify: `lib/teacher_assistant/academics.ex`, `accounts.ex` — set the `authorization` block; leave their existing functions in place FOR NOW (Phase C empties them)

**Interfaces:**
- Produces: 8 new domain modules + `Accounts`, each with authorization "off until requested". Resource→domain mapping per spec §1.

- [ ] **Step 1: Confirm the exact Ash 3 domain-auth DSL** for "authorize only when `authorize?: true` is passed" against the installed version:

```bash
grep -rn "when_requested\|authorize " deps/ash/lib/ash/domain/dsl.ex | head
```

Use the atom that means *do not authorize unless asked* (expected: `authorize :when_requested`).

- [ ] **Step 2: Create each focused domain module.** Example (`curriculum.ex`):

```elixir
defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  authorization do
    authorize :when_requested
  end

  resources do
    resource TeacherAssistant.Academics.Subject
    resource TeacherAssistant.Academics.TeachingContext
    resource TeacherAssistant.Academics.CombinedCourse
    resource TeacherAssistant.Academics.ProgressionPlan
    resource TeacherAssistant.Academics.ProgressionEntry
    resource TeacherAssistant.Academics.ProgressionModule
    resource TeacherAssistant.Academics.TeachingLogEntry
    resource TeacherAssistant.Academics.LessonPlan
    resource TeacherAssistant.Academics.LessonStep
  end
end
```

Repeat for Organization (Workspace, AcademicYear, Term, Sequence), Enrollment (ClassGroup, Student, Enrollment), Assessment (Assessment, Mark), Attendance (Period, AttendanceEntry), Discipline (SanctionEntry, ConductMark), Timetabling (TimetableSlot), Fees (FeeTranche, FeeAdjustment, Payment).

- [ ] **Step 3: Point each resource at its new domain.** In every resource, change `domain: TeacherAssistant.Academics` → its focused domain (e.g. `use Ash.Resource, domain: TeacherAssistant.Curriculum, ...`). Also add the `authorization` block placeholder if resources declare their own; keep existing `policy always()`.

- [ ] **Step 4: Update `ash_domains`.** In `config/config.exs`, replace the Academics entry with the 8 new domains (keep `Accounts`):

```elixir
config :teacher_assistant,
  ash_domains: [
    TeacherAssistant.Accounts,
    TeacherAssistant.Organization,
    TeacherAssistant.Enrollment,
    TeacherAssistant.Curriculum,
    TeacherAssistant.Assessment,
    TeacherAssistant.Attendance,
    TeacherAssistant.Discipline,
    TeacherAssistant.Timetabling,
    TeacherAssistant.Fees
  ]
```

- [ ] **Step 5: Add the `authorization` block to `Accounts`** (and, temporarily, keep `Academics` compiling as an empty/legacy domain — it will be deleted in Task C12). Set `authorize :when_requested` on `Accounts`.

- [ ] **Step 6: Regenerate snapshots (expect no migration), compile, test.**

Run: `mix ash.codegen reassign_domains && mix compile --warnings-as-errors && mix test`
Expected: NO new migration file (domain grouping is compile-time); if one appears, STOP. 632 passing.

- [ ] **Step 7: Commit.**

```bash
git add -A && git commit -m "refactor: split academics into focused domains; centralize auth posture"
```

---

## Phase C — Actions + code_interface (context modules dissolve)

**Pattern for every Phase C task** (behavior-preserving relocation):
1. For each *read/get/list/simple-update* function in the context module, add a matching action on the resource (if not already a default) and a `define` in the owning domain's `code_interface`, preserving the public callable name where a test/LiveView uses it.
2. For each `Repo.transaction` orchestration, add a **generic action** (`action :name, :type do run ... end` or a create/update action) with `transaction? true` on the owning resource.
3. Update all call sites (LiveViews, controllers, other domains, tests) to the new idiomatic call. Assertions unchanged.
4. Delete the context module.
5. `mix ash.codegen <name>` (commit snapshots), `mix test` green, commit.

**`code_interface` example** (Enrollment domain):

```elixir
resources do
  resource TeacherAssistant.Academics.SchoolMembership do
    define :list_members, action: :active_for_workspace, args: [:workspace_id]
  end
end
```

**Generic transactional action example** (replacing a `Repo.transaction`):

```elixir
# in CombinedCourse
actions do
  action :combine, :struct do
    constraints instance_of: __MODULE__
    argument :context_ids, {:array, :uuid}, allow_nil?: false
    run fn input, _ctx ->
      Ash.DataLayer.transaction(__MODULE__, fn ->
        # ...the existing Courses.combine/1 body, returning {:ok, course} or Ash.DataLayer.rollback/2
      end)
    end
  end
end
```

### Task C1: Accounts — memberships, invitations, school creation

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_membership.ex`, `school_invitation.ex`, `school_profile.ex`, `workspace.ex` (Organization)
- Modify: `lib/teacher_assistant/accounts.ex` (add code_interface; remove the hand-written fns as they migrate)
- Delete: `lib/teacher_assistant/accounts/schools.ex`
- Modify (call sites): `lib/teacher_assistant_web/live/onboarding/create_school_live.ex`, `school/members_live.ex`, `school/settings_live.ex`, `controllers/school_invitation_controller.ex`, `controllers/workspace_controller.ex`, `plug/*`, and tests under `test/teacher_assistant/accounts/`

**Interfaces:**
- Produces (idiomatic call sites; names may modernize but keep intent):
  - `Accounts.create_school(user, attrs)` → a `Workspace :create_school` action (below) or domain define.
  - `Accounts.list_members(workspace)`, `list_pending_invitations/1`, `fetch_school_membership/2`, `update_member_roles/2`, `deactivate_member/1`, `invite_member/3`, `fetch_invitation_by_token/1`, `revoke_invitation/1`, `accept_invitation/2`, `fetch_school_profile/1`, `update_school_profile/2`, `verify_school/3`, `reject_school/3`, `list_unverified_schools/0`, `list_workspaces_for/1`, `rename_school/2`.

- [ ] **Step 1: Model `create_school` as a Workspace action with after_action.** On `Workspace` (Organization domain) add:

```elixir
actions do
  create :create_school do
    accept [:name]
    argument :owner_user_id, :uuid, allow_nil?: false
    argument :profile, :map, default: %{}
    change set_attribute(:kind, :school)

    change after_action(fn _changeset, workspace, _ctx ->
      profile_attrs = Map.merge(%{school_type: :lycee, subsystem: :francophone, sector: :public, region: :centre, town: "—"},
        workspace.__metadata__[:profile] || %{})
      with {:ok, _p} <- create_profile(workspace, profile_attrs, owner_user_id),
           {:ok, _m} <- create_head_membership(workspace, owner_user_id),
           :ok <- seed_catalog(workspace) do
        {:ok, workspace}
      end
    end)
  end
end
```

Keep the seeding/profile/membership helpers as private module functions on Workspace (moved verbatim from `schools.ex`), calling `Ash.create(..., authorize?: false)` **replaced** by plain `Ash.create` (domain is now off-by-default). The whole create runs in Ash's create transaction — no `Repo.transaction`.

- [ ] **Step 2: Model the membership/invitation reads + updates as actions** and expose via `code_interface` on `Accounts` (or a dedicated Membership domain define). `last_head` guard moves to a validation in Task D1 — for now port the existing guard into the `:update`/`:deactivate` action as a `validate` calling a temporary private predicate (D1 replaces it with an aggregate).
- [ ] **Step 3: Port profile verify/reject/update** to `SchoolProfile` update actions (`:verify`, `:reject`, `:update`) with `code_interface` defines.
- [ ] **Step 4: Update call sites and tests** to the new names/args; keep assertions identical.
- [ ] **Step 5: Delete `schools.ex`.** `git rm lib/teacher_assistant/accounts/schools.ex`
- [ ] **Step 6: Codegen + test.** `mix ash.codegen accounts_actions && mix test` → expect no schema migration; 632 passing.
- [ ] **Step 7: Commit.** `git commit -am "refactor: Accounts school/membership/invitation logic onto resources + code_interface"`

### Task C2: Organization — personal workspace + calendar

**Files:** Modify `workspace.ex`, `academic_year.ex`, `term.ex`, `sequence.ex`; move `ensure_personal_workspace!/1` and year/term/sequence helpers off `academics.ex` onto these resources + `Organization` code_interface. Update call sites + `academics/seeding.ex` consumers.
- [ ] Steps: (1) add `Workspace :ensure_personal` action / `Organization.ensure_personal_workspace!/1` define; (2) year/term/sequence reads as actions+defines; (3) update call sites; (4) codegen+test; (5) commit `"refactor: Organization workspace/calendar onto resources"`.

### Task C3: Enrollment — classes, students, roster import

**Files:** Modify `class_group.ex`, `student.ex`, `enrollment.ex`; convert `enrollments.ex` import `Repo.transaction` to a generic `Enrollment :import` action (or `bulk_create`) with `transaction? true`; `code_interface` on `Enrollment`; delete `enrollments.ex`; update `school/enroll_import_live.ex`, `roster_live.ex`, controllers, tests.
- [ ] Steps: (1) import generic action; (2) list/get defines; (3) call sites; (4) `git rm enrollments.ex`; (5) codegen+test; (6) commit `"refactor: Enrollment onto resources; import as a transactional action"`.

### Task C4: Curriculum — subjects & teaching contexts (assignments)

**Files:** Modify `subject.ex`, `teaching_context.ex`; fold `subjects.ex` + `assignments.ex` into resource actions + `Curriculum` code_interface (`combinable_siblings/1` stays as a read action); delete both context modules; update `school/settings_live.ex`, `class_live.ex`, `classes_live.ex`, tests.
- [ ] Steps: (1) subject CRUD actions + defines (catalog manage/deactivate/delete, position); (2) teaching-context assignment actions + `combinable_siblings` read action; (3) call sites; (4) `git rm subjects.ex assignments.ex`; (5) codegen+test; (6) commit `"refactor: Curriculum subjects & assignments onto resources"`.

### Task C5: Curriculum — combined courses & unit resolution

**Files:** Modify `combined_course.ex`, `courses.ex`→resource, `progression_plan.ex`; convert `Courses.combine/1`, `split/1` (`Repo.transaction`) to generic actions on `CombinedCourse` with `transaction? true`; the double-count "unit plans only" filter becomes a **read action** `ProgressionPlan.unit_plans_for` (or calc, finalized in D3); `code_interface` defines (`combine_course`, `split_course`, `list_units_for_scope`, `unit_plans`, `list_union_students`, `contexts_of_course`, `get_course`); delete `courses.ex`; update `class_live.ex`, `teacher/log_live.ex`, dashboard/coverage, tests.
- [ ] Steps: (1) `:combine`/`:split` generic actions (port bodies; replace `Repo.transaction` with `Ash.DataLayer.transaction`); (2) unit-resolution read actions + defines; (3) call sites; (4) `git rm courses.ex`; (5) codegen+test (headline invariant: split destroys the course plan, combine starts fresh — assert unchanged); (6) commit `"refactor: combined-course combine/split & unit resolution as Ash actions"`.

### Task C6: Curriculum — progression, teaching log, lesson plans

**Files:** Modify `progression_plan.ex`, `progression_entry.ex`, `progression_module.ex`, `teaching_log_entry.ex`, `lesson_plan.ex`, `lesson_step.ex`; port `create_course_plan/2`, plan/entry/module/log reads and lesson-plan CRUD from `academics.ex` to actions + `Curriculum` code_interface; DnD reorder becomes an update action; update `teacher/fiche_live.ex`, `lesson_plan_live.ex`, `log_live.ex`, `coverage_live.ex`, print controllers, tests.
- [ ] Steps: (1) plan/entry/module actions+defines; (2) lesson-plan/step actions+defines + reorder; (3) call sites; (4) codegen+test; (5) commit `"refactor: progression, teaching log & lesson plans onto resources"`.

### Task C7: Assessment — assessments & marks (all-or-nothing)

**Files:** Modify `assessment.ex`, `mark.ex`; convert the marks upsert `Repo.transaction` + `persist_marks_notifications!` to a **bulk/generic** `Mark :upsert_all` action with `transaction? true` (notifier added in E1); `combined_assessments_for/2`, `create_combined_assessment/3` become actions; `code_interface` on `Assessment`; move remaining marks logic off `academics.ex`; update `teacher/marks_live.ex`, `marks_summary_live.ex`, bulletin/results, tests.
- [ ] Steps: (1) `Mark :upsert_all` transactional bulk action (per-class routing preserved; all-or-nothing); (2) assessment actions + combined-assessment actions + defines; (3) call sites; (4) codegen+test (assert all-or-nothing + per-class routing unchanged); (5) commit `"refactor: assessments & marks as transactional Ash actions"`.

### Task C8: Attendance — periods & attendance entries

**Files:** Modify `period.ex`, `attendance_entry.ex`; convert `attendance.ex` `combined_period_roll/3` + `record_combined_period/5` (`Repo.transaction`) to generic actions on `AttendanceEntry` (`transaction? true`, server-derived per-class routing); `code_interface` on `Attendance`; delete `attendance.ex`; update `school/attendance_live.ex`, `register_live.ex`, print controllers, tests.
- [ ] Steps: (1) `:record_combined_period` + `:combined_period_roll` actions; (2) period reads + defines; (3) call sites; (4) `git rm attendance.ex`; (5) codegen+test; (6) commit `"refactor: attendance onto resources; combined roll as a transactional action"`.

### Task C9: Discipline — sanctions & conduct

**Files:** Modify `sanction_entry.ex`, `conduct_mark.ex`; fold `discipline.ex` into resource actions + `Discipline` code_interface; delete `discipline.ex`; update `school/discipline_live.ex`, bulletin (conduct-in-average consumer), tests.
- [ ] Steps: (1) sanction/conduct actions + defines; (2) call sites; (3) `git rm discipline.ex`; (4) codegen+test; (5) commit `"refactor: discipline & conduct onto resources"`.

### Task C10: Timetabling — slots & combined placement

**Files:** Modify `timetable_slot.ex`; convert `timetables.ex` `place_combined_slot/3`, `clear_combined_slot/3` (`Repo.transaction`, with the `:exempt_class_group_ids` teacher-clash carve-out) to generic actions with `transaction? true`; `code_interface` on `Timetabling`; delete `timetables.ex`; update `school/timetable_live.ex`, `my_timetable_live.ex`, print controllers, tests.
- [ ] Steps: (1) place/clear combined generic actions (preserve clash carve-out); (2) slot reads + defines; (3) call sites; (4) `git rm timetables.ex`; (5) codegen+test; (6) commit `"refactor: timetabling onto resources; combined placement as actions"`.

### Task C11: Fees — tranches, adjustments, payments

**Files:** Modify `fee_tranche.ex`, `fee_adjustment.ex`, `payment.ex`; fold `fees.ex` into resource actions + `Fees` code_interface; delete `fees.ex`; update `school/fees_live.ex`, tests.
- [ ] Steps: (1) fee/payment actions + defines; (2) call sites; (3) `git rm fees.ex`; (4) codegen+test; (5) commit `"refactor: fees onto resources"`.

### Task C12: Retire the god-domain + slim Accounts

**Files:** Delete `lib/teacher_assistant/academics.ex` (now empty of logic); ensure `accounts.ex` holds only `use Ash.Domain`, `authorization`, `resources`, and `code_interface` (no hand-written orchestration — `create_user`/`get_user`/`promote_to_admin` become User actions + defines; `ensure_personal_workspace!` delegates to Organization define).
- [ ] Steps: (1) migrate the residual `academics.ex`/`accounts.ex` functions to actions+defines; (2) `git rm academics.ex`; (3) `grep -rn "TeacherAssistant.Academics\b" lib test` returns only resource-module references, no domain calls; (4) `mix compile --warnings-as-errors && mix test`; (5) commit `"refactor: remove the academics god-domain; Accounts is now declarative-only"`.

---

## Phase D — Calculations & aggregates

### Task D1: `last_head` as an aggregate + validation

**Files:** Modify `lib/teacher_assistant/accounts/school_membership.ex`; modify the role-change/deactivate actions to use it.

**Interfaces:** Produces a `count` aggregate `active_head_count` (or a resource calculation) and a validation `EnsureNotLastHead` used by `:update` (role change) and `:deactivate`.

- [ ] **Step 1: Add the aggregate.**

```elixir
aggregates do
  count :other_active_heads, :workspace_memberships do
    filter expr(active == true and :head in roles and id != parent(id))
  end
end
```

- [ ] **Step 2: Replace the temporary `last_head?` predicate** (from C1) in the `:update`/`:deactivate` validations with a validation that reads the aggregate and returns `{:error, :last_head}` when removing/deactivating the final head.
- [ ] **Step 3: Test** the existing last-head guard cases (unchanged assertions) + a focused test on the aggregate. `mix test`.
- [ ] **Step 4: Commit** `"refactor: last-head guard via Ash aggregate + validation"`.

### Task D2: Class averages & rankings as calculations/aggregates

**Files:** Modify `enrollment.ex`, `class_group.ex`, `mark.ex`; move the hand-computed average/ranking logic (currently in `academics.ex` bulletin/results helpers) into Ash calculations/aggregates read by `Assessment`/results LiveViews and the bulletin print controllers.
- [ ] Steps: (1) add `average`/`rank` calculations (identical formula, incl. coefficient weighting — dedupe `parse_coefficient` here since the file is open); (2) update results/bulletin consumers; (3) test against existing bulletin/ranking assertions (frozen numbers); (4) commit `"refactor: class averages & rankings as Ash calculations"`.

### Task D3: Double-count filter as a calculation/read action

**Files:** Finalize the C5 `unit_plans` read action as the single source; ensure dashboard, coverage, and teaching log all consume it (no residual `Enum.filter` double-count logic).
- [ ] Steps: (1) confirm one read action/calc; (2) remove any leftover manual filter; (3) test (unit-plans-only assertions unchanged); (4) commit `"refactor: unit-plan double-count filter as a single read action"`.

---

## Phase E — Notifiers / PubSub

### Task E1: Ash notifier for marks

**Files:** Modify `lib/teacher_assistant/academics/mark.ex` (+ `assessment.ex` if it publishes); delete the manual `persist_marks_notifications!` path; modify subscribing LiveViews (`teacher/marks_live.ex`, `marks_summary_live.ex`, results/dashboard) to subscribe to the notifier topics.

**Interfaces:** Produces PubSub broadcasts on `Mark` create/update to the topic the LiveViews already consume.

- [ ] **Step 1: Add the notifier.**

```elixir
use Ash.Resource,
  domain: TeacherAssistant.Assessment,
  data_layer: AshPostgres.DataLayer,
  notifiers: [Ash.Notifier.PubSub]

pub_sub do
  module TeacherAssistantWeb.Endpoint
  prefix "marks"
  publish_all :create, ["assessment", :assessment_id]
  publish_all :update, ["assessment", :assessment_id]
end
```

- [ ] **Step 2: Remove `persist_marks_notifications!`** and route the upsert-all action (C7) through the notifier (bulk actions support `notify?: true`).
- [ ] **Step 3: Update subscribers** to `Phoenix.PubSub.subscribe` the `marks:assessment:<id>` topic; keep the handle_info screen-update behavior identical.
- [ ] **Step 4: Test** — existing marks-live update behavior; add a focused test asserting a broadcast is published on save. `mix test`.
- [ ] **Step 5: Commit** `"refactor: marks notifications via Ash.Notifier.PubSub"`.

---

## Phase F — `AshPhoenix.Form`

**Form dialog pattern** (real AshPhoenix API):

```elixir
# mount/handle
form = AshPhoenix.Form.for_create(TeacherAssistant.Academics.Subject, :create, as: "subject") |> to_form()
# validate
form = AshPhoenix.Form.validate(socket.assigns.form, params)
# submit
case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
  {:ok, record} -> ...
  {:error, form} -> {:noreply, assign(socket, form: form)}
end
```

### Task F1: Convert the form dialogs

**Files:** `lib/teacher_assistant_web/live/onboarding/create_school_live.ex`, `school/classes_live.ex`, `school/members_live.ex`, `school/settings_live.ex`, `school/periods_live.ex`, `teacher/setup_live.ex`, `teacher/roster_live.ex`, `teacher/log_live.ex`, `teacher/fiche_live.ex`, `teacher/lesson_plan_live.ex`
- [ ] **Step 1:** Convert each dialog's `to_form(map)` to `AshPhoenix.Form.for_create/for_update` bound to the resource action from Phase C. Wire `phx-change` → `AshPhoenix.Form.validate`, `phx-submit` → `AshPhoenix.Form.submit`. Errors render from the Ash form.
- [ ] **Step 2:** Do this file-by-file, running `mix test` after each (keep failing set empty). Split the commit per 2-3 files if convenient.
- [ ] **Step 3: Commit** `"refactor: form dialogs on AshPhoenix.Form"` (or per-slice commits).

### Task F2: Convert the bulk grids (marks, attendance)

**Files:** `lib/teacher_assistant_web/live/teacher/marks_live.ex`, `school/attendance_live.ex`

**Interfaces:** Consumes the `Mark :upsert_all` (C7) and `AttendanceEntry :record_combined_period` (C8) actions.
- [ ] **Step 1:** Back the grid with an `AshPhoenix.Form` over the **bulk action** (one form whose params are the row list), not a per-row `to_form`. Preserve union roster, per-class routing, all-or-nothing save.
- [ ] **Step 2:** Test — the existing combined-marks and combined-attendance save behavior (assertions frozen: all-or-nothing, per-class routing). `mix test`.
- [ ] **Step 3: Commit** `"refactor: marks & attendance grids on bulk-action-backed AshPhoenix.Form"`.

---

## Phase G — Final sweep & verification

### Task G1: Prove the acceptance criteria

- [ ] **Step 1: No raw Repo in domains.** `grep -rn "Repo\." lib/teacher_assistant | grep -v "_web"` → empty (or only the Repo module definition).
- [ ] **Step 2: No authorize?: false.** `grep -rn "authorize?: false" lib/` → empty.
- [ ] **Step 3: No parallel label modules / context modules.** Confirm all 12 context modules + 6 parallel enum modules are deleted; `grep -rn "def label" lib/teacher_assistant` shows labels only on enum types.
- [ ] **Step 4: God-domain gone.** `test ! -f lib/teacher_assistant/academics.ex`.
- [ ] **Step 5: Snapshots committed, no stray migration.** `mix ash.codegen --check` clean; `git status` clean.
- [ ] **Step 6: Full suite.** `mix test` → ≥632 passing, 0 failures.
- [ ] **Step 7: Commit** any snapshot/format residue `"chore: idiomatic-ash sweep — final verification"`.

---

## Self-Review

**Spec coverage:** §1 domains→B1; §2 auth→B1/G1; §3 code_interface & module deletion→C1–C12/G1; §4 all 13 Repo.transaction sites→C1(create_school),C3(import),C5(combine/split),C7(marks),C8(attendance),C10(timetable) + G1 proof; §5 enums→A1/A2; §6 calcs/aggregates→D1–D3; §7 notifiers→E1; §8 AshPhoenix.Form (dialogs+grids)→F1/F2; §9 testing/migrations/non-goals→Global Constraints + G1. All spec sections map to tasks.

**Placeholder scan:** New-code steps (auth block, enum label, generic action, bulk action, aggregate, notifier, AshPhoenix.Form) show real code; relocation steps name exact files + the shared Phase-C pattern (stated once at the phase head, deliberately — not "similar to Task N", but a declared reusable procedure with per-task file lists and specifics). Verification commands are concrete.

**Type/name consistency:** `unit_plans` read action defined in C5, consumed in C6/D3/F. `Mark :upsert_all` defined C7, consumed E1/F2. `:record_combined_period` defined C8, consumed F2. `other_active_heads` aggregate defined D1, used by C1's actions (temporary predicate → aggregate). Auth atom (`:when_requested`) confirmed in B1 Step 1 before use.
