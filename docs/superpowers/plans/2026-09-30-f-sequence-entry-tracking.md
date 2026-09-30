# F — Sequence Entry Tracking (N05) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Censeur home page showing, per sequence, how complete each course's mark entry is (classes × subjects grid), matching the mockup layout.

**Architecture:** One pure-ish domain function `TeacherAssistant.Assessment.EntryProgress.grid/3` loads everything in a fixed number of queries and returns a plain map; a LiveView renders it with the mockup's layout. Spaces point the Censeur's home at it.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Ash 3 (attribute multitenancy), Tailwind v4 + daisyUI, Gettext (FR sources).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`, section "F — Censeur follow-up". **Mockup excerpt:** `docs/superpowers/mockups/f-censeur-suivi-sequences.html` (markup with inline styles, palette `K`, KPI texts, grid logic).

## Global Constraints

- Scope-first domain functions, `scope: scope` on every Ash call; no `authorize?: false`.
- UI strings are French `gettext` sources; `mix gettext.extract --merge` and fill `en`.
- LiveView starts with `<Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>`.
- Colors come from the app theme, not the mockup's raw oklch: mockup `K.pri` → `primary`, `K.amb` → `warning`, `K.err` → `error`, `K.ink` → `base-content`, `K.mute` → `base-content/60`, `K.line` → `base-300`, card → `base-200`. Mono numbers use the app's Plex Mono class (see how `marks_live.ex` renders `#entry-deadline`).
- No per-course/per-class query anywhere in the page (spec point 8).
- Finish with `mix precommit` AND `mix compile --warnings-as-errors` (precommit does not gate warnings).
- Branch `f-sequence-tracking`; commit per task.

## Review Focus

1. A class with zero students: no division by zero; its cells show a neutral "—" (pct nil), counted neither late nor complete — Task 1.
2. An exempted student's missing mark does not keep a course below 100 % — Task 1.
3. A mark on a student no longer enrolled (archived enrollment) does not push a course above 100 % — Task 1 (count only marks of students taking the course).
4. `?seq=` with an id from another year / garbage → falls back to the default sequence, no crash — Task 2.
5. No current academic year or no sequences → an empty-state message, no crash — Task 2.

---

### Task 1: EntryProgress domain computation

**Files:**
- Create: `lib/teacher_assistant/academics/entry_progress.ex` (module `TeacherAssistant.Academics.EntryProgress`)
- Modify: `lib/teacher_assistant/assessment.ex` — `def sequence_entry_grid(scope, year, sequence), do: EntryProgress.grid(scope, year, sequence)` and `def default_sequence(sequences, today)`
- Test: `test/teacher_assistant/academics/entry_progress_test.exs`

**Interfaces:**
- Consumes: `Enrollment.list_class_groups/2`, `Organization.list_sequences/2` (loads `:term, :grade_entry_deadline`), `Curriculum.list_subjects/1`, resources `TeachingContext`, `Enrollment`, `SubjectExemption`, `Assessment`, `Mark` (read with `Ash.Query.filter` + `scope:`).
- Produces:

```elixir
%{
  subjects: [%{key: term(), label: String.t()}],          # columns, catalog order then name
  rows: [%{class_group: ClassGroup.t(), cells: %{term() => cell | nil}}],
  overall_pct: non_neg_integer() | nil,                     # mean of cell pcts, nil if no cell
  complete_classes: {non_neg_integer(), non_neg_integer()}, # {complete, total classes}
  late: [%{teacher: User.t(), subject: String.t(), classes: [String.t()]}],
  council_date: Date.t() | nil
}
# cell:
%{teaching_context: TeachingContext.t(), teacher: User.t() | nil, entered: integer, expected: integer,
  pct: integer | nil, assessments: [String.t()], last_entry_at: DateTime.t() | nil}
```

`default_sequence(sequences, today) :: Sequence.t() | nil` — the one with `start_date <= today <= end_date`, else the last with `start_date <= today`, else the first.

- [ ] **Step 1: Failing tests** (fixtures as in `test/teacher_assistant_web/live/school/dashboard_live_test.exs`: `complete_school_setup!`, `member_scope_fixture`, `Curriculum.assign_teacher/4`, `Enrollment.enroll_new/3`, `Assessment.create_assessment…` — copy the helper calls used by `marks_combined_test.exs`)

