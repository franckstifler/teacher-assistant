# Idiomatic Ash structural sweep — design

**Date:** 2026-09-18
**Status:** approved for planning
**Branch (planned):** `refactor/idiomatic-ash-sweep`

## Problem

The codebase talks to Ash through a hand-written "context module" layer that
is not idiomatic Ash and duplicates machinery Ash already provides:

- **12 context modules** wrap `Ash.Changeset.for_* |> Ash.create/update(authorize?: false)`
  in bespoke functions. Two of them — `academics.ex` (~1440 lines) and
  `accounts.ex` — *are the Ash domains themselves*, bloated with orchestration.
- **13 raw `Repo.transaction` sites** hand-roll multi-resource orchestration
  with `with`-chains, bypassing Ash action transactions.
- **19 `Ash.Type.Enum`** modules. **6** have *parallel* label/order modules
  (`SchoolType` enum + `SchoolTypes` labels, ×6); ~13 have no labels at all.
- **11 LiveViews** build forms with hand-rolled `to_form` on plain maps and
  manual param plumbing, not `AshPhoenix.Form`.
- Hand-computed logic (`last_head?`, class averages, rankings, the
  combined-course double-count filter) lives in context functions instead of
  Ash calculations/aggregates.
- Marks fan-out notifications go through a manual `persist_marks_notifications!`
  path instead of an Ash notifier.

None of this is a Phase-2 regression; it is the established house pattern.
This sweep replaces it with idiomatic Ash. `code_interface` **nowhere**,
`AshPhoenix.Form` **nowhere** today.

## Goal & non-goals

**Goal:** make the entire app idiomatic Ash across six axes — `code_interface`,
Ash action transactions + generic actions, `AshPhoenix.Form`, enums-with-labels,
calculations/aggregates, and notifiers/PubSub — **without changing observable
behavior**, delivered as **one spec / one plan / one branch**.

**Non-goals (explicitly out):**
- **Real authorization policies.** Authorization is deferred to roadmap item
  **C**; it needs the role/capability model from item **B**. This sweep only
  *centralizes* the current "no auth" posture so C can flip it in one place.
- Any behavior change. The 632-test suite's assertions are frozen.
- The role model (item **B**).
- Unrelated refactors. `parse_coefficient` dedup rides along **only** where a
  file is already being touched.

## Decisions locked in brainstorming

1. **Depth:** maximal — all six axes, including calculations/aggregates and
   notifiers/PubSub.
2. **Decomposition:** one spec, one branch (not per-domain or per-axis
   increments). Accepted risk: long-lived branch; mitigated by keeping the
   suite green at every commit and sequencing logical commits.
3. **API stability:** *idiomatic call sites*. Public function names/signatures
   may change to the cleanest Ash form; tests and LiveViews are updated to
   match. **Behavior assertions stay identical** — only call syntax modernizes,
   so the suite remains a true before/after regression pin.
4. **Domain topology:** split the god-domain into focused domains.

## 1. Domain topology

`academics.ex` (one domain, 27 resources) splits into focused Ash domains;
`accounts.ex` stays. Cross-domain relationships are fully supported in Ash.

| Domain | Resources |
|---|---|
| **Accounts** (unchanged membership) | User, Token, SchoolProfile, SchoolMembership, SchoolInvitation |
| **Organization** | Workspace, AcademicYear, Term, Sequence |
| **Enrollment** | ClassGroup, Student, Enrollment |
| **Curriculum** | Subject, TeachingContext, CombinedCourse, ProgressionPlan, ProgressionEntry, ProgressionModule, TeachingLogEntry, LessonPlan, LessonStep |
| **Assessment** | Assessment, Mark |
| **Attendance** | Period, AttendanceEntry |
| **Discipline** | SanctionEntry, ConductMark |
| **Timetabling** | TimetableSlot |
| **Fees** | FeeTranche, FeeAdjustment, Payment |

`Period` lives in **Attendance**; **Timetabling** references it cross-domain.
**Option:** Attendance + Timetabling may merge into a single **Scheduling**
domain (Period, AttendanceEntry, TimetableSlot) for 7 domains total if 9 feels
over-cut during planning; the plan may choose the 7-domain shape without a spec
change. Module namespaces follow the domain (`TeacherAssistant.Curriculum.*`,
etc.); the plan handles the file moves.

## 2. Authorization deferral — centralized

Today authorization is skipped by passing `authorize?: false` at ~every call in
12 modules. Replace that with **domain-level** configuration: each domain is set
so authorization is **off unless explicitly requested** (Ash domain
`authorization` config), and the scattered `authorize?: false` flags are
removed. Resources keep a harmless `policy always() do authorize_if always() end`
placeholder.

