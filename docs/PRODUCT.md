# Teacher Assistant — Product Definition

> Rewritten 2026-06-26 for the from-scratch rethink. This is the evergreen product vision.
> The detailed, current build target lives in
> [`docs/superpowers/specs/`](superpowers/specs/). Domain facts live in
> [`docs/domain/`](domain/README.md) and are the source of truth for how Cameroon's system works.

## Product summary

Teacher Assistant is a **mobile-first, bilingual (FR/EN) platform for Cameroon secondary
education**, marketed around the **Competency-Based Approach (CBA / APC)**. It serves both
**independent teachers** and **schools**, built so a teacher gets full value alone and a school
layers official administration on top.

It must reflect *real* Cameroon school operations — academic years, terms and sequences, the
*fiche de progression*, CBA lesson structure, /20 marks and coefficients, report cards, programme
coverage, school roles and councils, fees and fee-based access. See [`docs/domain/`](domain/README.md).

## Principles

- **School-first (since 2026-09-23).** The school workspace is the product: identity, staff and
  roles, classes, subjects, timetables, roll call, marks and report cards. The independent-teacher
  workspace (personal progression plans, fiche import, lesson plans, teaching log, coverage)
  was removed on 2026-09-23; a future teacher mode would be a school-of-one. Teacher↔school stays
  many-to-many; a teacher works inside the schools that invited them.
- **Mobile-first.** Most teachers work from phones, over intermittent connectivity. Every flow is
  designed for a few taps on a small screen first.
- **Bilingual by law, not by translation.** Francophone (French model) and Anglophone (British
  model) are two tracks of one national system. Carry FR + EN labels for every concept.
- **CBA-ready, not CBA-mandatory.** CBA adoption is uneven in practice; CBA structure is available
  and encouraged but never blocks a teacher who plans more traditionally.
- **Configurable, not hard-coded.** Almost every Cameroon "number" (fees, coefficients by série,
  devoirs per sequence, distinction thresholds, calendar) is a per-school / per-year setting. Only
  the items marked ✅ in [`docs/domain/04`](domain/04-grading-and-report-cards.md) are constants.
- **Deterministic before AI.** Calculations (coverage, averages, ranks) must be correct and tested
  before any AI suggestion is layered on. AI produces editable suggestions, never authoritative numbers.

## Target users

- **Independent teacher** — plans the year, tracks teaching, (later) marks and lesson plans, with
  no school involved. The starting persona.
- **School-affiliated teacher** — same tools, plus participation in a school's classes, marks, and
  report-card workflows.
- **School pedagogic staff** — vice-principal (*censeur*) and heads of department follow programme
  coverage and teacher progression.
- **School discipline staff** — *surveillant général* tracks attendance and discipline.
- **School admin / bursar** — configures the school, manages enrollment, fees, and fee-based access.
- **Principal / head** — owns configuration, roles, report-card settings, and council decisions.

(Role definitions: [`docs/domain/05`](domain/05-school-roles-and-fees.md).)

## Phased roadmap

The build is sequenced so each phase ships a usable product. Detailed specs are written per phase.

> **Status 2026-09-23:** Phase 1 (independent teacher) is paused, not removed. Phase 2 (school)
> is the active track. Fees and fee-based access are deferred inside Phase 2. Audit and roadmap:
> [`docs/audits/2026-09-23-school-focus/`](audits/2026-09-23-school-focus/README.md).

### Phase 1 — Independent teacher (in progress)
- ✅ **v1 — Progression & Coverage (shipped).** *(spec:
  [`2026-06-26-teacher-progression-coverage-v1-design.md`](superpowers/specs/2026-06-26-teacher-progression-coverage-v1-design.md))*.
  Build a *fiche de progression* per subject × class (builder + templates), log what's actually
  taught (lightweight *cahier de textes*), and see **taux de couverture du programme**, on a clean
  Phoenix/Ash + branded-auth scaffold with a guided year-setup wizard and a teacher dashboard.
- ✅ **v1.1 — Assisted fiche import (shipped).** *(spec:
  [`2026-06-27-fiche-import-v1_1-design.md`](superpowers/specs/2026-06-27-fiche-import-v1_1-design.md))*.
  Import an existing **text-based fiche PDF** → editable draft rows → a new draft plan,
  **deterministically (no AI)** via `pdftotext`. Scanned/photo and Excel import, and AI structuring,
  are deferred to a later increment.
- ✅ **v1.2 — Marks & mark register (shipped).** *(spec:
  [`2026-07-01-teacher-marks-register-v1_2-design.md`](superpowers/specs/2026-07-01-teacher-marks-register-v1_2-design.md))*.
  Per-subject **mark register** for the independent teacher: a shared class **roster**, free-form
  **assessments** per séquence, **/20 marks**, and deterministic per-séquence statistics (moyenne
  séquentielle, class average, *taux de réussite*, rank, garçons/filles split, mentions). The
  official multi-subject **bulletin de notes** (cross-subject *moyenne générale*, ranking, conduct,
  decisions) is deferred to the **school layer (Phase 2)** — a solo teacher owns only their subject.
