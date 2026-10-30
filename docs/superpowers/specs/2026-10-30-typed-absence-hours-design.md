# Absence hours typed by hand — design

Date: 2026-10-30 · Status: draft for approval

## Why

The paper roll call (spec 2026-10-28) prints a weekly sheet per class and has the
surveillant type every « A » / « R » box back in. Some schools keep the same paper sheets
(or their own register) but will not type them box by box: at the end of a séquence or a
trimester someone counts each student's hours from the paper and writes one figure on the
bulletin. Today the app has no way to take that figure: every absence number on the
bulletin, the conseil de classe, the passage rule and the conduct suggestion comes from
lesson-by-lesson roll calls (`Attendance.class_conduct/3` over `AttendanceEntry`). A school
without the « Appel » module gets no absence row on the bulletin at all.

The goal: let a school type each student's absence hours directly, per séquence or per
trimester, and have that figure reach everything the bulletin depends on — **without ever
adding it to roll-call hours**, since teachers with a phone keep taking the roll call in
the app even in paper classes and the person counting includes those lessons.

## Decisions taken with the user

- **One source per class.** Each class chooses where its bulletin's absence hours come
  from: « calculées depuis l'appel » (today's behaviour) or « saisies à la main ». For a
  given student and period only one source ever reaches the card. Typed hours are never
  added to roll-call hours (that option was rejected because of double counting).
- **Rhythm per class:** typed « par séquence » or « par trimestre ».
- **One figure per student: the unjustified hours.** The person counting has already taken
  out excused hours. A « saisies à la main » class's card shows that figure and no
  justified row.
- **Who types:** whoever manages conduct (surveillant général, censeur…) for any class,
  and **the class's form master for their own class**.
- **Schools without the « Appel » module can type hours too.** There is nothing to
  compute from, so every class is « saisies à la main » and the source setting is hidden;
  only the rhythm is chosen.
- **What reads the typed figure:** bulletin, conseil de classe, passage (the year is the
  sum), and the séquence conduct suggestion when typed per séquence.
- **What does not:** day-to-day follow-up — alerts, « absences à justifier », Journée, the
  class register and student profile counters — keeps using the roll call, even in a
  « saisies à la main » class. *(My call, accepted with the rest.)*
- **Publishing:** the publish checklist warns when hours are missing; a published bulletin
  keeps the figures it was published with.

## Goals

1. A class can be switched to typed hours, per séquence or per trimester; a school-wide
   setting switches every class at once.
2. A form master or conduct manager types a whole class's hours for one séquence or
   trimester on one screen, in roll order, in a couple of minutes.
3. In a typed class, the bulletin, council, passage and conduct suggestion read only the
   typed figures; nothing is counted twice.
4. Schools without the roll-call module get an absence row on the bulletin from typed
   figures.

## Non-goals

- Typing justified hours, lates or per-subject absences by hand.
- Mixing sources inside one class (some students typed, some computed).
- Feeding typed hours into alerts, « à justifier », the SG's day views or the student's
  profile counters.
- Changing the paper roll-call sheet or its entry screen.

## Anti-goals (a failure even if it works)

- A student's hours are counted twice: once from app roll calls, once typed.
- A blank typed figure silently means « use the roll call » for that student.
- A school switches a class to typed hours and its already published bulletins change.
- A school without the « Appel » module now sees « 0 h » on every bulletin although it
  never typed anything.

## What exists today (builds on it)

- `Attendance.class_conduct/3` and `student_conduct/3`: `%{justified_hours,
  unjustified_hours, retards}` per enrollment for `{:sequence, s}`, `{:trimester, term}`
  or `{:annual, year}` (dates from `Organization.period_date_range/2`), via the pure
  `Academics.Conduct.totals/2`.
