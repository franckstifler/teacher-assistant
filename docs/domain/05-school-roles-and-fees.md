# 05 — School Roles, Councils, Teachers, Fees & Enrollment

*Confidence legend in [`README.md`](README.md). Source URLs inline.*

**Canonical legal source for roles & councils:** **Décret N° 2001/041 du 19 février 2001** (organization
of public schools + attributions of school-administration officials), published in **both French and
English** (Art. 57). Use it as the authoritative role list.
([full text](https://www.camerlex.com/cameroun-decret-n-2001041-du-10-fevrier-2001-portant-organisation-des-etablissements-scolaires-publics-et-fixant-les-attributions-des-responsables-de-ladministration-scolaire/))

## 1. Roles — bilingual map (load-bearing for the data model) ✅

| French | English (Anglophone CM) | Scope |
|---|---|---|
| Chef d'Établissement | Head of School | umbrella term |
| Proviseur (lycée) / Directeur (collège) | Principal | head of school |
| Censeur | Vice-Principal | deputy; **pedagogy + discipline**; builds timetables |
| Surveillant Général (SG) | (Senior) Discipline Master | **student discipline + attendance** |
| Surveillant de Secteur | Sector Discipline Master | assists SG |
| Intendant / Économe | **Bursar** (Agent Financier) | **finances/fees** |
| Animateur Pédagogique (AP) | **Head of Department (HOD)** | subject coordination; supervises subject teachers |
| Chef des Travaux | Head of Works | technical schools |
| Professeur Principal | **Form Master / Class Master** | per-class follow-up (compiles bulletins, leads class council for his class) |
| Conseiller d'Orientation | Guidance Counsellor | careers/guidance |
| Documentaliste | Librarian | library |

### Key responsibility lines
- **Head (Proviseur/Directeur/Principal):** administrative, pedagogical, educational AND financial
  responsibility; authority over all personnel; **grades the staff**; presides every council
  **except** the Conseil d'Établissement (there he is only Rapporteur). ✅
- **Censeur / Vice-Principal:** applies pedagogical regulations school-wide + discipline; draws up
  **timetables**. Bilingual schools have one deputy per FR/EN sub-section. ✅
- **Surveillant Général:** "maintenance of order and discipline"; owns day-to-day **student
  discipline + attendance**. ✅
- **Animateur Pédagogique / HOD:** leads the **Conseil d'Enseignement** (all teachers of one
  subject); supervises and coordinates the teachers *of his subject*; liaison to inspection. ✅
- **Bursar / Intendant:** opens accounts, executes spending, **collects all fees** (Régisseur des
  recettes), pays bursaries, reports to the school board. ← maps to the fee module. ✅
- **Professeur Principal:** statutory member of the Conseil de Discipline for his class; ⚠️ the
  decree names the role but does **not** enumerate duties — class-follow-up is established practice.

> **App distinction to enforce:** **pedagogical** follow-up of teachers (Censeur school-wide + HOD
> per subject + external Inspecteurs) is *separate* from **disciplinary** follow-up of students
> (Surveillant Général, escalating to Conseil de Discipline). Discipline over *staff* rests solely
> with the Head — there is no in-school body that disciplines teachers. Design permissions around
> these two axes.
>
> ⚠️ **Secretary/Registrar is NOT a decreed office** — model it as a custom/optional role.

## 2. Councils ✅

- **Conseil de Classe (Class Council)** — Art. 29. Presided by the Head; includes Censeur, SG, the
  class's teachers, Conseiller d'Orientation, 2 student + 2 parent delegates. **Decides
  orientation, promotion (passage), repetition (redoublement), or exclusion**; awards distinctions.
  ⚠️ Specific average thresholds for promote/repeat sometimes cited are from an Ivorian source —
  verify against the actual règlement intérieur before hard-coding numbers.
- **Conseil de Discipline (Disciplinary Council)** — Art. 30. Head + Censeur + SG + Chef des Travaux
  + Professeur Principal of the class. Sanctions: avertissement → blâme → exclusion temporaire →
  exclusion définitive.
- **Conseil d'Établissement (School Board)** — governance body (≤28 members); adopts school project,
  budget, internal rules; the Head is **Rapporteur**, not president.

## 3. Teacher ↔ School relationship — MANY-TO-MANY ✅

- **Grades:** general-education **PCEG** (lower-sec) / **PLEG** (upper-sec); technical **PCET / PLET**.
  Diplomas DIPES/DIPET I & II from the ENS/ENSET. Public teachers are civil-service Category A.
- **Status types:** **titulaire** (tenured civil servant), **contractuel**, **vacataire**
  (non-civil-servant, often APEE-funded, low wage). Model this.
- **Posting:** public teachers are **posted to a school by ministerial act** (affectation/mutation).
  Private teachers are **hired directly** by the school's *promoteur* (each needs an *autorisation
  d'enseigner*). So "teacher belongs to school" differs by sector.
- **Teaching load:** ⚠️ commonly ~**18–20 h/week** of class (statutory per-grade figure
  unconfirmed) — make configurable. Student timetable ≥35 h/week, ≥900 h/year over 36 weeks.
- **Multiple schools:** legally allowed (the civil-service ban on private lucrative activity
  **exempts "supplementary teaching"**) and common given the teacher shortage (>45,000 gap).
  **→ Model teacher↔school as many-to-many** with per-membership role(s) and status.

This validates the product's **personal vs school workspace** idea: a teacher exists independently
and may be attached to zero, one, or many schools.

## 4. School fees

**Fee types (FR/EN):** frais de scolarité / tuition · frais d'APEE / PTA fees · frais d'inscription
(registration) · réinscription · frais d'examen / exam fees. Model as **separate fee types**.

- **Public tuition** ⚠️ reported ~**7,500 FCFA (1er cycle) / 10,000 (2nd cycle)** (2022-23); figures
  are not crisp across sources (APEE is often bundled in).
- **APEE capped at max 25,000 FCFA** (Minister, Sept 2021) ✅ — but practice varies ~12,500–30,000. ⚠️
- **Exam fees** ⚠️ reported BEPC 11,000 / Probatoire 19,500 / Bac 20,500 FCFA (reverify against a
  MINESEC communiqué). Primary exam registration raised to 6,000 FCFA (Jan 2023).
- **Private secondary:** ~**100,000–300,000 FCFA/year**, highly variable. ✅

**APEE = Association des Parents d'Élèves et Enseignants (PTA).** Funds **pay vacataire teachers**,
infrastructure, materials — filling state-budget gaps. Legally "voluntary contributions," but
enforced in practice as a de facto enrollment condition (~74% of households treat them as
compulsory). ⚠️ Periodically "suspended" by communiqué — model a **per-year waived/suspended flag**;
do not encode suspension as permanent.

## 5. Fee-based access control ("chasse aux élèves") — the user's explicit requirement

- **Sending non-payers home / barring from class is real practice**, most aggressive in
  **private/confessional** schools (e.g. ≥50% of tuition required before 2nd term; place
  auto-revoked after a deadline). ✅
- **Barring specifically from sequence EXAMS** for non-payment is **widely reported but thinly
  documented** ⚠️ — treat exam-gating as plausible-but-grey. **Make exclusion configurable and
  overridable, never automatic/hard-coded.**
- **Installments (tranches)** are the billing norm: échéanciers with deadlines and % thresholds
  (e.g. 50% before a term). Model **multi-tranche schedules with per-tranche deadlines + % gates.**
- **Tracking payment:** trending electronic — official fees tie to the **matricule unique** + PIN,
  paid via Campost/MTN/Orange Money/SchoolPay on
  [cartescolaire.cm](https://www.cartescolaire.cm/faq) / [schoolpay.cm](https://schoolpay.cm/);
  students show a **reçu**. **Anchor receipts to the unique matricule.** ✅
- ⚠️ **No Cameroonian circular explicitly prohibits** sending students home / barring from exams
  for unpaid fees (unlike neighboring Benin). The legal baseline is free/compulsory public *basic*
  education only.

> **Product stance:** the access-control feature is legitimate and demanded, but because exam-gating
> is legally grey, model it as a **school-configured policy with explicit overrides and an audit
> trail** (reason, set-by, set-at) rather than an automated lockout.

## 6. Enrollment ✅

- **Matricule unique:** since 2024-25, a **national** unique student ID required to enroll in any
  secondary school; identifies the student throughout secondary; obtained on cartescolaire.cm.
  Without it: no fee payment, no official-exam registration, no insurance/FENASCO. ⚠️ exact
  format/length & assigning authority unspecified.
- **inscription** (first) vs **réinscription** (re-enrollment); MINESEC publishes annual *modalités
  d'inscription*.
- **Class lists:** *liste de classe* = roster; *effectif* = headcount/class size.
- Students assigned to a class and (from 2nde / Lower Sixth) a **série/stream**.

## Implications for the product
1. **Roles = Décret 2001/041 list**, with FR + EN labels; ship a fixed role catalog + an optional
   custom role (Secretary/Registrar). Permissions split on **pedagogical vs disciplinary vs
   financial** axes.
2. **Teacher↔School many-to-many**, per-membership role(s) + status (titulaire/contractuel/vacataire,
   public-posting vs private-hire). Confirms the personal-workspace-first design.
3. **Fees:** separate fee types · multi-tranche schedules with deadlines & % thresholds · per-year
   waived/suspended flags · receipts anchored to matricule · mobile-money/SchoolPay receipts.
4. **Access gating** at two levels (campus/class entry; exam sitting) — **configurable + overridable
   + audited**, not automatic.
5. **Reverify before hard-coding any number:** tuition, exam fees, teaching load, promotion
   thresholds — all soft. Confirm against current MINESEC communiqués and the school's own
   règlement intérieur.
