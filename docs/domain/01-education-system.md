# 01 — The Cameroonian Education System: Structure

*Confidence legend in [`README.md`](README.md). Source URLs inline.*

## 1. One national system, two subsystems

Cameroon runs **two parallel subsystems inside a single national education system**:

- **Francophone** — French language, French model.
- **Anglophone** — English language, British model.

This is the single most app-critical fact: it is *one* system with two linguistic/curricular
tracks, **not** two separate systems. Both run under the same ministries and the same
Competency-Based reform. (Colonial origin: France ~80% East, Britain the western fifth — today's
Northwest & Southwest.) ✅ ([WES/WENR](https://wenr.wes.org/education-system-profiles/education-in-cameroon/))

| Aspect | Francophone | Anglophone |
|---|---|---|
| Language of instruction | French | English |
| Curricular model | French | British |
| Primary exit certificate | **CEP** (Certificat d'Études Primaires) | **FSLC** (First School Leaving Certificate) |
| Secondary shape | **4 + 3** | **5 + 2** |
| Lower-secondary exam | **BEPC** | **GCE Ordinary Level** |
| Upper-secondary exam | **Probatoire** (1ère) then **Baccalauréat** (Tle) | **GCE Advanced Level** |
| 2nd-cycle exam board | **OBC** (Office du Baccalauréat) | **CGCEB** (Cameroon GCE Board) |

**Harmonization:** primary equalized to **6 years in both** subsystems (2006/07); a **unified
primary curriculum** taught to both since 2018/19. ✅ At **secondary** level the two still teach
**distinct syllabi** (French séries vs British O/A-Level subjects) — both competency-based but
not identical. ⚠️ Cross-system transfer remains hard in practice.

## 2. Levels, names, ages

| Level | French | English | Years | Ages | Compulsory |
|---|---|---|---|---|---|
| Pre-primary | Maternelle | Nursery / Kindergarten | 2 | 4–6 | No |
| Primary | Primaire | Primary | **6 (both)** | 6–12 | Yes (free in public) |
| Lower secondary (FR) | Premier cycle / Collège | — | 4 | ~12–16 | — |
| Upper secondary (FR) | Second cycle / Lycée | — | 3 | ~16–19 | — |
| Lower secondary (EN) | — | First cycle (Form 1–5) | 5 | ~12–17 | — |
| Upper secondary (EN) | — | Second cycle / Sixth Form | 2 | ~17–19 | — |

Ages are **nominal**; *redoublement* (grade repetition) is common, so real ages run higher. ✅

### Primary class names
- **Francophone (6 grades):** SIL, CP (initiation) · CE1, CE2 (fondamentaux) · CM1, CM2 (approfondissements). Exit: **CEP** + *concours d'entrée en 6ème*.
- **Anglophone:** Class 1 → Class 6. Exit: **FSLC**. ⚠️ There is **no "Class 7"** anymore (was 7 years pre-2006).

> **Scope note:** this product targets **secondary** first. Primary uses a *different* grading
> model (A/ECA/NA, 9 monthly evaluations) — do **not** conflate it with secondary's /20.

## 3. Francophone secondary — classes & séries

**Class order counts DOWN:**

| Cycle | Class | ~Age |
|---|---|---|
| Collège (1er cycle) | **6ème, 5ème, 4ème, 3ème** | 11–15 |
| Lycée (2nd cycle) | **2nde, 1ère, Terminale** | 15–18 |

Common curriculum 6ème→3ème, then **choose a série at entry to 2nde** (after BEPC). Two tracks:
**enseignement général (ESG)** and **technique et professionnel (ESTP)**.

**General séries** ([OBC nomenclature](https://officedubac.cm/nomenclature-des-examens/)):
- **Literary:** A1, A2, A3, **A4** (by far most common; split by 2nd language e.g. "A4 Espagnol", "A4 Allemand"), A5 (*Probatoire only*), ABI (bilingue), SH.
- **Artistic:** AC.
- **Scientific:** **C** (maths + physical sci), **D** (maths + life sci), **E** (maths + technology), **TI** (informatique).

**Technical séries** historically industrial **F1–F8** and commercial/tertiary **G1–G3**; current
OBC codes have evolved into groupings like **STT** (tertiary), **AF/CG**, agriculture, etc. ⚠️

> ⚠️ **Série B (economics):** sources disagree — widely treated as superseded by **SES**
> (Sciences Économiques et Sociales), which OBC lists under the STT grouping. Verify the live
> code on [obc.cm](https://obc.cm/series-et-specialites/) before hard-coding.
>
> **App implication:** model `série` as **configurable reference data**, not an enum frozen in
> code. Coefficients depend on série (see doc 04).

## 4. Anglophone secondary — Forms & Sixth Form

| Class | ~Age | Cycle → Exam |
|---|---|---|
| **Form 1 → Form 5** | 12–16 | First cycle → **GCE O Level** |
| **Lower Sixth → Upper Sixth** | 17–18 | Second cycle → **GCE A Level** |

Arts vs Science **streaming happens at entry to Lower Sixth**, based on O-Level results. ⚠️ This
is a *school-level* organizational practice; the CGCEB subject list is not formally partitioned
into streams. Loose parallels: Lower Sixth ≈ 1ère, Upper Sixth ≈ Terminale (rough only).

## 5. National exams

**Francophone:** CEP (primary) → *concours 6ème* → **BEPC** (end of 3ème) → choose série →
**Probatoire** (end of 1ère) → **Baccalauréat** (end of Terminale). Technical parallel: CAP →
Probatoire technique → Bac technique / Brevet de Technicien. ✅

**Anglophone:** FSLC (primary) → **GCE O Level** (end of Form 5) → **GCE A Level** (end of Upper
Sixth). Technical: TVEE Intermediate / TVE Advanced. ✅

**Exam bodies (all under MINESEC):** **OBC** (Probatoire/Bac + technical), **CGCEB / GCE Board**
(Buea, 1993 — O/A Level + technical), **DECC** (BEPC, CAP). ✅
([CGCEB](https://camgceb.org/examinations/), [OBC](https://officedubac.cm/nomenclature-des-examens/))

- GCE **O Level:** English, French, Maths compulsory; formal floor 4 subjects (customary load ~6). ⚠️
- GCE **A Level:** **max 5 subjects.** University baseline commonly 2 A-Level + 4 O-Level passes. ✅

## 6. Academic calendar

MINEDUB + MINESEC jointly fix **one national calendar** each year by a *décision* signed
mid-August. ✅ ([2025-26 decision](https://www.minesec.gov.cm/web/index.php/en/decisions/item/1846-the-2025-2026-school-year-calendar-in-the-republic-of-cameroon-19-aout-2025))

**Dual structure (critical):** **3 trimesters**, each split into **2 sequences** → **6 sequences
total, ~36 teaching weeks.** A report card is issued **after each sequence**; a term report after
each pair; annual average = mean of the 3 term averages (≡ mean of the 6 sequences). ✅
See doc 04 for the formulas.

**2025–2026 verified dates:** starts **Mon 8 Sep 2025**; administrative year-end **Fri 31 Jul
2026** (teaching ends ~mid-June, then official exams). Breaks: Christmas (19 Dec → 5 Jan),
Easter (2 Apr → 20 Apr), grandes vacances (mid-June → September). ✅

> ⚠️ **Dates change every year.** Model the academic year — term & sequence boundaries, the
> per-sequence *semaine d'intégration*, and holidays — as **configurable per-year data**, never
> constants.

## 7. School types & naming conventions

Ownership (under private-education **Loi n°2004/022**): **Public/Government**, **Private lay**
(*privé laïc*), **Private confessional/mission** (Catholic, Protestant — CBC/PCC/Full Gospel,
Islamic), **Community schools**. State requires all to follow the same curriculum. ✅

**Naming encodes the cycle — model a `school_type` field:**

*Anglophone* ✅:
- **GSS** Government Secondary School — first cycle only (Forms 1–5).
- **GHS** Government High School — includes second cycle / sixth form.
- **GBSS / GBHS** — bilingual variants (English + French sections).
- **GTC / GTHS** — technical (± Bilingual / Girls → GBTC/GGTC).
- Rule: **"High School" = has a second cycle**; **"Secondary School" = first cycle only.**

*Francophone* ✅:
- **Lycée** — general, includes second cycle (→ Bac). Parallel to "High School".
- **CES / CEG** (Collège d'Enseignement Secondaire / Général) — first cycle only. Parallel to "Secondary School".
- **Lycée Technique** — technical second cycle. **CETIC** — public technical first cycle. **SAR/SM** — artisanal sections.

## 8. Governing ministries

| Ministry | Governs | Subsystems |
|---|---|---|
| **MINEDUB** (Éducation de Base) | Nursery + primary + literacy | Both |
| **MINESEC** (Enseignements Secondaires) | General + technical secondary; pedagogic inspection (IGE); houses GCE Board, OBC, DECC | Both |
| **MINESUP** (Enseignement Supérieur) | Universities, higher ed, ENS teacher-training | Both |
| **MINEFOP** *(related)* | Labour-market vocational training | — |

Framework law: **Loi n°98/004 of 14 Apr 1998** (loi d'orientation de l'éducation). Vertical split
created by the Dec 2004 reorganization of the former MINEDUC. ✅ ([WES](https://wenr.wes.org/2021/04/education-in-cameroon))

## Top uncertainties to track
1. Série B vs SES code/grouping — verify on live OBC site.
2. Legacy F/G technical codes vs current OBC groupings.
3. Calendar dates — annual, configurable.
4. O-Level minimum subjects (formal 4 vs customary 6).

**Most authoritative sources:** [WES/WENR profile](https://wenr.wes.org/education-system-profiles/education-in-cameroon/) ·
[Alberta IQAS guide](https://www.alberta.ca/iqas-education-guide-cameroon) ·
[CGCEB](https://camgceb.org/) · [OBC](https://officedubac.cm/nomenclature-des-examens/) ·
[MINESEC](https://www.minesec.gov.cm/) · [MINEDUB](https://www.minedub.cm/).
