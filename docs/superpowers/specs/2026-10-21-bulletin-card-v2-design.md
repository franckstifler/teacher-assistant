# Report card & ID card v2 — design

Status: decisions taken in chat 2026-10-21, builder check done; awaiting the user's
review of this document.

Mockups (to scale, browser-checked): `.superpowers/brainstorm/10224-1792620719/content/`
— `bulletin-onepage.html` (APC 3rd-term card, 15 subjects, fits A4) and
`idcard.html` (option **A** chosen).

## 1. Why

A real Cameroonian report card (Lycée Technique de Ngog-Mapubi, APC model, 3rd term
2024/2025) and a real school ID card were compared with ours. Ours miss what makes a
paper look *official* to parents and inspectors (school code, bilingual header in two
columns, title naming the period), the APC competences some schools use, and — the
hard rule — **a report card always fits on one A4 page**. Ours currently spills to a
second page for a class with ~15 subjects (12pt serif, roomy cells, prose lines).

The ID card has the right data but lacks the national look (header, flag, title) and
the principal's name.

## 2. Goals, non-goals, anti-goals

Goals
- Every printed report card fits **one A4 page**, whatever the school ticked.
- Official look on both documents: FR header left / EN header right, logo + school
  code between them, school name in both languages, flag stripe.
- APC mode: one competence per subject per sequence, written by the teacher.
- Term 2 and 3 cards carry the earlier terms; the term 3 card is the end-of-year card.
- Each new piece is a school choice in the existing element list.

Non-goals
- No new report-card *models* or a template designer; one layout, elements toggled.
- No back side on the ID card (user chose option A).
- No change to how averages, ranks or passage are computed.
- The separate annual report card is **kept as it is** (my call): nothing removed,
  nothing new added to it, no competences on it.

Anti-goals (would be a failure even if it "works")
- A card that prints on two pages, or a page whose last box is cut.
- A published card changing after publication (snapshots stay frozen).
- APC chrome (competences, Cote, cotes box) appearing at a school that doesn't do APC.
- Blocking a teacher from entering marks because the competence isn't written.

## 3. User decisions

| Topic | Decision |
|---|---|
| Competence granularity | **Per sequence**, per subject (teaching context). |
| When written | Before entering marks of the sequence, **when APC is on**. Not blocking: a reminder. |
| Term 2 / term 3 content | T2 shows the T1 average; T3 shows earlier terms + annual average and the decision. |
| End-of-year card | **The term 3 card** is the only end-of-year card schools hand out. |
| What shows | Each school chooses; new pieces join the existing element list. |
| One-page layout | Mockup approved as the target. |
| ID card | **Option A**: everything on the front. |

## 4. Data

### 4.1 School profile (`TeacherAssistant.Accounts.SchoolProfile`)

New attributes (all optional strings, public, trimmed, blank → nil):

- `school_code` — the MINESEC establishment code (e.g. `5MN1TEF110431106`). Printed as
  « CODE : … » under the logo on the card and in the ID card's contact line. Distinct
  from `registration_number` (private-school opening authorisation, unchanged).
- `name_en` — the school's English name (e.g. « G.T.H.S Ngog-Mapubi »). Blank → the
  English column repeats the workspace name.
