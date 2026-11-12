# Paper roll call — design

Date: 2026-10-28 · Status: draft for approval

## Why

Many teachers in Cameroonian schools have no smartphone, or no data, so they cannot take
the roll call in the app for each lesson. Schools cope on paper: some keep a class
register (cahier d'appel), some print a list per class for the week, some have nothing.
Today the app only knows a roll call taken in the app, lesson by lesson, by the course's
teacher or a surveillant. Every lesson a teacher did on paper shows as a red « appel non
fait », the SG is alerted about it twice a day, and the absences never reach the
counters, the « absences à justifier » list or the bulletins.

The goal is to make paper the normal, supported path: the app prints the sheet, the
sheet comes back once a week, the surveillant types it in quickly, and nobody is
treated as late while the sheet is still in the classroom.

## Decisions taken with the user

- **Weekly rhythm.** Absences reach the app once a week; same-day entry is not needed.
- **The surveillant types the sheet in**, as a first step. Others may be allowed later.
- **Sheet layout: one A4 landscape page per class per week** (option A of the
  mockups), columns = every lesson of the class's timetable for the week, grouped by
  day, headed by the subject; one row per student; a « Visa » row where each teacher
  initials their own lesson's column.
- **Marks on paper:** « A » absent, « R » late.
- **Entry screen: the same grid as the paper** (option A): click a cell to cycle
  empty → A → R; one « appel fait » tick per lesson column, ticked when the visa is on
  the paper; « Enregistrer la semaine » saves the whole week at once.
- **The setting belongs to the class**, and it is **on by default**: paper is the rule,
  switching it off is the exception (a class whose teachers all use the app).
- **Teachers who have the app keep taking the roll call in it**, paper class or not.
  Those lessons show in green on the entry screen and are not overwritten.
- **Alerts in a paper class** (the alternative the user accepted):
  - During the week, a lesson not taken in the app shows as **« sur feuille · à
    saisir »** in neutral grey, not as a red « non fait ». Counters split the two, for
    example « 12 appels dans l'app · 30 sur feuille ».
  - « Relancer » stays available on every lesson.
  - **From the Monday after the lesson's week**, a lesson still neither taken in the
    app nor typed in from the sheet becomes a red « non fait », as today.
  - A class with paper switched off behaves exactly as today.
- **A lesson that never took place** (teacher absent, no visa): the entry screen offers
  « cours non assuré » for that column. It closes the lesson without recording anyone
  present or absent, so the week counts as entered.
- **Justification deadline: unchanged.** It still counts from the day of the absence.
  A justification can be recorded at any time anyway, so a paper absence that shows
  as overdue when it is typed in can still be justified.

## Goals

1. Print the weekly sheet for one class, and for every paper class at once.
2. Type a returned sheet in, a whole class-week on one screen, in a few minutes.
3. Paper lessons are not reported as missed before the sheet could come back, and are
   reported once it is overdue.
4. Absences entered from paper count everywhere an app roll call counts (absence
   hours, « à justifier », alerts, conduct, bulletins).

## Non-goals

- Same-day paper entry, scanning or photographing the sheet, OCR.
- SMS or USSD roll calls.
- Teacher-level « sans smartphone » flags (the class decides).
- Letting the class delegate or teachers type sheets in (later, if needed).
- Changing how an app roll call works for a teacher.

## Anti-goals (a failure even if it works)

- A paper school sees red alerts all week for lessons that were done on paper.
- Typing a sheet in silently overwrites a roll call a teacher took in the app.
- A lesson typed in from paper with nobody absent stays « non fait » (the visa must be
  enough to record « everyone present »).
- The printed sheet's student order differs from the entry screen's.

## What exists today (builds on it)

- `AttendanceEntry` (one row per enrollment, date and period; `status` present /
  absent / late / sent_home; `recorded_by_user_id`; `teaching_context_id`). A lesson's
  roll call is « done » when its entries exist.
- `RollCall` (`lib/teacher_assistant_web/live/school/roll_call.ex`) opens and records one
  lesson's roll call; the course's teacher or anyone who manages conduct may do it.
- `SchoolLife.school_day/3` and `roll_call_counts/1` build the day grid and the
  done / missed tally used by « Journée » (`/school/day`), the dashboard and the
  `MissedRollCalls` worker (twice a day, today only).
- « Relancer » (`SchoolLife.remind_roll_call/3`) notifies the slot's teacher.
- Timetable slots per class, the school calendar (closed days, holidays), print pages
  rendered as HTML (`BulletinPrintController` is the pattern).

## The design

### 1. Class setting « Appel sur feuille »

- A per-class boolean, **true by default** for existing and new classes.
- Changed by whoever manages conduct or the school (same rule as other Vie scolaire
  settings), on the class's Vie scolaire area.
- *My call:* Paramètres › Assiduité & discipline also gets « Appel sur feuille : toutes
  les classes / aucune » to set every class at once, for schools fully on paper or fully
  on the app.
- Switching it off affects the alert rule from then on; entries already made stay.

### 2. The printed sheet

- An HTML print page (A4 landscape, `@page` size), like the bulletin print.
- Header: school name, « Feuille d'appel · <classe> », « Semaine du lundi 2 au samedi 7
  novembre 2026 », the legend « A = absent · R = retard ».
- Rows: the class's students as enrolled when the sheet is printed (enrollments have no
  dates; *my call*), **same order and numbers as the class list and the entry screen**,
  then empty rows for students who join during the week (*my call: 3*).
