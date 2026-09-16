# 03 — Teacher Documents (the things we digitize)

*Confidence legend in [`README.md`](README.md). Source URLs inline.*

## How the documents fit together

```
Official Syllabus (MINESEC, national, immutable per cycle)
   └─ Répartition / Fiche de progression · Scheme of Work   (teacher/department pacing)
        └─ Fiche de préparation · Lesson plan               (per lesson)
             └─ Cahier de textes                            (what was ACTUALLY taught + homework)
   + Cahier de notes → Bulletin                             (marks → report card; see doc 04)
   + Fiche d'appel                                          (attendance)
```

The **fiche de progression is the pivot**: it turns the immutable national syllabus + the annual
calendar into a week-by-week teachable plan, against which the *cahier de textes* tracks reality
(**planned-vs-covered** — a strong product feature). The whole year is gridded as **3 trimestres →
6 séquences (2 per term) → ~36 weeks**, each sequence ending in an evaluation + integration week.
Model this grid once, reuse everywhere. ✅

> This is the document the user specifically called out: *"the base document from which they work
> is the Fiche de Progression… often shared in WhatsApp groups as PDF. We should be able to import
> it."* See §1 and the import note at the end.

## 1. Fiche de progression (Francophone) / Scheme of Work (Anglophone)

**Purpose:** year-long pacing plan distributing the official programme across weeks/sequences.
Also called *progression annuelle / pédagogique* or *répartition annuelle* (used interchangeably).
**Owner:** an individual teacher's document, **per subject × per class/level**, but in practice
**harmonized at department level** (chef de département / animateur pédagogique) so all teachers of
a level pace identically. Reviewed by the *inspecteur pédagogique*. 🟡 (mandatory sign-off is
customary, not verified regulation)

⚠️ **No single national blank template exists.** MINESEC standardizes the *programme* and the
*calendar*, but fiche columns are regional/department/teacher-authored. **Make the column set
per-subject configurable.**

**Synthesized common column set (FR), left→right:**

| Column (FR) | English gloss | Conf. |
|---|---|---|
| Trimestre (1–3) | term | ✅ |
| Séquence (1–6) | sequence | ✅ |
| Semaine | week no. | ✅ |
| Période / Dates (du…au…) | date range | 🟡 |
| Module | module | ✅ |
| Famille de situations | family of situations | 🟡 |
| Catégories d'action | action categories | ✅ |
| Chapitre / Leçon / Titre | lesson title | ✅ |
| Séances | sessions | ✅ |
| Compétences visées / Objectifs (savoirs, savoir-faire, savoir-être) | competencies/objectives | 🟡 |
| Notions / Contenus | content | 🟡 |
| Durée / Volume horaire / Nb d'heures | duration/hours | ✅ |
| Méthodes / Supports / Ressources | methods/materials | 🟡 |
| Évaluation | assessment | 🟡 |
| Observations | remarks | 🟡 |

