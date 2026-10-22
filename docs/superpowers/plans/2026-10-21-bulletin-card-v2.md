# Report card & ID card v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A report card that always fits one A4 page with the official bilingual header, school code, APC competences per sequence, earlier terms and an end-of-year term 3; an ID card with the national look, title, head's name and a verification QR.

**Architecture:** New data on existing resources (`SchoolProfile`, `Student`, `AppreciationBand`, `BulletinElement`) plus one new resource `SequenceCompetence` in the `Assessment` domain. `ReportCards.live_view/3` gathers the new pieces into the snapshot (frozen at publication, read with `Map.get` for older snapshots). A pure `BulletinLayout` picks a density tier from line counts. The print template `bulletin_print_html/show.html.heex` is rewritten to the mockup's layout. The ID card template is redone, and a `CardVerification` token is added beside `BulletinVerification`.

**Tech Stack:** Elixir, Phoenix 1.8 (controllers + LiveView), Ash 3 + AshPostgres (attribute multitenancy), Gettext, EQRCode.

**Spec:** `docs/superpowers/specs/2026-10-21-bulletin-card-v2-design.md`. Mockups: `.superpowers/brainstorm/10224-1792620719/content/bulletin-onepage.html` and `idcard.html` (option A). They are not committed; copy them into the worktree if needed.

## Global Constraints

- Migrations only via `mix ash.codegen bulletin_v2` (answer rename prompts with `yes n |`); never hand-written.
- No bare `:atom` attributes: Ash enums only.
- Snapshots are frozen. Every new snapshot key is read with `Map.get(view, key)` / `Map.get(entry, key)` so cards published before this work still render.
- `BulletinElement.defaults/0` is `values() -- [:qr_code, :apc]`. Saved element lists are kept exactly as they are.
- Always printed when filled in (not elements): school code, the two-column FR/EN header, the English name, the flag stripe, and the period in the title.
- APC chrome (competence lines, Cote column, cotes box, mark-entry reminder) appears only when `:apc` is in the class's template. A class graded by letter (`grading: :grade`) gets competence lines only.
- Marks are never blocked by a missing competence.
- Print pages have no inline `<script>`. Density is chosen on the server.
- Gettext: French msgids, English translations filled, no `fuzzy` left in either `.po` (re-run `mix gettext.extract --merge` after `mix precommit` reformats).
- « Today » is `TeacherAssistant.Academics.Reference.today/0`; tests run with the clock frozen at 2025-09-15.
- Work in a worktree under `.claude/worktrees/bulletin-v2` with `MIX_TEST_PARTITION=4`. Stage explicit paths (never `commit -a`). Run `mix precommit` before the last commit.

## Review Focus

1. **A card published before this work (no new snapshot keys) opened after deploy.** Expect: it renders with the v2 layout, and the missing pieces are omitted, not crashed. Test in Task 9.
2. **A school's custom French header lines with no English lines saved.** Expect: the English column falls back to the generated English lines. Test in Task 4.
3. **A teacher writes a competence for a combined course, and one member class's context belongs to another teacher.** Expect: all member contexts of the course are written. The course teacher owns them all, since a combined course has one teacher. Test in Task 3.
4. **Term 3 with `:annual_summary` published, then a teacher tries to change an annual council decision.** Expect: refused as locked; after the term 3 publication is withdrawn, allowed. Test in Task 7.
5. **A blank `national_id` / `school_code` / `name_en` typed as spaces.** Expect: stored as nil, nothing printed. Test in Task 1.

---

