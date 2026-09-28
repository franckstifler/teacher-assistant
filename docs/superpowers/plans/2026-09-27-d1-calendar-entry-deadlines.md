# D1 — Editable calendar and grade-entry deadlines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A calendar manager edits the sequence dates, grade-entry deadlines and class-council dates of the active year from Settings. Teachers see the effective deadline on the marks page.

**Architecture:** Two nullable dates are added: `Sequence.entry_deadline` and `Term.class_council_date`. A null deadline falls back to `end_date + 5 days` through the calculation `grade_entry_deadline`. Cross-row coherence (overlaps, year bounds, deadline and council order) lives in a pure `CalendarRules` module. `Organization.update_calendar/3` checks the whole proposed calendar with it, then writes every row inside one `Ash.transact`. Per-row authorization is enforced by the existing admin-only update policies.

**Tech Stack:** Elixir 1.20, Ash 3.33 / AshPostgres 2.13, Phoenix LiveView 1.x, daisyUI, Gettext (French msgids, `en` translations).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` § D1

## Global Constraints

- Migrations are generated, never hand-written: iterate with `mix ash.codegen --dev`, and finish with the named `mix ash.codegen calendar_milestones` (this squashes the dev migrations). `mix ash.codegen --check` must be clean at the final commit.
- Default grace period: **5 days** after `end_date` (`Reference.entry_grace_days/0`).
- UI copy is written as French gettext msgids. Every new msgid gets an English `msgstr` in `priv/gettext/en/LC_MESSAGES/default.po` (run `mix gettext.extract --merge` first).
- Use `<.input>` for every field. Do not add inline `<script>`.
- Finish with `mix precommit`. It does not fail on warnings (the alias flag is misspelled), so also run `mix compile --warnings-as-errors`.

## Review Focus

1. **Empty date field submitted** (a manager clears "début"): the error is `:required` on that row, not a crash. Tested in Task 2.
2. **Unparseable date string** (old browser, hand-edited request): the error is `:invalid_date`, and nothing is written. Tested in Task 2 and Task 3.
3. **Extending a sequence's end past an explicit deadline**: rejected with `:deadline_before_end`, not silently moved. Tested in Task 2.
4. **A year with no generated calendar**: `update_calendar/3` returns `:ok` and writes nothing; the page still offers "Générer le calendrier". Tested in Task 3.
5. **A non-manager submitting the form** (a crafted event from a teacher's socket): `Forbidden`, with no partial write, because the transaction rolls back. Tested in Task 3.

---

### Task 1: Schema — entry deadline, council date, default-deadline calculation

**Files:**
- Create: `lib/teacher_assistant/academics/sequence/grade_entry_deadline.ex`
- Modify: `lib/teacher_assistant/academics/sequence.ex`
- Modify: `lib/teacher_assistant/academics/term.ex`
- Modify: `lib/teacher_assistant/academics/reference.ex` (next to `@sequence_weights`, line ~49)
- Test: `test/teacher_assistant/academics/calendar_test.exs` (append to `CalendarTest`)
- Generated: `priv/repo/migrations/*_calendar_milestones.exs`, `priv/resource_snapshots/**`

**Interfaces:**
- Produces: `Sequence.entry_deadline :: Date.t() | nil`, `Sequence.grade_entry_deadline :: Date.t()` (loaded by `Organization.list_sequences/2`), `Term.class_council_date :: Date.t() | nil`, `Reference.entry_grace_days() :: 5`. `Sequence :update` accepts `:entry_deadline`; `Term :update` accepts `:class_council_date`.

- [ ] **Step 1: Write the failing tests** (append inside `TeacherAssistant.Academics.CalendarTest`, which already sets up `year` and `scope`)

```elixir
  test "a sequence without an explicit deadline closes grade entry 5 days after its end",
       %{year: year, scope: scope} do
    :ok = Organization.build_default_calendar(scope, year)
    [s1 | _] = Organization.list_sequences(scope, year)
    assert s1.entry_deadline == nil
    assert s1.grade_entry_deadline == Date.add(s1.end_date, 5)
  end

  test "an explicit deadline before the sequence end is rejected by the database",
       %{year: year, scope: scope} do
    :ok = Organization.build_default_calendar(scope, year)
    [s1 | _] = Organization.list_sequences(scope, year)

    assert {:error, %Ash.Error.Invalid{}} =
             s1
             |> Ash.Changeset.for_update(:update, %{entry_deadline: Date.add(s1.end_date, -1)},
               scope: scope
             )
             |> Ash.update()
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/calendar_test.exs`
Expected: FAIL, because `entry_deadline` / `grade_entry_deadline` do not exist yet.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/reference.ex`, below `@integration_weeks`:

```elixir
  @doc "Days after a séquence's end during which marks may still be entered, when no explicit deadline is set."
  def entry_grace_days, do: 5
```

`lib/teacher_assistant/academics/sequence/grade_entry_deadline.ex`:

```elixir
defmodule TeacherAssistant.Academics.Sequence.GradeEntryDeadline do
  @moduledoc """
  The effective grade-entry deadline of a séquence: its explicit `entry_deadline`,
  or `end_date + Reference.entry_grace_days/0` when none is set (the school default).
  """
  use Ash.Resource.Calculation

  alias TeacherAssistant.Academics.Reference

  @impl true
  def load(_query, _opts, _context), do: [:entry_deadline, :end_date]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn seq ->
      seq.entry_deadline || Date.add(seq.end_date, Reference.entry_grace_days())
    end)
  end
end
```

`lib/teacher_assistant/academics/sequence.ex`:
- in `postgres do … check_constraints do`, add:

```elixir
      check_constraint :entry_deadline, "sequences_entry_deadline_after_end_check",
        check: "entry_deadline IS NULL OR entry_deadline >= end_date",
        message: "must not be before the end date"
```

- in `defaults`, change the update list to `update: [:number, :position_in_term, :start_date, :end_date, :integration_week, :entry_deadline]`
- in `read :for_academic_year`, change the prepare to `prepare build(load: [:term, :grade_entry_deadline], sort: [number: :asc])`
- in `attributes`, after `:end_date`, add `attribute :entry_deadline, :date, public?: true`
- add a block after `relationships`:

```elixir
  calculations do
    calculate :grade_entry_deadline, :date, TeacherAssistant.Academics.Sequence.GradeEntryDeadline do
      public? true
    end
  end
```

`lib/teacher_assistant/academics/term.ex`:
- `update: [:position]` becomes `update: [:position, :class_council_date]`
- in `attributes`, after `:position`, add `attribute :class_council_date, :date, public?: true`

- [ ] **Step 4: Generate the migration and run the tests**

Run: `mix ash.codegen --dev && mix ash.migrate && MIX_ENV=test mix ash.migrate && mix test test/teacher_assistant/academics/calendar_test.exs`
Expected: PASS. The generated migration adds two nullable columns and one check constraint, and nothing else. If it touches anything more, stop.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics priv/repo/migrations priv/resource_snapshots test/teacher_assistant/academics/calendar_test.exs
git commit -m "feat: séquence grade-entry deadline and trimester class-council date

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `CalendarRules` — whole-calendar coherence

**Files:**
- Create: `lib/teacher_assistant/academics/calendar_rules.ex`
- Test: `test/teacher_assistant/academics/calendar_rules_test.exs`

**Interfaces:**
- Consumes: nothing from Task 1. It is pure, and works on plain maps.
- Produces: `CalendarRules.validate(year, sequences, terms) :: :ok | {:error, {:invalid, %{id => [{field, code}]}}}` where
  - `year :: %{start_date: Date.t(), end_date: Date.t()}`
  - `sequences :: [%{id, number, term_id, start_date, end_date, entry_deadline}]`; each date is `Date.t() | nil | :invalid`
  - `terms :: [%{id, class_council_date}]` with `Date.t() | nil | :invalid`
  - `code ∈ :required | :invalid_date | :end_before_start | :outside_year | :overlaps_previous | :deadline_before_end | :council_before_term_end`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CalendarRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.CalendarRules

  @year %{start_date: ~D[2026-09-07], end_date: ~D[2027-06-30]}

  defp seq(n, term, start_date, end_date, deadline \\ nil),
    do: %{
      id: "s#{n}",
      number: n,
      term_id: term,
      start_date: start_date,
      end_date: end_date,
      entry_deadline: deadline
    }

  defp valid_seqs,
    do: [
      seq(1, "t1", ~D[2026-09-07], ~D[2026-10-02]),
      seq(2, "t1", ~D[2026-10-05], ~D[2026-11-13])
    ]

  defp errors(result) do
    assert {:error, {:invalid, errors}} = result
    errors
  end

  test "a coherent calendar passes, with gaps between séquences allowed" do
    assert :ok = CalendarRules.validate(@year, valid_seqs(), [%{id: "t1", class_council_date: nil}])
  end

  test "missing and unparseable dates are reported per field" do
    [s1, s2] = valid_seqs()
    seqs = [%{s1 | start_date: nil}, %{s2 | end_date: :invalid}]
    errs = errors(CalendarRules.validate(@year, seqs, []))
    assert {:start_date, :required} in errs["s1"]
    assert {:end_date, :invalid_date} in errs["s2"]
  end

  test "an end before its start is rejected" do
    [s1, s2] = valid_seqs()
    errs = errors(CalendarRules.validate(@year, [%{s1 | end_date: ~D[2026-09-01]}, s2], []))
    assert {:end_date, :end_before_start} in errs["s1"]
  end

  test "séquences must stay inside the academic year" do
    [s1, s2] = valid_seqs()
    seqs = [%{s1 | start_date: ~D[2026-09-01]}, %{s2 | end_date: ~D[2027-07-15]}]
    errs = errors(CalendarRules.validate(@year, seqs, []))
    assert {:start_date, :outside_year} in errs["s1"]
    assert {:end_date, :outside_year} in errs["s2"]
  end

  test "a séquence must start after the previous one ends" do
    [s1, s2] = valid_seqs()
    errs = errors(CalendarRules.validate(@year, [s1, %{s2 | start_date: ~D[2026-10-02]}], []))
    assert {:start_date, :overlaps_previous} in errs["s2"]
  end

  test "an explicit deadline cannot precede the séquence end, even after the end moves" do
    [s1, s2] = valid_seqs()
    moved = %{s1 | end_date: ~D[2026-10-02], entry_deadline: ~D[2026-10-01]}
    errs = errors(CalendarRules.validate(@year, [moved, s2], []))
    assert {:entry_deadline, :deadline_before_end} in errs["s1"]
  end

  test "a class council cannot precede the end of its trimester" do
    terms = [%{id: "t1", class_council_date: ~D[2026-11-10]}]
    errs = errors(CalendarRules.validate(@year, valid_seqs(), terms))
    assert {:class_council_date, :council_before_term_end} in errs["t1"]

    assert errors(CalendarRules.validate(@year, valid_seqs(), [%{id: "t1", class_council_date: :invalid}]))["t1"] ==
             [{:class_council_date, :invalid_date}]
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/calendar_rules_test.exs`
Expected: FAIL with `CalendarRules.validate/3 is undefined`.

- [ ] **Step 3: Implement** `lib/teacher_assistant/academics/calendar_rules.ex`

```elixir
defmodule TeacherAssistant.Academics.CalendarRules do
  @moduledoc """
  Coherence rules for a whole academic-year calendar, checked before any row is
  written. Single-row checks (see `Sequence`'s check constraints) cannot see an
  overlap between two séquences or a council date against its trimester, so the
  whole proposed calendar is validated at once.

  Dates are `Date.t()`, `nil` (blank) or `:invalid` (unparseable input). Errors are
  `{field, code}` codes keyed by row id; the UI translates them.
  """

  def validate(year, sequences, terms) do
    sequences = Enum.sort_by(sequences, & &1.number)

    errors =
      Enum.flat_map(sequences, &sequence_errors(year, &1)) ++
        order_errors(sequences) ++ Enum.flat_map(terms, &term_errors(&1, sequences))

    case Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1)) do
      map when map_size(map) == 0 -> :ok
      map -> {:error, {:invalid, map}}
    end
  end

  defp sequence_errors(year, %{id: id} = seq) do
    presence =
      [
        presence_error(:start_date, seq.start_date, true),
        presence_error(:end_date, seq.end_date, true),
        presence_error(:entry_deadline, seq.entry_deadline, false)
      ]
      |> Enum.reject(&is_nil/1)

    if presence == [] do
      [
        {Date.before?(seq.end_date, seq.start_date), {:end_date, :end_before_start}},
        {Date.before?(seq.start_date, year.start_date), {:start_date, :outside_year}},
        {Date.after?(seq.end_date, year.end_date), {:end_date, :outside_year}},
        {seq.entry_deadline != nil and Date.before?(seq.entry_deadline, seq.end_date),
         {:entry_deadline, :deadline_before_end}}
      ]
      |> Enum.flat_map(fn {failed?, error} -> if failed?, do: [{id, error}], else: [] end)
    else
      Enum.map(presence, &{id, &1})
    end
  end

  defp presence_error(field, :invalid, _required?), do: {field, :invalid_date}
  defp presence_error(field, nil, true), do: {field, :required}
  defp presence_error(_field, _value, _required?), do: nil

  defp order_errors(sequences) do
    for [prev, next] <- Enum.chunk_every(sequences, 2, 1, :discard),
        match?(%Date{}, prev.end_date) and match?(%Date{}, next.start_date),
        not Date.after?(next.start_date, prev.end_date),
        do: {next.id, {:start_date, :overlaps_previous}}
  end

  defp term_errors(%{class_council_date: :invalid, id: id}, _sequences),
    do: [{id, {:class_council_date, :invalid_date}}]

  defp term_errors(%{class_council_date: %Date{} = council, id: id}, sequences) do
    ends = for %{term_id: ^id, end_date: %Date{} = d} <- sequences, do: d

    if ends != [] and Date.before?(council, Enum.max(ends, Date)),
      do: [{id, {:class_council_date, :council_before_term_end}}],
      else: []
  end

  defp term_errors(_term, _sequences), do: []
end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/calendar_rules_test.exs`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/calendar_rules.ex test/teacher_assistant/academics/calendar_rules_test.exs
git commit -m "feat: whole-calendar coherence rules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `Organization.update_calendar/3` — atomic save

**Files:**
- Modify: `lib/teacher_assistant/organization.ex` (after `list_terms/2`, ~line 181)
- Test: `test/teacher_assistant/academics/calendar_edit_test.exs`

**Interfaces:**
- Consumes: `CalendarRules.validate/3` (Task 2); `Sequence :update` with `:entry_deadline` and `Term :update` with `:class_council_date` (Task 1); `list_terms/2` (it loads `:sequences`).
- Produces: `Organization.update_calendar(scope, year, params) :: :ok | {:error, {:invalid, errors}} | {:error, Ash.Error.t()}`. `params` is form-shaped and string-keyed: `%{"sequences" => %{seq_id => %{"start_date" => iso | "", "end_date" => …, "entry_deadline" => …}}, "terms" => %{term_id => %{"class_council_date" => iso | ""}}}`. A missing key keeps the stored value, and `""` means blank.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.CalendarEditTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [s1, s2 | _] = Organization.list_sequences(scope, year)
    [t1 | _] = Organization.list_terms(scope, year)
    %{scope: scope, year: year, s1: s1, s2: s2, t1: t1}
  end

  defp iso(date), do: Date.to_iso8601(date)

  test "saves dates, an explicit deadline and a council date", ctx do
    %{scope: scope, year: year, s1: s1, s2: s2, t1: t1} = ctx

    params = %{
      "sequences" => %{
        s1.id => %{
          "end_date" => iso(Date.add(s1.end_date, -3)),
          "entry_deadline" => iso(s1.end_date)
        }
      },
      "terms" => %{t1.id => %{"class_council_date" => iso(Date.add(s2.end_date, 4))}}
    }

    assert :ok = Organization.update_calendar(scope, year, params)
    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.end_date == Date.add(s1.end_date, -3)
    assert u1.grade_entry_deadline == s1.end_date
    assert hd(Organization.list_terms(scope, year)).class_council_date == Date.add(s2.end_date, 4)
  end

  test "clearing a deadline falls back to the default rule", %{scope: scope, year: year, s1: s1} do
    :ok =
      Organization.update_calendar(scope, year, %{
        "sequences" => %{s1.id => %{"entry_deadline" => iso(Date.add(s1.end_date, 9))}}
      })

    :ok =
      Organization.update_calendar(scope, year, %{"sequences" => %{s1.id => %{"entry_deadline" => ""}}})

    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.entry_deadline == nil
    assert u1.grade_entry_deadline == Date.add(u1.end_date, 5)
  end

  test "an incoherent calendar is rejected and nothing is written", ctx do
    %{scope: scope, year: year, s1: s1, s2: s2} = ctx

    params = %{
      "sequences" => %{
        s1.id => %{"entry_deadline" => iso(Date.add(s1.end_date, 2))},
        s2.id => %{"start_date" => iso(s1.end_date)}
      }
    }

    assert {:error, {:invalid, errors}} = Organization.update_calendar(scope, year, params)
    assert {:start_date, :overlaps_previous} in errors[s2.id]
    [u1, u2 | _] = Organization.list_sequences(scope, year)
    assert u1.entry_deadline == nil
    assert u2.start_date == s2.start_date
  end

  test "an unparseable date is reported, not raised", %{scope: scope, year: year, s1: s1} do
    assert {:error, {:invalid, errors}} =
             Organization.update_calendar(scope, year, %{
               "sequences" => %{s1.id => %{"end_date" => "31/12/2025"}}
             })

    assert {:end_date, :invalid_date} in errors[s1.id]
  end

  test "a year without a calendar saves as a no-op", %{scope: scope} do
    {:ok, bare} =
      Organization.create_academic_year(scope, %{
        name: "2027-2028",
        start_date: ~D[2027-09-06],
        end_date: ~D[2028-07-28],
        active: false
      })

    assert :ok = Organization.update_calendar(scope, bare, %{})
  end

  test "a teacher cannot change the calendar", %{scope: scope, year: year, s1: s1} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    params = %{"sequences" => %{s1.id => %{"end_date" => iso(Date.add(s1.end_date, -1))}}}
    assert_forbidden(Organization.update_calendar(teacher, year, params))
    assert hd(Organization.list_sequences(scope, year)).end_date == s1.end_date
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant/academics/calendar_edit_test.exs`
Expected: FAIL with `Organization.update_calendar/3 is undefined`.

- [ ] **Step 3: Implement.** In `lib/teacher_assistant/organization.ex`, add `CalendarRules` to the alias line: `alias TeacherAssistant.Academics.{AcademicYear, CalendarRules, Sequence, Term, Workspace}`. Then add after `list_terms/2`:

```elixir
  @doc """
  Saves a year's whole calendar — séquence dates, grade-entry deadlines and
  trimester class-council dates — in one transaction, after `CalendarRules`
  accepts the complete proposed calendar (so a later row can never be written
  against a stale neighbour).

  `params` is form-shaped and string-keyed:
  `%{"sequences" => %{id => %{"start_date" => "2026-09-07", "end_date" => …,
  "entry_deadline" => …}}, "terms" => %{id => %{"class_council_date" => …}}}`.
  A missing key keeps the stored value; `""` blanks it. Authorization is the
  per-row update policy (admin axis): a forbidden row rolls back every write.
  """
  def update_calendar(%Scope{} = scope, %AcademicYear{} = year, %{} = params) do
    terms = list_terms(scope, year)
    seq_params = Map.get(params, "sequences", %{})
    term_params = Map.get(params, "terms", %{})

    sequences =
      for term <- terms, seq <- term.sequences do
        p = Map.get(seq_params, seq.id, %{})

        %{
          record: seq,
          id: seq.id,
          number: seq.number,
          term_id: term.id,
          start_date: date_param(p, "start_date", seq.start_date),
          end_date: date_param(p, "end_date", seq.end_date),
          entry_deadline: date_param(p, "entry_deadline", seq.entry_deadline)
        }
      end

    proposed_terms =
      for term <- terms do
        p = Map.get(term_params, term.id, %{})

        %{
          record: term,
          id: term.id,
          class_council_date: date_param(p, "class_council_date", term.class_council_date)
        }
      end

    with :ok <- CalendarRules.validate(year, sequences, proposed_terms),
         {:ok, :ok} <-
           Ash.transact([Sequence, Term], fn ->
             with :ok <- update_rows(sequences, [:start_date, :end_date, :entry_deadline], scope),
                  :ok <- update_rows(proposed_terms, [:class_council_date], scope),
                  do: {:ok, :ok}
           end) do
      :ok
    end
  end

  defp date_param(params, key, current) do
    case Map.fetch(params, key) do
      :error -> current
      {:ok, ""} -> nil
      {:ok, value} when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          {:error, _} -> :invalid
        end
    end
  end

  defp update_rows(rows, fields, scope) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      row.record
      |> Ash.Changeset.for_update(:update, Map.take(row, fields), scope: scope)
      |> Ash.update()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant/academics/calendar_edit_test.exs test/teacher_assistant/academics/calendar_test.exs`
Expected: PASS. If the teacher test gets `{:error, %Ash.Error.Invalid{}}` instead of `Forbidden`, the transaction wrapped the error. In that case, make the domain function unwrap it with `Ash.Error.to_error_class/1` and assert again. Do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/organization.ex test/teacher_assistant/academics/calendar_edit_test.exs
git commit -m "feat: atomic academic calendar update

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Settings → Année — editable calendar

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (the `year-calendar-*` block, ~lines 213–244; `mount/3`; the new `handle_event("save_calendar", …)` next to `generate_calendar`; private helpers at the bottom)
- Modify: `test/teacher_assistant_web/live/school/settings_live_test.exs` (the test "settings lists the active year's séquences", ~line 83, plus new tests)
- Modify: `priv/gettext/default.pot`, `priv/gettext/{fr,en}/LC_MESSAGES/default.po` (via extract)

**Interfaces:**
- Consumes: `Organization.update_calendar/3` (Task 3); `seq.grade_entry_deadline`, `seq.term.class_council_date` (Task 1: `list_sequences/2` loads `:term` and `:grade_entry_deadline`).
- Produces: DOM ids `#calendar-form`, `#sequence-<id>` (one `<tr>` per séquence), and inputs named `calendar[sequences][<id>][start_date|end_date|entry_deadline]` and `calendar[terms][<term_id>][class_council_date]` (the latter only on the row where `position_in_term == 2`).

- [ ] **Step 1: Write the failing tests.** Replace the assertion `assert has_element?(view, "#year-calendar-#{year.id} li", "Séquence 6")` with `assert has_element?(view, "#year-calendar-#{year.id}", "Séquence 6")`, then append:

```elixir
  test "head edits a séquence end and its grade-entry deadline", %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    [s1 | _] = Organization.list_sequences(scope, year)
    new_end = Date.add(s1.end_date, -2)
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#calendar-form", %{
      "calendar" => %{
        "sequences" => %{
          s1.id => %{
            "end_date" => Date.to_iso8601(new_end),
            "entry_deadline" => Date.to_iso8601(s1.end_date)
          }
        }
      }
    })
    |> render_submit()

    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.end_date == new_end
    assert u1.entry_deadline == s1.end_date
    assert render(view) =~ "Calendrier enregistré."
  end

  test "an overlapping séquence is flagged on its row and nothing is saved", %{
    conn: conn,
    scope: scope
  } do
    year = Organization.current_academic_year(scope)
    [s1, s2 | _] = Organization.list_sequences(scope, year)
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#calendar-form", %{
      "calendar" => %{"sequences" => %{s2.id => %{"start_date" => Date.to_iso8601(s1.end_date)}}}
    })
    |> render_submit()

    assert has_element?(view, "#sequence-#{s2.id}", "Commence avant la fin de la séquence précédente.")
    assert Enum.at(Organization.list_sequences(scope, year), 1).start_date == s2.start_date
  end
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `mix test test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: the 2 new tests FAIL (no `#calendar-form`).

- [ ] **Step 3: Implement.**

In `mount/3`, next to the other assigns, add `|> assign(calendar_errors: %{}, calendar_params: %{})`.

Replace the whole `<div :if={@active_year && @active_sequences != []} id={"year-calendar-#{@active_year.id}"} …>…</div>` block with:

```heex
          <div
            :if={@active_year && @active_sequences != []}
            id={"year-calendar-#{@active_year.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <h3 class="text-sm font-semibold">
              {gettext("Trimestres et séquences")} · {@active_year.name}
            </h3>
            <p class="mt-1 text-xs text-base-content/70">
              {gettext(
                "Sans date limite, la saisie des notes ferme %{days} jours après la fin de la séquence.",
                days: TeacherAssistant.Academics.Reference.entry_grace_days()
              )}
            </p>

            <.form
              for={to_form(%{}, as: :calendar)}
              id="calendar-form"
              phx-submit="save_calendar"
              class="mt-3 space-y-3"
            >
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>{gettext("Séquence")}</th>
                      <th>{gettext("Début")}</th>
                      <th>{gettext("Fin")}</th>
                      <th>{gettext("Limite de saisie")}</th>
                      <th>{gettext("Conseil de classe")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={seq <- @active_sequences} id={"sequence-#{seq.id}"} class="align-top">
                      <td class="whitespace-nowrap">
                        <span class="text-base-content/60">
                          {gettext("Trimestre %{n}", n: seq.term.position)} ·
                        </span>
                        {gettext("Séquence %{n}", n: seq.number)}
                      </td>
                      <td :for={field <- [:start_date, :end_date, :entry_deadline]}>
                        <.input
                          type="date"
                          name={"calendar[sequences][#{seq.id}][#{field}]"}
                          value={calendar_value(@calendar_params, "sequences", seq.id, field, Map.get(seq, field))}
                          disabled={!@can_manage_calendar?}
                          errors={calendar_errors(@calendar_errors, seq.id, field)}
                        />
                        <span
                          :if={field == :entry_deadline and is_nil(seq.entry_deadline)}
                          class="ta-num text-xs text-base-content/60"
                        >
                          {gettext("Par défaut : %{date}",
                            date: Calendar.strftime(seq.grade_entry_deadline, "%d/%m/%Y")
                          )}
                        </span>
                      </td>
                      <td>
                        <.input
                          :if={seq.position_in_term == 2}
                          type="date"
                          name={"calendar[terms][#{seq.term_id}][class_council_date]"}
                          value={
                            calendar_value(@calendar_params, "terms", seq.term_id, :class_council_date, seq.term.class_council_date)
                          }
                          disabled={!@can_manage_calendar?}
                          errors={calendar_errors(@calendar_errors, seq.term_id, :class_council_date)}
                        />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <button :if={@can_manage_calendar?} type="submit" class="btn btn-primary btn-sm">
                {gettext("Enregistrer le calendrier")}
              </button>
            </.form>
          </div>
```

Add the event (next to `generate_calendar`):

```elixir
  def handle_event("save_calendar", %{"calendar" => params}, socket) do
    case Organization.update_calendar(socket.assigns.scope, socket.assigns.active_year, params) do
      :ok ->
        {:noreply,
         socket
         |> assign(calendar_errors: %{}, calendar_params: %{})
         |> load_years()
         |> put_flash(:info, gettext("Calendrier enregistré."))}

      {:error, {:invalid, errors}} ->
        {:noreply,
         socket
         |> assign(calendar_errors: errors, calendar_params: params)
         |> put_flash(:error, gettext("Calendrier non enregistré : corrigez les dates signalées."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Calendrier non enregistré."))}
    end
  end
```

Add private helpers at the bottom of the module:

```elixir
  # The submitted value after a rejected save (so the manager's input is kept),
  # otherwise the stored date.
  defp calendar_value(params, kind, id, field, stored) do
    get_in(params, [kind, id, Atom.to_string(field)]) || stored
  end

  defp calendar_errors(errors, id, field) do
    for {^field, code} <- Map.get(errors, id, []), do: calendar_error_text(code)
  end

  defp calendar_error_text(:required), do: gettext("Date obligatoire.")
  defp calendar_error_text(:invalid_date), do: gettext("Date invalide.")
  defp calendar_error_text(:end_before_start), do: gettext("La fin est avant le début.")
  defp calendar_error_text(:outside_year), do: gettext("En dehors de l'année scolaire.")

  defp calendar_error_text(:overlaps_previous),
    do: gettext("Commence avant la fin de la séquence précédente.")

  defp calendar_error_text(:deadline_before_end),
    do: gettext("La limite de saisie est avant la fin de la séquence.")

  defp calendar_error_text(:council_before_term_end),
    do: gettext("Le conseil est avant la fin du trimestre.")
```

Then run `mix gettext.extract --merge` and fill the English `msgstr` for each new msgid in `priv/gettext/en/LC_MESSAGES/default.po`:
"Calendar saved." / "Calendar not saved: fix the highlighted dates." / "Calendar not saved." / "Save calendar" / "Start" / "End" / "Mark entry deadline" / "Class council" / "Default: %{date}" / "Without a deadline, mark entry closes %{days} days after the sequence ends." / "Date required." / "Invalid date." / "End is before start." / "Outside the academic year." / "Starts before the previous sequence ends." / "Mark entry deadline is before the sequence end." / "Council is before the end of the term.". The old msgid "…modifiables prochainement." becomes obsolete: let extract mark it, then delete it.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: PASS (all tests, including the edited listing test).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/settings_live.ex test/teacher_assistant_web/live/school/settings_live_test.exs priv/gettext
git commit -m "feat: edit séquence dates, entry deadlines and council dates in settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Marks page shows the effective grade-entry deadline

**Files:**
- Modify: `lib/teacher_assistant_web/live/teacher/marks_live.ex` (both toolbars: after `<form id="seq-select" …>` in the render near line 477, and the one near line 571)
- Test: `test/teacher_assistant_web/live/teacher/marks_live_test.exs`
- Modify: gettext files

**Interfaces:**
- Consumes: `@seq.grade_entry_deadline` (Task 1; the sequences come from `Organization.list_sequences/2`).

- [ ] **Step 1: Write the failing test** (append to `MarksLiveTest`)

```elixir
  test "shows the séquence's grade-entry deadline", %{conn: conn, ctx: ctx, seq: seq, a: a} do
    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{ctx.id}/marks?seq=#{seq.id}&assessment=#{a.id}")

    assert has_element?(
             view,
             "#entry-deadline",
             Calendar.strftime(seq.grade_entry_deadline, "%d/%m/%Y")
           )
  end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `mix test test/teacher_assistant_web/live/teacher/marks_live_test.exs`
Expected: the new test FAILS (no `#entry-deadline`).

- [ ] **Step 3: Implement.** In **both** toolbars, directly after the closing `</form>` of `id="seq-select"`, insert:

```heex
          <p
            :if={@seq}
            id="entry-deadline"
            class="ta-num self-center text-xs text-base-content/70"
          >
            {gettext("Limite de saisie : %{date}",
              date: Calendar.strftime(@seq.grade_entry_deadline, "%d/%m/%Y")
            )}
          </p>
```

Run `mix gettext.extract --merge` and set the English msgstr to "Mark entry deadline: %{date}".

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `mix test test/teacher_assistant_web/live/teacher/`
Expected: PASS (the combined-course marks tests still pass; the combined branch renders the same element).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/teacher/marks_live.ex test/teacher_assistant_web/live/teacher/marks_live_test.exs priv/gettext
git commit -m "feat: show the grade-entry deadline on the marks page

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Name the migration, full gate

- [ ] **Step 1:** Run `mix ash.codegen calendar_milestones`. This replaces the `_dev` migration with a named one. Then run `mix ash.reset && MIX_ENV=test mix ash.reset`.
- [ ] **Step 2:** Run `mix ash.codegen --check && mix compile --warnings-as-errors && mix precommit`.
  Expected: no drift, no warnings, the whole suite green. The count is the current 747 plus the new tests.
- [ ] **Step 3:** Commit the named migration and snapshots (`precommit`'s formatter may have rewritten files, so check `git status`):

```bash
git add -A priv/repo/migrations priv/resource_snapshots lib test
git commit -m "chore: name the calendar milestones migration

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
