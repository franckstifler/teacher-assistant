# P2.2 — School Enrollment & Shared Classes (Design)

**Date:** 2026-07-03
**Status:** Approved
**Depends on:** P2.1 school-workspace foundations (merged, `b62a7a1`)
**Feeds:** P2.3 (bulletins & statistics), P2.4 (fees & access control)

## Goal

Make a school workspace *usable for teaching*: the school owns its academic year,
classes, and student enrollment; teachers who are members get **teaching
assignments** (subject × class) and work with their existing tools (marks,
progressions, coverage, fiches, log) unchanged inside the school workspace.

Decisions locked during brainstorming:

1. **School-owned teaching contexts** — marks/progressions/fiches at a school
   live in the school workspace (the school's registers), not the teacher's
   personal workspace.
2. **One teacher UI everywhere** — `/teacher/*` is unblocked under school scope
   (replacing the P2.1 `:require_personal_scope` guard) rather than duplicated.
3. **Admin gate = Head or Vice-Principal** — one coarse `Permissions.admin?/1`
   for year/classes/enrollment/assignments (Censeur builds timetables per
   Décret 2001/041). Finer axes wait for real need (P2.4).
4. **Durable-student model (Enrollment entity)** — `Student` becomes a person
   record; a new `Enrollment` carries the class link per year. Unified across
   personal and school workspaces.
5. **Bulk import included** — school enrollment ships with the adapted import
   stepper; one-at-a-time enrollment alone is not viable for 60–100+ student
   classes.

## Section 1 — Data model

### Student (modified)

- Add `workspace_id` (required, `belongs_to :workspace`).
- Remove `class_group_id` and `repeater` (both move to Enrollment).
- Keep `full_name`, `sex`, `matricule` (optional).
- Identity: **matricule unique per workspace** — partial unique index, only
  where `matricule IS NOT NULL`.

### Enrollment (new resource, `TeacherAssistant.Academics.Enrollment`)

- `student_id` (required), `class_group_id` (required), `academic_year_id`
  (required), `workspace_id` (required, denormalized for flat scoping).
- `status`: **`Ash.Type.Enum`** `TeacherAssistant.Academics.EnrollmentStatus`,
  values `[:inscription, :reinscription]`, default `:inscription`.
- `repeater`: boolean, default `false` (per-year property, moved from Student).
- Identity: `unique_enrollment_per_year` on `[:student_id, :academic_year_id]`
  — a student is in exactly one class at a time; **mid-year transfer = update
  `class_group_id`** on the existing enrollment.
- Standard house pattern: `uuid_v7_primary_key`, `timestamps()`,
  `Ash.Policy.Authorizer` with `policy always()`.

### TeachingContext (modified)

- Add `teacher_user_id` (optional, `belongs_to` the Accounts user).
  `nil` = personal-workspace context; set = school teaching assignment.
  References the **user**, not the membership, so contexts survive membership
  role edits. Assignment creation requires an *active* membership (validated in
  the context layer, not the DB).
- `class_group_id` required for school contexts (school assignment is always
  subject × class); stays optional for personal contexts (context-layer rule,
  not a DB constraint).
- Identities: keep `unique_context` `(workspace, year, subject, level, serie)`
  **restricted to personal contexts** (partial: `WHERE teacher_user_id IS
  NULL`); add `unique_school_assignment` `(workspace, year, class_group_id,
  subject)` partial `WHERE teacher_user_id IS NOT NULL` — **one teacher per
  subject per class**; reassignment = change `teacher_user_id`.
- Cleanup while in the file: convert `subsystem` from bare `:atom` to the
  existing `TeacherAssistant.Academics.Subsystem` enum (per project rule:
  never bare `:atom` attributes).

### Untouched

- `Mark` (keyed on `student_id` — survives the refactor as-is), `Assessment`,
  `Sequence`, `Term`, `AcademicYear` (already workspace-scoped; a school
  creates/activates its own), lesson plans, progression plans.

### Migration (single, hand-reviewed, data-preserving)

`mix ash.codegen p2_2_enrollments` then hand-rewrite to be strictly
additive-then-backfill-then-drop, in one transaction:

1. Add `students.workspace_id` (nullable at first); backfill via join through
   `class_groups`; then set NOT NULL.
2. Create `enrollments`; backfill one row per student from its old
   `(class_group_id, academic_year_id via class_group, repeater)` with status
   `:inscription`.
3. Drop `students.class_group_id` and `students.repeater` only after backfill.
4. Add `teaching_contexts.teacher_user_id` + the two partial unique indexes;
   replace the old full unique index with the personal-only partial one.

Verify against a seeded dev DB (existing personal-workspace data round-trips:
same roster, same marks) before the task is green.

## Section 2 — Scope resolution & teacher experience

### `Workspaces.scope_for/3` school branch

Now resolves, instead of returning nils:

- `current_academic_year`: the school's active year via the existing
  `Academics.current_academic_year/1` (already workspace-generic).
- `current_context`: resolved among **only this user's assigned contexts**
  (`teacher_user_id == user.id`, active year), honoring the same `context_id`
  param + fallback-to-first logic as personal scope.

### Route guard

Replace `on_mount(:require_personal_scope)` with
`on_mount(:require_teaching_scope)`:

- Personal scope → always allowed (today's behavior).
- School scope → allowed iff the member has ≥ 1 teaching assignment in the
  active year; otherwise redirect to `/school` (e.g. a Bursar with no classes
  never lands on marks pages).
- Router keeps the two `ash_authentication_live_session` blocks; only the
  on_mount of the teacher block changes.

### Teacher pages under school scope

- **Context switcher** lists the member's assignments ("Maths — 6e A"). Marks,
  progression, coverage, fiches, teaching log work unchanged (they already
  write against `current_context` / `workspace_id`).
- **Roster page read-only under school scope**: teachers see their class list
  (G/F counts, matricules, repeater) but add/edit/import/delete controls are
  hidden — enrollment belongs to `/school/*`. Under personal scope the roster
  keeps editing; its add/import paths now create Student + Enrollment pairs
  under the hood, with identical UX.
- **Setup page (`/teacher/setup`) stays personal-only**: under school scope it
  redirects to `/school` (school structure is managed there).
- **Fiche print cartouche** uses the school workspace's `name` as
  *établissement* when in school scope.
- **Write-guard story**: mutations on `/teacher/*` already scope by
  `current_context`; under school scope that context is provably assigned to
  the actor by scope resolution — no extra per-page re-checks.

## Section 3 — School admin UI

All admin mutations double-gated (hidden in UI **and** re-checked server-side
per handler via `Permissions.admin?/1` = Head or Vice-Principal), with every
target lookup scoped to the current school workspace (P2.1 pattern).

### `/school/settings` — year management added

Create an academic year; activate it (one active per workspace, existing
semantics). Rename stays.

### `/school/classes` — classes list

Each class: label, level, série, subsystem, effectif (enrollment count),
assigned-subjects count. Create/edit; delete blocked with a clear message when
enrollments or assignments exist.

### `/school/classes/:id` — class detail, two panels

**Roster panel**

- Enrolled students: name, sex, matricule, status (inscription/réinscription),
  repeater.
- Enroll one student: search existing school students by matricule/name first
  (re-enrollment/transfer case) or create new (inscription).
- Transfer to another class (updates the enrollment's `class_group_id`);
  remove enrollment.
- Duplicate matricule rejected by the DB identity, surfaced as a friendly
  message.

**Assignments panel**

- Rows: subject × teacher × weekly hours.
- Assign: pick an **active** member + subject + weekly hours → creates the
  school `TeachingContext` (level/série/subsystem derived from the class).
- Reassign: swap `teacher_user_id`. Remove: delete context — **blocked with a
  warning if it has marks/progressions/plans** (`{:error, :has_data}`).

### `/school/classes/:id/import` — bulk enrollment

Existing 3-step import stepper adapted: paste/CSV → columns name, sex,
matricule, repeater. Matching rule: a row whose matricule matches an existing
school student **re-enrolls** that student (status `:reinscription`) instead
of duplicating; matricule-less rows always create (status `:inscription`).
Rows whose matricule is already enrolled this year are flagged as conflicts,
not silently skipped.

### `/school` dashboard

Upgraded from stub: stats (classes, students enrolled, teachers with
assignments) + setup-gate prompts (no year → create year; no classes → create
class).

### Navigation

School nav gains **Classes** between Dashboard and Members. FR/EN throughout;
gettext extract + FR fill is the final task; `mix precommit` gates every task.

## Section 4 — Error handling & testing

### Error handling

Context functions return tagged errors, surfaced as flash/inline messages
(never raw Ash errors): `{:error, :duplicate_matricule}`,
`{:error, :not_assignable}` (inactive member), `{:error, :has_data}` (delete
class/assignment with dependents), `{:error, :already_enrolled}`.

### Testing

- **Context tests (DataCase)**: Enrollments — enroll, transfer, re-enroll,
  duplicate matricule, import matching (matricule match → réinscription,
  no matricule → create, same-year duplicate → conflict). Assignments —
  assign, reassign, one-per-subject-per-class, inactive-member rejection,
  delete-with-data blocked.
- **Scope tests**: school branch resolves year + assigned contexts;
  `require_teaching_scope` redirects a no-assignment member to `/school` and
  admits an assigned teacher; personal scope unaffected.
- **LiveView tests (ConnCase)**: classes list, class detail (both panels;
  admin-gated + forged-event rejection for non-admin members), import flow,
  roster read-only under school scope, setup redirect under school scope.
- **Regression**: full existing suite must stay green — personal roster/import
  paths change internally (Student + Enrollment) with identical behavior.

### Execution

Subagent-driven development on branch `feat/p2-2-school-enrollment`:
~10 tasks, fresh implementer + task review per task, final whole-branch
review, ledger at `.superpowers/sdd/progress.md`.

## Out of scope (later increments)

- Subject coefficients, moyenne générale, rank, bulletins, class councils →
  **P2.3**.
- Fees, tranches, receipts, access gating → **P2.4**.
- Multi-year student history views, cumulative records (the Enrollment model
  enables them; no UI now).
- Timetables/schedules; HOD subject-coordination views; fine-grained
  permission axes.
