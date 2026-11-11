# A8 — Smaller performance items — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the remaining avoidable work on the hot pages: the T3 bulletin view computed in one pass, the marks grid's pending list computed in memory, photos served from the browser cache, the six heaviest LiveViews loading their data on the connected pass only, websocket frames compressed, and the five missing indexes.

**Architecture:** Five independent changes, each its own commit, in one branch. `Assessment.class_results_for_period/3` learns to take precomputed year-wide inputs (`grading_rules`, `class_subjects_by_sequence`) so `ReportCards.live_view/3` computes them once and slices them per term. `MarksLive.assign_pending/1` reads the in-memory `loaded` map. `StudentPhotoController` answers `304` on a matching `If-None-Match`. A `loading?` assign and one `<.loading_panel>` component give the six LiveViews a dead-render skeleton. Indexes come from `custom_indexes` through `mix ash.codegen --dev`.

**Tech Stack:** Elixir, Phoenix 1.8.16, LiveView 1.2.13, Ash 3.37 / AshPostgres (`custom_indexes`, codegen), daisyUI `skeleton` class, `:telemetry` query counting as in A3.

**Spec:** `docs/superpowers/specs/2026-11-10-audit-follow-ups-design.md` §A8.

## Global Constraints

- No figure of any bulletin view changes: trimester and annual results stay equal to `Assessment.class_results_for_period/3` called alone (Task 1 pins it).
- All-or-nothing and authorization are untouched; the dead-render skip never skips an authorization guard or a redirect (guards stay before the `connected?` check).
- The photo ownership check is unchanged (`Enrollment.fetch_owned_student/2`, `Uploads.resolve/2`); the `304` path runs the same checks before answering.
- Never write a migration by hand: `mix ash.codegen --dev` from the resources' `custom_indexes`, then `mix ash.codegen a8_indexes` to name it (check `mix help ash.codegen`), then `mix ash.migrate` on dev (never reset the dev DB).
- Branch `feat/audit-a8` in `.claude/worktrees/audit-a8`, `MIX_TEST_PARTITION=a8`; explicit paths in commits; `mix precommit` green before merge. Every new string through Gettext (FR source, EN filled, no fuzzy).

## Review Focus

1. A LiveView opened by a crawler or a user with JavaScript blocked stays on the skeleton forever: the skeleton must say what is loading in words (`gettext("Chargement…")`), never a blank page — Task 5 tests that each dead render carries its `#…-loading` text.
2. An expired or stale session on the connected pass: the guards in `mount/3` run on both passes, so the redirect behaviour is unchanged — Task 5 tests one guarded page (DayLive without `can_manage_conduct?`) still redirects on `live/2`.
3. A photo replaced after the browser cached the old one: the URL already changes (`?v=<basename>`), and the ETag is that basename, so a replaced photo is never served from the old entry — Task 3 tests that a different `If-None-Match` gets `200`.
4. A T3 view where T1 is published and T2 is not: the published snapshot still wins for T1 and the shared inputs are used for T2 only — Task 1 tests it.
5. A pending make-up list after a save that clears an absence (student becomes graded): the name leaves the list without a column re-read — Task 2 tests it.

---

### Task 1: T3 and annual bulletin view in one pass

**Files:**
- Modify: `lib/teacher_assistant/assessment.ex` (`class_results_for_period/3` → `/4` with `opts`, `period_result/6`, `grading_rules/2`, `passage_rules/2`, new `period_inputs/3`)
- Modify: `lib/teacher_assistant/report_cards.ex` (`live_view/3` lines 45–72, `template/2` :85, `prior_terms/4` :919, `term_results/3` :939, `annual_summary/4` :950, `council_entry/4` :816, `group_subtotals?/1` :870, `last_term?` :880)
- Test: `test/teacher_assistant/report_cards_test.exs` (new `describe "one-pass T3 view (A8)"`)

**Interfaces:**
- `Assessment.period_inputs(scope, cg, seqs) :: %{rules: GradingRules.t(), subjects_by_seq: %{sequence_id => [subject]}}` — `rules = grading_rules(scope)` (one profile read), `subjects_by_seq = class_subjects_by_sequence(scope, cg, seqs)` for the whole list (the year's séquences, `Organization.list_sequences(scope, year)` with `term` loaded).
- `Assessment.class_results_for_period(scope, cg, period, opts \\ [])` — `opts[:inputs]` as above; when given, `period_result/6` uses `inputs.rules` and slices `inputs.subjects_by_seq` by the period's séquence ids (`Map.take`) instead of calling `grading_rules/1` and `class_subjects_by_sequence/3`. `bulletin_students/4` stays per period (it depends on the period's discipline). Without `:inputs` behaviour is today's.
- `Assessment.grading_rules(scope, profile)` and `Assessment.passage_rules(scope, profile)` — same as the arity-1 versions with the profile given; arity-1 delegates to arity-2 after `fetch_school_profile`.
- `ReportCards.live_view/3`: fetches the profile once (`Accounts.fetch_school_profile/1`), passes it to `template_with/4`, `grading_rules/2`, `passage_rules/2`, `group_subtotals?/2`; computes `inputs = Assessment.period_inputs(scope, cg, year_seqs)` once when `period` is `{:trimester, _}` or `{:annual, _}`, and threads it to the main `class_results_for_period`, `term_results/3` (unpublished earlier terms only — the published snapshot still wins) and `annual_summary/4`; `list_terms` called once and shared by `prior_terms` and `last_term?`. The public signature of `live_view/3` is unchanged.

