# Absence hours typed by hand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a class take its bulletin absence hours from figures typed by hand (per séquence or per trimester) instead of the roll call, with exactly one source per class so nothing is counted twice.

**Architecture:** A per-class enum setting picks the source. A new `TypedAbsence` resource stores one figure per enrollment and séquence or trimester. One pure module decides which records count, and one domain function `Attendance.bulletin_conduct/3` (same shape as `class_conduct/3`, plus `:source` and `:recorded?`) replaces `class_conduct/3` on the bulletin path only: report cards, passage inputs and the conduct sheet. A new class screen « Heures d'absence » types the figures and switches the setting.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 + AshPostgres, Gettext (FR msgids, EN translations), daisyUI.

**Spec:** `docs/superpowers/specs/2026-10-30-typed-absence-hours-design.md`

## Global Constraints

- Ash enums, never bare `:atom` attributes: the source is an `Ash.Type.Enum`.
- Migrations only via `mix ash.codegen --dev` (never hand-written); never reset the dev DB (only `MIX_ENV=test` drops).
- French gettext msgids with English translations in `priv/gettext/en`; after `mix gettext.extract --merge`, fill and unflag every new fuzzy entry.
- Shared checkout with parallel sessions: work in a worktree, stage explicit paths, never `git commit -a`; set `MIX_TEST_PARTITION` when running tests beside another session.
- `mix precommit` before finishing. It does **not** fail on warnings, and its `format` step rewrites files, so re-stage after it.
- LiveView templates start with `<Layouts.app flash={@flash} current_scope={@current_scope}>` (use the class shell like `DisciplineLive`); use `<.input>` and `<.icon>`.
- Hours are `Decimal`, ≥ 0. The card shows « Absences non justifiées » only, for a typed class.
- Day-to-day readers stay on `class_conduct/3` / `student_conduct/3`: `RegisterLive`, `StudentLive`, `AbsencesLive`, `SchoolLife` alerts. Do not switch them.

## Review Focus

1. **French decimal comma:** « 2,5 » typed on a phone must save as 2.5, not be refused or read as 25. → Task 5 test `parses a decimal comma`.
2. **A form master on another class** must not read or write this class's figures, even by posting a forged `enrollment_id`. → Task 2 test `form master of another class is forbidden`, Task 5 test `refuses enrollments outside the class`.
3. **Closed academic year:** typing into a closed year is refused like conduct marks (`YearOpen`). → Task 2 test `refuses a closed year`.
4. **Stale séquence/trimester records after a rhythm switch** must not reach the card. → Task 3 tests `per_sequence ignores trimester records`, `per_term sequence is none`.
5. **Published trimester:** saving new figures must not change the published card. → Task 6 test `a published snapshot keeps its hours after a new save`.

---

### Task 1: Class setting « Heures d'absence au bulletin »