### Task 1: Data — profile, student, competence resource, band code, elements

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_profile.ex` (attributes; `:create` and `:update` accept `school_code`, `name_en`; `:update_official_header` accepts `official_header_lines_en`)
- Modify: `lib/teacher_assistant/academics/student.ex` (`national_id`; default create/update accept it)
- Modify: `lib/teacher_assistant/accounts/appreciation_band.ex` (`code`)
- Modify: `lib/teacher_assistant/academics/bulletin_element.ex`
- Create: `lib/teacher_assistant/academics/sequence_competence.ex`; register it in `lib/teacher_assistant/assessment.ex` `resources do`
- Create: migration via `mix ash.codegen bulletin_v2`
- Test: `test/teacher_assistant/academics/bulletin_v2_data_test.exs`; extend `test/teacher_assistant/tenancy_isolation_test.exs` with `SequenceCompetence`

**Interfaces:**
- Produces:
  - `SchoolProfile`: `school_code`, `name_en` (`:string`, public), `official_header_lines_en` (`{:array, :string}`, public). A trim change makes blank values nil (reuse an existing trim change if the resource has one).
  - `Student.national_id :: string | nil`, with the same trim-to-nil behaviour.
  - `AppreciationBand.code :: string | nil` (max 8 characters).
  - `BulletinElement` new values `:apc, :previous_terms, :annual_summary, :guardians, :national_id, :class_profile, :teacher_visa`, each with a `label/1`: « Bulletin APC (compétences, cotes) », « Moyennes des trimestres précédents », « Bilan annuel au 3e trimestre », « Parents / tuteurs », « Identifiant unique », « Profil de la classe (moyennes ≥ 10, taux de réussite) », « Colonne visa de l'enseignant ». `defaults/0` = `values() -- [:qr_code, :apc]`.
  - `SequenceCompetence`: `teaching_context_id` (FK, `on_delete: :delete`), `sequence_id` (FK, `on_delete: :delete`), `text :: string` (required, trimmed, `max_length: 140`), workspace multitenancy like `Assessment`. Identity `unique_per_sequence [:teaching_context_id, :sequence_id]`. Actions: `:read`, `create :upsert` (`upsert? true`, `upsert_identity :unique_per_sequence`, `upsert_fields [:text]`), `:destroy`, `read :for_contexts` (args `context_ids :: {:array, :uuid}`, `sequence_ids :: {:array, :uuid}`). Policies: read for any `:member`; writes use `forbid_unless` member, `forbid_unless Checks.SchoolVerified`, then `authorize_if` `:admin` or `teaching_context.teacher_user_id == ^actor(:id)` (copy `assessment.ex:175-181`).

- [ ] **Step 1: Write failing tests** in `bulletin_v2_data_test.exs`:
  - `test "profile stores school code, English name and English header lines; blanks become nil"`: set `school_code: " 5MN1TEF110431106 "`, `name_en: "G.T.H.S Ngog-Mapubi"`, `official_header_lines_en: ["Republic of Cameroon"]`, then `school_code: "  "` → nil.
  - `test "student national_id is optional and trimmed"`.
  - `test "competence upsert keeps one row per context and sequence"`: two upserts give one row with the second text.
  - `test "competence text longer than 140 is refused"`.
  - `test "only the context's teacher or an admin writes a competence"`: a different teacher's `Ash.can?` is false.
  - `test "defaults exclude qr_code and apc"`: `:apc not in BulletinElement.defaults()` and `:previous_terms in BulletinElement.defaults()`.
  - `test "an appreciation band accepts a code"`.
- [ ] **Step 2:** Run `MIX_TEST_PARTITION=4 mix test test/teacher_assistant/academics/bulletin_v2_data_test.exs`. Expected: FAIL.
- [ ] **Step 3:** Implement the attributes, resource and enum values as listed in Interfaces.
- [ ] **Step 4:** Run `yes n | mix ash.codegen bulletin_v2`, then `MIX_ENV=test MIX_TEST_PARTITION=4 mix ecto.drop`. Run the new test and `tenancy_isolation_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): school code, English name, national ID, sequence competences, band codes, new elements`.

### Task 2: Appreciation codes and the APC preset

**Files:**
- Modify: `lib/teacher_assistant/academics/appreciations.ex`
- Modify: `lib/teacher_assistant_web/live/school/appreciations_live.ex` (code column per band; « Barème APC » button)
- Modify: `lib/teacher_assistant/academics/bulletin_template.ex` (`resolve/3` adds `cote_codes`)
- Test: `test/teacher_assistant/academics/appreciations_test.exs`, `test/teacher_assistant_web/live/school/appreciations_live_test.exs`, `test/teacher_assistant/academics/bulletin_template_test.exs`

**Interfaces:**
- Produces:
  - `Appreciations.bands/1` maps carry `code` (nil when unset). `default_bands/0` codes are all nil.
  - `Appreciations.appreciation/2 :: %{label, code, position, passed?} | nil`.
  - `Appreciations.apc_bands/0 :: [%{from: Decimal, code: String, label: String}]`, lowest first: `{0, "CNA", « C. non acquise »}`, `{10, "CMA", « C. moyennement acquise »}`, `{12, "CA", « C. acquise »}`, `{14, "CBA", « C. bien acquise »}`, `{16, "CTBA", « C. très bien acquise »}`. Labels go through gettext.
  - `BulletinTemplate.resolve/3` → template map gains `cote_codes :: [String]`: the codes of the bands in force, highest band first, nil codes dropped.

- [ ] **Step 1: Write failing tests:**
  - `test "appreciation returns the band's code"`: with `apc_bands/0` saved, 14.5 → `%{code: "CBA", label: "C. bien acquise"}`.
  - `test "apc preset fills five bands"` (LiveView): click « Barème APC » and the form shows the five codes and thresholds. Saving persists them through the existing save event.
  - `test "template lists cote codes highest first"`: `["CTBA", "CBA", "CA", "CMA", "CNA"]`; default bands give `[]`.
- [ ] **Step 2:** Run the three test files. Expected: FAIL.
- [ ] **Step 3:** Implement. The preset button fills the form only; the user still saves.
- [ ] **Step 4:** Run the three test files and `test/teacher_assistant/academics/bulletin_data_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): appreciation band codes and the APC preset`.

### Task 3: Writing competences in mark entry

**Files:**
- Modify: `lib/teacher_assistant/assessment.ex` (domain functions)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`, `lib/teacher_assistant_web/live/teacher/marks_components.ex`
- Test: `test/teacher_assistant/assessment/sequence_competence_test.exs`, `test/teacher_assistant_web/live/teacher/marks_live_test.exs`, `marks_combined_test.exs`