**Item C** later flips each domain's authorization on and writes real policies
against the role model — a single, central switch per domain instead of a
repo-wide grep. This is the *only* auth work in this sweep.

## 3. `code_interface` — context modules dissolve

The 12 hand-written modules are **deleted**:

```
accounts/schools.ex
academics.ex (as a context; survives only as the (now-slim) Organization/Curriculum split)
academics/assignments.ex  academics/attendance.ex  academics/courses.ex
academics/discipline.ex    academics/enrollments.ex academics/fees.ex
academics/seeding.ex       academics/subjects.ex    academics/timetables.ex
accounts.ex (as a context; survives as the Accounts domain)
```

- Read/list/get/simple-update wrappers → `code_interface` `define`s on the
  owning domain (e.g. `Enrollment.list_members`, `Curriculum.get_course`).
- Multi-step orchestration → resource actions (§4).
- Call sites (LiveViews, controllers, tests, other domains) move to the new
  idiomatic names.

The domain modules end as: resource list + `code_interface` block + domain
config. No business logic in them.

## 4. Actions & transactions — the 13 `Repo.transaction` sites

Each hand-rolled `Repo.transaction` + `with` becomes an Ash action with
`transaction? true`, so Ash owns the transaction and rollback:

| Current (`Repo.transaction`) | Becomes |
|---|---|
| `Schools.create_school/2` | `Workspace :create` with `after_action` → SchoolProfile + `:head` SchoolMembership + seeded Subject catalog (via `manage_relationship`/after_action) |
| `Courses.combine/1`, `Courses.split/1` | generic actions on `CombinedCourse` |
| `Attendance.record_combined_period/5` | generic action (union roll → per-class routing) |
| `Timetables.place_combined_slot/3`, `clear_combined_slot/3` | generic actions on `TimetableSlot` |
| marks all-or-nothing save (`academics.ex`) | bulk/generic action on `Mark` |
| `Enrollments` import | generic action / `bulk_create` |
| `verify`/`reject`/`accept_invitation` | `update` actions + change modules |

Validations already added (e.g. `ProgressionPlan.ExactlyOneOwner`) stay. No raw
`Repo` calls remain in the domain layer.

## 5. Enums + labels

- **Collapse the 6 parallel label modules** into their `Ash.Type.Enum`:
  `SchoolTypes`→`SchoolType`, `SchoolSubsystems`→`SchoolSubsystem`,
  `SchoolSectors`→`SchoolSector`, `SchoolRoles`→`SchoolRole`,
  `CameroonRegions`→`CameroonRegion`,
  `SchoolVerificationStatuses`→`SchoolVerificationStatus`. Declaration order in
  `values:` provides display order (replacing `@order`/`all/0`); `label/1` (and
  `description/1` where used) defined **on the type** via gettext. Delete the
  parallel modules; update call sites to `SchoolType.label/1` etc.
- **Add `label/1`** (gettext) to the UI-surfaced label-less enums:
  SubjectCategory, AttendanceStatus, PaymentMethod, DayOfWeek, PeriodKind,
  SanctionType, EnrollmentStatus, Sex, Subsystem. Purely-internal enums
  (WorkspaceKind, MembershipStatus, InvitationStatus, UserRole where not shown)
  stay bare.
- Bilingual (FR/EN) coverage: any new gettext strings extracted; FR default
  preserved.

## 6. Calculations & aggregates

Hand-computed logic moves onto resources as Ash calculations/aggregates,
producing identical numbers:

- `last_head?` / "can't remove the last head" → an aggregate/count of active
  head memberships feeding an Ash **validation** on the deactivate/role-change
  actions.
- Class averages & rankings → calculations/aggregates on Enrollment/ClassGroup
  over Mark.
- Combined-course **double-count filter** (unit plans only) → a read
  action/calculation on ProgressionPlan.
- Active-member / duplicate-email checks → aggregates instead of
  `read! |> Enum.filter`.

## 7. Notifiers / PubSub

`Assessment` and `Mark` gain an `Ash.Notifier.PubSub` notifier replacing the
manual `persist_marks_notifications!` path. It publishes on create/update to the
topics the LiveViews already consume; subscribers unchanged in intent.
Observable screen-update behavior is preserved.

## 8. `AshPhoenix.Form`

All 11 `to_form` LiveViews convert:

- **Form dialogs** — create school (`create_school_live`), create/edit class
  (`classes_live`), invite member (`members_live`), settings profile
  (`settings_live`), periods (`periods_live`), fiche/lesson-plan
  (`fiche_live`, `lesson_plan_live`), setup (`setup_live`), roster
  (`roster_live`), log (`log_live`) — bind to `AshPhoenix.Form` over the
  resource action. Validation errors come from Ash.
