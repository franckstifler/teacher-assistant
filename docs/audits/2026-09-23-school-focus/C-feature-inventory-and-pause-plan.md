# TeacherAssistant — functional feature inventory & pause classification

Read-only inventory of `/Users/franckstfiler/Documents/projects/teacher-assistant` at commit `1fc5547` (main, clean). All paths are relative to the repo root unless absolute. 674 tests across 124 test files (`grep -c 'test "'`).

## 0. Orientation (what the docs say vs what the code does)

- `docs/PRODUCT.md` still says "Teacher-first, then school" and lists Phase 1 (independent teacher v1–v1.3) as shipped, Phase 2 (school layer) as the add-on. It has NOT been updated for the reposition.
- `docs/superpowers/specs/2026-09-16-school-identity-onboarding-design.md` §Context states the actual current direction: "The product is repositioning around the school workspace as the primary product (previously teacher-first)", with a 5-increment roadmap: (1) identity/onboarding — merged; (2) staff & roles — merged (`ef38e1b`); (3) authorization hardening — spec + plan only (`b58cda3`, `d29bf81`); (4) settings & configuration (grading scale, term structure, year CRUD) — not started; (5) dashboard & navigation — not started.
- `2026-09-22-onboarding-setup-wizard-design.md` — merged (`eaf6892`): blocking wizard.
- `2026-09-17-school-subjects-teaching-model-design.md` — subjects catalog + seeding + combined courses merged.
- `2026-09-18-idiomatic-ash-structural-sweep-design.md` — partially applied (12 context modules collapsed into 8 domain modules: `Organization`, `Curriculum`, `Enrollment`, `Assessment`, `Attendance`, `Discipline`, `Fees`, `Timetabling`, `Accounts`), but every resource still has `policy always() do authorize_if always() end` (e.g. `lib/teacher_assistant/academics/workspace.ex:77-81`, `teaching_context.ex:151-155`).

Two vocabularies coexist and matter for the pause plan:
- **Workspace kind** (`lib/teacher_assistant/accounts/workspace_kind.ex:2`): `:personal | :school`.
- **Scope type** (`lib/teacher_assistant/scope.ex:9`, set in `accounts/workspaces.ex:31,58`): `:personal_teacher | :school`. `Scope.personal_context?/1` (`scope.ex:19`) exists but is never called from `lib/` (grep).

---

## 1. USER JOURNEYS AS THEY EXIST TODAY

### J1. Registration / sign-in (SHARED)
1. `GET /` landing (`PageController.home`, `page_html/home.html.heex`). CTAs: `/schools/start` (x5), `/register`, `/sign-in`.
2. `/register`, `/sign-in`, `/reset` — AshAuthentication.Phoenix `sign_in_route`/`reset_route`/`magic_sign_in_route` with branded overrides (`router.ex:54-78`, `auth_overrides.ex`). Password + magic link strategies (`accounts/user.ex:55-84`).
3. On success `AuthController.success/4` (`controllers/auth_controller.ex:6`) redirects to `session[:return_to] || "/teacher"`.
4. **Dead-end/gate**: `live_no_user` (`live_user_auth.ex:74-82`) bounces an already signed-in user to `/teacher`. `LocaleController.set` (`locale_controller.ex:10`) always redirects to `/teacher`. Every error fallback in `WorkspaceController` (`:23,:36`) and `SchoolInvitationController` (`:34,:51`) goes to `/teacher`. → **The teacher workspace is the app's implicit home; there is no "no workspace" state.**

### J2. Workspace resolution & selection (SHARED)
1. Every authenticated LiveView mounts through `LiveUserAuth.assign_scope/2` (`live_user_auth.ex:88-103`) → `Workspaces.scope_for(user, session["workspace_id"], session["context_id"])`.
2. `scope_for(user, nil, _)` (`accounts/workspaces.ex:10-13`) **auto-creates the personal workspace** (`Organization.ensure_personal_workspace!/1`, `organization.ex:81-95`, `Workspace.unique_owner_user` identity). So every user always has a `:personal` workspace and defaults to it when the session has no `workspace_id`.
3. `Organization.list_workspaces_for/1` (`organization.ex:63-73`) = `[personal | active school memberships]` — this feeds the header workspace dropdown in `Layouts.app` (`components/layouts.ex:50-53`, links at `:141` `GET /workspaces/select/:id`, plus a "create school" button `:152` → `/schools/new`).
4. `WorkspaceController.select/2` (`workspace_controller.ex:7-25`) stores `workspace_id` in session and redirects to `/school` (school kind) or `/teacher` (personal). `POST /workspaces` (`:27-38`) is a legacy name-only school create that still exists in the router (`router.ex:38`) but no template posts to it anymore (the header now links to `/schools/new`).
5. School scope requires an active `SchoolMembership` (`workspaces.ex:43-69`); non-members get `{:error, :not_a_member}` → scope falls back to `%Scope{current_user: user}` with no workspace (`live_user_auth.ex:119`).

### J3. School creation (SCHOOL-CORE)
1. `GET /schools/start` (`page_controller.ex:17-25`): signed-in → `/schools/new`; visitor → `session[:return_to]="/schools/new"` then `/register`.
2. `/schools/new` `Onboarding.CreateSchoolLive` (`live_session :onboarding`, `router.ex:130-133`). Fields: name, school_type, subsystem, sector, region, town (`create_school_live.ex`, `field=` grep). Submits `Organization.create_school/2` (`organization.ex:47-57`) → `Workspace.:create_school` transactional create (`academics/workspace.ex:50-74`): workspace `kind: :school` + `SchoolProfile` + creator `:head` membership + seeded `Subject` catalog by type/subsystem (`SchoolTemplates.subjects_for/2`).
3. On success → `redirect /workspaces/select/#{school.id}` (`create_school_live.ex:23`) → session switch → `/school`.

### J4. Blocking setup wizard (SCHOOL-CORE)
1. `on_mount :require_school_setup` (`live_user_auth.ex:56-72`) on every `:school_workspace` route: school scope AND `!Scope.setup_complete?` (`scope.ex:32-37` = active year AND ≥1 class) → `push_navigate /school/setup` (wizard itself exempt).
2. `/school/setup` `Onboarding.SetupWizardLive` steps `[:identity, :year, :classes, :invite]` (`setup_wizard_live.ex:18`), initial step derived from data (`:42-48`).
   - `create_year`: `AshPhoenix.Form.submit` on `AcademicYear.:create_for_workspace` then `Seeding.seed_starter_classes/2` (`:246-253`). **Does NOT build terms/séquences** (no call to `Organization.build_default_calendar/1`; the only caller in `lib/` is the personal `Teacher.SetupLive` `setup_live.ex:44`). See Gap G1.
   - `add_class` / `delete_class` (admin-gated `:282,:305`), `continue_classes`, `invite` (head-gated `:343`, `Accounts.invite_member/3`), `finish` → `/school` (`:368`).