```elixir
test "pct = entered / (students taking × assessments), any status counts", ctx do
  # class with 3 students, course with 2 assessments, marks: s1 graded both, s2 abs on one
  grid = Assessment.sequence_entry_grid(ctx.head, ctx.year, ctx.seq)
  cell = cell(grid, ctx.cg, "Maths")
  assert {cell.entered, cell.expected, cell.pct} == {3, 6, 50}
  assert cell.assessments == ["Interro 1", "Devoir 1"]
end

test "exempted students are not expected", ctx do
  Curriculum.set_exemptions(ctx.head, ctx.tc, [ctx.s1.id, ctx.s2.id])   # s3 exempt
  # marks for s1, s2 on both assessments
  assert cell(Assessment.sequence_entry_grid(ctx.head, ctx.year, ctx.seq), ctx.cg, "Maths").pct == 100
end

test "no assessment = 0 %, no course = nil cell, empty class = nil pct", ctx do
  grid = Assessment.sequence_entry_grid(ctx.head, ctx.year, ctx.seq)
  assert cell(grid, ctx.cg, "Anglais").pct == 0           # course, students, no assessment
  assert cell(grid, ctx.cg, "Allemand") == nil            # subject not taught in this class
  assert cell(grid, ctx.empty_cg, "Maths").pct == nil     # class without students
end

test "pct rounds down: 119/120 is 99", ctx do
  assert EntryProgress.pct(119, 120) == 99 and EntryProgress.pct(0, 0) == nil
end

test "KPIs: complete classes, late teachers grouped with their classes", ctx do
  grid = Assessment.sequence_entry_grid(ctx.head, ctx.year, ctx.seq)
  assert grid.complete_classes == {0, 2}
  assert [%{subject: "Anglais", classes: ["4e B", "3e A"]}] = grid.late
  assert grid.overall_pct == div(50 + 0 + 0, 3)   # adapt to the cells the setup creates
end

test "default_sequence picks the current, else last started, else first" do
  seqs = [seq(~D[2026-09-07], ~D[2026-10-02]), seq(~D[2026-10-05], ~D[2026-11-06])]
  assert Assessment.default_sequence(seqs, ~D[2026-10-03]) == hd(seqs)
  assert Assessment.default_sequence(seqs, ~D[2026-10-10]) == List.last(seqs)
  assert Assessment.default_sequence(seqs, ~D[2026-08-01]) == hd(seqs)
end
```


- [ ] **Step 2: Run** `mix test test/teacher_assistant/academics/entry_progress_test.exs` → FAIL.

- [ ] **Step 3: Implement** — queries, in this order, each once:
  1. class groups of the year (`Enrollment.list_class_groups/2`);
  2. teaching contexts of the year, `load: [:teacher]` (filter `academic_year_id == ^year.id`);
  3. enrollments of the year → `%{class_group_id => MapSet(student_id)}`;
  4. subject exemptions for those contexts → `%{tc_id => MapSet(student_id)}`;
  5. assessments with `sequence_id == ^seq.id` → grouped by `teaching_context_id` (keep `label`, order by `given_on, inserted_at`);
  6. marks with `assessment_id in ^ids` (select `assessment_id, student_id, updated_at`).

  Then pure code:

```elixir
  def pct(_entered, 0), do: nil
  def pct(entered, expected), do: div(entered * 100, expected)
```

  per context: `taking = enrolled[cg] -- exempt[tc]`; `expected = MapSet.size(taking) * length(assessments)`; `entered = count(marks where assessment in tc's and student in taking)`; `last_entry_at = max(updated_at)`. A course with 0 assessments and students > 0 → `entered 0, expected 0` but `pct: 0` (spec: "Rien saisi") — so special-case: `pct = if assessments == [] and students > 0, do: 0, else: pct(entered, expected)`. Column key = `tc.subject_id || tc.subject`, label = catalog name or `tc.subject`. `complete_classes`: classes with ≥1 cell and every non-nil pct == 100. `late`: cells with pct 0, grouped by teacher. `council_date`: `seq.term.class_council_date` (check the field name on `Term`).

- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: per-course mark entry progress for a sequence"`

---

### Task 2: "Suivi des séquences" LiveView, matching the mockup

**Files:**
- Create: `lib/teacher_assistant_web/live/school/sequence_tracking_live.ex`
- Modify: `router.ex` (`live "/school/sequences", School.SequenceTrackingLive, :index` in `:school_workspace`)
- Test: `test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs`