- [ ] **Step 1: Write the failing tests**

```elixir
# fixture: year with 3 terms × 2 séquences, cg with 3 students, two subjects with marks in every séquence,
# template with :previous_terms and :annual_summary shown (see tests at 581–643 for the helpers)
test "the T3 view's prior terms and annual summary equal the standalone period results" do
  # view = ReportCards.live_view(scope, cg, {:trimester, t3})
  # for each student: view.prior_terms[t1 id].per_student[sid].average == class_results_for_period(scope, cg, {:trimester, t1}).per_student[sid].average
  # same for t2 and for view.annual vs {:annual, year}; ranks equal too
end

test "a published T1 still comes from its snapshot in the one-pass view" do
  # publish T1, change a mark of S1 of T1, live_view T3: prior_terms[t1].per_student[sid].average == snapshot's, not the live one
end

test "a T3 view reads marks, assignments and the school profile once" do
  # count_queries (move the A3 helper to test/support/query_count.ex first — Task 5 needs it too):
  # needles ~s(FROM "marks") == 1, ~s(FROM "school_profiles") <= 1 (check the table name in priv/resource_snapshots),
  # ~s(FROM "teaching_contexts") or the assignments table <= 2 (competences + teachers still read it; ruling if the number differs — record it)
end
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a8 mix test test/teacher_assistant/report_cards_test.exs --only describe:"one-pass T3 view (A8)"` — Expected: the equality tests PASS already (they pin behaviour), the query-count test FAILS (4 `FROM "marks"`).
- [ ] **Step 3: Implement** `period_inputs/3`, the `opts` on `class_results_for_period`, the arity-2 rule helpers, and thread them in `live_view/3`.
- [ ] **Step 4: Run** the whole file + `test/teacher_assistant/assessment_test.exs` + `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` — PASS.
- [ ] **Step 5: Commit** `perf(bulletins): compute the year's subjects and rules once per T3 view`.

---

### Task 2: Pending make-ups from the in-memory marks

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex:150-165` (`assign_pending/1`)
- Test: `test/teacher_assistant_web/live/teacher/marks_absence_test.exs`

**Interfaces:**
- `assign_pending/1` reads `socket.assigns.loaded` (`%{student_id => field text}`): a student is pending when `grading_rules.absence == :makeup` and `MarkEntry.parse(Map.get(loaded, s.id)) in [{:ok, :absent}, {:ok, :excused}]`. A stored mark with a nil status formats as `"—"` and parses to `:error`: not pending, as today (`Marks.status/1` gives `:graded`/`:blank` for it). `Assessment.list_marks/2` is no longer called from `assign_pending`.
- No change to events or to `Marks.makeup_pending?/2` (still used elsewhere; if it becomes unused, remove it).

- [ ] **Step 1: Write the failing tests**

```elixir
test "under the make-up rule a save that marks a student absent adds them to the pending list, and clearing it removes them" do
  # mount; save_mark student Awa "abs" → has_element?(view, "#pending-makeups", "Awa"); save "12" → refute
end

test "a save does not re-read the column's marks" do
  # count_queries around render_blur(save_mark): ~s(FROM "marks") count == the number upsert_marks needs on its own
  # (measure once before the change, note it in a comment; the assertion is that number, not the old number + 1 per assessment)
