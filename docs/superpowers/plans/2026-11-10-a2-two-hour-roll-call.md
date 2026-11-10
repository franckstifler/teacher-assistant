# A2 — Two-hour roll call with bulk write — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teacher who has the same class two hours in a row takes the roll once (writing both periods), or opens the second hour prefilled from the first, and each save is one bulk upsert per period instead of one create per student.

**Architecture:** `RollCall.open/4` learns the class's adjacent timetable slots (same teaching context or combined course, back to back) and exposes `prefilled_from` and `following`; `RollCall.record/2` writes the chosen periods through `Attendance.record_period/7` and `record_combined_period/5`, which now take a list of periods and write each with `Ash.bulk_create` under one transaction. `YearOpen` becomes an `Ash.Resource.Change` with a batch callback so the year is resolved once per batch; the teacher-ownership rule on `:record` becomes a pre-check so no per-row filter query remains.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ash 3.37 (bulk actions, changes with `batch_change/3`), AshPostgres, Gettext (FR source, EN translations).

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A2.

## Global Constraints

- One `AttendanceEntry` per student per period, identity `unique_mark` `[:enrollment_id, :date, :period_id]` — unchanged.
- All-or-nothing: any refused row rolls every period's writes back; error mapping stays `:forbidden | :unverified | :failed` in `RollCall`.
- A later hour already taken is never overwritten from an earlier one.
- Lates do not carry over on prefill (the student is in the room); absences and `:sent_home` do.
- The checkbox exists on Ma journée only; the prefill applies on Ma journée and `AttendanceLive`.
- Every new string through Gettext, FR + EN, no fuzzy entry left (`mix gettext.extract --merge`, then fill EN).
- Tests run with `MIX_TEST_PARTITION=a2`; commit explicit paths only; branch `feat/audit-a2` in `.claude/worktrees/audit-a2`.
- `mix precommit` green before merge (warnings fail it since A1).

## Review Focus

1. A paper-roll class (`class_group.paper_roll_call`): the app's `:record` upsert must still overwrite a `:paper` row with `source: :app` after the bulk change — Task 1 asserts `source == :app` after a bulk upsert over a paper row.
2. A combined course whose member classes have different adjacent slots (class A continues at the next period, class B does not): `following` is only the periods where **every** member class continues — Task 3 tests it.
3. The following hour's slot belongs to another teacher's context (the same class, a different subject): no checkbox — Task 3 tests a different context at the next period.
4. The period after a break (`Cours 3` ends 10:00, `Cours 4` starts 10:15): not adjacent — Task 3 tests it through `end_time == start_time`.
5. A student `:sent_home` at hour 1 with the box checked: hour 2 gets `:sent_home` too and `validate_sent_home` must accept it for both periods — Task 1 tests a two-period write with a `:sent_home` mark.

---

### Task 1: Bulk write in `Attendance.record_period/7`

**Files:**
- Modify: `lib/teacher_assistant/attendance.ex:348-420` (`record_period/7`)
- Modify: `lib/teacher_assistant/academics/attendance_entry.ex:107-131` (`:record`, `:record_paper` policies)
- Test: `test/teacher_assistant/academics/attendance_test.exs`

**Interfaces:**
- Consumes: `AttendanceEntry` `:record` and `:record_paper` upsert actions as they are.
- Produces: `Attendance.record_period(scope, class_group, period_or_periods, teaching_context, date, marks, opts \\ [])` where the third argument is a `%Period{}` **or a list of `%Period{}`**; returns `{:ok, count}` with `count` = rows written over all periods, `{:error, %Ash.Error.Forbidden{}}`, `{:error, :record_failed}` or the existing validation errors.

- [ ] **Step 1: Write the failing tests**