**Interfaces:**
- Consumes: Task 1 functions; `Organization.can_manage_calendar?/1` as the admin-axis guard (it is what `manage_school` uses in `live_user_auth.ex`).
- Produces: ids `#seq-tabs`, `#seq-tab-<n>`, `#kpi-overall`, `#kpi-complete`, `#kpi-late`, `#kpi-council`, `#entry-grid`, `#cell-<class_group_id>-<n>` (n = column index), `#cell-detail`, `#late-teachers`.

- [ ] **Step 1: Failing tests** — teacher → redirected to `/school` with flash; Censeur sees KPI tiles with values, the grid with `50%` in the Maths cell, a dashed cell where no course; `render_click` on a cell shows `#cell-detail` with "Notes saisies 3 / 6", teacher name, assessment names, "Dernière saisie"; `#late-teachers` lists a 0 % teacher as "Anglais · 4e B, 3e A · rien saisi" and contains no `button`; `?seq=<S2 id>` selects S2 (tab has `aria-current`); `?seq=garbage` falls back without crash; a school with no sequences shows the empty state.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Read the mockup excerpt first and reproduce its structure:
  - header block: eyebrow `gettext("Censorat")`, title `gettext("Suivi des séquences")`;
  - 4 KPI tiles in a responsive grid (`grid grid-cols-2 lg:grid-cols-4 gap-3`), each: small mono uppercase label, big mono value in the tile's color, sub-line (texts from the excerpt's KPI comment);
  - sequence tabs S1…S6 as small outlined pills (`patch` to `?seq=`), selected one `border-warning text-warning bg-warning/15`;
  - main area two columns on desktop (`lg:grid-cols-[minmax(0,1fr)_320px]`), stacked on mobile;
  - left card: title "Classes × disciplines" + legend (Complet / En cours / Rien saisi dots); the grid as CSS grid `grid-template-columns: 72px repeat(<n>, minmax(56px,1fr))` inside `overflow-x-auto`; header row of subject labels (short, mono, muted); each cell a `<button phx-click="select" phx-value-cg=… phx-value-col=…>` rounded, `bg-primary/30` (100), `bg-error/40` (0), `bg-warning/30` (between), selected `ring-2 ring-base-content`; empty = `border border-dashed border-base-300` with `title={gettext("Non enseignée")}`; neutral "—" for nil pct;
  - right column: `#cell-detail` card (hidden until a selection) then the "À relancer" card listing late teachers (bold name, muted detail line), with a muted note `gettext("Les relances arrivent avec les notifications.")` instead of buttons;
  - micro-interactions: `transition-colors` + `hover:ring-1` on cells, tabs `hover:border-warning`.
  Mount: guard, `year = scope.current_academic_year`, sequences via `Organization.list_sequences/2`; `handle_params` resolves `seq` (unknown id → `default_sequence(seqs, Reference.today())`) and assigns `Assessment.sequence_entry_grid/3`.
  Verify visually with the `run` skill or Chrome at 390 px and 1280 px wide against the mockup layout; fix spacing until they match.
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: the censeur follows mark entry per sequence"`

---

### Task 3: Censeur home and menu

**Files:**
- Modify: `lib/teacher_assistant_web/spaces.ex`, `lib/teacher_assistant_web/live/school/dashboard_live.ex`
- Test: `test/teacher_assistant_web/spaces_test.exs`, `test/teacher_assistant_web/live/school/dashboard_live_test.exs`, `test/teacher_assistant_web/live/role_spaces_test.exs`

**Interfaces:**
- Produces: item `nav-school-sequences` "Suivi des séquences" (`hero-chart-bar-square`, `~p"/school/sequences"`); Censeur `home: ~p"/school/sequences"` with the item first in its first section; Proviseur gets the item after Dashboard.

- [ ] **Step 1: Failing tests** — `Spaces.space(:censeur, facts).home == "/school/sequences"`; a Censeur visiting `/school` is navigated to `/school/sequences`; a Proviseur visiting `/school` stays on the dashboard and sees `#nav-school-sequences`; a teacher does not.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — add `sequences/0` item helper beside `dashboard/0`; update the two spaces; in `dashboard_live.ex` change the guard to `when key == :proviseur` (so the Censeur lands on its space home).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** — `git commit -m "feat: the censeur lands on sequence tracking"`

---

### Task 4: Translations and final check

- [ ] `mix gettext.extract --merge`; fill `en` for new msgids; fuzzy count must not grow (`grep -c "#, fuzzy" priv/gettext/en/LC_MESSAGES/default.po` before/after).
- [ ] `mix compile --warnings-as-errors`; `mix precommit` → all green.
- [ ] Commit `chore: F translations`; mark F done in the roadmap table and the memory note.