- Columns: per school day of the week, one column per timetable lesson of that class,
  headed by the subject's short name (rotated if needed); day groups in a header row.
  Closed days and holidays print as a greyed band with their label. Combined courses
  appear like any lesson.
- Bottom row « Visa » with one cell per lesson.
- One page per class; « Imprimer toutes les classes » prints every paper class, one
  page each.
- Who: anyone who manages conduct. Default week: the current one (from Saturday on,
  *my call:* the next one); any other week can be chosen.

### 3. The entry screen

- For one class and one week, reached from the class's Vie scolaire area and from
  « Journée ». Only for people who manage conduct.
- Same grid, order and columns as the sheet. Each cell cycles empty → A → R on click
  (keyboard works too: *my call*, arrows to move, A / R / space to set).
- Header row « Appel fait » with one tick per lesson column, and per column the choice
  « cours non assuré » (user's decision) for a lesson that did not take place: it
  stores that the lesson was not held (new data: a per class, date and period record),
  writes no attendance, and makes the lesson count as closed (neither « sur feuille »
  nor « non fait ») in every view, counter and notification. The normal one-lesson
  roll-call page gets nothing new (*my call*); un-marking it on the entry screen puts
  the lesson back.
- Students sent home for unpaid fees that day (`FeeControl.sent_home_ids`) show a
  locked « Renvoyé » cell and are recorded `:sent_home` when the column is saved, as
  the app's roll call already does (*my call*).
- Lessons already taken in the app: the column shows in green with its absences,
  read-only here, and its tick is set; *my call:* a link opens that lesson's normal
  roll-call page for corrections.
- Saving (« Enregistrer la semaine ») records, for each ticked column not taken in the
  app: an entry per student (absent / late / present), `recorded_by_user_id` = the
  surveillant, the slot's `teaching_context_id`, all in one transaction. Late from
  paper has no minutes.
- An unticked column is not written, even if it has « A » cells (the screen says so
  before saving: *my call*); it stays « non fait » under the alert rule.
- Re-opening a week shows what was saved; editing and saving again updates those
  lessons (still never the ones taken in the app).
- The grid lists the class's current students, like today's roll call (which refuses
  anyone not in the roster). A student who joined mid-week appears; one who left or
  moved class does not (*my call*, since enrollments carry no dates; their marks
  before the move cannot be typed into the old class).

### 4. Alerts and counters

- Lesson state, per class, date and lesson: **done** (entries exist), **not held**
  (marked « cours non assuré »), **on paper** (neither, paper class, and today is
  before the Monday after that lesson's week), **missed** (otherwise, as today).
- « Journée », the dashboard counters and the class views show « sur feuille · à
  saisir » in neutral grey and split the tally (« 12 appels dans l'app · 30 sur
  feuille »). « Relancer » stays on every lesson that isn't done.
- `MissedRollCalls` keeps reporting today's missed lessons; paper lessons are never in
  it on the day itself.
- The teacher's own views follow the same states (« Ma journée »: `teacher_day`,
  `teacher_missed_this_week`, and the teacher facts in `spaces.ex`), so a teacher who
  uses the app does not see red for lessons done on paper (*my call*).
- Bulletin pre-publish checklist (`ReportCards.publish_checklist/4`): a **warning**, not
  a block, when the period still has paper lessons neither entered nor « non assuré »
  (*my call*), since a published bulletin freezes its absences.
- *My call:* on Monday morning, one notification to the SG / Proviseur lists the paper
  classes whose previous week still has lessons not entered (« Feuilles d'appel non
  saisies : 6e A, 4e B · semaine du 2 nov. »), linking to the entry screen; each
  further Monday repeats it while weeks stay unentered, up to the term's end.

## Left to the builder

- Data shape: where the class flag lives (`ClassGroup` attribute is the obvious place),
  whether the week-level save is a generic Ash action or a domain function, the
  migration (generated with `mix ash.codegen --dev`).
- Exact routes, page names and where the links sit, following the existing class tabs
  and Vie scolaire pages.
- Print CSS details (column widths, rotated headers, page breaks between classes).
- Whether the Monday notification is a new `NotificationKind` or reuses
  `:missed_roll_calls` with other params.
- Tests at the usual level (domain, LiveView, print controller), translations FR/EN
  (fill every new fuzzy entry), `mix precommit`.

## Amendment 2026-11-12 — the sheet is the school's week, not the class's timetable

Decided with the user after the first real sheets: the printed sheet and the entry
screen no longer follow the class's timetable.

- Days: every lesson day of the school calendar (the school's lesson days setting),
  whether or not the class has a lesson that day. Holidays keep their greyed band.
- Columns: under each day, one column per lesson period of the school's bell schedule
  (breaks are not printed); with Wednesday afternoon off, Wednesday stops at noon. The
  header is the period's hours, « 07:30–08:20 » rotated, the period's name as tooltip.
  No subject, no teacher: the sheet works whatever the timetable says and whoever took
  the hour.
- Entry screen: the same days × periods grid, so the surveillant finds a paper column at
  the same place. A cell where the class has no timetable lesson is greyed and locked,
  because a recorded entry needs a subject and teacher behind it. Letting the
  surveillant pick a subject for such a column (paper's « Autre cours maintenant ») is a
  later increment.
- Students, blank rows, the « Visa » row, the week picker and « toutes les classes »
  are unchanged.
