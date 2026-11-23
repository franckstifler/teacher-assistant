# Bilan des absences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A « Bilan des absences » page (and its A4 print) where a conduct manager picks a
period and « Toutes les classes » or one class and reads each student's absence totals, the
figures the bulletin prints, with students at or over a typed threshold marked.

**Architecture:** The figures come from `Attendance.bulletin_conduct/3` per class; a new
`Attendance.absence_totals/3` assembles them with the roster in roll order. A pure module
`AbsenceTotals` holds the threshold rules and the « over threshold » filter. One web helper
resolves the URL params (period, class, threshold) for both the LiveView and the print
controller, so screen and paper always agree.

**Tech Stack:** Phoenix 1.8 LiveView, Ash, gettext FR/EN, daisyUI/Tailwind v4.

**Spec:** `docs/superpowers/specs/2026-11-23-absence-totals-design.md`

## Global Constraints

- Route `/school/absence-totals` (not under `/school/absences/`: `Spaces.path_under_item?/2`
  would light « Absences » for it); print at `/school/absence-totals/print`.
- Access: `Discipline.can_manage_conduct?/1`; module `:discipline` for the view and the print.
- Threshold default: 20 h per séquence × the period's séquences (`Organization.period_sequences/2`).
- URL params: `period` (`Organization.period_param/1` format: `seq:<id>`, `trim:<id>`, `annee`),
  `class` (class group id, absent = all classes), `seuil` (hours, decimal, comma or dot).
- The school's `absence_alert_hours` is not used or changed by this page.
- Copy (FR source strings): « Bilan des absences », « Toutes les classes », « Seuil », « Année »,
  « saisi », « non saisi », « Aucun élève au-dessus du seuil », « Imprimer ».
- Every new gettext entry extracted with `MIX_ENV=test mix gettext.extract --merge`, English
  filled, no fuzzy flag left. `mix precommit` green before each commit. Stage explicit paths.

## Review Focus

1. A typed class with a student who has no figure yet: shows « non saisi », never counted over the threshold (Task 1 test).
2. A threshold typed as « 12,5 », « abc », « -3 » or empty: comma accepted; anything not a positive number falls back to the default (Task 1 test).
3. A `class` param naming another school's class or a past year's class: treated as « Toutes les classes », no crash (Task 2 test).
4. A school with no séquences yet (start of setup): page shows an empty state instead of crashing (Task 2 test).
5. A student who left mid-period: follows the bulletin's roster (class on the period's first day), as `bulletin_conduct/3` does — no extra rule (covered by reuse; Task 1 test asserts roster order only).

---

### Task 1: Totals and threshold rules

**Files:**
- Create: `lib/teacher_assistant/academics/absence_totals.ex`
- Modify: `lib/teacher_assistant/attendance.ex` (next to `bulletin_conduct/4`)
- Test: `test/teacher_assistant/academics/absence_totals_test.exs`

**Interfaces:**
- Produces:
  - `AbsenceTotals.default_threshold(sequence_count :: non_neg_integer) :: Decimal.t()` — `20 × count` (count 0 → 20).
  - `AbsenceTotals.parse_threshold(param :: String.t() | nil, default :: Decimal.t()) :: Decimal.t()` — accepts « 12,5 » and « 12.5 »; not a number or ≤ 0 → `default`.
  - `AbsenceTotals.flagged?(row, threshold) :: boolean` — `row.unjustified_hours >= threshold`.
  - `AbsenceTotals.over_threshold(groups, threshold) :: [group]` — keeps flagged rows only, sorted by `unjustified_hours` descending (ties: name), drops groups left empty; group order kept.
  - `Attendance.absence_totals(scope, period, class_groups) :: [group]` where
    `group = %{class_group: ClassGroup.t(), source: :roll_call | :typed, rows: [row]}` and
    `row = %{enrollment: Enrollment.t(), student: Student.t(), unjustified_hours: Decimal.t(), justified_hours: Decimal.t(), retards: integer, recorded?: boolean}`;
    rows in roll order (`Enrollment.list_roster(scope, cg, on: Organization.period_first_day(scope, period))`),
    figures from `bulletin_conduct(scope, cg, period)`; groups in the order of `class_groups`.