**Interfaces:**
- Consumes: `SequenceCompetence` (Task 1).
- Produces:
  - `Assessment.put_sequence_competence(scope, %TeachingContext{}, %Sequence{}, text) :: :ok | {:error, term}`. When the context has a `combined_course_id`, it upserts one row per member context of the course in one transaction. Blank text destroys the row(s).
  - `Assessment.sequence_competences(scope, context_ids, sequence_ids) :: %{{context_id, sequence_id} => text}`.
  - `Assessment.apc?(scope, %ClassGroup{}) :: boolean`, which is `:apc in ReportCards.template(scope, cg).elements`.

- [ ] **Step 1: Write failing tests:**
  - `test "put then read a competence"`; `test "blank text removes it"`.
  - `test "combined course writes every member context"`: two classes, one course, and one put gives two rows with the same text.
  - LiveView `test "APC on: competence field above the marks and a reminder while empty"`: `has_element?(view, "#sequence-competence")` and `has_element?(view, "#competence-reminder")`. After `render_submit` with text, the reminder is gone and the text is saved.
  - `test "reminder can be dismissed and marks still save"`: click `#competence-reminder button`, the reminder is gone, and a mark blur saves.
  - `test "APC off: no competence field"`.
- [ ] **Step 2:** Run the test files. Expected: FAIL.
- [ ] **Step 3:** Implement. In MarksLive, load `apc?` once at mount (the class of the context, or the first member class for a combined course). Load the current sequence's text when the sequence is chosen. Save on submit/blur through `put_sequence_competence/4`. The reminder is dismissible (assign `competence_reminder_dismissed?`), with the copy « Écrivez la compétence évaluée — elle figure sur le bulletin ». The field label is « Compétence évaluée (séquence %{n}) ». Disable the field when `locked?`, like the marks.
- [ ] **Step 4:** Run the test files. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): teachers write the competence evaluated per sequence`.

### Task 4: Header data, settings and student form

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletin_template.ex` (header keys, `official_lines/2`, head title)
- Create: `lib/teacher_assistant/accounts/head_title.ex`
- Modify: `lib/teacher_assistant/report_cards.ex` (`head_name/1` public; used by both prints)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (drop its private `head_name/1` and use `ReportCards.head_name/1`)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (fields `school_code`, `name_en` next to `registration_number`)
- Modify: `lib/teacher_assistant_web/live/school/official_header_live.ex` (French and English line lists; reset clears both)
- Modify: `lib/teacher_assistant_web/live/school/student_live.ex` (`national_id` in the identity form and the details list, next to the matricule)
- Test: `bulletin_template_test.exs`, `settings_profile_test.exs`, `official_header_live_test.exs`, `student_live_test.exs`, `test/teacher_assistant/accounts/head_title_test.exs`

