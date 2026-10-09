# Pilotage redesign (dashboard, séquences, bulletins, councils, corrections, notifications) — design

Date: 2026-10-09
Status: approved in conversation, awaiting written-spec review
Mockup: claude.ai/design project « Tableau », file `Pilotage.dc.html`
(screens `#dashboard`, `#sequences`, `#bulletins`, `#bulletin`, `#councils`, `#council`,
`#corrections`, `#notifications`).
Follows: `2026-10-09-enseignant-redesign-design.md` (cycle 4).

## Goal

Bring the eight Pilotage screens to the mockup. Every screen keeps its route, its rights
and its menu entry: `/school` (Proviseur dashboard), `/school/sequences`,
`/school/bulletins`, `/school/classes/:id/students/:enrollment_id/bulletin` (+ its print
route), `/school/councils`, `/school/councils/:class_id` (+ PV print),
`/school/corrections/review`, `/school/notifications`. Desktop and 390 px; FR + EN.
The space structure is unchanged: the dashboard stays Proviseur-only, the Censeur keeps
`/school/sequences` as home.

Out of scope (deferred): SMS (no SMS channel exists — reminders are in-app
notifications only), the global top-bar search, the « Synchronisé » chip, the
correction explanation text (decided out in cycle 4), the fees « Recouvrement » KPI
(Intendance cycle), publishing séquence bulletins, multiple distinctions per student.

## Decisions

| Question | Decision |
|---|---|
| Séquence bulletins | Séquence tabs on the bulletins page are read-only (ranked list, side card); publishing stays trimester/year |
| Council scheduling | New date + time per council, « Planifier » action; statuses À planifier / Planifié / Tenu / Clôturé |
| Council decisions | Single-select chips over the existing single distinction choice |
| Fees KPI | Left out; four KPI cards |
| New notifications | All four: bulletins publiés, appels non faits (digest), mot de passe temporaire expiré, nouveau membre |
| Features the mockup omits | Kept, in secondary places (disclosure, below main content, checklist only while setup is incomplete) |
| Refusal reason | Required when refusing a correction; optional when accepting |
| Report card content | Configurable per school: the new bulletin pieces are new `BulletinElement` values, toggled on the existing template page |

## 1. Data and domain

### 1.1 Council scheduling

- `ClassCouncil` gains `starts_at` (`:time`, nullable). `held_on` (date) stays the
  council's date.
- New `:schedule` action (accepts `held_on`, `starts_at`), same policy as the existing
  council update. `Councils.schedule(scope, class_group, period, date, time)` creates
  the council row when absent.
- Derived status, one function in `Councils` used by the list and the council page:
  - `:to_plan` — no council row, or no `starts_at` (scheduling always sets date and
    time; a council created early by a decision save carries only the term's default
    date, which does not count as planned);
  - `:planned` — `starts_at` set, status `:open`;
  - `:held` — status `:held`, the period's bulletins not published;
  - `:closed` — status `:held` and the period's bulletins published for the class.
- « Clôturer le conseil » is today's « Marquer le conseil tenu », renamed; « Rouvrir »
  stays. The term default date still pre-fills the « Planifier » form.

### 1.2 Correction refusal reason

- `MarkCorrection :refuse` validates that `decision_note` is present (after trim);
  `:approve` keeps it optional. Error surfaced in the review card.

### 1.3 Notifications

New `NotificationKind` values, each with FR/EN texts:

| Kind | Trigger | Recipients | Title · detail (FR) |
|---|---|---|---|
| `bulletins_published` | `ReportCards.publish/3` succeeds | the class's form master + teachers of its courses, minus the publisher | « Bulletins <période> publiés » · « <classe> · par <nom> » |
| `missed_roll_calls` | Oban cron, school days at 12:30 and 17:30 (Africa/Douala); skips days off/holidays; nothing when all done | members with role `:head` or `:discipline_master` | « N appel(s) non fait(s) ce matin / cet après-midi » · « 6e B 08:25 (Brice Tabi) · 3e A 09:20 (…) » |
| `temporary_password_expired` | Oban cron, daily 07:10; accounts whose `temporary_password_expires_at` fell in the last 24 h and `must_change_password` is still true (the window reports each once, no new column) | the school's admins (`:head`, `:vice_principal`) | « <nom> n'a pas utilisé son mot de passe temporaire » · « Expiré le <date> » |
| `member_joined` | `Accounts.accept_invitation/2` succeeds | the school's admins, minus the newcomer | « <nom> a rejoint l'établissement » · « Compte lié · <rôles> » |

