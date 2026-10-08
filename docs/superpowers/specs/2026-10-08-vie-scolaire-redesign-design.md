# Vie scolaire redesign (day, absences, conduct, sanctions, timetable editor) — design

Date: 2026-10-08
Status: implemented on feat/vie-scolaire-redesign (2026-10-08)
Mockup: claude.ai/design project « Tableau », file `Vie scolaire.dc.html`
(screens `#day`, `#absences`, `#conduct`, `#sanctions`, `#timetable`).
Follows: `2026-10-08-eleves-redesign-design.md` (cycle 2).

## Goal

Bring the five existing Vie scolaire LiveViews to the mockup, and add the four
pieces of data the mockup needs. Every screen keeps its route
(`/school/day`, `/school/absences`, `/school/conduct`, `/school/sanctions`,
`/school/timetable`) and its rights (`Discipline.can_manage_conduct?`, or
`Timetabling.can_edit_timetable?` for the editor). Desktop and 390 px; FR + EN.

Out of scope: « sans enseignant » timetable cells (a slot requires a teacher),
a parent-convocation record, splitting a subject between two teachers.

## Decisions

| Question | Decision |
|---|---|
| New data in this cycle | Roll-call reminder, Conseil de discipline, consigne in hours, « Confier à un autre enseignant » — all four |
| « Confier à un autre enseignant » | The new teacher takes the class's whole subject (the teaching context), every slot of it |
| Teacher service | Existing `SchoolMembership.statutory_hours`, else `SchoolProfile.statutory_hours` — no new field |
| « Convoquer les parents » | No button; names in the banner link to the student page (parents' phones are there) |
| Day grid orientation | Classes stay rows (20–40 classes), mockup styling |
| Day page « Absences à justifier » card | Removed, as in the mockup; justification lives on `/school/absences` |

## 1. Data and domain

### 1.1 Roll-call reminder (« Relancer »)

- New resource `RollCallReminder` (Attendance domain): `timetable_slot_id`,
  `date`, `sent_by_user_id`, workspace
  multitenancy like its neighbours; identity `once_a_day` on
  `(timetable_slot_id, date)`. Modelled on `EntryReminder`.
- `NotificationKind` gains `:roll_call_reminder`, with FR/EN text
  « Appel non fait : %{class} · %{time} · %{subject} ».
- `SchoolLife.remind_roll_call(scope, slot_id, date)`: creates the reminder,
  then `Notifications.deliver(scope, :roll_call_reminder, [teacher], payload,
  "/school/today")` — the teacher's « Ma journée », where that roll call is
  taken — both in one transaction. A second call for the same slot and day
  returns `{:error, :already_reminded}` (checked first; the unique index
  backs it).
- `Attendance.reminded_slot_ids(scope, date)`: the day page marks the slots
  already reminded (kept out of `school_day/3`, which the rail badge also calls).
- Policy: create allowed when `Discipline.can_manage_conduct?` holds (same
  check as the page).

### 1.2 Conseil de discipline

- `SanctionType` gains `:conseil_discipline`; `SanctionPoints` gains
  `conseil_discipline: "0"` (the council's decision is recorded as its own
  sanction). Labels FR « Conseil de discipline » / EN « Disciplinary council ».
- It flows everywhere the type list is used (sanctions form, settings points,
  conduct sheet), like `:exclusion_definitive`. A school that already saved its
  own « types utilisés » list turns it on in Paramètres › Assiduité & discipline.

### 1.3 Consigne in hours

- `SanctionEntry.duration_hours` (integer, 1–40, nullable).
- Validation in the resource: `:consigne` requires `duration_hours` (on create;
  the generic update does not accept hours);
  `:exclusion_temporaire` keeps requiring `duration_days`; every other type
  clears both. Existing consigne rows without hours stay valid and display with
  no duration.
- Display: « Consigne · 2 h », « Exclusion temporaire · 3 j ».

### 1.4 Confier à un autre enseignant

- `Timetabling.reassign_candidates(scope, teaching_context)` returns
  `[%{user: user, load: hours, service: hours}]`:
  - active teacher members of the school except the current teacher;
  - free in **every** existing slot of that teaching context
    (`TimetableConflicts.busy?/5`);
  - `load + tc.weekly_hours <= service`, where load is the sum of
    `weekly_hours` of their teaching contexts this year and service is
    `statutory_hours` of the membership, else of the school profile (never nil,
    default 18);
  - sorted: teachers who already teach that subject (catalog subject) in the
    school first, then by lowest load, then by name.
- `TimetableConflicts.suggestions/4` stays pure; the editor appends up to 2
  candidates as fixes `{:reassign, user_id}`, shown
  « Confier à Jean Kana · 16 h / 18 h ».
- Applying calls the existing `Curriculum` teacher change on the teaching
  context (all its slots follow, since a slot's teacher comes from it). Rights:
  `can_edit_timetable?` and the existing assignment policy.

### 1.5 Migrations

Via `mix ash.codegen --dev` only: the `roll_call_reminders` table and
`sanction_entries.duration_hours`. Enum values need none.

## 2. Screens

### 2.1 Aujourd'hui (`/school/day`)

- Header: eyebrow « date · HH:MM », H1 « Aujourd'hui », outline button
  « Absences à justifier · N » → `/school/absences` (N = current séquence).
- KPIs: « Appels faits X / Y » (sub « N non faits à HH:MM »), « Absents »
  (distinct students absent on at least one slot today), « Retards » (count of
  today's `:late` entries, new query), « À justifier » (current séquence).
- Grid « Appels par créneau · nombre d'absents »: rows = classes, columns =
  periods. Cell: absent count (0 green, ≥ 3 red); red « ? » roll call not
  taken; « … » in progress; « · » no course. Legend as the mockup.
- Card « Appels non faits »: « 6e B · 08:25 · Anglais » / « Brice Tabi ·
  créneau terminé », button « Relancer » → « Relancé ✓ » (flash
  « Rappel envoyé à Brice Tabi. »).
- Card « Sanctions récentes »: 3 latest, link « Toutes → » `/school/sanctions`.
- The inline absences card is removed.

### 2.2 Absences (`/school/absences`)

- Header: eyebrow « Vie scolaire · Séquence N », subtitle
  « N absences à justifier · M élèves au-delà du seuil de X h ».
- Red banner « Absences répétées. » when M > 0: « Nom (classe · 12 h), … »,
  each name a link to the student page. No button.
- Controls: segmented « À justifier / Justifiées / Toutes » (`?filter=`),
  class select (`?class=`), period select « Séquence N / Cette semaine /
  Aujourd'hui » (`?period=`), all in the URL.
- Rows: name · class; when (« Lun 6 oct. · 07:30 – 10:15 » or « journée »);
  hours (red ≥ 3, yellow below); main contact « Nom · phone » or « Aucun
  contact » (loaded via `primary_guardian_link`).
- « Justifier » expands reason chips inline + « Précision (facultatif) »
  passed as `note` to `justify_day/5`. Justified rows show
  « Justifiée · Maladie ». Side panel removed. Label « Convocation » becomes
  « Convocation officielle ».
- Footer « N sur M affichées » + « Afficher tout » (`?all=1`); default 50.

### 2.3 Conduite (`/school/conduct`)

- Header: subtitle « Note de conduite /20 par séquence, portée sur le
  bulletin. », primary « Appliquer les suggestions ».
- Classes as segmented tabs (select when > 8 classes and at phone width);
  séquence select kept; rule line generated from `SchoolLifeRules`
  (« 20 − 0,5 pt / h injustifiée − 0,25 pt / retard − sanctions »), linking to
  the school-life settings.
- Table: Élève / Abs. injust. / Sanctions / Suggestion / Note /20. Row click
  keeps the breakdown (with lates). « Valider la classe » still saves.

### 2.4 Sanctions (`/school/sanctions`)

- Subtitle « N familles à prévenir » (distinct students with a sanction to
  notify).
- Two columns on desktop: sticky « Nouvelle sanction » form left, list right;
  stacked on phones.
- Form: student search as today; type chips; Date; « Durée (heures) » for a
  consigne, « Durée (jours) » for an exclusion temporaire; Motif; type note
  (conseil de discipline: « Le conseil de discipline est convoqué par le chef
  d'établissement ; la décision sera ajoutée après la séance. », otherwise
  « Les parents sont à prévenir… »); « Enregistrer la sanction ».
- List: Élève (class below) / Type (duration) / « JJ/MM · motif » / Parents:
  inline « Marquer notifiés » or « Notifiés le JJ/MM ». Filters, pagination
  and the side panel (contacts, delete) kept.

### 2.5 Emploi du temps (`/school/timetable`)

- Header action « Imprimer la classe »; hint « Cliquez sur une case pour
  placer ou déplacer un cours. ».
- Cells: « Fermé » on closed cells, « + Libre » on free ones.
- Side panel: chips « Maths 4/5 »; clash text with day and time
  (« Marie Ekotto enseigne déjà en 3e A le mardi à 08:25. »); fixes move,
  swap, and the new « Confier à … » (§1.4). « Heures par matière » unchanged.

## 3. Testing

- Domain: reminder create + `:already_reminded` + notification delivered;
  `duration_hours` validation per type; `conseil_discipline` points default;
  `reassign_candidates` (busy teacher excluded, over-service excluded, sort
  order); reassign moves every slot.
- LiveView: each screen's new behaviour (Relancer, banner links, filters in the
  URL, inline justify with note, apply suggestions, hours/days field switch,
  inline notify, « Confier à »). Existing tests updated where wording or
  layout changed.
- Browser pass at desktop and 390 px on the demo school.