**Interfaces:**
- Produces:
  - `BulletinTemplate.resolve/3` header map gains `school_code`, `name_en`, `official_lines_en`, `head_title :: %{fr: String | nil, en: String}`, `head_name :: String | nil`. The signature becomes `resolve(profile, school_name, class_group, head_name \\ nil)`, so the existing callers (`bulletin_template_live.ex:25`, `bulletin_template_test.exs`) keep working. `ReportCards.template/2` passes `head_name(scope)`.
  - `BulletinTemplate.official_lines(header, :fr | :en) :: [String]`: the saved list for that language when non-empty, else the generated lines in that locale. `:en` with no English list falls back to the generated English lines, never to the French custom ones.
  - `HeadTitle.title(school_type, :fr | :en) :: String | nil`. French: `:lycee`, `:lycee_technique` → « Le Proviseur »; `:ces_ceg`, `:cetic`, `:sar_sm` → « Le Directeur »; anglophone types (`:gss, :ghs, :gbss, :gbhs, :gtc, :gths`) → nil. English: always « The Principal ».
  - `ReportCards.head_name(scope) :: String | nil`: `SchoolProfile.head_name` when present, else the first member with the `:head` role (today's controller logic).

- [ ] **Step 1: Write failing tests:**
  - `test "English column falls back to generated lines when only French lines are saved"` (Review Focus 2).
  - `test "header carries code, English name and head title"`.
  - `test "head title by school type"` covering one type from each group.
  - `test "head name prefers the profile's head_name"`.
  - Settings: `test "saves school code and English name"`.
  - Official header: `test "edits English lines next to French ones; reset clears both"`.
  - Student page: `test "edits and shows the national ID"`.
- [ ] **Step 2:** Run the test files. Expected: FAIL.
- [ ] **Step 3:** Implement. Keep the existing one-argument `official_lines/1` only if other callers need it; otherwise replace it.
- [ ] **Step 4:** Run the test files plus `bulletin_print_controller_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): bilingual header data, head title and name, settings and student fields`.

### Task 5: `BulletinLayout` — density tiers

**Files:**
- Create: `lib/teacher_assistant/academics/bulletin_layout.ex`
- Test: `test/teacher_assistant/academics/bulletin_layout_test.exs`

**Interfaces:**
- Produces:
  - `BulletinLayout.subject_lines(template, period_kind, groups, sequences_per_term, group_subtotals?) :: non_neg_integer`, where `groups` is `data.groups` (each with `rows`). It counts one line per subject row; with `:apc` on a `:trimester` card (either grading), `sequences_per_term` lines per row. With group subtotals, it adds 2 per group (header + total).
  - `BulletinLayout.density(subject_lines, identity_rows) :: :normal | :compact | :dense | :overflow`. Starting capacities (Task 12 calibrates them in the browser) are effective lines `subject_lines + identity_rows`: ≤ 26 → `:normal`, ≤ 38 → `:compact`, ≤ 46 → `:dense`, else `:overflow`.
  - `BulletinLayout.identity_rows(template) :: pos_integer`, which is 4 plus 1 if `:guardians`.

- [ ] **Step 1: Write failing tests**: 15 subjects without APC → `:normal`; 15 subjects with APC on a trimester card (30 lines + 5 identity rows) → `:compact`; 18 subjects with APC (36 + 5) → `:dense`; 30 subjects with APC → `:overflow`; an annual card with APC counts one line per subject.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement as pure functions.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): density tiers for the one-page card`.

### Task 6: Snapshot data — competences, guardians, national ID, earlier terms, annual summary

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`live_view/3`, `plain_entry/1`, new helpers)
- Modify: `lib/teacher_assistant/enrollment.ex` (`guardians_for_students/2`)
- Modify: `lib/teacher_assistant/academics/bulletins.ex` (`class_profile/1`)
- Test: `test/teacher_assistant/report_cards_test.exs`, `test/teacher_assistant/academics/bulletins_test.exs`

**Interfaces:**
- Consumes: `Assessment.sequence_competences/3` (Task 3); `BulletinTemplate` header (Task 4).
- Produces (all keys added to the `live_view/3` map, so they are frozen in snapshots):
  - `roster` entries: `student.national_id`, and `guardians :: [%{name, phone}]` (main contact first, at most 2) from `Enrollment.guardians_for_students(scope, student_ids) :: %{student_id => [%{name, phone}]}` in one query.
  - `competences :: %{context_id => [%{position: n, text: String | nil}]}` for trimester and sequence periods (positions are the period's sequences in order); `%{}` for annual.
  - `sequences_per_term :: pos_integer` (the term's sequence count; 1 for a sequence period).
  - `prior_terms :: %{student_id => [%{position, average, rank}]}` for a trimester period: the earlier terms of the year by position. Each term's figures come from its current publication's `snapshot.results.per_student` when there is one, else from `Assessment.class_results_for_period/3`. An empty map when `:previous_terms` is off.
  - `annual :: nil | %{per_student: %{student_id => %{average, rank}}, council: council_map}`. Present only for the year's last term (highest `position` in `Organization.list_terms/2`) with `:annual_summary` on. Built from `Assessment.class_results_for_period(scope, cg, {:annual, year})` and `council_entry(scope, cg, {:annual, year}, annual_results)`.
  - `Bulletins.class_profile(results) :: %{passing: n, graded: n, rate: integer | nil}`, where `passing` counts `moyenne_generale >= Appreciations.pass_mark()` and `rate = round(100 * passing / graded)` (nil when `graded == 0`). Computed at render, not stored.
  - `ReportCards.last_term?(scope, %Term{}) :: boolean`.

- [ ] **Step 1: Write failing tests:**
  - `test "snapshot carries guardians, national ID and competences"`: two guardians at most, main contact first, and the competence text at position 1.
  - `test "term 2 view carries term 1 average and rank, from term 1's publication when published"`: publish T1, then change a T1 mark; T2's `prior_terms` still shows the published figure.
  - `test "prior_terms falls back to live results when the earlier term is unpublished"`.
  - `test "annual summary only on the last term and only with the element"`.
  - `test "class_profile counts averages at or above 10"`: averages 9, 10, 12 and nil → `%{passing: 2, graded: 3, rate: 67}`.
  - `test "published snapshot keeps the competence after it is edited"`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. Gate the expensive reads (`prior_terms`, `annual`) on the template's elements.
- [ ] **Step 4:** Run `report_cards_test.exs`, `bulletins_test.exs`, `report_cards_access_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): snapshot carries competences, guardians, earlier terms and the annual summary`.

### Task 7: Term 3 publication rules and checklist

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`publish/3`, `publish_checklist/3`)
- Modify: `lib/teacher_assistant/councils.ex` (`locked?/3`)
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex` (`check_text/1` for new keys; error flash for `:annual_council_not_held`)
- Test: `report_cards_test.exs`, `councils_test.exs`, `test/teacher_assistant_web/live/school/bulletins_live_test.exs`