- Its readers that feed the bulletin and its decisions:
  - `ReportCards.live_view/3` → `conduct:` (and the published snapshot) → the print
    template `bulletin_print_html/show.html.heex` (rows « Absences non justifiées »,
    « Absences justifiées », « Retards ») via `BulletinPrintController`.
  - `Councils.passage_inputs/3` → `PassageRules` (`exclusion_absence_hours`).
  - `Discipline.conduct_sheet/3` → `ConductSuggestion.suggest/2` (per séquence).
  - Anything else on the bulletin/council path that calls `class_conduct` (the builder
    checks `ReportCards` council data and `Assessment` ~l.1100).
- Its readers for day-to-day follow-up, unchanged by this design: `RegisterLive`,
  `StudentLive`, `AbsencesLive`, `SchoolLife` alerts (`unjustified_hours/3`).
- `ReportCards.template/2` hides the `:absences` element when the school lacks the
  `:appel` module.
- `ReportCards.publish_checklist/4`, including `paper_check/3` (paper lessons not entered).
- `ClassGroup.paper_roll_call` with `:set_paper_roll_call` and
  `Attendance.set_paper_roll_call_all/3` (Paramètres › Assiduité & discipline) — the
  pattern for a per-class setting with a school-wide switch.
- `ConductMark` (enrollment × séquence, upsert `:set`, `YearOpen` validation, read for
  conduct role or form master) — the pattern for a per-student, per-period figure.

## The design

### 1. Class setting « Heures d'absence au bulletin »

- A per-class setting with three values (an `Ash.Type.Enum`, not a bare atom):
  « calculées depuis l'appel » (default, existing and new classes),
  « saisies à la main, par séquence », « saisies à la main, par trimestre ».
- Changed by whoever manages conduct or the school (same rule as « Appel sur feuille »),
  on the class's Vie scolaire area next to « Appel sur feuille ». The form master does not
  change it *(my call)*.
- Paramètres › Assiduité & discipline gets the same three-way choice « pour toutes les
  classes », like `set_paper_roll_call_all`.
- **Without the « Appel » module:** the effective source is always « à la main »; the
  setting offers only the two rhythms, and a stored « calculées depuis l'appel » acts as
  « par séquence » *(my call)*. The setting must be reachable without the module (the
  builder places it where the Discipline / Vie scolaire settings are visible).
- So that turning the module on later does not flip a class back to computed hours,
  without the module the setting only ever saves an explicit typed value, and saving the
  typing screen for a class still stored as « calculées depuis l'appel » also stores
  « par séquence » for it *(my call)*.
- Switching changes what the next unpublished bulletin reads; published snapshots keep
  their figures.

### 2. Stored figure

- One record per student and period: enrollment, **either** a séquence **or** a trimester,
  `hours` (decimal ≥ 0), `recorded_by_user_id`. Unique per (enrollment, séquence) and per
  (enrollment, trimester). Upsert like `ConductMark.set`; clearing an input deletes the
  record. `YearOpen` validation as for conduct marks.
- Policies: read and write for the conduct role, and for the form master of the
  enrollment's class (`enrollment.class_group.form_master_user_id == actor.id`).
- Records are kept when a class changes rhythm or source; only the reading rule below
  decides what counts.

### 3. Reading rule (the one place sources are chosen)

A single domain function — e.g. `Attendance.bulletin_conduct(scope, cg, period)` — returns
the same shape as `class_conduct/3`, plus which source it used, and every bulletin-path
reader in « What exists today » switches to it:

- **Class on « calculées depuis l'appel »** (and the module on): exactly `class_conduct/3`.
- **Class typed by hand:**
  - `unjustified_hours` = the typed figure; `justified_hours` = 0; `retards` = 0. App roll
    calls do not contribute anything, lates included *(my call: one source per class, so
    the conduct suggestion's late deduction also drops out)*.
  - The class's **current rhythm** decides which records count *(my call)*:
    - « par séquence »: séquence = its record; trimester = sum of its séquences'
      records. Trimester records are ignored.
    - « par trimestre »: trimester = its record if there is one, else the sum of its
      séquences' records (left from before a rhythm switch); séquence = nothing (0, no
      absence deduction in the conduct suggestion).
  - Year: the sum of the trimesters computed as above.
  - A student with no record for the period counts 0 on the card (the checklist warns,
    § 6).
