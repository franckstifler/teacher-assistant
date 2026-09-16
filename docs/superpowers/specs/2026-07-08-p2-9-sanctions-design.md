# P2.9 — Sanctions & note de conduite

**Status:** Approved design
**Date:** 2026-07-08
**Builds on:** P2.1 (school workspaces, roles, permissions), P2.2 (students / enrollments), P2.5 (form-master scoped access), P2.6 (bulletin period abstraction), P2.8 (attendance, conduct section G, `discipline_master?`/`conduct_manager?`, `period_date_range/1`)

## Purpose

Complete the discipline layer: let the Surveillant Général (the `conduct_manager?`
roles) record a student's disciplinary **sanctions** (the section-G ladder:
avertissement → blâme → exclusion temporaire → exclusion définitive, plus consignes)
and an optional **note de conduite** (/20), and surface both on the bulletin's Conduite
section alongside the P2.8 absence hours + retards. Conduct remains **display-only** —
nothing here enters the moyenne générale.

## Scope

In scope:
- A flat per-student sanction log (type, date, reason, exclusion duration, issuer).
- An optional per-student per-séquence note de conduite (/20), display-only.
- A dedicated per-class discipline page to record/manage both.
- Extension of the P2.8 bulletin Conduite section (screen + print) with sanctions,
  consignes count, and note de conduite.

Out of scope (deferred / YAGNI):
- No Conseil de Discipline / Conseil de Classe meeting workflow — we record the
  outcome (the sanction), not the deliberation, membership, or votes.
- Exclusions are records only: they do **not** auto-generate attendance absences and
  do **not** bar exam/class access (fee- and exam-gating is a separate future area).
