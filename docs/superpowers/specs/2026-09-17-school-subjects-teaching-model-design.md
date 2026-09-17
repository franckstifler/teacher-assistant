# School Subjects, Specialities, Seeding & Combined Courses (Design)

**Date:** 2026-09-17
**Status:** Draft — for review
**Depends on:** School Identity & Onboarding (`feat/school-identity-onboarding`, 2026-09-16) — `SchoolProfile`, `Schools.create_school/2`, school types & subsystems.
**Relates to:** P2.2 School Enrollment & Shared Classes (`2026-07-03`) — `ClassGroup`, `Enrollment`, `TeachingContext`, `Assignments`.

## Goal

Give a school a real, managed academic structure instead of free-typed strings:

1. A **subject catalog** the school owns and edits — the single place to manage
   all of a school's subjects (general, languages, technical).
2. **Seeding** on school creation: a school of a given *type + subsystem* starts
   with a sensible catalog and starter classes it can edit or remove, rather
   than a blank workspace.
3. **Specialities** (ELEQ, MACO, MENU…) and **séries** (A, C, D…) as first-class,
   pickable, seedable properties of a class — not ad-hoc text.
4. **Combined courses**: when several classes are taught together (same teacher,
   same subject, same hour — common in technical schools), the teacher records
   marks/attendance/progression **once**, while each class stays separate for
   enrollment, bulletins and ranking.

### Decisions locked during brainstorming

1. **Combined teaching is a delivery link, not a merge.** ELEQ and MACO remain
   distinct classes. A combined course links several per-class assignments so
   the teacher records once; every mark and attendance row still belongs to a
   student → their class → their **speciality-classified** bulletin and ranking.
   Nothing about bulletins/ranking/statistics changes.
2. **Subjects are managed per school, in Settings.** A catalog resource is the
   palette; assignments are chosen from it.
3. **Minimal blast radius.** `TeachingContext.subject` stays a **string**
   (the chosen catalog name, denormalized) — no FK migration of existing
   contexts, so marks/coverage/bulletins/fiches and their tests keep working.
   The catalog supplies the pick-list and the default coefficient.
4. **A combined course owns one shared progression** (it is literally one
   delivery); marks and attendance stay per student.
5. **Specialities/séries reuse the existing `serie` field** on `ClassGroup` —
   no new structural concept, just reference data + seeding + a labelled picker.

### Build phases

The design is one coherent whole, built in two phases so value ships early and
the deeper change is isolated:

- **Phase 1 — Subjects, Specialities, Seeding, Settings.** Additive; touches no
  existing marks/coverage/bulletin behaviour. Delivers the catalog, the
  reference data, seeding, and the Settings rethink.
- **Phase 2 — Combined courses.** The teaching-group link + shared-progression
  re-ownership + record-once teacher surface. Depends on Phase 1's catalog.

---

## Section 1 — Subject catalog (Phase 1)

### `Subject` (new resource, `TeacherAssistant.Academics.Subject`)

- `workspace_id` (required, `belongs_to :workspace`) — a school's own catalog.
- `name` (string, required) — e.g. `"Mathématiques"`, `"Allemand"`, `"Électricité"`.
- `code` (string, optional) — short label, e.g. `"MATH"`, `"ALL"`.
- `default_coefficient` (decimal, default `1`) — copied onto an assignment as its
  starting coefficient (still overridable per assignment, as today).
- `category` — `Ash.Type.Enum` `TeacherAssistant.Academics.SubjectCategory`,
  values `[:general, :language, :technical]`, default `:general` (per the
  project rule: never a bare `:atom`). Used for grouping in the UI and for
  seeding templates.