- Workers: `TeacherAssistant.Workers.MissedRollCalls` and
  `TeacherAssistant.Workers.ExpiredTemporaryPasswords` (`use Oban.Worker`), registered
  in the existing `Oban.Plugins.Cron` config; each iterates every verified school
  workspace and builds a system scope for it. These are the app's first workers.
- `NotificationText` returns `{title, detail}` for every kind (existing four included:
  e.g. correction requested → « <enseignant> demande une correction de note » ·
  « <élève> · <classe> · <matière> · 08 → 13 »).

### 1.4 New reads (no new data)

- `Attendance` (or `SchoolLife`): `day_roll_call_counts(scope, date, now)` →
  `%{expected, done, missed: [slot]}`, extracted from `DayLive`; used by the dashboard
  and the digest.
- `Attendance`: `absences_to_justify(scope)` → `%{count, over_threshold}`, extracted
  from `Spaces.counts(:surveillant)`; used by the dashboard and the menu badge.
- `EntryProgress`: the « à relancer » list becomes every course under 100 % with
  students, grouped by teacher: `%{teacher, subject, classes: [%{label, pct, tc_id}]}`.
  `late_teacher_count`, the menu badge, `Assessment.remind_late/2` and a new
  `Assessment.remind_teacher(scope, seq, teacher_id)` all use it. Reminder dedup
  (once per course, séquence and day) unchanged.
- Dashboard to-do: classes without a form master; subjects without a teacher
  (`Curriculum.assignment_overview/1` cells of kind `:to_assign`); accounts awaiting
  first sign-in (`must_change_password`, with the expired count); councils to plan
  (§1.1, current term).
- Bulletin data (`Bulletins`): per-subject teacher (teaching context teacher's display
  name) added; per-subject rank, class highest/lowest, repeater, form master and the
  verification code are already computed or loadable and are passed through.
