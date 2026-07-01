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

- **Teacher-first, then school.** A teacher is the atomic unit; teacher↔school is many-to-many
  (moonlighting is normal given the teacher shortage). We ship a complete independent-teacher
  product first, then add the school layer teachers opt into. Bottom-up adoption is the on-ramp.
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

### Later
- National **syllabus library** · **offline-first** sync · **AI**-assisted remarks and scaffolding.

## Product quality bar

- No route crashes because academic year, class, subject, or assignment data is missing — guide to
  setup instead.
- Data is workspace-scoped; no tenant fallback through arbitrary records.
- Permissions derive from the selected workspace and role.
- Deterministic calculations are correct and tested before AI suggestions are introduced.
- Both languages render without overflow at mobile widths.
- Every critical flow is testable via LiveView selectors against stable DOM IDs.