- `position` (integer, default `0`) — display order within the catalog.
- `active?` (boolean, default `true`) — soft-hide without deleting.
- Identity: `unique_subject_name` on `[:workspace_id, :name]`.
- House pattern: `uuid_v7_primary_key`, `timestamps()`, and the **same
  authorization pattern `ClassGroup`/`TeachingContext` use today** (verify at
  implementation; match, don't diverge).

### Code interface (`TeacherAssistant.Academics.Subjects`)

`list/1` (by workspace, ordered by position/name), `create/2`, `update/2`,
`deactivate/1`, `delete/1`. Delete is allowed freely (assignments hold their own
string copy, so removing a catalog entry never orphans data); deleting a subject
that is still the pick for active assignments shows an informational note but is
not blocked.

### Assignments read from the catalog

`Assignments.assign/3` today takes a raw `subject` string. Change the school
assignment UI (class-detail *Assignments* panel) to pick a subject **from the
catalog** (a select of active subjects, grouped by category), defaulting
`coefficient` from the subject's `default_coefficient`. The stored
`TeachingContext.subject` remains the chosen **name string** (denormalized).

**Trade-off (accepted):** renaming a catalog subject does not rename it on
existing assignments. Acceptable — rare, and a later "rename & cascade" is a
small follow-up. A hard `subject_id` FK is intentionally *not* introduced now
(it would migrate every existing context and ripple through marks/coverage/
bulletin tests for no Phase-1 benefit).

---

## Section 2 — Specialities, séries & reference data (Phase 1)

Cameroon secondary structure varies by school type and subsystem. We capture it
as **reference templates**, keyed by `{school_type, subsystem}`, in a dedicated
module `TeacherAssistant.Academics.SchoolTemplates` (Reference stays for the
calendar/period presets). Each template provides:

- `levels` — ordered level labels. General francophone: `6ème…Terminale`;
  anglophone: `Form 1…Upper Sixth`; technical (`cetic`, `lycee_technique`):
  `1ère Année…` per the cycle.
- `streams` — the values that populate a class's `serie` field, labelled by
  kind so the UI can call them correctly:
  - general lycée upper levels → **séries** (`A`, `C`, `D`, `TI`…);
  - technical → **spécialités** (`ELEQ`, `MACO`, `MENU`, `IH`…);
  - lower general levels → none (`serie` stays null).
- `subjects` — the starter **catalog** for that template: general subjects
  everywhere; language subjects (LV2) where relevant; technical/speciality
  subjects for technical types, tagged `:technical`.

The module defines the **structure** plus a concrete starter set for the common
types (`lycee`, `ces_ceg`, `cetic`, `lycee_technique`, the bilingual GBHS/GHS/
GSS). The exhaustive per-speciality subject grids are compiled from
`docs/domain/01-education-system.md` during implementation, following this
structure; no template ships empty.

The class create/edit form gains a **série / spécialité** select driven by the
active school's template (labelled "Série" or "Spécialité" per the stream kind),
writing the existing `ClassGroup.serie` field.

---

## Section 3 — Seeding on school creation (Phase 1)

Two seed moments, because the catalog is year-independent and classes are
year-scoped:

1. **Catalog — at school creation.** Extend `Schools.create_school/2`'s
   transaction (which already creates Workspace + `SchoolProfile` + `:head`
   membership) to also insert the template's starter **subjects** for the
   school's `{type, subsystem}`. A school opens Settings → Subjects to a real,
   editable list, not a blank one.

2. **Classes — at first academic year creation.** Classes need a year. When the
   head creates the school's **first** academic year (existing Settings flow),
   auto-create the template's starter **classes** (one class per level, and per
   level × stream where the template defines streams — e.g. one `1ère MACO`,
   one `1ère MENU`), into that year. All are ordinary `ClassGroup`s: fully
   editable, removable, and addable in `/school/classes`.

Seeds are a *starting point* — deliberately minimal (one class per
level/stream), matching "a couple of things he can modify, remove".