```elixir
describe "record_period/7 with several periods" do
  test "writes one entry per student per period in one go", ctx do
    assert {:ok, 4} =
             Attendance.record_period(ctx.scope, ctx.cg, [ctx.p1, ctx.p2], ctx.tc, ctx.date, [
               {ctx.e1.id, :absent},
               {ctx.e2.id, :late, 5}
             ])

    for p <- [ctx.p1, ctx.p2] do
      %{students: students} = Attendance.period_roll(ctx.scope, ctx.cg, p, ctx.date)
      assert %{status: :absent} = Enum.find(students, &(&1.enrollment_id == ctx.e1.id))
      assert %{status: :late, late_minutes: 5} = Enum.find(students, &(&1.enrollment_id == ctx.e2.id))
    end
  end

  test "a sent-home mark is accepted for both periods", ctx  # uses FeeControl to send e1 home on date, then records [{e1, :sent_home}] on [p1, p2]

  test "one refused row rolls every period back", ctx  # a teacher scope on a context they do not own: {:error, %Ash.Error.Forbidden{}} and period_roll of p1 and p2 both show nil statuses

  test "an app roll overwrites a paper row", ctx  # record_period(..., p1, ..., [{e1, :absent}], source: :paper) then record_period(..., [p1], ..., [{e1, :present}]); the entry's source is :app

  test "a save of 40 students over two periods runs under 12 queries", ctx do
    # attach a :telemetry handler on [:teacher_assistant, :repo, :query] counting events during the call
    assert count <= 12
  end
end
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant/academics/attendance_test.exs`
Expected: FAIL — `record_period/7` does not accept a list (FunctionClauseError) and the query budget is exceeded.

- [ ] **Step 3: Implement the bulk path**

In `attendance.ex`, `record_period/7`: normalise `period_or_periods` to a list; validate marks and sent-home once per period (`validate_sent_home(scope, marks, period.id, date)` per period); then

```elixir
TeacherAssistant.Repo.transaction(fn ->
  Enum.reduce(periods, 0, fn %Period{id: period_id}, n ->
    entries = Enum.map(marks, &entry_attrs(&1, period_id, date, teaching_context_id, source_attrs, scope))
    case Ash.bulk_create(entries, AttendanceEntry, action,
           scope: scope, upsert?: true, upsert_identity: :unique_mark,
           return_errors?: true, stop_on_error?: true, return_records?: false,
           transaction: false, batch_size: 500) do
      %Ash.BulkResult{status: :success} -> n + length(entries)
      %Ash.BulkResult{errors: [error | _]} -> TeacherAssistant.Repo.rollback(error)
    end
  end)
end)
```

`transaction: false` because the outer `Repo.transaction` already wraps every period. Keep the error mapping that follows (`Ash.Error.to_error_class`). Do not pass `upsert_fields`: the default (every attribute set on the changeset) is what the per-row create upserted. `ClearLateMinutes` is a change, so it still runs per changeset in the bulk.

- [ ] **Step 4: Move the teacher-ownership rule to a pre-check**

In `attendance_entry.ex` the `create` policy `authorize_if expr(teaching_context.teacher_user_id == ^actor(:id))` is a filter check: in a bulk create it costs one query per row. Replace it on the `:record` / `:record_paper` path with a simple check `TeacherAssistant.Academics.AttendanceEntry.Checks.OwnsContext` (new file `lib/teacher_assistant/academics/attendance_entry/checks/owns_context.ex`, `use Ash.Policy.SimpleCheck`) that authorizes when the changeset context carries `%{roll_call: %{owner?: true}}`. `record_period/7` computes `owner?` **once** (`teaching_context && teaching_context.teacher_user_id == scope.current_user.id`) and passes `context: %{roll_call: %{owner?: owner?}}` to `Ash.bulk_create`. The `:conduct` role path is unchanged (`authorize_if {Checks.SchoolRole, any_of: :conduct}` stays first). The existing `test/teacher_assistant/authorization/attendance_test.exs` must still refuse a teacher who does not own the context, and a create without the context key (any other caller) must still be refused for a plain teacher.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant/academics/attendance_test.exs test/teacher_assistant/authorization/attendance_test.exs test/teacher_assistant/academics/paper_roll_call_test.exs test/teacher_assistant/academics/attendance_late_minutes_test.exs`
Expected: PASS, including the query budget.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/attendance.ex lib/teacher_assistant/academics/attendance_entry.ex lib/teacher_assistant/academics/attendance_entry/checks/owns_context.ex test/teacher_assistant/academics/attendance_test.exs
git commit -m "perf(attendance): record_period writes each period as one bulk upsert"
```