3. Gate is per-school; a plain teacher member of an unconfigured school is also sent to the wizard (test "a plain teacher member without an active year is also redirected to the setup wizard", `test/teacher_assistant_web/live/school/dashboard_live_test.exs`) — but cannot act there (admin gates) → **dead end for non-admin members of an unconfigured school**.

### J5. Invitations & joining (SCHOOL-CORE)
1. Head invites from wizard step 4 or `/school/members` (`members_live.ex`, events `invite`, `revoke_invite`, `set_roles`, `set_status`, `deactivate_member`; head-only `:172-268`). Roles multi-select `invite[roles][]` (`:114`), employment type (`MembershipStatus`).
2. Email is really delivered: `Senders.SendSchoolInvitationEmail` → `Mailer.deliver` (`accounts/user/senders/send_school_invitation_email.ex`), Swoosh Local adapter in dev (`/dev/mailbox`, `router.ex:151`).
3. `GET /schools/invitations/:token` (`school_invitation_controller.ex:6-36`): signed-out → stores `return_to` and renders a page offering register/sign-in; email mismatch → shown; `POST .../accept` (`:38-53`) → `Accounts.accept_invitation/2` → session `workspace_id` → `/school`.

### J6. Daily use — school admin (head / vice_principal) (SCHOOL-CORE)
`/school` dashboard (checklist, KPIs, "Mes classes" for form masters, unverified banner) → `/school/classes` (create/delete classes, `classes_live.ex`) → `/school/classes/:id` (`class_live.ex`: enroll new/existing, transfer, withdraw, assign/reassign/unassign teacher per subject, coefficient, form master, teach_together/split combined courses; links to results, import, timetable, register, discipline, fees `:57-100`) → `/school/settings` (profile, logo, years create/activate, subject catalog; link to `/school/periods` `:328`) → `/school/periods` (bell schedule, seed default) → `/school/classes/:id/timetable` (place slots) → `/school/members`.

