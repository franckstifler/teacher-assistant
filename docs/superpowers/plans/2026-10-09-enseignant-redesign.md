# Enseignant Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the six teacher screens (Ma journée + appel, Mes cours, Saisie des notes, Résultats, Mon emploi du temps, Corrections) to the « Espace enseignant » mockup, with marks saved on blur and a Censeur decision note.

**Architecture:** Every screen keeps its LiveView and route. Data changes are limited to `MarkCorrection.decision_note` and two new motive values. New read helpers live where their data already lives (`EntryProgress`, `AssignmentGrid`, `Marks`, `RollCall`). The 941-line `MarksLive` loses its batch save and unsaved-stash machinery in favour of a per-mark `save_mark` event; its row and side panel move to a function-component module.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView (colocated hooks), Ash 3 + AshPostgres, daisyUI/Tailwind v4, Gettext (FR source strings, EN translations).

**Spec:** `docs/superpowers/specs/2026-10-09-enseignant-redesign-design.md`

## Global Constraints

- Work in a worktree: move `.claude/worktrees/vie-scolaire` to `.claude/worktrees/enseignant` (`git worktree move`), then `git switch -c feat/enseignant-redesign main` inside it. Run tests with `MIX_TEST_PARTITION=7`. Never `git commit -a`; stage explicit paths (the user runs parallel sessions).
- Migrations only via `mix ash.codegen --dev <name>`; the final named migration is produced in the last task (`mix ash.codegen enseignant_redesign`).
- Never bare `:atom` attributes — use `Ash.Type.Enum` (`MarkCorrectionMotive` already is one).
- Routes, live_session membership and rights unchanged for all six screens.
- Desktop and 390 px; FR source strings in `gettext`, EN translated in `priv/gettext/en/LC_MESSAGES`, no fuzzy entries left (a guard test exists).
- Numbers shown with a decimal comma (`MarkEntry.format/2`, `String.replace(".", ",")`).
- Mockup colours map to daisyUI tokens: green = `primary`, amber = `warning`, red = `error`, muted = `base-content/70`; use the existing `ta-leaf`, `ta-panel`, `ta-eyebrow`, `ta-num` classes and `<.page_header>`.
- `mix precommit` at the end (note: it does not fail on warnings — check the compile output for warnings yourself).

## Review Focus