- Each enrollment's map carries the source (`:roll_call` / `:typed`) so the snapshot and the
  print template know which rows to show. Snapshots published before this key read it
  with `Map.get(…, :source, :roll_call)`.

### 4. Typing screen « Heures d'absence »

- On the class's Vie scolaire area (and wherever the form master reaches their class),
  shown only for a typed class. Picker: the class's séquences, or its trimesters,
  following the rhythm; default the current one.
- The class in roll order (same order and numbers as the class list); one hours input per
  student (decimals allowed, e.g. 2.5); beside it, when the « Appel » module is on, a grey
  hint « dans l'app : 2 h » — that period's `class_conduct` unjustified hours — so whoever
  counts can check they included the lessons taken on a phone.
- One « Enregistrer » for the whole class, in one transaction; negative or non-numeric
  input refused per row.
- Per trimester, if séquence records exist and no trimester record, the inputs are
  pre-filled with their sum *(my call)*.
- **A class switched to typed hours mid-year (user's decision):** for a period with no
  typed record yet, the inputs are pre-filled with that period's roll-call unjustified
  hours (the « dans l'app » figure), clearly marked as pre-filled and not saved until
  « Enregistrer ». Until then the period counts as missing (checklist warning, § 6) and 0
  on the card, so nothing is ever read from the roll call in a typed class. This keeps an
  earlier trimester's roll-call hours in the year total once the screen is confirmed.
- When the period's bulletin is already published: the screen says « Bulletin publié :
  les heures imprimées ne changent qu'après retrait et nouvelle publication » *(my call:
  figures stay editable, like conduct marks; the snapshot protects the published card)*.

### 5. Bulletin print

- A typed class (per the snapshot's or live view's source): only the « Absences non
  justifiées » row; no « Absences justifiées », no « Retards » row.
- Séquence bulletins (live drafts only; séquences are never published) of a class typed
  « par trimestre » show no absence row at all, since there is no séquence figure
  *(my call)*.
- `ReportCards.template/2`: without the « Appel » module, the `:absences` element is shown
  when the class has at least one typed record in the period, hidden otherwise (no « 0 h »
  for a school that never typed anything).

### 6. Publish checklist

- Typed class: a **warning** (not a block) « Heures d'absence non saisies : N élèves »
  when students lack a figure for the period (trimester: neither a trimester record nor a
  record for every séquence; year: any trimester missing).
- Typed class: no `paper_check` warning, since paper lessons no longer reach its card
  *(my call)*.

### 7. Conduct suggestion and council

- `Discipline.conduct_sheet/3` reads the séquence figure through the reading rule: typed
  per séquence → the typed hours; typed per trimester → no séquence record, so 0 hours
  and no absence deduction (the user accepted this trade-off).
- Councils and passage read the year figure through the reading rule; the
  `exclusion_absence_hours` rule applies to typed hours unchanged.

## Left to the builder

- Resource and attribute names, which Ash domain owns the record (`Attendance` like
  `AttendanceEntry`, or `Discipline` like `ConductMark`), whether « either séquence or
  trimester » is one resource with a check constraint or two; the migration via
  `mix ash.codegen --dev`.
- The exact list of `class_conduct/3` call sites on the bulletin path (confirm each).
- Route and link placement for the typing screen, following the class tabs.
- Tests at the usual level (reading rule as pure/domain tests incl. rhythm switch and no
  double counting, policies incl. form master, LiveView screen, print rows, checklist,
  no-module school), FR msgids with EN translations (fill every new fuzzy entry),
  `mix precommit`.