- Note de conduite never enters the moyenne générale (kept off, per the KB's
  unsettled flag and P2.8's stance).
- No parent notifications / SMS.
- No incident→sanction two-tier model; no appeal/revision history beyond delete.

## 1. Data model

One `Ash.Type.Enum` and two resources (Ash 3 house style: `use Ash.Resource,
otp_app: :teacher_assistant, domain: TeacherAssistant.Academics, data_layer:
AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]`; `policy always() do
authorize_if always() end`; `uuid_v7_primary_key :id`; `timestamps()`; FK `on_delete`
inside `postgres do ... references do ... end end`).

**Enum**
- `TeacherAssistant.Academics.SanctionType` —
  `[:avertissement, :blame, :exclusion_temporaire, :exclusion_definitive, :consigne]`.

**`SanctionEntry`** — one disciplinary sanction for one student.
- `belongs_to :enrollment` (`allow_nil? false` — student×class×year), `type`
  `SanctionType` (`allow_nil? false`), `date :date` (`allow_nil? false`),
  `reason :string` (nullable), `duration_days :integer` (nullable — meaningful only
  for `:exclusion_temporaire`), `issued_by_user_id :uuid`, denormalized
  `workspace_id :uuid` (`allow_nil? false`, set from the class group).
- No identity beyond the primary key (a student can receive the same sanction type
  more than once).
- `references` with `on_delete: :delete` for `enrollment`.

**`ConductMark`** — the optional note de conduite, one per student per séquence.
- `belongs_to :enrollment` (`allow_nil? false`), `belongs_to :sequence`
  (`allow_nil? false` — the P2.2/P2.6 séquence), `value :decimal` (`allow_nil? false`,
  0–20), `recorded_by_user_id :uuid`, denormalized `workspace_id :uuid`.
- Identity `unique_conduct_mark [:enrollment_id, :sequence_id]` (one mark per student
  per séquence; re-entry upserts).
- `references` with `on_delete: :delete` for `enrollment` and `sequence`.
- An upsert-capable create action (identified by `:unique_conduct_mark`) for set/replace.

Both resources are registered in the `TeacherAssistant.Academics` domain. The note de
conduite is keyed per **séquence**; a trimester/annual figure is the mean of the
present séquence marks in range (mirroring how séquentiel averages roll up in P2.6).

## 2. Context — `TeacherAssistant.Academics.Discipline`

New module (all Ash calls `authorize?: false`, tagged tuples, workspace-scoped, never
leak raw Ash errors):
- `list_sanctions(class_group, period_tuple)` → the class's `SanctionEntry` rows whose
  `date` falls in the période's range (via `Academics.period_date_range/1`), newest
  first, with the student name loaded. `list_sanctions(enrollment, period_tuple)` → the
  same for one student.
- `add_sanction(enrollment, attrs, issued_by_user_id)` → `{:ok, entry} | {:error,
  term}`: validate `type` ∈ the enum (whitelist), set `workspace_id` from the
  enrollment's class group; `duration_days` accepted only meaningfully for
  `:exclusion_temporaire` (stored nil otherwise).
- `delete_sanction(sanction)` → `:ok | {:error, term}`.
- `set_conduct_mark(enrollment, sequence, value, recorded_by_user_id)` → upsert on
  `:unique_conduct_mark`; validate `0 ≤ value ≤ 20`. `clear_conduct_mark(enrollment,
  sequence)` → deletes the mark.
- `note_de_conduite(enrollment, period_tuple)` → `Decimal | nil`: for `{:sequence, s}`
  the séquence's mark; for `{:trimester, t}` the mean of that term's present séquence
  marks; for `{:annual, y}` the mean of the year's present séquence marks; nil when
  none.
- `discipline_summary(enrollment, period_tuple)` → `%{sanctions: [%SanctionEntry{}],
  consignes_count: integer, note_de_conduite: Decimal | nil}` — the section-G feed.
  `consignes_count` = count of `:consigne` entries in range; the `sanctions` list
  contains only the non-consigne ladder entries (avertissement / blâme / exclusion
  temporaire / définitive). The two are kept distinct because the bulletin shows them
  as two separate fields (a Consignes count and a Sanctions list).
- `class_discipline(class_group, period_tuple)` → per-enrollment summaries for the
  whole roster in scoped reads (for the discipline page + whole-class bulletin print).

Period→date-range and any hour math are reused from P2.8; this module adds no new
date logic.

## 3. Access

Reuses the P2.8 model exactly. `conduct_manager?/1` (SG / admin) adds and deletes
sanctions and sets/clears the note de conduite for any class in the workspace. The
class **form master** (`admin_or_form_master?/2`, true but not conduct_manager) gets a
**read-only** discipline view. Everyone else is redirected to `/school` with a flash.
Every surface resolves the class via `fetch_owned_class_group/2`, gates the mount, and
re-checks `conduct_manager?` in each mutating handler; the enrollment/sanction targets
come from socket-loaded collections (never raw client ids); the `type` arrives through
a whitelist (no `String.to_atom` on raw input); the note value is parsed/validated as a
bounded number.

## 4. UI — dedicated discipline page

`/school/classes/:id/discipline` (route in the `:school_workspace` live session):
- **Period selector** mirroring the results/bulletin pages (séquence / trimester /
  annual), driving what the log and note column show.
- **Sanctions log** — the class's sanctions for the selected période, newest first:
  student · type · date · duration (for exclusion temporaire) · reason · issued-by.
  Conduct managers get an **add-sanction form** (student `<select>` from the roster,
  type, date defaulting today, an optional duration input shown for
  `:exclusion_temporaire`, optional reason) and a per-row delete; the form master sees
  the log read-only (no form, no delete).
- **Note de conduite** — a per-student inline `/20` entry for the current séquence
  (conduct managers edit; form master read-only). When a trimester/annual période is
  selected the note column is read-only and shows the computed mean (marks are entered
  per séquence).
- Linked from the class-detail page, gated `:if` to `conduct_manager?(scope) or
  admin_or_form_master?(scope, class_group)`.

## 5. Bulletin section G (extends P2.8, display-only)

The Conduite section on `bulletin_live` and the bulletin print (single + whole-class)
gains, alongside the P2.8 absences (h) + retards:
- **Consignes** — the consignes count for the selected période.
- **Sanctions** — the période's non-consigne ladder entries, rendered as a short list
  (e.g. "Avertissement · Exclusion temporaire (3 j)").
- **Note de conduite (/20)** — shown when present, via `note_de_conduite/2`, formatted
  with the bulletin's existing numeric helper.
The moyenne générale and every existing bulletin figure are **unchanged**; the P2.3 /
P2.6 arithmetic is not touched. Screen uses `discipline_summary/2` for the displayed
student; whole-class print uses `class_discipline/2` keyed by enrollment id.

## 6. Testing

- **Context (`Discipline`):** `add_sanction` persists with workspace scope and
  type whitelist (invalid type rejected); `duration_days` retained for exclusion
  temporaire; `list_sanctions` filters by période date range (an out-of-range entry
  excluded) and orders newest first; `delete_sanction` removes; `set_conduct_mark`
  upserts (re-set replaces, one row) and rejects out-of-range values; `note_de_conduite`
  returns the séquence mark, the term mean across séquences, and nil when none;
  `discipline_summary` counts consignes separately from the ladder list;
  `class_discipline` covers the roster in scoped reads.
- **LiveView (discipline page):** a conduct manager adds a sanction (persists,
  re-renders), sets a note de conduite (persists), deletes a sanction; the exclusion
  duration input appears only for exclusion temporaire; the period selector reloads;
  a form master sees a read-only view and a forged add/delete/set event is rejected
  (no change); a non-member / cross-school class redirects.
- **Bulletin:** section G renders sanctions + consignes count + note de conduite for a
  student over a séquence and a trimester, and the moyenne générale is unchanged vs a
  no-discipline baseline.
- **Print:** the bulletin print includes the sanctions / consignes / note figures.
- **i18n / gate:** gettext extract + non-empty FR/EN msgstrs for every new msgid
  (sanction type labels, "Sanctions", "Consignes", "Note de conduite", "Motif",
  "Durée (jours)", "Exclusion temporaire", access/flash strings, etc.); `mix precommit`
  (full suite) green. Note: the precommit alias flag is misspelled
  `--warning-as-errors` (a no-op), so warnings do not gate — confirm the suite passes;
  the `format` step rewrites files in place, so commit any format-only diffs.

## Notes / risks

- Keep the two concepts the bulletin distinguishes cleanly separated: **consignes** are
  a count, **sanctions** (the ladder) are a list. `discipline_summary` returns both so
  the bulletin renders each in its own field.
- The note de conduite is keyed per séquence, but the bulletin period can be a
  trimester/annual — `note_de_conduite/2` must roll up as a mean of present séquence
  marks (nil when none), consistent with the P2.6 périodic averaging, never a raw sum.
- Denormalize `workspace_id` onto both resources (set from the class group /
  enrollment on create) so discipline reads stay single scoped queries.
- Conduct stays **off** the moyenne générale; the P2.3 / P2.6 engine is untouched.
  Turning it on later would be an additive change (the marks already exist), consistent
  with P2.8's reversible stance.
- `on_delete: :delete` on the enrollment FK means removing a student's enrollment
  cleans up their sanctions and conduct marks (same cascade posture as attendance).
