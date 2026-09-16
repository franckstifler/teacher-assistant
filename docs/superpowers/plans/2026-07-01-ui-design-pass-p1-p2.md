# UI Design Pass P1+P2 (v1.2 pages + polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the locked "Tableau" design-pass treatment to the v1.2 pages (roster, mark entry, séquence summary — cards→tables, toolbars, data-viz moments) and polish the six existing pages (dashboard strip, coverage per-séquence, fiche table, import stepper, log fixes, setup helper text), per `docs/superpowers/specs/2026-07-01-authenticated-ui-design-pass.md` §2 + §3 (P1, P2).

**Architecture:** Pure LiveView template + small handler changes; no schema/migration work. All statistics reuse the existing pure modules (`Academics.Marks`, `Academics.Coverage`) and existing context functions (`current_sequence/2`, `list_recent_logs/2`). Tables use a **single-structure responsive-collapse pattern** (cells `block` below `md:`, `md:table-cell` above) so each row renders once and every existing DOM id stays unique and preserved.

**Tech Stack:** Phoenix LiveView 1.x + HEEx, daisyUI/Tailwind (existing "Tableau" theme), Ash-backed `Academics` context, gettext FR/EN.

## Global Constraints

- **Stable DOM ids:** every existing id (`#teacher-roster`, `#student-row-<id>`, `#student-form`, `#roster-create-class-form`, `#teacher-marks`, `#seq-select`, `#assessment-select`, `#new-assessment-form`, `#marks-form`, `#mark-input-<id>`, `#mark-row-<id>`, `#marks-submit`, `#teacher-marks-summary`, `#summary-class-average`, `#summary-pass-rate`, `#summary-row-<id>`, `#teacher-dashboard`, `#coverage-kpis`, `#kpi-<id>`, `#academic-year-setup-gate`, `#teacher-coverage`, `#coverage-summary`, `#uncovered-entries`, `#fiche-builder`, `#fiche-entries`, `#entry-<id>`, `#add-entry-form`, `#duplicate-plan`, `#fiche-import`, `#import-*`, `#teacher-log`, `#log-form`, `#log-submit`, `#teacher-setup`, `#setup-form`, `#setup-submit`) is preserved. Existing LiveView tests must pass unchanged, **except** the specced Log behavior change (Task 8 — save no longer navigates away; update only that assertion).
- **No new colors/fonts.** Only existing Tableau primitives (`ta-leaf`, `ta-eyebrow`, `ta-num`, `coverage_ribbon`, daisyUI `btn/badge/steps/alert`) and existing kit components (`page_header`, `stat`, `empty_state`, `setup_gate`, `mention_badge` in `core_components.ex`).
- **All copy through `gettext`.** New msgids are extracted + FR-translated in Task 10 (don't run `gettext.extract` per task).
- Numeric columns use `ta-num`; mentions/pass always word + icon, never color alone; touch targets ≥44px on inputs.
- `mix precommit` (compile `--warnings-as-errors`, format, test) green at every commit. Suite is currently 108 tests / 0 failures.
- Tests use the existing setup idiom (see `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`): `register_and_log_in_user`, `create_academic_year` → `build_default_calendar` → `create_teaching_context` → `create_class_group` → `link_class_group` → `add_student` → `create_assessment` → `upsert_marks`.
- Work on branch `feat/ui-design-pass-p1-p2` off `main`.

### Locked design decisions (from the P0/P1 brainstorm + this plan)

1. **Responsive-collapse tables** (roster, summary, fiche): one `<table>` whose `thead` is `hidden md:table-header-group`, rows are `block md:table-row`, cells `block md:table-cell` (secondary cells `hidden md:table-cell` on mobile). One DOM node per row — ids preserved, no duplicated inputs.
2. **Mark entry md: sheet:** ONE editable input per student (the existing `#mark-input-<id>`, selected assessment). At `md:` each row additionally shows **read-only** scores for the séquence's *other* assessments (`hidden md:flex` cells) under a `hidden md:grid` header row. No editable matrix — save semantics unchanged (one assessment at a time).
3. **Average preview is server-side** `phx-change` on `#marks-form`, computed with `Academics.Marks.summarize/3` (the spec's "client-side" intent is *immediate feedback*, which phx-change provides without duplicating the stats in JS).
4. **Roster undo** = keep the deleted student's attrs in an assign and re-`add_student` on click (no soft delete, no schema change).
5. **Fiche "teachable hours" comparison** is derived, not a new constant: show planned-hours total and "≈ N semaines à X h/sem" using the context's `weekly_hours` (no hard-coded weeks-per-year — [configurable, not hard-coded]).
6. **Dashboard "behind schedule"**: `coverage.rate + 0.10 < elapsed_fraction(year)` where `elapsed_fraction` is days-elapsed/days-total clamped to 0..1.
7. **Import virtualization** = rows beyond the first 100 render inside a collapsed `<details>` (inputs stay in the form so save still submits every row).

---

### Task 1: Roster — responsive table, G/F count, grouped form, delete confirm + undo

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/roster_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/roster_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `Academics.list_students/1` (returns structs with `full_name`, `sex` (`:f`/`:m`), `matricule`), `Academics.add_student/2`, `Academics.delete_student/1`, `Academics.fetch_owned_student/2`; kit `<.page_header>`, `<.empty_state>`.
- Produces: DOM ids `#roster-count`, `#student-table`, `#student-undo` (button inside the undo bar `#student-undo-bar`). Keeps `#student-row-<id>`, `#student-delete-<id>`, `#student-form`, `#student-submit`, `#roster-create-class-form`.

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant_web/live/teacher/roster_live_test.exs` (inside the existing describe/setup that yields `ctx` with a linked class group and students; if the file's setup differs, mirror `marks_summary_live_test.exs` setup):

```elixir
  test "shows girls/boys count and student table", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

    # setup has 1 girl (Awa) + 1 boy (Beba)
    assert has_element?(view, "#roster-count", "1")
    assert render(element(view, "#roster-count")) =~ "Filles"
    assert render(element(view, "#roster-count")) =~ "Garçons"
    assert has_element?(view, "#student-table")
  end

  test "empty roster shows a strong empty state", %{conn: conn, ws: ws} do
    year = TeacherAssistant.Academics.current_academic_year(ws)

    {:ok, ctx2} =
      TeacherAssistant.Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 2
      })

    {:ok, cg2} = TeacherAssistant.Academics.create_class_group(ws, year, %{label: "3e P", level: "3ème"})
    {:ok, ctx2} = TeacherAssistant.Academics.link_class_group(ctx2, cg2)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx2.id}/roster")
    assert render(view) =~ "No students yet"
  end

  test "deleting a student offers undo, undo restores", %{conn: conn, ctx: ctx, s1: s1} do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

    view |> element("#student-delete-#{s1.id}") |> render_click()
    refute has_element?(view, "#student-row-#{s1.id}")
    assert has_element?(view, "#student-undo", "Undo")

    view |> element("#student-undo") |> render_click()
    # restored student has a new id; assert by name and that the undo bar is gone
    assert render(element(view, "#student-table")) =~ s1.full_name
    refute has_element?(view, "#student-undo")
  end
```

If the existing roster test setup doesn't bind `s1`/`ws`/`ctx` under those names, adapt the bindings to the file's actual setup — do not change the existing setup block's behavior.

- [ ] **Step 2: Run to verify failures**

Run: `mix test test/teacher_assistant_web/live/teacher/roster_live_test.exs`
Expected: the 3 new tests FAIL (no `#roster-count` / `#student-table` / `#student-undo`, no "No students yet"); existing tests PASS.

- [ ] **Step 3: Implement**

In `roster_live.ex`, add the delete/undo handlers and counts. Replace `handle_event("delete_student", ...)` and add `undo_delete`:

```elixir
  def handle_event("delete_student", %{"id" => id}, socket) do
    with {:ok, s} <- Academics.fetch_owned_student(id, socket.assigns.ws),
         :ok <- Academics.delete_student(s) do
      {:noreply,
       socket
       |> assign(:students, Academics.list_students(socket.assigns.class_group))
       |> assign(:undo_student, %{full_name: s.full_name, sex: s.sex, matricule: s.matricule})}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not remove the student"))}
    end
  end

  def handle_event("undo_delete", _params, socket) do
    cg = socket.assigns.class_group

    case socket.assigns[:undo_student] do
      nil ->
        {:noreply, socket}

      attrs ->
        case Academics.add_student(cg, attrs) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:students, Academics.list_students(cg))
             |> assign(:undo_student, nil)}

          _ ->
            {:noreply, put_flash(socket, :error, gettext("Could not restore the student"))}
        end
    end
  end
```

In `load/3` add `|> assign(:undo_student, nil)` and a counts helper:

```elixir
  defp sex_counts(students) do
    Enum.frequencies_by(students, & &1.sex)
  end
```