---

### Task 2: `YearOpen` as a batch-aware change

**Files:**
- Modify: `lib/teacher_assistant/academics/year_open.ex`
- Modify: the 29 resources listing `validate {TeacherAssistant.Academics.YearOpen, path: …}, on: […]` → `change {TeacherAssistant.Academics.YearOpen, path: …}, on: […]` (grep `YearOpen` under `lib/teacher_assistant/academics`).
- Test: `test/teacher_assistant/academics/year_open_test.exs` (existing tests on closed years must stay green; find them with `grep -rl "clôturée" test`).

**Interfaces:**
- Produces: `TeacherAssistant.Academics.YearOpen` as an `Ash.Resource.Change` with `init/1` (same `path:` option), `change/3` (single changeset: the current `validate/3` logic, adding the error with `Ash.Changeset.add_error/2`), `batch_change/3` (resolves the year ids of the whole batch with **one** query per distinct parent id set, then adds the error to the changesets whose year is closed), `atomic/3` unchanged in meaning.

- [ ] **Step 1: Write the failing test**

```elixir
test "a bulk create over a closed year refuses every row with one lookup", ctx do
  # close the year, then Ash.bulk_create 3 AttendanceEntry :record changesets
  # assert every error message == YearOpen.message(year.name)
  # assert the number of SELECTs on academic_years during the call == 1 (telemetry counter, filter on the query string)
end
```