- ⏳ **v1.3 (next)** — **lesson-plan (fiche de préparation)** editor scaffolded from a progression entry.

### Phase 2 — The school layer
- School workspaces; staff **roles & councils**; teacher **invitations** (teacher↔school many-to-many).
- Official **report cards** and **statistics** (with gender disaggregation, programme coverage).
- **Enrollment**, **fees** (multi-tranche schedules), and **fee-based access control** —
  configurable, overridable, audited (exam-gating is legally grey; never automatic).

### Wanted next (picked 2026-11-10, to review)

From a comparison with Cameroonian school software (EduCam Pro, Kalara, SAMIA, Skoulou, FobsSMS,
EduManager Pro, Go4School). Facts behind both items:
[`docs/domain/06`](domain/06-ministry-statistics-and-school-papers.md).

1. **School papers the secretariat prints.** A **certificat de scolarité** on demand (name, birth
   details, class, year, matricule and national matricule, issue date, the head's signature and
   stamp, national header, QR check like the card and the receipt), possibly an **exeat**, and
   perhaps a file in the **CarteScolaire** import template (new students, transfers) so lists are not
   typed twice. Open: a real school's certificate to copy the wording; who may print it (secretariat?
   head only?); numbering and a register of issued papers.
2. **Statistics for the MINESEC campaign.** A printable « Statistiques — campagne MINESEC » page that
   lays out the questionnaire's tables in its order and with its line codes, so the secretariat copies
   the numbers into the official Excel file (Scolaka never writes into that file: it is protected,
   full of macros and changes yearly). Fillable from our data: students by year and series —
   divisions, students by sex, repeaters by sex (II.1.2); students by year × sex × birth year (II.1.1),
   only where birth dates are entered, so the page lists the students without one; staff weekly hours
   per cycle and main subject taught (from the timetable). Not stored today: staff matricule, birth
   date, sex, grade, diplomas, years of service; OEV / disabled / refugee / displaced counts;
   technical specialty codes per class. Open: this year's form (only the 2021 one was found), whether
   to add the missing staff fields, and a trimester or end-of-year report from the head (no official
   model found; a real copy is needed).

Also seen in other software and **not wanted for now** (user, 2026-11-10): mobile money collection
and anything payment-related, payroll, accounting. Not picked: parent portal and messages, a digital
cahier de textes for the school, offline mode, staff clock-in, multi-campus, canteen / transport /
boarding / library / infirmary.

### Later
- National **syllabus library** · **offline-first** sync · **AI**-assisted remarks and scaffolding.
- **Half-class lessons** (deferred 2026-11-09). Technical schools split a class into two groups
  for workshops: two teachers, two subjects, same class, same hour (Ngog-Mapubi « génie bois »,
  e.g. 1ère AMEB F.F.O + Mécanique appliquée on Thursday 12:00). A timetable cell holds one
  lesson per class (`TimetableSlot` identity `unique_cell`), so the second lesson can't be
  placed: it's missing from that teacher's timetable, « Ma journée » and roll call (courses,
  marks and bulletins are unaffected). To decide: a group label on the slot or real sub-groups
  with their own students, roll call per group, two lessons in one cell on screen and in prints,
  clash checks.

## Données personnelles

Records belong to the school: Scolaka keeps them for it while the school uses the product, and
never sells, rents or shares them, nor uses them for advertising.

A departed student is anonymised three years after their last enrollment ended (`left_on`, else
the end of that academic year): the name becomes « Élève parti », the national id, birth place and
photo are erased (the photo everywhere, published bulletins included), guardians are unlinked (a
guardian left without a child in the school is deleted). Marks, roll calls, conduct and payments
stay for the school's figures. Numbered documents keep the name they were issued with: published
bulletins (snapshots), receipts, fee warnings and return notes (`student_name` columns). Weekly
job, Sunday 04:00 school time (`AnonymiseDepartedStudents`, cron in UTC).

Upload files no row refers to any more (student photos, school logos and signatures older than a
day) are deleted weekly, Sunday 04:30 school time (`SweepOrphanPhotos`), and counted in the operator digest.

A person who is a member of no school deletes their own account from « Mon compte »: name, e-mail,
phone and password are erased and every session is revoked; what they entered keeps its place
under « Compte supprimé ». A member of a school is first removed by the head — the school's
records keep a name until then.

The operator never sells or shares a school's data. Support opens a member's space only through
one-hour, journaled impersonation; marks, roll calls, sanctions and payments entered then carry
the operator's name (A6).

## Product quality bar

- No route crashes because academic year, class, subject, or assignment data is missing — guide to
  setup instead.
- Data is workspace-scoped; no tenant fallback through arbitrary records.
- Permissions derive from the selected workspace and role.
- Deterministic calculations are correct and tested before AI suggestions are introduced.
- Both languages render without overflow at mobile widths.
- Every critical flow is testable via LiveView selectors against stable DOM IDs.
