# A3 — Head's dashboard and bulletin status without row loads — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The head's home page and every bulletin status check stop loading mark rows, absence rows with their guardians, and bulletin snapshots when all they need is a count, a date or a class id.

**Architecture:** `EntryProgress` reads per-assessment aggregates (`marks_count`, `last_mark_at`) instead of mark rows; `SchoolLife.absences_to_justify/2` and a new `absence_counts/2` count from narrow selects with no relationship loads; `BulletinPublication` gets a status read that leaves the `snapshot` term out, used by `current_publication/3`, `published_class_ids/2` and `history/3`, with the snapshot loaded only where it is rendered or printed. Behaviour and figures are unchanged; the tests compare the new figures with the old ones on the same fixtures and bound the queries.

**Tech Stack:** Elixir, Ash 3.37 (resource aggregates with filters, `Ash.Query.select`, `Ash.load` of an unselected attribute), AshPostgres, Phoenix LiveView 1.2, telemetry query counting as in `test/teacher_assistant/academics/entry_progress_test.exs:185`.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A3.

## Global Constraints

- Same numbers as today: entry percentages, `last_entry_at`, « Absences à justifier » count and flagged students, published class sets, council locks. Each task's first test pins the old figure on a fixture before the swap.
- A student not taking a course (exempted, or not enrolled in the class) still does not count (`entry_progress_test.exs:98,108`).
- No new resources, no migration (aggregates and selects only). `mix ash.codegen --dev` must report nothing to generate.
- Tests run with `MIX_TEST_PARTITION=a3`; branch `feat/audit-a3` in `.claude/worktrees/audit-a3`; commit explicit paths only; `mix precommit` green before merge.

## Review Focus

1. A mark whose student left the class (enrollment destroyed, mark kept): it must not count as entered — Task 1 tests a mark of a student enrolled elsewhere.
2. A withdrawn publication followed by a new one for the same period: `current_publication` must return the published one, `history` both — Task 3 tests withdraw-then-republish.
3. `Ash.load!(pub, :snapshot)` on a record read without it: must return the full term, not `%Ash.NotLoaded{}` — Task 3 asserts the loaded snapshot has `:results`.
4. The absences count when the school has no current séquence (holidays, before the year starts): zero, no crash — Task 2 tests `current_sequence_range` nil.
5. A long late counted as an absence (`late_as_absence_minutes`): the count must include it as before — Task 2 tests a late over the threshold.

---

### Task 1: `EntryProgress` from aggregates, not mark rows

**Files:**
- Modify: `lib/teacher_assistant/academics/assessment.ex` (aggregates block, after `relationships`)
- Modify: `lib/teacher_assistant/academics/student.ex:141` (add `has_many :subject_exemptions`)
- Modify: `lib/teacher_assistant/academics/entry_progress.ex:34-110,148-190,245-283,299-318`
- Test: `test/teacher_assistant/academics/entry_progress_test.exs`

**Interfaces:**
- Produces on `Assessment`: aggregates `marks_count` (count of `marks` whose student takes the course) and `last_mark_at` (max `marks.updated_at` under the same filter). "Takes the course" = `exists(student.enrollments, class_group_id == parent(teaching_context.class_group_id))` and `not exists(student.subject_exemptions, teaching_context_id == parent(teaching_context_id))`.
- `EntryProgress.grid/3`, `context_cells/4`, `class_rates/3`, `class_rate/4`: same return shapes as today; `cell/4` becomes `cell(tc, taking, assessments)` with `entered = Enum.sum_by(assessments, & &1.marks_count)` and `last_entry_at = max of last_mark_at`; `load_marks/2` deleted; `sorted_assessments/2` and `load_sequences_assessments/3` load the two aggregates.

- [ ] **Step 1: Write the failing tests**

```elixir
test "a mark of a student who left the class is not counted", ctx do
  # second class cg2 with student s2; assessment a on ctx.tc (cg); mark(ctx, a, s2) directly
  # (Marks.upsert bypasses the roster) → grid cell for cg/Maths: entered == 0, last_entry_at == nil
end

test "the grid reads no mark rows", ctx do
  # 3 marks on an assessment; count queries whose SQL contains ~s(FROM "marks") during grid(ctx)
  assert mark_row_queries == 0
end
```

Both use the file's existing `count_queries/1` (extend it to take a table substring, as `year_open_test.exs` does).

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=a3 mix test test/teacher_assistant/academics/entry_progress_test.exs`
Expected: FAIL — "the grid reads no mark rows" counts 1; the left-class test fails if the stray mark is counted (it is: the student is not in `taking`, so today it passes — keep it as a regression guard and note it in the ledger).

- [ ] **Step 3: Add the relationship and the aggregates**

```elixir
# student.ex
has_many :subject_exemptions, TeacherAssistant.Academics.SubjectExemption