- [ ] **Step 1: Write the failing tests** — setup copied from `test/teacher_assistant/academics/bulletin_conduct_test.exs` (school, year, default calendar, class « 6e A » with Awa and Bob, one app absence for Awa on 2025-09-08 in séquence 1).

```elixir
test "default threshold is 20 h per séquence" do
  assert AbsenceTotals.default_threshold(1) == Decimal.new(20)
  assert AbsenceTotals.default_threshold(3) == Decimal.new(60)
  assert AbsenceTotals.default_threshold(0) == Decimal.new(20)
end

test "parse_threshold takes a comma, falls back on anything else" do
  d = Decimal.new(20)
  assert AbsenceTotals.parse_threshold("12,5", d) == Decimal.new("12.5")
  assert AbsenceTotals.parse_threshold("8", d) == Decimal.new(8)
  for bad <- [nil, "", "abc", "-3", "0"], do: assert(AbsenceTotals.parse_threshold(bad, d) == d)
end

test "over_threshold keeps flagged students, most hours first, drops empty classes" do
  row = fn name, h -> %{student: %{full_name: name}, unjustified_hours: Decimal.new(h)} end
  a = %{class_group: %{id: "a"}, source: :roll_call, rows: [row.("Ali", 3), row.("Ben", 25), row.("Cyr", 21)]}
  b = %{class_group: %{id: "b"}, source: :roll_call, rows: [row.("Dan", 5)]}

  assert [%{class_group: %{id: "a"}, rows: rows}] =
           AbsenceTotals.over_threshold([a, b], Decimal.new(20))

  assert Enum.map(rows, & &1.student.full_name) == ["Ben", "Cyr"]
end

test "absence_totals gives the bulletin's figures in roll order", ctx do
  [g] = Attendance.absence_totals(ctx.scope, {:sequence, ctx.s1}, [ctx.cg])
  assert g.source == :roll_call
  assert Enum.map(g.rows, & &1.student.full_name) == ["Awa", "Bob"]
  assert Decimal.gt?(hd(g.rows).unjustified_hours, 0)
end

test "a typed class shows typed hours and an unrecorded student", ctx do
  cg = typed(ctx, :typed_per_sequence)            # helper as in bulletin_conduct_test
  set_seq(ctx, ctx.awa, ctx.s1, "25")
  [g] = Attendance.absence_totals(ctx.scope, {:sequence, ctx.s1}, [cg])
  assert g.source == :typed
  [awa, bob] = g.rows
  assert awa.unjustified_hours == Decimal.new(25) and awa.recorded?
  refute bob.recorded?
  assert [%{rows: [%{student: %{full_name: "Awa"}}]}] =
           AbsenceTotals.over_threshold([g], Decimal.new(20))
end
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=7 mix test test/teacher_assistant/academics/absence_totals_test.exs` — Expected: FAIL (module `AbsenceTotals` undefined).
- [ ] **Step 3: Implement** `AbsenceTotals` (pure, no DB) and `Attendance.absence_totals/3` with the signatures above. `group.source` is `:roll_call` or `:typed` from any row's `:source` (`bulletin_conduct` tags every row), `:roll_call` for an empty class.
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit** `feat(attendance): absence totals per class for a period, threshold rules`.

### Task 2: The page

