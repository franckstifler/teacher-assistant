# Teacher Member Profile Implementation Plan

**Goal:** Deliver the approved Overview, Timetable and Settings drawer, including service comparison, contact shortcuts and individual timetable printing.

**Architecture:** Keep MembersLive as the event owner. Add a scoped TeacherProfile reader for grouped assignments and schedule totals and a MemberProfileComponents module for presentation. Reuse existing member settings and print templates.

**Tech Stack:** Elixir, Phoenix LiveView, Ash, PostgreSQL, Tailwind and daisyUI.

## Global constraints

- Selected school/year and existing staff/service-management permissions apply to all reads.
- Combined courses count once per teaching period. Scheduled hours mean school periods, not 60-minute durations, matching the existing editor.
- Keep unsaved settings mounted across tab changes. Keep French and English strings.
- Gate timetable features by the school module and preserve existing member administration.
- No migrations or new dependencies.

## Task 1: Scoped teacher profile

Files: create `lib/teacher_assistant/academics/teacher_profile.ex` and `test/teacher_assistant/academics/teacher_profile_test.exs`.

- [x] Test selected school/year, independent form-master duties, combined-course totals, missing year and unauthorized viewer.
- [x] Implement `TeacherProfile.load(scope, member)` returning `{:ok, profile}` or `{:error, reason}`. Use existing assignment, class, service, calendar and timetable reads. Group assignments by combined course or context ID, count scheduled lessons by day/period/unit, and compute missing periods per assignment so excess periods cannot conceal gaps elsewhere.
- [x] Run `mix test test/teacher_assistant/academics/teacher_profile_test.exs`.

## Task 2: Member drawer

Files: modify `members_live.ex`, `members_components.ex`, `components/drawer.ex`, `assets/js/app.js`; create `live/school/member_profile_components.ex` and `assets/js/hooks/member_profile_tabs.js`.

- [x] Add member profile, selected tab and selected day state; initialize and reset on member selection/close. Reject unrecognized tabs/days and retry academic reads only for the selected authorized member.
- [x] Add an optional wide drawer variant without changing other drawers.
- [x] Render profile details, assigned/expected/scheduled service, per-course classes and missing periods, form-master classes, phone call/copy and email shortcuts.
- [x] Render school-day mobile lessons and desktop grid, preserving real overlaps and combining shared lessons. Keep the settings form mounted but hidden outside Settings. Show its save footer only on Settings.
- [x] Implement arrow/Home/End keyboard tab navigation. Keep existing clipboard behavior and add success/failure feedback for the new contact shortcut.
- [x] Extend member LiveView tests for defaults, transitions, state reset, no year/data and permissions. Run `mix test test/teacher_assistant_web/live/school/members_live_test.exs`.

## Task 3: Individual timetable print

Files: modify `controllers/timetable_print_controller.ex`, `router.ex`, `modules.ex`, and `test/teacher_assistant_web/controllers/timetable_print_controller_test.exs`.

- [x] Add `/school/members/:id/timetable/print`, resolving membership from the current school's members and requiring staff/service-management permission. Render a single existing teacher print sheet.
- [x] Register the new action with the timetable module gate and link it from the profile only when enabled and a year exists.
- [x] Test one teacher only, foreign/malformed member IDs, unauthorized callers and module registration.

## Task 4: Integration verification

- [x] Extract and translate new Gettext strings in English.
- [x] Run focused profile/member/print tests, then `mix precommit` and asset build.
- [x] Inspect responsive layout and keyboard interactions in the running app if a usable local session is available. Record any environmental blockers and remaining verification honestly.


## Verification results

- 62 focused tests passed across TeacherProfile, MemberProfileLive, MembersLive and TimetablePrintController.
- Asset build, format check, Gettext extraction check and Git whitespace check passed.
- Browser verification used disposable SQL-sandbox fixtures: overview, timetable, 390 px and 320 px phone layouts, keyboard tabs, unsaved name preservation across tabs, and the individual teacher print sheet. The preview server was stopped afterward and fixtures rolled back.
- `mix precommit` passed compilation, then stopped at the existing Plug 1.20.3 advisory EEF-CVE-2026-120287. No dependency changes were made.
- The full test run was stopped after repeated unrelated PostgreSQL failures: the running Homebrew PostgreSQL 18.6_1 binary could not load the installed 18.7 plpgsql library (missing `_DatumGetHeapTupleHeader`). A lesson-plan concurrency test also encountered a connection-queue timeout. The shared database service was not restarted. The focused suite was rerun afterward and passed.