# assessment.ex
aggregates do
  count :marks_count, :marks do
    filter expr(
      exists(student.enrollments, class_group_id == parent(teaching_context.class_group_id)) and
        not exists(student.subject_exemptions, teaching_context_id == parent(teaching_context_id))
    )
  end

  max :last_mark_at, :marks, :updated_at do
    filter expr(... same ...)
  end
end
```

If Ash refuses `parent/1` through two levels inside an aggregate filter, fall back to: plain `marks_count` / `last_mark_at` aggregates, plus one narrow query of the stray marks (`Mark |> filter(assessment_id in ^ids and (student_id in ^exempt_ids or not exists(student.enrollments, class_group_id == parent(assessment.teaching_context.class_group_id))))`, select `[:assessment_id, :student_id, :updated_at]`) subtracted in `cell/3`. Record the choice in the ledger.

- [ ] **Step 4: Rewrite `cell/3` and the loaders; delete `load_marks/2`**

`sorted_assessments/2` and `load_sequences_assessments/3` add `Ash.Query.load([:marks_count, :last_mark_at])` and keep their selects. `cell(tc, taking, assessments)` keeps `expected = MapSet.size(taking) * length(assessments)` and the « Rien saisi » rule.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=a3 mix test test/teacher_assistant/academics/entry_progress_test.exs test/teacher_assistant_web/live/school/sequence_tracking_live_test.exs test/teacher_assistant_web/live/school/dashboard_live_test.exs test/teacher_assistant/pilotage_test.exs`
Expected: PASS, "the number of queries does not grow with the number of classes" still green.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/assessment.ex lib/teacher_assistant/academics/student.ex lib/teacher_assistant/academics/entry_progress.ex test/teacher_assistant/academics/entry_progress_test.exs
git commit -m "perf(entry-progress): count marks with aggregates instead of loading them"
```

---

### Task 2: Absence counts without rows or guardians

**Files:**
- Modify: `lib/teacher_assistant/academics/school_life.ex:357-409`
- Modify: `lib/teacher_assistant/attendance.ex` (delegate `absence_counts/2`)
- Modify: `lib/teacher_assistant_web/live/school/day_live.ex:33-54`
- Test: `test/teacher_assistant/academics/school_life_test.exs`, `test/teacher_assistant_web/live/school/school_life_live_test.exs` (Surveillant day)

**Interfaces:**
- `SchoolLife.absences_to_justify(scope, today)` — same map `%{count, flagged_students, alert_hours}`, computed from `AttendanceEntry` with `select([:enrollment_id, :date, :justified])` under `absences_between/4`, grouped by `{enrollment_id, date}`; a day is open when any of its entries is unjustified. `flagged_students` from `unjustified_hours/3`.
- `unjustified_hours(scope, today, rules)` — no `load(:period)`: select `[:enrollment_id, :status, :late_minutes, :period_id]` and put the period from `Attendance.list_periods/1` (one query) before `Conduct.totals/2`.
- New `SchoolLife.absence_counts(scope, today) :: %{today_absent_students: integer, to_justify: integer}` delegated from `Attendance`; `DayLive.load/1` uses it instead of `absence_days/4`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "absences_to_justify equals the absence_days-derived figures and reads no students or guardians", ctx do
  # fixture: 2 students, one absent 2 days (one day justified), one long late over the threshold
  rows = Attendance.absence_days(ctx.scope, first, last, today)
  expected = %{count: Enum.count(rows, &(not &1.justified?)), flagged_students: ...}
  {result, student_queries} = count_queries(~s(FROM "students"), fn -> Attendance.absences_to_justify(ctx.scope, today) end)
  assert Map.take(result, [:count, :flagged_students]) == expected
  assert student_queries == 0
end

test "absence_counts: today's absent students and the open days", ctx  # equals the day page's old derivation
test "no current séquence → zero counts", ctx  # scope whose year has no séquence containing today
```

- [ ] **Step 2: Run to verify they fail** — `absence_counts/2` undefined; student queries > 0.

- [ ] **Step 3: Implement** as in Interfaces. `absence_counts/2`: one narrow read of the séquence range (same select), `today_absent_students = rows |> Enum.filter(&(&1.date == today)) |> Enum.uniq_by(& &1.enrollment_id) |> length()`, `to_justify` as in `absences_to_justify`. Share the grouped read between the two through a private `open_days/3` returning `[%{enrollment_id, date, justified?}]`.

- [ ] **Step 4: `DayLive.load/1`** uses `Attendance.absence_counts(scope, today)`; remove `sequence_rows`.

- [ ] **Step 5: Run** `MIX_TEST_PARTITION=a3 mix test test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant_web/live/school/dashboard_live_test.exs test/teacher_assistant_web/spaces_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics/school_life.ex lib/teacher_assistant/attendance.ex lib/teacher_assistant_web/live/school/day_live.ex test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs
git commit -m "perf(absences): count open absence days without loading rows or guardians"
```

---

### Task 3: Bulletin status without the snapshot