**Interfaces:**
- Consumes: `ReportCards.last_term?/2` (Task 6), `BulletinLayout` (Task 5).
- Produces:
  - `publish/3` on the last term with `:annual_summary` in the class's template returns `{:error, :annual_council_not_held}` until `Councils.held?(scope, cg, {:annual, year})`.
  - `Councils.locked?(scope, cg, {:annual, year})` is also true while a publication of the year's last term is in force whose `snapshot` has a non-nil `annual` key.
  - `publish_checklist/3` adds the following:
    - `%{key: :annual_council, ok?: held?, data: %{status, date, time}}`, only in the gated case above (blocking, enforced by `publish/3`).
    - `%{key: :competences, ok?: missing == [], data: %{missing: [subject labels]}}`, only with `:apc` on a trimester period (non-blocking).
    - `%{key: :page_fit, ok?: density != :overflow, data: %{subjects: n}}` (non-blocking).
  - Copy: « Conseil de fin d'année : tenu le %{date} / prévu le … / à planifier » (mirror `:council`), « Compétences : %{count} matière(s) sans compétence », « Bulletin trop long pour une page (%{count} matières) » / « Tient sur une page ».

- [ ] **Step 1: Write failing tests:**
  - `test "term 3 with annual summary refuses publishing before the annual council"`, then `Councils.hold(scope, cg, {:annual, year})` and publish succeeds.
  - `test "term 3 without annual summary publishes as today"`.
  - `test "publishing term 3 with annual summary locks the annual council; withdrawing unlocks it"` (Review Focus 4): `Councils.set_decision/5` on the annual period returns the locked error, then succeeds after `ReportCards.withdraw/3`.
  - `test "checklist lists missing competences and page fit"`.
  - LiveView: `test "bulletins page words the annual council and competence checks"`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `report_cards_test.exs`, `councils_test.exs`, `bulletins_live_test.exs`, `council_live_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): term 3 needs the end-of-year council when it carries the annual summary`.

