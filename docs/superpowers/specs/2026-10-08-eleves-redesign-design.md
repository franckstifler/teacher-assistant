# Élèves redesign (students list, student page, import) — design

Date: 2026-10-08
Status: approved in conversation, awaiting spec review
Mockup: claude.ai/design project « Tableau », file `Classes et eleves.dc.html`
(screens `#students`, `#student`, `#import`).
Follows: `2026-10-08-classes-redesign-design.md` (cycle 1).

## Goal

Finish the « Classes & élèves » group of the Tableau mockup. The three screens
already exist (`StudentsLive`, `StudentLive`, `EnrollImportLive`); this cycle
closes the gaps with the mockup and fixes two import behaviours.

Out of scope: the Frais link/tab (bursar deferred), a per-student filter on
`/school/absences`, birth place in the import.

## Decisions

| Question | Decision |
|---|---|
| Import format | Mockup's 5 columns, `;` or tab; name and sex required |
| Year result on the student page | Average and rank of the latest **published** report card of that class; nothing when none |
| « Inscrire un élève » on `/school/students` | The class page's enrol drawer, extracted into a shared component, with a class picker |
| « Sans contact parent » | No guardian linked at all |
| Page size of the students list | Stays 50 |

## 0. Shared enrol drawer

The « Inscrire un élève » panel, its events (`open_enroll`, `enroll_mode`,
`enroll_change`, `enroll_new`, `search`, `enroll_existing`) and helpers
(`reset_enroll`, `enroll_attrs`, `guardian_attrs`, `parse_birth_date`, …) move
out of `class_live.ex` into a stateful LiveComponent
`TeacherAssistantWeb.School.EnrollDrawer`
(`lib/teacher_assistant_web/live/school/enroll_drawer.ex`).

- Attributes: `scope`, `class_group` (a `ClassGroup` or `nil`), `classes`
  (the year's classes, only used when `class_group` is `nil`), `open?`.
- When `class_group` is `nil`, the first field is « Classe »: a select of the
  year's classes, each option « 6ème A — 52 / 60 » (`Enrollment.capacity_of/2`
  from counts loaded in one query). A near/over class shows the same warning
  line as on the class page. Submitting without a class is refused with
  « Choisissez une classe. ».
- On success the component sends `{:enrolled, enrollment}` to the parent
  LiveView. The class page reloads its roster (today's behaviour, including
  « Inscrire un autre »); the students list refreshes its page and counts.
- Closing goes through the parent (`close_drawer`), as today.
- Rights: unchanged — `can_manage_classes?` to open it, `can_manage_guardians?`
  for the parent block.
- Every existing class-page enrol test passes unchanged (DOM ids kept:
  `enroll-drawer`, `enroll-form`, `enroll-submit`, `enroll-another`, …).

## 1. Import (`/school/classes/:id/import`)

### Format (`Academics.RosterLine`)

One line per student: `nom ; sexe ; matricule ; date de naissance ; téléphone du parent`.

- Separator: `;` or tab, decided per line (a line containing a tab splits on
  tabs). Fields are trimmed; missing trailing fields are blank.
- Sex, case-insensitive: `m`, `g`, `garçon`, `garcon`, `b`, `boy`, `male` →
  `:m`; `f`, `fille`, `girl`, `female` → `:f`. Anything else, blank included,
  gives `sex: nil` and `error: :sex`.
- Date: `JJ/MM/AAAA`, today's rules (impossible or future dates dropped).
- Phone: when present, the row carries
  `guardian: %{full_name: "Parent de <nom>", phone: phone}`. The guardian is
  created with relationship `:autre`.
- No birth place, no parent-name column.
- Blank-name lines are dropped, as today.

### Classification (`Enrollment.preview_rows/3`)

Each row gets one action:

| Action | When | Note shown |
|---|---|---|
| `{:error, :sex}` | sex missing or unknown | « Sexe manquant ou inconnu (M ou F) » |
| `:create` | no matricule, or unknown matricule | parent note (below) |
| `{:reenroll, student, last}` | matricule known, same name, not enrolled this year | « Était en 6e B en 2025–2026 » (`last` = latest enrollment, or no note) |
| `{:conflict, :already_enrolled, cls}` | matricule known, same name, enrolled this year | « Déjà inscrit cette année (6e B) » |
| `{:conflict, :matricule_taken, name}` | matricule known, **different name** | « Matricule déjà utilisé (Ebogo Sandrine) » |

Same name: both names lower-cased, accents stripped, split on whitespace,
compared as sorted word lists (`Ebogo Sandrine` = `SANDRINE ébogo`).

Parent note, for `:create` and re-enrolments:

- no phone → none
- phone not `Guardian.Phone.valid?` → « Numéro « 690 22 » invalide — parent ignoré »
- phone matches an existing guardian → « Parent existant lié : Bekono Rose »
- else → « Parent : 6 77 45 12 90 »

The preview carries this as `{row, action, parent}` with
`parent :: nil | {:invalid, phone} | {:existing, guardian} | {:new, phone}`.

`import_rows/3` re-classifies at confirm (no trust in the preview), skips
errors and conflicts, and returns
`%{created, reenrolled, skipped: [%{full_name, reason}], guardian_issues}`.
An invalid phone is not attempted; it is reported in `guardian_issues` with
the number.

### Screen

- Breadcrumb « Classes / 6e A / Import ». Eyebrow « 6e A · 52 / 60 »
  (capacity line), title « Importer une liste d'élèves ». Stepper Coller →
  Vérifier → Terminé.