- `official_header_lines_en` — `{:array, :string}`, the English counterpart of
  `official_header_lines` (the school's own national lines, spec KLM6).

Edited where their neighbours are: `school_code` and `name_en` with the school
identity fields (settings), `official_header_lines_en` on the official-header page
next to the French lines (generated English lines as the starting value, « reset »
clears both). PO Box and several phones stay in the free-text `address` / `phone`
fields — no new fields (my call).

### 4.2 Student (`TeacherAssistant.Academics.Student`)

- `national_id` — optional string, the national *Identifiant unique* from
  cartescolaire.cm. `matricule` stays the school's own number. No uniqueness
  constraint (my call: typos must not block enrolment). Editable wherever `matricule`
  is; included in `plain_entry/1` so it is frozen in snapshots.

### 4.3 Competences — new resource `TeacherAssistant.Academics.SequenceCompetence`

| Field | |
|---|---|
| `teaching_context_id` | belongs_to, required |
| `sequence_id` | belongs_to, required |
| `text` | string, required, trimmed, max 140 chars |
| workspace multitenancy | like `Assessment` |

Identity: unique `(teaching_context_id, sequence_id)`; the write is an upsert.
Policies: write — the context's teacher, or the school's admin axis (same rule as
entering marks on that context); read — any active member.

### 4.4 Bulletin elements (`BulletinElement`)

New values:

| Element | Shows |
|---|---|
| `:apc` | Competence lines, Cote column, cotes box (§5.3), and the mark-entry reminder (§6). |
| `:previous_terms` | Earlier terms' averages (and ranks if `:rank`) in the *Travail de l'élève* box. |
| `:annual_summary` | On the term 3 card: annual average, annual rank, decision (§5.5). |
| `:guardians` | Parents / guardians with phones in the identity block. |
| `:national_id` | « Identifiant unique » next to the matricule. |
| `:class_profile` | « Moyennes ≥ 10 » count and success rate in the class profile box. |
| `:teacher_visa` | Empty « Visa » column per subject. |

`defaults/0` becomes `values() -- [:qr_code, :apc]` — APC is never on by surprise.
Schools that saved their list keep it exactly (existing rule), so the new elements are
off for them until ticked.

Always printed when filled, not elements (my call): school code, two-column header,
English name, flag stripe, period in the title.

## 5. The report card

One layout, the mockup's. Order top to bottom:

### 5.1 Header (every card, whatever the language)

Three columns: **French national lines** left, **logo + « CODE : <school_code> »**
centre, **English national lines** right. Lines are the school's own when saved
(`official_header_lines` / `_en`), else the generated ones in each locale. Under
them, the school name left (French) and right (`name_en`), each with address/BP and
phone. Then a thin green-red-yellow stripe.

This replaces today's rule where a French card shows one centred French column and a
school's custom lines force one column.

### 5.2 Title and identity

- Title: « BULLETIN SCOLAIRE DU PREMIER / DEUXIÈME / TROISIÈME TRIMESTRE » (annual
  card: « BULLETIN ANNUEL »), with « Année scolaire 2024/2025 » under it. Bilingual cards
  use the same « fr / en » rule as today.
- Photo left of a compact identity table: name, class, birth date & place, sex,
  national ID (if element), matricule, effectif, repeater, form master,
  parents/guardians with phones (if element). Guardians = the student's guardian links
  in the existing order (main contact first), at most two, frozen in the snapshot.

### 5.3 Subject table

Columns: Matière + enseignant · *Compétences évaluées* (APC) · N/20 · M/20 · Coef ·
M×Coef · *Cote* (APC) · Min–Max · Rang · Appréciation · *Visa* (if element). Columns
for elements that are off disappear, as today.

- **APC on, trimester card:** each subject is one line per sequence of the term (two in
  the usual calendar — the template must read the term's sequences, not hard-code two
  as `show.html.heex` and `comp/3` do today): « Seq n · <competence> » and that
  sequence's mark. M/20, Coef, M×Coef, Cote, Min–Max,
  Rang, Appréciation, Visa span both lines. Missing competence → empty cell.
- **APC off, trimester card:** one line per subject with both sequence marks side by
  side (today's columns).
- **Annual card:** unchanged column set; never competences.
- **Sequence card** (draft view, not publishable): one line per subject with that
  sequence's competence when APC is on.
- **Anglophone classes** (graded by letter, `grading: :grade`): APC shows the
  competence lines only; no Cote column and no cotes box — the existing Grade column
  already plays that role (my call).
- **Cote** = the appreciation band's short code. To support it, `AppreciationBand`
  gains an optional `code` (e.g. « CBA ») next to `label` (« C. bien acquise »); the
  appreciation column prints the label, the Cote column the code. An « APC » preset
  button on the appreciation-bands settings fills: CTBA ≥ 16 « C. très bien acquise »,
  CBA ≥ 14 « C. bien acquise », CA ≥ 12 « C. acquise », CMA ≥ 10 « C. moyennement
  acquise », CNA < 10 « C. non acquise » (thresholds editable afterwards; my call on the
  numbers — the builder may adjust if the domain notes say otherwise).
- Group sub-totals keep working as today when the school uses them.
- Footer row: total coefficients, total points, the period's average.

### 5.4 Four boxes (replace today's prose lines)

1. **Discipline** — absences unjustified / justified (h), lateness, detentions
   (count, as today's `consignes_count` — no hours, my call), warning, blame,
   exclusion (days), conduct mark. Same data and element gates (`:absences`,
   `:conduct`) as today.
2. **Travail de l'élève** — this period's average and rank; with `:previous_terms`, the
   earlier terms' averages (and ranks); with `:annual_summary` on term 3, the annual
   average and rank.
3. **Cotes** (`:apc`) — count of subjects per Cote code for this student.
4. **Profil de la classe** — class average, min–max of averages (`:class_extremes`),
   with `:class_profile` the number of students averaging ≥ 10 and the success rate
   (that number / students with an average, as %).

Then a row: council appreciation (left) · distinction and decision (right). Then the
signature row: parent · form master (name printed) · head (stamp, signature,
« Fait à <town>, le <publication date> ») · QR. « Page 1 / 1 » is not printed (mockup
only).

### 5.5 Earlier terms and the end-of-year card

- Earlier terms' figures come from **that term's published snapshot** when there is
  one (what parents already saw), else computed live; a term with nothing → « — ».
- On term 3 with `:annual_summary`, the annual average and rank come from the annual
  results (`Assessment.class_results_for_period(scope, cg, {:annual, year})`) and the
  decision from the **annual council's** outcome (passage), as the annual card shows
  today.
- **Publishing term 3 with `:annual_summary` requires the end-of-year (annual)
  council to be held** (user decision, 2026-10-21), so the printed decision is the
  council's, never the engine's proposal. `publish/3` refuses with a new error
  (e.g. `:annual_council_not_held`) and the publish checklist shows the missing
  council as a blocking line. Without `:annual_summary`, term 3 publishes as today.
- Publishing term 3 with `:annual_summary` also **locks the annual council** as
  publishing the annual card does today: `Councils.locked?/3` for the annual period
  (`councils.ex:56-58`, derived from the publication in force) also returns true while
  a term 3 publication whose snapshot carries the annual summary is in force. The
  frozen term 3 card and later edits cannot disagree; withdrawing that publication
  unlocks it (my call).
- All of it is computed at publication and stored in the snapshot (new keys, read with
  `Map.get` for older snapshots, as the existing code does).

### 5.6 One page, always

- Print CSS: A4, ~10 mm margins, sans-serif (Plex Sans as the ID card), base ~7.5pt,
  tight cells; boxes rather than prose.
- **Density tiers chosen on the server** from the number of subject lines (APC doubles
  them) and the identity rows shown: e.g. normal / compact / dense, each a CSS class
  that lowers font size and padding. No client-side JS (house rule: no inline scripts).
  The builder sets the thresholds by measuring in the browser.
- Free text is capped on the page so it cannot push the layout: a competence prints
  on one line (ellipsis), the council appreciation on at most two lines.
- Beyond what the densest tier holds (estimated from the same line counts), the
  publish checklist shows a **non-blocking warning** « Bulletin trop long pour une
  page » naming the cause (subject count); nothing is dropped automatically (my call).
- Acceptance: an APC term-3 class with **18 subjects** and every element ticked prints
  on one page, measured in the browser like the mockup (`.paper` content bottom inside
  the A4 box), in FR, EN and bilingual. A technical class with its full general +
  technical subject list (`school_templates.ex`) is measured too.
- **All period kinds share the v2 layout** (one template): header, title, identity,
  boxes, density tiers apply to sequence, trimester and annual cards alike; only the
  subject columns differ by period kind (my call).

## 6. Writing competences (teacher side)

In the teacher's mark entry (`TeacherWeb.MarksLive`), when the class's school has
`:apc` ticked:

- Above the marks for a sequence: a one-line field « Compétence évaluée (séquence n) »
  with the saved text, saved on blur / submit (upsert).
- If it is empty when the teacher starts entering marks: a dismissible reminder
  (« Écrivez la compétence évaluée — elle figure sur le bulletin »). Marks are never
  blocked.
- A combined course has one teaching context per member class (linked by
  `combined_course_id`). The teacher writes the competence once; saving upserts one
  row per member context (my call), so each class's card and checklist read their own
  context as usual.
- The results/publish screen of the class lists subjects with a missing competence
  for the period as a **non-blocking** checklist line (existing `publish_checklist/3`).

## 7. ID card (option A)

Same print page (`CardPrintController`, 10 cards per A4, 85.6 × 54 mm). Front only:

1. Flag stripe.
2. FR national lines (short: République du Cameroun · Paix – Travail – Patrie ·
   MINESEC · DR … · DD …) left, logo centre, EN lines right.
3. School name, BP / phones, « Code <school_code> ».
4. Title band « CARTE SCOLAIRE · SCHOOL IDENTITY CARD ».
5. Photo · name · born on / at · class · sex · matricule · national ID (when set) ·
   guardian contact (as today).
6. Right column: school year badge, QR code.
7. Bottom right: stamp + signature images, the head's title and name.
   - Title by `SchoolType` (new pure helper, also used for the bulletin's head visa):
     `:lycee`, `:lycee_technique` → « Le Proviseur »; `:ces_ceg`, `:cetic`, `:sar_sm`
     → « Le Directeur »; English always « The Principal »; anglophone types (`:gss`,
     `:ghs`, `:gbss`, `:gbhs`, `:gtc`, `:gths`) print « The Principal » only.
     (Per docs/domain/05 §1; `:sar_sm` → Directeur is my call.)
   - Name: `SchoolProfile.head_name` when set, else the first member with the
     `:head` role (today's bulletin source) — one helper for both documents.

Field labels follow the existing language rule (FR / EN / bilingual).

**Card QR** → `GET /verify/card/:token`, token built like `BulletinVerification`
(HMAC over `{workspace_id, enrollment_id}`, own salt). The public page shows only:
school name, student name, class, academic year, and whether the enrolment is still
active. No photo, birth date or contacts (my call: minors' data on a public URL).

## 8. Translations

Every new string through gettext (FR source, EN filled). Fill and unflag every fuzzy
entry after `extract --merge` (guard test exists).

## 9. Testing

- Resource tests: `SequenceCompetence` upsert, identity, policies (teacher of the
  context, admin, other teacher refused); `SchoolProfile` new fields; `Student.national_id`.
- Template tests: header always two columns; custom FR + EN lines; code / English name
  printed; APC off → no Compétences/Cote/cotes box; APC on → two lines per subject with
  the competence text; previous terms on T2/T3; annual summary only on T3.
- Publish: term 3 with `:annual_summary` refused until the annual council is held,
  then allowed and locks the annual council; without the element, unchanged.
- Snapshot tests: published card unchanged after a competence / national ID / guardian
  edit; old snapshots (no new keys) still render.
- Density: tier chosen from line counts (unit test of the pure function).
- Card: new header / title / head name; QR verification valid, tampered token rejected,
  page shows no birth date or photo.
- Mark entry: reminder shown when APC on and empty, absent when APC off, never blocks.
- Visual pass in the browser (demo seed): one-page measurement per §5.6.

## 10. Open questions for the user

None. Term 3 vs the annual council was answered (§5.5).

## 11. Left to the builder

Exact density thresholds and font sizes; module placement for snapshot helpers; the
settings UI layout for the new fields and the APC preset button; how the
« Seq n » label reads on English cards (« Seq n »).