**Files:**
- Modify: `lib/teacher_assistant/academics/bulletin_publication.ex:46-50` (`:for_class` select) and add `read :current`
- Modify: `lib/teacher_assistant/report_cards.ex:150-172,784-791` and the snapshot callers at `:153,:329,:921`
- Modify: `lib/teacher_assistant/councils.ex:75`, `lib/teacher_assistant_web/controllers/council_print_controller.ex:86`
- Test: `test/teacher_assistant/report_cards_test.exs`

**Interfaces:**
- `BulletinPublication` `read :current` — arguments `class_group_id`, `period_key`; filter `status == :published`; `prepare build(select: @status_fields)` where `@status_fields = [:id, :class_group_id, :academic_year_id, :term_id, :period_kind, :period_key, :status, :snapshot_version, :published_at, :published_by_user_id, :withdrawn_at, :withdrawn_by_user_id, :withdrawal_reason, :workspace_id, :inserted_at, :updated_at]`. `:for_class` gets the same select (history lists dates, people and reasons, never the snapshot).
- `ReportCards.current_publication(scope, cg, period)` — unchanged signature, reads `:current`, returns the record **without** `snapshot`.
- `ReportCards.current_publication(scope, cg, period, snapshot: true)` — the same record with `snapshot` loaded (`Ash.load!(pub, :snapshot, scope: scope)`). Used by `class_view/3`, `view_for/3`'s `:published` branch, `term_results/3`, `Councils.last_term_carries_year?/3`, `CouncilPrintController.figures/4`.
- `ReportCards.published_class_ids(scope, period)` — `Ash.Query.select([:class_group_id])`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "published_class_ids and current_publication never read the snapshot column", ctx do
  # publish cg for the term; count queries whose SQL contains "snapshot" during both calls
  assert snapshot_queries == 0
  assert %Ash.NotLoaded{} = ReportCards.current_publication(scope, cg, period).snapshot
end

test "current_publication with snapshot: true returns the frozen view", ctx do
  assert %{results: %{}} = ReportCards.current_publication(scope, cg, period, snapshot: true).snapshot
end

test "withdraw then republish: current is the new one, history has both", ctx
test "history carries no snapshot", ctx  # every entry's snapshot is %Ash.NotLoaded{}
```

- [ ] **Step 2: Run to verify they fail** — snapshot queries ≥ 1, `snapshot` loaded.

- [ ] **Step 3: Implement** as in Interfaces; `class_view/3` and the `:published` branch of `view_for/3` call the `snapshot: true` form once and pass the record down (no second read in `bulletins_live` `load/2`: it already receives `pub` from `view_for`).

- [ ] **Step 4: Run** `MIX_TEST_PARTITION=a3 mix test test/teacher_assistant/report_cards_test.exs test/teacher_assistant/report_cards_access_test.exs test/teacher_assistant/pilotage_test.exs test/teacher_assistant_web/live/school/bulletins_live_test.exs test/teacher_assistant_web/live/school/councils_live_test.exs test/teacher_assistant_web/controllers/council_print_controller_test.exs test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs test/teacher_assistant_web/live/school/absence_hours_live_test.exs` — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/bulletin_publication.ex lib/teacher_assistant/report_cards.ex lib/teacher_assistant/councils.ex lib/teacher_assistant_web/controllers/council_print_controller.ex test/teacher_assistant/report_cards_test.exs
git commit -m "perf(bulletins): status checks read publications without their snapshot"
```

---

### Task 4: Dashboard query budget

**Files:**
- Test: `test/teacher_assistant_web/live/school/dashboard_live_test.exs`

- [ ] **Step 1: Measure.** On the file's existing school fixture plus 3 classes × 2 students × 1 assessment with marks and 2 absences, count the queries of `live(conn, ~p"/school")` for the head (telemetry handler attached in the test process; LiveView mounts in the test process under `live/2`). Write the number down in the ledger.

- [ ] **Step 2: Write the test** `"the head's dashboard mounts under N queries and reads no mark, student or guardian rows"` with `N` = measured + 5, and zero queries on `"marks"`, `"students"`, `"guardians"` tables. Run it: PASS (it documents the budget after Tasks 1–3; if it fails, a task above regressed).

- [ ] **Step 3: Commit**

```bash
git add test/teacher_assistant_web/live/school/dashboard_live_test.exs
git commit -m "test(dashboard): bound the head's dashboard queries"
```

---

### Task 5: Verify and merge

- [ ] `mix ash.codegen --dev --check` (or `mix ash.codegen --dev` showing nothing to generate): no migration from the aggregates.
- [ ] Browser check with the demo school: `/school` as proviseur@demo.test shows the same KPIs as before (note the figures before on main, compare after), `/school/day` as sg@, `/school/bulletins` for a published class still renders the snapshot. Dev server from the worktree on port 4010 as in A2.
- [ ] `MIX_TEST_PARTITION=a3 mix precommit` → exit 0; fast-forward merge into main; update memory `project-audit-2026-11-10`.
