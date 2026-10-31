# Class Lists and School Timetable Prints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print a class roster (official and working versions), every teacher's timetable in one go, and the school-wide « emploi du temps général ».

**Architecture:** Three print pages in the app's existing style: Phoenix controllers rendering standalone HTML (`put_layout(false)`, `put_root_layout(false)`, `window.print()` button), gated by `TeacherAssistantWeb.Plug.SchoolAccess` and mapped in `TeacherAssistant.Modules`. Data comes from `Enrollment.list_roster/2` and two new `Timetabling` loaders that read the current year's slots in one query each. The bulletin's official header markup moves into a shared component so the roster reuses it.

**Tech Stack:** Elixir 1.20, Phoenix 1.8, Ash 3 (multitenant, `scope:` everywhere), Gettext (fr default, en).

**Spec:** `docs/superpowers/specs/2026-10-31-class-list-and-timetable-prints-design.md`

## Global Constraints

- Work in a worktree: `git worktree add .claude/worktrees/prints -b feat/prints main`, `ln -s ../../../deps deps`, `cp -Rc ../../../_build _build`; run tests with `MIX_TEST_PARTITION=_prints`. Stage explicit paths; never `git commit -a`; never touch the dev DB.
- Print pages are HTML only. No PDF generation, no Excel/CSV, no downloadable file.
- Every new route under `/school/` or `/teacher/` must be mapped in `TeacherAssistant.Modules` (`test/teacher_assistant_web/router_modules_test.exs` fails otherwise).
- Unauthorised access to a print route redirects to `/school`, like the other print controllers.
- Numbering = `Enrollment.list_roster/2` order (case-insensitive full name), 1..n. No other sort or filter.
- Gettext: French msgids; after `mix gettext.extract --merge`, fill every new English msgstr and remove `fuzzy` (fuzzy entries render at runtime); keep each .po's trailing newline. Existing translations to reuse: « Matricule »→"Student ID", « Effectif »→"Class size", « Garçons »/« Filles »→"Boys"/"Girls", « Redoublants »→"Repeaters", « Année scolaire »→"School year", « Professeur principal »→"Form master". New: « LISTE DE CLASSE »→"CLASS ROSTER", « EMPLOI DU TEMPS GÉNÉRAL »→"SCHOOL TIMETABLE".
- Dates print as `dd/mm/yyyy`.

## Review Focus

1. A class with no students, a school with no timetable yet, a year with no active academic year: every print renders (empty table / "no lesson" page), never crashes. → tests in Tasks 3, 6, 7.
2. Last year's slots after a new year starts must not leak into any timetable print. → Task 1 test, reused by Tasks 6–7 through the shared loaders.
3. A teacher opening the roster (A) URL directly, or the working list of a class they don't teach: redirected. → Tasks 3 and 4.
4. A student with no matricule / birth date / birth place: empty cells, not "nil" or "—". → Task 3.
5. A course combining two classes: shown in both class rows of the general grid, and once (with both class labels) in the teacher's sheet. → Tasks 6 and 7.

---

### Task 1: Timetables read the current year only

**Files:**
- Modify: `lib/teacher_assistant/academics/timetable_slot.ex` (`read :for_workspace_teacher`)
- Modify: `lib/teacher_assistant/timetabling.ex` (`define :list_for_teacher`, `teacher_timetable/2`)
- Test: `test/teacher_assistant/academics/timetables_reads_test.exs` (add a describe)

**Interfaces:**
- Produces: `Timetabling.teacher_timetable(scope, user) :: %{{day, period_id} => [slot_view]}` — unchanged shape, now restricted to `scope.current_academic_year`; `%{}` when the scope has no current year.