- [ ] **Step 2: Run it**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant/academics/year_open_test.exs`
Expected: FAIL on the query count (3 lookups today).

- [ ] **Step 3: Convert the module**

`use Ash.Resource.Change`; keep `year_ids/2`, `check/2`, `closed_error/2`; `batch_change(changesets, opts, context)`: collect `{changeset, parent_ids}` for all, read the parents in one `Ash.Query.filter(id in ^ids)` per `rel.destination`, resolve each changeset's year ids from that map, then `closed_error` once per distinct year id. Return the changesets with errors added. `change/3` delegates to `batch_change([changeset], …)` and takes the single result. Keep the moduledoc's warning about no compile-time `AcademicYear` struct pattern.

- [ ] **Step 4: Swap `validate` for `change` in every resource**

`sed`-style edit over the files found by grep; `on:` is accepted by `change` as well. Compile with `mix compile --warnings-as-errors`.

- [ ] **Step 5: Run the closed-year tests and the whole academics folder**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant/academics`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/academics test/teacher_assistant/academics/year_open_test.exs
git commit -m "perf(year-open): a batch-aware change resolves the year once per batch"
```

---

### Task 3: Adjacent hours in `RollCall.open/4` (prefill and following)

**Files:**
- Modify: `lib/teacher_assistant/attendance.ex` — add `adjacent_slots/4`
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex:25-48,151-193`
- Test: `test/teacher_assistant/academics/attendance_test.exs` (unit of `adjacent_slots/4`), `test/teacher_assistant_web/live/school/attendance_live_test.exs` (prefill on the surveillant's page)

**Interfaces:**
- Produces: `Attendance.adjacent_slots(scope, class_group, date, period) :: %{previous: %Period{} | nil, following: [%Period{}]}` — among the class's slots on that weekday (`TimetableSlot` `:for_class` filtered by `day`), the lesson periods back to back with `period` (`end_time == next.start_time`, chained) whose slot has the **same `teaching_context_id`**, or the same `combined_course_id` when the context has one. `previous` is the one just before, `following` the chain after, in order.
- Produces on the roll map: `prefilled_from: %Period{} | nil` (the previous adjacent period whose roll is taken, used only when this roll is not taken), `following: [%Period{}]` (adjacent periods after this one whose roll is **not** taken; for a combined course only the periods adjacent for every member class), `record_following: boolean` (default `following != []`).

- [ ] **Step 1: Write the failing unit tests for `adjacent_slots/4`**

```elixir
describe "adjacent_slots/4" do
  # fixtures: default periods; slots on monday for cg: Cours 1 + Cours 2 (tc), Cours 3 (other_tc), Cours 4 (tc) — Cours 4 follows a break
  test "the same context back to back is previous/following", ctx do
    assert %{previous: nil, following: [p2]} = Attendance.adjacent_slots(ctx.scope, ctx.cg, @monday, ctx.p1)
    assert %{previous: p1, following: []} = Attendance.adjacent_slots(ctx.scope, ctx.cg, @monday, ctx.p2)
  end
  test "another teacher's context is not adjacent"  # from p2: following == [] because Cours 3 is other_tc
  test "a break breaks the chain"  # from Cours 4 (tc): previous == nil
  test "a combined course chains on its course, not its context"  # two member classes, course placed at Cours 1 and Cours 2 → following from Cours 1 == [Cours 2]
end
```

- [ ] **Step 2: Write the failing LiveView test for prefill on `AttendanceLive`**

```elixir
test "the second hour opens prefilled from the first: absences, not lates", ctx do
  # slots monday p1 and p2 for tc; record p1: e1 absent, e2 late 5
  {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/attendance/#{p2.id}?date=2025-09-08")
  assert has_element?(view, "#roll-prefilled", "1re heure")
  assert has_element?(view, "#roll-counts", "1 absent")
  assert has_element?(view, "#roll-counts", "0 retard")
  assert has_element?(view, "#record-roll", "Valider l'appel")   # taken? still false
  refute has_element?(view, "#record-following")                 # no checkbox on this page
end
```

- [ ] **Step 3: Run them**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant/academics/attendance_test.exs test/teacher_assistant_web/live/school/attendance_live_test.exs`
Expected: FAIL — `adjacent_slots/4` undefined; `#roll-prefilled` missing.

- [ ] **Step 4: Implement `adjacent_slots/4` and the roll fields**

`adjacent_slots/4` in `attendance.ex` next to `slot_for/4`: read the class's slots for the weekday with `teaching_context` loaded, sort the school's lesson periods by `position`, walk backwards and forwards from `period` while `end_time == start_time` and the slot at that period matches (`same_unit?/2`: equal `teaching_context_id`, or both contexts' `combined_course_id` equal and non-nil).

In `roll_call.ex` `open/4`: after `reload/2`, call `adjacent_slots` (for a combined course, intersect the `following` of every member class and take `previous` only if every member class has the same previous period), then `put_adjacent/2`:
- `following`: those periods whose roll for this class (every member class) is not taken — `Attendance.period_roll/4` per period, `Enum.any?(students, & &1.status)`.
- `prefilled_from`: when `roll.taken?` is false and `previous` is taken: the previous period, and `roll.marks` becomes the previous roll's statuses with `:late` → `:present`, `minutes` emptied; `sent_home` recomputed from the marks. When `roll.taken?` is true: nil.
- `record_following: roll.following != []`.

- [ ] **Step 5: Run the tests**

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/attendance.ex lib/teacher_assistant_web/live/school/roll_call.ex test/teacher_assistant/academics/attendance_test.exs test/teacher_assistant_web/live/school/attendance_live_test.exs
git commit -m "feat(roll-call): the second hour opens prefilled from the first"
```

---

### Task 4: Record the following hours from Ma journée

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/roll_call.ex:98-120` (`record/2`), `:286-404` (`roll_panel/1` footer), add `toggle_following/1`
- Modify: `lib/teacher_assistant_web/live/school/my_day_live.ex:94-117` (events), `:158-185` (panel call)
- Modify: `lib/teacher_assistant/attendance.ex:252-300` (`record_combined_period/5` takes a period list)
- Modify: `priv/gettext/en/LC_MESSAGES/default.po` (+ `default.pot`, `fr` via `mix gettext.extract --merge`)
- Test: `test/teacher_assistant_web/live/school/school_life_live_test.exs`, `test/teacher_assistant/academics/attendance_combined_test.exs`

**Interfaces:**
- Consumes: `roll.following`, `roll.record_following` from Task 3; `Attendance.record_period/7` list form from Task 1.
- Produces: `RollCall.record(scope, roll)` writes `[roll.period | roll.following]` when `roll.record_following` is true, else `[roll.period]`; `RollCall.toggle_following(roll)` flips `record_following`; `roll_panel` attr `following?: boolean` (default `false`) shows the checkbox `#record-following` in the footer, label `ngettext("Aussi pour la 2e heure", "Aussi pour les %{count} heures suivantes", length(following))`, with `phx-click="toggle_following"`; after a save the panel's « Appel enregistré. » line reads « Appel enregistré pour 2 heures. » when more than one period was written (`roll.saved_periods`, integer, set by `record/2`).
- `Attendance.record_combined_period(scope, course, period_or_periods, date, marks)` — list form, one transaction, bulk per group per period (the `:record_combined_period` generic action gains a `period_ids` argument list and `create_group_entries` uses `Ash.bulk_create` like Task 1).

- [ ] **Step 1: Write the failing LiveView tests**

```elixir
test "Ma journée: the first of two hours offers to record the second too", ctx do
  # ctx has slots p1, p2 for tc on monday and p1 NOT recorded (adapt the setup: record nothing)
  {:ok, view, _} = live(conn, ~p"/school/today?#{[slot: "#{cg.id}-#{p1.id}"]}")
  assert has_element?(view, "#record-following[aria-checked=true]", "2e heure")
  view |> element("#att-#{e.id}-absent") |> render_click()
  view |> element("#record-roll") |> render_click()
  assert has_element?(view, "#roll-footer", "pour 2 heures")
  for p <- [p1, p2], do: assert %{status: :absent} = roll_status(scope, cg, p, e)  # helper over period_roll
  assert view |> element("#slot-#{cg.id}-#{p2.id}") |> render() =~ "Appel fait"
end

test "unchecked, only the first hour is written"      # click #record-following first → p2 statuses all nil
test "a second hour already taken is not offered"     # record p2 first → refute #record-following on p1
test "a combined course records both hours for every member class"  # attendance_combined-style setup, two periods
```

- [ ] **Step 2: Run them**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant/academics/attendance_combined_test.exs`
Expected: FAIL — no `#record-following`.

- [ ] **Step 3: Implement**

`record/2`: `periods = if roll.record_following, do: [roll.period | roll.following], else: [roll.period]`; `write/3` passes the list; on `{:ok, _}` reload and set `saved_periods: length(periods)`. `toggle_following/1`. In `roll_panel` footer, before the counts: a `<button role="checkbox" aria-checked=…>` styled as the existing pill toggles (`toggle_class/2`) when `@following?`. `MyDayLive` passes `following?={@roll.following != []}` and handles `"toggle_following"`; `AttendanceLive` does not pass it (default false). `record_combined_period/5` list form as in the interface. Extract and fill Gettext.

- [ ] **Step 4: Run the tests and the whole attendance-related set**

Run: `MIX_TEST_PARTITION=a2 mix test test/teacher_assistant_web/live/school test/teacher_assistant/academics test/teacher_assistant_web/gettext_test.exs`
Expected: PASS. Note: the existing "Ma journée records the selected slot's roll call in place" test now opens p2 prefilled from p1 (Awa absent); its assertions (`0 retard` → `1 retard`) still hold.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/roll_call.ex lib/teacher_assistant_web/live/school/my_day_live.ex lib/teacher_assistant/attendance.ex lib/teacher_assistant/academics/attendance_entry.ex priv/gettext test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant/academics/attendance_combined_test.exs
git commit -m "feat(roll-call): record the following hours from Ma journée in one save"
```

---

### Task 5: Browser check and merge

- [ ] **Step 1: Browser check on a phone width** with the demo school (memory `reference-demo-school-seed`): open Ma journée as a teacher with two consecutive hours (seed one if none: place two slots), see the checkbox checked, validate, see both lessons « Appel fait »; open the surveillant's attendance page for the second hour of another class, see « Pré-rempli depuis la 1re heure ». Screenshot both.
- [ ] **Step 2: `MIX_TEST_PARTITION=a2 mix precommit`** — expected `exit 0`.
- [ ] **Step 3: Fast-forward merge** `feat/audit-a2` into `main` from the main checkout; update memory `project-audit-2026-11-10` (A2 merged, commit, test count).
