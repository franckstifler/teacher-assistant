# Class lists and school timetable prints — design

Date: 2026-10-31. Status: design approved in conversation, not built.

## Why

An audit of what the app can hand out on paper (2026-10-30) found three gaps a
Cameroonian secondary school hits in its first weeks of the year:

1. **No « liste de classe ».** The most-used paper in a school (docs/domain/05,
   *liste de classe* = roster, *effectif* = headcount). The only class list the
   app prints today is the weekly roll sheet, which is a form to fill, not a roster.
2. **The censeur can't print the timetables of all teachers.** Each teacher can print
   their own (« Mon emploi du temps »), but at the start of the year many teachers
   have not signed in yet; the censeur hands the timetables out on paper at the
   first staff meeting.
3. **No « emploi du temps général ».** The one sheet with the whole school's week,
   pinned on the censeur's office wall.

Spreadsheet (Excel/CSV) exports were considered and **set aside by the user**: "we'll
discuss it when we need it". Room timetables were also considered and dropped.

## Goals

- A class list in two versions — the official roster (A) and a working list with
  empty columns (B) — for any class.
- One click that prints every teacher's timetable, one page each.
- One click that prints the « emploi du temps général », one row per class.

## Non-goals

- Excel, CSV or any downloadable data file.
- Room timetables (per-room printouts).
- A one-row-per-teacher school grid (shown as option B in the mockups; the user
  chose one row per class).
- Server-generated PDFs. Like every printout in the app, these are HTML print pages;
  « Enregistrer en PDF » from the browser's print dialog is the PDF path.
- Choosing columns, the number of empty columns, or the sort order on screen.

## Anti-goals (would make it a failure even if it works)

- A list whose numbering disagrees with the roll sheet or the bulletins for the same
  class: N° 12 must be the same pupil everywhere.
- Students who left the class appearing on the roster.
- A working list for a class of 60–70 that spills onto a second page.
- A teacher reaching the roster (A) — birth dates and places are register data — or
  any class's list for a class they don't teach.

## Existing pieces to build on

- Print pages are Phoenix controllers rendering a standalone HTML page
  (`put_layout(false)`, `put_root_layout(false)`), with an « Imprimer » button calling
  `window.print()`, under `plug TeacherAssistantWeb.Plug.SchoolAccess`. Examples:
  `CardPrintController`, `RollSheetPrintController`, `TimetablePrintController`.
- **Roster:** `Enrollment.list_roster(scope, class_group)` → `[%{student, enrollment}]`,
  current enrolments only, sorted by `String.downcase(student.full_name)` — the same
  order the roll sheet and the ID cards use. Student has `full_name`, `sex`,
  `matricule`, `birth_date`, `birth_place`; enrollment has `repeater`.