### Task 8: Print template — header, title, identity

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (top of the page)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html.ex`
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (assigns: `density`, `guardians`, `sequences_per_term`)
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: header keys (Task 4), roster keys (Task 6), `BulletinLayout` (Task 5).
- Produces: `BulletinPrintHTML.title(lang, period_kind, term_position) :: String`, giving « Bulletin scolaire du premier / deuxième / troisième trimestre », « Bulletin annuel », or « Bulletin de la séquence %{n} ». The body element gets class `density-<tier>`, where `:overflow` uses the dense CSS.

- [ ] **Step 1: Write failing tests:**
  - `test "French card prints both header columns with logo and code between"`: the body contains `RÉPUBLIQUE DU CAMEROUN`, `REPUBLIC OF CAMEROON` and `CODE : 5MN1TEF110431106`.
  - `test "English name in the right column; workspace name when blank"`.
  - `test "title names the period"`: a T3 card contains « BULLETIN SCOLAIRE DU TROISIÈME TRIMESTRE » (case-insensitive match).
  - `test "identity shows national ID and guardians only with their elements"`.
  - `test "no code line when school_code is nil"`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Rewrite the top of the template to the mockup: a three-column header (`official_lines(header, :fr)` left, logo and code in the centre, `official_lines(header, :en)` right), school names with address and phone, the flag stripe, the title and year, and the photo plus a compact identity table. Switch the CSS to Plex Sans and A4 with 10 mm margins, and add the density classes `density-normal` (8pt), `density-compact` (7.4pt), `density-dense` (6.6pt) with matching cell padding.
- [ ] **Step 4:** Run the controller test file. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): official bilingual header, period title and compact identity`.

### Task 9: Print template — subject table, four boxes, signatures

**Files:**
- Modify: `bulletin_print_html/show.html.heex` (rest of the page), `bulletin_print_html.ex`
- Modify: `bulletin_print_controller.ex` (assigns `class_profile`, `competences`, `prior_terms`, `annual`)
- Test: `bulletin_print_controller_test.exs`

**Interfaces:**
- Consumes: Tasks 2, 5 and 6.
- Produces helpers in `BulletinPrintHTML`:
  - `sequence_lines(row, competences, sequences_per_term) :: [%{position, text, mark}]` (the mark is the row's `components.sequences` entry at that position).
  - `cote_counts(subject_rows, cote_codes) :: [{code, count}]` (every code, zeros included, highest first).

- [ ] **Step 1: Write failing tests:**
  - `test "APC trimester card: one line per sequence with its competence and mark"`.
  - `test "APC off: no Compétences, Cote or cotes box"`.
  - `test "letter-graded class with APC: competence lines but no Cote column"`.
  - `test "sequence card with APC shows that sequence's competence on the subject's line"`.
  - `test "annual card never shows competences"`.
  - `test "cotes box counts subjects per code"`.
  - `test "term 2 shows term 1 average; term 3 shows annual average, rank and decision"`.
  - `test "class profile box shows passing count and rate with the element"`.
  - `test "teacher visa column only with the element"`.
  - `test "head visa shows title and name with « Fait à <town>, le <date> »"`.
  - `test "a pre-v2 snapshot still renders"` (Review Focus 1): publish, then strip the new keys from `pub.snapshot` with an `Ash.Changeset.force_change_attribute` update (or a direct `Repo.update_all` in the test), then GET the print page and expect 200 with the student's name.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Rewrite the rest of the template to the mockup:
  - Subject table: `rowspan` over a subject's sequence lines; competences clamped to one line with ellipsis via CSS.
  - The four boxes: discipline (unjustified/justified hours, lateness, detention count, warning, blame, exclusion days, conduct mark), student's work, cotes, class profile.
  - Council appreciation (clamped to two lines) next to distinction and decision.
  - Signature row: parent, form master, head with stamp and signature and « Fait à %{town}, le %{date} », then the QR.
  - The decision on term 3 comes from `annual.council.outcomes[student_id].passage`.
- [ ] **Step 4:** Run the controller test file and `bulletin_verify_controller_test.exs`. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): one-page subject table with APC lines, four boxes and signature row`.

### Task 10: ID card layout (option A)

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/card_print_controller.ex`, `card_print_html.ex`, `card_print_html/show.html.heex`
- Test: `test/teacher_assistant_web/controllers/card_print_controller_test.exs`