- Pre-publish checklist (`ReportCards`): notes rate (existing `entry_rate`), subjects
  without a teacher for the class, conduct notes entered / effectif (Discipline
  `note_de_conduite` for the period's term), council date and status (§1.1).

### 1.5 Configurable report card

New `BulletinElement` values, labelled on the template page
(`/school/settings/bulletin`, existing checkbox list):

| Value | Shows | Default |
|---|---|---|
| `:subject_rank` | Rank of the student in each subject (« Rang » column) | on |
| `:subject_teacher` | Teacher's name under each subject | on |
| `:class_extremes` | Class highest and lowest general averages (« Classe » box) | on |
| `:repeater` | « Redoublant(e) : oui / non » in the identity block | on |
| `:form_master` | « Professeur principal : <nom> » in the identity block | on |
| `:parent_visa` | « Visa du parent » signature slot | on |
| `:verify_link` | « Vérifiable en ligne : <url>/<code> » next to the QR | on |

- `BulletinElement.defaults/0` includes them, so schools that never saved a choice get
  them. Schools that saved a list keep exactly their list (new elements off until
  ticked) — an explicit choice is respected; the template page shows them unticked.
- Existing elements (`:rank`, `:min_max`, `:class_average`, …) unchanged. The same
  element set drives the print and the on-screen bulletin (§2.4), and is stored in the
  publication snapshot as today.

### 1.6 Migration

One migration (generated with `mix ash.codegen --dev`, final name at the end):
`class_councils.starts_at`. Enum additions need none (stored as text).

## 2. Screens

### 2.1 Dashboard `/school` (Proviseur)

- Header: eyebrow « <jour date> · Séquence N · J-n » (current séquence, days to its
  entry deadline; parts omitted when absent), title « Bonjour, <nom> ».
- Four KPI cards, each a link:
  - « Saisie Séq. N » — overall % · « N enseignants à relancer » → `/school/sequences`;
  - « Appels aujourd'hui » — done / expected · « N non faits » → `/school/day`;
  - « Absences à justifier » — count · « N élèves au-delà de X h » → `/school/absences`;
  - « Corrections » — pending count · « en attente de décision » → review page.
  Value colour: green when nothing to do, amber otherwise, red for the entry KPI under
  60 %.
- « À traiter · N »: rows (coloured mark, title, sub-line, CTA button) shown only when
  their condition holds — corrections (« Décider », oldest date), late teachers
  (« Relancer », deadline), classes without PP (« Désigner » → class page), subjects
  without a teacher (« Affecter » → assignments), accounts awaiting first sign-in
  (« Voir » → members, « dont N expiré(s) »), councils to plan (« Planifier » →
  councils). Empty: « Rien à traiter ».
- « Saisie Séquence N par classe »: one horizontal bar per class (green ≥ 90 %,
  amber ≥ 60 %, red below), « Détail → » to `/school/sequences`.
- Kept: verification callout and the setup checklist only while setup is incomplete;
  « Mes cours » / « Mes classes » below, only when the head teaches / is form master.
  The three count stats are removed.

### 2.2 Suivi des séquences `/school/sequences`

- Header: eyebrow « Séquence N · saisie jusqu'au <date> (J-n) », title « Suivi de la
  saisie des notes ».
- Segmented séquence tabs labelled « Séq. N · close » (locked), « · en cours »
  (started, open), plain (future).
- Grid « Classes × disciplines »: ✓ when 100 %, % otherwise, « · » not taught; colours
  complete / in progress / not started; legend. Cell click opens the existing detail
  panel (kept).
- « À relancer · N »: one row per teacher — name, « <matière> · 6e A (60 %), Tle D
  (0 %) », « Relancer » → « Relancé ✓ » (from today's reminders); « Relancer tous ».
  Flash « N rappels envoyés. ». The KPI row is removed.

### 2.3 Bulletins `/school/bulletins`

- Header: eyebrow « Bulletins · <classe> », title « Bulletins ». Segmented class tabs
  and period tabs: séquences, trimestres, année.
- Published (trimester/year): banner « Publiés le <date> par <nom> · visibles par les
  professeurs principaux et imprimables. » + « Imprimer toute la classe ».
- Draft (trimester/year): banner « <Période> — pas encore publiés », checklist
  (✓ / ! per line): « Notes : N % saisies (N matière(s) sans enseignant) »,
  « Conduite : x / effectif notes », « Conseil de classe : prévu le … / tenu le … /
  à planifier »; « Publier les bulletins » with today's rules (held council required,
  confirmation under 100 %).
- Séquence tabs: read-only — no banner, no publish; list and side card only.
- Table: Rang (« 1er », « 2e »…), Élève, Moyenne (red under 10), Distinction; row click
  selects. Side card: name, « Ne / effectif · moyenne X », per-subject averages,
  « Ouvrir → ».
- Kept below the table: « Dépublier » with its reason and the publication history. The
  per-row print icon goes (print from the bulletin page or « Imprimer toute la
  classe »).

### 2.4 Bulletin (single student)

- Top bar: « ← Bulletins de la <classe> », « Fiche élève » (student page), « Imprimer ».
  Period select kept.
- The bulletin rendered as a paper sheet on screen by embedding the existing print
  document (`…/bulletin/print`, a standalone page with its own styles) in an
  A4-proportioned frame — one markup for screen and print: bilingual header with logo, period
  title, year; identity (name, class, effectif, matricule, birth, repeater, form
  master); subject table (subject + teacher, coef., mark /20, mark × coef.,
  appreciation, rank); totals, average, rank; boxes Discipline, Classe, Distinction;
  signatures (PP, parent's visa, head with name); QR + « Vérifiable en ligne ».
  Every optional piece follows the school's elements (§1.5). Council appreciation and
  passage render when present, as today.

### 2.5 Conseils de classe `/school/councils`

- Header: eyebrow « Trimestre N » (or « Année »), title « Conseils de classe »,
  summary « N classes · N tenus · N planifiés · N à planifier ». Term/year tabs kept.
- Table: Classe, Date (« Mar 14 oct. · 14:00 », « — » when to plan), Préparation
  (« Notes 72 % · conduite à saisir » or « Prêt »), Statut pill (À planifier amber,
  Planifié info, Tenu / Clôturé green), CTA: « Préparer » (planned/to plan with
  date) → council page, « Voir le PV » (held/closed) → PV print, « Planifier » (to
  plan) → inline date + time form in the row (pre-filled with the term date).

### 2.6 Conseil de classe `/school/councils/:class_id`

- Header: « ← Conseils de classe », eyebrow « <Trimestre N> · <jour date> · <HH:MM> »,
  title « Conseil de classe · <classe> », « Présidé par <président> · PP : <nom> »;
  actions « Imprimer le PV », « Clôturer le conseil » (→ « Conseil clôturé ✓ » +
  « Rouvrir »; confirmation under 100 % entry as today).
- Table: Élève, Moy. trim. (red under 10), Conduite (/20), Décision — single-select
  chips of the school's distinction choices, pre-selected from the proposal, disabled
  once held. Footnote: « Les propositions viennent des règles de l'établissement
  (Paramètres › Appréciations & distinctions). Le conseil peut les modifier ; après
  clôture, elles figurent sur les bulletins du trimestre. »
- « Détails du conseil » disclosure (closed by default): date + time, président,
  présents, observations, the stats, and per student the appreciation, conduct warning
  and (year council) passage — all existing fields, unchanged behaviour.

### 2.7 Corrections `/school/corrections/review`

- Header: eyebrow « Censorat · intégrité des notes », title « Corrections de notes »,
  subtitle « N demande(s) en attente · une note ne change qu'après votre décision ».
- Pending as cards: student; « <classe> · <matière> · Séquence N · <évaluation> »;
  large « 08 → 13 »; séquence average before → after; motive chip; « Demandée par
  <nom> · <quand> »; optional « Note pour l'enseignant » + « Accepter »; « Refuser »
  reveals a required reason field and « Confirmer le refus ». Empty: « Aucune demande
  en attente. »
- « Journal des notes » under the cards (« Toute modification après verrouillage est
  tracée. »). Decided requests stay on a « Traitées » tab.

### 2.8 Notifications `/school/notifications`

- Rows: title (bold when unread), detail line, time right-aligned; unread with an amber
  dot and tinted background; « Tout marquer comme lu », paging kept. The bell dropdown
  uses the same title/detail.

## 3. Testing

- Domain: council `schedule` and derived status (no council, no date, open, held,
  held + published; non-admin refused); refusal without note rejected, approval
  without note accepted; late list groups a 60 % and a 0 % course of one teacher, and
  badge / remind-all / per-teacher reminder agree, reminders not repeated the same
  day; each new notification's recipients and texts (publisher and newcomer excluded);
  digest worker: one notice when calls are missed, none when all done, none on a
  holiday; password worker: an account expired in the window reported once, a used
  one never; extracted day and absence counts equal the previous figures; new
  bulletin elements default on for schools without a saved list, off for schools with
  one.
- LiveView: dashboard KPIs and links, each to-do row only when its condition holds,
  checklist hidden once set up; séquence tab states, ✓, partial courses listed,
  « Relancer » → « Relancé ✓ »; bulletins draft banner + checklist, séquence tab
  without publish, ordinal ranks, withdraw/history still work; bulletin shows teacher,
  subject rank, extremes, verify link, and hides each when its element is off;
  councils status pills, CTAs, inline « Planifier » saves; council chips save and lock
  after « Clôturer », disclosure fields still save; corrections cards, refuse asks a
  reason; notifications two-line rows for each kind.
- Gettext: new strings extracted and translated, no fuzzy entries left. Browser pass at
  desktop and 390 px with the demo seed as head and as Censeur.

## 4. Risks and order

- First Oban workers: production needs Oban running with the cron entries; tests use
  `testing: :manual` and `perform_job/2`.
- The print document gains columns/blocks only behind new elements; output for
  elements already shown today stays identical (print tests stay green).
- Oban is configured but not started today: the supervision tree gains it.
- Size: the largest cycle so far. Order of work: data and notifications → corrections,
  notifications, séquences → dashboard → councils list, council → bulletin elements,
  bulletin, bulletins list → translations, final migration, browser pass.
