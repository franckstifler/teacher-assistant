# UX refonte — design (2026-11-03)

Source: the Design canvas « Teacher Assistant — refonte UX »
(https://claude.ai/code/artifact/478f70b2-899f-4396-a076-d63756e26af8), 34 artboards.
The user asked to apply every suggested fix. This document records how each
artboard maps onto the code, what changes, and the calls made where the
mockup is silent, contradicts the domain, or needs something the app lacks.

## Intent

The canvas states one principle per row:

- Saisie des notes — one page centred on the student list.
- Espace enseignant — every screen leads to the next action.
- Direction — 41 classes, 371 students: group, prioritise, act in bulk.
- Scolarité / vie scolaire — pick a class by level, act in bulk.

So the recurring moves are: lists instead of card grids, classes grouped by
level, filter pills with counts, one primary action per row, bulk actions
with a selection bar, a « what's left to do » block at the top, and on phones
a back-arrow task header with a sticky bottom action.

## Global rules (calls made)

1. **Keep what the mockup leaves out** when the app needs it: Résultats/Élèves
   tabs, locked/upcoming banners, late minutes, `:sent_home`, `:missed`/`:not_held`
   lesson states, invitations, search fields, conflict panel, print menus,
   « Traitées » tab, deductions, durations on sanctions, Matières/Affectations
   settings, verification/reject for unverified schools. Mockups show one state;
   the code keeps the others.
2. **Domain wins over sample data.** Mentions come from the school's grading
   rules, assessment types from the school's list, conduct rule text from
   `school_life_rules`, level labels from `SchoolTemplates`, distribution keeps
   5 bands. Bilingual labels keep `tr(@lang)`.
3. **Every new string goes through Gettext** (FR + EN), no fuzzy entries left.
4. **Phone numbers stay in full** (no masking): staff and the operator use them
   to call.
5. **Late is minutes, absence flags name earlier periods** (mockup slips ignored).

### Deferred — not built in this refonte

Each needs something the app does not have, or carries security / domain
weight beyond a UI change:

- **SMS sending** (« Envoyer le SMS », « Prévenir la famille (SMS) », « Envoyer
  par SMS »): no SMS channel. Rows keep « Marquer notifié » plus a `tel:` link.
- **Printing access codes** (Membres, Dashboard): temporary passwords are hashed,
  so this means bulk password resets. Security decision for the user.
- **Automatic class-council planner** (SCouncils): needs duration/room on
  `ClassCouncil`, a scheduler, and conflict rules (one chair, shared teachers).
  The councils page gets list polish only.
- **School-wide parent-contacts import** and **« Demander aux PP »**: no
  school-wide import, no request mechanism. The Élèves banner links to the
  per-class import and to the students without contacts.
- **Period-wide paper entry** (« Reporter les feuilles du cours 4 »): paper
  roll call is a weekly per-class sheet; the Surveillant day links to it.
- **Editing the timetable from the teacher or room view**: those views are
  read-only; editing stays in the class view.
- **« Petits effectifs » filter**: no minimum-size rule exists. Dropped.
- **Import tracking on the operator overview**: imports are not recorded.

## Shared pieces (built with their first consumer)

In `lib/teacher_assistant_web/components/ui_components.ex` unless noted:

- `<.filter_pills>` — patch links with counts, `aria-pressed`.
- `<.class_picker>` — native select with optgroups by level (order from
  `SchoolTemplates.class_sort_key`), ‹ › stepper, optional suffix per option.
- `<.level_group>` header — « Niveau X · n classes · m élèves ».
- `<.progress_meter>` — count / total + bar.
- `<.bulk_bar>` — « N sélectionnés » + actions, sticky.
- `<.attention_card>` — amber « À compléter / À régler » block, one action per row.
- `<.stat_tile>` — label, mono value, sub-line, link.
- `<.task_header>` — phone back arrow + title + subtitle + trailing slot;
  `Layouts.app` gains `immersive` (no phone tab bar).
- `Dates.countdown/1` — « J-n », public (today private in DashboardLive).
- A combined-course grouping helper for lessons (by `combined_course_id`,
  merging consecutive periods) used by Ma journée and Mon emploi du temps.

## Batch 1 — Saisie des notes (`Teacher.MarksLive`, `/teacher/contexts/:id/marks`)

Phone (below `sm`):
- Task header: back to `/school/courses`; title « Matière · Niveau » with
  subtitle « Cours groupé · N classes · N élèves » opening the **course picker**
  sheet; « Séq. N ▾ » pill opening a séquence sheet. Phone tab bar hidden.
- Evaluation chips scrolling sideways (« label · /max », own « x/N » count, ✓ when
  complete) + dashed « + Nouvelle ». Per-assessment counts via a batch count.
- Combined course: class chips jumping to each class header.
- Competence + save state line; full competence form in a sheet.
- Rows as a list: number (restarting at 1 per class), name, mention/absence
  underneath, 72px mark box, ✓ once saved, next empty row highlighted; no Absent
  button (a / abs / abj typed).
- Sticky bottom bar: « x/N saisies », provisional average (red under 10),
  progress bar, CTA « Saisir les N notes manquantes » opening the **keypad**.
- **Keypad mode**: full-screen focus card (previous/next students dimmed,
  class · N°, « n restants dans <classe> », large mark, « / max », live mention),
  4×4 keypad 0–9 , ⌫ ABS ABJ ↑ Suivant. A colocated JS hook types locally;
  « Suivant » pushes the existing `save_mark` and moves on.
- **New evaluation** in a bottom sheet: type chips (the school's types), Nom +
  « Noté sur » side by side, name filled as soon as a type is picked, « Créer et
  commencer la saisie » then opens the keypad.

Desktop (`sm+`):
- Header: course + member classes in the breadcrumb, séquence tabs, deadline
  chip « Clôture dd/mm · J-n » replacing the open banner text.
- Evaluation cards with progress bars + dashed « Nouvelle évaluation » card.
- Toolbar row: competence inline + « Évaluation ⋯ » menu (rename / change max /
  delete; the update action already accepts label and max_score).
- Table: no Absent column, status column ✓/⚠, cell styles for ABS/ABJ/error/next.
- Side panel: « Tout est enregistré · hh:mm », « N note(s) à corriger (names) »,
  « Aller à la prochaine note vide ». ↑/↓ move between rows.

## Batch 2 — Espace enseignant

- **Ma journée** (`School.MyDayLive`): combined lessons grouped into one row
  with student count; « MAINTENANT » pill + solid outline; « Appel fait » tag;
  new « À faire » card (notes of the séquence: courses without evaluation, in
  progress, J-n). Desktop: horizontal now-card, left panel « Notes de la
  séquence N » with per-course progress and CTA. Roll call stays inline.
- **Mes cours** (`School.CoursesLive`): rows grouped by subject (link to marks,
  classes line, state pill, chevron) instead of cards with four buttons; filter
  pills Tous / Notes à saisir / Compétence; subtitle with deadline J-n. PP badge
  and coefficient kept as small meta.
- **Appel** (`roll_call.ex`, `attendance_live.ex`): task header « Appel · Matière ·
  Niveau » + mono line; class chips with counts and group summaries; Absent and
  Retard toggles (toggle off → present) instead of P/A/R; tinted rows; helper
  line; footer counts + « Valider l'appel ». Late minutes, sent-home, « Tous
  présents » kept.
- **Résultats** (`Teacher.MarksSummaryLive`, `teaching_nav.ex`): phone task
  header + underline tabs; séquence chips with lock state; three stats
  (Moyenne / Réussite / Écart); stacked distribution bar (5 bands); pass rate by
  sex on one line; ordinal ranks, marks < 10 red, Rang / A→Z sort. Combined
  courses aggregate member contexts.
- **Mon emploi du temps** (`School.MyTimetableLive`): phone day tabs with lesson
  counts, one day as cards with times, combined lessons merged, break rows;
  today: past dimmed, current outlined, roll-call chips. Fix the desktop grid
  marking combined lessons as conflicts.
- **Bulletins (teacher)** (`School.BulletinsLive` when the user cannot publish):
  trimester tabs, stepper (séquences locked → open J-n → conseils → publication),
  « Vos notes pour ce trimestre » per course; published classes below.
- **Corrections** (`School.CorrectionsLive`): phone form straight away under a
  task header; assessment card with « Changer »; tappable student list with
  current marks (all classes of a combined course); large « 8 → [12] »; sticky
  submit « Envoyer au censeur · Élève 8 → 12 »; « Mes demandes » as cards.

## Batch 3 — Direction

- **Tableau de bord** (`School.DashboardLive`, `Pilotage`): title « Tableau de
  bord », eyebrow with deadline; « Mise en place · N étapes » block (PP missing,
  subjects without teacher, accounts) shown whenever a count > 0; calls KPI
  shows paper state; to-do rows « N feuilles d'appel à reporter » and « N cours
  sans compétence »; entry bars grouped by level. Check the unassigned count.
- **Suivi de la saisie** (`School.SequenceTrackingLive`): séquence select; 4 KPI
  strip; teacher-first table (checkbox, subjects, courses, started bar,
  competences left, last entry) with Par enseignant / Par classe / Par matière;
  search; « Relancer la sélection · N » (bulk `remind_teacher`, keeps the daily
  guard).
- **Bulletins · état de préparation** (`School.BulletinsLive` without `class`):
  period select, blocker banner with counts, Toutes / Prêtes / Publiées, search,
  table by level (Notes %, Conduite x/y, PP, Conseil, État); a batched readiness
  read; « Publier les classes prêtes ». Clicking a class opens today's view.
- **Conseils** (`School.CouncilsLive`): grouped by level, list polish (planner
  deferred).
- **Frais** (`School.FeeSettingsLive`, `FeesOverviewLive`): three numbered steps
  (types → amounts → tranches); type chips with presets by school type (public:
  no scolarité); amounts one row per level with per-class override; overview
  shows the stepper before setup.
- **Surveillant · Aujourd'hui** (`School.DayLive`, phone): hero card for the
  current period; list of periods with progress and state. Desktop unchanged.

## Batch 4 — Classes, Élèves, Conduite, Emploi du temps, Membres

- **Classes**: table grouped by level (Classe · Élèves · PP · Matières · Ouvrir);
  filter pills Toutes / Sans PP / Matières à affecter; search placeholder;
  « Mode désignation » with an inline PP select per row and one « Enregistrer · N
  PP » (bulk `set_form_master` in a transaction); phone keeps a list.
- **Élèves**: subtitle; contacts banner (links to students without contact and
  to the class import); class select with optgroups; pills Redoublants / Sans
  photo (new read arguments); « + Ajouter » when no contact; outline buttons.
- **Conduite**: class picker by level with « · n élèves »; séquence select kept;
  only students with an incident shown as cards (incident line, suggestion
  pre-filled), toggle « Seulement les incidents », footer for the others;
  « Valider X et passer à Y »; subtitle « n classes validées sur N ».
- **Emploi du temps (éditeur)**: Classe / Enseignant / Salle switcher (the last
  two read-only); class picker with « · n h à placer »; sidebar « Reste à placer »
  with drag into a free cell (hook) next to tap-to-place; subject-only cells,
  dashed empty cells.
- **Membres**: table with checkboxes (Membre + phone, Rôles, Service, Accès);
  role pills with counts + « Jamais connectés » (new `last_sign_in_at`);
  selection bar (print list; SMS and access codes deferred); wider container.

## Batch 5 — Paramètres, Sanctions, Corrections, Absences, Page de classe

- **Paramètres**: grouped list panels (one row per setting with state and
  chevron); pinned « À compléter · N »; search field; groups Calendrier / Notes et
  bulletins / Vie scolaire et organisation; « Nouvelle année » on the hub.
- **Sanctions**: pills « À notifier · N » / « Toutes · N »; list rows with state
  badge and one CTA (mark notified + call); form on the right; « Enregistrer ».
- **Validation des corrections**: count in title; full-width cards with « 7 → 17 »;
  Refuser… / Approuver; journal in `<details>` with counts; bulk « Approuver les N
  erreurs de saisie ».
- **Absences (phone)**: tabs À justifier / Au-delà du seuil / Justifiées; subtitle
  with threshold; reason buttons on each row (Maladie / Famille / Autre…); call
  button; badge = cumulative unjustified hours for the séquence (red over the
  threshold), with « cours a à b » for the day.
- **Page de classe**: new « Vue d'ensemble » tab first (`/school/classes/:id`),
  roster moves to `/students`; header with back + previous/next class, summary
  subtitle, « Imprimer… » menu, tab counts; « À régler » block (PP select,
  subjects without teacher, contacts); four glance cards (notes, calls,
  absences, timetable hours).

## Batch 6 — Console opérateur, carte scolaire

- **Vue d'ensemble** (`Admin.OverviewLive`): subtitle counts; joined KPI strip
  (« Membres actifs · 7 j » as x / total); table of every school (status,
  students, activated accounts, entries · 7 j, last activity); attention card
  styling. Système and Dernières actions stay below.
- **Un établissement** (`Admin.SchoolLive`): back link, status pill, meta line;
  two columns (members table with search, temp-password filter and « ⋯ » menu |
  modules with 30-day use, journal, danger card with a suspend dialog).
- **Carte** (`card_print_html/show.html.heex`): vertical flag stripe, round
  logo + one-line Republic line + school name, year chip, split title band,
  photo 20×25 mm with the stamp over its corner, 2-column fields, signature +
  head title, QR 13 mm with caption. Keep unique ID and labels via `tr`; no
  label under ~5 pt.
- **Planche A4**: hairline outlines, crop marks outside the grid, fixed sheet
  geometry, caption per sheet « classe · planche i / n ».

## Done means

Each batch merged into `feat/ux-refonte` with tests green and `mix precommit`
clean; the whole branch checked in the browser on phone and desktop widths
against the canvas before merging to main.
