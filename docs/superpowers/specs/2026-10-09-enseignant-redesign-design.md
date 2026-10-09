# Enseignant redesign (my day, courses, marks, results, timetable, corrections) — design

Date: 2026-10-09
Status: approved in conversation, awaiting written-spec review
Mockup: claude.ai/design project « Tableau », file `Espace enseignant.dc.html`
(screens `#today`, `#courses`, `#marks`, `#results`, `#timetable`, `#corrections`).
Follows: `2026-10-08-vie-scolaire-redesign-design.md` (cycle 3).

## Goal

Bring the six teacher screens to the mockup. Every screen keeps its route and its
rights: `/school/today`, `/school/classes/:id/attendance/:period_id`,
`/school/courses`, `/teacher/contexts/:id/marks`, `/teacher/contexts/:id/marks/summary`,
`/school/timetable/me`, `/school/corrections` (`:index`, `:new`). Desktop and
390 px; FR + EN.

Out of scope (deferred): offline mode (roll call and marks kept on the phone,
« Synchronisé » indicator, « Simuler : hors connexion »), the global top-bar
search, an explanation text on correction requests.

## Decisions

| Question | Decision |
|---|---|
| Offline mode | Deferred to its own cycle |
| Marks saving | Save on blur, one mark at a time; the « Enregistrer les notes » button goes away |
| Correction explanation field | Not added |
| Censeur note on a decision | Added: `MarkCorrection.decision_note`, optional, on accept and refuse |
| Correction motives | Form offers the mockup's four; the two old values stay valid (history) but are no longer offered |
| Current mark in the student select | Shown (« Nom — note actuelle 08 ») |
| Results distribution | 5-band histogram added; mention counts, girls/boys and per-student table kept |
| « N h par semaine · service attendu : M h » | N = the teacher's load as the « Confier à » editor computes it (sum of `weekly_hours` of their teaching contexts, a combined course counted once); M = `SchoolMembership.statutory_hours`, else `SchoolProfile.statutory_hours` |

## 1. Data and domain

### 1.1 Decision note

- `MarkCorrection` gains `decision_note` (string, nullable, trimmed, max 500).
- The approve and refuse actions (`Assessment.approve_correction/2`,
  `Assessment.refuse_correction/2` and the underlying Ash actions) accept an
  optional `decision_note` argument stored on the row. Policies unchanged.

### 1.2 Motives

- `MarkCorrectionMotive` values become
  `[:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul, :copie_mal_corrigee, :reclamation_eleve]`.
  Labels: Erreur de saisie, Copie retrouvée, Rattrapage, Erreur de calcul (new
  or relabelled), the last two keep their labels.
- `MarkCorrectionMotive.offered/0` returns the first four, in that order; the
  request form uses it. Existing rows are not migrated.

### 1.3 Read helpers (no new data)

- Course card facts: student count per class, coefficient from the coefficient
  grid for (level, serie, subject), form master = `ClassGroup.form_master_user_id`,
  séquence progress from `Academics.EntryProgress` for the current séquence.
  Loaded in bulk for all the teacher's courses (no per-card query).
- Teacher load: extract the load computation shared by `Timetabling.reassign_candidates/3`
  into one function (e.g. `Curriculum.teacher_load/2`) used by both the editor and
  « Mon emploi du temps »; service via the existing `services`/`school_hours` fallback.
- Results histogram: pure function bucketing student séquence averages into
  `0–5, 5–10, 10–12, 12–15, 15–20` (lower bound inclusive, 20 in the last band),
  scaled to /20.

### 1.4 Migrations

One migration, generated with `mix ash.codegen --dev`, final name chosen at the end
(`decision_note` column). The enum change needs no migration (stored as text).

## 2. Screens

### 2.1 Ma journée (`/school/today`) and the roll-call panel

- Header: eyebrow « <jour date> · Séquence N », title « Ma journée », subtitle
  « N cours aujourd'hui · N appel(s) à faire maintenant ».
- Left column: « Mes créneaux du jour » (time, class · subject, meta line with room or
  « N présents · N absents », status pill Fait / Maintenant / À venir / Non fait) and
  « Appels manquants cette semaine » (count, each row with « Faire l'appel »). Same data
  as today.
- Right (spans two columns on desktop, below on phone): the `RollCall.roll_panel`,
  restyled — eyebrow « En cours · HH:MM – HH:MM », title « Appel · class · subject »,
  « Tous présents » button (resets every status to present and clears late minutes),
  count chips présents / absents / retards, one row per student with a
  Présent / Absent / Retard segmented control (late keeps its minutes input), footer
  with the summary and « Valider l'appel » (or « Modifier l'appel » once saved, with
  « Appel envoyé à HH:MM »).
- `/school/classes/:id/attendance/:period_id` uses the same restyled panel.

### 2.2 Mes cours (`/school/courses`)

- Header: eyebrow « Enseignement · YYYY–YYYY », title « Mes cours », subtitle
  « N cours · N élèves · Séquence N ouverte jusqu'au <deadline> » (séquence part
  omitted when none is open).