1. A blur on a cell whose value did not change must not write (no needless `updated_at` churn, no overwrite of another device's newer mark) — test in Task 7.
2. Blur with an invalid value must keep the typed text in the cell after re-render — test in Task 7.
3. A combined course: a blur on a student of class B must write to class B's assessment, never class A's — test in Task 7.
4. A teacher with no `statutory_hours` and a school with none: header shows load only, no crash on `nil` service — test in Task 3.
5. A refused correction with an empty note shows no dangling « · » — test in Task 2.

---

### Task 1: Decision note and motives (domain + review page)

**Files:**
- Modify: `lib/teacher_assistant/academics/mark_correction.ex` (attribute + approve/refuse arguments)
- Modify: `lib/teacher_assistant/academics/mark_correction/decide.ex` (store the note)
- Modify: `lib/teacher_assistant/academics/mark_correction_motive.ex`
- Modify: `lib/teacher_assistant/assessment.ex:441-447` (`approve_correction/3`, `refuse_correction/3`)
- Modify: `lib/teacher_assistant_web/live/school/correction_review_live.ex` (note textarea)
- Test: `test/teacher_assistant/assessment/mark_correction_test.exs` (create if absent; else the existing correction domain test — `grep -rln approve_correction test`)
- Test: `test/teacher_assistant_web/live/school/correction_review_live_test.exs`

**Interfaces:**
- Produces: `Assessment.approve_correction(scope, correction, note \\ nil)`, `Assessment.refuse_correction(scope, correction, note \\ nil)` → `{:ok, %MarkCorrection{decision_note: String.t() | nil}}`; `MarkCorrectionMotive.offered/0 :: [atom]` = `[:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul]`; `@correction_loads` now also loads `:decider`.

- [ ] **Step 1: Failing domain tests** (reuse the setup of `corrections_live_test.exs`: `MarksFixtures.marks_world/0`, a 12 mark on `s1`, `MarksFixtures.lock!/2`, a `:vice_principal` member `censeur`)

```elixir
test "refusal stores the censeur's note", ctx do
  {:ok, c} = request(ctx)
  {:ok, refused} = Assessment.refuse_correction(ctx.censeur, c, "  Joindre la copie au dossier  ")
  assert refused.decision_note == "Joindre la copie au dossier"
  assert refused.decider.id == ctx.censeur.current_user.id
end

test "approval without a note leaves it nil", ctx do
  {:ok, c} = request(ctx)
  {:ok, approved} = Assessment.approve_correction(ctx.censeur, c)
  assert approved.decision_note == nil
end

test "offered motives are the mockup's four; old values still label" do
  assert MarkCorrectionMotive.offered() ==
           [:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul]
  assert MarkCorrectionMotive.label(:copie_retrouvee) == "Copie retrouvée"
  assert MarkCorrectionMotive.label(:note_rattrapage) == "Rattrapage"
  assert MarkCorrectionMotive.label(:reclamation_eleve) == "Réclamation de l'élève"
end

defp request(ctx),
  do: Assessment.request_correction(ctx.t, %{assessment_id: ctx.a.id, student_id: ctx.s1.id,
        requested_status: :graded, requested_score: Decimal.new(14), motive: :erreur_saisie})
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=7 mix test <file>` — expect FAIL (`refuse_correction/3` undefined, `offered/0` undefined).

- [ ] **Step 3: Implement**

`mark_correction_motive.ex`:
```elixir
use Ash.Type.Enum,
  values: [:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul,
           :copie_mal_corrigee, :reclamation_eleve]

@doc "The motives the request form offers (spec 2026-10-09 §1.2); the last two stay for history."
def offered, do: [:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul]

def label(:erreur_saisie), do: gettext("Erreur de saisie")
def label(:copie_retrouvee), do: gettext("Copie retrouvée")
def label(:note_rattrapage), do: gettext("Rattrapage")
def label(:erreur_calcul), do: gettext("Erreur de calcul")
def label(:copie_mal_corrigee), do: gettext("Copie mal corrigée")
def label(:reclamation_eleve), do: gettext("Réclamation de l'élève")
```

`mark_correction.ex` — attribute and action arguments:
```elixir
attribute :decision_note, :string, public?: true, constraints: [max_length: 500, trim?: true]
```
```elixir
update :approve do
  validate {TeacherAssistant.Academics.YearOpen, path: [:assessment, :sequence, :term]}
  require_atomic? false
  argument :decision_note, :string, constraints: [max_length: 500, trim?: true]
  change {Decide, decision: :approved}
end
# same argument on :refuse
```

`decide.ex` — in the `force_change_attributes` map add
`decision_note: Ash.Changeset.get_argument(changeset, :decision_note)` (trimmed empty string → nil: `case ... do "" -> nil; v -> v end`).

`assessment.ex`:
```elixir
@correction_loads [:student, :requester, :decider, assessment: [teaching_context: [:class_group]]]

def approve_correction(%Scope{} = scope, %MarkCorrection{} = correction, note \\ nil),
  do: decide_correction(scope, correction, :approve, note)

def refuse_correction(%Scope{} = scope, %MarkCorrection{} = correction, note \\ nil),
  do: decide_correction(scope, correction, :refuse, note)

defp decide_correction(scope, correction, action, note) do
  with {:ok, decided} <-
         correction
         |> Ash.Changeset.for_update(action, %{decision_note: note}, scope: scope)
         |> Ash.update(load: @correction_loads) do
    # notification unchanged
```
Drop the now-duplicate `++ [:decider]` in `list_corrections(:decided)`.

- [ ] **Step 4: Run** `mix ash.codegen --dev` (adds `decision_note`), then the domain tests — PASS.

- [ ] **Step 5: Review page note.** Failing LiveView test in `correction_review_live_test.exs`:

```elixir
test "the censeur refuses with a note", ctx do
  {:ok, c} = request(ctx)
  {:ok, view, _} = live(ctx.censeur_conn, ~p"/school/corrections/review")
  view |> element("#correction-row-#{c.id}") |> render_click()   # use the row selector the file already uses
  view |> form("#decision-form", %{"decision" => %{"note" => "Joindre la copie"}}) |> render_change()
  view |> element("#refuse-correction") |> render_click()
  assert [%{decision_note: "Joindre la copie"}] = Assessment.list_corrections(ctx.censeur, :decided)
end
```

Implement: wrap the aside's buttons in `<.form for={@decision_form} id="decision-form" phx-change="note">` with `<.input type="textarea" field={@decision_form[:note]} label={gettext("Note pour l'enseignant")} rows="2" />`; assign `decision_form: to_form(%{"note" => ""}, as: :decision)` on `select` and after a decision; `handle_event("note", %{"decision" => p}, s)` re-assigns the form; `decide/3` passes `socket.assigns.decision_form[:note].value` as the third argument (`fun.(scope, selected, note)`). Keep the buttons `type="button"` with `phx-click`.

- [ ] **Step 6: Run** both test files — PASS. Commit:

```bash
git add lib/teacher_assistant/academics/mark_correction.ex lib/teacher_assistant/academics/mark_correction/decide.ex lib/teacher_assistant/academics/mark_correction_motive.ex lib/teacher_assistant/assessment.ex lib/teacher_assistant_web/live/school/correction_review_live.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant
git commit -m "feat: correction decision note and the mockup's motives"
```

---

### Task 2: Corrections page (teacher)

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/corrections_live.ex`
- Modify: `lib/teacher_assistant/assessment.ex` (add `censeur_name/1`)
- Test: `test/teacher_assistant_web/live/school/corrections_live_test.exs`

**Interfaces:**
- Consumes: `MarkCorrectionMotive.offered/0`, `decision_note`, loaded `:decider` (Task 1).
- Produces: `Assessment.censeur_name(scope) :: String.t() | nil` — the display name of the single active member with role `:vice_principal`, nil when zero or several.

- [ ] **Step 1: Failing tests** (append; existing tests change: `"Demande envoyée au censeur."` assertion becomes the named form since the setup has one censeur)

```elixir
test ":index hides the form until « Nouvelle demande »", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
  refute has_element?(view, "#new-correction-form")
  view |> element("#new-correction-button") |> render_click()
  assert_patch(view, ~p"/school/corrections/new")
  assert has_element?(view, "#new-correction-form")
end

test "the student option shows the current mark; only four motives", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")
  assert has_element?(view, "#new-correction-form option[value='#{ctx.s1.id}']", "— note actuelle 12")
  assert has_element?(view, "input[name='correction[motive]'][value='copie_retrouvee']")
  refute has_element?(view, "input[name='correction[motive]'][value='reclamation_eleve']")
end

test "the flash names the censeur", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections/new?assessment=#{ctx.a.id}")
  html = view |> form("#new-correction-form", %{"correction" => %{"assessment_id" => ctx.a.id,
           "student_id" => ctx.s1.id, "value" => "14", "motive" => "erreur_saisie"}}) |> render_submit()
  assert html =~ "Demande envoyée à #{TeacherAssistant.Accounts.User.display_name(ctx.censeur.current_user)} (censeur)."
end

test "a decision shows who decided and the note; an empty note adds no separator", ctx do
  {:ok, c1} = request(ctx, ctx.s1)
  {:ok, _} = Assessment.refuse_correction(ctx.censeur, c1, "Joindre la copie")
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
  assert has_element?(view, "#correction-#{c1.id}", "Joindre la copie")
  assert has_element?(view, "#correction-#{c1.id}", "Refusée")
  {:ok, c2} = request(ctx, ctx.s2)   # s2 from marks_world; give s2 a mark in setup first
  {:ok, _} = Assessment.approve_correction(ctx.censeur, c2)
  {:ok, view, _} = live(ctx.conn, ~p"/school/corrections")
  refute render(element(view, "#correction-#{c2.id}")) =~ " · <"
end
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  - `handle_params/3`: `assign(:show_form?, socket.assigns.live_action == :new)` (keep the preselect). `handle_event("open_form", _, s)` → `push_patch(to: ~p"/school/corrections/new")`. After a successful request: `push_patch(to: ~p"/school/corrections")` and flash `Assessment.censeur_name(scope)` → `gettext("Demande envoyée à %{name} (censeur).", name: n)`, nil → `gettext("Demande envoyée au censeur.")`.
  - `assign_form/3`: also assign `current_marks` = `Map.new(Assessment.list_marks(scope, assessment), &{&1.student_id, &1})`; option label `"#{s.full_name} — #{gettext("note actuelle")} #{MarkEntry.format(m && m.status, m && m.score)}"`.
  - Motive chips iterate `MarkCorrectionMotive.offered()`.
  - Live hint under the button: `"#{current} → #{requested} · " <> gettext("Le bulletin n'est recalculé qu'après validation.")` when a student and a parsable value are present.
  - Header per spec §2.6 (lead paragraph, `<:actions>` with `#new-correction-button`, primary). Form panel shown `:if={@show_form?}` as a `ta-leaf` grid (`grid gap-3 sm:grid-cols-2`); submit label `gettext("Envoyer la demande")`.
  - Status cell: pill (rename « Approuvée » → « Acceptée »), then a `text-xs text-base-content/70` line: pending → `gettext("Envoyée au censeur")`; decided → `gettext("Par %{name} le %{date}", ...)` and, only when `decision_note not in [nil, ""]`, `" · " <> note`.
  - `Assessment.censeur_name/1`: `scope |> Accounts.list_members() |> Enum.filter(&(:vice_principal in &1.roles)) |> case do [m] -> User.display_name(m.user); _ -> nil end`.

- [ ] **Step 4: Run** the file — PASS. Commit (`git add` the three files) `feat: corrections page follows the mockup`.

---

### Task 3: Teacher load and « Mon emploi du temps »

**Files:**
- Modify: `lib/teacher_assistant/academics/assignment_grid.ex` (make `loads/2` public)
- Modify: `lib/teacher_assistant/timetabling.ex` (`reassign_candidates/3` uses it; add `teacher_service/2`)
- Modify: `lib/teacher_assistant_web/live/school/my_timetable_live.ex`
- Test: `test/teacher_assistant/academics/assignment_grid_test.exs`, `test/teacher_assistant_web/live/school/my_timetable_live_test.exs`

**Interfaces:**
- Produces: `AssignmentGrid.loads(contexts, %{services: map, school_hours: integer | nil}) :: %{user_id => %{load: integer, service: integer | nil, over?: boolean}}`; `Timetabling.teacher_service(scope, user) :: %{load: integer, service: integer | nil}`.

- [ ] **Step 1: Failing tests**

```elixir
# assignment_grid_test.exs
test "loads/2 counts a combined course once and falls back to the school's service" do
  contexts = [
    %{teacher_user_id: "t1", combined_course_id: "c", id: "a", weekly_hours: 4},
    %{teacher_user_id: "t1", combined_course_id: "c", id: "b", weekly_hours: 4},
    %{teacher_user_id: "t1", combined_course_id: nil, id: "d", weekly_hours: 3}
  ]
  assert %{"t1" => %{load: 7, service: 18, over?: false}} =
           AssignmentGrid.loads(contexts, %{services: %{}, school_hours: 18})
  assert %{"t1" => %{service: nil, over?: false}} =
           AssignmentGrid.loads(contexts, %{services: %{}, school_hours: nil})
end
```

```elixir
# my_timetable_live_test.exs (reuse the file's setup: a teacher with an assigned context)
test "the header shows the weekly load against the service", ctx do
  # Arrange: give the teacher's context weekly_hours 14 (the fixture's update or
  # `Ash.Changeset.for_update(ctx.tc, :update, %{weekly_hours: 14})`) and
  # `Accounts.set_member_statutory_hours`-style call (accounts.ex:395) to 18.
  {:ok, view, _} = live(ctx.conn, ~p"/school/timetable/me")
  assert has_element?(view, "#my-timetable-hours", "14 h par semaine · service attendu : 18 h")
end

test "without any service the header shows the load only", ctx do
  # Arrange: `Accounts.update_school_profile(profile, %{statutory_hours: nil}, scope: head)`
  # and leave the membership's statutory_hours nil.
  {:ok, view, _} = live(ctx.conn, ~p"/school/timetable/me")
  assert render(element(view, "#my-timetable-hours")) =~ "h par semaine"
  refute render(element(view, "#my-timetable-hours")) =~ "service attendu"
end
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  - `AssignmentGrid.loads/2`: rename `defp loads` → `def loads` with `@doc`; `over?: is_integer(service) and load > service`.
  - `Timetabling.reassign_candidates/3`: replace its inline `loads` block with `AssignmentGrid.loads(contexts, grid)` and read `get_in(loads, [m.user_id, :load]) || 0`.
  - `Timetabling.teacher_service/2`:
    ```elixir
    def teacher_service(%Scope{current_academic_year: nil}, _user), do: %{load: 0, service: nil}

    def teacher_service(%Scope{current_academic_year: year} = scope, %{id: user_id}) do
      {:ok, profile} = Accounts.fetch_school_profile(scope)
      member = Enum.find(Accounts.list_members(scope), &(&1.user_id == user_id))
      contexts =
        TeachingContext
        |> Ash.Query.filter(academic_year_id == ^year.id and teacher_user_id == ^user_id)
        |> Ash.read!(scope: scope)
      grid = %{services: %{user_id => member && member.statutory_hours}, school_hours: profile.statutory_hours}
      case AssignmentGrid.loads(contexts, grid) do
        %{^user_id => %{load: load, service: service}} -> %{load: load, service: service}
        _ -> %{load: 0, service: AssignmentGrid.service(grid, user_id)}
      end
    end
    ```
  - `MyTimetableLive`: assign `service: Timetabling.teacher_service(scope, scope.current_user)`; header eyebrow `gettext("Semaine type")`, title « Mon emploi du temps », subtitle `<p id="my-timetable-hours">` = `gettext("%{n} h par semaine", n: load)` plus `" · " <> gettext("service attendu : %{m} h", m: service)` when service; `#print-my-timetable` moves into `<:actions>` (outline button). Grid restyle: cells `bg-primary/15 rounded` with class label (`font-semibold`) and subject (`text-xs text-base-content/70`), « Libre » closed cells become `gettext("Fermé")` on `bg-base-300/50 text-base-content/50`; keep break rows and the « Faire l'appel » link; drop `table-zebra`; wrapper `overflow-x-auto` with `min-w-[700px]` on the table.

- [ ] **Step 4: Run** both files plus `test/teacher_assistant_web/live/school/timetable_editor_live_test.exs` (reassign stays green) — PASS. Commit `feat: my timetable shows load against service`.

---

### Task 4: Résultats histogram

**Files:**
- Modify: `lib/teacher_assistant/academics/marks.ex` (add `distribution/1`)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex`
- Test: `test/teacher_assistant/academics/marks_test.exs`, `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`

**Interfaces:**
- Produces: `Marks.distribution([Decimal.t() | nil]) :: [%{label: String.t(), count: non_neg_integer, below_pass?: boolean}]` — five bands in order `0 – 5, 5 – 10, 10 – 12, 12 – 15, 15 – 20`; lower bound inclusive, upper exclusive, 20 in the last band; nils ignored.

- [ ] **Step 1: Failing tests**

```elixir
test "distribution buckets averages with inclusive lower bounds" do
  avgs = Enum.map(~w(0 4.99 5 9.99 10 11.99 12 14.99 15 20), &Decimal.new/1) ++ [nil]
  assert Enum.map(Marks.distribution(avgs), &{&1.label, &1.count, &1.below_pass?}) ==
           [{"0 – 5", 2, true}, {"5 – 10", 2, true}, {"10 – 12", 2, false},
            {"12 – 15", 2, false}, {"15 – 20", 2, false}]
end
```

```elixir
# marks_summary_live_test.exs, reuse its setup with marks giving known averages
test "shows the distribution bars", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/teacher/contexts/#{ctx.ctx.id}/marks/summary?seq=#{ctx.seq.id}")
  assert has_element?(view, "#summary-distribution [data-band='10 – 12']", "1")
end
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  ```elixir
  @bands [{"0 – 5", 0, 5}, {"5 – 10", 5, 10}, {"10 – 12", 10, 12}, {"12 – 15", 12, 15}, {"15 – 20", 15, 21}]

  @doc "Counts of /20 averages per results band (spec 2026-10-09 §1.3)."
  def distribution(averages) do
    graded = Enum.reject(averages, &is_nil/1)
    Enum.map(@bands, fn {label, low, high} ->
      %{label: label, below_pass?: high <= 10,
        count: Enum.count(graded, &(Decimal.compare(&1, low) != :lt and Decimal.compare(&1, high) == :lt))}
    end)
  end
  ```
  Summary LiveView: header eyebrow `gettext("Résultats · Séquence %{n}", n: @seq.number)`, title `"#{@ctx.subject} · #{class label}"` (assign `cg` in mount), subtitle « N élèves · N notes », actions = séquence select + « Retour à la saisie » link to the marks page. KPI cards in mockup style (`.stat` kept; « ≥ 10/20 » label with `tone={:primary}`, lowest with an `error` tone — add `:error` tone to `stat` if missing). New `<div id="summary-distribution" class="ta-leaf p-4">` with heading « Répartition des notes » and a `grid grid-cols-5 items-end h-40 gap-2`; each band `<div data-band={b.label}>` with count, bar `style={"height: #{pct}%"}` (`pct = count * 100 / max(1, max count)`), `bg-error` when `below_pass?` else `bg-primary`, label below. Averages = `Enum.map(Map.values(@summary.per_student), & &1.average)`. Existing mentions, girls/boys, missing warning and table stay below.

- [ ] **Step 4: Run** — PASS. Commit `feat: séquence results histogram`.

---

### Task 5: Mes cours cards

**Files:**
- Modify: `lib/teacher_assistant/academics/entry_progress.ex` (add `context_cells/4`)
- Modify: `lib/teacher_assistant_web/live/school/courses_live.ex`
- Test: `test/teacher_assistant/academics/entry_progress_test.exs` (exists for `grid/3`; append), `test/teacher_assistant_web/live/school/courses_live_test.exs`

**Interfaces:**
- Produces: `EntryProgress.context_cells(scope, year, seq, contexts) :: %{tc_id => %{entered: int, expected: int, pct: int | nil}}` — the same `cell/4` as `grid/3`, computed only for the given contexts (contexts need `:class_group_id`).

- [ ] **Step 1: Failing tests**

```elixir
# entry_progress_test.exs — reuse grid/3's setup
test "context_cells/4 matches the grid cell for that context", ctx do
  grid = EntryProgress.grid(ctx.scope, ctx.year, ctx.seq)
  [row | _] = grid.rows
  cell = row.cells |> Map.values() |> Enum.find(& &1)
  tc = cell.teaching_context
  assert %{entered: e, expected: x, pct: p} =
           EntryProgress.context_cells(ctx.scope, ctx.year, ctx.seq, [tc])[tc.id]
  assert {e, x, p} == {cell.entered, cell.expected, cell.pct}
end
```

```elixir
# courses_live_test.exs — teacher is form master of the class, coefficient 4 set on the grid,
# 2 students, one assessment with one mark in the current séquence
test "a card shows students, coefficient, PP and séquence progress", ctx do
  {:ok, view, _} = live(ctx.conn, ~p"/school/courses")
  card = "#course-#{ctx.ctx.id}"
  assert has_element?(view, card, "2 élèves")
  assert has_element?(view, card, "coef. 4")
  assert has_element?(view, "#{card} [data-role='pp']")
  assert has_element?(view, "#{card} [data-role='progress']", "1 / 2")
end
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  - `context_cells/4`: `enrolled = load_enrolled(scope, year)`, `exempt = load_exempt(scope, contexts)`, assessments of `seq` filtered to the contexts' ids, `load_marks/2`, then for each tc reuse `cell/4` (it reads `tc.teacher`; pass `Map.put_new(tc, :teacher, nil)` or make `cell/4` use `Map.get(tc, :teacher)`), returning `Map.take(cell, [:entered, :expected, :pct])`.
  - `CoursesLive.mount/3`: compute once — `seq = Assessment.default_sequence(sequences, today)` (the existing wrapper at `assessment.ex:149`), all unit contexts flattened, `progress = EntryProgress.context_cells(...)` (skip when `seq` nil), `cells = Curriculum.coefficient_cells(scope)`, enrolled counts via `Enrollment.list_students/2` per class (classes are few per teacher) or the `load_enrolled` sizes, `user_id`.
  - `course_row/2` gains: `students` (sum over member classes), `coefficient` (`CoefficientRules.resolve(cells, %{subject_id: tc.subject_id, subsystem: cg.subsystem, level: cg.level, serie: cg.serie})` → `cells[key].coefficient`, nil when unresolved; first member for a combined course), `pp?` (`Enum.any?(classes, &(&1.form_master_user_id == user_id))`), `progress` (sum entered / sum expected over member contexts, pct via `EntryProgress.pct/2`).
  - Render per spec §2.2: header subtitle `gettext("%{c} cours · %{n} élèves", ...)` + `" · " <> gettext("Séquence %{n} ouverte jusqu'au %{date}", ...)` when `seq` open (deadline = `seq.grade_entry_deadline`, load it); cards in `grid gap-3 [grid-template-columns:repeat(auto-fill,minmax(270px,1fr))]`; class name `font-display text-2xl`; meta line `subject · N élèves · coef. 4` (coef part omitted when nil); PP pill `data-role="pp"` (`bg-warning/20 text-warning`); progress block `data-role="progress"` with label « Notes Séq. N », `entered / expected`, bar colour `primary` at 100, `warning` > 0, `error` at 0; button row `grid grid-cols-4 gap-1.5` — Notes (`btn-primary`), Appel, Résultats, Élèves (`btn-outline`), same hrefs as today.

- [ ] **Step 4: Run** — PASS. Commit `feat: course cards with coefficient, PP and séquence progress`.

---

### Task 6: Ma journée and the roll-call panel

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex` (`all_present/1`, panel restyle)
- Modify: `lib/teacher_assistant_web/live/school/my_day_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/attendance_live.ex` (`all_present` event)
- Test: `test/teacher_assistant_web/live/school/attendance_live_test.exs`, the MyDay test file (`grep -rln MyDayLive\|/school/today test`)

**Interfaces:**
- Produces: `RollCall.all_present(roll) :: roll` — every mark `:present`, every minute `nil`. Event name `"all_present"` handled by both LiveViews.

- [ ] **Step 1: Failing tests**

```elixir
test "« Tous présents » resets absents and lates", ctx do
  {:ok, view, _} = live(ctx.conn, attendance_path(ctx))   # the file's existing path helper/setup
  view |> element("#att-#{ctx.e1}-absent") |> render_click()
  view |> element("#att-#{ctx.e2}-late") |> render_click()
  view |> element("#all-present") |> render_click()
  assert has_element?(view, "#att-#{ctx.e1}-present[aria-pressed='true']")
  refute has_element?(view, "#late-minutes-#{ctx.e2}")
  assert has_element?(view, "#roll-counts", "0 absent")
end

test "after recording, the button reads « Modifier l'appel »", ctx do
  {:ok, view, _} = live(ctx.conn, attendance_path(ctx))
  view |> element("#record-roll") |> render_click()
  assert has_element?(view, "#record-roll", "Modifier l'appel")
end
```
And in the MyDay test: `assert has_element?(view, "#my-day h1", "Ma journée")`.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  - `RollCall.all_present/1`: `%{roll | marks: Map.new(roll.marks, fn {id, _} -> {id, :present} end), minutes: Map.new(roll.minutes, fn {id, _} -> {id, nil} end)}`.
  - Both LiveViews: `def handle_event("all_present", _, socket), do: {:noreply, update(socket, :roll, &(&1 && RollCall.all_present(&1)))}`.
  - `roll_panel/1` gains `attr :eyebrow, :string, default: nil`; header: eyebrow (e.g. `gettext("En cours · %{from} – %{to}", ...)` passed by MyDay for the in-progress slot), title, `#all-present` outline button. Counts row `#roll-counts`: three chips (`bg-primary/15`, `bg-error/20`, `bg-warning/20`) using the existing `ngettext` strings. Student rows: segmented control with labels Présent / Absent / Retard (`AttendanceStatus.label/1`) instead of P/A/R, `min-w-[76px] h-[34px]`, keep ids `att-<id>-<status>` and `aria-pressed`; keep late minutes and flags. Footer `bg-base-200 rounded-b-box`: left = summary, or after save `gettext("Appel envoyé à %{time}. Modifiable jusqu'à la fin du créneau.")` (time from the latest `updated_at` the reload exposes; if not exposed, show `gettext("Appel enregistré.")`); right = `#record-roll` primary, label `gettext("Valider l'appel")` / `gettext("Modifier l'appel")`. Remove the « Tous présents par défaut — … » hint and the `#roll-status` pill (state is in the button and footer) — update any test asserting `#roll-status`.
  - `MyDayLive` header: eyebrow `"#{Dates.long(@today)} · " <> gettext("Séquence %{n}", ...)` (current séquence via `Organization.list_sequences` + `EntryProgress.default_sequence`; omit when nil), title `gettext("Ma journée")`, subtitle `ngettext("%{count} cours aujourd'hui", ...)` + `" · " <> ngettext("%{count} appel à faire maintenant", ...)` (count of `:in_progress` + `:missed` not done). Drop the `calls-done` side chip. Layout `grid gap-4 lg:grid-cols-3`: left column (slots card + missed card, `ta-leaf` with a header row) and roll panel `lg:col-span-2`. Slot rows: time, « class · subject », meta, status pill (Fait = primary soft, Maintenant = warning solid, À venir = base-300, Non fait = error soft). Missed rows keep their link, styled as « Faire l'appel » outline small button, card header shows the count.

- [ ] **Step 4: Run** the attendance, attendance_combined and MyDay test files — PASS. Commit `feat: my day and roll call follow the mockup`.

---

### Task 7: Marks — save on blur, absent toggle, appreciation

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Create: `lib/teacher_assistant_web/live/teacher/marks_components.ex` (row + side panel function components)
- Modify tests: `test/teacher_assistant_web/live/teacher/marks_live_test.exs`, `marks_absence_test.exs`, `marks_lock_test.exs`, `marks_combined_test.exs`

**Interfaces:**
- Produces: events `"save_mark"` (`%{"student" => id, "value" => raw}`) and `"toggle_absent"` (`%{"student" => id}`); assigns `errors :: %{student_id => message}`, `saved_at :: DateTime.t() | nil`; component `MarksComponents.mark_row/1` (attrs `student`, `n`, `value`, `error`, `locked?`, `max`, `grading_rules`), `MarksComponents.side_panel/1` (attrs `title`, `done`, `total`, `average`, `missing`, `deadline`).
- Removed: events `"save"`, `"preview"`; assigns `unsaved`; `stash_current/1`, `restore_scores/3`, `restore_combined_scores/3`, `save_solo/2`, `save_combined/2`, `save_marks/2`; `#marks-submit`.

- [ ] **Step 1: Rewrite the existing submit-based tests** to the blur API. Helper at the top of each file:

```elixir
defp blur(view, student_id, value),
  do: view |> element("#mark-input-#{student_id}") |> render_blur(%{"value" => value})
```
`form("#marks-form", %{"scores" => %{s1.id => "15"}}) |> render_submit()` becomes `blur(view, s1.id, "15")`, one call per student. Out-of-range test asserts the cell error instead of a flash:

```elixir
html = blur(view, s1.id, "25")
assert has_element?(view, "#mark-error-#{s1.id}", "Note entre 0 et 20")
assert has_element?(view, "#mark-input-#{s1.id}[value='25']")
assert Assessment.list_marks(scope, a) == []
```
Add:

```elixir
test "blur with an unchanged value does not write", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1, scope: scope} do
  :ok = Assessment.upsert_marks(scope, a, [%{student_id: s1.id, score: Decimal.new(12)}])
  [before] = Assessment.list_marks(scope, a)
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")
  blur(view, s1.id, "12")
  [after_blur] = Assessment.list_marks(scope, a)
  assert after_blur.updated_at == before.updated_at
end

test "the absent toggle marks and unmarks", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1, scope: scope} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")
  view |> element("#absent-#{s1.id}") |> render_click()
  assert [%{status: :absent, score: nil}] = Assessment.list_marks(scope, a)
  assert has_element?(view, "#mark-input-#{s1.id}[disabled]")
  view |> element("#absent-#{s1.id}") |> render_click()
  refute Enum.any?(Assessment.list_marks(scope, a), &(&1.status == :absent))
  refute has_element?(view, "#mark-input-#{s1.id}[disabled]")
end

test "a saved mark shows its appreciation and « Enregistré »", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1, scope: scope} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")
  blur(view, s1.id, "15")
  expected = TeacherAssistant.Academics.Marks.mention(Decimal.new(15), Assessment.grading_rules(scope))
  assert has_element?(view, "#mark-appreciation-#{s1.id}", expected.label)
  assert has_element?(view, "#save-state", "Enregistré")
end
```
In `marks_combined_test.exs` add (Review Focus 3): blur a student of the second class and assert the mark landed on that class's assessment (`selected.by_class_group_id[cg_b.id]`) and nothing on the first class's. In `marks_lock_test.exs`: `assert has_element?(view, "#mark-input-#{s1.id}[disabled]")` and `refute has_element?(view, "#absent-#{s1.id}:not([disabled])")`.

- [ ] **Step 2: Run** the four files — FAIL (`render_blur` finds no `phx-blur`, `#absent-*` missing).

- [ ] **Step 3: Implement in `MarksLive`**

```elixir
def handle_event("save_mark", _params, %{assigns: %{locked?: true}} = socket),
  do: {:noreply, put_flash(socket, :error, gettext("Séquence verrouillée."))}

def handle_event("save_mark", %{"student" => id, "value" => raw}, socket) do
  socket = assign(socket, :scores, Map.put(socket.assigns.scores, id, raw))

  case MarkEntry.parse(raw) do
    :error -> {:noreply, put_error(socket, id, :invalid)}
    {:ok, entry} -> write_mark(socket, id, entry)
  end
end

def handle_event("toggle_absent", _params, %{assigns: %{locked?: true}} = socket),
  do: {:noreply, socket}

def handle_event("toggle_absent", %{"student" => id}, socket) do
  entry = if MarkEntry.parse(socket.assigns.loaded[id]) == {:ok, :absent}, do: :blank, else: :absent
  write_mark(socket, id, entry)
end

defp write_mark(socket, id, entry) do
  cond do
    not TeacherAssistant.Scope.school_verified?(socket.assigns.current_scope) ->
      {:noreply, put_flash(socket, :error, gettext("École en attente de vérification — enregistrement indisponible."))}

    same_entry?(entry, MarkEntry.parse(Map.get(socket.assigns.loaded, id))) ->
      {:noreply, clear_error(socket, id)}

    true ->
      assessment = assessment_for(socket, id)   # solo: @assessment; combined: by_class_group_id of the student's group
      case Assessment.upsert_marks(socket.assigns.current_scope, assessment,
             [Map.put(entry_attrs(entry), :student_id, id)]) do
        :ok ->
          {:noreply, socket |> clear_error(id) |> assign(:saved_at, Reference.now())
                     |> assign(:loaded, Map.put(socket.assigns.loaded, id, mark_text(entry)))
                     |> assign(:scores, Map.put(socket.assigns.scores, id, mark_text(entry)))
                     |> assign_pending()}
        {:error, :out_of_range} -> {:noreply, put_error(socket, id, :out_of_range)}
        {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
        _ -> {:noreply, put_error(socket, id, :failed)}
      end
  end
end
```
`mark_text/1`: `:blank → ""`, `{:graded, d} → Decimal.to_string(d, :normal)`, status → `MarkStatus.code(status)` (same shape `mark_field/1` produces). `put_error/3` stores `gettext("Note entre 0 et %{max}", max: max_label(assessment))` for `:invalid`/`:out_of_range`, `gettext("Non enregistrée")` for `:failed`. `assessment_for/2` in combined mode finds the student's group in `@groups` and returns `@selected.by_class_group_id[group.class_group.id]`. Delete the batch/stash functions listed under Interfaces; `handle_params/3` no longer stashes (assign `scores`/`loaded` from `existing_scores`/`combined_existing_scores`, `errors: %{}`).

`MarksComponents.mark_row/1` (a `<tr>` with ids): `mark-row-<id>`, input `mark-input-<id>` with `name="value"`, `phx-blur="save_mark"`, `phx-value-student={id}`, `inputmode="decimal"`, `disabled={@locked? or absent?}`, border `border-error` when `@error`, text `text-error` when score < 10/20; Absent button `absent-<id>` (`phx-click="toggle_absent"`, `phx-value-student`, `disabled={@locked?}`, label « Absent » / « Présent », `bg-error/20 border-error` when absent); appreciation cell `mark-appreciation-<id>`: error text `#mark-error-<id>` when error, « Absent — rattrapage possible » when absent, else `Marks.mention(scaled, @grading_rules)` label (`scaled = score × 20 / max`) via the existing `<.mention_badge>` or its label. Row dims (`opacity-60`) when absent. Inputs are no longer inside a `phx-change` form (drop `#marks-form`'s change/submit; keep a plain `<table id="marks-table">`). `#save-state` in the page header: `gettext("Enregistré · %{time}", ...)` from `@saved_at` (green), `ngettext("Erreur : %{count} note à corriger", ...)` when `@errors != %{}` (amber), nothing before the first save. `#marks-progress` and `#marks-average-preview` move into `MarksComponents.side_panel/1` (keep those ids); average computed from `@loaded` (saved values) with the existing `preview_average/4`; combined mode totals over all groups.

- [ ] **Step 4: Run** the four marks test files plus `marks_isolation_test.exs`, `context_switcher_combined_test.exs` — PASS. Commit `feat: marks save on blur with an absent toggle and appreciations`.

---

### Task 8: Marks — toolbar tabs, banners, side panel, shortcuts

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Modify: `lib/teacher_assistant_web/live/teacher/marks_components.ex`
- Test: `test/teacher_assistant_web/live/teacher/marks_live_test.exs`, `marks_lock_test.exs`

**Interfaces:**
- Consumes: `Curriculum.list_units_for_scope/1`, `Curriculum.unit_label/1`, `MarksComponents.side_panel/1` (Task 7).
- Produces: colocated hook `.MarksGrid` on `#marks-table`.

- [ ] **Step 1: Failing tests**

```elixir
test "course tabs link to the teacher's other courses", %{conn: conn, ctx: ctx, scope: scope, year: year, actor: head} do
  other = TeacherFixtures.assigned_context_fixture(scope, year, %{subject: "Maths", level: "4ème", teacher: head})
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks")
  assert has_element?(view, "#course-tabs a[href^='/teacher/contexts/#{other.id}/marks']")
  assert has_element?(view, "#course-tabs [aria-current='page']")
end

test "séquence tabs name their state", %{conn: conn, ctx: ctx, seq: seq} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")
  assert has_element?(view, "#seq-tab-#{seq.id}", "Séquence #{seq.number} · ouverte")
end

test "open banner names the deadline", %{conn: conn, ctx: ctx, seq: seq} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}")
  assert has_element?(view, "#open-banner", "Saisie ouverte jusqu'au")
end

test "the side panel counts what is left before the deadline", %{conn: conn, ctx: ctx, seq: seq, a: a} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")
  assert has_element?(view, "#marks-missing", "1 note à saisir avant le")
end

test "the grid carries the shortcuts hook", %{conn: conn, ctx: ctx, seq: seq, a: a} do
  {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")
  # colocated hook names render with the LiveView module prefix
  assert has_element?(view, "#marks-table[phx-hook$='MarksGrid']")
end
```
In `marks_lock_test.exs`: `assert has_element?(view, "#seq-tab-#{seq.id}", "verrouillée")` and the existing `#locked-request-link` still points to `/school/corrections/new?assessment=`.

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**
  - Mount: assign `course_tabs` = `Curriculum.list_units_for_scope(scope)` mapped to `%{label: Curriculum.unit_label(unit), context_id: ..., current?: ...}` (combined: representative context, current when the mounted ctx belongs to the course).
  - Toolbar: `<nav id="course-tabs">` segmented links (`navigate`, `aria-current="page"` on current, `bg-primary text-primary-content` active); `<div id="seq-tabs">` with one `<.link patch id={"seq-tab-#{s.id}"}>` per séquence labelled `gettext("Séquence %{n}", n: s.number) <> " · " <> state` where state = `gettext("verrouillée")` if `Lock.locked?(s)`, `gettext("ouverte")` if within dates/before deadline, nothing for future ones. Remove `#seq-select` (update tests that used `form("#seq-select")` to click `#seq-tab-…`). Assessment select and new-assessment form stay on the next line; the old `#entry-deadline` text is folded into the open banner.
  - Banners: `#locked-banner` restyled `bg-info/15 border-info/50` with « Séquence N verrouillée depuis le … » + « Demander une correction → » (`#locked-request-link`, unchanged href); `#open-banner` `bg-primary/10 border-primary/45`: `gettext("Saisie ouverte jusqu'au %{date} (J-%{n}). Chaque note est enregistrée dès que vous quittez la case.")`, with n = days from `Reference.today()` to `seq.grade_entry_deadline` (load the calculation on the séquences).
  - Layout: `grid gap-4 lg:grid-cols-[minmax(0,1fr)_260px]`; table card left; right `lg:sticky lg:top-4` stack: `side_panel` (eyebrow « class · Séquence N », `done / total` large `ta-num`, bar, « Moyenne provisoire : » `#marks-average-preview`, `#marks-missing` = `ngettext("%{count} note à saisir avant le %{date}", ...)`) and a « Raccourcis » card (« Entrée : élève suivant », « « a » : absent », « Virgule ou point acceptés : 12,5 = 12.5 »).
  - Colocated hook on `#marks-table` (inside the HEEx, `<script :type={Phoenix.LiveView.ColocatedHook} name=".MarksGrid">`):
    ```javascript
    export default {
      mounted() {
        this.el.addEventListener("keydown", (e) => {
          const input = e.target.closest("input[data-mark-input]");
          if (!input) return;
          if (e.key === "Enter") {
            e.preventDefault();
            const inputs = [...this.el.querySelectorAll("input[data-mark-input]:not([disabled])")];
            const next = inputs[inputs.indexOf(input) + 1];
            next ? next.focus() : input.blur();
          } else if ((e.key === "a" || e.key === "A") && input.value === "") {
            e.preventDefault();
            this.pushEvent("toggle_absent", { student: input.dataset.student });
          }
        });
      }
    };
    ```
    Add `data-mark-input` and `data-student={id}` to the row input in `mark_row/1`.

- [ ] **Step 4: Run** all `test/teacher_assistant_web/live/teacher` — PASS. Commit `feat: marks toolbar tabs, banners, side panel and shortcuts`.

---

### Task 9: Translations, final migration, checks

**Files:**
- Modify: `priv/gettext/**` (extract/merge), `priv/repo/migrations/*` (final name), `priv/resource_snapshots/**`

- [ ] **Step 1:** `mix gettext.extract --merge`; fill every new EN msgstr in `priv/gettext/en/LC_MESSAGES/default.po` (e.g. « Ma journée » → "My day", « Copie retrouvée » → "Paper found", « Erreur de calcul » → "Calculation error", « Note pour l'enseignant » → "Note for the teacher", « Répartition des notes » → "Mark distribution", « %{n} h par semaine » → "%{n} h per week", « service attendu : %{m} h » → "expected service: %{m} h", « Enregistré · %{time} » → "Saved · %{time}", « Tous présents » → "All present", « Valider l'appel » → "Submit roll call", « Modifier l'appel » → "Edit roll call"); remove every `#, fuzzy` flag on new entries and fix their text.
- [ ] **Step 2:** Replace the dev migration: delete the `--dev` migration file(s) and snapshots created in Task 1 per the ash.codegen workflow (`mix ash.codegen enseignant_redesign`), then `mix ecto.reset` is NOT needed — run `MIX_TEST_PARTITION=7 mix test`.
- [ ] **Step 3:** `mix precommit`; read the compile output for warnings and fix them; full suite green.
- [ ] **Step 4:** Commit `chore: Enseignant redesign translations and final migration` (explicit paths).
- [ ] **Step 5:** Browser pass at desktop and 390 px on the dev server (spare port, e.g. `PORT=4017`) with the demo school seed, logged in as a teacher: Ma journée, appel, Mes cours, Saisie (blur, error cell, Enter, « a »), Résultats, Mon emploi du temps, Corrections (new, refused with a note). Fix what you find in a `fix: Enseignant visual pass — …` commit.