Header (cartouche): Établissement · Classe · Année scolaire · Horaire hebdomadaire · Nombre de
leçons · Coefficient · Nom/Grade/Ancienneté de l'enseignant. ✅
([real Physics example, 2025-26](https://www.scribd.com/document/903735035/Progressions-Digitalisees-PHYSIQUE-2025-2026))

> **2025/26 "digitalisation" trend (directly relevant to us):** newest fiches add columns
> `Digitalisation des enseignements (OUI/NON)`, `Ressources en ligne`, `Ressources à utiliser`.
> MINESEC is actively pushing digital-resource columns and "inclusion of digitalized lessons in
> teachers' schemes of work." ✅

**Anglophone Scheme of Work — three profiles circulate** (support all three; constant = Term →
Sequence → Week):
- **A — CBA grid** (syllabus matrix copied): `TERM · SEQUENCE · WEEK · CONTEXTUAL FRAMEWORK [Families | Examples] · COMPETENCES [Categories | Examples of Actions] · RESOURCES [Knowledge | Skills | Attitudes | Other]`.
- **B — slim/traditional:** `WEEKS · TOPICS · CONTENT · ATTAINMENT TARGETS`.
- **C — English/skills-based:** `Sequences & weeks · Skills [Topics | Listening | Speaking | Reading | Writing] · Sub-Skills [Grammar | Vocabulary]`.

> ⚠️ The classic Commonwealth list (objectives/content/activities/aids/references/evaluation) is
> **Kenyan/East-African, not Cameroon CBA** — Cameroon uses **Attainment Targets** or
> **Competences/Examples of Actions**, not "Specific Objectives." Don't default to it.

**Mapping to the calendar:** rows keyed Trimestre → Séquence → Semaine; the **last week of each
sequence is the *semaine d'intégration/évaluation*** (no new lesson). Week→sequence boundaries
shift yearly with the official calendar → **calendar-driven config**, not constants.

**Pacing algorithm (drives auto-scheduling):** for each module,
`weeks_needed = module_hours (CRÉDIT) ÷ weekly_hours`; distribute across the 6 sequences,
reserving each sequence's final week for évaluation/intégration.

## 2. Official syllabus / programme (the immutable source)

**Issuer:** MINESEC via the IGE + subject Inspections de Pédagogie. One official syllabus per
subject per class. **Data hierarchy (confirmed from primary MINESEC PDFs):**

```
PROGRAMME D'ÉTUDES  (subject + class; volume horaire annuel + hebdo + coefficient)
└── MODULE  (n°, title, CRÉDIT = hours)            # 3–8 per subject/class
    ├── FAMILLE DE SITUATIONS (1 per module)
    ├── compétences visées
    └── MATRICE (3 column-groups):
        ├── CADRE DE CONTEXTUALISATION → Famille de situations | Exemples de situations
        ├── AGIR COMPÉTENT            → Catégories d'actions   | Exemples d'actions
        └── RESSOURCES                → Savoirs | Savoir-faire | Savoir-être | Autres
```
✅ ([Maths 6e/5e programme PDF](https://files.minesec.gov.cm/direct/view.php?s=2b&%2FPROGRAMME_MATH_6%C3%A8me_5%C3%A8me.pdf=))

**Programme vs répartition vs progression:**
- *Programme* = canonical, national, immutable per cycle — says *what* + *how many hours*, not *when*.
- *Répartition* = department/teacher split of modules→chapters→weeks/sequences (macro).
- *Fiche de progression* = répartition turned into a trackable week-by-week sheet. (Often merged.)

## 3. Cahier de textes (class diary / teaching log)

**Purpose:** official session-by-session record of work actually done + homework set — for
continuity, teacher liaison, and inspection. ✅ ([CAMEDU](http://secondaire.cam-edu.org/service/cahier-de-textes))
**Canonical model:** **one cahier PER CLASS**, kept in the classroom; **all teachers of that
class write in it**, sectioned by discipline; it does not leave the school. Digital versions
reorganize per-teacher/per-class. (Model may want **both** views.)
**Visa chain:** teacher signs daily; chef d'établissement signs termly; inspector countersigns on visits.

**Per-lesson fields:** Date (+ time slot) · Discipline · Contenu/travail effectué · Travail à
faire/devoirs (+ due date) · Observations · Signature · Visa. ✅

## 4. Fiche de préparation (lesson plan)

Detailed in [`02-cba-pedagogy.md`](02-cba-pedagogy.md) §3. Backbone: **header** (Date, Classe,
Module, Effectif, Titre, Durée, Compétence attendue, Supports, Situation/Corpus) + **body table**
`Étapes | Durée | Contenus | Supports | Activités d'apprentissage` populated by the 6-phase APC
démarche. APC lessons run **~50–55 min**. Column composition is 🟡 configurable. ✅
([ENS filled fiches](https://dicames.online/jspui/bitstream/20.500.12177/4565/1/ENS_2016_mem_0271.pdf))

## 5. Cahier de notes (grade book)

Secondary keeps numeric **/20, 6-sequence** system. One sheet = subject × class × sequence.
**Layout (reconstructed):** `N° · Matricule · Nom · Sexe · Interro 1 (/20,c1) · Interro 2 (/20,c1)
· Devoir surveillé (/20,c2) · Compo séquence (/20) · Moyenne séquentielle · Rang · Appréciation`.
**Evaluations per sequence are NOT nationally fixed** — model **N evaluations per (subject, class,
sequence), each with its own coefficient.** 🟡 Formulas in [`04-grading-and-report-cards.md`](04-grading-and-report-cards.md).

## 6. Attendance — fiche/cahier d'appel

Two overlapping mechanisms: subject teacher does per-lesson roll call; the **Surveillant Général**
centralizes daily absences, manages justifications, totals absence *hours* for the bulletin.
**Layout (reconstructed; no official blank template online ⚠️):** one sheet per class, days/periods
across columns: `N° · Matricule · Nom · [day/period cells] · Total présences · absences ·
justifiées · non justifiées`. Cell codes **P / A / R / AJ / AnJ**. Model **per-period OR per-day**
marking. ✅ (mechanism) / ⚠️ (exact layout)

## Key implications for the product

- **Separate three layers:** immutable **syllabus** (national reference data) · local **pacing**
  (fiche de progression, configurable columns, calendar-driven) · per-lesson **execution**
  (lesson plan + cahier de textes). Link a cahier-de-textes entry back to a progression row to
  compute **taux de couverture du programme** (planned-vs-covered).
- **Build for variability + import:** offer the 3 Anglophone scheme profiles; support
  **photo/PDF/Excel import** of legacy fiches shared on WhatsApp (the user's explicit ask). Treat
  imported fiches as a starting draft the teacher edits, since layouts vary school to school.
- **Bilingual everywhere** (FR/EN column headers and labels).

**High-value sources for real layouts:** [MINESEC programmes portal](https://www.minesec.gov.cm/web/index.php/fr/systeme-educatif/progammes-officiels) ·
[Maths 6e/5e PDF](https://files.minesec.gov.cm/direct/view.php?s=2b&%2FPROGRAMME_MATH_6%C3%A8me_5%C3%A8me.pdf=) ·
[Physics progression 2025-26](https://www.scribd.com/document/903735035/Progressions-Digitalisees-PHYSIQUE-2025-2026) ·
[CBA scheme examples](https://www.ektecknologies.com/2021/09/download-gce-syllabus-scheme-of-work.html) ·
[WES sample bulletins/transcripts](https://wenr.wes.org/wp-content/uploads/2021/04/Cameroon-Sample-Documents.pdf) ·
[2025-26 calendar](https://www.minesec.gov.cm/web/index.php/en/press-releases/item/1842-calendar-of-school-year-2025-2026-pdf).
