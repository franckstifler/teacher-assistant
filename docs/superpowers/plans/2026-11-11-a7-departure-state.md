# A7 — Departure state instead of destroy on withdraw — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A student who leaves mid-year keeps their history: the enrollment stays with `left_on` and a reason, rosters and roll calls drop the student from that day, every period that started before that day keeps them on its bulletin and in its figures, and only a mistaken enrollment with no history can still be deleted.

**Architecture:** `Enrollment` gains `left_on`, `departure_reason`, `departure_note`, the actions `:leave` and `:return` (admin only), and a `current_on` argument on its roster read `:for_class_group`. The one roster choke point, `Enrollment.roster_query/3`, applies the date rule; `list_roster/3` and `list_students/3` take `on: date | :all`, default today. Readers that know a date (roll call, register) pass it; readers that know a period (bulletins, entry progress) pass the period's first day. The Élèves page gets a « Partis » pill, the class roster a « Marquer parti… » form, the student page a departure block with « De retour », the bulletin a « parti le … » line.

**Tech Stack:** Elixir, Ash 3.37 / AshPostgres (`mix ash.codegen --dev`), Phoenix 1.8 LiveView 1.2, Gettext FR source + EN.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A7.

## Global Constraints

- **Period rule (confirmed by the user, 2026-11-10):** a departed student is **in** a period whose first day is before `left_on` (`Organization.period_date_range/2` first element; a séquence's `start_date`), **out** of a period starting on or after `left_on`; rosters and roll calls compare `left_on` to the day itself: in when `left_on > day`.
- `EnrollmentStatus` (inscription / réinscription) is untouched; departure is the two fields.
- `:leave` and `:return` are the admin axis (`{Checks.SchoolRole, any_of: :admin}`); the existing destroy policy (admin or the class's form master) is unchanged for the mistaken-student case, which is refused as soon as the student has a mark, an attendance entry, a sanction, a payment, a fee warning or a return note (`student_deletion_blocker/2` extended; same blocker for the enrollment path).
- One enrollment per student per year stays a DB identity: `:return` updates the departed row; `enroll_existing` in the same year keeps returning `{:error, :already_enrolled}` and the UI says to use « De retour » instead.
- The fee balance of a departed student is left as it is; `Fees.enrollments_of/2`, `recovery/3` and `arrears_candidates` are not filtered (the bursar still sees what is owed).
- Never write a migration by hand: `mix ash.codegen --dev add_enrollment_departure`, read it, `mix ash.migrate` on dev.
- Branch `feat/audit-a7` in `.claude/worktrees/audit-a7`, `MIX_TEST_PARTITION=a7`; explicit paths; Gettext extract + EN, no fuzzy; `mix precommit` green before merge.

## Review Focus

1. A student who left on the first day of a séquence (`left_on == seq.start_date`): out of that séquence (not before), in the previous one — Task 2 tests the boundary both ways.
2. A departed student's bulletin page `/school/classes/:id/students/:enrollment_id/bulletin`: must still open for the periods they were in (the roster lookup there uses `on: :all`) — Task 2 tests it.
3. A teacher's marks grid for a séquence that started before the departure: the student stays in the grid and may still receive a mark for that séquence (`Mark.StudentEnrolled` compares to the assessment's séquence start, not today) — Task 2 tests a mark entered after departure for an earlier séquence is accepted and for a later one refused.
4. A closed year: `:leave` and `:return` are refused by `YearOpen` like any write; the register of a closed year is unchanged — Task 1 tests it.
5. The class list print and the exam-photos page of a class with a departed student: they use `list_roster` default today, so the student is absent from today's lists — Task 2 tests one print.

---

### Task 1: Fields, actions, roster date rule, context functions

**Files:**
- Create: `lib/teacher_assistant/academics/departure_reason.ex` (`use Ash.Type.Enum, values: [:transfer, :dropout, :exclusion, :other]`, `label/1` « Transfert », « Abandon », « Exclusion », « Autre »)
- Modify: `lib/teacher_assistant/academics/enrollment.ex` (attributes :208-218, actions :41-174, policies :176-193, `read :for_class_group` :55-59, `read :school_list` :62-96)
- Modify: `lib/teacher_assistant/academics/class_group.ex:220` (`count :enrollment_count, :enrollments` with `filter expr(is_nil(left_on))`)
- Modify: `lib/teacher_assistant/enrollment.ex` (`withdraw/2` :731 → `leave/3`; new `return/2`, `remove_mistaken/2`, `departed?/1`; `student_deletion_blocker/2` :262 extended; `roster_query/3` :634, `list_students/3` :545, `list_roster/3` :552, `list_school_students/3` :565, `student_counts/2` :592; aliases `AttendanceEntry`, `SanctionEntry`)
- Create (generated): migration + snapshot
- Test: `test/teacher_assistant/academics/enrollment_departure_test.exs` (new), `test/teacher_assistant/cross_workspace_guard_test.exs`, updates to `enrollments_test.exs`, `enrollments_model_test.exs`, `student_deletion_test.exs`, `fees_data_test.exs:179`, `fees2_data_test.exs:112`, `revocation_test.exs:27`

**Interfaces:**
- Attributes: `left_on :date` (nil while enrolled), `departure_reason DepartureReason` (nil while enrolled), `departure_note :string, constraints: [max_length: 200]`; all `public? true`.
- `update :leave` — `accept [:left_on, :departure_reason, :departure_note]`, `require_atomic? false`; `left_on` defaults to `Reference.today()` when absent (`change` before validations); `validate present(:departure_reason)`; `validate attribute_equals(:left_on, nil)` on the **stored** record is not expressible — a custom validation `NotDeparted` refuses when `changeset.data.left_on != nil` (message « Cet élève est déjà marqué parti. »). `update :return` — no accepted attributes, sets the three fields to nil, refused when `data.left_on == nil`. `policy action([:leave, :return]) do forbid_unless member; authorize_if admin end`, placed **before** the `action_type([:create, :update, :destroy])` policy so a form master is refused.
- `read :for_class_group` gains `argument :current_on, :date` (optional): `filter expr(is_nil(^arg(:current_on)) or is_nil(left_on) or left_on > ^arg(:current_on))`. `read :school_list` gains `argument :departed, :boolean, default: false`: `filter expr((^arg(:departed) and not is_nil(left_on)) or (not ^arg(:departed) and is_nil(left_on)))`.
- `Enrollment.list_roster(scope, cg, opts \\ [])`, `list_students(scope, cg, opts \\ [])` — `opts[:on]` is a `Date` (default `Reference.today()`) or `:all` (no date filter); `roster_query(cg_id, scope, on)` passes `current_on`.
- `Enrollment.leave(scope, %Enrollment{} = e, attrs) :: {:ok, e} | {:error, term}` (attrs `%{departure_reason:, left_on:, departure_note:}`); `return(scope, e)`; `remove_mistaken(scope, e) :: :ok | {:error, :marks | :attendance | :sanctions | :fee_documents | term}` — runs the blocker for the enrollment's student, then `Ash.destroy` as `withdraw/2` did. `withdraw/2` is deleted (callers updated in Task 3). `student_deletion_blocker/2` returns, in order, `:marks`, `:attendance` (`AttendanceEntry` with `enrollment.student_id`), `:sanctions` (`SanctionEntry` likewise), `:fee_documents`.
- `list_school_students/3` accepts `departed: true`; `student_counts/2` gains `departed:`.

- [ ] **Step 1: Write the failing tests**

```elixir
# enrollment_departure_test.exs — school_fixture + complete_school_setup!, cg "6e A", students Awa and Bilal
test "leave stamps today, the reason and the note; status is untouched"            # left_on == Reference.today(), status still :inscription
test "a departed student is out of today's roster and in yesterday's"             # list_roster(on: Date.add(today, -1)) includes; default excludes; on: :all includes
test "leave is refused twice, and refused to a form master"                        # second leave {:error, _}; member_scope_fixture + set_form_master → assert_forbidden
test "return clears the departure and re-enrolling in the same year is refused"    # enroll_existing → {:error, :already_enrolled}; return → left_on nil, back in the roster
test "remove_mistaken deletes an enrollment without history and names the blocker otherwise"  # attendance entry → {:error, :attendance}; sanction → :sanctions
test "enrollment_count counts current students only"
test "the Élèves list hides departed students unless departed: true; counts follow"
test "a closed year refuses leave and return"                                      # close_year! → {:error, _}
# cross_workspace_guard_test: "Enrollment.leave refuses another school's enrollment" (scope_b on enrollment_a → {:error, _}; reload with scope_a: left_on nil)
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a7 mix test test/teacher_assistant/academics/enrollment_departure_test.exs` — FAIL (`leave/3` undefined).
- [ ] **Step 3: Implement** enum, attributes, actions, policies, read arguments, aggregate filter; `mix ash.codegen --dev add_enrollment_departure`; context functions. Update the listed existing tests: the same-year re-enrol tests (`enrollments_test` "enroll_existing re-enrolls…", "import_rows…", `enroll_import_live_test:48,167`, `class_live_test:192`) use `remove_mistaken/2`; the "cannot be withdrawn" fee tests assert `remove_mistaken` returns `{:error, :fee_documents}` and `leave` succeeds; `revocation_test` asserts the revoked form master cannot `remove_mistaken`; `entry_progress_test:121` uses `leave` with `left_on` before the séquence start (Task 2 makes it pass — mark it `@tag :a7_task2` and skip until then, or order it in Task 2; ruling in the ledger).
- [ ] **Step 4: Run** the new file + `test/teacher_assistant/academics/` + `cross_workspace_guard_test.exs` — PASS.
- [ ] **Step 5: Commit** `feat(enrollment): departure state (left_on, reason) with leave / return / remove_mistaken`.

---

### Task 2: The period rule in every reader

**Files:**
- Modify: `lib/teacher_assistant/organization.ex` (`period_first_day(scope, period) :: Date` next to `period_date_range/2` :349)
- Modify: `lib/teacher_assistant/assessment.ex` (`bulletin_students/4` :1367-1382 → `on: period_first_day`; `mark_sheet/3` :1314 → first séquence's start)
- Modify: `lib/teacher_assistant/academics/attendance_entry.ex:367-403` (`period_roll` passes `current_on: date` to its own `:for_class_group` read), `lib/teacher_assistant/attendance.ex` (`validate_group_marks` :370, `record_period` :446, `class_register/3` :575, `class_conduct/3` :674 → `on:` date / period first day)
- Modify: `lib/teacher_assistant/academics/entry_progress.ex:202-220` (`load_enrolled` filters `is_nil(left_on) or left_on > ^seq.start_date`; callers pass the séquence)
- Modify: `lib/teacher_assistant/academics/mark/student_enrolled.ex:50-54` (enrolled when `is_nil(left_on) or left_on > assessment's sequence start_date`; load the séquence start through the assessment in the changeset), `lib/teacher_assistant/academics/mark_correction/request.ex:67-75` (same rule)
- Modify: `lib/teacher_assistant/report_cards.ex` (`live_view/3` :50 `list_roster(on: :all)` for the frozen roster but `results` already filtered by `bulletin_students`; `plain_entry/2` :845 adds `left_on`), `lib/teacher_assistant_web/live/school/bulletin_live.ex:13` (`on: :all`), `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex:106` (« Parti(e) le <date> » under the name when `Map.get(b.enrollment, :left_on)`), `bulletin_print_controller.ex:71-99` (bundles only for students present in `results.per_student`)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex:59,275`, `marks_summary_live.ex:61,97` (`list_students(on: seq.start_date)`); `lib/teacher_assistant/academics/teacher_statistics.ex` (A4) — same rule for its students
- Test: `test/teacher_assistant/academics/departure_periods_test.exs` (new), `entry_progress_test.exs:121`, `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`, `class_list_print_controller_test.exs`

**Interfaces:**
- `Organization.period_first_day(scope, {:sequence, seq})` → `seq.start_date`; trimester / annual → `elem(period_date_range(scope, period), 0)`.
- Every reader listed passes `on:`; readers not listed (class overview, discipline sheet, fee control, council, new year, prints, exam photos, roster live, class shell count) keep the default today, which is the spec's rule for them.
- The bulletin bundle of a departed student in a period they were in carries `enrollment.left_on`; the template prints « Parti(e) le 12/03/2026 » in the identity cell under the name (same `Map.get` guard as the repeater row, so older snapshots render).

- [ ] **Step 1: Write the failing tests**

```elixir
# departure_periods_test.exs — calendar: S1 2025-09-08.., S2 starts later (read term.sequences); Awa leaves on S2's start_date
test "a student departed on a séquence's first day is out of it and in the previous one"   # class_results_for_period S1 has Awa, S2 has not; trimester 1 (starts with S1) has her
test "the roll call of the departure day excludes, the day before includes"                 # Attendance.period_roll(scope, cg, period, left_on) vs Date.add(left_on, -1)
test "a mark for the earlier séquence is still accepted, for the later one refused"         # upsert_marks on assessments of S1 / S2
test "entry progress counts the student in S1 only"
test "the bulletin of trimester 1 prints « Parti(e) le » under the name; trimester 2 has no bulletin for her"   # print controller
test "the departed student's bulletin page still opens for trimester 1"                     # /school/classes/:cg/students/:eid/bulletin?period=trim:
test "today's class list print no longer lists her"
```

- [ ] **Step 2: Run** the new file — FAIL (she is in every period, or out of all).
- [ ] **Step 3: Implement**, one reader at a time, running the file after each; un-skip `entry_progress_test:121`.
- [ ] **Step 4: Run** the new file + `test/teacher_assistant/` (whole directory) + the three controller tests — PASS.
- [ ] **Step 5: Commit** `feat(enrollment): departed students follow the period rule in results, roll calls and bulletins`.

---

### Task 3: Screens — « Marquer parti », « Supprimer (erreur de saisie) », « Partis », « De retour »

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (menu items :211-217 and :297-306; `handle_event("withdraw", …)` :517-525 → `"leave"` opening `#leave-form`, `"leave_submit"`, `"remove_mistaken"`)
- Modify: `lib/teacher_assistant_web/live/school/student_live.ex` (`load/1` :95-113, `#student-delete` :870-899, `deletion_blocker_text/1` :334-344, new `#student-departure` block, events `"leave_submit"`, `"return"`)
- Modify: `lib/teacher_assistant_web/live/school/students_live.ex` (`@flags` :18 + `:departed`, pill `#departed-pill` « Partis », `list_path/2` :136, counts)
- Test: `test/teacher_assistant_web/live/school/class_live_test.exs`, `student_live_test.exs:351-397`, `students_live_test.exs:113`

**Interfaces:**
- Class roster row menu: « Marquer parti… » (`phx-click="leave"`, `phx-value-enrollment-id`) opens a `<.modal id="leave-form">` with a `<.input type="select">` reason (`DepartureReason` labels), a date (default today), a note (optional); submit → `Enrollment.leave/3` → flash « Élève marqué parti. » and `load_roster/1`. « Supprimer (erreur de saisie) » (`data-confirm`) → `remove_mistaken/2`; `{:error, blocker}` → flash with `blocker_text/1` (« Cet élève a des notes : marquez-le parti plutôt. » etc.). The old « Retirer de la classe… » label and the `"withdraw"` event are gone.
- Student page: `#student-departure` for the current enrollment: when enrolled, the same « Marquer parti… » form; when departed, « Parti(e) le <date> · <reason label> · <note> » and a « De retour » button (admins) → `Enrollment.return/2`. `#student-delete` keeps its button; `deletion_blocker_text/1` reworded to point at « Marquer parti » on this page.
- Élèves: pill « Partis » (`?departed=1`) lists departed students of the year with « parti le … » under the name; count from `student_counts`.

- [ ] **Step 1: Write the failing tests**

```elixir
# class_live_test
test "« Marquer parti » asks a reason and removes the student from today's roster"   # form submit; refute row; reload: left_on set
test "« Supprimer (erreur de saisie) » deletes a history-less enrollment and refuses one with a roll call"  # flash text names the blocker
# student_live_test
test "the student page shows the departure and « De retour » brings the student back"
test "the deletion panel explains the blocker and points at « Marquer parti »"        # replaces the assertion at :380
# students_live_test
test "« Partis » lists departed students with their date; the default list hides them"
```

- [ ] **Step 2: Run** the three files — FAIL.
- [ ] **Step 3: Implement**; Gettext extract + EN (reason labels, « Partis », « Parti(e) le %{date} », flashes).
- [ ] **Step 4: Run** the three files + gettext tests — PASS.
- [ ] **Step 5: Commit** `feat(students): mark a departure, bring back, delete only a mistaken enrollment, « Partis » filter`.

---

### Task 4: Verify and merge

- [ ] Browser check on the demo school (worktree server on 4010, phone width): as proviseur mark a student parti with a backdated date inside S1, check the class roster, Élèves « Partis », the student page, « De retour »; a S1 bulletin print with « Parti(e) le »; the roll call of today without her; delete a freshly added student with no history. Take screenshots of the form and the bulletin line.
- [ ] `MIX_TEST_PARTITION=a7 mix precommit` → exit 0 (refresh Gettext references if needed); fast-forward merge into main; `mix ash.migrate` on the dev DB from main; update memory `project-audit-2026-11-10` (A7 merged; `withdraw/2` gone; the rulings: destroy policy kept for form masters, fees unfiltered).
