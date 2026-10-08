# Classes & class page redesign — design

Date: 2026-10-08
Status: approved in conversation, awaiting spec review
Mockup: claude.ai/design project « Tableau », file `Classes et eleves.dc.html`
(screens `#classes` and `#class`).

## Goal

Bring `/school/classes` and the class page in line with the « Tableau »
mockup: classes shown as cards grouped by cycle, and one class page with tabs
instead of a page plus four separate sub-pages reached by buttons.

Out of scope (later cycles): the Frais tab (bursar features stay deferred,
`docs/audits/2026-09-23-school-focus/README.md` §2), the import screen,
`/school/students`, the student page.

## Decisions

| Question | Decision |
|---|---|
| Tabs architecture | Shared shell (breadcrumb, header, tab bar) over the existing LiveViews; each tab keeps its route |
| Capacity | Optional per-class `max_size`; falls back to the school's `max_class_size`; warns, never blocks |
| Cycle | Derived from the level, no stored field |
| Frais tab | Not shown this cycle |

## 1. Data

### `ClassGroup.max_size`

- `:integer`, `allow_nil? true`, `public? true`, constraints `min: 1, max: 200`
  (same as `SchoolProfile.max_class_size`).
- Accepted by the class create and update actions.
- Migration through `mix ash.codegen --dev`.

`Enrollment.capacity/2` returns `max: cg.max_size || profile.max_class_size`.
It gains `near?: is_integer(max) and not over? and count >= ceil(max * 0.9)`.
Every caller keeps working (same keys plus one).

### Cycle

`SchoolTemplates.cycle/2` — `cycle(level, subsystem)` returns:

- `:first` — `6ème`…`3ème`, `1ère Année`…`4ème Année` (francophone)
- `:second` — `2nde`, `1ère`, `Terminale` (francophone)
- `:anglophone` — every class with `subsystem: :anglophone`
- `:other` — any level not listed (free-text levels)

The anglophone group holds Form 1…Upper Sixth together. The mockup's chips are
Toutes / 1er cycle / 2nd cycle / Anglophone. An « Autres » group appears only
when a class falls in `:other`.

### Unassigned subjects

`Academics.unassigned_subjects(scope, cg)` returns the subjects that have a
row in the coefficient grid for the class's subsystem × level × série (falling
back to the blank-série row, the same rule as `grid_coefficient`) and no
`TeachingContext` in the class. It is used for the class card (« 2 matières
sans enseignant ») and the Enseignements tab. When no grid row exists for the
level, the list is empty (we never guess).

The classes page loads these counts for all classes in one query. It must not
run one query per class.

## 2. Classes page (`/school/classes`)

Header: eyebrow « Établissement », title « Classes », subtitle « N classes ·
M élèves ». Actions (admins only, i.e. `can_manage_classes?`): « Nouvelle
classe » (primary). The mockup's « Importer une liste d'élèves » button is not
added here: import stays reachable from the class page.

Toolbar: cycle chips (Toutes / 1er cycle / 2nd cycle / Anglophone, only the
cycles present), a text filter (matches label and level, case- and
accent-insensitive), and a legend (« À compléter », « Presque pleine »).
Filtering is client-side state on the LiveView (`phx-change`), no reload.

Groups, in order 1er cycle, 2nd cycle, Anglophone, Autres. Each group has a
heading and « N classes · M élèves ». Inside, cards sorted by the existing
`class_sort_key/1`.

Card (a link to the class page):

- label, and a tag: série when present, otherwise the level
- « Effectif n / max » with a bar; bar colour: warning when `near?`, error
  when `over?`; no bar when no max is known
- « PP : name » or « PP : à désigner »
- « N matières sans enseignant » in the error tone, or « N matières
  affectées » muted
- the card's left edge carries the « À compléter » marker when unassigned
  subjects > 0

Delete moves off the list: it goes in the class page header's « Gérer ▾ »
menu (admins), keeping today's `destroy` rules and confirmation.

Empty filter result: « Aucune classe ne correspond à ce filtre. » Empty
school: the existing empty state.

### « Nouvelle classe » drawer

Same drawer pattern as the Members page (always in the DOM, opened with JS).
Fields:

1. Sous-système — chips Francophone / Anglophone (default from the school
   profile).