end
```

- [ ] **Step 2: Run** — the first PASSES today (behaviour), the second FAILS (one extra `FROM "marks"` per assessment).
- [ ] **Step 3: Implement** the in-memory `assign_pending/1`.
- [ ] **Step 4: Run** `marks_absence_test.exs` + `marks_live_test.exs` — PASS.
- [ ] **Step 5: Measure the save diff.** Worktree server on 4010 with LiveDebugger disabled, demo school, a class of ≥ 60 students (the largest on the demo seed; note the size), DevTools → Network → the `/live/websocket` frame after one blur. Ledger the bytes. If a save ships more than ~2 KB, add `:key={s.id}` on the `mark_row` comprehension first (LiveView 1.2 keyed comprehension) and re-measure; move to `stream/3` only if still above. Record the ruling.
- [ ] **Step 6: Commit** `perf(marks): pending make-ups from the loaded marks, no column re-read`.

---

### Task 3: Photos answer 304 and cache for a week

**Files:**
- Modify: `lib/teacher_assistant_web/controllers/student_photo_controller.ex` (`send_photo/2`, `show/2`, `frozen/2`)
- Test: `test/teacher_assistant_web/controllers/student_photo_controller_test.exs`, `bulletin_print_controller_test.exs:989-1081` (frozen photo tests still pass)

**Interfaces:**
- `send_photo(conn, path)`: `etag = ~s("#{Path.basename(path, ".jpg")}")` (the UUIDv7 file name; a replaced photo has a new name); when `etag in get_req_header(conn, "if-none-match")` → `send_resp(304, "")` with the same `etag` and `cache-control` headers; else `200` with `etag`, `cache-control: private, max-age=604800`, `content-type image/jpeg`. Both `show` and `frozen` pass through it after their checks (the ownership check always runs first).
- `student_photo_url/1` keeps `?v=<basename>`; `BulletinPrintController.photo_url/2` (`bulletin_print_controller.ex:142-148`) adds `?v=<basename of photo_path>` when present, so the frozen image also has a stable cache key.

- [ ] **Step 1: Write the failing tests**

```elixir
test "a member gets the current photo with an etag, cached a week" do  # replaces test at line 19
  # get_resp_header("cache-control") == ["private, max-age=604800"]; etag == [~s("#{basename}")]
end
test "a matching If-None-Match answers 304 without a body" do  # put_req_header("if-none-match", etag) → status 304, body ""
test "a different If-None-Match answers 200 with the file" do
test "another school's member gets 404 even with a matching If-None-Match" do
test "a frozen photo's URL carries its version" do  # bulletin_print_controller_test: html =~ ~r{/photo/#{student.id}\?v=}
```

- [ ] **Step 2: Run** `MIX_TEST_PARTITION=a8 mix test test/teacher_assistant_web/controllers/student_photo_controller_test.exs` — FAIL (cache-control 86400, no etag).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the two controller test files — PASS.
- [ ] **Step 5: Commit** `perf(photos): etag + 304 and a week of browser cache`.

---

### Task 4: Websocket compression and the five indexes

**Files:**
- Modify: `lib/teacher_assistant_web/endpoint.ex:15-17`
- Modify: `lib/teacher_assistant/academics/typed_absence.ex` (new `custom_indexes` after `repo`, line 17), `mark_event.ex:20-25`, `attendance_entry.ex:27-38`, `payment.ex:14-22`, `sanction_entry.ex` (new block after line 12)
- Create (generated): `priv/repo/migrations/<ts>_a8_indexes.exs` + resource snapshots
- Test: `test/teacher_assistant_web/endpoint_test.exs` (new), `test/teacher_assistant/indexes_test.exs` (new)

**Interfaces:**
- Endpoint: `websocket: [compress: true, connect_info: [session: @session_options]]`; longpoll unchanged.
- Indexes (attribute multitenancy prefixes `workspace_id` automatically, so write them without it): `typed_absence`: `index [:sequence_id]`, `index [:term_id]`; `mark_event`: `index [:assessment_id]`, `index [:student_id]` (its existing `[:inserted_at]` stays); `attendance_entry`, `payment`, `sanction_entry`: `index [:inserted_at]`. Each with a one-line comment naming the reader (register / journal / séquence tracking / fee list / sanctions list).

- [ ] **Step 1: Write the failing tests**

```elixir
# endpoint_test.exs
test "the LiveView websocket compresses its frames" do
  # {_, _, opts} = Enum.find(TeacherAssistantWeb.Endpoint.__sockets__(), &match?({"/live", _, _}, &1)); assert opts[:websocket][:compress] == true
end
# indexes_test.exs — read pg_indexes through Repo
test "the A8 indexes exist" do
  # for {table, cols} <- [{"typed_absences", ["workspace_id","sequence_id"]}, {"typed_absences", ["workspace_id","term_id"]},
  #   {"mark_events", ["workspace_id","assessment_id"]}, {"mark_events", ["workspace_id","student_id"]},
  #   {"attendance_entries", ["workspace_id","inserted_at"]}, {"payments", ["workspace_id","inserted_at"]}, {"sanction_entries", ["workspace_id","inserted_at"]}]
  # assert an indexdef on `table` contains "(#{Enum.join(cols, ", ")})"