- **Coller**: textarea (left) and a format panel (right): the column line,
  « Séparateur : point-virgule ou tabulation. Seuls le nom et le sexe sont
  obligatoires. », « Un matricule déjà connu de l'école réinscrit l'élève au
  lieu de le recréer. », « Le téléphone est écrit comme vous voulez (677 45 12
  90, +237…) : il est lié au parent existant s'il est déjà enregistré. ».
  Buttons « Vérifier la liste », « Annuler » (back to the class).
- **Vérifier**: chips with counts (only non-zero ones): « N nouveaux élèves »,
  « N réinscriptions », « N conflits — ignorés », « N erreurs — ignorées »,
  « N numéros de parent invalides ». Table: action badge | name | « G ·
  12/02/2014 » | note. Buttons « Confirmer l'import de N élèves » (N = creates
  + re-enrolments; disabled when 0), « Corriger la liste » (back to Coller,
  text kept). Line « Après import : 58 / 60 élèves. », in warning tone when
  over the maximum.
- **Terminé**: headline « 5 inscriptions, 1 réinscription. »; one paragraph
  naming each skipped row with its reason and each parent not recorded with
  its number; the over-capacity warning when it applies. Buttons « Retour à la
  6e A », « Importer une autre liste » (empty Coller step).

## 2. Students list (`/school/students`)

- Header: eyebrow « Établissement », title « Élèves », subtitle « 781 inscrits
  en 2026–2027 · 37 sans contact parent » (year total and no-contact total,
  independent of filters). Action « Inscrire un élève » (`can_manage_classes?`)
  opens the shared drawer with the class picker.
- Toolbar: search (name or matricule), class select, toggle chip « Sans
  contact parent · 37 » (URL param `no_contact=1`, active style when on).
- `Enrollment :school_list` gains `argument :no_contact, :boolean, default:
  false` → `filter expr(not ^arg(:no_contact) or not exists(student.guardian_links, true))`.
  `Enrollment.count_students_without_contact(scope, year)` counts the year's
  enrollments with no guardian (one aggregate query).
- Table columns Élève | Matricule | Classe | Contact principal. Élève: initials
  avatar, name, sex under it (« Fille » / « Garçon »), repeater badge. Classe:
  chip. Contact: « Ebogo Martin · 6 77 12 34 56 » (`tel:` link on the number),
  else « Aucun contact » in the error tone. The whole row navigates to the
  student page (`phx-click` + `JS.navigate`; the name stays a real link for
  keyboard and middle-click).
- Footer: « 1–50 sur 781 » and « ← Précédent » / « Suivant → » (patch links,
  disabled at the ends). Empty: « Aucun élève ne correspond. ».

## 3. Student page (`/school/students/:id`)

### Header

- Breadcrumb « Élèves / Ebogo Sandrine » (the « Élèves » link only for
  `:manage` access, as today's back button).
- Initials avatar, name; meta line: current class as a link to the class page
  (or « Pas inscrit cette année »), matricule, « Fille · 12 ans » (age in full
  years at today's date, omitted without a birth date).
- Links when enrolled this year: « Bulletin » (this year's enrollment bulletin
  route) and « Absences » (`/school/classes/:id/register`).

### Left column

- **Identité**: unchanged behaviour (view list, « Modifier » toggles the form).
- **Parents et tuteurs**: header with « + Ajouter » (`:manage`), which toggles
  the add form (hidden by default; open after a failed submit). Each guardian
  card: name, relationship, « Contact principal » badge; phone(s); a meta line
  « Messages en français · aussi parent de Ebogo Ivan (3e A) » (other students
  linked to the guardian, with this year's class when enrolled). Actions
  « Modifier », « Contact principal », « Retirer » as today. The add form puts
  the phone first with the hint « Téléphone — commencez par lui ». The match
  line reads « Déjà enregistré : Abena Thérèse — mère de 2 élèves (4e A, 2nde
  C) » with « Lier Abena Thérèse ».
- Sibling data: `Enrollment.list_guardian_links/2` loads, per guardian, its
  other students and their current-year enrollment class in the same read;
  `find_guardians_by_phone/2` does the same for the match line.

### Right column

- **Cette année** (when enrolled this year): 4 tiles — « Absences injustifiées »
  (yellow when > 0), « Absences justifiées », « Retards », « Consignes » — then
  the sanctions list, then « Conduite · Séq. 1 · 16 · Séq. 2 · — ».
- **Scolarité dans l'établissement**: one row per enrollment, newest first:
  year, class, repeater badge, passage decision, result line, « Bulletin » link.
  Result line: from the latest published report card of that class —
  the annual publication if any, else the latest trimester's — « Année : 14,20
  · 5e / 48 » or « Trim. 2 : 15,72 · 3e / 52 ». Nothing when no publication.
  New `ReportCards.latest_published_result(scope, enrollment)` reads the
  frozen snapshot; it never computes a draft. One call per history row (a
  student has few).

### Access

Unchanged: `:manage` edits, `:read` (form masters, teachers) sees the page
without edit controls; write events from `:read` are refused.

## Testing

- `RosterLine`: 5 columns, tab separator, sex synonyms, blank/unknown sex →
  error, phone → guardian, short lines padded.
- `preview_rows`: each action of the table, name comparison (accents, order,
  case), parent notes (invalid, existing, new); `import_rows` skips errors and
  conflicts and reports invalid numbers.
- `:school_list` `no_contact` filter and `count_students_without_contact`.
- `latest_published_result`: annual over trimester, none when unpublished.
- LiveView: import three steps and chips; students list header counts, chip,
  row navigation, pagination, enrol from the list (class picker, refusal
  without class); student page header, age, add-parent toggle, sibling line,
  result line; existing class-page enrol tests unchanged.
- Gettext: new strings extracted, French/English filled, no fuzzy entries.
- Browser pass at the end (desktop and 390 px).