- [ ] **Step 1: Write the failing test** — `describe "teacher_timetable/2"`, test `"only the scope's current year"`: one teacher with a placed slot in year 2024-2025 (inactive) and one in 2025-2026 (active, `scope.current_academic_year`); assert the map has exactly the 2025-2026 cell; with `%{scope | current_academic_year: nil}` assert `== %{}`.
- [ ] **Step 2: Run** `MIX_TEST_PARTITION=_prints mix test test/teacher_assistant/academics/timetables_reads_test.exs` — Expected: FAIL (both years' cells returned).
- [ ] **Step 3: Implement** — add `argument :academic_year_id, :uuid, allow_nil?: false` and `filter expr(teaching_context.teacher_user_id == ^arg(:teacher_user_id) and teaching_context.academic_year_id == ^arg(:academic_year_id))`; `define :list_for_teacher, args: [:teacher_user_id, :academic_year_id]`; `teacher_timetable/2` gets a `%Scope{current_academic_year: nil}` clause returning `%{}`.
- [ ] **Step 4: Run** the file plus `test/teacher_assistant_web/controllers/timetable_print_controller_test.exs` and `test/teacher_assistant_web/live/school/my_timetable_live_test.exs` — Expected: PASS.
- [ ] **Step 5: Commit** `fix(timetable): a teacher's timetable shows the current year only`.

### Task 2: Shared official header component

**Files:**
- Create: `lib/teacher_assistant_web/components/official_header_components.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex`, `bulletin_print_html/show.html.heex:88-121`
- Test: existing `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (must stay green; no new test — pure move)

**Interfaces:**
- Produces: `TeacherAssistantWeb.OfficialHeaderComponents.official_header/1` with attrs `header` (map, required — `template.header`) and `logo?` (boolean, required). Renders exactly the bulletin's current markup: `div.header` (FR `official_lines` | logo + school code | EN `official_lines`), `div.school` (FR / EN `school_lines`, first line `.name`), `div.flag`. CSS stays in each page's `<style>`, class names unchanged.

- [ ] **Step 1:** Move `official_lines/2`, `school_lines/2`, `tr_list/2`, `present?/1` (the header's uses) and the markup into the component; `BulletinPrintHTML` imports it and the template calls `<.official_header header={@template.header} logo?={@logo?} />`.
- [ ] **Step 2: Run** `MIX_TEST_PARTITION=_prints mix test test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/controllers/card_print_controller_test.exs` — Expected: PASS, unchanged count.
- [ ] **Step 3: Commit** `refactor(print): official header as a shared component`.

### Task 3: Official class roster (version A)

**Files:**
- Create: `lib/teacher_assistant_web/controllers/class_list_print_controller.ex`, `class_list_print_html.ex`, `class_list_print_html/roster.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (the `[:browser, :school]` scope next to the other prints), `lib/teacher_assistant/modules.ex` (`@controllers`)
- Modify: `priv/gettext/default.pot`, `priv/gettext/{en,fr}/LC_MESSAGES/default.po`
- Test: `test/teacher_assistant_web/controllers/class_list_print_controller_test.exs`

**Interfaces:**
- Consumes: `official_header/1` (Task 2); `BulletinPrintHTML.tr/2` (public) for the class's language.
- Produces: route `GET /school/classes/:id/class-list/print` → `ClassListPrintController.roster/2`, mapped `{W.ClassListPrintController, :roster} => :core`. Access: `TeacherAssistantWeb.School.ClassShell.allowed?(scope, cg, :register)` (= `Discipline.can_manage_conduct?(scope) or Enrollment.class_manager?(scope, cg)`).

Page: portrait A4; `<.official_header>` with `template = ReportCards.template(scope, cg)`, `logo?: template.header.logo? and profile.logo_path` present; title « LISTE DE CLASSE »; line `cg.label — « Année scolaire » year.name — « Professeur principal » : name` (last part only when `cg.form_master` is set; load it); table N° · « Matricule » · « Noms et prénoms » · « Sexe » (M/F) · « Date et lieu de naissance » (`"%{date} à %{place}"`, either half alone when the other is missing, empty when both are) · « Red. » (« R » when `enrollment.repeater`); `thead` repeats on print (`display: table-header-group`); footer « Effectif : n — Garçons : g — Filles : f — Redoublants : r » and, right, the head's title (`template.header.head_title`, per language) + `ReportCards.head_name(scope)` with blank room; no signature/stamp image. Every label through `tr(template.language, fn -> gettext(...) end)`.

- [ ] **Step 1: Write the failing tests** (setup as `card_print_controller_test.exs`: `register_and_log_in_user`, class « 6e P », Awa Ngono F matricule M1 born 2010-03-12 in Yaoundé, repeater; Ben Ateba M with no matricule/birth data):
  - `"lists the class in roster order with identity columns and totals"` — body has « LISTE DE CLASSE », « 6e P », `"M1"`, `"12/03/2010 à Yaoundé"`; Awa's row before Ben's; « Effectif : 2 », « Garçons : 1 », « Filles : 1 », « Redoublants : 1 »; `refute body =~ "nil"`.
  - `"an empty class prints its header and zero totals"` — new class, « Effectif : 0 ».
  - `"the form master is named when set"` — set `form_master_user_id`, body has their display name and « Professeur principal ».
  - `"an anglophone class prints in English"` — class with `subsystem: :anglophone`; `assert ReportCards.template(scope, cg).language == :en`; body has "CLASS ROSTER", "Class size".
  - `"a conduct member may print it"` — `member_scope_fixture(scope, %{roles: [:conduct]})`, 200.
  - `"a teacher is sent away"` — `roles: [:teacher]`, `redirected_to == ~p"/school"`.
  - `"the roster is core"` — `Modules.module_for_controller(W.ClassListPrintController, :roster) == :core`.
- [ ] **Step 2: Run** `MIX_TEST_PARTITION=_prints mix test test/teacher_assistant_web/controllers/class_list_print_controller_test.exs` — Expected: FAIL (no route).
- [ ] **Step 3: Implement** controller action, view module, template, route, module map entry.
- [ ] **Step 4:** `mix gettext.extract --merge`; fill the new English msgstr, drop `fuzzy`.
- [ ] **Step 5: Run** the test file and `test/teacher_assistant_web/router_modules_test.exs` — Expected: PASS.
- [ ] **Step 6: Commit** `feat(class-list): printable official class roster`.

### Task 4: Working list (version B), school and teacher sides

**Files:**
- Modify: `class_list_print_controller.ex`, `class_list_print_html.ex`, router, modules, gettext files
- Create: `class_list_print_html/working.html.heex`
- Test: `class_list_print_controller_test.exs`

**Interfaces:**
- Produces: `GET /school/classes/:id/class-list/working/print` → `:working` (same access as `:roster`, `=> :core`); `GET /teacher/contexts/:id/class-list/print` → `:teacher` (`Curriculum.fetch_assigned_teaching_context(scope, id)` then `Enrollment.fetch_owned_class_group(scope, ctx.class_group_id)`; `=> :notes`, like `Teacher.RosterLive`).

Page: portrait A4, labels in the interface language (plain `gettext`); short header `school — class label — year`; line « Matière : ____ Enseignant : ____ », pre-filled with `ctx.subject` and the user's display name on `:teacher`; table N° · « Noms et prénoms » · « S » · 6 empty columns; footer « Effectif : n (G g / F f) ». One-page fit: a CSS class on `<body>` chosen from the count — `≤40` normal, `41–55` compact, `>55` dense — with row heights so 70 rows fit A4 (builder sets sizes; check in the browser at 70).

- [ ] **Step 1: Write the failing tests:**
  - `"the working list has six empty columns and blank subject line"` — `length(Regex.scan(~r/class="blank"/, row_html_of_awa)) == 6` (count `td.blank` in one row), « Matière ».
  - `"a teacher prints it for their own course, pre-filled"` — `school_teacher_fixture(scope, %{class_group: cg, subject: "Maths"})`, log in as that teacher, GET `/teacher/contexts/#{tc.id}/class-list/print` → 200, body has "Maths" and the teacher's display name.
  - `"a teacher can't print another teacher's course"` → redirect `/school`.
  - `"seventy students get the dense layout"` — 70 `add_student` calls, body has `class="dense"`.
  - module mapping asserts for `:working` (`:core`) and `:teacher` (`:notes`).
- [ ] **Step 2: Run** the file — Expected: FAIL.
- [ ] **Step 3: Implement** both actions, template, routes, module entries; gettext extract + fill.
- [ ] **Step 4: Run** the file + router modules test — Expected: PASS.
- [ ] **Step 5: Commit** `feat(class-list): working class list for staff and teachers`.

### Task 5: « Liste de classe » buttons

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex` (`<:actions>`), `register_live.ex` (`<:actions>`), `lib/teacher_assistant_web/live/teacher/roster_live.ex`
- Test: the three LiveViews' existing test files under `test/teacher_assistant_web/live/`

**Interfaces:**
- Consumes: the three routes of Tasks 3–4.

On ClassLive and RegisterLive: a `<details class="dropdown">` « Liste de classe ▾ » (id `class-list-menu`) with two `<a target="_blank">`: « Liste officielle » (id `class-list-roster`) and « Liste de travail » (id `class-list-working`); on RegisterLive only when `ClassShell.allowed?(scope, cg, :register)` (always true there). On RosterLive: one link `id="class-list-print"` « Imprimer la liste » to `/teacher/contexts/:id/class-list/print`.

- [ ] **Step 1: Write the failing tests** — `has_element?(view, "#class-list-roster[href='/school/classes/#{cg.id}/class-list/print']")` on ClassLive and RegisterLive (as a conduct member for RegisterLive); `has_element?(view, "#class-list-print")` on RosterLive and `refute has_element?(view, "#class-list-roster")` there.
- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement**; gettext extract + fill.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(class-list): print buttons on the class, register and roster pages`.

### Task 6: Every teacher's timetable

**Files:**
- Modify: `lib/teacher_assistant/timetabling.ex`, `timetable_print_controller.ex`, `timetable_print_html.ex`, `timetable_print_html/show.html.heex`, router, modules, `lib/teacher_assistant_web/live/school/timetable_editor_live.ex:396-412`, gettext files
- Test: `test/teacher_assistant/academics/timetables_reads_test.exs`, `timetable_print_controller_test.exs`, the editor's LiveView test

**Interfaces:**
- Consumes: Task 1's year filter (same filter here).
- Produces: `Timetabling.all_teacher_timetables(scope) :: [%{teacher: User.t(), grid: %{{day, period_id} => [slot_view]}}]` — one read of the current year's slots (load `[:room, class_group: :home_room, teaching_context: :teacher]`), grouped by teacher, each cell's views carrying `class_label` and sorted by it (as `teacher_timetable/2`), list sorted by `String.downcase(User.display_name(teacher))`; `[]` without a current year. Route `GET /school/timetable/teachers/print` → `TimetablePrintController.teachers/2`, `=> :emploi_du_temps`, access `Timetabling.can_edit_timetable?(scope)`.

The template renders a list of sheets: `class` and `me` pass one sheet, `teachers` one per teacher; each `<section class="sheet">` breaks the page after it (`break-after: page`, not after the last).

- [ ] **Step 1: Write the failing tests:**
  - domain: `"all_teacher_timetables lists teachers with lessons, by name"` — two teachers with slots (« Zoé » and « Alain ») and one without; result names in order `["Alain…", "Zoé…"]`, the slot-less teacher absent.
  - domain: a combined course across 6e A and 6e B taught by one teacher → that teacher's cell holds two views with `class_label`s "6e A", "6e B".
  - controller: `"prints one sheet per teacher"` — two `class="sheet"` sections, both names present; `"a teacher is sent away"` → `/school`; module mapping `:emploi_du_temps`.
  - controller: `"no timetable yet prints an empty page"` — no slots → 200, zero sheets, a « Aucun cours placé » line.
  - editor LiveView: `has_element?(view, "#print-teachers[href='/school/timetable/teachers/print']")`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** loader, action, template loop (update `class`/`me` to pass `sheets: [%{title:, grid:}]`), button « Emplois du temps des enseignants » (`target="_blank"`) next to `#print-timetable`; gettext.
- [ ] **Step 4: Run** the three test files + the existing timetable print tests — Expected: PASS.
- [ ] **Step 5: Commit** `feat(timetable): print every teacher's timetable at once`.

### Task 7: Emploi du temps général

**Files:**
- Modify: `timetabling.ex`, `timetable_print_controller.ex`, `timetable_print_html.ex`, router, modules, `timetable_editor_live.ex`, gettext files
- Create: `timetable_print_html/general.html.heex`
- Test: as Task 6

**Interfaces:**
- Produces: `Timetabling.school_timetable(scope) :: %{class_group_id => %{{day, period_id} => [slot_view]}}` — one read of the current year's slots, `slot_view` gaining `subject_code` (`teaching_context.catalog_subject.code` when present, else `teaching_context.subject`; load `teaching_context: [:teacher, :catalog_subject]`); `%{}` without a current year. Route `GET /school/timetable/general/print` → `:general`, `=> :emploi_du_temps`, access `can_edit_timetable?`.

Page: A3 landscape (`@page { size: A3 landscape }`); title « EMPLOI DU TEMPS GÉNÉRAL », school, year; rows = `Enrollment.list_class_groups(scope, year)`; header row 1 = each `calendar.lesson_days` day spanning its lesson periods, row 2 = period labels; `:break` periods are not columns; closed cells (`SchoolCalendar.open_cell?/3` false) shaded and empty; cell = `subject_code` (bold) over `teacher_name` (`text-overflow: ellipsis`, no name parsing); heavier left border on each day's first column; `thead` repeats on each printed page.

- [ ] **Step 1: Write the failing tests:**
  - domain: `"school_timetable groups the year's slots by class"` and the combined-course case (both class ids hold the lesson); a subject with `code: "MATH"` yields `subject_code == "MATH"`, one without yields its name.
  - controller: `"one row per class in level order with code and teacher"` — classes « 5e A » and « 6e A » created in that order; « 6e A » row before « 5e A »; cell shows "MATH" and the teacher's name; Saturday absent when the calendar has no Saturday lessons; teacher redirected; module mapping.
  - controller: `"a school with classes but no lessons prints empty rows"` → 200.
  - editor LiveView: `#print-general` link present.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** loader, action, template, button « Emploi du temps général »; gettext.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(timetable): print the school-wide timetable`.

### Task 8: Finish

- [ ] **Step 1:** `MIX_TEST_PARTITION=_prints mix precommit` (format rewrites in place; it does not gate on warnings — also run `mix compile --warnings-as-errors` and check no new warnings beyond the known `marks_live.ex:210` / `my_day_live.ex:293`). Expected: all tests pass.
- [ ] **Step 2:** Browser check on a second dev server (`PORT=4010 ELIXIR_ERL_OPTIONS="-live_debugger 'disabled?' true" mix phx.server` from the worktree, demo school « Lycée Bilingue d'Etoug-Ebé »): print preview of roster A (one class), working list B at the class's real size, all teachers' timetables, the general grid in A3 landscape. Fix what's broken; commit `fix(print): …`.