- **Official header:** `ReportCards.template(scope, class_group)` gives
  `template.header` and `template.language` (the class's sub-system, or bilingual);
  `BulletinTemplate.official_lines/2`, `school_lines`, the logo route and the
  head's title/name are what the bulletin and the ID card already render
  (FR left, EN right, logo between).
- **Timetables:** `Timetabling.teacher_timetable(scope, user)` (cell → list of slot
  views with `class_label`, `subject`), `Timetabling.class_timetable(scope, cg).slots`
  (cell → slot view with `subject`, `teacher_name`), `Timetabling.can_edit_timetable?/1`,
  `Attendance.school_calendar/1` (`lesson_days`) and `Attendance.list_periods/1`.
  `TimetablePrintController` + `timetable_print_html/show.html.heex` already render one
  timetable (modes `:class` and `:me`).
- **Class order:** `Enrollment.list_class_groups(scope, year)` sorts by
  `level_rank`, then `label` (6e → Tle).

## 1. Class list

### Where and who

- **School side:** a « Liste de classe » action offering both versions, on the
  class page (`/school/classes/:id`, the Élèves tab) **and** on the class's
  register tab (`/school/classes/:id/register`, Vie scolaire). The class page only
  admits `Enrollment.class_manager?/2` (admin axis, form master); conduct-only users
  (SG, surveillants) never reach it and land on the register tab instead, so the
  action must live there too. The print route admits exactly the register tab's rule:
  `Discipline.can_manage_conduct?(scope) or Enrollment.class_manager?(scope, cg)`
  (`ClassShell.allowed?(scope, cg, :register)`). *(Designer's call after the builder
  check: the earlier draft named only the class page, which conduct users can't open.)*
- **Teacher side:** on a teacher's course roster (`/teacher/contexts/:id/roster`),
  a « Liste de classe » link printing **version B only**, for that course's class,
  with the subject and the teacher's name pre-filled in the top line. A teacher never
  gets version A.

### A. Official roster (« Liste de classe »)

- Portrait A4.
- Official header as on the bulletin, in the class's language (bilingual header for
  a bilingual school).
- Title « LISTE DE CLASSE », then one line: class label — « Année scolaire » year —
  « Professeur principal : » form master's name (line part omitted when none).
- Columns: N° · Matricule · Noms et prénoms · Sexe (M/F) · Né(e) le … à … · Red.
  (« R » for repeaters, empty otherwise). Missing matricule, birth date or place
  print as an empty cell, never as "nil" or a dash invented by us.
- Footer: « Effectif : n — Garçons : g — Filles : f — Redoublants : r », and on
  the right the head's title (as on the bulletin: « Le Proviseur », « Le Directeur »…)
  with room for the signature and stamp. The printed signature/stamp images are
  **not** placed here (it's not a certified document).
- A long class may run onto a second page; the column header repeats.

### B. Working list (« Liste de classe » — version de travail)

- Portrait A4, **always one page** up to 70 students (row height and font shrink
  as the class grows, as the bulletin's one-page fit does).
- Short header: school name, class label, year.
- Top line: « Matière : ________ Enseignant : ________ », blanks, or pre-filled from
  the teacher side.
- Columns: N° · Noms et prénoms · S (M/F) · **6 empty columns** with blank headers.
- Footer: « Effectif : n (G g / F f) ».

### Language

*(Designer's call after the builder check.)*

- **A (official roster)** follows the bulletin's rule: every label — title, column
  headings, footer, « Professeur principal » — is printed in the class's language
  (`template.language`) through the same `tr/2` / `Gettext.with_locale` mechanism the
  bulletin and the ID card use, whatever the user's interface language. A bilingual
  school gets both languages on the sheet, as on its bulletins.
- **B (working list)** is a working paper, not an official one: its labels follow the
  user's interface language (plain `gettext`).

### Numbering and who is listed

Both versions list the class's current enrolments (`list_roster`), numbered 1..n in
that order. No other filter, no other sort.

## 2. Every teacher's timetable

- A « Imprimer les emplois du temps des enseignants » action on the censeur's
  timetable page (`/school/timetable`), visible only when
  `Timetabling.can_edit_timetable?/1`; the route refuses everyone else (redirect, as
  the other print controllers do).
- One A4 page per teacher, each starting on a new sheet, identical in layout to what
  `/school/timetable/me/print` prints for that teacher today (days across from the
  school calendar's lesson days, periods down, class + subject in each cell; a cell
  with two classes — combined course or a saved clash — shows both).
- Teachers: every user with at least one slot in the current year, ordered by
  display name. Teachers with no slot are left out.
- **Current year only — fix the existing print too.** `Timetabling.teacher_timetable/2`
  reads `TimetableSlot :for_workspace_teacher`, which filters on the teacher alone,
  not the year: once a new year starts, last year's lessons land in the same cells
  (periods are school-wide). Add the current-year filter there
  (`teaching_context.academic_year_id == current year`, as `school_slots/1` does), so
  the bulk print, `/school/timetable/me/print` and « Mon emploi du temps » all show the
  current year only and stay identical. *(Designer's call after the builder check;
  it changes existing behaviour, deliberately, and needs a test with slots in two
  years.)*

## 3. Emploi du temps général

- An « Imprimer l'emploi du temps général » action next to the one above, same
  visibility and refusal rules.
- A3 landscape.
- Title « EMPLOI DU TEMPS GÉNÉRAL », school name and year.
- One row per class of the current year, in `list_class_groups` order.
- Columns: one per period of each lesson day (`school_calendar.lesson_days` ×
  `list_periods`), grouped under the day's name, with a heavier rule between days.
  A school without Saturday lessons has no Saturday columns.
- Cell: the subject code (`Subject.code` when set, else the subject name, cut to fit)
  on top, the teacher's short name under it. Empty cell = the class is free.
- A combined course appears in the row of each class it covers.
- More classes than fit: the table continues on the next page with the day/period
  header repeated.

## Decided by the user

- Both class list versions (A and B).
- No spreadsheets for now; no room timetables.
- Teacher timetables printed all at once, plus the school grid with one row per class.
- Every guess played back in the conversation was accepted ("looks ok"): alphabetical
  numbering shared with the roll sheet, current enrolments only, ~6 empty columns,
  print pages (no file download), buttons on the censeur's timetable page, days and
  periods from the school calendar, classes ordered 6e → Tle, short teacher names.

## Left to the builder

- Route names and controller split (a new `ClassListPrintController`; the two
  school-wide timetable prints can extend `TimetablePrintController`).
- Exact type sizes and the shrink rule that keeps B on one page.
- How the teacher's short name is derived for the grid cells (e.g. family name in
  capitals + initial) as long as it fits a cell and stays recognisable.
- How the « Liste de classe » action is presented on the class page (two links or
  one menu).
- French and English strings (Gettext), as everywhere else; fill the English
  msgstr and unflag fuzzy entries.