- One card per course (solo or combined): class name (combined: class badges), subject ·
  N élèves · coef. N, PP badge when the teacher is form master of the class, « Notes
  Séq. N » progress (done / total, bar green at 100 %, amber above 0, red at 0), four
  buttons Notes (primary), Appel, Résultats, Élèves. Appel keeps today's behaviour
  (today's period, else the attendance page).

### 2.3 Saisie des notes (`/teacher/contexts/:id/marks`)

- Header: eyebrow « Notes · <subject> », title « Saisie des notes », save state at the
  right: « Enregistré · HH:MM » (green) or « Erreur : N note(s) à corriger » (amber).
- Toolbar: course tabs (the teacher's courses, linking to each course's marks page),
  séquence segmented tabs (« Séquence N · verrouillée / ouverte »), then the existing
  assessment select and « nouvelle évaluation » form.
- Banners: locked (« Séquence N verrouillée depuis le … » + « Demander une correction → »
  to `/school/corrections/new?assessment=`), open (« Saisie ouverte jusqu'au … (J-N).
  Chaque note est enregistrée dès que vous quittez la case. »).
- Table: N°, Élève, « <assessment> · /max » input, Absent toggle, Appréciation.
  - Blur saves that one mark (`phx-blur` with the row's enrollment id); value parsed by
    `Academics.MarkEntry.parse` (comma or point; `a`/`abs`, `abj` still accepted).
  - Invalid value (not a number, out of 0–max): the cell stays as typed with a red
    border and « Note entre 0 et <max> » in the appreciation cell; nothing saved.
  - Absent toggle sets status `:absent` (score cleared) or back to empty; row dims.
  - Scores under 10/20 shown in red; appreciation from the school scale
    (`Marks.mention`).
  - Locked séquence: inputs and toggles disabled.
- Colocated hook `.MarksGrid`: Enter moves focus to the next row's input (which blurs
  and saves the current one); « a » in an empty input marks absent.
- Sticky side panel (below the table on phone): « class · Séquence N », done / total
  with bar, « Moyenne provisoire », « N note(s) à saisir avant le … »; then a
  « Raccourcis » card. Combined courses keep their per-class grouping; the side panel
  shows the totals over all classes.

### 2.4 Résultats (`/teacher/contexts/:id/marks/summary`)

- Header: eyebrow « Résultats · Séquence N », title « <subject> · <class> », subtitle
  « N élèves · N notes », « Retour à la saisie » button; séquence select kept.
- KPI cards: Moyenne, ≥ 10/20 (green), Plus forte, Plus faible (red).
- « Répartition des notes »: 5 bars with the count above and the band below, bars under
  10 red, others green, height relative to the largest band.
- Below, unchanged in content: mention counts, girls/boys pass rate, students without
  marks warning, per-student table.

### 2.5 Mon emploi du temps (`/school/timetable/me`)

- Header: eyebrow « Semaine type », title « Mon emploi du temps », subtitle
  « N h par semaine · service attendu : M h » (subtitle without the service part when
  neither membership nor school has one), « Imprimer » button (existing print route).
- Grid in mockup style: time column + lesson days, class + subject in tinted cells,
  « Fermé » cells, break rows kept, « Faire l'appel » link kept for today's slots.

### 2.6 Corrections de notes (`/school/corrections`, `/school/corrections/new`)

- Header: eyebrow « Démarches · notes verrouillées », title « Corrections de notes »,
  lead « Une note verrouillée ne change qu'après validation du censeur. Tout est
  tracé. », « + Nouvelle demande » button.
- `:new` renders the form panel open; `:index` shows it only after « + Nouvelle
  demande » (patches to `/new`). `?assessment=` still preselects.
- Form: Évaluation, Élève (« Nom — note actuelle 08 » / « absent » / « — »), Nouvelle
  note, Motif (the four offered motives), « Envoyer la demande », live hint
  « 08 → 13 · Le bulletin n'est recalculé qu'après validation. ».
- On send: flash « Demande envoyée à <censeur name> (censeur). » when one Censeur
  exists, else « Demande envoyée au censeur. »; form closes (patch to `:index`).
- List: Date, Élève, Classe, Avant → après, Statut pill (En attente / Acceptée /
  Refusée) with a line under it: « Envoyée au censeur » for pending, « Par <name> le
  <date> » plus « · <decision note> » when decided.
- Review page (`/school/corrections/review`): an optional « Note pour l'enseignant »
  textarea on the decision card, sent with Accepter / Refuser.

## 3. Testing

- Domain: `decision_note` stored on approve and refuse; `offered/0`; old motives still
  load and label; teacher load function shared by editor and timetable (existing
  editor tests stay green); histogram buckets incl. edges 0, 5, 10, 20.
- LiveView:
  - Ma journée: « Tous présents » resets an absent and a late student; « Valider
    l'appel » saves; existing roll-call tests adapted.
  - Mes cours: coefficient, student count, PP badge, progress figures on a card.
  - Saisie: blur saves a valid mark (persisted, « Enregistré »); blur with « 25 »
    shows the error and saves nothing; Absent toggle sets status; locked séquence has
    disabled inputs and the correction link; course tabs link to sibling courses;
    combined course still saves per class.
  - Résultats: histogram counts for a known set of averages.
  - Mon emploi du temps: hours header with membership service, school fallback, none.
  - Corrections: `:index` hides and `:new` shows the form; current mark in the student
    option; only four motives offered; decision note shown in the teacher list after
    the Censeur refuses with a note.
- Gettext: new strings extracted and translated, no fuzzy entries left.