2. Niveau — chips from `SchoolTemplates.levels_for(school_type, subsystem)`;
   « Autre… » reveals a text input (today's free-text level).
3. Série — chips from the school's series, only for levels that take one
   (today's `serie` datalist source); « Aucune ».
4. Suffixe — prefilled with the next free suffix
   (`SchoolTemplates.next_class_label/3` today); the hint says which labels
   already exist at that level.
5. Effectif maximum — optional, placeholder shows the school's value; hint
   « Alerte au-delà, sans bloquer ».
6. Professeur principal — optional select of active members.
7. Aperçu — the resulting label, in large type, live. If the label already
   exists this year: « Une classe porte déjà ce nom » and the submit is
   disabled.

Submit « Créer la classe 6ème A » creates the class and navigates to it.
The mockup's « Préparer les enseignements depuis la grille » checkbox is not
built (no such feature today).

The label is level + série + suffix, joined like `suggest_label/2` does today.
The user can no longer type a free label; the suffix is the only free part.

## 3. Class page shell

New function component `TeacherAssistantWeb.School.ClassShell.class_shell/1`
in `lib/teacher_assistant_web/live/school/class_shell.ex`:

```heex
<.class_shell scope={@scope} cg={@cg} tab={:students} capacity={@capacity}>
  <:actions>…page-specific buttons…</:actions>
  …tab body…
</.class_shell>
```

It renders inside `<Layouts.app>` (each page keeps its own `Layouts.app`):

- breadcrumb « Classes / 6ème A » (link to `/school/classes`)
- title (label), chips: « Francophone · 1er cycle », « PP : name » (or « PP :
  à désigner »), « n / max élèves · k places » (or « +k au-delà » in warning)
- the `:actions` slot on the right
- a tab bar: `<nav role="tablist">` of `<.link navigate>` items, the current
  one `aria-current="page"`, daisyUI `tabs tabs-border`; the Élèves tab shows
  the headcount badge, Enseignements shows the unassigned count in the error
  tone when > 0
- horizontally scrollable on phones, no wrapping

### Tabs, routes, access

Visibility is decided by `ClassShell.visible_tabs(scope, cg)`, which calls the
same checks the pages' `mount/3` use today, moved into one place so page and
tab bar cannot disagree:

| Tab | Route | Visible / mount allowed when |
|---|---|---|
| Élèves | `/school/classes/:id` | `class_manager?` |
| Enseignements | `/school/classes/:id/teachings` (new) | `class_manager?` |
| Emploi du temps | `/school/classes/:id/timetable` | `class_manager?` |
| Cahier d'appel | `/school/classes/:id/register` | `can_manage_conduct?` or `class_manager?` |
| Discipline | `/school/classes/:id/discipline` | `can_manage_conduct?` or `class_manager?` |
| Résultats | `/school/classes/:id/results` | `ReportCards.access/2` ≠ `:none` |

Today `/school/classes/:id` refuses anyone who is not a class manager. It now
lets in anyone with at least one visible tab: a viewer who is not a class
manager lands on their first visible tab (`push_navigate`). Anyone with no
visible tab is refused exactly as today (same flash and redirect).

The timetable tab keeps today's behaviour for timetable editors: they are sent
to `/school/timetable?class=…` (the editor). The tab label stays the same for
them.

The surveillant général reaching a class from `/school/day` or a student page
now sees the class header and the Cahier d'appel / Discipline tabs. They no
longer see a bare page.

## 4. Élèves tab (`ClassLive`, `/school/classes/:id`)

Actions slot: « Bulletins » (link to the class bulletins, existing route),
« Importer une liste » (existing import route, admins), « Inscrire un
élève » (primary, admins and form master as today), « Gérer ▾ » (admins:
« Effectif maximum… » in a small form, « Supprimer la classe »). The PP is
chosen on the Enseignements tab only.

Toolbar: search (name or matricule, client-side), filter chips Tous / Filles /
Garçons / Redoublants, a summary « 27 F · 25 G · 2 redoublants ».

Table: N°, Élève (initials avatar, name linking to the student page, sex and a
« Redoublant » badge), Matricule, Né(e) le, Parent principal (primary contact
guardian's name and phone, « Aucun contact » in warning when none), and a
« Gérer ▾ » menu: Ouvrir la fiche · Transférer vers (other classes of the
same level first, then the rest) · Retirer de la classe… (confirmation).
Transfer and withdraw call the existing `Enrollment.transfer/3` and
`Enrollment.withdraw/2`. The primary guardians for the roster are loaded in
one query.

The roster shows every student (no « 12 sur 52 » paging).

### « Inscrire un élève » drawer

Mode switch: « Nouvel élève » / « Ancien élève (réinscription) ».

Nouvel élève:

- Nom et prénoms (required), Sexe (chips F / M, required), Date de naissance,
  Lieu de naissance, Matricule (optional), « Redoublant dans ce niveau ».
- Parent ou tuteur · recommandé: phone first. On a valid phone,
  `Enrollment.find_guardians_by_phone/2` runs; one match shows « Déjà
  enregistré : name (relationship de N élèves) — sera lié automatiquement. »
  and hides the name fields. Several matches: radio list to pick one. No
  match: Nom du parent + relation (Mère / Père / Tuteur·rice / Autre).
- Footer: « n / max élèves après cet ajout : n+1 » (warning tone when it
  exceeds max), buttons « Inscrire et en ajouter un autre » and
  « Inscrire ».

Student, enrollment and guardian link are written in one transaction: the
`:enroll_new` action gains an optional `guardian` map argument, either
`%{guardian_id: id}` or `%{full_name:, phone:, relationship:}`. The action
creates or links the guardian as primary contact inside its existing
transaction, with the same authorization as `Enrollment.add_guardian/3` /
`link_guardian/3`. A guardian refused by policy rolls the whole enrolment
back.

Ancien élève: today's search (`search` / `enroll_existing`), restyled as the
mockup's result rows (name, last class and year, « Réinscrire » or a
disabled « Déjà inscrit cette année »).

Errors stay in the drawer (duplicate matricule, invalid phone, required
fields). « Inscrire » closes the drawer with a flash « Élève inscrit en 6ème
A (53 / 60). »; « … et en ajouter un autre » keeps it open with a cleared
form.

## 5. Enseignements tab (`TeachingsLive`, new)

Moves today's « Enseignements » section out of `class_live.ex`, behaviour
unchanged: form master select, assignments table (subject, teacher select,
h / sem., coefficient with « modèle » note and « Revenir au modèle »,
takers, regroupement / « Enseigner ensemble » / « Séparer »), add-assignment
form.

New: a warning block above the table when `unassigned_subjects` is not empty:
« 2 matières sans enseignant : Informatique, Travail manuel. Les notes et
l'emploi du temps de ces matières restent bloqués tant qu'elles ne sont pas
affectées. »; each subject name pre-fills the add form.

Header line: « Grille 6ème : 11 matières · 29 h / semaine » (count and sum of
`weekly_hours` over the class's teaching contexts).

The matching events and helpers move with the section; `ClassLive` keeps only
roster and enrolment code.

## 6. Other tabs

`TimetableLive`, `RegisterLive`, `DisciplineLive`, `ResultsLive` replace their
own page header with `class_shell`, move their page buttons (print, period
picker…) into the `:actions` slot or their toolbar, and drop their « back to
class » links. Bodies keep their content. Restyling is limited to matching the
mockup's table and card styles (borders, headings, number fonts). No new data
on these tabs.

## 7. Removed / moved

- The five navigate buttons in today's class header (results, import,
  timetable, register, discipline) — replaced by tabs and the actions slot.
- The delete column on the classes table — moved to the class « Gérer ▾ ».
- The free-text class label input — replaced by the suffix.

## 8. Testing

- `SchoolTemplates.cycle/2` unit tests over every level list.
- `Enrollment.capacity/2`: per-class max wins, school fallback, `near?`.
- `unassigned_subjects/2`: grid with série, blank-série fallback, no grid.
- `:enroll_new` with a guardian: link existing, create new, policy refusal
  rolls back student + enrollment.
- `ClassShell.visible_tabs/2` per role: admin, form master, teacher of the
  class (Résultats once published), surveillant général, plain member (none).
- LiveView: classes page grouping, chips, text filter, card markers, new-class
  drawer (preview, duplicate label disabled, creates and navigates); class page
  redirect of a non-manager to their first tab; enrol drawer both modes with
  parent match; teachings tab moved tests; each sub-page renders the shell with
  the right active tab.
- Existing tests for the moved sections are moved, not deleted.
- Browser check at desktop and 390 px against the mockup before merge.