- **Bulk grids** — the marks union grid (`marks_live`) and attendance roll
  (`attendance_live`) are row-editors, and their SAVE already routes through the
  idiomatic transactional bulk/generic actions from §4
  (`Assessment.upsert_marks` → `Mark :upsert_all`;
  `Attendance.record_combined_period`), preserving all-or-nothing + per-class
  routing.
  **AMENDED 2026-09-19 (F2 ruling):** these grids are **NOT** wrapped in
  `AshPhoenix.Form`. Forcing it would be a bad abstraction the sweep forbids:
  (i) marks range validation + the French-decimal parser live in the
  `Assessment` domain wrapper, *outside* `:upsert_all` — a form bound to the
  bare action would bypass them or force relocating validation into the action
  (a C7-scope change); (ii) the attendance roll is a `phx-click` editor with no
  `<form>` to bind. So the grids keep their bulk-param submit (through the
  idiomatic transactional action), and only the **auxiliary** single-record
  forms inside those LiveViews convert (e.g. `marks_live`'s solo
  `new_assessment_form` → `AshPhoenix.Form.for_create(Assessment, :create)`).
  Optional future follow-up: move mark range validation into the `:upsert_all`
  action, after which the marks grid could bind to it non-lossily.

## 9. Testing, migrations, sequencing, risks

**Testing.** Full suite (`mix test`, 632 tests) green at **every commit**.
Behavior assertions are frozen; when a test's invocation changes to the
idiomatic call, its assertions do not. New calculations/aggregates/notifiers get
focused tests. TDD applies to genuinely new resource code (actions, changes,
calculations).

**Migrations.** None expected. Enum stored values are unchanged (no data
migration). New domains, actions, calculations, aggregates, and notifiers do not
alter columns. Resource **snapshots** are regenerated with `mix ash.codegen` and
committed whenever a resource changes; if `ash.codegen` emits an unexpected
migration, stop and reconcile before continuing.

**Sequencing (single branch, logical commits).** Suggested order, each a
green-suite checkpoint:
1. Enums (independent, mechanical) — collapse + label.
2. Domain scaffolding — create the focused domains, move resources, set
   authorization config; keep old context modules delegating temporarily.
3. Per domain: resource actions + `code_interface`, delete that context module,
   update its call sites.
4. Calculations/aggregates + the `last_head`/average/ranking/double-count moves.
5. Notifiers for Assessment/Mark.
6. `AshPhoenix.Form` conversions (dialogs, then the two bulk grids).
7. Final sweep: no raw `Repo` in domains, no `authorize?: false`, no parallel
   label modules; snapshots committed.

**Risks.**
- *Long-lived branch* vs. other work — mitigated by green-at-each-commit and
  landing promptly; no other active branch is expected during the sweep.
- *Bulk grids* (§8) are the only non-mechanical conversion — highest-attention
  area in review.
- *AshAuthentication* lives in Accounts; its generated actions/routes must be
  left intact when Accounts is tidied.

## Acceptance criteria

- No `Repo.transaction` (or other raw `Repo.*`) calls in `lib/teacher_assistant`
  domain code.
- No `authorize?: false` call-site flags; authorization is configured at the
  domain level (off until item C).
- No parallel enum label/order modules; every UI-surfaced enum exposes `label/1`.
- `code_interface` defines the domain APIs; the 12 hand-written context modules
  are gone (their names live on as domain/resource APIs).
- The dialog LiveViews use `AshPhoenix.Form`. **AMENDED 2026-09-19 (F2
  ruling):** the two bulk grids (`marks_live` scores grid, `attendance_live`
  roll) are NOT wrapped in `AshPhoenix.Form` — they submit through the idiomatic
  transactional bulk/generic actions instead, because forcing a form would be a
  bad abstraction (see §8). Auxiliary single-record forms inside those LiveViews
  do convert.
- **AMENDED 2026-09-19 (D2 ruling):** class averages/rankings are realized as
  domain functions over the pure `Marks`/`Bulletins` modules (numbers must stay
  byte-identical; SQL aggregates would change `Decimal` rounding), not SQL
  calculations/aggregates — the location moved off the god-domain, the
  computation form did not. `last_head` (aggregate) and the double-count filter
  (read action) ARE Ash calc/aggregate/read-action as specified; marks
  notifications go through an `Ash.Notifier.PubSub` notifier.
- `mix test` = 632 passing at start (now higher, with added focused tests), 0 failures.
- No unexpected DB migration; snapshots committed.
- The god-domain `academics.ex` no longer exists as a 1440-line module.