**Files:**
- Create: `lib/teacher_assistant/academics/absence_hours_source.ex`
- Modify: `lib/teacher_assistant/academics/class_group.ex` (attribute, `:set_absence_hours_source` action, policy beside `:set_paper_roll_call`)
- Modify: `lib/teacher_assistant/enrollment.ex` (beside `set_paper_roll_call/3`)
- Modify: `lib/teacher_assistant/attendance.ex` (beside `set_paper_roll_call_all/3`)
- Generated: migration + resource snapshot via `mix ash.codegen --dev add_absence_hours_source`
- Test: `test/teacher_assistant/academics/typed_absence_setting_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Academics.AbsenceHoursSource` — `use Ash.Type.Enum, values: [:roll_call, :typed_per_sequence, :typed_per_term]`, with `label/1` (gettext: « Calculées depuis l'appel », « Saisies à la main, par séquence », « Saisies à la main, par trimestre »).
  - `ClassGroup.absence_hours_source`, `allow_nil?: false`, `default: :roll_call`, public.
  - `Enrollment.set_absence_hours_source(scope, cg, source) :: {:ok, ClassGroup.t()} | {:error, term}`
  - `Attendance.set_absence_hours_source_all(scope, %AcademicYear{}, source) :: :ok | {:error, term}` (bulk, same shape as `set_paper_roll_call_all/3`)
  - `Attendance.effective_absence_source(scope, cg) :: :roll_call | :typed_per_sequence | :typed_per_term`. Without the `:appel` module, `:roll_call` reads as `:typed_per_sequence`.

- [ ] **Step 1: Write failing tests**, with setup copied from `paper_checklist_test.exs`:
  - `new classes default to roll call`: `cg.absence_hours_source == :roll_call`.
  - `a conduct manager sets it`: a `[:discipline_master]` member scope gets `{:ok, %{absence_hours_source: :typed_per_term}}`.
  - `a teacher, even form master, cannot set it`: a form master `[:teacher]` scope gets `{:error, %Ash.Error.Forbidden{}}`.
  - `set_absence_hours_source_all sets every class of the year`: two classes become `:typed_per_sequence`.
  - `without the appel module roll_call reads as typed_per_sequence`: after `Organization.set_modules(op, ws, [:notes, :discipline])` (operator scope as in `modules_ui_test.exs`), `effective_absence_source(scope, cg) == :typed_per_sequence`; with `:appel` it is `:roll_call`.
- [ ] **Step 2: Run** `mix test test/teacher_assistant/academics/typed_absence_setting_test.exs`. Expected: FAIL (undefined function / unknown attribute).
- [ ] **Step 3: Implement** the enum, attribute, action (`accept [:absence_hours_source]`, `require_atomic? false` like `:set_paper_roll_call`), add the action to the existing `action([:set_paper_roll_call, :set_exam_codes])` policy, then the three functions. Run `mix ash.codegen --dev add_absence_hours_source` and `mix ash.migrate`.
- [ ] **Step 4: Run** the test file. Expected: PASS.
- [ ] **Step 5: Commit** the enum, class_group.ex, enrollment.ex, attendance.ex, the generated migration and snapshot, and the test (explicit paths): `feat(absence-hours): per-class source setting`.

### Task 2: `TypedAbsence` resource

**Files:**
- Create: `lib/teacher_assistant/academics/typed_absence.ex`
- Modify: `lib/teacher_assistant/attendance.ex` (`resources do`: `resource TeacherAssistant.Academics.TypedAbsence`)
- Generated: migration via `mix ash.codegen --dev add_typed_absences`
- Test: `test/teacher_assistant/academics/typed_absence_test.exs`

**Interfaces:**
- Produces `TeacherAssistant.Academics.TypedAbsence`, table `typed_absences`, attribute multitenancy on `workspace_id`, references tenant-matched like `ConductMark`:
  - attributes: `hours :decimal` (not nil), `recorded_by_user_id :uuid`; `belongs_to :enrollment` (not nil), `:sequence` (nil allowed), `:term` (nil allowed).
  - check constraints: `"hours >= 0"`; `"(sequence_id IS NULL) <> (term_id IS NULL)"` (exactly one).
  - identities: `:unique_per_sequence [:enrollment_id, :sequence_id]`, `:unique_per_term [:enrollment_id, :term_id]`.
  - actions: `:read`, `:destroy`; `create :set_for_sequence` (accept `enrollment_id, sequence_id, hours`; `upsert? true`, `upsert_identity :unique_per_sequence`, `upsert_fields [:hours, :recorded_by_user_id, :updated_at]`; `change set_attribute(:recorded_by_user_id, actor(:id))`); `create :set_for_term` (same with `term_id`, `:unique_per_term`); `read :for_enrollments` (argument `enrollment_ids {:array, :uuid}`).
  - policies, for read and for create/destroy: `forbid_unless {Checks.SchoolRole, any_of: :member}`; `authorize_if {Checks.SchoolRole, any_of: :conduct}`; `authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))`.
  - validation `{TeacherAssistant.Academics.YearOpen, path: [:enrollment]}` on create/destroy.

- [ ] **Step 1: Write failing tests:**
  - `a conduct manager sets and re-sets a séquence figure`: two `:set_for_sequence` calls leave one row with the second `hours`.
  - `the form master sets a figure for their class`.
  - `form master of another class is forbidden`: `{:error, %Ash.Error.Forbidden{}}` on create, and reading returns no rows.
  - `refuses negative hours` and `refuses a row with both sequence and term`: `:set_for_sequence` changeset with `Ash.Changeset.force_change_attribute(:term_id, term.id)` returns `{:error, _}` from the DB check.
  - `refuses a closed year`: after `TeacherFixtures.close_year!/2`, create errors.
- [ ] **Step 2: Run** the file. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the resource. Run `mix ash.codegen --dev add_typed_absences`, then `mix ash.migrate`.
- [ ] **Step 4: Run** the file. Expected: PASS.
- [ ] **Step 5: Commit** the resource, attendance.ex, the migration, snapshots and the test: `feat(absence-hours): typed absence records`.

### Task 3: Reading rule (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/typed_absences.ex`
- Test: `test/teacher_assistant/academics/typed_absences_test.exs` (`use ExUnit.Case, async: true`)

**Interfaces:**
- Consumes: records as plain maps `%{sequence_id, term_id, hours}` (one enrollment's).
- Produces, with `span` one of `{:sequence, seq_id}` | `{:term, term_id, [seq_id]}` | `{:year, [{term_id, [seq_id]}]}` and `rhythm` `:typed_per_sequence | :typed_per_term`:
  - `TypedAbsences.hours(records, span, rhythm) :: {:ok, Decimal.t()} | :none`. `:none` means no record contributed.
  - `TypedAbsences.complete?(records, span, rhythm) :: boolean`.
  - The rule (spec §3):
    - **per_sequence:** séquence = its record; term = sum of its séquences' records (term records ignored).
    - **per_term:** term = its record, else the sum of its séquences' records; séquence = `:none` always.
    - **Year:** sum over terms of `hours`, `:none` only when every term is `:none`.
    - **`complete?`:** per_sequence term = every séquence has a record; per_term term = a term record, or every séquence has a record; per_term séquence = `true` (nothing expected); year = every term complete.

- [ ] **Step 1: Write failing tests:** `per_sequence sums sequences for the term` (2 + 1.5 → `{:ok, Decimal.new("3.5")}`); `per_sequence ignores trimester records`; `per_term prefers the term record over sequence records`; `per_term falls back to sequence records`; `per_term sequence is none`; `year sums terms and is none when nothing typed`; `complete? per_sequence needs every sequence`; `complete? per_term accepts a term record`.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement** the two functions.
- [ ] **Step 4: Run** the file. Expected: PASS.
- [ ] **Step 5: Commit**: `feat(absence-hours): reading rule`.

### Task 4: `bulletin_conduct/3` and the bulletin-path readers

**Files:**
- Modify: `lib/teacher_assistant/attendance.ex` (next to `class_conduct/3`)
- Modify: `lib/teacher_assistant/report_cards.ex:59` (`conduct:`)
- Modify: `lib/teacher_assistant/councils.ex:215` (`passage_inputs/3`)
- Modify: `lib/teacher_assistant/discipline.ex:383` (`conduct_sheet/3`)
- Test: `test/teacher_assistant/academics/bulletin_conduct_test.exs`

**Interfaces:**
- Consumes: Task 1 `effective_absence_source/2`, Task 2 `:for_enrollments`, Task 3 `hours/3`, `complete?/3`.
- Produces:
  - `Attendance.bulletin_conduct(scope, cg, period) :: %{enrollment_id => %{justified_hours, unjustified_hours, retards, source: :roll_call | :typed, recorded?: boolean}}`. For `:roll_call` it is `class_conduct/3` with `source: :roll_call, recorded?: true` added. For typed classes, `unjustified_hours` = `hours/3` (or 0 on `:none`), `justified_hours` 0, `retards` 0, `recorded?` = not `:none`. Spans come from `period`: `{:sequence, s}` → `{:sequence, s.id}`; `{:trimester, term}` → its loaded `sequences`; `{:annual, year}` → `Organization.list_terms/2` (sequences loaded). One read of records for the roster.
  - `Attendance.typed_absences_missing(scope, cg, period) :: non_neg_integer`: roster students for whom `complete?/3` is false (0 for a roll-call class).

- [ ] **Step 1: Write failing tests:**
  - `roll-call class equals class_conduct plus source`.
  - `typed class ignores app roll calls`: record an app absence (`Attendance.record_period/6`) plus a typed séquence figure of 3. The result is `unjustified_hours == Decimal.new(3)`, `justified_hours` 0, `retards` 0, `source: :typed`. No double count.
  - `a typed student with nothing typed counts 0 and recorded? false`.
  - `annual sums the trimesters`.
  - `passage_inputs reads typed hours`: `Councils.passage_inputs/3` gives the typed annual figure.
  - `conduct_sheet suggestion uses typed séquence hours` (per_sequence) and `per_term conduct sheet has 0 hours` (`Discipline.conduct_sheet/3`).
  - `typed_absences_missing counts students without a complete figure`.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement** both functions, then switch the three readers to `bulletin_conduct/3`. `conduct_sheet/3` pattern-matches `%{unjustified_hours: hours, retards: retards}`, which still matches.
- [ ] **Step 4: Run** the file plus `mix test test/teacher_assistant/report_cards_test.exs test/teacher_assistant/councils_test.exs test/teacher_assistant/discipline_conduct_sheet_test.exs test/teacher_assistant/academics/attendance_test.exs`. Expected: PASS.
- [ ] **Step 5: Commit**: `feat(absence-hours): bulletin path reads one source`.

### Task 5: Typing sheet and save (domain)

**Files:**
- Modify: `lib/teacher_assistant/attendance.ex`
- Test: `test/teacher_assistant/academics/typed_absence_sheet_test.exs`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `Attendance.typed_absence_sheet(scope, cg, period) :: [%{enrollment, student, hours: Decimal.t() | nil, prefilled?: boolean, app_hours: Decimal.t() | nil}]`, in roster order (`Enrollment.list_roster/2`); `period` is `{:sequence, s}` or `{:trimester, term}`. Value precedence:
    1. the record for that exact period → `prefilled?: false`;
    2. per_term with séquence records → their sum, `prefilled?: true`;
    3. with `:appel`, the `class_conduct/3` unjustified hours → `prefilled?: true`;
    4. otherwise nil.
    `app_hours` = `class_conduct/3` unjustified hours with `:appel`, else nil.
  - `Attendance.save_typed_absences(scope, cg, period, %{enrollment_id => String.t()}) :: :ok | {:error, %{enrollment_id => :invalid}} | {:error, term}`. In one transaction (`Ash.DataLayer.transaction` / `Repo.transaction`, like `PaperWeek.save`):
    - `""` deletes that period's record;
    - any other value is trimmed, `,` → `.`, parsed with `Decimal.parse/1` (whole string), must be ≥ 0, else `:invalid` for that row and nothing is saved;
    - ids not in the class roster → `{:error, :not_in_class}`;
    - when the stored source is `:roll_call` and the school lacks `:appel`, also stores `:typed_per_sequence` (spec §1).

- [ ] **Step 1: Write failing tests:** `sheet pre-fills from the roll call when nothing typed` (`prefilled?: true`, value = app hours); `sheet shows the saved figure unprefilled`; `per_term sheet pre-fills the sum of séquence records`; `saves and clears`; `parses a decimal comma` (`"2,5"` → `Decimal.new("2.5")`); `refuses invalid rows and saves nothing` (`"abc"`, `"-1"`); `refuses enrollments outside the class`; `stores typed_per_sequence when the school lacks appel`.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement** both functions.
- [ ] **Step 4: Run** the file. Expected: PASS.
- [ ] **Step 5: Commit**: `feat(absence-hours): typing sheet and save`.

### Task 6: Bulletin print, absence row and publish checklist

**Files:**
- Modify: `lib/teacher_assistant/report_cards.ex` (`template/2` hidden list, `live_view/3`, `publish_checklist/4`, `paper_check/3`)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex:320-333`
- Modify: `lib/teacher_assistant_web/live/school/bulletins_live.ex` (`check_text/1`)
- Modify: `test/teacher_assistant_web/live/school/modules_ui_test.exs:40-49` (the absences assertion moves to the new rule)
- Test: `test/teacher_assistant/academics/typed_absence_bulletin_test.exs`

**Interfaces:**
- Consumes: Task 4 `bulletin_conduct/3`, `typed_absences_missing/3`.
- Produces:
  - `template/2` hides `:absences` only when the school has neither `:appel` nor `:discipline` (the screen lives in Discipline, Task 7).
  - `live_view/3` drops `:absences` from its `template.elements` when either (a) the class is `:typed_per_term` and the period is a séquence, or (b) the school lacks `:appel` and no enrollment has `recorded?: true`. `BulletinTemplate.show?/2` is a membership test, so order doesn't matter.
  - The print shows the « Absences justifiées » and « Retards » rows only when `Map.get(b.conduct, :source, :roll_call) == :roll_call` (old snapshots have no key).
  - Checklist item `%{key: :typed_absences, ok?: missing == 0, data: %{missing: n}}` for typed classes. `paper_check/3` returns `[]` for typed classes.
  - `check_text/1` clauses: ok → « Heures d'absence : toutes saisies »; else `ngettext("%{count} élève sans heures d'absence saisies", "%{count} élèves sans heures d'absence saisies", n)`.

- [ ] **Step 1: Write failing tests:**
  - `typed class print shows only unjustified hours`: `get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?…")` (copy the query used in the existing bulletin print tests), assert « Absences non justifiées » and the typed value, refute « Absences justifiées » and « Retards ».
  - `no-appel school without typed figures has no absence row`, and `… with a typed figure shows it`.
  - `per_term séquence bulletin has no absence row`.
  - `checklist warns for missing typed hours and skips paper_check`.
  - `a published snapshot keeps its hours after a new save`: publish with `TeacherFixtures.publish_trimester/3`, save new figures, then `ReportCards.class_view/3` snapshot conduct is unchanged.
- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement**, and update the `modules_ui_test.exs` assertion: absences stay with `[:notes, :discipline]` and go with `[:notes]`.
- [ ] **Step 4: Run** the file plus `modules_ui_test.exs`, `paper_checklist_test.exs`, `bulletins_live_test.exs`, `report_cards_test.exs`. Expected: PASS.
- [ ] **Step 5: Commit**: `feat(absence-hours): bulletin rows and checklist`.

### Task 7: « Heures d'absence » screen and settings

**Files:**
- Create: `lib/teacher_assistant_web/live/school/absence_hours_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (beside `/school/classes/:id/discipline`): `live "/school/classes/:id/absence-hours", School.AbsenceHoursLive, :show`
- Modify: `lib/teacher_assistant/modules.ex` (`discipline:` list gains `W.School.AbsenceHoursLive`)
- Modify: `lib/teacher_assistant_web/live/school/discipline_live.ex` and `register_live.ex` (link « Heures d'absence au bulletin » for `ClassShell.allowed?/3` users)
- Modify: `lib/teacher_assistant_web/live/school/school_life_settings_live.ex` (three-way « pour toutes les classes » buttons beside `#paper-roll-call`, event `absence_source_all` → `set_absence_hours_source_all/3`; only `:typed_*` buttons without `:appel`)
- Test: `test/teacher_assistant_web/live/school/absence_hours_live_test.exs`; add to `school_life_settings_live_test.exs`

**Interfaces:**
- Consumes: Task 1 setters and `effective_absence_source/2`, Task 5 sheet/save, `ReportCards.current_publication/3`, `Organization.list_sequences/2`, `list_terms/2`.
- Produces the page (mount guarded like `DisciplineLive`: `ClassShell.allowed?(scope, cg, :discipline)`; rendered in the class shell, tab `:discipline`):
  - `#absence-source` setting: a select of `AbsenceHoursSource` labels (no `:roll_call` without `:appel`), editable only when `Discipline.can_manage_conduct?/1`; read-only text for the form master.
  - `:roll_call` → a note « Les heures du bulletin viennent de l'appel. » and no inputs.
  - Typed → `?period=` picker (séquences or trimesters by rhythm, default `Councils.default_term/2` / current séquence), the form `#typed-absences-form` with one `<.input type="text" inputmode="decimal" name="hours[<enrollment_id>]">` per student in roll order, a grey « dans l'app : X h » hint when `app_hours`, a « pré-rempli » badge when `prefilled?`, the per-row error « Nombre d'heures invalide », and « Enregistrer ».
  - When the period (or a séquence's trimester) has a current publication, a banner `#published-warning`: « Bulletin publié : les heures imprimées ne changent qu'après retrait et nouvelle publication. »

- [ ] **Step 1: Write failing LiveView tests:** `form master types and saves hours` (render_submit, then assert the saved value is shown unprefilled); `form master cannot change the source` (no `select` in `#absence-source`); `conduct manager switches the class to typed per term`; `roll-call class shows the note and no form`; `invalid row shows the error and saves nothing`; `published trimester shows the warning`; `a teacher who is not form master is redirected`; settings test `absence_source_all sets every class`.
- [ ] **Step 2: Run** the files. Expected: FAIL.
- [ ] **Step 3: Implement** the page (mobile-first: one column of rows, input right-aligned, sticky save bar like the paper week screen), route, module entry, links, settings buttons.
- [ ] **Step 4: Run** the files. Expected: PASS.
- [ ] **Step 5: Commit**: `feat(absence-hours): typing screen and settings`.

### Task 8: Translations and precommit

- [ ] **Step 1:** `mix gettext.extract --merge`, then fill the English for every new msgid in `priv/gettext/en/LC_MESSAGES/*.po` and remove their `fuzzy` flags (the guard test fails on fuzzy entries).
- [ ] **Step 2:** `mix precommit`. Expected: compile clean (check for warnings by eye, since the alias doesn't fail on them), gettext up to date, all tests pass.
- [ ] **Step 3: Commit** the `.po`/`.pot` files and anything `format` rewrote (explicit paths): `chore(absence-hours): translations`.
