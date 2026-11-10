# 06 — Ministry statistics and school papers

What a secondary school sends up to the ministry (the annual statistics campaign), the national
student register (CarteScolaire), and the papers the secretariat issues to families
(certificat de scolarité, exeat). Researched 2026-11-10. Confidence legend: see
[`README.md`](README.md).

## 1. The annual statistics campaign (MINESEC) ✅

**What it is.** Each year the MINESEC Planning Unit (*Cellule de la planification*, Division des
projets, de la planification et de la coopération) sends every secondary school an Excel
questionnaire. The school fills it in; departmental and regional *chefs service carte scolaire*
check it and summarise it per school; the ministry publishes an *annuaire statistique* from it
(≈ 93 % of schools returned it in 2018/2019). ✅
([questionnaire page](https://minesec.gov.cm/web/index.php/en/theslips/item/906-questionnaire-enseignement-normal),
[annuaire 2018-2019](https://ins-cameroun.cm/wp-content/uploads/2025/06/Annuaire_Statistique_Minesec_2018-2019.pdf),
[organigramme](https://www.minesec.gov.cm/web/attachments/article/116/Organigramme%20MINESEC.pdf))

**The form.** `1-QUESTIONNAIRE CAMPAGNE STATISTIQUE MINESEC 2021-SECONDAIRE.xls` — "Statistiques
scolaires 2020/2021", the latest version found online. Excel 97 workbook with macros, write-protected
with Excel's default key (opens with no real password); bilingual FR/EN; every cell row carries a
numeric line code (2119, 2120, …). A circular letter accompanies each campaign
([2020-2021](https://minesec.gov.cm/web/index.php/en/theslips/item/905-lettre-circulaire-campagne-statistique-2020-2021),
not read). ⚠️ The layout may change between campaigns: check the current year's file.

| Sheet | What it asks |
|---|---|
| Menu | Region, département, arrondissement, school name (from a list), respondent, head, school registration number, date, school type and status |
| Identification | Commune, town, quarter, zone, treasury post, phones, e-mail, website, year created/opened/transformed, land title, areas, distance to nearest public school, number of cycles, boarding places (girls/boys), access roads, nearby primary schools by distance |
| Eleves_ESG_Fr / Students_ESG_Eng | **II.1.1** students by **year of study (6e → Tle) × sex × birth year** (11 or under … 24 or over), plus *dont* orphans & vulnerable (OEV), disabled, refugees, internally displaced. **II.1.2** for each year **and series/option** (6e, 6e Bilingue, 4e Esp, 4e All, 4e Bilingue, 4e Ang renforcé, … 2nde A4 All/Esp, 2nde C, 1ère C/D/TI, Tle A4/C/D/TI, …): **number of divisions (classes), students by sex, repeaters by sex**, with totals per cycle. The two tables must agree (built-in check). |
| Eleves_ESTP_Fr / Students_ESTP_Eng | Same for technical education: by age and year (1ère → 4ème année, 2nde/1ère/Tle T or BT), then by **specialty code** (≈ 100 codes: TCCOM, TCIND, AAT, AG-PV, …) × year: divisions, students by sex, repeaters |
| Infrastructures, Atelier_Workshop | Buildings by type/construction/state, furniture, other facilities; workshops |
| Personnels | **One row per staff member**: matricule, surname, first names, date of birth, sex, status, position, academic diploma, professional diploma, subject trained in, main subject taught, grade, function, years in public service, sub-system taught in 1st / 2nd cycle, **weekly hours taught in 1st / 2nd cycle** |
| Manuels-Didactics | Textbooks/guides available per subject × level, per sub-system |
| Financement-Funding | School funding |
| Themes_Tranversaux | Added 2021: comprehensive sexuality & HIV education taught or not |
| Variables Essentielles | Reserved for the Délégation's *carte scolaire* services |

## 2. CarteScolaire — the national student register ✅

[cartescolaire.cm](https://cartescolaire.cm/) ([FAQ](https://cartescolaire.cm/faq)), run by
MINESEC. Every secondary student (public, private, mission) has a **national matricule**, unique for
their whole secondary schooling; without it a student cannot pay fees through the approved channels,
register for public exams (DECC, OBC, GCE Board), be insured or play FENASCO games. ✅

- The head signs in with a phone number and an SMS code (sender « CarteScolaire » / « SchoolMap »).
- **New students:** download the Excel template, fill it in, import it, wait ~48 h for SMS
  validation, then download the list with matricules.
- **Transfers:** « Transférer les élèves » → transfer template → import → ~48 h validation.
- No statistics, no certificates, no API mentioned. The template's columns are not published online.

Scolaka already stores it: `Student.national_id` (separate from the school's own `matricule`).

## 3. Papers the secretariat issues 🟡

No official Cameroonian model was found online for either paper; schools use their own. Most
papers are signed by the head (user, 2026-11-10).

- **Certificat de scolarité** — attests that the student is enrolled. Usual content: student's name,
  date and place of birth, class, school year, matricule (and national matricule), issue date, the
  head's signature and the school stamp, under the national header. Public lycées hand one over once
  enrolment fees are paid ([vosreponses](https://vosreponses.com/comment-sinscrire-dans-un-lycee-public-au-cameroun/),
  [generic model](https://lettre-modeles.com/certificat-de-scolarite/)). 🟡
- **Exeat / certificat de départ** — attests that the student leaves the school and owes it nothing
  (French practice; [IntendanceZone](https://www.intendancezone.net/spip.php?article21=)). In Cameroon
  the transfer itself is recorded on CarteScolaire. ⚠️
- Certificates of success, diploma rectification or loss are **ministry** procedures (RDSE/MINESEC),
  not school papers ([actes certificatifs](https://www.minesec.gov.cm/web/index.php/en/constitution-des-dossiers-en/actes-certificatifs-en)). ✅
