# Roll call outside the timetable — design (2026-11-12)

Source: the conversation of 2026-11-11/12 (candidate 9 of the audit follow-ups
spec). Two situations share one mechanism: a teacher who teaches one of their
classes at another period than the timetable says (a swap with a colleague, a
make-up hour), and a teacher who has assignments but no timetable at all. Today
the roll-call page would accept both (`RollCall.open/5` falls back to the
teacher's own assignment when the period has no slot), but nothing leads there:
Ma journée lists timetable lessons only, and a colleague's slot at that period
wins over the teacher's assignment and refuses them.

## Intent

A teacher in front of a class can always take the roll call for it, whatever the
timetable says, with their own subject on the record. The surveillant's day stays
honest: the lesson appears at the time it was really held, and the hour the teacher
vacated reads « non assuré · déplacé à … » instead of « appel non fait ».

## Goals, non-goals, anti-goals

Goals:

- « Autre cours maintenant » on Ma journée: pick one of my classes (a combined
  course counts as one), a period of today or of an earlier day of the current week,
  take the roll call as usual, recorded under **my** teaching context.
- Optionally name the own lesson it replaces (« À la place de ») so that slot is
  marked not held with the motive « déplacé à <period> », in the same save.
- A teacher with no timetable sees their classes on Ma journée with « Faire
  l'appel » instead of an empty day.
- Moved lessons show on Ma journée, on the surveillant's day view and in the
  roll-call counts; vacated slots show their motive.

Non-goals (user, 2026-11-12):

- A replacement module where the censeur assigns substitutes in advance.
- Moving a lesson to another **day**: the « À la place de » list offers the
  teacher's own lessons of the same day only. A roll call on an earlier day of the
  week is allowed (forgotten entry), without a vacated slot.
- Touching a colleague's slot from a teacher's phone: each teacher marks only
  their own lessons; the colleague uses the same button for theirs.
- A « 2e heure » offer or a prefill for a moved lesson (both come from the class's
  timetable slots, which a moved lesson does not have).

Anti-goals:

- A moved roll call that silently overwrites a roll call a colleague really took at
  that period: the open is refused with the name of who took it.
- A vacated slot marked not held by someone who does not teach it.
- A moved lesson at a period that has not started yet.

## Behaviour

### 1. « Autre cours maintenant » on Ma journée

- A button `#other-lesson` « Autre cours maintenant » in the page header, shown to
  every member who teaches (the page already requires at least one unit). It opens
  a panel `#other-lesson-form` with: the class (`#other-class`, a `<select>` of my
  courses from `TeacherCourses.list/2`, a combined course as one entry), the period
  (`#other-period`, today's lesson periods — `kind == :lesson`, open that weekday
  per `SchoolCalendar.open_cell?` — the one under way preselected, periods that have
  not started yet disabled), and the day (`#other-date`, today preselected, the
  earlier lesson days of the current week offered; on an earlier day every lesson
  period is enabled). « Continuer » patches to
  `/school/today?class=<id>&period=<id>&date=<iso>` (`class` is a class group id or
  `course:<combined course id>`).
- With those params the roll panel opens as today's `?slot=` does, with the eyebrow
  « Cours déplacé · <period label> » (« Appel · <date> » on an earlier day) and one
  extra control above the footer: `#moved-from` « À la place de », a `<select>` of my
  own timetable lessons of **that day on the same class or course** that are neither
  done, nor already marked not held, nor the lesson itself (label « 14:00 ·
  Mathématiques »), with « Aucun (cours supplémentaire) » as the first option.
  Default: the first such lesson if any, else « Aucun ». Same class only, on
  purpose: the lesson that moved is this course at another hour; the other side of a
  swap (my own slot that a colleague is teaching) needs no marking from me — it
  shows as « pris par » (§3).
- « Valider l'appel » writes the entries for the chosen class(es) and period and,
  when a lesson is named, marks it not held with `moved_to_period_id` = the chosen
  period, in one transaction; failure anywhere rolls everything back. Then the
  page reloads the day: the moved lesson appears in the timeline at its period with
  the tag « Déplacé », the vacated one reads « Non assuré · déplacé à 10:00 ».
- Refusals, shown as the panel's error line: a roll call already taken at that
  class and period by **another** teaching context → « Un appel a déjà été fait pour
  6e A à 10:00 (Mme Ngo Bassa, Anglais). » (the teacher's own earlier roll call at
  that key reopens for editing as usual); a period not started yet → « Ce créneau n'a
  pas encore commencé. »; a school not verified → the existing message.

### 2. A teacher without timetable

- When `@lessons == []` and the day is not off, Ma journée shows, instead of
  « Pas de cours aujourd'hui », a section `#my-classes` « Mes classes » listing my
  courses with a « Faire l'appel » button each, which opens the same panel with the
  class preselected and the current period chosen. The day's moved roll calls then
  appear in the timeline as in §1, so the page is no longer empty after the first
  one.
- The roll panel, the « À faire » block and « Appels manquants cette semaine » no
  longer sit inside the `@lessons != []` branch (they are lifted so a roll opened
  from `#my-classes` renders).

### 3. What the surveillant and the counts see

**What « moved » means.** The roll-call entries of a `(class, period, day)` carry
a teaching context. A lesson is *moved* when those entries exist and their context
is **not** the context of the class's timetable slot at that period (either there
is no slot, or the slot belongs to another teacher). Entries with the slot's
context, or with no context (a conduct manager's roll call), are the slot's own
roll call, as today.

- **The held lesson.** `Attendance.school_day/3` and `teacher_day/4` build one cell
  per moved lesson: status `:done`, `moved?: true`, teacher and subject from the
  entries' context, `slot_id: nil`. A class with no slot that weekday gets a row
  when it has one. `/school/day` draws it with a small « ↷ » before the figure and
  the title « Cours déplacé · Mathématiques · Mme Mvondo ». When the period also has
  a slot (a swap), the grid cell shows the held lesson and its title adds « · à la
  place de Anglais · Mme Ngo Bassa ».
- **The slot under a moved lesson.** For the slot's owner that lesson is not done:
  its cell gets the new status `:covered` (« Pris par Mme Mvondo ») — neither done,
  nor missed, nor reminded, and it stays in the owner's « À la place de » list, so
  the colleague who teaches that class later the same day can mark their own slot
  « déplacé à 14:00 » in turn. A slot both covered and marked déplacé reads
  « Non assuré · déplacé à 14:00 » for its owner (not held wins over covered; done
  of the owner's own context wins over both, as `PaperRollCall.state/5` does today).
- **The vacated slot** keeps the `:not_held` look with the title « Non assuré ·
  déplacé à 10:00 » on `/school/day`, on the owner's Ma journée and timetable.
- `roll_call_counts/1`: moved cells count in `done` and `expected`; `:covered` and
  `:not_held` slots stay out of every figure. « Relancer » ignores moved and covered
  cells (someone took that roll call).
- A moved lesson is never « missed » (it exists only once taken); the week's missed
  list and the « Appel à faire » badge therefore never count it, and never count a
  covered or vacated slot either.
- The paper sheet (`RollSheetLive`) and the printed sheet stay timetable-shaped: a
  moved lesson is not a column there; the vacated slot shows « Non assuré » as the
  surveillant's own marking does today.
- `MissedRollCalls` and `RollCallReminder` are unchanged: a vacated slot that the
  teacher did not name stays a missed roll call, on purpose (the teacher may well
  teach both).

### 4. Rules

- Period rule: on today, a moved roll call needs `period.start_time <= now`; on an
  earlier day of the week any lesson period. Dates before the current week's Monday
  are refused (the surveillant's sheet owns the past).
- One roll call per class, period and day stays the invariant
  (`AttendanceEntry :unique_mark`). Opening a roll call — from « Autre cours » **or
  from my own timetable slot** — at a key whose entries carry another teaching
  context than mine is refused with the owner's name (anti-goal 1); at a key whose
  entries are mine or have no context, it reopens them. A conduct manager is never
  refused (the surveillant corrects); their save keeps the entries' context.
- The vacated slot can only be my own: a slot of the day whose teaching context's
  `teacher_user_id` is me (or a member context of my combined course). Marking it
  is refused otherwise, at the policy level, not only in the UI.
- Undo: the teacher may delete their own « déplacé » marking the same day (the
  « Non assuré · déplacé » row in Ma journée offers « Annuler »); conduct managers
  keep today's rights through the paper sheet.

## Where

- **`LessonNotHeld`** gains `moved_to_period_id` (nullable `belongs_to :moved_to_period, Period`)
  and a new `create :mark_moved` accepting `class_group_id, period_id, date,
  moved_to_period_id` with a validation `OwnsSlot` (the class has a slot at
  `period_id` on that weekday whose context belongs to the actor, or to the actor's
  combined course) and `moved_to_period_id != period_id`; policy for `:mark_moved`:
  member and (`OwnsSlot` passes — the validation doubles as the check, builder's
  call on expressing it as a `SimpleCheck`). `:destroy` additionally allowed to the
  actor who marked it when `date == today`. Migration via `mix ash.codegen --dev`.
  The existing `:mark` (surveillant, no motive) is unchanged.
- **`Attendance`**: `moved_lessons/3` (scope, date, teacher_user_id | nil) — the
  entries of the day grouped by `(class_group_id, period_id, teaching_context_id)`
  whose `(class, period)` has no slot that weekday; `record_moved_period/6` (scope,
  class or course, period, date, marks, `moved_from: period | nil`) — one
  transaction around `record_period`/`record_combined_period` and the
  `:mark_moved`; `taken_by_other_context?/4`. `record_combined_period/5` takes the
  course's member contexts when a member class has no slot at that period (today it
  takes the slot's context, nil off-timetable, and refuses the teacher).
- **`SchoolLife`**: `done_roll_calls/4` groups entries by `(class, period, date,
  teaching_context_id)`; a slot's cell is `:done` only for entries with its own
  context or none, `:covered` for entries of another context; moved cells are
  appended (`cell` shape + `moved?: true`, `slot_id: nil`, `covers:` the slot's
  teacher and subject when there is one); `not_held` carries the motive so
  `cell_title` can say « déplacé à … »; `PaperRollCall.state/5` gains `:covered`
  (own done > not held > covered > the clock); `roll_call_counts/1` counts moved
  cells and ignores covered ones. `LessonGroups` keeps `moved?` on the group;
  `status_tag` renders « Déplacé », « Pris par %{name} » and « Non assuré · déplacé
  à %{time} ».
- **`RollCall`**: `open/5` gains `context: :mine` (resolve my assignment on the
  class — or my combined course — regardless of the slot) and `moved_from:` options,
  and refuses every open (slot or moved) at a key held by another context unless the
  actor manages conduct; `record/2` routes to `record_moved_period/6` when
  `roll.moved?`. `authorized?/2` unchanged.
- **`MyDayLive`**: the header button, `#other-lesson-form`, the `class/period/date`
  params, `#moved-from` in the panel, `#my-classes`, « Annuler » on a « déplacé »
  row; the `@lessons != []` branch lifted.
- **`DayLive`**: moved cells and the two titles.
- Module gating: all of it is `:appel`, as the pages are today.

## Tests

- `school_life_test`: a moved roll call appears in the teacher's day and the
  school's day at its period with `moved?: true`, counts as done, and the vacated
  slot reads not held with `moved_to`; a teacher with no slot gets their moved
  lesson only; a moved lesson is never in « missed this week »; **the swap**: A
  records 6e A at B's 10:00 slot, B records at A's 14:00 slot (marked déplacé) —
  B's 10:00 is `:covered` then `:not_held` once B names it, A's 14:00 reads
  « déplacé à 10:00 » for A while the grid cell shows B's held lesson, counts are
  2 done / 0 missed, B's covered slot is offered in B's « À la place de ».
- `attendance_test`: `record_moved_period/6` writes entries under the teacher's own
  context at a period where a colleague's slot exists, marks the vacated slot in the
  same transaction, rolls both back when the marking is refused; a key already taken
  by another context is refused with the owner, from « Autre cours » and from the
  slot owner's own open alike, and not for a conduct manager; a combined course
  off-timetable writes every member class.
- `lesson_not_held` policy tests: `:mark_moved` by the slot's teacher ok, by another
  teacher forbidden, by a conduct manager ok; destroy by the marker same day ok, next
  day forbidden.
- `school_life_live_test` (Ma journée): the button, the panel's period list (future
  disabled), the « À la place de » default on the same class, the saved lesson in
  the timeline with « Déplacé » and the vacated one « Non assuré · déplacé à … »,
  « Annuler »; a teacher without timetable sees `#my-classes` and takes a roll call;
  the refusal when a colleague's roll call exists at that key. `/school/day`: the
  moved cell and both titles; « Relancer » skips it.
- `missed_roll_calls_test`: a vacated slot marked « déplacé » is not reminded; one
  not marked still is.

## Calls made in this document

- « Moved » is decided by the entries' teaching context, not by the absence of a
  slot, so a swap between two teachers works at both hours; the colleague's slot
  under a moved lesson reads « Pris par … » (`:covered`) and is never counted done
  or missed for them.
- « À la place de » offers lessons of the same class only; the other side of a swap
  is covered automatically.
- The slot owner's own open is refused too when another context holds the key;
  only a conduct manager may override.

- Same-day « À la place de » only; earlier days of the week allowed for the roll
  call itself, nothing before Monday.
- The colleague's slot is never touched; both teachers act for their own lessons.
- Entries at a key owned by another context refuse the open (no silent overwrite);
  the teacher's own entries reopen.
- Moved lessons are invisible on the paper sheet by design.
- The surveillant's reminders keep treating an unnamed vacated slot as missed.