**Open detail (for review):** auto-create starter classes on first-year
creation (recommended — it's what "create him a couple of things" asks), versus
a one-click *"Populate from template"* button on the empty classes page. Both
are editable afterward; the difference is whether the head opts in.

---

## Section 4 — Combined courses (Phase 2)

### `CombinedCourse` (new resource, `TeacherAssistant.Academics.CombinedCourse`)

- `workspace_id`, `academic_year_id` (required).
- `teacher_user_id` (required, `belongs_to` the Accounts user).
- `subject` (string, from the catalog — same denormalized convention).
- `label` (string, e.g. `"Maths · 1ère MACO+MENU+ELEQ"`, auto-suggested).
- House pattern as elsewhere.

### `TeachingContext` gains an optional link

- Add `combined_course_id` (nullable `belongs_to :combined_course`). `nil` =
  ordinary per-class assignment (today). Set = this assignment is delivered as
  part of a combined course.
- **Linking rule (context layer, not DB):** every context in a course shares the
  course's `teacher_user_id` and `subject`; each keeps its own `class_group_id`.
  A context belongs to at most one course.

### Shared progression — the one structural change

Today `ProgressionPlan belongs_to :teaching_context`. A combined course delivers
one set of lessons, so it owns **one** plan:

- Add nullable `combined_course_id` to `ProgressionPlan`; make
  `teaching_context_id` nullable. A plan belongs to **exactly one** teaching
  unit — a lone context **or** a combined course (validated in the context
  layer).
- Introduce the notion of a **teaching unit** in scope resolution and the fiche/
  coverage code: `unit = context.combined_course || context`. The teacher's
  fiche, coverage math (`Coverage.summarize/2` over the plan's entries), and
  teaching log resolve against the unit. Solo assignments are unchanged (unit =
  context, plan on the context — today's path).

### Record-once teacher surface

- **Context switcher** lists a combined course as a single item
  ("Maths · 1ère MACO+MENU+ELEQ") instead of one row per class.
- **Marks:** the roster is the **union** of enrolled students across the course's
  linked classes; marks write per student exactly as today, so each mark lands
  on that student's own class bulletin and ranking. The marks grid may group
  rows by class for legibility, but it is one entry surface.
- **Attendance:** one session over the union; `AttendanceEntry` rows are
  per-student as today.
- **Bulletins / ranking / statistics:** untouched — they already read per
  student, per class.

### Creating a combined course

From the class-detail *Assignments* panel or a school *Courses* view: pick a
teacher + subject already assigned to several classes and "teach together",
which creates the `CombinedCourse` and stamps `combined_course_id` on the chosen
contexts. "Split" clears the link (each class returns to its own assignment and,
if it had one, its own progression). Timetable slot coordination (one slot for
the combined course) is manual for now.

---

## Section 5 — Settings rethink (Phase 1)

`/school/settings` is one long page today (name, profile, periods link, years,
logo). Reorganize into clear, anchored sections with a sticky sub-nav:

- **Profil** — the `SchoolProfile` form (type, subsystem, sector, region, head,
  logo, …) as today.
- **Année scolaire** — year create/activate/rename as today; first-year creation
  triggers class seeding (Section 3).
- **Matières** — the new subject catalog: list grouped by category, add/edit/
  reorder/deactivate/delete (Section 1). *This is the "manage all subjects"
  home.*
- **Emploi du temps** — periods (existing).
- **Classes** — a link across to `/school/classes` (which stays the classes
  home, now with the série/spécialité picker and seeding).

No behavioural change to Profile/Year/Periods; the rework is information
architecture plus the new Matières section.

---

## Section 6 — What does NOT change

Marks, attendance, enrollment, bulletins, moyennes, ranking, statistics,
coverage math, fiches, the teaching log, and the personal-teacher workspace flow
all keep working. Phase 1 is additive. Phase 2's only structural edit is making
`ProgressionPlan` attach to a teaching unit (context *or* course); everything
downstream of a plan is unchanged. Personal-workspace contexts keep their
current free-string subjects (the catalog is a school feature for now).

---

## Open questions (resolve at spec review)

1. **Starter classes:** auto-seed on first-year creation, or one-click "Populate
   from template"? *(Recommend: auto, editable.)*
2. **Subject denormalized string vs FK:** accept that a catalog rename does not
   cascade to existing assignments? *(Recommend: yes; add a rename-cascade later
   only if it bites.)*
3. **Default academic year:** should `create_school` also create a default
   active year (so class seeding can happen immediately at creation), or keep
   year setup as the head's explicit first step? *(Recommend: keep explicit;
   catalog seeds at creation, classes at first-year creation.)*
4. **Phase boundary:** ship Phase 1 (subjects/specialities/seeding/settings) as
   its own increment and plan Phase 2 (combined courses) after, or plan both
   together? *(Recommend: Phase 1 first — it answers the immediate needs and
   Phase 2's progression change deserves its own focused review.)*

## Out of scope

- Personal-workspace subject catalog; a cross-school shared subject library.
- Automatic timetable generation for combined courses (slot linking is manual).
- HOD/coordinator subject-coordination views; per-subject fine permissions.
- Rename-and-cascade of a catalog subject onto existing assignments.