Replace the `render/1` roster branch (the `@class_group` truthy branch; keep the create-class branch untouched) with:

```heex
<%= if @class_group do %>
  <div id="roster-count" class="flex items-center gap-3 text-sm text-base-content/70">
    <span class="font-semibold text-base-content">{length(@students)} {gettext("students")}</span>
    <span class="ta-num">{Map.get(sex_counts(@students), :f, 0)} {gettext("Filles")}</span>
    <span class="text-base-content/40">·</span>
    <span class="ta-num">{Map.get(sex_counts(@students), :m, 0)} {gettext("Garçons")}</span>
  </div>

  <div
    :if={@undo_student}
    id="student-undo-bar"
    class="ta-leaf flex items-center justify-between gap-2 text-sm"
  >
    <span>{gettext("%{name} removed.", name: @undo_student.full_name)}</span>
    <button id="student-undo" phx-click="undo_delete" class="btn btn-outline btn-xs">
      {gettext("Undo")}
    </button>
  </div>

  <.form for={@student_form} id="student-form" phx-submit="add_student" class="ta-leaf space-y-2">
    <fieldset class="space-y-2">
      <legend class="ta-eyebrow">{gettext("Add a student")}</legend>
      <.input field={@student_form[:full_name]} label={gettext("Full name")} />
      <div class="grid gap-2 sm:grid-cols-2">
        <.input
          type="select"
          field={@student_form[:sex]}
          label={gettext("Sex")}
          options={[{gettext("Girl"), "f"}, {gettext("Boy"), "m"}]}
        />
        <.input
          field={@student_form[:matricule]}
          label={gettext("Matricule (optional)")}
          inputmode="numeric"
        />
      </div>
    </fieldset>
    <.button id="student-submit" type="submit" class="btn btn-primary w-full">
      {gettext("Add student")}
    </.button>
  </.form>

  <table :if={@students != []} id="student-table" class="w-full border-separate border-spacing-y-1">
    <caption class="sr-only">{gettext("Class roster")}</caption>
    <thead class="hidden md:table-header-group">
      <tr class="text-left">
        <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Élève")}</th>
        <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Sexe")}</th>
        <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Matricule")}</th>
        <th scope="col" class="px-3 pb-1"><span class="sr-only">{gettext("Actions")}</span></th>
      </tr>
    </thead>
    <tbody class="block space-y-1 md:table-row-group">
      <tr
        :for={s <- @students}
        id={"student-row-#{s.id}"}
        class="ta-leaf block md:table-row"
      >
        <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
          <span class="font-semibold md:font-normal">{s.full_name}</span>
          <button
            id={"student-delete-#{s.id}"}
            phx-click="delete_student"
            phx-value-id={s.id}
            data-confirm={gettext("Remove %{name} from the roster?", name: s.full_name)}
            class="btn btn-ghost btn-xs md:hidden"
          >
            {gettext("Remove")}
          </button>
        </td>
        <td class="hidden md:table-cell md:px-3 md:py-2 text-sm text-base-content/70">
          {if s.sex == :f, do: gettext("Fille"), else: gettext("Garçon")}
        </td>
        <td class="hidden md:table-cell md:px-3 md:py-2 text-sm ta-num text-base-content/70">
          {s.matricule || "—"}
        </td>
        <td class="hidden md:table-cell md:px-3 md:py-2 text-right">
          <button
            id={"student-delete-md-#{s.id}"}
            phx-click="delete_student"
            phx-value-id={s.id}
            data-confirm={gettext("Remove %{name} from the roster?", name: s.full_name)}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Remove")}
          </button>
        </td>
      </tr>
    </tbody>
  </table>

  <.empty_state
    :if={@students == []}
    icon="hero-user-plus"
    title={gettext("No students yet — add your first with the form above.")}
  />
<% else %>
```

Also widen the section wrapper: `class="mx-auto max-w-md space-y-5"` → `class="mx-auto max-w-2xl space-y-5"`.

Note the mobile Remove button and the md: Remove button are **two different ids** (`student-delete-<id>` mobile, `student-delete-md-<id>` desktop) so ids stay unique; existing tests click `#student-delete-<id>` which remains the mobile one (present in DOM regardless of CSS).

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/roster_live_test.exs`
Expected: ALL PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/roster_live.ex test/teacher_assistant_web/live/teacher/roster_live_test.exs
git commit -m "feat(roster): responsive table, filles/garçons count, delete confirm + undo, empty state"
```

---

### Task 2: Mark entry — toolbar, progress line, average preview, md: sheet with sibling assessments

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/marks_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `Academics.list_marks_for_context_sequence/2` (marks for ALL assessments of the séquence: maps with `assessment_id`, `student_id`, `score`), `Academics.Marks.summarize/3`, existing assigns (`@students`, `@assessments`, `@assessment`, `@scores` — `%{student_id => score_string}`).
- Produces: DOM ids `#marks-toolbar` (wraps the two selects + new-assessment form — their ids unchanged), `#marks-progress` ("N of M entered"), `#marks-average-preview` (live class average), `#marks-sheet-header` (md: column header row). Keeps `#mark-row-<id>`, `#mark-input-<id>`, `#marks-form`, `#marks-submit`. New event: `"preview"` (`phx-change` on `#marks-form`).

- [ ] **Step 1: Write the failing tests**