end
```

- [ ] **Step 2: Run** both files — FAIL.
- [ ] **Step 3: Implement** the endpoint option and the `custom_indexes`; `mix ash.codegen a8_indexes` (dev env); read the generated migration (indexes only, `concurrently: false` is fine at this size); `mix ash.migrate` on dev; `MIX_ENV=test mix ash.migrate` runs through the test alias.
- [ ] **Step 4: Run** both files — PASS. `mix ash.codegen --check` clean.
- [ ] **Step 5: Commit** `perf(db): websocket compression and indexes for the register, journal and lists`.

---

### Task 5: Data loads on the connected pass only

**Files:**
- Modify: `lib/teacher_assistant_web/components/core_components.ex` (new `loading_panel/1`)
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex` (`mount/3` :36, `handle_params/3` :411, `render/1` :941), `live/school/bulletins_live.ex` (`mount` :26, `handle_params` :55, `render` clauses :684/:807/:1093), `live/school/sequence_tracking_live.ex` (`mount` :18, `handle_params` :53, `render` :355), `live/school/dashboard_live.ex` (`mount` :18, `render` :64), `live/school/day_live.ex` (`mount` :21, `render` :96), `live/school/students_live.ex` (`mount` :20, `handle_params` :53, `render` :151)
- Create: `test/support/query_count.ex` (if not done in Task 1: move `count_queries/1` from `dashboard_live_test.exs:394-416`, `use`/import it there)
- Test: the six pages' test files (`marks_live_test`, `bulletins_live_test`, `sequence_tracking_live_test`, `dashboard_live_test`, `school_life_live_test` for DayLive, `students_live_test`)

**Interfaces:**
- `<.loading_panel id="…-loading" />` in `core_components.ex`: a `ta-panel` with three daisyUI `skeleton` bars and the text `gettext("Chargement…")` (visible, not `sr-only`).
- One pattern in all six: `mount/3` keeps its guards and redirects first, then `if connected?(socket), do: <today's full mount>, else: {:ok, assign(socket, loading?: true, page_title: …)}`; the full mount assigns `loading?: false`. `handle_params(_params, _uri, %{assigns: %{loading?: true}} = socket)` returns `{:noreply, socket}` as the first clause where a `handle_params` exists. `render(%{loading?: true} = assigns)` is the first `render` clause and draws `<Layouts.app …><.page_header title={@page_title} /><.loading_panel id="<page>-loading" /></Layouts.app>` (`page_header` at `core_components.ex:557`). Ids: `marks-loading`, `bulletins-loading`, `sequence-tracking-loading`, `dashboard-loading`, `day-loading`, `students-loading`.
- `DashboardLive` and `DayLive` have no `handle_params`: the gate lives in `mount/3` alone (ruling: spec says "handle_params loads", there is none to load from; the connected mount is the equivalent).
- `MarksLive`: `Curriculum.fetch_assigned_teaching_context` and its redirect stay before the gate; the roster and `mount_common/2` move behind it. `SequenceTrackingLive`: `loading?` is distinct from `grid: nil` (`#no-sequences` keeps meaning "no séquence").
- Dashboard query budget: after this task re-measure `dashboard_live_test.exs:344` (`@budget 155`, measured 146 with both renders) and set `@budget` to the new measurement + 10 %, comment updated with the date.

- [ ] **Step 1: Write the failing tests** (one per page, in its test file)

```elixir
test "the dead render shows the loading panel and reads no marks; the connected render shows the data" do
  # conn |> get(path) |> html_response(200) =~ "Chargement…" and has id "<page>-loading", and (count_queries) ~s(FROM "marks") == 0 (marks/bulletins/sequence tracking/dashboard)
  # {:ok, view, html} = live(conn, path): refute html =~ "<page>-loading"; the page's usual first assertion holds
end
# day_live (school_life_live_test): a user without can_manage_conduct? is still redirected by live/2
# dashboard_live_test: @budget lowered to the new measurement
```

- [ ] **Step 2: Run** the six files — FAIL (no loading panel; dead render reads marks).
- [ ] **Step 3: Implement** the component, then one LiveView at a time, running its file after each.
- [ ] **Step 4: Run** the six files + `MIX_TEST_PARTITION=a8 mix test` (whole suite) — PASS.
- [ ] **Step 5: Commit** per page or in one: `perf(live): load the six heaviest pages on the connected pass only`.

---

### Task 6: Verify and merge

- [ ] Browser check on the demo school (worktree server on 4010, phone width): Ma journée → a course's Notes (skeleton flashes then the grid; a save updates pending), `/school` as proviseur, `/school/day`, `/school/students`, `/school/bulletins` (teacher and class views), `/school/sequences`; a bulletin print of T3; a student photo twice (second request 304 in DevTools). Note the websocket frame size of one mark save in the ledger.
- [ ] `MIX_TEST_PARTITION=a8 mix precommit` → exit 0 (refresh Gettext references if the check fails on line numbers); fast-forward merge into main; `mix ash.migrate` on the dev DB from main; update memory `project-audit-2026-11-10` (A8 merged, measured numbers, deferred minors).