**Files:**
- Create: `lib/teacher_assistant_web/live/school/absence_totals_params.ex` (module `TeacherAssistantWeb.School.AbsenceTotalsParams`)
- Create: `lib/teacher_assistant_web/live/school/absence_totals_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`live "/school/absence-totals", School.AbsenceTotalsLive, :index` next to `/school/absences`)
- Modify: `lib/teacher_assistant/modules.ex` (`W.School.AbsenceTotalsLive` under `discipline:`)
- Modify: `lib/teacher_assistant_web/spaces.ex` (item `absence_totals/0`: id `"absence-totals"`, label « Bilan des absences », icon `hero-chart-bar`, path `~p"/school/absence-totals"`; in the surveillant's « Vie scolaire » right after `absences(...)`)
- Modify: `test/teacher_assistant_web/spaces_test.exs:190-199` (surveillant list gains `"nav-school-absence-totals"` after `"nav-school-absences"`)
- Test: `test/teacher_assistant_web/live/school/absence_totals_live_test.exs`

**Interfaces:**
- Consumes: Task 1 (`Attendance.absence_totals/3`, `AbsenceTotals.*`).
- Produces: `AbsenceTotalsParams.resolve(scope, params) :: {:ok, view} | :no_sequences` with
  `view = %{period: period_tuple, period_param: String.t(), class_group: ClassGroup.t() | nil, class_groups: [ClassGroup.t()], sequences: [Sequence.t()], terms: [Term.t()], threshold: Decimal.t(), default_threshold: Decimal.t(), sequence_count: integer, groups: [group]}` —
  `groups` already filtered: all classes → `AbsenceTotals.over_threshold/2`; one class → that class's full group.
  Period: `Organization.resolve_period/3` on `params["period"]`, else the current séquence (`EntryProgress.default_sequence/2` with `Reference.today()`).
  Class: one of `Enrollment.list_class_groups(scope, year)` (sorted by `SchoolTemplates.class_sort_key/1`) whose id is `params["class"]`, else nil.
  Also `AbsenceTotalsParams.query(view, overrides \\ []) :: keyword` — the URL params (`period`, `class` when set, `seuil` only when ≠ default) for links and the print.

- [ ] **Step 1: Write the failing LiveView tests** (conn as head, who manages conduct; data as Task 1):
  - `"lists every student of one class with source and figures"` — `live(conn, ~p"/school/absence-totals?class=#{cg.id}")`; `#absence-row-#{awa.id}` and `#absence-row-#{bob.id}` present; `#absence-source` has « appel ».
  - `"all classes shows only students at or over the threshold"` — with `seuil=0,5`: Awa's row present, Bob's absent; with default (20): `#absence-empty` has « Aucun élève au-dessus du seuil ».
  - `"a trimester pre-fills 20 h per séquence"` — `?period=trim:#{t1.id}` → `#absence-threshold` input value `"60"` (three séquences in the default calendar's first term; assert against `20 * length(t1.sequences)`).
  - `"changing the pickers patches the URL"` — `render_change(form("#absence-totals-form"), %{period: "annee", class: cg.id, seuil: "5"})` then `assert_patch(view, ~p"/school/absence-totals?#{[period: "annee", class: cg.id, seuil: "5"]}")`.
  - `"a foreign class id falls back to all classes"` — `?class=#{Ecto.UUID.generate()}` renders, class select on « Toutes les classes ».
  - `"a year without séquences shows an empty state"` — fresh school without calendar → `#absence-no-sequences`.
  - `"a teacher is refused"` — `as_member(... [:teacher])` → redirected with « Access denied. » (pattern of `absence_hours_live_test.exs`).
  - `"the print link carries the pickers"` — `#absence-print[href^='/school/absence-totals/print?']` with `class=` and `period=`.
- [ ] **Step 2: Run** `MIX_TEST_PARTITION=7 mix test test/teacher_assistant_web/live/school/absence_totals_live_test.exs` — Expected: FAIL (no route).
- [ ] **Step 3: Implement** `AbsenceTotalsParams` then `AbsenceTotalsLive`: mount checks `Discipline.can_manage_conduct?/1` and a current year (else flash « Access denied. » and navigate to `/school`); `handle_params` calls `resolve/2`; one `phx-change` form `#absence-totals-form` (period select, class select, threshold input `#absence-threshold`, `inputmode="decimal"`) that `push_patch`es `query/2`. Header line under the pickers: « Seuil : 60 h — 20 h × 3 séquences » (just « Seuil : 20 h » for a séquence). One class: a table (phone: `list_row`s) with Nom · NJ · J · Retards, `#absence-source` naming « appel » or « saisi », flagged rows marked (`text-warning` + icon), « non saisi » for unrecorded typed rows. All classes: a section per class `#absence-class-#{cg.id}` with its label, then its rows. Row ids `absence-row-#{enrollment.id}`. « Imprimer » link `#absence-print` to `~p"/school/absence-totals/print?#{query}"`, `target="_blank"`. Start with `<Layouts.app ...>`; follow `AbsenceHoursLive` for the select styling.
- [ ] **Step 4: Wire** route, module list, menu item and the spaces test change.
- [ ] **Step 5: Run** the new test file and `test/teacher_assistant_web/spaces_test.exs` plus `test/teacher_assistant/modules_test.exs` and `test/teacher_assistant_web/router_modules_test.exs` — Expected: PASS.
- [ ] **Step 6: Commit** `feat(attendance): « Bilan des absences » page`.

### Task 3: Print and the Discipline tab link

**Files:**
- Create: `lib/teacher_assistant_web/controllers/absence_totals_print_controller.ex`, `absence_totals_print_html.ex`, `absence_totals_print_html/show.html.heex`
- Modify: `lib/teacher_assistant_web/router.ex` (`get "/school/absence-totals/print", AbsenceTotalsPrintController, :show` among the print routes)
- Modify: `lib/teacher_assistant/modules.ex` (`{W.AbsenceTotalsPrintController, :show} => :discipline`)
- Modify: `lib/teacher_assistant_web/live/school/discipline_live.ex` (link `#absence-totals-link` « Bilan des absences » beside `#absence-hours-link`, to `~p"/school/absence-totals?#{[class: cg.id, period: period_param]}"`)
- Test: `test/teacher_assistant_web/controllers/absence_totals_print_controller_test.exs`, one case in `test/teacher_assistant_web/live/school/discipline_live_test.exs`

**Interfaces:**
- Consumes: `AbsenceTotalsParams.resolve/2` (Task 2) — the controller renders exactly the resolved `view`.

- [ ] **Step 1: Write the failing tests:**
  - print `"prints one class with its figures and the threshold"` — body has « BILAN DES ABSENCES » (or the template's title), the class label, « Awa », « Seuil : 20 h ».
  - print `"all classes prints only students over the threshold"` — `seuil=0,5`: « Awa » in, « Bob » out.
  - print `"a teacher is redirected"` → `redirected_to(conn) == ~p"/school"`.
  - modules: `Modules.module_for_controller(AbsenceTotalsPrintController, :show) == :discipline`.
  - discipline tab: `#absence-totals-link[href*='class=#{cg.id}']`.
- [ ] **Step 2: Run** both test files — Expected: FAIL.
- [ ] **Step 3: Implement** the controller on the `EntryReportPrintController` pattern (`plug SchoolAccess`, conduct check, `put_layout(false)`, `put_root_layout(false)`, official header via `OfficialHeaderComponents.official_header/1`, A4 portrait, printed-on date). Template: title, period, class choice, threshold line, then the same tables as the page (no pickers, no links).
- [ ] **Step 4: Run** the tests — Expected: PASS.
- [ ] **Step 5: Extract gettext** (`MIX_ENV=test mix gettext.extract --merge`), fill every new English entry, remove fuzzy flags; run `MIX_TEST_PARTITION=7 mix precommit` — Expected: all green.
- [ ] **Step 6: Commit** `feat(attendance): Bilan des absences print and link from Discipline`.

### Task 4: Browser check

- [ ] Start the dev server from this worktree (`PORT=4010 ELIXIR_ERL_OPTIONS="-live_debugger 'disabled?' true" mix phx.server`, via the preview tool), sign in as the demo surveillant/proviseur (credentials in the project seeds), open « Bilan des absences »: séquence / trimester / year, one class / all classes, a typed threshold, the print; desktop and 375 px. Never reset the dev DB.
- [ ] Fix what the check finds (test first for behaviour bugs), precommit, commit `fix(attendance): Bilan des absences browser check`.