Append to `test/teacher_assistant_web/live/teacher/marks_live_test.exs` (adapt setup bindings to the file's existing setup, which creates ctx/cg/students/assessment like `marks_summary_live_test.exs`):

```elixir
  test "shows entry progress and live average preview", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1, s2: s2} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    # nothing entered yet in the form -> progress reflects saved scores
    assert has_element?(view, "#marks-progress")

    html =
      view
      |> element("#marks-form")
      |> render_change(%{"scores" => %{s1.id => "14", s2.id => "10"}})

    assert html =~ "2"
    # average preview: (14 + 10) / 2 = 12
    assert view |> element("#marks-average-preview") |> render() =~ "12"
  end

  test "toolbar wraps séquence and assessment controls", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-toolbar #seq-select")
    assert has_element?(view, "#marks-toolbar #assessment-select")
  end

  test "md sheet shows sibling assessment scores read-only", %{conn: conn, ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, other} = TeacherAssistant.Academics.create_assessment(ctx, seq, %{label: "Devoir 2"})

    :ok =
      TeacherAssistant.Academics.upsert_marks(other, [
        %{student_id: s1.id, score: Decimal.new("17")}
      ])

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(view, "#marks-sheet-header", "Devoir 2")
    assert render(element(view, "#mark-row-#{s1.id}")) =~ "17"
  end
```

- [ ] **Step 2: Run to verify failures**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: 3 new FAIL (missing ids/behavior); existing PASS.

- [ ] **Step 3: Implement**

In `marks_live.ex`:

(a) Load sibling marks + preview state. Add to `mount` success branch (after `students`) and mirror in `handle_params`:

```elixir
      sibling_scores = sibling_scores(ctx, seq)
```

with helpers:

```elixir
  # %{ {student_id, assessment_id} => score } for every assessment of the séquence
  defp sibling_scores(_ctx, nil), do: %{}

  defp sibling_scores(ctx, seq) do
    ctx
    |> Academics.list_marks_for_context_sequence(seq)
    |> Map.new(fn m -> {{m.student_id, m.assessment_id}, m.score} end)
  end

  defp entered_count(scores), do: Enum.count(scores, fn {_id, v} -> v not in [nil, ""] end)

  defp preview_average(_students, nil, _scores), do: nil

  defp preview_average(students, assessment, scores) do
    marks =
      Enum.map(students, fn s ->
        %{assessment_id: assessment.id, student_id: s.id, score: parse_score(Map.get(scores, s.id))}
      end)

    summary =
      TeacherAssistant.Academics.Marks.summarize(
        Enum.map(students, fn s -> %{id: s.id, sex: s.sex} end),
        [%{id: assessment.id, weight: assessment.weight, max_score: assessment.max_score}],
        marks
      )

    summary.class_average
  end
```

(b) Add assigns wherever `:scores` is assigned (mount, `handle_params`, after save): also `assign(:sibling_scores, sibling_scores(ctx_or_assigns.ctx, seq))`. Add the preview `phx-change` handler:

```elixir
  def handle_event("preview", %{"scores" => scores}, socket) do
    {:noreply, assign(socket, :scores, Map.new(scores, fn {k, v} -> {k, v} end))}
  end
```

(Scores keys arrive as the student-id strings already used by `Map.get(@scores, s.id)` — student ids are UUID strings in both, so no conversion is needed.)

(c) Replace `render/1` with (section widened to `max-w-3xl`; toolbar + progress + sheet):

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks" class="mx-auto max-w-3xl space-y-4">
        <.page_header eyebrow={gettext("Marks")} title={"#{@ctx.subject} · #{@ctx.level}"} />

        <div
          id="marks-toolbar"
          class="ta-leaf sticky top-16 z-10 flex flex-wrap items-end gap-2 backdrop-blur"
        >
          <form id="seq-select" phx-change="select_seq" class="min-w-36 flex-1">
            <.input
              type="select"
              name="seq"
              value={@seq && @seq.id}
              label={gettext("Séquence")}
              options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
            />
          </form>

          <form :if={@seq} id="assessment-select" phx-change="select_assessment" class="min-w-36 flex-1">
            <.input
              type="select"
              name="assessment"
              value={@assessment && @assessment.id}
              label={gettext("Assessment")}
              options={for a <- @assessments, do: {a.label, a.id}}
            />
          </form>

          <.form
            :if={@seq}
            for={@new_assessment_form}
            id="new-assessment-form"
            phx-submit="new_assessment"
            class="flex flex-1 items-end gap-2"
          >
            <.input field={@new_assessment_form[:label]} placeholder={gettext("New assessment")} />
            <.button type="submit" class="btn btn-outline btn-sm">{gettext("Add")}</.button>
          </.form>
        </div>

        <%= if @assessment do %>
          <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
            <p id="marks-progress" class="ta-num text-base-content/70">
              {gettext("%{entered} of %{total} entered",
                entered: entered_count(@scores),
                total: length(@students)
              )}
            </p>
            <p id="marks-average-preview" class="ta-num font-semibold">
              {gettext("Class average")}:
              <span class="text-primary">{fmt_avg(preview_average(@students, @assessment, @scores))}</span>
            </p>
          </div>
          <p class="text-xs text-base-content/55">
            {gettext("Blank = absent. Marks are out of 20.")}
          </p>

          <.form
            for={to_form(%{}, as: :scores)}
            id="marks-form"
            phx-change="preview"
            phx-submit="save"
            class="space-y-2"
          >
            <div
              id="marks-sheet-header"
              class="hidden items-center gap-2 px-3 md:flex"
            >
              <span class="ta-eyebrow flex-1">{gettext("Élève")}</span>
              <span
                :for={a <- @assessments, a.id != @assessment.id}
                class="ta-eyebrow w-16 text-right"
              >
                {a.label}
              </span>
              <span class="ta-eyebrow w-24 text-right">{@assessment.label}</span>
            </div>

            <div
              :for={s <- @students}
              id={"mark-row-#{s.id}"}
              class="ta-leaf flex items-center justify-between gap-2"
            >
              <span class="flex-1">{s.full_name}</span>
              <span
                :for={a <- @assessments, a.id != @assessment.id}
                class="ta-num hidden w-16 text-right text-sm text-base-content/55 md:inline-block"
              >
                {fmt_avg(@sibling_scores[{s.id, a.id}])}
              </span>
              <input
                id={"mark-input-#{s.id}"}
                type="number"
                step="0.25"
                min="0"
                max="20"
                inputmode="decimal"
                aria-label={s.full_name}
                placeholder={gettext("Abs")}
                name={"scores[#{s.id}]"}
                value={Map.get(@scores, s.id, "")}
                class="input input-bordered h-11 w-24 text-right ta-num"
              />
            </div>
            <.button id="marks-submit" type="submit" class="btn btn-primary w-full">
              {gettext("Save marks")}
            </.button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
```

with the formatting helper:

```elixir
  defp fmt_avg(nil), do: "—"
  defp fmt_avg(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()
```

Note: the `seq-select`/`assessment-select` forms moved inside `#marks-toolbar` but keep their ids and events; the standalone `<%= if @seq %>` wrapper is replaced by `:if={@seq}` on the two inner forms.

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/marks_live.ex test/teacher_assistant_web/live/teacher/marks_live_test.exs
git commit -m "feat(marks): sticky toolbar, entry progress + live average preview, md: sheet with sibling scores, Abs affordance"
```

---

### Task 3: Séquence summary — stat grid, mention distribution, responsive table, sex bars, switcher, missing marks

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_summary_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `@summary` from `Academics.Marks.summarize/3` (`class_average`, `pass_rate`, `highest`, `lowest`, `graded_count`, `by_sex.f/.m` with `pass_rate`, `per_student` map of `%{average, mention, rank}`), kit `<.stat>`, `<.mention_badge>`, `<.empty_state>`.
- Produces: DOM ids `#summary-stats` (grid of `<.stat>`), `#summary-mentions` (distribution), `#summary-sex-bars`, `#summary-missing`, `#summary-seq-select` (séquence switcher form), `#summary-table`. Keeps `#summary-class-average`, `#summary-pass-rate`, `#summary-row-<id>` (now `<tr>`s). New event `"select_seq"` → `push_patch` (requires a `handle_params/3`, which this LiveView currently lacks).

- [ ] **Step 1: Write the failing tests**

Append to `marks_summary_live_test.exs`:

```elixir
  test "shows mention distribution, sex bars and missing-marks line", %{
    conn: conn,
    ctx: ctx,
    seq: seq,
    cg: cg
  } do
    {:ok, _ungraded} = Academics.add_student(cg, %{full_name: "Chantal", sex: :f})

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    # Awa 14 => Bien; Beba 8 => Insuffisant
    assert render(element(view, "#summary-mentions")) =~ "Bien"
    assert render(element(view, "#summary-mentions")) =~ "Insuffisant"
    assert has_element?(view, "#summary-sex-bars", "Filles")
    assert has_element?(view, "#summary-sex-bars", "Garçons")
    # 1 of 3 students has no marks
    assert has_element?(view, "#summary-missing", "1")
  end

  test "séquence switcher patches to the chosen séquence", %{conn: conn, ctx: ctx, ws: ws} do
    year = Academics.current_academic_year(ws)
    seq2 = Academics.list_sequences(year) |> Enum.at(1)

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary")

    view
    |> element("#summary-seq-select")
    |> render_change(%{"seq" => seq2.id})

    assert_patch(view, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq2.id}")
    # séquence 2 has no assessments -> guided empty state, not stats
    refute has_element?(view, "#summary-class-average")
    assert render(view) =~ "No marks in this séquence yet"
  end

  test "renders a table with rank and mention columns", %{conn: conn, ctx: ctx, seq: seq, s1: s1} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks/summary?seq=#{seq.id}")

    assert has_element?(view, "#summary-table")
    row = render(element(view, "#summary-row-#{s1.id}"))
    assert row =~ "Awa"
    assert row =~ "14"
    assert row =~ "Bien"
  end
```

- [ ] **Step 2: Run to verify failures**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`
Expected: 3 new FAIL; existing PASS.

- [ ] **Step 3: Implement**

In `marks_summary_live.ex`:

(a) Extract summary computation so `handle_params` can reuse it; add switcher event:

```elixir
  def handle_params(params, _uri, socket) do
    seq = pick(socket.assigns.sequences, params["seq"]) || List.first(socket.assigns.sequences)
    {:noreply, socket |> assign(:seq, seq) |> assign_summary()}
  end

  def handle_event("select_seq", %{"seq" => seq_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/teacher/contexts/#{socket.assigns.ctx.id}/marks/summary?seq=#{seq_id}"
     )}
  end

  defp assign_summary(socket) do
    %{ctx: ctx, seq: seq, students: students} = socket.assigns

    summary =
      if seq do
        assessments = Academics.list_assessments(ctx, seq)
        marks = Academics.list_marks_for_context_sequence(ctx, seq)

        if assessments == [] do
          nil
        else
          Marks.summarize(
            Enum.map(students, fn s -> %{id: s.id, sex: s.sex} end),
            Enum.map(assessments, fn a -> %{id: a.id, weight: a.weight, max_score: a.max_score} end),
            Enum.map(marks, fn m ->
              %{assessment_id: m.assessment_id, student_id: m.student_id, score: m.score}
            end)
          )
        end
      end

    assign(socket, :summary, summary)
  end
```

In `mount`, replace the inline `summary = ...` computation with assigns of `ctx/sequences/seq/students` followed by `assign_summary(socket)` (`handle_params` runs after mount and recomputes — keep `mount` assigning `:summary` via `assign_summary` so direct renders are consistent). Note `assessments == []` now yields `nil` summary → the guided empty state ("No marks in this séquence yet") instead of all-dash stats.

(b) Add helpers:

```elixir
  @mention_order [:excellent, :tres_bien, :bien, :assez_bien, :passable, nil]

  defp mention_distribution(summary) do
    freq =
      summary.per_student
      |> Map.values()
      |> Enum.reject(&is_nil(&1.average))
      |> Enum.frequencies_by(& &1.mention)

    for m <- @mention_order, count = Map.get(freq, m, 0), count > 0, do: {m, count}
  end

  defp missing_count(students, summary), do: length(students) - summary.graded_count

  defp bar_width(%Decimal{} = avg), do: "#{avg |> Decimal.mult(5) |> Decimal.round(0)}%"
  defp bar_width(rate) when is_float(rate), do: "#{round(rate * 100)}%"
```

(c) Replace `render/1` body (widen to `max-w-2xl`; keep the outer section id):

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-marks-summary" class="mx-auto max-w-2xl space-y-4">
        <.page_header eyebrow={gettext("Séquence results")} title={"#{@ctx.subject} · #{@ctx.level}"}>
          <:actions>
            <form id="summary-seq-select" phx-change="select_seq">
              <.input
                type="select"
                name="seq"
                value={@seq && @seq.id}
                options={for s <- @sequences, do: {gettext("Séquence") <> " #{s.number}", s.id}}
              />
            </form>
          </:actions>
        </.page_header>

        <%= if @summary do %>
          <div id="summary-stats" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <div id="summary-class-average" class="contents">
              <.stat label={gettext("Class average")} value={fmt(@summary.class_average)} suffix="/20" tone={:primary} />
            </div>
            <div id="summary-pass-rate" class="contents">
              <.stat label={gettext("Pass rate")} value={pct(@summary.pass_rate)} />
            </div>
            <.stat label={gettext("Highest")} value={fmt(@summary.highest)} suffix="/20" />
            <.stat label={gettext("Lowest")} value={fmt(@summary.lowest)} suffix="/20" />
          </div>

          <div id="summary-mentions" class="flex flex-wrap items-center gap-2">
            <span
              :for={{mention, count} <- mention_distribution(@summary)}
              class="badge badge-soft gap-1"
            >
              <.mention_badge mention={mention} />
              <span class="ta-num">×{count}</span>
            </span>
          </div>

          <div id="summary-sex-bars" class="ta-leaf space-y-2">
            <p class="ta-eyebrow">{gettext("Pass rate — filles / garçons")}</p>
            <div
              :for={{label, stats} <- [{gettext("Filles"), @summary.by_sex.f}, {gettext("Garçons"), @summary.by_sex.m}]}
              class="flex items-center gap-2 text-sm"
            >
              <span class="w-20 shrink-0 text-base-content/70">{label}</span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div class="h-full rounded-full bg-primary" style={"width: #{bar_width(stats.pass_rate)}"}></div>
              </div>
              <span class="ta-num w-12 text-right">{pct(stats.pass_rate)}</span>
            </div>
          </div>

          <p
            :if={missing_count(@students, @summary) > 0}
            id="summary-missing"
            class="flex items-center gap-2 text-sm text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-4" />
            {gettext("%{count} student(s) without marks in this séquence",
              count: missing_count(@students, @summary)
            )}
          </p>

          <table id="summary-table" class="w-full border-separate border-spacing-y-1">
            <caption class="sr-only">{gettext("Per-student results")}</caption>
            <thead class="hidden md:table-header-group">
              <tr class="text-left">
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Rang")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Élève")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Moyenne")}</th>
                <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Mention")}</th>
              </tr>
            </thead>
            <tbody class="block space-y-1 md:table-row-group">
              <tr
                :for={s <- @students}
                id={"summary-row-#{s.id}"}
                class="ta-leaf block md:table-row"
              >
                <td class="hidden md:table-cell md:px-3 md:py-2 ta-num text-base-content/60">
                  {@summary.per_student[s.id].rank || "—"}
                </td>
                <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                  <span>{s.full_name}</span>
                  <span class="ta-num font-mono md:hidden">
                    {fmt(@summary.per_student[s.id].average)}
                    <span :if={@summary.per_student[s.id].rank} class="opacity-60">
                      ({@summary.per_student[s.id].rank})
                    </span>
                  </span>
                </td>
                <td class="hidden md:table-cell md:px-3 md:py-2">
                  <span class="flex items-center gap-2">
                    <span class="ta-num font-mono">{fmt(@summary.per_student[s.id].average)}</span>
                    <span
                      :if={@summary.per_student[s.id].average}
                      class="h-1.5 w-16 overflow-hidden rounded-full bg-base-300"
                    >
                      <span
                        class="block h-full rounded-full bg-primary"
                        style={"width: #{bar_width(@summary.per_student[s.id].average)}"}
                      >
                      </span>
                    </span>
                  </span>
                </td>
                <td class="block md:table-cell md:px-3 md:py-2">
                  <.mention_badge
                    :if={@summary.per_student[s.id].average}
                    mention={@summary.per_student[s.id].mention}
                  />
                  <span :if={is_nil(@summary.per_student[s.id].average)} class="text-base-content/40">
                    —
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        <% else %>
          <.empty_state
            icon="hero-pencil-square"
            title={gettext("No marks in this séquence yet")}
            message={gettext("Enter marks for an assessment to see the séquence results.")}
          >
            <:action>
              <.link
                navigate={~p"/teacher/contexts/#{@ctx.id}/marks?seq=#{@seq && @seq.id}"}
                class="btn btn-primary btn-sm"
              >
                {gettext("Enter marks")}
              </.link>
            </:action>
          </.empty_state>
        <% end %>
      </section>
    </Layouts.app>
```

**Careful:** existing tests assert `#summary-class-average` contains "11" and `#summary-pass-rate` contains "50" — the `class="contents"` wrapper divs keep those ids valid around the `<.stat>` cells. The old no-year fallback text (`"No séquences yet — set up the school year first."`) is replaced by the empty state — check existing tests: if one asserts that string, keep a `:if={@sequences == []}` paragraph with the original string alongside the empty state (only shown when there are no séquences at all).

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/marks_summary_live.ex test/teacher_assistant_web/live/teacher/marks_summary_live_test.exs
git commit -m "feat(summary): stat grid, mention distribution, responsive results table with /20 bars, sex pass-rate bars, séquence switcher, missing-marks line"
```

---

### Task 4: Dashboard — at-a-glance strip, Roster/Coverage card links, behind-schedule accent

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/dashboard_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/dashboard_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `Academics.list_teaching_contexts/2`, `Academics.current_sequence/2` (returns a Sequence or nil for a date), `Academics.coverage_for_plan/1` (`%{rate, planned_hours, covered_hours, ...}`), `coverage_ribbon` `behind?:` attr, kit `<.stat>`.
- Produces: DOM ids `#dashboard-stats`, `#kpi-roster-<plan_id>`, `#kpi-coverage-<plan_id>`. Keeps `#teacher-dashboard`, `#coverage-kpis`, `#kpi-<plan_id>`, `#academic-year-setup-gate`.

- [ ] **Step 1: Write the failing tests**

Append to `dashboard_live_test.exs` (mirror its existing setup that creates a year + plan; adapt bindings):

```elixir
  test "shows the at-a-glance strip and per-card roster/coverage links", %{conn: conn} = context do
    {:ok, view, _html} = live(conn, ~p"/teacher")

    assert has_element?(view, "#dashboard-stats")
    assert render(element(view, "#dashboard-stats")) =~ "Classes"
    # one plan exists in setup
    plan_id = context[:plan].id
    assert has_element?(view, "#kpi-roster-#{plan_id}")
    assert has_element?(view, "#kpi-coverage-#{plan_id}")
  end
```

If the existing setup doesn't expose `plan`, fetch it inside the test: `plan = TeacherAssistant.Academics.list_progression_plans(ws) |> List.first()` (binding `ws` from the setup context).

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
Expected: new test FAILS (no `#dashboard-stats`); existing PASS.

- [ ] **Step 3: Implement**

In `dashboard_live.ex` `mount`, extend the `if year` branch:

```elixir
      if year do
        ws = scope.current_workspace
        plans = Academics.list_progression_plans(ws)
        kpis = Enum.map(plans, fn p -> %{plan: p, coverage: Academics.coverage_for_plan(p)} end)
        contexts_count = length(Academics.list_teaching_contexts(ws, year))
        current_seq = Academics.current_sequence(year, Date.utc_today())

        assign(socket,
          year: year,
          kpis: kpis,
          contexts_count: contexts_count,
          current_seq: current_seq,
          overall_rate: overall_rate(kpis),
          elapsed: elapsed_fraction(year)
        )
      else
        assign(socket, year: nil, kpis: [])
      end
```

with helpers:

```elixir
  defp overall_rate([]), do: nil

  defp overall_rate(kpis) do
    planned = Enum.reduce(kpis, Decimal.new(0), &Decimal.add(&1.coverage.planned_hours, &2))
    covered = Enum.reduce(kpis, Decimal.new(0), &Decimal.add(&1.coverage.covered_hours, &2))

    if Decimal.equal?(planned, Decimal.new(0)),
      do: nil,
      else: Decimal.to_float(Decimal.div(covered, planned))
  end

  defp elapsed_fraction(year) do
    total = max(Date.diff(year.end_date, year.start_date), 1)
    (Date.diff(Date.utc_today(), year.start_date) / total) |> min(1.0) |> max(0.0)
  end

  # behind when coverage trails the elapsed school year by >10 points
  defp behind?(rate, elapsed), do: rate + 0.10 < elapsed
```

In `render/1`, insert the strip between `<.page_header>` and the import-link div:

```heex
          <div id="dashboard-stats" class="grid grid-cols-3 gap-2">
            <.stat label={gettext("Classes")} value={"#{@contexts_count}"} />
            <.stat
              label={gettext("Overall coverage")}
              value={(@overall_rate && "#{round(@overall_rate * 100)}") || "—"}
              suffix={@overall_rate && "%"}
              tone={if @overall_rate && behind?(@overall_rate, @elapsed), do: :behind, else: :primary}
            />
            <.stat
              label={gettext("Séquence in progress")}
              value={(@current_seq && "S#{@current_seq.number}") || "—"}
            />
          </div>
```

In each KPI card, pass the behind flag to the ribbon and add the two links after the "Results" link:

```heex
              <.coverage_ribbon
                rate={kpi.coverage.rate * 100}
                behind?={behind?(kpi.coverage.rate, @elapsed)}
              />
```

```heex
                <.link
                  id={"kpi-roster-#{kpi.plan.id}"}
                  navigate={~p"/teacher/contexts/#{kpi.plan.teaching_context_id}/roster"}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Roster")}
                </.link>
                <.link
                  id={"kpi-coverage-#{kpi.plan.id}"}
                  navigate={~p"/teacher/plans/#{kpi.plan.id}/coverage"}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Coverage")}
                </.link>
```

**Check the coverage route first** in `router.ex` (`grep coverage lib/teacher_assistant_web/router.ex`) and use the actual path helper (it may be `~p"/teacher/coverage/#{kpi.plan.id}"`).

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/dashboard_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/dashboard_live.ex test/teacher_assistant_web/live/teacher/dashboard_live_test.exs
git commit -m "feat(dashboard): at-a-glance stat strip, roster/coverage card links, behind-schedule ribbon accent"
```

---

### Task 5: Coverage — stat cell, per-séquence breakdown, hours on uncovered rows, empty state

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/coverage_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/coverage_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `@coverage.by_sequence` (`%{sequence_id | nil => %{planned, covered, rate}}`), `@coverage.per_entry` (list of `%{entry_id, sequence_id, planned, covered}`), `Academics.list_sequences/1`, `Academics.current_academic_year/1`, kit `<.stat>`, `<.empty_state>`, `coverage_ribbon`.
- Produces: DOM ids `#coverage-by-sequence`, `#coverage-seq-<sequence_id>`. Keeps `#teacher-coverage`, `#coverage-summary`, `#uncovered-entries`, `#uncovered-<entry_id>`.

- [ ] **Step 1: Write the failing tests**

Append to `coverage_live_test.exs` (adapt to its setup; it needs a plan with entries assigned to a séquence and a log):

```elixir
  test "shows per-séquence breakdown with hours", %{conn: conn} = context do
    plan = context[:plan] || TeacherAssistant.Academics.list_progression_plans(context.ws) |> List.first()
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}/coverage")

    assert has_element?(view, "#coverage-by-sequence")
    # at least one séquence row renders with an hours figure like "0h / 2h"
    assert render(element(view, "#coverage-by-sequence")) =~ "h"
  end
```

(Adapt the `live/2` path to the actual coverage route from `router.ex`. If the setup's entries carry no `sequence_id`, the nil-séquence row "Sans séquence" renders — assert that instead: `assert render(element(view, "#coverage-by-sequence")) =~ "Sans séquence"`.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/coverage_live_test.exs`
Expected: new FAIL; existing PASS.

- [ ] **Step 3: Implement**

In `mount`, add sequences + a per-entry lookup:

```elixir
        year = Academics.current_academic_year(ws)
        sequences = (year && Academics.list_sequences(year)) || []
        per_entry = Map.new(coverage.per_entry, fn pe -> {pe.entry_id, pe} end)

        {:ok,
         assign(socket,
           plan: plan,
           coverage: coverage,
           uncovered: uncovered,
           sequences: sequences,
           per_entry: per_entry
         )}
```

In `render/1`:

(a) Replace the big-number block inside `#coverage-summary` with `<.stat>` (keep the ribbon and hours):

```heex
        <div id="coverage-summary" class="ta-leaf flex flex-col gap-4">
          <div class="flex items-end justify-between gap-4">
            <.stat
              label={gettext("covered")}
              value={"#{round(@coverage.rate * 100)}"}
              suffix="%"
              tone={:primary}
            />
            <div class="text-right text-sm text-base-content/65">
              <div class="ta-num mt-1 font-semibold text-base-content">
                {@coverage.covered_hours}h / {@coverage.planned_hours}h
              </div>
            </div>
          </div>
          <.coverage_ribbon rate={@coverage.rate * 100} />
        </div>
```

(b) Insert the per-séquence breakdown between the summary and the uncovered list:

```heex
        <div :if={map_size(@coverage.by_sequence) > 0} class="space-y-3">
          <h2 class="ta-eyebrow">{gettext("By séquence")}</h2>
          <ul id="coverage-by-sequence" class="space-y-2">
            <li
              :for={s <- @sequences}
              :if={@coverage.by_sequence[s.id]}
              id={"coverage-seq-#{s.id}"}
              class="ta-leaf flex items-center gap-3 text-sm"
            >
              <span class="w-24 shrink-0 font-semibold">{gettext("Séquence")} {s.number}</span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{round(@coverage.by_sequence[s.id].rate * 100)}%"}
                >
                </div>
              </div>
              <span class="ta-num w-24 shrink-0 text-right text-base-content/70">
                {@coverage.by_sequence[s.id].covered}h / {@coverage.by_sequence[s.id].planned}h
              </span>
            </li>
            <li
              :if={@coverage.by_sequence[nil]}
              id="coverage-seq-none"
              class="ta-leaf flex items-center gap-3 text-sm"
            >
              <span class="w-24 shrink-0 font-semibold text-base-content/60">
                {gettext("Sans séquence")}
              </span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{round(@coverage.by_sequence[nil].rate * 100)}%"}
                >
                </div>
              </div>
              <span class="ta-num w-24 shrink-0 text-right text-base-content/70">
                {@coverage.by_sequence[nil].covered}h / {@coverage.by_sequence[nil].planned}h
              </span>
            </li>
          </ul>
        </div>
```

(c) On each uncovered row, append the hours; replace the row content:

```heex
            <li
              :for={e <- @uncovered}
              id={"uncovered-#{e.id}"}
              class="ta-leaf flex items-baseline gap-2 text-sm"
            >
              <span class="font-semibold">{e.module}</span>
              <span class="text-base-content/45">·</span>
              <span class="flex-1 text-base-content/75">{e.lesson_title}</span>
              <span :if={@per_entry[e.id]} class="ta-num shrink-0 text-base-content/60">
                {@per_entry[e.id].covered}h / {@per_entry[e.id].planned}h
              </span>
            </li>
```

(d) Replace the "Everything is covered" `<li>` with an `<.empty_state>` **outside** the `ul` (keep the `ul` for the non-empty case only):

```heex
          <ul :if={@uncovered != []} id="uncovered-entries" class="space-y-2">
            ...rows...
          </ul>
          <.empty_state
            :if={@uncovered == []}
            icon="hero-check-circle"
            title={gettext("Everything is covered.")}
          />
```

**Check existing tests first:** if one asserts `#uncovered-entries` exists when empty, keep the id on a wrapper div around the empty state instead.

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/coverage_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/coverage_live.ex test/teacher_assistant_web/live/teacher/coverage_live_test.exs
git commit -m "feat(coverage): stat cell, per-séquence breakdown bars with hours, hours on uncovered rows, empty state"
```

---

### Task 6: Fiche builder — responsive entries table + planned-hours total

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/fiche_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/fiche_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `@entries` (structs with `module`, `lesson_title`, `entry_type`, `planned_hours` Decimal), `Academics.get_teaching_context/1`, `@plan.teaching_context_id`, kit `<.stat>`.
- Produces: DOM ids `#fiche-hours-total`, `#entry-delete-<id>`. Keeps `#fiche-builder`, `#fiche-entries` (moves onto the `<table>`), `#entry-<id>` (now `<tr>`s), `#add-entry-form`, `#add-entry-submit`, `#duplicate-plan`.

- [ ] **Step 1: Write the failing tests**

Append to `fiche_live_test.exs` (adapt to its setup; a plan with ≥1 entry):

```elixir
  test "shows a running planned-hours total", %{conn: conn} = context do
    plan = context[:plan] || TeacherAssistant.Academics.list_progression_plans(context.ws) |> List.first()
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    assert has_element?(view, "#fiche-hours-total")
    assert render(element(view, "#fiche-hours-total")) =~ "h"
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: new FAIL; existing PASS.

- [ ] **Step 3: Implement**

Add helpers to `fiche_live.ex`:

```elixir
  defp hours_total(entries) do
    Enum.reduce(entries, Decimal.new(0), fn e, acc -> Decimal.add(acc, e.planned_hours) end)
  end

  defp weeks_estimate(_total, nil), do: nil

  defp weeks_estimate(total, weekly_hours) when weekly_hours > 0 do
    total |> Decimal.div(Decimal.new(weekly_hours)) |> Decimal.round(0, :ceiling) |> Decimal.to_string()
  end

  defp weeks_estimate(_total, _), do: nil
```

In `assign_entries/2`, also assign the context (once):

```elixir
  defp assign_entries(socket, plan) do
    ctx =
      case Academics.get_teaching_context(plan.teaching_context_id) do
        {:ok, ctx} -> ctx
        _ -> nil
      end

    socket
    |> assign(:plan, plan)
    |> assign(:ctx, ctx)
    |> assign(:entries, Academics.list_progression_entries(plan))
    |> assign(:entry_form, to_form(%{}, as: :entry))
  end
```

In `render/1`, insert the hours stat under the page header:

```heex
        <div id="fiche-hours-total" class="flex items-center gap-3">
          <.stat label={gettext("Planned hours")} value={Decimal.to_string(hours_total(@entries))} suffix="h" />
          <p :if={@ctx && weeks_estimate(hours_total(@entries), @ctx.weekly_hours)} class="text-sm text-base-content/60">
            {gettext("≈ %{weeks} weeks at %{hours} h/week", weeks: weeks_estimate(hours_total(@entries), @ctx.weekly_hours), hours: @ctx.weekly_hours)}
          </p>
        </div>
```

Replace the `#fiche-entries` `<ul>` with the responsive table (add-entry form unchanged):

```heex
        <table :if={@entries != []} id="fiche-entries" class="w-full border-separate border-spacing-y-1">
          <caption class="sr-only">{gettext("Progression entries")}</caption>
          <thead class="hidden md:table-header-group">
            <tr class="text-left">
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Module")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Leçon")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1">{gettext("Type")}</th>
              <th scope="col" class="ta-eyebrow px-3 pb-1 text-right">{gettext("Heures")}</th>
              <th scope="col" class="px-3 pb-1"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody class="block space-y-2 md:table-row-group">
            <tr :for={e <- @entries} id={"entry-#{e.id}"} class="ta-leaf block md:table-row">
              <td class="hidden md:table-cell md:px-3 md:py-2 text-sm text-base-content/65">
                {e.module}
              </td>
              <td class="flex items-center justify-between gap-2 md:table-cell md:px-3 md:py-2">
                <span>
                  <span class="font-display font-semibold">{e.lesson_title}</span>
                  <span class="mt-0.5 block text-sm text-base-content/65 md:hidden">
                    {e.module} <span class="text-base-content/40">·</span>
                    <span class="ta-num">{e.planned_hours}h</span>
                    <span class="badge badge-soft badge-sm ml-1">{e.entry_type}</span>
                  </span>
                </span>
                <.button
                  phx-click="delete-entry"
                  phx-value-id={e.id}
                  class="btn btn-ghost btn-xs text-error md:hidden"
                >
                  <.icon name="hero-trash" class="size-4" />
                  <span class="sr-only">{gettext("Delete")}</span>
                </.button>
              </td>
              <td class="hidden md:table-cell md:px-3 md:py-2">
                <span class="badge badge-soft badge-sm">{e.entry_type}</span>
              </td>
              <td class="hidden md:table-cell md:px-3 md:py-2 ta-num text-right">
                {e.planned_hours}h
              </td>
              <td class="hidden md:table-cell md:px-3 md:py-2 text-right">
                <.button
                  id={"entry-delete-#{e.id}"}
                  phx-click="delete-entry"
                  phx-value-id={e.id}
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                  <span class="sr-only">{gettext("Delete")}</span>
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
        <.empty_state
          :if={@entries == []}
          icon="hero-document-text"
          title={gettext("No entries yet — add your first lesson below.")}
        />
```

**Check existing tests:** if a test clicks the delete button via a selector inside `#entry-<id>`, the mobile button (no id) still matches `button[phx-click=delete-entry]` within the row; if a test asserts the empty-state string, it's preserved verbatim in the `<.empty_state>` title.

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/fiche_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/fiche_live.ex test/teacher_assistant_web/live/teacher/fiche_live_test.exs
git commit -m "feat(fiche): responsive entries table, planned-hours total with weeks estimate, empty state via kit"
```

---

### Task 7: Import — visible stepper, md: row grid with headers, raw-text disclosure, overflow fold

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/import_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/import_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `@stage` (`:upload` | `:review`), `@rows`, `@raw_text`, `@confidence`; all existing events unchanged.
- Produces: DOM ids `#import-stepper`, `#import-rows-header`, `#import-rows-overflow`, `#import-raw-details`. Keeps every existing `#import-*` id (including `#import-raw-text` on the `<pre>`, now inside the details).

- [ ] **Step 1: Write the failing tests**

Append to `import_live_test.exs`:

```elixir
  test "shows the three-step stepper on the upload stage", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/import")

    assert has_element?(view, "#import-stepper")
    html = render(element(view, "#import-stepper"))
    assert html =~ "Upload"
    assert html =~ "Review"
    assert html =~ "Save"
  end
```

(The review-stage stepper state and overflow fold are covered by the implementation below; the existing review-stage tests exercise those templates.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: new FAIL; existing PASS.

- [ ] **Step 3: Implement**

(a) Stepper right under `<.page_header>` (daisyUI steps; requires `@contexts != []` not needed — show always):

```heex
        <ul id="import-stepper" class="steps w-full text-xs">
          <li class="step step-primary">{gettext("Upload")}</li>
          <li class={["step", @stage == :review && "step-primary"]}>{gettext("Review")}</li>
          <li class="step">{gettext("Save")}</li>
        </ul>
```

(b) Raw-text progressive disclosure — replace the bare `<pre id="import-raw-text" ...>` with:

```heex
            <details id="import-raw-details">
              <summary class="cursor-pointer text-sm font-semibold">
                {gettext("Show extracted text")}
              </summary>
              <pre
                id="import-raw-text"
                class="ta-num max-h-48 overflow-auto whitespace-pre-wrap text-xs text-base-content/60"
              >{@raw_text}</pre>
            </details>
```

(c) md: column headers above `#import-rows` and single-line rows at `md:`. Add the header:

```heex
            <div
              id="import-rows-header"
              class="hidden gap-2 px-3 md:grid md:grid-cols-[1fr_1.5fr_5rem_8rem_4rem_7rem_2.5rem]"
            >
              <span class="ta-eyebrow">{gettext("Module")}</span>
              <span class="ta-eyebrow">{gettext("Lesson")}</span>
              <span class="ta-eyebrow">{gettext("Hours")}</span>
              <span class="ta-eyebrow">{gettext("Type")}</span>
              <span class="ta-eyebrow">{gettext("Week")}</span>
              <span class="ta-eyebrow">{gettext("Sequence")}</span>
              <span></span>
            </div>
```

and restructure each row `<li>`'s inner markup: replace the two stacked `div.grid` groups + delete button with ONE wrapper

```heex
                <div class="grid gap-2 sm:grid-cols-2 md:grid-cols-[1fr_1.5fr_5rem_8rem_4rem_7rem_2.5rem] md:items-center">
                  ...the 6 existing inputs/selects in this order: module, lesson_title, planned_hours, entry_type, week_no, sequence_id (names and attributes unchanged)...
                  <button
                    type="button"
                    phx-click="delete-row"
                    phx-value-index={i}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-trash" class="size-4" />
                    <span class="sr-only">{gettext("Delete row")}</span>
                  </button>
                </div>
```

(d) Overflow fold — replace the single `#import-rows` list with a split at 100:

```heex
            <ul id="import-rows" class="space-y-2">
              <li
                :for={{row, i} <- Enum.with_index(@rows) |> Enum.take(100)}
                id={"import-row-#{i}"}
                class="ta-leaf space-y-2"
              >
                ...row markup from (c)...
              </li>
            </ul>
            <details :if={length(@rows) > 100} id="import-rows-overflow">
              <summary class="cursor-pointer text-sm font-semibold">
                {gettext("Show remaining %{count} rows", count: length(@rows) - 100)}
              </summary>
              <ul class="mt-2 space-y-2">
                <li
                  :for={{row, i} <- Enum.with_index(@rows) |> Enum.drop(100)}
                  id={"import-row-#{i}"}
                  class="ta-leaf space-y-2"
                >
                  ...row markup from (c)...
                </li>
              </ul>
            </details>
```

To avoid duplicating the row markup, extract it into a function component in the same module:

```elixir
  attr :row, :map, required: true
  attr :i, :integer, required: true
  attr :sequences, :list, required: true

  defp import_row(assigns) do
    ~H"""
    <li id={"import-row-#{@i}"} class="ta-leaf space-y-2">
      <div class="grid gap-2 sm:grid-cols-2 md:grid-cols-[1fr_1.5fr_5rem_8rem_4rem_7rem_2.5rem] md:items-center">
        <input
          name={"rows[#{@i}][module]"}
          value={@row.module}
          placeholder={gettext("Module")}
          class="w-full input input-sm"
        />
        <input
          name={"rows[#{@i}][lesson_title]"}
          value={@row.lesson_title}
          placeholder={gettext("Lesson")}
          class="w-full input input-sm"
        />
        <input
          name={"rows[#{@i}][planned_hours]"}
          value={@row.planned_hours}
          type="number"
          step="0.5"
          placeholder={gettext("Hours")}
          class="w-full input input-sm"
        />
        <select name={"rows[#{@i}][entry_type]"} class="w-full select select-sm">
          <option
            :for={t <- entry_type_options()}
            value={t.key}
            selected={to_string(t.key) == to_string(@row.entry_type)}
          >
            {t.fr}
          </option>
        </select>
        <input
          name={"rows[#{@i}][week_no]"}
          value={@row.week_no}
          type="number"
          placeholder={gettext("Week")}
          class="w-full input input-sm"
        />
        <select name={"rows[#{@i}][sequence_id]"} class="w-full select select-sm">
          <option value="">{gettext("Sequence…")}</option>
          <option :for={s <- @sequences} value={s.id} selected={s.number == @row.sequence_no}>
            {gettext("Seq")} {s.number}
          </option>
        </select>
        <button
          type="button"
          phx-click="delete-row"
          phx-value-index={@i}
          class="btn btn-ghost btn-xs text-error"
        >
          <.icon name="hero-trash" class="size-4" />
          <span class="sr-only">{gettext("Delete row")}</span>
        </button>
      </div>
    </li>
    """
  end
```

and call `<.import_row :for={{row, i} <- ...} row={row} i={i} sequences={@sequences} />` in both lists.

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/import_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/import_live.ex test/teacher_assistant_web/live/teacher/import_live_test.exs
git commit -m "feat(import): visible upload/review/save stepper, md: row grid with headers, raw-text disclosure, 100+ row fold"
```

---

### Task 8: Log — hours default fix, stay-on-save + recent-entries ledger, inline hours validation

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/log_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/log_live_test.exs` (add tests; **one specced assertion change allowed**: save no longer navigates away)

**Interfaces:**
- Consumes: `Academics.list_recent_logs/2` (ws, limit → recent `TeachingLogEntry` structs; verify field names with `grep -n "attribute" lib/teacher_assistant/academics/teaching_log_entry.ex` — expect `date`, `content_taught`, `hours`), `Academics.log_teaching/2`.
- Produces: DOM ids `#log-recent`, `#log-recent-<entry_id>`. Keeps `#teacher-log`, `#log-form`, `#log-submit`. New event `"validate"` (`phx-change`).

- [ ] **Step 1: Write the failing tests**

Append to `log_live_test.exs` (adapt setup bindings; it needs a plan entry to log against):

```elixir
  test "hours field shows its default value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")
    assert view |> element("#log-form input[name='log[hours]']") |> render() =~ ~s(value="1")
  end

  test "saving stays on the page and shows the entry in the recent list", %{conn: conn} = context do
    entry = context[:entry] || hd(TeacherAssistant.Academics.list_progression_entries(context.plan))
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    view
    |> form("#log-form", %{
      "log" => %{
        "progression_entry_id" => entry.id,
        "date" => "2026-07-01",
        "hours" => "2",
        "content_taught" => "Fractions",
        "status" => "done"
      }
    })
    |> render_submit()

    # no navigation; ledger shows the new entry
    assert has_element?(view, "#log-recent", "Fractions")
  end

  test "invalid hours shows an inline error on change", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/log")

    html =
      view
      |> form("#log-form", %{"log" => %{"hours" => "abc"}})
      |> render_change()

    assert html =~ "Enter hours like 1 or 1.5"
  end
```

**Also update** any existing test asserting the old redirect (e.g. `assert_redirect(view, "/teacher")` after save) to instead assert `has_element?(view, "#log-recent")` — this is the specced behavior change (ledger, not lost-in-void submit). Change nothing else in existing tests.

- [ ] **Step 2: Run to verify failures**

Run: `mix test test/teacher_assistant_web/live/teacher/log_live_test.exs`
Expected: new tests FAIL (hours blank, redirect still happens, no validate handler).

- [ ] **Step 3: Implement**

In `log_live.ex`:

(a) `mount`: seed the form with the default and load recents:

```elixir
    {:ok,
     socket
     |> assign(:ws, ws)
     |> assign(:entries, entries)
     |> assign(:recent, (ws && Academics.list_recent_logs(ws, 5)) || [])
     |> assign(:form, to_form(%{"hours" => "1"}, as: :log))}
```

(b) Save: stay on the page, reset form, refresh recents:

```elixir
      {:noreply,
       socket
       |> put_flash(:info, gettext("Logged"))
       |> assign(:recent, Academics.list_recent_logs(ws, 5))
       |> assign(:form, to_form(%{"hours" => "1"}, as: :log))}
```

(c) Inline validation:

```elixir
  def handle_event("validate", %{"log" => p}, socket) do
    errors =
      case Decimal.parse(p["hours"] || "") do
        {_d, ""} -> []
        _ -> [hours: {gettext("Enter hours like 1 or 1.5"), []}]
      end

    {:noreply, assign(socket, :form, to_form(p, as: :log, errors: errors, action: :validate))}
  end
```

(d) Template: add `phx-change="validate"` to the `<.form>`; add `inputmode="decimal"` to the hours input (drop the now-redundant `value="1"` attr — the form carries it); remove the hours `value` prop bug. Beneath the form, add the ledger (verify field names against the resource first):

```heex
        <div :if={@recent != []} class="space-y-2">
          <h2 class="ta-eyebrow">{gettext("Recently logged")}</h2>
          <ul id="log-recent" class="space-y-1">
            <li
              :for={l <- @recent}
              id={"log-recent-#{l.id}"}
              class="ta-leaf flex items-baseline justify-between gap-2 text-sm"
            >
              <span class="flex-1 truncate">{l.content_taught}</span>
              <span class="ta-num shrink-0 text-base-content/60">{l.date} · {l.hours}h</span>
            </li>
          </ul>
        </div>
```

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/log_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/log_live.ex test/teacher_assistant_web/live/teacher/log_live_test.exs
git commit -m "fix(log): hours default renders; stay on save with recent-entries ledger; inline hours validation"
```

---

### Task 9: Setup — stepper affordance, helper text, error clarity with preserved input

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/setup_live.ex`
- Test: `test/teacher_assistant_web/live/teacher/setup_live_test.exs` (add tests; existing must pass)

**Interfaces:**
- Consumes: `Academics.create_academic_year/2` (returns `{:error, %Ash.Error.Invalid{}}` on bad input), `Reference.subsystems/0` etc.
- Produces: DOM ids `#setup-stepper`, helper-text paragraphs `#setup-help-subsystem`, `#setup-help-hours`. Form defaults move from `value=` attrs into the seeded form map (so failed submits preserve input).

- [ ] **Step 1: Write the failing tests**

Append to `setup_live_test.exs`:

```elixir
  test "shows stepper and helper text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    assert has_element?(view, "#setup-stepper")
    assert has_element?(view, "#setup-help-subsystem")
    assert has_element?(view, "#setup-help-hours")
  end

  test "failed setup surfaces the reason and preserves input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    html =
      view
      |> form("#setup-form", %{
        "setup" => %{
          "name" => "My Year",
          "start_date" => "2026-07-01",
          # end before start -> invalid
          "end_date" => "2025-09-01",
          "subsystem" => "francophone",
          "subject" => "Mathématiques",
          "level" => "6ème",
          "weekly_hours" => "4"
        }
      })
      |> render_submit()

    # not the generic message; the actual reason surfaces
    refute html =~ "Could not complete setup."
    # entered name is preserved in the re-rendered form
    assert html =~ "My Year"
  end
```

**Verify first** that `create_academic_year` with end < start actually errors (`grep -n "validate\|end_date" lib/teacher_assistant/academics/academic_year.ex`). If there's no such validation, use `"weekly_hours" => "abc"` as the failing input instead and assert the hours message.

- [ ] **Step 2: Run to verify failures**

Run: `mix test test/teacher_assistant_web/live/teacher/setup_live_test.exs`
Expected: new FAIL; existing PASS.

- [ ] **Step 3: Implement**

In `setup_live.ex`:

(a) Seed defaults in `mount` (so errors can re-render user input) and drop the `value=` attrs from `name/start_date/end_date/weekly_hours` inputs:

```elixir
    {:ok,
     socket
     |> assign(:subsystem, :francophone)
     |> assign(
       :form,
       to_form(
         %{
           "name" => "2025-2026",
           "start_date" => "2025-09-08",
           "end_date" => "2026-07-31",
           "weekly_hours" => "4"
         },
         as: :setup
       )
     )}
```

**Careful with `phx-change="subsystem-changed"`:** the change event submits all fields; re-assign the form from the change params so typing isn't lost:

```elixir
  def handle_event("subsystem-changed", %{"setup" => %{"subsystem" => sub} = p}, socket) do
    {:noreply,
     socket
     |> assign(:subsystem, String.to_existing_atom(sub))
     |> assign(:form, to_form(p, as: :setup))}
  end
```

(b) Safe hours parse + error surfacing in `save`:

```elixir
  def handle_event("save", %{"setup" => p}, socket) do
    ws = socket.assigns.current_scope.current_workspace

    with {wh, ""} <- Integer.parse(p["weekly_hours"] || ""),
         {:ok, year} <-
           Academics.create_academic_year(ws, %{
             name: p["name"],
             start_date: p["start_date"],
             end_date: p["end_date"],
             active: true
           }),
         :ok <- Academics.build_default_calendar(year),
         {:ok, _ctx} <-
           Academics.create_teaching_context(ws, year, %{
             subject: p["subject"],
             level: p["level"],
             subsystem: String.to_existing_atom(p["subsystem"]),
             weekly_hours: wh
           }) do
      {:noreply,
       socket |> put_flash(:info, gettext("Setup complete")) |> push_navigate(to: ~p"/teacher")}
    else
      error ->
        {:noreply,
         socket
         |> assign(:form, to_form(p, as: :setup))
         |> put_flash(:error, setup_error(error))}
    end
  end

  defp setup_error(:error),
    do: gettext("Weekly hours must be a whole number, e.g. 4")

  defp setup_error({_n, _rest}),
    do: gettext("Weekly hours must be a whole number, e.g. 4")

  defp setup_error({:error, %{errors: [first | _]}}) do
    detail =
      case first do
        %{field: field, message: message} when not is_nil(field) -> "#{field}: #{message}"
        %{message: message} when is_binary(message) -> message
        other -> Exception.message(other)
      end

    gettext("Could not complete setup") <> " — " <> detail
  end

  defp setup_error(_), do: gettext("Could not complete setup")
```

(Note `Integer.parse("4abc")` returns `{4, "abc"}` which fails the `{wh, ""}` match and lands in the `{_n, _rest}` clause; a non-numeric string returns `:error`.)

(c) Stepper + helper text in the template — stepper above the form:

```heex
        <ul id="setup-stepper" class="steps w-full text-xs">
          <li class="step step-primary">{gettext("Année")}</li>
          <li class="step step-primary">{gettext("Classe")}</li>
        </ul>
```

Helper paragraphs directly under the subsystem select and weekly-hours input:

```heex
            <p id="setup-help-subsystem" class="text-xs text-base-content/55">
              {gettext("Francophone or Anglophone track — this sets the class levels you can pick.")}
            </p>
```

```heex
            <p id="setup-help-hours" class="text-xs text-base-content/55">
              {gettext("Hours per week on your timetable for this subject and class.")}
            </p>
```

- [ ] **Step 4: Run tests**

Run: `mix test test/teacher_assistant_web/live/teacher/setup_live_test.exs`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/setup_live.ex test/teacher_assistant_web/live/teacher/setup_live_test.exs
git commit -m "feat(setup): stepper affordance, helper text, real error reasons with preserved input"
```

---

### Task 10: Gettext extraction + FR translations + full-suite gate

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po` (via `mix gettext.extract --merge`)

**Interfaces:**
- Consumes: every `gettext(...)` msgid added in Tasks 1–9.
- Produces: FR catalog complete for the new strings; EN catalog auto-merged (EN msgids are their own msgstr — leave empty msgstr, Gettext falls back to msgid).

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`
Expected: new msgids appear in the `.pot` and both `.po` files.

- [ ] **Step 2: Fill the FR msgstr for the new msgids**

In `priv/gettext/fr/LC_MESSAGES/default.po`, set `msgstr` for every newly added empty entry. Use exactly:

| msgid | FR msgstr |
|---|---|
| students | élèves |
| Filles | Filles |
| Garçons | Garçons |
| Fille | Fille |
| Garçon | Garçon |
| Add a student | Ajouter un élève |
| %{name} removed. | %{name} retiré(e). |
| Undo | Annuler |
| Could not restore the student | Impossible de restaurer l'élève |
| Remove %{name} from the roster? | Retirer %{name} de l'effectif ? |
| Class roster | Effectif de la classe |
| Élève | Élève |
| Sexe | Sexe |
| Matricule | Matricule |
| Actions | Actions |
| No students yet — add your first with the form above. | Aucun élève pour l'instant — ajoutez le premier avec le formulaire ci-dessus. |
| %{entered} of %{total} entered | %{entered} sur %{total} saisies |
| Class average | Moyenne de classe |
| Blank = absent. Marks are out of 20. | Vide = absent. Les notes sont sur 20. |
| Abs | Abs |
| Pass rate — filles / garçons | Taux de réussite — filles / garçons |
| %{count} student(s) without marks in this séquence | %{count} élève(s) sans note dans cette séquence |
| Per-student results | Résultats par élève |
| Rang | Rang |
| Moyenne | Moyenne |
| Mention | Mention |
| Highest | Note maximale |
| Lowest | Note minimale |
| No marks in this séquence yet | Pas encore de notes dans cette séquence |
| Enter marks for an assessment to see the séquence results. | Saisissez les notes d'une évaluation pour voir les résultats de la séquence. |
| Enter marks | Saisir les notes |
| Classes | Classes |
| Overall coverage | Couverture globale |
| Séquence in progress | Séquence en cours |
| By séquence | Par séquence |
| Sans séquence | Sans séquence |
| Planned hours | Heures prévues |
| ≈ %{weeks} weeks at %{hours} h/week | ≈ %{weeks} semaines à %{hours} h/sem |
| Module | Module |
| Leçon | Leçon |
| Type | Type |
| Heures | Heures |
| Progression entries | Entrées de la progression |
| Upload | Téléversement |
| Review | Vérification |
| Save | Enregistrement |
| Show extracted text | Afficher le texte extrait |
| Show remaining %{count} rows | Afficher les %{count} lignes restantes |
| Lesson | Leçon |
| Hours | Heures |
| Week | Semaine |
| Sequence | Séquence |
| Recently logged | Enregistrées récemment |
| Enter hours like 1 or 1.5 | Saisissez les heures comme 1 ou 1,5 |
| Année | Année |
| Classe | Classe |
| Francophone or Anglophone track — this sets the class levels you can pick. | Sous-système francophone ou anglophone — il détermine les classes proposées. |
| Hours per week on your timetable for this subject and class. | Heures par semaine à l'emploi du temps pour cette matière et cette classe. |
| Weekly hours must be a whole number, e.g. 4 | Les heures hebdomadaires doivent être un nombre entier, ex. 4 |
| Could not complete setup | Impossible de terminer la configuration |

Only fill entries `gettext.extract` actually added and that are empty; never overwrite existing non-empty msgstr; skip any listed string that wasn't extracted (wording drift) and instead translate the msgid that WAS extracted. Note "Hours"/"Module"/"Lesson" may already exist from earlier phases — leave them if translated.

- [ ] **Step 3: Full gate**

Run: `mix precommit`
Expected: compile (warnings-as-errors) clean, format clean, ALL tests pass (≥120 expected).

- [ ] **Step 4: Commit**

```bash
git add priv/gettext
git commit -m "chore(i18n): extract + FR translations for P1/P2 design-pass strings"
```

---

## Self-Review (done at plan time)

- **Spec coverage:** §2.8 roster (Task 1), §2.9 marks (Task 2), §2.10 summary (Task 3), §2.2 dashboard (Task 4), §2.5 coverage (Task 5), §2.4 fiche (Task 6), §2.7 import (Task 7), §2.6 log (Task 8), §2.3 setup (Task 9), gettext (Task 10). Deliberately **out of scope**: sortable tables ("where useful" — none critical), summary inline-bar on mobile (md: only), fiche sticky add-row (form stays below table), import row *virtualization* (fold instead, cap is 300).
- **P1 DoD:** tables at `md:` + cards below ✓ (Tasks 1–3), `ta-num` numerics ✓, mention word+icon ✓ (existing `mention_badge`), DOM ids preserved ✓.
- **P2 DoD:** each page's listed change ✓; log hours-field and setup error-reason fixes explicitly tested ✓ (Tasks 8–9).
- **Type consistency:** `fmt/1`, `pct/1` exist in summary already; `fmt_avg/1` added in marks; `bar_width/1` handles Decimal (avg/20) and float (rate) — both call sites match. `sibling_scores` keyed `{student_id, assessment_id}` matches its lookup. `Marks.summarize/3` signature matches all three call sites.