### J7. Daily use — school teacher (SCHOOL-CORE but implemented in `/teacher/*`)
1. Teacher selects the school in the header → `/school` (`workspace_controller.ex:12`). Nav rail in school mode (`layouts.ex:234-282`): Dashboard, Classes, Mon emploi du temps, Members, Settings (admin only). **No "Marks" entry in the school nav.**
2. Marks/roster/results are reached only through the **class-context switcher** (`layouts.ex:159-195`, units from `Curriculum.list_units_for_scope/1` `curriculum.ex:372-383` = the user's own assignments in school scope) and the **per-class nav** (`layouts.ex:284-315`) which links to `/teacher/contexts/:id/roster|marks|marks/summary`. Those routes live in `live_session :teacher_workspace` with `on_mount :require_teaching_scope` (`live_user_auth.ex:46-54`): school scope with no assignment → bounce to `/school`.
3. `Teacher.MarksLive` resolves the context with `Curriculum.fetch_assigned_teaching_context/2` (`curriculum.ex:618-639`: school → `:assigned_in_school` read filtered by `teacher_user_id`; personal → workspace-owned). Combined-course mode (`marks_live.ex:63+`). Save is blocked unless `Permissions.operating_allowed?` (`marks_live.ex:174`) = school profile `:verified` (`permissions.ex:59-61`).
4. Roster is read-only in school scope (`roster_live.ex:12`, test "roster is read-only under school scope").
5. Attendance: `/school/timetable/me` (`my_timetable_live.ex:77`) links each of the teacher's own slots to `/school/classes/:id/attendance/:period_id?date=` (`attendance_live.ex:16-46`): requires a `Period`, a placed `TimetableSlot` for that class/day/period (`Attendance.slot_for/3` `attendance.ex:108-119`, `{:error,:no_slot}` → `slot=nil` → `owns_slot?` false → "Access denied" unless conduct manager), and `operating_allowed?` to record (`:159`).
6. Cross-links back into personal-style tools: `Teacher.DashboardLive` at `/teacher` shows coverage KPIs and links to plans/fiche/coverage/import (`dashboard_live.ex:95-227`).

### J8. Daily use — independent teacher (TEACHER-PERSONAL)
`/teacher` (setup gate if no year → `/teacher/setup` `setup_live.ex`: creates year + default calendar + first `TeachingContext` with free-text subject/level) → `/teacher/plans/:id` fiche builder (modules DnD, quotas, completion) → `/teacher/plans/:id/coverage` → `/teacher/log` cahier de textes → `/teacher/import` PDF fiche import → `/teacher/entries/:entry_id/fiche` lesson plan (+ `/fiche/print`) → `/teacher/contexts/:id/roster` (create class + students) → `/marks` → `/marks/summary`.

### J9. Platform operator (SHARED infra)
`/admin/schools` (`live_session :operator`, `require_operator` = `user.role == :admin` `live_user_auth.ex:38-44`): list unverified `SchoolProfile`s, `verify` / `reject`. This is what flips `operating_allowed?` on (J7.3). No UI promotes a user to `:admin` (`User.:promote_to_admin` action exists `user.ex:116`; `priv/repo/seeds.exs` dev-only).

### "Teacher context" means
`Scope.current_context` = a `TeachingContext` (subject × level/serie × year, optionally × class_group × teacher). Persisted as `session[:context_id]` via `GET /teacher/select-context/:id` (`teacher_context_controller.ex`, only `/teacher*` return_to paths allowed `:22`). Personal scope: any context of the workspace (`Curriculum.resolve_current_context/3` `curriculum.ex:700-703`); school scope: only contexts where `teacher_user_id == user` (`workspaces.ex:74-77`).

---

## 2. FEATURE INVENTORY TABLE

Classification key: **CORE** = SCHOOL-CORE keep · **LATER** = SCHOOL-LATER (defer, keep code) · **PAUSE** = TEACHER-PERSONAL · **SHARED** = infra used by both.

| # | Feature | Class | Routes | LiveView / controller | Ash resources | Tests (file → count) | Maturity | Notes |
|---|---|---|---|---|---|---|---|---|
| A1 | Auth: register / sign-in / magic link / reset | SHARED | `/register`, `/sign-in`, `/reset`, `/auth/*`, `/sign-out` | AshAuthentication.Phoenix + `AuthController`, `AuthOverrides` | `User`, `Token` | `live/auth_smoke_test` 4; `accounts/senders_test` 2; `accounts/emails_test` 2 | working | Post-auth default `/teacher` (`auth_controller.ex:6`). |
| A2 | Locale FR/EN switch | SHARED | `/locale/:locale` | `LocaleController` | — | `locale_test` 1 | working | Redirects to `/teacher` (`locale_controller.ex:10`). |
| A3 | Landing page | SHARED | `/`, `/schools/start` | `PageController` | — | `page_controller_test` 3 | working | Landing sells "create a school" (5× `/schools/start`). |
| A4 | Workspace model & switcher | SHARED | `/workspaces/select/:id`, `POST /workspaces` | `WorkspaceController`, `Layouts.app` | `Workspace` (kind), `SchoolMembership` | `accounts/workspaces_test` 8; `workspace_test` 2; `components/workspace_switcher_test` 1; `permissions_test` 11 | working | Personal ws auto-created for everyone (`organization.ex:81`). `POST /workspaces` is orphaned (no form posts to it). |
| A5 | Scope + on_mount gates | SHARED | — | `LiveUserAuth`, `Scope` | — | `school_teaching_scope_test` 3; `setup_gate_test` 4 | working | Four gates: `live_user_required`, `require_teaching_scope`, `require_school_setup`, `require_operator`. |
| A6 | Component kit / theme | SHARED | — | `core_components.ex`, `layouts.ex`, `money.ex` | — | `kit_test` 5; `money_test` 5; `shell_test` 3; `navigation_test` 1 | working | `navigation_test` asserts personal nav links (dashboard, log). |
| S1 | School: create school (identity) | CORE | `/schools/new`, `/schools/start` | `Onboarding.CreateSchoolLive` | `Workspace.:create_school`, `SchoolProfile`, `SchoolMembership`, `Subject` (seed) | `create_school_live_test` 1; `schools_create_test` 6; `schools_test` 5; `school_profile_test` 4; `school_resources_test` 4; `school_enums_test` 2; `schools_catalog_seed_test` 2; `school_templates_test` 6 | working | Transactional create with catalog seeding. |
| S2 | School: setup wizard (blocking) | CORE | `/school/setup` | `Onboarding.SetupWizardLive` | `AcademicYear`, `ClassGroup` (via `Seeding`), `SchoolInvitation` | `setup_wizard_live_test` 12; `seeding_test` 2 | working / **partial** | Year created without terms/séquences (Gap G1). Identity step is read-only recap. |
| S3 | School: dashboard | CORE | `/school` | `School.DashboardLive` | `ClassGroup`, `Enrollment`, `TeachingContext`, `SchoolMembership`, `SchoolProfile` | `dashboard_live_test` 9 | working / stub-ish | Checklist + 3 KPIs + form-master "Mes classes". No teacher-facing "my classes → marks/attendance" section (Gap G4). |
| S4 | School: members & roles & employment type | CORE | `/school/members` | `School.MembersLive` | `SchoolMembership`, `SchoolRole`, `MembershipStatus` | `members_live_test` 5 | working | Head-only mutations; every member can view. `:hod`, `:guidance_counsellor`, `:librarian` roles have no behaviour anywhere (`grep ":hod" lib` → only enum). |
| S5 | School: invitations by email + accept-with-signup | CORE | `/schools/invitations/:token`, `POST …/accept` | `SchoolInvitationController` (+ wizard/members invite) | `SchoolInvitation`, `Emails`, `Mailer`, `Senders.SendSchoolInvitationEmail` | `school_invitations_test` 9; `school_invitation_controller_test` 6 | working | Real Swoosh delivery; Local adapter in dev/test; prod adapter not configured (`config/runtime.exs:109-123` comments). |
| S6 | School: settings — profile, logo, rename | CORE | `/school/settings`, `/school/logo` | `School.SettingsLive`, `SchoolLogoController` | `SchoolProfile`, `Workspace` | `settings_live_test` 10; `settings_logo_test` 2; `settings_profile_test` 2 | working | Upload dir `priv/uploads` (`config.exs:75`). |
| S7 | School: academic years (create/activate) | CORE | `/school/settings` | `School.SettingsLive` (`create_year`, `activate_year`) | `AcademicYear` | in `settings_live_test`; `academic_year_test` 2 | **partial** | No edit/delete; no terms/séquences UI; creating a year re-seeds starter classes (`settings_live.ex:379`). |
| S8 | School: terms & séquences (calendar) | CORE | — (no route) | — | `Term`, `Sequence`, `Reference.default_calendar_preset/0`, `Organization.build_default_calendar/1` | `calendar_test` 2; `reference_test` 5 | **missing UI / not wired for schools** | Only personal `Teacher.SetupLive` calls `build_default_calendar` (`setup_live.ex:44`). Tests for school marks/results/bulletins call it manually (20 test files, see §5 G1). |
| S9 | School: subject catalog (seeding + CRUD + coefficient + active flag) | CORE | `/school/settings` | `School.SettingsLive` (`create_subject`, `update_subject`, `toggle_subject_active`, `delete_subject`) | `Subject`, `SubjectCategory`, `SchoolTemplates` | in `settings_live_test`; `subjects_test` 4; `subject_test` 2 | working | Coefficient is per subject (school-wide default) and copied onto each assignment (`TeachingContext.coefficient`), editable per class (`class_live` `set_coefficient`). No per-série coefficient table. |
| S10 | School: classes CRUD (+ starter seeding by type/subsystem) | CORE | `/school/classes` | `School.ClassesLive` | `ClassGroup`, `SchoolTemplates.levels_for/streams_for/classes_for`, `Seeding` | `classes_live_test` 7; `class_group_test` 3 | working | Fields: label, level, serie (stream kind label "Série/Spécialité/Stream"), subsystem. Spécialité is stored in the same `serie` column (no dedicated attribute — `grep -i speciali lib` only hits `school_templates.ex`). |
| S11 | School: teacher assignments (subject × class → teacher), coefficient, reassign, unassign | CORE | `/school/classes/:id` | `School.ClassLive` (`assign`, `reassign`, `unassign`, `set_coefficient`) | `TeachingContext` (school mode: `teacher_user_id` + `class_group_id` set; partial unique index `teaching_contexts_unique_school_assignment` `teaching_context.ex:20-24`) | `class_live_test` 29 (shared); `assignments_test` 12; `teaching_context_test` 6 | working | This is THE link between school config and teacher marks/attendance. |
| S12 | School: combined courses (teach several classes together) | CORE (keep; optional) | `/school/classes/:id` (`teach_together`, `split_course`) | `School.ClassLive` | `CombinedCourse` (`:combine`, `:split`), `TeachingContext.combined_course_id`, `ProgressionPlan.combined_course_id` | `courses_test` 7; `combined_course_test` 1; `teaching_context_combined_test` 2; `context_switcher_combined_test` 2; `marks_combined_test` 4; `attendance_combined_test` (domain) 4 + (live) 2; `timetables_combined_test` 4 | working | **Entangled with progression plans**: `CombinedCourse.:combine` creates a shared `ProgressionPlan` (`combined_course.ex:49-51,162-171`) and `:split` destroys it. |
| S13 | School: form master (professeur principal) | CORE | `/school/classes/:id` (`set_form_master`), dashboard "Mes classes" | `School.ClassLive`, `School.DashboardLive` | `ClassGroup.form_master_user_id` | `class_group_form_master_test` 3; `form_master_context_test` 3; class_live tests | working | Access is FK-based, not the `:form_master` role. |
| S14 | School: enrollment (inscription/réinscription/transfer/withdraw, search) | CORE | `/school/classes/:id` | `School.ClassLive` | `Student`, `Enrollment` (`:enroll_new`), `EnrollmentStatus`, `Sex` | `enrollments_test` 9; `enrollments_model_test` 7; `student_test` 5; class_live tests | working | Matricule unique per workspace (`student.ex:12-13`). |
| S15 | School: enrollment CSV/paste import | CORE | `/school/classes/:id/import` | `School.EnrollImportLive` | `Enrollment.preview_rows/import_rows` | `enroll_import_live_test` 5 | working | Admin-only. |
| S16 | School: periods (bell schedule) | CORE | `/school/periods` | `School.PeriodsLive` (`seed`, `update_period`, `delete_period`) | `Period`, `PeriodKind` | `periods_live_test` 5; `timetables_periods_test` 3 | working | Admin-only. Prerequisite for attendance. Reachable only via link in settings (`settings_live.ex:328`); not in nav. |
| S17 | School: class timetable + teacher timetable + print | CORE (prerequisite for attendance) | `/school/classes/:id/timetable`, `/school/timetable/me`, `…/timetable/print`, `/school/timetable/me/print` | `School.TimetableLive`, `School.MyTimetableLive`, `TimetablePrintController` | `TimetableSlot`, `DayOfWeek` | `timetable_live_test` 8; `my_timetable_live_test` 3; `timetable_print_controller_test` 3; `timetables_slots_test` 6; `timetables_reads_test` 3; `timetables_combined_test` 4 | working | Attendance is keyed on slots (Gap G2). |
| S18 | School: attendance / roll call (cahier d'appel) | CORE | `/school/classes/:id/attendance/:period_id?date=` | `School.AttendanceLive` | `AttendanceEntry` (`:record`, `:period_roll`, `:combined_period_roll`, `:record_combined_period`), `AttendanceStatus` | `attendance_live_test` 7; `attendance_combined_test` (live) 2; `attendance_test` 21; `attendance_entry_test` 6; `operate_gate_test` 2 | working | Slot owner or conduct manager; blocked until school verified. |
| S19 | School: daily class register + justification (SG) | CORE | `/school/classes/:id/register` | `School.RegisterLive` (`pick_date`, `justify`, `unjustify`) | `AttendanceEntry`, `Attendance.class_register/justify_day` | `register_live_test` 6 | working | conduct_manager or admin/form-master. |
| S20 | School: sanctions & note de conduite | CORE-adjacent (keep; low risk) | `/school/classes/:id/discipline` | `School.DisciplineLive` | `SanctionEntry`, `SanctionType`, `ConductMark`, `Conduct` | `discipline_live_test` 7; `discipline_test` 27; `sanction_entry_test` 4; `conduct_test` 7; `conduct_mark_test` 4 | working | Needs séquences for note de conduite. |
| S21 | School: marks entry in school context (teacher's assigned subject × class) | CORE | `/teacher/contexts/:id/marks`, `/teacher/contexts/:id/marks/summary`, `/teacher/contexts/:id/roster`, `/teacher/select-context/:id` | **`Teacher.MarksLive`, `Teacher.MarksSummaryLive`, `Teacher.RosterLive`, `TeacherContextController`** | `Assessment`, `Mark` (`:upsert_all`), `Marks` (stats/mentions), `Sequence` | `marks_live_test` 14; `marks_combined_test` 4; `marks_isolation_test` 3; `marks_summary_live_test` 7; `roster_live_test` 5; `school_scope_ux_test` 4; `teacher_context_controller_test` 4; `mark_test` 10; `marks_test` 11; `assessment_test` 4; `resolve_context_test` 3 | working (given séquences exist) | **Lives in the `/teacher/*` live_session — must NOT be paused.** Teacher-scoped in school mode (`curriculum.ex:618-634`). Blocked until verified. |
| S22 | School: results (class table per period), bulletins, print | CORE (verification tools) | `/school/classes/:id/results`, `…/students/:enrollment_id/bulletin`, `…/bulletin/print`, `…/students/:eid/bulletin/print` | `School.ResultsLive`, `School.BulletinLive`, `BulletinPrintController` | `Bulletins`, `Assessment.class_results_for_period`, `Term`, `Sequence` | `results_live_test` 6; `bulletin_live_test` 5; `bulletin_print_controller_test` 10; `bulletins_test` 7; `bulletin_data_test` 3; `period_results_test` 5 | working | Admin or form-master. Mention thresholds hard-coded (`academics/marks.ex:15-16`). |
| S23 | School: fees (tranches, payments, adjustments, balances) | LATER | `/school/classes/:id/fees` | `School.FeesLive` | `FeeTranche`, `Payment`, `PaymentMethod`, `FeeAdjustment`, `FeeBalance` | `fees_live_test` 13; `fees_test` 30; `fee_adjustment_test` 3; `fee_balance_test` 7; `fee_tranche_test` 4; `payment_test` 4 | working | Bursar/admin edit, form-master read. Self-contained; only inbound link is `class_live.ex:100` (`fees_link?`). No gating anywhere else. |
| S24 | School: verification / operate gate | SHARED (platform) | `/admin/schools` | `Admin.SchoolsLive` | `SchoolProfile.:verify/:reject`, `SchoolVerificationStatus` | `admin/schools_live_test` 2; `workspaces_verification_test` 2; `operate_gate_test` 2 | working | Requires `user.role == :admin`; no UI to grant it. Blocks marks/attendance/bulletin print for unverified schools. |
| T1 | Teacher: personal workspace (auto-created) + workspace switch to it | PAUSE (entry) / SHARED (model) | `/workspaces/select/:id` (personal id) | `WorkspaceController`, `Organization.ensure_personal_workspace!` | `Workspace kind :personal` | `workspaces_test` (3 of 8) | working | The **default scope** for any session without `workspace_id`. |
| T2 | Teacher: year setup gate (personal) | PAUSE | `/teacher/setup` | `Teacher.SetupLive` | `AcademicYear`, `Term`, `Sequence`, `TeachingContext` (free-text subject/level, targets) | `setup_live_test` 4 | working | Only place that builds the default calendar. |
| T3 | Teacher: dashboard (coverage KPIs) | PAUSE (but is the `/teacher` landing) | `/teacher` | `Teacher.DashboardLive` | `ProgressionPlan.:unit_plans`, `Coverage` | `dashboard_live_test` 5 | working | In school scope lists **all** workspace plans (`dashboard_live.ex:13`), not just the teacher's (§3). |
| T4 | Teacher: progression plan builder (modules DnD, quotas, completion, duplicate, templates) | PAUSE | `/teacher/plans/:id` | `Teacher.FicheLive` (11 handle_event clauses) + `assets/js/hooks/module_layout.js` | `ProgressionPlan` (`ExactlyOneOwner`), `ProgressionModule`, `ProgressionEntry`, `Quota`, `ModuleGrouping`, `Reference` | `fiche_live_test` 13; `progression_plan_test` 4; `progression_plan_unit_test` 6; `progression_entry_test` 2; `progression_module_test` 10; `module_grouping_test` 1; `apply_layout_test` 5; `quota_test` 2 | working | Workspace-scoped lookups (`fetch_owned_plan(id, ws)` `fiche_live.ex:14`). |
| T5 | Teacher: fiche PDF import | PAUSE | `/teacher/import` | `Teacher.ImportLive` | `FicheExtractor` (pdftotext), `FicheParser`, `ProgressionPlan.:import` | `import_live_test` 7; `fiche_extractor_test` 2; `fiche_parser_test` 9; `import_progression_plan_test` 4 | working | Nav link `nav-import` only in personal nav (`layouts.ex:225`) but dashboard button also in school scope (`dashboard_live.ex:100`). |
| T6 | Teacher: lesson plan (fiche de préparation) + print | PAUSE | `/teacher/entries/:entry_id/fiche`, `/teacher/entries/:entry_id/fiche/print` | `Teacher.LessonPlanLive`, `FichePrintController` | `LessonPlan`, `LessonStep` | `lesson_plan_live_test` 7; `lesson_plan_test` 6; `lesson_plan_resource_test` 3; `lesson_step_test` 4; `fiche_print_controller_test` 2 | working | Print shows school name as établissement under school scope (`fiche_print_controller.ex:32`). |
| T7 | Teacher: teaching log (cahier de textes) | PAUSE | `/teacher/log` | `Teacher.LogLive` | `TeachingLogEntry` | `log_live_test` 5; `teaching_log_entry_test` 1 | working | Workspace-wide plan list (`log_live.ex:8`). |
| T8 | Teacher: coverage view | PAUSE | `/teacher/plans/:id/coverage` | `Teacher.CoverageLive` | `Coverage` | `coverage_live_test` 4; `coverage_test` 4 | working | |
| T9 | Teacher: personal roster (create class, add/delete student, undo) | PAUSE (write path) / CORE (read path) | `/teacher/contexts/:id/roster` | `Teacher.RosterLive` | `ClassGroup`, `Student`, `Enrollment` via `Enrollment.add_student` | `roster_live_test` 5 | working | Same LiveView serves the school read-only roster (`read_only?` `roster_live.ex:12`). |
| T10 | Teacher: personal mark register | PAUSE (personal mode) / CORE (school mode) | same as S21 | same as S21 | same as S21 | same as S21 | working | Same code; mode decided by `Scope.current_workspace_type`. |

---

## 3. SHARED-RESOURCE ANALYSIS

Domain modules: `Organization` (Workspace, AcademicYear, Term, Sequence), `Curriculum` (Subject, TeachingContext, CombinedCourse, ProgressionPlan/Module/Entry, LessonPlan/Step, TeachingLogEntry), `Enrollment` (ClassGroup, Student, Enrollment), `Assessment` (Assessment, Mark), `Attendance` (Period, AttendanceEntry), `Discipline` (SanctionEntry, ConductMark), `Fees` (FeeTranche, Payment, FeeAdjustment), `Timetabling` (TimetableSlot), `Accounts` (User, Token, SchoolProfile, SchoolMembership, SchoolInvitation).

| Resource | Used by school | Used by teacher-personal | Both-mode carrier? | Evidence / entanglement |
|---|---|---|---|---|
| `Workspace` | yes | yes | **YES — polymorphic** `kind :personal|:school` (`workspace.ex:87-90`) | Personal created implicitly for every user (`organization.ex:81-95`, `workspaces.ex:10-13`). Every academic row FKs `workspace_id`. |
| `AcademicYear`, `Term`, `Sequence` | yes | yes | YES (per workspace) | Calendar only built in personal setup (`setup_live.ex:44`). Schools get a year with no terms/séquences (Gap G1). |
| `TeachingContext` | yes (assignment: `teacher_user_id` + `class_group_id` non-nil) | yes (`teacher_user_id` nil, `class_group_id` optional) | **YES — the central pivot.** Two partial unique indexes encode the two modes (`teaching_context.ex:12-25`: `WHERE teacher_user_id IS NULL` = personal, `IS NOT NULL` = school). | `Curriculum.fetch_assigned_teaching_context/2` (`:618-639`) branches on scope type; `resolve_current_context/3` (personal, any ctx) vs `resolve_assigned_context` (school, own ctxs) (`workspaces.ex:36,63`). Carries `coefficient`, `weekly_hours` (school) AND `annual_hours`, `target_*` (personal quotas). |
| `ClassGroup` | yes | yes (created from `RosterLive` `create_class`) | YES | `form_master_user_id` is school-only. Personal classes are the same table. |
| `Student`, `Enrollment` | yes | yes (`Enrollment.add_student/2` `enrollment.ex:173`) | YES | Matricule uniqueness per workspace; `Enrollment.status/repeater` used by bulletins only. |
| `Assessment`, `Mark` | yes (via `/teacher/contexts/:id/marks` in school scope + `Assessment.class_results_for_period` for bulletins) | yes | **YES — a mark belongs to an `Assessment` → `TeachingContext` which can be personal OR school.** No column distinguishes; mode is inferred from the context's `teacher_user_id`. | `Assessment.:create_combined` writes one assessment per member context (`assessment.ex:74`). |
| `CombinedCourse` | yes only (needs `teacher_user_id` non-nil `combined_course.ex:105`) | no | school-only but **creates a `ProgressionPlan`** on combine (`:162-171`) and destroys it on split (`:83-86`) | Pausing the fiche UI leaves orphan school plans — harmless but present. |
| `ProgressionPlan` | indirectly (combined-course plan; teacher dashboard/log in school scope) | yes | **YES — `ExactlyOneOwner`** (`progression_plan/exactly_one_owner.ex`): owner is a `TeachingContext` (personal or school) XOR a `CombinedCourse` (school). | School-mode lookups are **workspace-scoped, not teacher-scoped**: `Curriculum.unit_plans!(ws.id)` in `Teacher.DashboardLive` (`dashboard_live.ex:13`) and `LogLive` (`log_live.ex:8`); `fetch_owned_plan(id, ws)` in `FicheLive` (`:14`) / `CoverageLive` (`:8`); `fetch_owned_entry_with_context(entry_id, ws)` in `LessonPlanLive` (`:8`) and `FichePrintController` (`:13`); `ImportLive` lists all `list_teaching_contexts(ws, year)` (`import_live.ex:14`). → In a school, **any member can view/edit/import into any colleague's plan and log**. No test asserts otherwise (the isolation tests only cover marks/roster/summary: `marks_isolation_test.exs`). |
| `ProgressionModule`, `ProgressionEntry`, `LessonPlan`, `LessonStep`, `TeachingLogEntry`, `Coverage`, `Quota`, `ModuleGrouping`, `Reference`, `FicheParser`, `FicheExtractor` | no (except through the leaks above) | yes | Personal-only in practice | Clean to park. `Reference.default_calendar_preset/0` (`reference.ex`) is ALSO needed by school calendar seeding — keep the module. |
| `Period`, `TimetableSlot`, `AttendanceEntry`, `SanctionEntry`, `ConductMark` | yes | no | School-only | `AttendanceEntry.teaching_context_id` FK to a school context. |
| `FeeTranche`, `Payment`, `FeeAdjustment`, `FeeBalance` | yes | no | School-only, self-contained | Only inbound UI link: `class_live.ex:100`. |
| `Subject` | yes | no (personal contexts use free-text `subject` string; school assignments copy `Subject.name` into `TeachingContext.subject` `curriculum.ex:136`) | School-only | Note: `TeachingContext.subject` is a **string**, not an FK to `Subject` — renaming a subject in the catalog does not propagate. |
| `SchoolProfile`, `SchoolMembership`, `SchoolInvitation`, `SchoolRole`, `MembershipStatus`, `InvitationStatus` | yes | no | School-only | |
| `User` (`role: teacher|principal_teacher|admin` `user_role.ex`) | yes | yes | Platform | `UserRole.:principal_teacher` unused anywhere. |
| `Scope` | yes | yes | Carries `current_workspace_type` `:personal_teacher|:school` and `current_context` | `personal_context?/1` unused. |

**Cleanly pausable** (no school code path touches them once the `/teacher` personal routes are gone): LessonPlan/LessonStep, TeachingLogEntry, FicheParser/FicheExtractor, Quota, Coverage, ModuleGrouping, personal-mode `RosterLive` writes, `Teacher.SetupLive`, `Teacher.ImportLive`.

**Entangled** (need care): `TeachingContext` (keep, both modes), `ProgressionPlan` (school combine/split creates/destroys it; teacher dashboard/log surface it), `Assessment/Mark` (school marks entry is the personal register code), `Workspace :personal` (default scope for everyone), `Reference` (calendar preset).

---

## 4. THE PAUSE PLAN (proposal)

### 4.1 What is teacher-personal but REQUIRED by the school flow (do not pause)
- `Teacher.MarksLive`, `Teacher.MarksSummaryLive`, `Teacher.RosterLive` (read-only mode), `TeacherContextController` (`/teacher/select-context/:id`), the class-context switcher + per-class nav in `layouts.ex:159-195, 284-315`, `Curriculum.fetch_assigned_teaching_context/2`, `list_units_for_scope/1`, `Assessment`, `Mark`, `Marks`, `Sequence/Term`, `Reference.default_calendar_preset/0`, `Organization.build_default_calendar/1`.
- `on_mount :require_teaching_scope` (keeps unassigned school members out of the marks pages).
- Tests to keep green: `marks_live_test`, `marks_combined_test`, `marks_isolation_test`, `marks_summary_live_test`, `school_scope_ux_test` (roster read-only; fiche-print test inside it would need moving), `teacher_context_controller_test`, `context_switcher_combined_test`, `school_teaching_scope_test`.

### 4.2 Recommended mechanism: router-level removal + scope-default change, behind one compile-time flag (not delete, not runtime feature flag)

Rationale:
- **Delete** loses ~2,500 lines of working, tested LiveView code (fiche 630, marks-of-personal, import 419, lesson plan 327, setup 206, log 143, coverage 134, dashboard 253) and 100+ tests that the owner explicitly wants parked, and forces a rewrite if teacher-personal returns.
- **Runtime feature flag** (per-workspace/env) keeps dead UI compiled into every request, keeps the personal-workspace auto-creation in the hot path, and gives a false sense that "personal mode still works" while it silently diverges. There is also no existing flag infrastructure (`grep feature config/` → none).
- **Router-level removal** is the least risky: the LiveViews and Ash resources stay compiled (so `mix precommit`'s `compile --warning-as-errors` keeps catching drift in shared modules), nothing is reachable, and re-enabling is a one-line router change. Guard it with `Application.compile_env(:teacher_assistant, :teacher_personal_routes, false)` exactly like the existing `:dev_routes` pattern (`router.ex:144`) so the pause is auditable and reversible.

### 4.3 Concrete change list

**Router (`lib/teacher_assistant_web/router.ex`)**
1. Split `live_session :teacher_workspace` (`:84-100`): keep `/teacher/contexts/:id/roster|marks|marks/summary` (rename the session to `:teaching` for clarity; keep both on_mounts). Wrap under the compile flag: `/teacher` (dashboard), `/teacher/setup`, `/teacher/import`, `/teacher/log`, `/teacher/plans/:id`, `/teacher/plans/:id/coverage`, `/teacher/entries/:entry_id/fiche`.
2. Same flag around `get "/teacher/entries/:entry_id/fiche/print"` (`:40`) and `post "/workspaces"` (`:38`, already orphaned).
3. Keep `get "/teacher/select-context/:id"` (`:39`).

**Default landing / redirects (all currently `/teacher`)**
4. `AuthController.success/4` `auth_controller.ex:6` → `~p"/school"` when the user has a school membership, else `~p"/schools/new"` (see 4.4). Also `LiveUserAuth.on_mount(:live_no_user)` `:78`, `LocaleController.set` `:10`, `WorkspaceController` `:23,:36`, `SchoolInvitationController` `:34,:51`, `TeacherContextController` fallback `:17` (→ `/school`), and `MarksLive/MarksSummaryLive/RosterLive` fallbacks `push_navigate ~p"/teacher/setup"` (`marks_live.ex:21,54,88`, `marks_summary_live.ex:36`, `roster_live.ex:18`) → `/school`.
5. `School.DashboardLive/ClassesLive/MembersLive/MyTimetableLive/PeriodsLive` non-school fallback `push_navigate ~p"/teacher"` (`dashboard_live.ex:17`, `classes_live.ex:15`, `members_live.ex:18`, `my_timetable_live.ex:14`, `periods_live.ex:13`) → a "pick or create a school" page (see 4.4).

**Workspace kind `:personal` creation path**
6. Stop auto-creating personal workspaces: `Workspaces.scope_for(user, nil, ctx)` (`workspaces.ex:10-13`) should resolve to the user's **first active school membership** (or a `%Scope{current_user: user}` with no workspace) instead of `ensure_personal_workspace!`. `Organization.list_workspaces_for/1` (`organization.ex:63-73`) should return schools only. Keep `ensure_personal_workspace!/1` and `Workspace.:for_owner` (test fixtures `workspace_fixture/1` use them) but unreachable from the web layer. Existing personal rows in the DB are untouched.
7. `Layouts.app`: workspace dropdown (`layouts.ex:120-152`) lists schools only; `workspace_type_label(:personal_teacher)` (`:411`) can stay.

**Navigation (`components/layouts.ex`)**
8. Remove/flag the personal `#main-nav` (`:201-232`: Dashboard `/teacher`, Log, Import) and the `@units == [] && !@in_school?` "set up" callout (`:192-196` → `/teacher/setup`).
9. Per-class nav (`:284-315`) stays; consider adding a "Notes" rail entry in `#school-nav` that opens the first unit's marks page (Gap G4).

**Teacher-facing LiveViews that stay compiled but unreachable**
10. `Teacher.DashboardLive`, `SetupLive`, `ImportLive`, `LogLive`, `FicheLive`, `CoverageLive`, `LessonPlanLive`, `FichePrintController` + `fiche_print_html.ex`. Add a `@moduledoc "PAUSED — see docs/…"` only; no code change needed.
11. `Teacher.RosterLive`: keep, but the personal-mode write events (`create_class`, `add_student`, `delete_student`, `undo_delete`) are already rejected in school scope (test "forged roster mutation events are rejected under school scope"). Nothing to do.

**Ash resources**
12. Nothing to remove. `ProgressionPlan/Module/Entry`, `LessonPlan/Step`, `TeachingLogEntry`, `FicheParser/Extractor`, `Quota`, `Coverage`, `ModuleGrouping` become unreachable from the UI. `CombinedCourse.:combine` still creates a plan (`combined_course.ex:49-51`) — harmless; optionally make plan creation there conditional later.
13. `assets/js/hooks/module_layout.js` (DnD for fiche) stays imported (`app.js:27,50`); it is inert without the hook element.

**Tests**
14. Tag the personal-only test files with `@moduletag :teacher_personal` and add `exclude: [:teacher_personal]` to `ExUnit.start` in `test/test_helper.exs` (no tags exist today — grep found none): `live/teacher/{dashboard,setup,fiche,import,lesson_plan,log,coverage}_live_test.exs`, `navigation_test.exs` (asserts personal nav), `shell_test.exs` (check), `controllers/fiche_print_controller_test.exs`, `academics/{progression_plan,progression_plan_unit,progression_entry,progression_module,module_grouping,apply_layout,quota,lesson_plan,lesson_plan_resource,lesson_step,teaching_log_entry,coverage,fiche_parser,fiche_extractor,import_progression_plan}_test.exs`. ≈ 25 files / ≈ 150 tests.
15. Tests that will break from the redirect change (4–6) and must be updated rather than skipped: `auth_smoke_test`, `locale_test`, `workspaces_test` (personal default), `dashboard_live_test` (school, "teacher pages redirect…"), `school_scope_ux_test` ("setup redirects to /school", "fiche print shows the school name" → move to the paused set), `roster_live_test` (personal mode cases), `marks_live_test` / `marks_summary_live_test` personal-mode cases (they use `workspace_fixture` = personal ws; convert fixtures to `setup_complete_school_fixture` + `assign_teacher`), `teacher_context_controller_test`.
16. `test/support/fixtures/teacher_fixtures.ex`: `workspace_fixture/1` returns the personal workspace and is used by 21 test files; keep it for the paused set, but add a school-mode variant for marks tests.

**Docs**
17. Update `docs/PRODUCT.md` "Principles/Phased roadmap" and `docs/DESIGN.md` "Personal Teacher Workspace" section to mark teacher-personal as paused.

### 4.4 New minimal surface the pause creates (must exist or users dead-end)
- A **"no school yet" landing** for a signed-in user with zero memberships (today they'd land on `/teacher`): simplest is `AuthController.success` → `/schools/new` when `list_workspaces_for` is empty, and `School.*` fallbacks → `/schools/new`. `CreateSchoolLive` already handles this.
- A user with several schools: `scope_for(user, nil, _)` picks the first; the header dropdown switches. Fine.

---

## 5. GAPS for "create school → subjects/classes/teachers → roll call + marks"

**G1 — School academic year has no terms/séquences (blocking for marks).**
`SetupWizardLive` `create_year` (`setup_wizard_live.ex:246-253`) and `SettingsLive` `create_year` (`settings_live.ex:373-379`) submit `AcademicYear.:create_for_workspace` (`academic_year.ex:27-34`, no after_action building the calendar) and then only seed classes. `Organization.build_default_calendar/1` (`organization.ex:135-162`) is called from `lib/` exclusively by the personal `Teacher.SetupLive` (`setup_live.ex:44`). Consequences in a school created through the real UI: `MarksLive` `sequences = Organization.list_sequences(year)` is `[]` (`marks_live.ex:29-30`) so no assessment can be created; `ResultsLive`/`BulletinLive` period selectors empty; `DisciplineLive` note de conduite has no séquence. 20 test files mask this by calling `build_default_calendar` manually (e.g. `test/teacher_assistant_web/live/school/results_live_test.exs`, `bulletin_live_test.exs`, `register_live_test.exs`, `fees_live_test.exs`, `academics/mark_test.exs`); `complete_school_setup!` in `test/support/fixtures/teacher_fixtures.ex:39-51` does NOT build it, and `setup_wizard_live_test.exs` never mentions sequences. Fix: call `build_default_calendar` in the `:create_for_workspace` after_action (or in the wizard), and give Settings a Terms/Séquences editor (roadmap increment 4 "term structure").

**G2 — Roll call requires a fully built timetable.**
`AttendanceLive` needs a `Period` (`/school/periods`, admin-only, reachable only via a link at `settings_live.ex:328`) and a placed `TimetableSlot` for class × day × period (`Attendance.slot_for/3` `attendance.ex:108-119`); without a slot the teacher is "Access denied" (`attendance_live.ex:95-98`). There is no "take attendance for my class now" entry that works from an assignment alone. For a minimal school, either (a) make the wizard seed default periods (`Attendance.build_default_periods/1` exists `attendance.ex:84`) and let a teacher record attendance for any class they are assigned to when no slot exists, or (b) add a timetable step to the wizard.

**G3 — Marks entry is only reachable through the `/teacher/*` area and the context switcher.**
No `/school/*` route for marks; the school nav rail has no "Notes" item (`layouts.ex:234-282`); the school dashboard has no teacher-facing list of assignments (`dashboard_live.ex` renders checklist/KPIs/form-master classes only). A teacher must find the class-switcher dropdown then the per-class rail. Also `MarksLive` fallbacks redirect to `/teacher/setup` (`marks_live.ex:21,54,88`), which in school scope bounces to `/school` (`setup_live.ex:16-17`) — a silent loop for the user.

**G4 — School verification is a hard gate with no in-product path.**
`operating_allowed?` (`permissions.ex:59-61`) blocks marks save (`marks_live.ex:174`), attendance record (`attendance_live.ex:159`) and bulletin print (`bulletin_print_controller.ex:42`) until a platform `:admin` verifies via `/admin/schools`. `User.:promote_to_admin` has no UI; only `priv/repo/seeds.exs` (dev) creates users. For the school-first goal either auto-verify on creation (dev/staging) or build the operator promotion path.

**G5 — Configuration surface is thin (roadmap increment 4 not started).**
No UI for: terms/séquences (G1), grading scale / mention thresholds (hard-coded `academics/marks.ex:15-16`), number of devoirs per séquence, per-série coefficients (coefficient is per Subject then per assignment only), year edit/delete/archive, school delete/transfer. `AcademicYear` has `update: [:name, :start_date, :end_date, :active]` but no LiveView calls it.

**G6 — Role model is coarse; no head-of-school vs staff separation beyond head/vice_principal.**
`Permissions` (`permissions.ex`) knows head, admin (head|vice_principal), bursar, discipline_master, form master (FK). `:hod`, `:guidance_counsellor`, `:librarian` (`school_role.ex:5-15`) grant nothing. Authorization is presentation-only; every resource policy is allow-all (spec `2026-09-23-authorization-hardening-design.md`, not implemented). A plain `:teacher` member can open `/school/members` (read) and the setup wizard (read).

**G7 — Data isolation leak inside a school for progression/log/import surfaces** (also §3): `Teacher.DashboardLive`, `LogLive`, `ImportLive`, `FicheLive`, `CoverageLive`, `LessonPlanLive`, `FichePrintController` use workspace-scoped queries in school scope, so members see and can edit colleagues' plans. Pausing those routes (4.3 step 1) removes the leak; if any of them is kept, they need the `fetch_assigned_*` treatment that marks already has.

**G8 — Subject is not a foreign key on assignments.**
`Curriculum.assign_teacher/3` copies `Subject.name` into `TeachingContext.subject` (string) (`curriculum.ex:134-146`); duplicate detection is by name; renaming/deleting a catalog subject leaves assignments untouched (`class_live_test` "unassign removes a data-free assignment; blocked with data" shows deletion guard is only on the assignment side). Fine for now, but bulletins group by that string (`Assessment.class_subjects/2`).

**G9 — Class "spécialité" has no dedicated field**; `SchoolTemplates.streams_for/2` (`school_templates.ex:71-92`) relabels the `serie` column as Série/Spécialité/Stream. Acceptable, but the spec `2026-09-17-school-subjects-teaching-model-design.md` §3 asked for first-class specialities.

**G10 — Dead ends for non-admin members**: a `:teacher` member of a school whose setup is incomplete is redirected to the wizard where every action is admin/head-gated (`setup_wizard_live.ex:250,282,305,343`), with no message. A member with no assignment and no form-master class lands on `/school` with only a checklist they cannot act on.

**G11 — Prod mailer not configured** (`config/runtime.exs:109-123` commented Mailgun example); invitations only work in dev (`/dev/mailbox`) and test.

**G12 — Legacy/orphaned routes**: `POST /workspaces` (`router.ex:38`, `workspace_controller.ex:27`) no longer has a caller; `UserRole.:principal_teacher` and `Scope.personal_context?/1` unused.

---

## Appendix — test count by area (674 total)

- Shared/auth/kit: 33 (auth_smoke 4, locale 1, page 3, error_html 2, error_json 2, kit 5, switcher 1, money 5, senders 2, emails 2, shell 3, navigation 1, permissions 11 — permissions counted under school below instead) → 22 + permissions 11.
- School identity/workspace/wizard/dashboard/scope: create_school 1, schools_create 6, schools 5, school_profile 4, school_resources 4, school_enums 2, catalog_seed 2, school_templates 6, seeding 2, workspace 2, workspaces 8, workspaces_verification 2, permissions 11, setup_wizard 12, setup_gate 4, dashboard(school) 9, school_teaching_scope 3, admin schools 2, operate_gate 2 = **87**.
- Members/invites: 20. Settings/years/subjects/calendar: 24. Classes/assignments/enrollment/combined: 89 (class_live 29, assignments 12, courses 7, combined_course 1, teaching_context 6+2, enrollments 9+7, student 5, enroll_import 5, classes_live 7, class_group 3+3, form_master_context 3).
- Periods/timetable: 35. Attendance/register: 46. Discipline: 49. Marks (shared code, school-critical): 67 (marks_live 14, combined 4, isolation 3, summary 7, roster 5, school_scope_ux 4, ctx controller 4, mark 10, marks 11, assessment 4, switcher_combined 2, resolve_context 3). Results/bulletins: 36. Fees: 61.
- Teacher-personal only: ≈ 116 (dashboard 5, setup 4, fiche_live 13, plan 4+6, entry 2, module 10, grouping 1, apply_layout 5, quota 2, reference 5, import_live 7, extractor 2, parser 9, import_plan 4, lesson_plan_live 7, lesson_plan 6+3, lesson_step 4, fiche_print 2, log_live 5, coverage_live 4, coverage 4, log_entry 1).
