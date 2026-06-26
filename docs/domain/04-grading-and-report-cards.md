# 04 — Grading, Averages & Report Cards

*Confidence legend in [`README.md`](README.md). Source URLs inline. This is the doc with the most
"configurable vs hard-codeable" guidance — read §9 before modeling.*

## 1. Sequence / term structure (Francophone) ✅

The MINESEC year = **6 administrative sequences ("séquences administratives"), 36 weeks, grouped
into 3 trimesters (2 séquences per trimestre).** Verbatim ministerial text:
*"L'année scolaire s'organise en six (06) séquences administratives pour un total de trente six
(36) semaines"* and *"se divise en trois trimestres."* Real exam papers labeled "Évaluation
séquentielle N°1…N°6" confirm nationwide use. Each séquence requires continuous assessment
(*devoirs surveillés*), then correction, remediation, relevé de notes.
([calendar PDF](https://www.minesec.gov.cm/web/attachments/article/147/CALENDRIER%20SCOLAIRE%202021-2022.pdf))

⚠️ **Number of devoirs per séquence is NOT nationally fixed** ("2 devoirs + 1 composition" is
school-dependent) → configurable.
⚠️ **Primary ≠ secondary:** the A/ECA/NA + "9 monthly evaluations" model is **MINEDUB primary
only**. Secondary keeps 6 séquences / /20. Do not conflate.

## 2. Scale, coefficients, average formulas (Francophone)

**Scale /20; pass = 10/20 ("la moyenne").** Each subject has a **coefficient**; coefficients are
set by MINESEC and **vary sharply by série**.

**Formulas (✅ confirmed):**
- **Moyenne séquentielle** = `Σ(Note × Coef) ÷ Σ(Coef)`. Total des points = `Σ(Note×Coef)`; Total des coefficients = `Σ(Coef)`.
- **Moyenne annuelle** = **mean of the 6 séquence averages** (`Σ séquences ÷ 6`). ✅ verbatim ministerial rule.
- **Moyenne trimestrielle** = mean of the term's 2 séquences. (derived, consistent.)
- **Moyenne générale** of a student = coefficient-weighted `Σ(moyenne_matière × coef) ÷ Σ(coef)`.

> ⚠️ Do **NOT** use the generic French weighted-trimester formula `(T1 + 2·T2 + 2·T3)/5` — that's
> France, not Cameroon. Cameroon uses the **unweighted mean of the 6 séquences.**

**Coefficient example — 2nd cycle (Probatoire), shows série dependence** ✅
([itag-cm](https://lms.itag-cm.com/lecon.php?id=2312)):

| Subject | A4 (literary) | C (maths/phys) | D (life sci) |
|---|---|---|---|
| Français | 5 | 3 | 3 |
| Philosophie | 4 | 2 | 2 |
| Mathématiques | — | **5** | 4 |
| Physique-Chimie | — | 4 | 4 |
| SVT | — | 2 | **4** |
| Histoire-Géo | 3+3 | 2 | 2 |
| Anglais / LV2 | 3 / 2 | 1 | 1 |
| EPS | 1 | 1 | 1 |

⚠️ **Premier cycle (6e–3e) coefficient tables** could not be verified from an authoritative
Cameroon source online — treat any 6e–3e coefficients as **configurable, school-supplied**.

## 3. Ranking ✅

**Rang / Place** within the class against the **effectif** (e.g. "5e / 60"). Standard comparison
values: **moyenne de la classe**, **plus forte moyenne**, **plus faible moyenne**. Ex-aequo
(ties) exist but no standardized printed convention.

## 4. The Bulletin de Notes (Francophone) — full field list

Richest primary source: a real Cameroonian **APC 6ème bulletin**
([fliphtml5](https://fliphtml5.com/zeixy/wrlj/BULLETIN_DE_NOTES_APC_6%C3%A8me_ordinaire/1/)),
corroborated by Cameroon school-software vendors. Sections:

- **A. Header / identity:** bilingual national header (République du Cameroun – Paix-Travail-Patrie);
  MINESEC; Établissement (+ address/BP/tél); Année scolaire; Trimestre/Séquence; Classe + Série;
  Effectif; Nom et Prénoms; **Matricule / Identifiant Unique**; date & lieu de naissance; Sexe;
  Redoublant (O/N); Professeur principal; contacts Parents/Tuteurs.
- **B. Per-subject rows:** Matière + enseignant · Compétences évaluées (APC) · Coefficient · Note
  /20 · Note×Coef · Cote/range [min–max] classe · Appréciation · Visa enseignant.
- **C. Subject "Groupes" (I/II) with sub-totals** — legacy; ⚠️ not on modern APC bulletins (flat
  list). Optional.
- **D. Totals:** Total des points · Total des coefficients · Moyenne générale/trimestrielle ·
  Moyenne de la classe · plus forte/faible moyenne.
- **E. Ranking:** Rang/Place · Effectif · ex-aequo.
- **F. Mentions/Distinctions:** Tableau d'honneur · Encouragements · Félicitations · Avertissement
  (travail) → Blâme.
- **G. Conduct/discipline:** Absences non justifiées (h) · Absences justifiées (h) · Retards ·
  Consignes · Note de conduite (vendor variant) · Sanctions (Avertissement/Blâme de conduite,
  Exclusion temporaire (days), Exclusion définitive).
- **H. Decisions/signatures:** Appréciation du travail · Appréciation du conseil de classe ·
  **Décision annuelle — Admis / Redouble / Exclu** · Visa Professeur principal · Visa Chef
  d'établissement · Visa parent · Cachet · Fait à … le ….

Vendor corroboration (séquentiel/trimestriel bulletins, synthèses, tableaux d'honneur,
absences justifiées/non, conduite): [SYGEST](https://nouviceduc.website/) ·
[SICOLO](https://www.gedeon.cm/sicolo/) · [EcoTech](https://www.ecotech-solutions.net/fr/features/gestion-notes) ·
[MyScol](https://myscol.com/logiciel-de-gestion-des-notes-scolaires/).

## 5. Anglophone grading — keep a SEPARATE engine

Two regimes:
- **National GCE exams (✅):**
  - **O Level:** letters **A, B, C, D, E, U**; only **A/B/C pass**; below C not printed.
  - **A Level:** **A, B, C, D, E, O, F**; A–E pass; **points A=5, B=4, C=3, D=2, E=1; max 5
    subjects = 25 pts**; **O** = compensatory non-pass; F = fail.
    ([CGCEB](https://camgceb.org/examinations/gce-advanced-level/))
- **In-school assessment (⚠️ source disagreement /20 vs /100):** many Anglophone schools mark
  /20 or /100, convert to %, assign **letter grade + word remark** (Excellent/Very Good/Good/
  Credit/Average/Pass/Fail). **Common pass = 50%.** No single national MINESEC standard — varies
  by school.

**Anglophone report card** (real example, St. Therese, Form 11): `Subject | Mark | Grade | Remark
| Teacher initials` + term average · class average · position in class/size · conduct · class
master & Principal comments · promotion decision · parent signature.
**Term structure:** 3 terms; the "2 sequences per term" count is well-attested Francophone but
⚠️ **not confirmed for Anglophone** — varies by school.

## 6. Statistics schools/teachers care about ✅

| French | English | Definition |
|---|---|---|
| Moyenne de la classe | class average | mean of students' moyennes générales |
| Moyenne par matière | subject average | mean of all marks in a subject |
| Taux de réussite | pass rate | % with moyenne ≥ 10/20 |
| Effectif / garçons / filles | headcount / boys / girls | counts split by sex |
| Plus forte / plus faible moyenne | highest / lowest average | max / min |
| Écart-type / Médiane | std deviation / median | ⚠️ vendors list them; no CM-specific formula |
| Taux de couverture du programme | curriculum coverage rate | % of syllabus taught |
| Tableau d'honneur / encouragement / félicitations | honour / encouragement / congratulations rolls | distinction lists |

**Gender disaggregation (garçons/filles) is a required standard output** — both in school
software and MINESEC/INS national statistics. Each metric above should support a gender split. ✅

The **conseil de classe** (chaired by the head, each trimester-end) reviews class results,
per-subject **programme coverage**, teaching-hour coverage, and decides mentions/sanctions/
promotion. National benchmarks for context: Bac général 2025 ≈ 47.4%; BEPC 2025 ≈ 65–69%. ✅

## 7. Mentions & pass mark ✅

**Pass = 10/20.** Bac/school mention bands (/20):

| Mention | Range |
|---|---|
| Passable | 10 – 11.99 |
| Assez Bien | 12 – 13.99 |
| Bien | 14 – 15.99 |
| Très Bien | 16 – 17.99 |
| **Excellent** | ≥ 18 |

⚠️ Top label is **Excellent**, NOT the French "Très Honorable" (THF is a French university term;
Scholaro's THF labeling is wrong for Cameroon).

**Distinction-roll thresholds (Encouragements / Tableau d'honneur / Félicitations / Excellence)
are configurable per école** — common sets are 12/14/16 or 12/13–14/15–16/>17; *every source says
each établissement sets its own*. Also gated on behavior (all subjects ≥10, acceptable conduct). 🟡

## 8. Conduct & the délibération reform (both flagged) ⚠️

- **Conduct representation varies:** the readable APC sample records it as **event counts** (abs.
  justifiées/non h, retards, consignes, sanctions); some vendors use a single **note de conduite**.
  Whether conduct is /20 vs qualitative and whether it enters the moyenne générale is **not
  settled by any authoritative MINESEC text** — common practice tracks it **separately**.
  **Support both models.**
- **2024 "no-compensation / no-délibération" reform was MIXED:** announced for BEPC/Probatoire/Bac
  (need ≥10 overall AND ≥10 in each first-group subject), enforced in 2024 (Bac crashed to ~37%),
  but **deliberations restored for 2025** (~47%). **Do NOT hard-code "one failed subject = fail"
  for 2026.** Default to the traditional moyenne-générale-with-compensation model, configurable.
  Anglophone GCE unaffected.
  ([durcissement](https://fr.journalducameroun.com/cameroun-le-gouvernement-durcit-les-criteres-dadmission-aux-examens-officiels/) ·
  [restored](https://www.journaletudiant.com/baccalaureat-2025-finalement-on-delibere/))

## 9. What to hard-code vs configure (decision table)

**Safe to hard-code (✅):**
- Pass mark **10/20** (Francophone).
- Annual average = **mean of the 6 séquences**; sequence average = `Σ(N×c)/Σc`.
- Mention bands **10 / 12 / 14 / 16 / 18**, top = **Excellent**.
- GCE A-Level points **5-4-3-2-1**, max 5 subjects = 25.
- Year grid: **3 trimesters / 6 sequences / integration weeks**.

**Must be configurable per école / per série / per year (🟡 / ⚠️):**
- Subject **coefficients** (by série) — reference data, not enum.
- **Devoirs per sequence** and their coefficients.
- **Distinction thresholds.**
- **Conduct model** (/20 vs qualitative vs event-counts) and whether it enters the average.
- **Compensation / délibération** rule.
- Anglophone in-school scale (**/20 vs /100**) and pass % and sequences-per-term.
- All **fee** and **calendar** values (docs 05 & 01).

**Biggest remaining uncertainties:** premier-cycle 6e–3e coefficients; exact conduct scale & weight;
Anglophone in-school /20-vs-/100 & sequences-per-term; 2026 enforcement of no-compensation. Resolve
by obtaining a real MINESEC circular / actual bulletin PDFs
([WES samples](https://wenr.wes.org/wp-content/uploads/2021/04/Cameroon-Sample-Documents.pdf)).