**Interfaces:**
- Consumes: `BulletinTemplate` header (Task 4) through `ReportCards.template/2`; `HeadTitle`; `ReportCards.head_name/1`.

- [ ] **Step 1: Write failing tests:**
  - `test "card has the title, both national headers and the school code"`: « CARTE SCOLAIRE · SCHOOL IDENTITY CARD », `RÉPUBLIQUE DU CAMEROUN`, `REPUBLIC OF CAMEROON`, the code.
  - `test "card shows the national ID when set"`.
  - `test "card shows head title and name"`: « Le Proviseur · The Principal » for a lycée, and « The Principal » alone for a GHS.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Rewrite the card to `idcard.html` option A, keeping 85.6 × 54 mm, 10 per A4 and the toolbar:
  - flag stripe;
  - short national lines FR | logo | EN;
  - school name with BP/phones and the code;
  - title band;
  - photo, details and guardian contact;
  - year badge and QR (Task 11 fills the QR; leave the slot);
  - head stamp, signature, title and name.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): ID card with national header, title and head's name`.

### Task 11: ID card QR verification

**Files:**
- Create: `lib/teacher_assistant_web/card_verification.ex`, `lib/teacher_assistant_web/controllers/card_verify_controller.ex`, `card_verify_html.ex`, `card_verify_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (`get "/verify/card/:token"` next to the bulletin route), `lib/teacher_assistant/enrollment.ex` (`card_verification/2`), `card_print_controller.ex` (QR per card)
- Test: `test/teacher_assistant_web/controllers/card_verify_controller_test.exs`

**Interfaces:**
- Produces:
  - `CardVerification.token(workspace_id, enrollment_id) :: String` and `verify(token) :: {:ok, map} | :invalid`, the same construction as `BulletinVerification` (two 16-byte ids + a 16-byte HMAC tag) with salt `"card-verify"`.
  - `Enrollment.card_verification(workspace_id, enrollment_id) :: {:ok, %{school_name, student_name, class_label, year_name, current?}} | :invalid`. It reads with `authorize?: false` scoped to the tenant (as `ReportCards.verification/3`). `current?` is true when the enrollment's academic year is the school's active year.

- [ ] **Step 1: Write failing tests:**
  - `test "valid token shows school, name, class, year and current status"`.
  - `test "tampered token shows the invalid page"`.
  - `test "page never shows birth date, photo or phone"`: refute the birth date string, `student_photo` and the guardian phone.
  - `test "card print embeds a QR per card"`: the `<svg` count equals the number of cards.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. The page copy is « Carte scolaire valide · <school> · <name> · <class> · <year> » with « inscrit(e) cette année » or « année scolaire terminée », and « Code invalide » for a bad token.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit: `feat(bulletin-v2): verifiable QR on the ID card`.

### Task 12: Translations, precommit, visual pass

**Files:**
- Modify: `priv/gettext/**` (extract and fill)
- Modify: `docs/superpowers/specs/2026-10-21-bulletin-card-v2-design.md` (status line, and the calibrated density thresholds noted in §5.6)
- Modify: `lib/teacher_assistant/academics/bulletin_layout.ex` (calibrated thresholds, if changed)

- [ ] **Step 1:** Run `mix gettext.extract --merge`, then fill every new English entry and unflag the fuzzy ones in both `.po` files. Run the fuzzy guard test. Expected: PASS.
- [ ] **Step 2:** Run `MIX_TEST_PARTITION=4 mix precommit`. Expected: all tests pass and no warnings in the new code. Re-run the extract if line references drift.
- [ ] **Step 3: Visual pass** in the browser pane on the demo seed (memory `reference-demo-school-seed`):
  - Tick `:apc` and every element; give a class 18 subjects with competences; hold the T3 and annual councils; publish T3; open the print page.
  - Measure with `javascript_tool` that the last element's bottom stays within the A4 page height (297 mm at 96 dpi = 1123 px per page, minus the margins) in FR, EN and bilingual. Also measure a technical class with the full general + technical subject list.
  - Adjust the `BulletinLayout` thresholds and density CSS until the measurements fit, and update the thresholds in Task 5's tests.
  - Screenshot the card and an ID card sheet.
- [ ] **Step 4:** Commit: `chore(bulletin-v2): translations, calibrated density, spec marked implemented`.
