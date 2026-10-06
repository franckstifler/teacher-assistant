# KLM9 — Next school year and closed years Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school year can be closed for good (everything in it read only, payments excepted); the Proviseur
or Censeur starts the next year from a 4-step wizard that carries classes, courses and form masters over and
re-enrols students from their passage decisions; closed years stay viewable.

**Architecture:** 9a: `AcademicYear.status` and a `YearOpen` validation that each year-bound resource
declares with the relationship path to its year; a test discovers every year-bound resource (fixed point over
`belongs_to`) and fails when a write action lacks the check. 9b: a pure `Academics.NewYearPlan` (targets,
placements, sizes, totals) and a `TeacherAssistant.NewYear` context (`plan/2` reads, `start/2` writes in one
`Ash.transact`), driven by `NewYearLive`. 9c: `Organization.class_year/2` so the results and bulletin pages
read the class's own year, and a read-only `/school/years/:id`.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3.33 (custom validations with `atomic/3`, `Ash.transact`,
row locks), AshPostgres, Gettext.

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM9 — Next school year and closed years".

## Global Constraints

- Worktree `.claude/worktrees/klm9`, branch `klm9-next-year`, `MIX_TEST_PARTITION=9` for every `mix test`.
  Stage explicit paths only — never `git commit -a` (the user runs parallel sessions).
- Migration: the only schema change is `academic_years.status`. Generate it **named** in Task 1
  (`mix ash.codegen klm9_closed_years`), never by hand; `mix ash.codegen --check` clean at the end.
- `AcademicYear.status` enum `:open | :closed`, default `:open`; a closed year is never activated, updated or
  destroyed; no reopening.
- Refusal message (domain, French, not gettext — domain errors are not translated in this codebase):
  « L'année <nom> est clôturée. »
- Not locked: `Payment` (arrears), `MarkCorrection :mark_seen`, `MarkEvent`, school-wide data.
- Placement decision = the annual council's choice, else the engine's proposal; `:admis`/`:admis_rachat` →
  target, `:redouble` → same class (repeater), `:exclu` / none / admis without target → not re-enrolled.
- The spec names a generic action `AcademicYear.start_next_year`; this plan implements it as
  `TeacherAssistant.NewYear.start/3` inside one `Ash.transact` (the codebase's pattern for multi-resource
  writes, e.g. `Discipline.set_conduct_marks/4`); authorization is each inner action's policy (admin axis).
- Strings through gettext; after `mix gettext.extract --merge`, fill every new `en` msgstr and clear new fuzzy
  flags. This repo's flag line is `#, elixir-autogen, elixir-format, fuzzy`: compare `grep -c fuzzy` per
  locale with main, not `grep -c "#, fuzzy"`.
- `mix compile --warnings-as-errors` and `MIX_TEST_PARTITION=9 mix precommit` before the last commit
  (precommit does not gate on warnings; its format step rewrites files — stage them).

## Review Focus

1. A write into a closed year through a generic action (`Enrollment.add_student/3` → `:enroll_new`, marks
   `:upsert_all`) — refused, and nothing half-written (no orphan student) (test in Task 2).
2. Two admins start the next year at once, or one clicks twice — the second gets « déjà clôturée », one new
   year exists (test in Task 5).
3. A forged admis target naming a class of another year or garbage — treated as « Ne pas réinscrire », no
   crash (test in Task 5).
4. Blank or duplicate class labels at step 3 — refused at step 3, nothing started (test in Task 6).
5. After closing, the teacher of a past class opens its results (allowed, read only); a teacher who never
   taught it is turned away (test in Task 7).

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm9 -b klm9-next-year main
cd .claude/worktrees/klm9 && mix deps.get
MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/academic_year_test.exs
```

Expected: 0 failures. Every later command runs inside `.claude/worktrees/klm9`.

---

## 9a — Closed years and the lock

### Task 1: Year status, `:close`, the `YearOpen` validation on years, terms and classes

**Files:**
- Create: `lib/teacher_assistant/academics/academic_year_status.ex`
- Create: `lib/teacher_assistant/academics/year_open.ex`
- Modify: `lib/teacher_assistant/academics/academic_year.ex` (attribute, `:close`, validation)
- Modify: `lib/teacher_assistant/academics/term.ex`, `lib/teacher_assistant/academics/class_group.ex`
  (validation)
- Modify: `lib/teacher_assistant/organization.ex` (`close_academic_year/2`)
- Modify: `test/support/fixtures/teacher_fixtures.ex` (`close_year!/2`)
- Create: migration + snapshot via `mix ash.codegen klm9_closed_years`
- Test: `test/teacher_assistant/academics/year_open_test.exs`

**Interfaces:**
- Produces:
  - `TeacherAssistant.Academics.YearOpen` — validation, opts `path: [atom]` (belongs_to names from the
    resource to a record carrying `academic_year_id`; `[]` = the record carries it; on `AcademicYear` the
    record is the year). `YearOpen.message(name) :: String.t()`.
  - `Organization.close_academic_year(%Scope{}, %AcademicYear{}) :: {:ok, year} | {:error, term}`
  - `TeacherFixtures.close_year!(%Scope{}, %AcademicYear{}) :: %{closed: year, next: year}` — creates an
    inactive next year (« Après <nom> », dates + 1 year, default calendar, one class « 6ème Z »), activates it,
    closes `year`.
  - `%AcademicYear{status: :open | :closed}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.YearOpenTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}
  alias TeacherAssistant.Academics.Term

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    %{head: head, year: year}
  end

  defp closed_error?({:error, error}), do: Exception.message(error) =~ "est clôturée"
  defp closed_error?(_), do: false

  test "a year starts open; closing it leaves it inactive and closed", ctx do
    assert ctx.year.status == :open
    %{closed: closed, next: next} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed.status == :closed
    refute closed.active
    assert Organization.current_academic_year(ctx.head).id == next.id
  end

  test "a closed year is never activated, changed or deleted", ctx do
    %{closed: closed} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert {:error, error} = Organization.activate_academic_year(ctx.head, closed)
    assert Exception.message(error) =~ "L'année Année de référence est clôturée."

    assert closed_error?(
             closed
             |> Ash.Changeset.for_update(:update, %{name: "Autre"}, scope: ctx.head)
             |> Ash.update()
           )

    assert closed_error?(Ash.destroy(closed, scope: ctx.head))
  end

  test "nothing is added to a closed year", ctx do
    %{closed: closed} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed_error?(
             Enrollment.create_class_group(ctx.head, closed, %{label: "6ème Y", level: "6ème"})
           )

    assert closed_error?(
             Term
             |> Ash.Changeset.for_create(:create, %{position: 9, academic_year_id: closed.id},
               scope: ctx.head
             )
             |> Ash.create()
           )
  end

  test "an existing class of a closed year is neither renamed nor deleted", ctx do
    [cg | _] = Enrollment.list_class_groups(ctx.head, ctx.year)
    TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed_error?(
             cg
             |> Ash.Changeset.for_update(:update, %{label: "Renommée"}, scope: ctx.head)
             |> Ash.update()
           )

    assert closed_error?(Ash.destroy(cg, scope: ctx.head))
  end

  test "the open year is not affected", ctx do
    %{next: next} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert {:ok, _} =
             Enrollment.create_class_group(ctx.head, next, %{label: "6ème Y", level: "6ème"})
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/year_open_test.exs`
Expected: FAIL — `TeacherFixtures.close_year!/2` undefined (and `status` unknown).

- [ ] **Step 3: The enum and the validation**

`lib/teacher_assistant/academics/academic_year_status.ex`:

```elixir
defmodule TeacherAssistant.Academics.AcademicYearStatus do
  @moduledoc "Spec KLM9: a school year is open until the next one starts, then closed for good."
  use Ash.Type.Enum, values: [:open, :closed]
end
```

`lib/teacher_assistant/academics/year_open.ex`:

```elixir
defmodule TeacherAssistant.Academics.YearOpen do
  @moduledoc """
  Spec KLM9: nothing of a closed school year is created, changed or deleted — by anyone.
  Each year-bound resource names the `path` of `belongs_to` relationships from itself to
  a record carrying `academic_year_id` (`[]`: the record carries it; on `AcademicYear`
  itself, the record is the year). The written value and the stored one are both
  checked, so a record cannot be moved into or out of a closed year either. Internal
  reads (`authorize?: false`): the check must see the year whatever the actor may read.

  No compile-time reference to `AcademicYear` (no struct pattern): that resource uses
  this validation, so a struct pattern here would deadlock compilation.
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias TeacherAssistant.Academics.AcademicYear

  @impl true
  def init(opts) do
    case opts[:path] do
      path when is_list(path) ->
        if Enum.all?(path, &is_atom/1), do: {:ok, opts}, else: {:error, "YearOpen: bad path"}

      _ ->
        {:error, "YearOpen needs `path:`, a list of belongs_to relationship names"}
    end
  end

  @impl true
  def validate(changeset, opts, _context),
    do: changeset |> year_ids(opts[:path]) |> check(changeset.tenant)

  # A single-record update or destroy carries its record, so the check runs now. A
  # query-based (bulk atomic) write has no record to follow: it must run row by row.
  @impl true
  def atomic(changeset, opts, _context) do
    case year_ids(changeset, opts[:path]) do
      [] ->
        if match?(%{__meta__: %{state: :loaded}}, changeset.data),
          do: :ok,
          else: {:not_atomic, "YearOpen reads each record's year"}

      ids ->
        check(ids, changeset.tenant)
    end
  end

  @doc "The refusal for a write touching the closed year `name`."
  def message(name), do: "L'année #{name} est clôturée."

  defp check(year_ids, tenant), do: Enum.find_value(year_ids, :ok, &closed_error(&1, tenant))

  defp year_ids(%{resource: AcademicYear, data: %{id: id}}, []) when is_binary(id), do: [id]
  defp year_ids(%{resource: AcademicYear}, []), do: []
  defp year_ids(changeset, []), do: values(changeset, :academic_year_id)

  defp year_ids(changeset, [first | rest]) do
    rel = Ash.Resource.Info.relationship(changeset.resource, first)

    changeset
    |> values(rel.source_attribute)
    |> Enum.map(&parent_year_id(rel.destination, &1, rest, changeset.tenant))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp parent_year_id(resource, id, rest, tenant) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load(nested(rest))
    |> Ash.read_one(tenant: tenant, authorize?: false)
    |> case do
      {:ok, %{} = record} ->
        rest |> Enum.reduce(record, &(&2 && Map.get(&2, &1))) |> year_of()

      _ ->
        nil
    end
  end

  defp year_of(%{academic_year_id: id}), do: id
  defp year_of(_record), do: nil

  defp nested([]), do: []
  defp nested([rel]), do: [rel]
  defp nested([rel | rest]), do: [{rel, nested(rest)}]

  defp values(changeset, field) do
    [Ash.Changeset.get_attribute(changeset, field), Map.get(changeset.data, field)]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp closed_error(year_id, tenant) do
    case Ash.get(AcademicYear, year_id, tenant: tenant, authorize?: false) do
      {:ok, %{status: :closed, name: name}} ->
        {:error, field: :academic_year_id, message: message(name)}

      _ ->
        nil
    end
  end
end
```

- [ ] **Step 4: Attach it; the status and `:close`**

In `lib/teacher_assistant/academics/academic_year.ex`:

1. In `attributes do`, after `attribute :active, …`:

```elixir
    attribute :status, TeacherAssistant.Academics.AcademicYearStatus,
      allow_nil?: false,
      default: :open,
      public?: true
```

2. In `actions do`, after `update :activate do … end`:

```elixir
    # Spec KLM9: closed for good — no reopening. Only `NewYear.start/3` calls it, once
    # the next year is active.
    update :close do
      accept []
      change set_attribute(:status, :closed)
      change set_attribute(:active, false)
    end
```

3. In `validations do`, after the `compare` validation:

```elixir
    # Spec KLM9: a closed year is never activated, updated or destroyed.
    validate {TeacherAssistant.Academics.YearOpen, path: []}, on: [:update, :destroy]
```

In `lib/teacher_assistant/academics/term.ex` and `lib/teacher_assistant/academics/class_group.ex`, add to
the resource's `validations do` block (create the block right after `actions do … end` when the resource
has none):

```elixir
    validate {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
```

In `lib/teacher_assistant/organization.ex`, after `activate_academic_year/2`:

```elixir
  @doc "Spec KLM9: closes `year` for good (read only from then on). Called by `NewYear.start/3`."
  def close_academic_year(%Scope{} = scope, %AcademicYear{} = year) do
    year
    |> Ash.Changeset.for_update(:close, %{}, scope: scope)
    |> Ash.update()
  end
```

In `test/support/fixtures/teacher_fixtures.ex`, after `complete_school_setup!/2`:

```elixir
  @doc """
  Spec KLM9: closes `year` as `NewYear.start/3` does — an inactive next year (dates + 1
  year, default calendar, one class « 6ème Z ») is activated first, then `year` closed.
  """
  def close_year!(%Scope{} = scope, %TeacherAssistant.Academics.AcademicYear{} = year) do
    {:ok, next} =
      Organization.create_academic_year(scope, %{
        name: "Après #{year.name}",
        start_date: Date.shift(year.start_date, year: 1),
        end_date: Date.shift(year.end_date, year: 1),
        active: false
      })

    :ok = Organization.build_default_calendar(scope, next)

    {:ok, _} =
      TeacherAssistant.Enrollment.create_class_group(scope, next, %{label: "6ème Z", level: "6ème"})

    {:ok, next} = Organization.activate_academic_year(scope, next)
    {:ok, year} = Organization.get_academic_year(scope, year.id)
    {:ok, closed} = Organization.close_academic_year(scope, year)
    %{closed: closed, next: next}
  end
```

- [ ] **Step 5: Named migration**

```bash
mix ash.codegen klm9_closed_years
```

Expected: one migration adding `status` (text, not null, default `"open"`) to `academic_years`, and a new
snapshot. Read it; nothing else may appear.

- [ ] **Step 6: Run the tests**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/year_open_test.exs \
  test/teacher_assistant/academics/academic_year_test.exs test/teacher_assistant/academics/class_group_test.exs \
  test/teacher_assistant/academics/calendar_test.exs
```

Expected: PASS. If `Exception.message/1` shows the error without the year name, the validation's error
keyword is not reaching the message: keep `message:` a plain string (no `vars`) as written.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/academic_year_status.ex lib/teacher_assistant/academics/year_open.ex \
  lib/teacher_assistant/academics/academic_year.ex lib/teacher_assistant/academics/term.ex \
  lib/teacher_assistant/academics/class_group.ex lib/teacher_assistant/organization.ex \
  test/support/fixtures/teacher_fixtures.ex test/teacher_assistant/academics/year_open_test.exs \
  priv/repo/migrations priv/resource_snapshots
git commit -m "feat: closed school years — status, close action and the YearOpen lock on years, terms, classes"
```

---

### Task 2: The lock on every year-bound resource, and the guard test

**Files:**
- Modify (one validation line each, see table): `sequence.ex`, `enrollment.ex`, `teaching_context.ex`,
  `combined_course.ex`, `subject_exemption.ex`, `assessment.ex`, `mark.ex`, `mark_correction.ex`,
  `entry_reminder.ex`, `attendance_entry.ex`, `sanction_entry.ex`, `conduct_mark.ex`, `class_council.ex`,
  `council_decision.ex`, `bulletin_publication.ex`, `holiday.ex`, `timetable_slot.ex`, `fee_tranche.ex`,
  `fee_adjustment.ex`, `progression_plan.ex`, `progression_module.ex`, `progression_entry.ex`,
  `lesson_plan.ex`, `lesson_step.ex`, `teaching_log_entry.ex` — all under `lib/teacher_assistant/academics/`
- Test: `test/teacher_assistant/academics/year_open_coverage_test.exs`
- Test: `test/teacher_assistant/academics/closed_year_lock_test.exs`

**Interfaces:**
- Consumes: `YearOpen` (path option), `TeacherFixtures.close_year!/2` (Task 1).
- Produces: every create, update and destroy of the year's data refuses a closed year, except `Payment`,
  `MarkEvent` and `MarkCorrection :mark_seen`.

- [ ] **Step 1: Write the failing tests**

`test/teacher_assistant/academics/year_open_coverage_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.YearOpenCoverageTest do
  @moduledoc "Spec KLM9 rule 5: every write on a year's data checks the year."
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.{
    AcademicYear,
    LessonStep,
    Mark,
    MarkCorrection,
    MarkEvent,
    Payment,
    Student,
    TimetableSlot,
    YearOpen
  }

  # Rule 4: payments stay open (arrears); the journal and a read receipt are not year data;
  # a new year is created open.
  @exempt %{
    Payment => :all,
    MarkEvent => :all,
    MarkCorrection => [:mark_seen],
    AcademicYear => [:create, :create_for_workspace]
  }

  test "every create, update and destroy of a year-bound resource checks the year" do
    missing =
      for resource <- year_bound(),
          action <- Ash.Resource.Info.actions(resource),
          action.type in [:create, :update, :destroy],
          not exempt?(resource, action.name),
          not checks_year?(resource, action),
          do: "#{inspect(resource)}.#{action.name}"

    assert missing == []
  end

  test "the discovery finds the year's data and only it" do
    found = year_bound()

    for resource <- [AcademicYear, Mark, LessonStep, TimetableSlot, Payment],
        do: assert(resource in found, "#{inspect(resource)} not found")

    refute Student in found
  end

  # A resource is year-bound when it carries `academic_year_id` or belongs to a
  # year-bound resource (fixed point over `belongs_to`).
  defp year_bound do
    all =
      :teacher_assistant
      |> Application.fetch_env!(:ash_domains)
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)

    seed =
      MapSet.new([
        AcademicYear | Enum.filter(all, &Ash.Resource.Info.attribute(&1, :academic_year_id))
      ])

    all |> grow(seed) |> MapSet.to_list()
  end

  defp grow(all, set) do
    next =
      Enum.reduce(all, set, fn resource, acc ->
        if Enum.any?(
             Ash.Resource.Info.relationships(resource),
             &(&1.type == :belongs_to and MapSet.member?(set, &1.destination))
           ),
           do: MapSet.put(acc, resource),
           else: acc
      end)

    if MapSet.equal?(next, set), do: set, else: grow(all, next)
  end

  defp exempt?(resource, name) do
    case Map.get(@exempt, resource) do
      :all -> true
      names when is_list(names) -> name in names
      nil -> false
    end
  end

  defp checks_year?(resource, action) do
    Enum.any?(
      Ash.Resource.Info.validations(resource),
      &(year_open?(&1) and action.type in &1.on)
    ) or Enum.any?(action.changes, &year_open?/1)
  end

  defp year_open?(%Ash.Resource.Validation{validation: {YearOpen, _opts}}), do: true
  defp year_open?(_other), do: false
end
```

`test/teacher_assistant/academics/closed_year_lock_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.ClosedYearLockTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.{
    Assessment,
    Councils,
    Curriculum,
    Discipline,
    Enrollment,
    Fees,
    MarksFixtures,
    Organization,
    TeacherFixtures
  }

  alias TeacherAssistant.Academics.Student

  setup do
    world = MarksFixtures.marks_world()
    [%{enrollment: e} | _] = Enrollment.list_roster(world.head, world.cg)
    TeacherFixtures.close_year!(world.head, world.year)
    Map.put(world, :enrollment, e)
  end

  defp closed_error?({:error, error}) when is_exception(error),
    do: Exception.message(error) =~ "est clôturée"

  defp closed_error?({:error, error}), do: inspect(error) =~ "clôturée"
  defp closed_error?(_), do: false

  test "marks, assessments and council decisions of a closed year are refused", ctx do
    assert {:error, _} =
             Assessment.upsert_marks(ctx.t, ctx.a, [
               %{student_id: ctx.s1.id, score: Decimal.new(15)}
             ])

    assert closed_error?(Assessment.create_assessment(ctx.t, ctx.tc, ctx.seq, %{label: "Interro 2"}))

    assert closed_error?(
             Councils.set_decision(ctx.head, ctx.cg, {:annual, ctx.year}, ctx.s1.id, %{
               "passage_decision" => "admis"
             })
           )
  end

  test "school life, courses and the calendar of a closed year are refused", ctx do
    assert closed_error?(
             Discipline.add_sanction(ctx.head, ctx.enrollment, %{
               type: :avertissement,
               date: ~D[2025-09-10]
             })
           )

    assert closed_error?(
             Curriculum.assign_teacher(ctx.head, ctx.cg, ctx.head.current_user, %{subject: "SVT"})
           )

    assert closed_error?(
             Organization.create_holiday(ctx.head, ctx.year, %{
               label: "Pont",
               start_date: ~D[2025-12-19],
               end_date: ~D[2025-12-20]
             })
           )
  end

  test "enrolling into a closed year writes nothing at all", ctx do
    students = fn -> Student |> Ash.Query.filter(true) |> Ash.count!(scope: ctx.head) end
    before = students.()

    assert {:error, _} = Enrollment.add_student(ctx.head, ctx.cg, %{full_name: "Zoé", sex: :f})
    assert students.() == before
  end

  test "a payment on a closed year's enrolment is still recorded (arrears)", ctx do
    assert {:ok, _} =
             Fees.record_payment(ctx.head, ctx.enrollment, %{
               amount: 5_000,
               paid_on: ~D[2026-09-10],
               method: :cash
             })
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/year_open_coverage_test.exs test/teacher_assistant/academics/closed_year_lock_test.exs`
Expected: the coverage test FAILS listing every resource action of the table below; the lock tests FAIL
(writes succeed). If the discovery test fails because some school-wide resource is found (a `belongs_to`
to year data you did not expect), stop and read it: either it is year data (add it to the table) or the
relationship is not ownership (add it to `@exempt` with a one-line reason) — ledger the ruling.

- [ ] **Step 3: Attach `YearOpen`**

In each file of the table, add the line to the resource's `validations do` block (create the block right
after `actions do … end` when the resource has none):

```elixir
    validate {TeacherAssistant.Academics.YearOpen, path: PATH}, on: [:create, :update, :destroy]
```

| File (`lib/teacher_assistant/academics/`) | `PATH` |
|---|---|
| `sequence.ex` | `[:term]` |
| `enrollment.ex` | `[]` |
| `teaching_context.ex` | `[]` |
| `combined_course.ex` | `[]` |
| `subject_exemption.ex` | `[:teaching_context]` |
| `assessment.ex` | `[:sequence, :term]` |
| `mark.ex` | `[:assessment, :sequence, :term]` |
| `entry_reminder.ex` | `[:sequence, :term]` |
| `attendance_entry.ex` | `[:enrollment]` |
| `sanction_entry.ex` | `[:enrollment]` |
| `conduct_mark.ex` | `[:enrollment]` |
| `class_council.ex` | `[]` |
| `council_decision.ex` | `[:class_council]` |
| `bulletin_publication.ex` | `[]` |
| `holiday.ex` | `[]` |
| `timetable_slot.ex` | `[:class_group]` |
| `fee_tranche.ex` | `[:class_group]` |
| `fee_adjustment.ex` | `[:enrollment]` |
| `progression_plan.ex` | `[]` |
| `progression_module.ex` | `[:progression_plan]` |
| `progression_entry.ex` | `[:progression_plan]` |
| `lesson_plan.ex` | `[:progression_entry, :progression_plan]` |
| `lesson_step.ex` | `[:lesson_plan, :progression_entry, :progression_plan]` |
| `teaching_log_entry.ex` | `[:progression_entry, :progression_plan]` |

`mark_correction.ex` is the exception: `:mark_seen` stays open, so add the check **inside** each of the
`:request`, `:approve` and `:refuse` actions instead (first line of each action body):

```elixir
      validate {TeacherAssistant.Academics.YearOpen, path: [:assessment, :sequence, :term]}
```

(Before writing each line, confirm the relationship names in that file's `relationships do` block; a name
that differs is a plan typo — use the real one and ledger it.)

- [ ] **Step 4: Run the two tests and the domain suite**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/year_open_coverage_test.exs \
  test/teacher_assistant/academics/closed_year_lock_test.exs
MIX_TEST_PARTITION=9 mix test test/teacher_assistant
```

Expected: PASS everywhere (no open-year behaviour changes). If an existing test fails with « cannot be
done atomically », that action builds its record without loading it: read the failure and add
`require_atomic? false` to that one action (ledger it), never weaken `YearOpen`.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics test/teacher_assistant/academics/year_open_coverage_test.exs \
  test/teacher_assistant/academics/closed_year_lock_test.exs
git commit -m "feat: a closed year's data is read only everywhere, payments excepted; guard test"
```

---

### Task 3: *Paramètres → Année* without free create and activate

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex`
- Modify: `test/teacher_assistant_web/live/school/settings_live_test.exs`

**Interfaces:**
- Produces: `#years-table` rows `#year-row-<id>` with status « Active » / « Inactive » / « Clôturée »; an
  empty actions cell that Tasks 6 and 7 fill. No `#year-form`, no `#year-activate-*`.

- [ ] **Step 1: Rewrite the tests**

In `test/teacher_assistant_web/live/school/settings_live_test.exs`:
- delete the tests « head creates and activates an academic year », « creating a year from settings builds
  its calendar », « activating a year deactivates the previous one », « a plain teacher member cannot create
  years (forged event) » and « additional academic years created via form are inactive; only first is
  active »;
- in « a vice_principal member sees the Settings nav link and can manage years », rename it « a
  vice_principal member sees the Settings nav link and the years » and replace everything after
  `{:ok, view, _html} = live(conn, ~p"/school/settings")` with
  `assert has_element?(view, "#years-table")`;
- add:

```elixir
  test "years are listed with their status; none is created or activated here",
       %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    %{closed: closed, next: next} = TeacherAssistant.TeacherFixtures.close_year!(scope, year)

    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#year-row-#{next.id}", "Active")
    assert has_element?(view, "#year-row-#{closed.id}", "Clôturée")
    refute has_element?(view, "#year-form")
    refute has_element?(view, "[id^=year-activate-]")
  end
```

- [ ] **Step 2: Run to verify the new test fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/settings_live_test.exs`
Expected: the new test FAILS (`#year-form` present, no « Clôturée »).

- [ ] **Step 3: Implement**

In `lib/teacher_assistant_web/live/school/settings_live.ex`:
1. Delete the whole `<div class="ta-leaf space-y-3">` holding « Create an academic year » and `#year-form`.
2. Replace the status `<td>` and the actions `<td>` of each `#year-row-…` with:

```heex
                  <td>
                    <span :if={year.status == :closed} class="badge badge-ghost">
                      {gettext("Clôturée")}
                    </span>
                    <span :if={year.status == :open and year.active} class="badge badge-primary">
                      {gettext("Active")}
                    </span>
                    <span :if={year.status == :open and !year.active} class="badge badge-ghost">
                      {gettext("Inactive")}
                    </span>
                  </td>
                  <td class="text-right"></td>
```

3. Delete the `handle_event` clauses `"validate_year"`, `"create_year"` and `"activate_year"`, the private
   `year_form/2`, the `:year_form` assign in `mount/3` and the comment above it that explains its ordering.
   Remove any alias left unused (`mix compile --warnings-as-errors` tells you).

- [ ] **Step 4: Run the tests**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/settings_live_test.exs \
  test/teacher_assistant_web/live/role_spaces_test.exs test/teacher_assistant_web/live/onboarding
mix compile --warnings-as-errors
```

Expected: PASS; no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/settings_live_test.exs
git commit -m "feat: years listed with their status; a year is no longer created or activated by hand"
```

---

## 9b — Starting the next year

### Task 4: `NewYearPlan` — targets, placements, sizes, totals (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/new_year_plan.ex`
- Test: `test/teacher_assistant/academics/new_year_plan_test.exs`

**Interfaces:**
- Produces (all pure; classes are maps with `:id, :label, :level, :serie`):
  - `NewYearPlan.suffix(class) :: String.t() | nil`
  - `NewYearPlan.default_targets([class]) :: %{class_id => class_id | nil}`
  - `NewYearPlan.next_name(String.t()) :: String.t()` (« 2025-2026 » → « 2026-2027 », else `""`)
  - `NewYearPlan.placements([student], targets) :: [student merged with %{to: class_id | nil, repeater?: boolean, reason: nil | :exclu | :sans_decision | :sans_classe}]`
    where a student is `%{student_id, enrollment_id, class_id, decision}` (`decision` atom or nil)
  - `NewYearPlan.sizes(placements) :: %{class_id => non_neg_integer}`
  - `NewYearPlan.totals(placements) :: %{reenrolled: n, repeaters: n, not_reenrolled: %{reason => n}}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.NewYearPlanTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.NewYearPlan

  defp cls(id, label, level, serie \\ nil),
    do: %{id: id, label: label, level: level, serie: serie}

  test "the suffix is the label's last word when it is letters or a number" do
    assert NewYearPlan.suffix(cls("a", "6ème A", "6ème")) == "A"
    assert NewYearPlan.suffix(cls("a", "3e 2", "3ème")) == "2"
    assert NewYearPlan.suffix(cls("a", "6ème", "6ème")) == nil
    assert NewYearPlan.suffix(cls("a", "2nde C", "2nde", "C")) == nil
    assert NewYearPlan.suffix(cls("a", "2nde C B", "2nde", "C")) == "B"
  end

  test "the admis target is the next level's class with the same suffix and série" do
    classes = [
      cls("6a", "6ème A", "6ème"),
      cls("6b", "6ème B", "6ème"),
      cls("5a", "5ème A", "5ème"),
      cls("3", "3ème", "3ème"),
      cls("2c", "2nde C", "2nde", "C"),
      cls("1c", "1ère C", "1ère", "C"),
      cls("tc", "Terminale C", "Terminale", "C")
    ]

    targets = NewYearPlan.default_targets(classes)
    assert targets["6a"] == "5a"
    # No « 5ème B »: the admin chooses.
    assert targets["6b"] == nil
    # 3ème has no série, every 2nde has one.
    assert targets["3"] == nil
    assert targets["2c"] == "1c"
    # Last level.
    assert targets["tc"] == nil
  end

  test "levels the school does not have are skipped to the next one it has" do
    classes = [cls("3", "3ème A", "3ème"), cls("2", "2nde A", "2nde")]
    assert NewYearPlan.default_targets(classes)["3"] == "2"
  end

  test "the next year's name follows the old one" do
    assert NewYearPlan.next_name("2025-2026") == "2026-2027"
    assert NewYearPlan.next_name(" 2025 / 2026 ") == "2026-2027"
    assert NewYearPlan.next_name("Année de référence") == ""
  end

  test "each decision places the student, and the totals count them" do
    students = [
      %{student_id: "awa", enrollment_id: "e1", class_id: "6a", decision: :admis},
      %{student_id: "bob", enrollment_id: "e2", class_id: "6a", decision: :redouble},
      %{student_id: "cy", enrollment_id: "e3", class_id: "6a", decision: :admis_rachat},
      %{student_id: "dan", enrollment_id: "e4", class_id: "6a", decision: :exclu},
      %{student_id: "eve", enrollment_id: "e5", class_id: "6a", decision: nil},
      %{student_id: "fay", enrollment_id: "e6", class_id: "tc", decision: :admis}
    ]

    placed = NewYearPlan.placements(students, %{"6a" => "5a", "tc" => nil})
    by = Map.new(placed, &{&1.student_id, &1})

    assert %{to: "5a", repeater?: false, reason: nil} = by["awa"]
    assert %{to: "6a", repeater?: true} = by["bob"]
    assert %{to: "5a"} = by["cy"]
    assert %{to: nil, reason: :exclu} = by["dan"]
    assert %{to: nil, reason: :sans_decision} = by["eve"]
    assert %{to: nil, reason: :sans_classe} = by["fay"]

    assert NewYearPlan.sizes(placed) == %{"5a" => 2, "6a" => 1}

    assert NewYearPlan.totals(placed) == %{
             reenrolled: 3,
             repeaters: 1,
             not_reenrolled: %{exclu: 1, sans_decision: 1, sans_classe: 1}
           }
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/new_year_plan_test.exs`
Expected: FAIL — `NewYearPlan` undefined.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/academics/new_year_plan.ex`:

```elixir
defmodule TeacherAssistant.Academics.NewYearPlan do
  @moduledoc """
  Spec KLM9 (rules 7–8), pure: from the open year's classes and each student's decision,
  every class's default admis target, where each student goes, how big each new class
  would be, and the wizard's totals. Ids are the open year's: a target names the class
  whose copy receives the admis.
  """
  alias TeacherAssistant.Academics.SchoolTemplates

  @doc "The label's last word when it is letters or a number and not the level's or série's own text."
  def suffix(%{label: label, level: level, serie: serie}) do
    case String.split(label) do
      [_, _ | _] = words ->
        last = List.last(words)

        if last != level and last != serie and Regex.match?(~r/^([A-Za-z]{1,3}|\d{1,3})$/, last),
          do: last

      _ ->
        nil
    end
  end

  @doc "Each class's admis target: the next level's class (of those the school has) with the same série and suffix."
  def default_targets(classes) do
    ranks = SchoolTemplates.level_order() |> Enum.with_index() |> Map.new()

    present =
      classes
      |> Enum.map(& &1.level)
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(ranks, &1))
      |> Enum.sort_by(&Map.fetch!(ranks, &1))

    Map.new(classes, fn c -> {c.id, target(c, classes, next_level(c.level, present))} end)
  end

  defp next_level(level, present) do
    case Enum.drop_while(present, &(&1 != level)) do
      [_level, next | _] -> next
      _ -> nil
    end
  end

  defp target(_class, _classes, nil), do: nil

  defp target(class, classes, next) do
    suffix = suffix(class)

    case Enum.find(classes, &(&1.level == next and &1.serie == class.serie and suffix(&1) == suffix)) do
      nil -> nil
      found -> found.id
    end
  end

  @doc "« 2025-2026 » → « 2026-2027 »; another form of name → \"\" (the admin types it)."
  def next_name(name) do
    case Regex.run(~r/^(\d{4})\s*[-\/]\s*(\d{4})$/, String.trim(name)) do
      [_, first, last] -> "#{String.to_integer(first) + 1}-#{String.to_integer(last) + 1}"
      _ -> ""
    end
  end

  @doc "Where each student goes, given the classes' targets (class id → class id or nil)."
  def placements(students, targets),
    do: Enum.map(students, &Map.merge(&1, place(&1, targets)))

  defp place(%{decision: decision, class_id: id}, targets) when decision in [:admis, :admis_rachat] do
    case Map.get(targets, id) do
      nil -> %{to: nil, repeater?: false, reason: :sans_classe}
      to -> %{to: to, repeater?: false, reason: nil}
    end
  end

  defp place(%{decision: :redouble, class_id: id}, _targets),
    do: %{to: id, repeater?: true, reason: nil}

  defp place(%{decision: :exclu}, _targets), do: %{to: nil, repeater?: false, reason: :exclu}
  defp place(_student, _targets), do: %{to: nil, repeater?: false, reason: :sans_decision}

  @doc "The projected size of each receiving class (by the open year's class id)."
  def sizes(placements),
    do: placements |> Enum.filter(& &1.to) |> Enum.frequencies_by(& &1.to)

  def totals(placements) do
    placed = Enum.filter(placements, & &1.to)

    %{
      reenrolled: length(placed),
      repeaters: Enum.count(placed, & &1.repeater?),
      not_reenrolled: placements |> Enum.reject(& &1.to) |> Enum.frequencies_by(& &1.reason)
    }
  end
end
```

- [ ] **Step 4: Run the test**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant/academics/new_year_plan_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/new_year_plan.ex \
  test/teacher_assistant/academics/new_year_plan_test.exs
git commit -m "feat: next-year plan — admis targets, placements, projected sizes"
```

---

### Task 5: `NewYear` — reading the plan, starting the year in one transaction

**Files:**
- Create: `lib/teacher_assistant/new_year.ex`
- Test: `test/teacher_assistant/new_year_test.exs`

**Interfaces:**
- Consumes: `NewYearPlan` (Task 4), `Organization.close_academic_year/2` (Task 1), existing
  `Councils.council/3`, `Councils.outcomes/3`, `Councils.passage_inputs/3`, `Councils.for_period/2`,
  `Assessment.class_results_for_period/3`, `Assessment.passage_rules/1`, `Enrollment.list_roster/2`,
  `Enrollment.create_class_group/3`, `Enrollment.set_form_master/3`, `Curriculum.combine_course/2`,
  `Accounts.list_members/1`, `Organization.create_academic_year/2`, `build_default_calendar/2`,
  `activate_academic_year/2`.
- Produces:
  - `NewYear.plan(%Scope{}, %AcademicYear{}) :: %{year, classes: [%ClassGroup{}], students: [%{student_id, enrollment_id, class_id, name, decision, source: :council | :proposal | nil}], default_targets, checks: %{open_councils: [%ClassGroup{}], proposals: %{class_id => n}, departed_courses: n, before_end?: boolean}, courses, members}`
  - `NewYear.decisions(scope, cg, year) :: %{student_id => {decision, :council | :proposal}}`
  - `NewYear.start(%Scope{}, %AcademicYear{}, %{name, start_date, end_date, labels: %{class_id => String.t()}, targets: %{class_id => class_id | nil}}) :: {:ok, %AcademicYear{}} | {:error, :forbidden} | {:error, :already_closed} | {:error, term}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.NewYearTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Councils, Curriculum, Enrollment, NewYear, Organization, TeacherFixtures}

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, a6} = Enrollment.create_class_group(head, year, %{label: "6ème A", level: "6ème"})
    {:ok, a5} = Enrollment.create_class_group(head, year, %{label: "5ème A", level: "5ème"})

    {:ok, tc} =
      Enrollment.create_class_group(head, year, %{
        label: "Terminale C",
        level: "Terminale",
        serie: "C"
      })

    teacher = TeacherFixtures.member_scope_fixture(head)
    {:ok, _} = Enrollment.set_form_master(head, a6, teacher.current_user.id)

    {:ok, maths6} =
      Curriculum.assign_teacher(head, a6, teacher.current_user, %{
        subject: "Maths",
        weekly_hours: 5,
        coefficient: Decimal.new(4)
      })

    {:ok, maths5} = Curriculum.assign_teacher(head, a5, teacher.current_user, %{subject: "Maths"})
    {:ok, _} = Curriculum.combine_course(head, [maths6, maths5])

    {:ok, awa} = Enrollment.add_student(head, a6, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(head, a6, %{full_name: "Bob", sex: :m})
    {:ok, _carl} = Enrollment.add_student(head, a6, %{full_name: "Carl", sex: :m})
    {:ok, dina} = Enrollment.add_student(head, tc, %{full_name: "Dina", sex: :f})

    for {cg, s, d} <- [{a6, awa, "admis"}, {a6, bob, "redouble"}, {tc, dina, "admis"}] do
      {:ok, _} =
        Councils.set_decision(head, cg, {:annual, year}, s.id, %{"passage_decision" => d})
    end

    %{head: head, year: year, a6: a6, a5: a5, tc: tc, teacher: teacher, awa: awa}
  end

  defp attrs(extra \\ %{}) do
    Map.merge(
      %{name: "2026-2027", start_date: ~D[2026-09-07], end_date: ~D[2027-07-30]},
      extra
    )
  end

  defp roster(scope, cg),
    do: scope |> Enrollment.list_roster(cg) |> Map.new(&{&1.student.full_name, &1.enrollment})

  test "the plan proposes targets, reads decisions and lists what to check", ctx do
    plan = NewYear.plan(ctx.head, ctx.year)

    assert plan.default_targets[ctx.a6.id] == ctx.a5.id
    assert plan.default_targets[ctx.tc.id] == nil

    by = Map.new(plan.students, &{&1.name, &1})
    assert %{decision: :admis, source: :council} = by["Awa"]
    assert %{decision: :redouble} = by["Bob"]
    # No decision and no marks, so no proposal either.
    assert %{decision: nil, source: nil} = by["Carl"]

    assert ctx.a6.id in Enum.map(plan.checks.open_councils, & &1.id)
    assert plan.checks.departed_courses == 0
    # The test clock (2025-09-15) is before the year's end.
    assert plan.checks.before_end?
  end

  test "starting the next year carries classes, courses and students over, then closes the old one",
       ctx do
    assert {:ok, new} =
             NewYear.start(ctx.head, ctx.year, attrs(%{labels: %{ctx.a5.id => "5ème A bis"}}))

    {:ok, old} = Organization.get_academic_year(ctx.head, ctx.year.id)
    assert old.status == :closed
    refute old.active
    assert Organization.current_academic_year(ctx.head).id == new.id
    assert length(Organization.list_sequences(ctx.head, new)) == 6

    classes = Map.new(Enrollment.list_class_groups(ctx.head, new), &{&1.label, &1})
    a6n = classes["6ème A"]
    a5n = classes["5ème A bis"]
    tcn = classes["Terminale C"]
    assert a6n.form_master_user_id == ctx.teacher.current_user.id

    [maths] = Curriculum.list_assignments_for_class(ctx.head, a6n)
    assert maths.weekly_hours == 5
    assert Decimal.equal?(maths.coefficient, 4)
    assert maths.teacher_user_id == ctx.teacher.current_user.id
    assert maths.combined_course_id

    assert %{"Awa" => %{status: :reinscription, repeater: false}} = roster(ctx.head, a5n)
    assert %{"Bob" => %{status: :reinscription, repeater: true}} = r6 = roster(ctx.head, a6n)
    refute Map.has_key?(r6, "Carl")
    # Last level: Dina admis has no class to go to.
    assert roster(ctx.head, tcn) == %{}
  end

  test "a failure keeps nothing; a second start is refused", ctx do
    years = length(Organization.list_academic_years(ctx.head))

    # Two classes with the same label: the copy fails, everything is rolled back.
    assert {:error, _} =
             NewYear.start(ctx.head, ctx.year, attrs(%{labels: %{ctx.a5.id => "6ème A"}}))

    assert length(Organization.list_academic_years(ctx.head)) == years
    assert {:ok, %{status: :open, active: true}} = Organization.get_academic_year(ctx.head, ctx.year.id)

    assert {:ok, _} = NewYear.start(ctx.head, ctx.year, attrs())

    assert {:error, :already_closed} =
             NewYear.start(ctx.head, ctx.year, attrs(%{name: "2027-2028"}))
  end

  test "a forged target is ignored: the student is simply not re-enrolled", ctx do
    assert {:ok, new} =
             NewYear.start(
               ctx.head,
               ctx.year,
               attrs(%{targets: %{ctx.a6.id => Ecto.UUID.generate(), "garbage" => ctx.a5.id}})
             )

    a5n = Enum.find(Enrollment.list_class_groups(ctx.head, new), &(&1.label == "5ème A"))
    refute Map.has_key?(roster(ctx.head, a5n), "Awa")
  end

  test "a teacher cannot start the next year", ctx do
    assert {:error, :forbidden} = NewYear.start(ctx.teacher, ctx.year, attrs())
    assert {:ok, %{status: :open}} = Organization.get_academic_year(ctx.head, ctx.year.id)
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant/new_year_test.exs`
Expected: FAIL — `TeacherAssistant.NewYear` undefined.

- [ ] **Step 3: Implement**

`lib/teacher_assistant/new_year.ex`:

```elixir
defmodule TeacherAssistant.NewYear do
  @moduledoc """
  Spec KLM9 (rules 7–11): preparing and starting the next school year. `plan/2` reads
  what the wizard shows; `start/3` builds the new year from it in one transaction —
  calendar, classes, courses, combined courses, form masters, re-enrolments — then
  activates it and closes the old one. Authorization is each write's own policy (admin).
  """
  require Ash.Query

  alias TeacherAssistant.{
    Accounts,
    Assessment,
    Councils,
    Curriculum,
    Enrollment,
    Organization,
    Scope
  }

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ClassGroup,
    CombinedCourse,
    NewYearPlan,
    Reference,
    TeachingContext
  }

  # The resource, not the domain `TeacherAssistant.Enrollment` aliased above.
  alias TeacherAssistant.Academics.Enrollment, as: EnrollmentRecord

  @doc "What the wizard shows for the open `year` (see the moduledoc of `NewYearPlan`)."
  def plan(%Scope{} = scope, %AcademicYear{} = year) do
    classes = Enrollment.list_class_groups(scope, year)

    courses =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id and not is_nil(class_group_id))
      |> Ash.read!(scope: scope)

    members = scope |> Accounts.list_members() |> MapSet.new(& &1.user_id)
    councils = Councils.for_period(scope, {:annual, year})
    students = Enum.flat_map(classes, &class_students(scope, &1, year))

    %{
      year: year,
      classes: classes,
      courses: courses,
      members: members,
      students: students,
      default_targets: NewYearPlan.default_targets(classes),
      checks: %{
        open_councils: Enum.reject(classes, &match?(%{status: :held}, councils[&1.id])),
        proposals:
          students |> Enum.filter(&(&1.source == :proposal)) |> Enum.frequencies_by(& &1.class_id),
        departed_courses: Enum.count(courses, &(not MapSet.member?(members, &1.teacher_user_id))),
        before_end?: Date.compare(Reference.today(), year.end_date) == :lt
      }
    }
  end

  @doc "Each student's decision for the year: the annual council's choice, else the engine's proposal."
  def decisions(%Scope{} = scope, %ClassGroup{} = cg, %AcademicYear{} = year) do
    period = {:annual, year}
    council = Councils.council(scope, cg, period)

    passage = %{
      rules: Assessment.passage_rules(scope),
      students: Councils.passage_inputs(scope, cg, period)
    }

    proposed =
      for {student_id, %{proposal: proposal}} when not is_nil(proposal) <-
            Councils.outcomes(council, Assessment.class_results_for_period(scope, cg, period), passage),
          into: %{},
          do: {student_id, {proposal, :proposal}}

    chosen =
      for %{passage_decision: decision, student_id: student_id} when not is_nil(decision) <-
            council.decisions || [],
          into: %{},
          do: {student_id, {decision, :council}}

    Map.merge(proposed, chosen)
  end

  defp class_students(scope, cg, year) do
    decisions = decisions(scope, cg, year)

    for %{student: student, enrollment: enrollment} <- Enrollment.list_roster(scope, cg) do
      {decision, source} = Map.get(decisions, student.id, {nil, nil})

      %{
        student_id: student.id,
        enrollment_id: enrollment.id,
        class_id: cg.id,
        name: student.full_name,
        decision: decision,
        source: source
      }
    end
  end

  @doc """
  Starts the next year from the open `year` (rules 9–10), in one transaction. A class
  missing from `labels` keeps its label; `targets` override the default targets, and a
  target that is not one of the year's classes counts as « Ne pas réinscrire ».
  """
  def start(%Scope{} = scope, %AcademicYear{id: year_id}, attrs) do
    # Checked first: the plan's reads (discipline, attendance) are not all open to
    # every member, and a refused read must not surface as a crash.
    if Organization.can_manage_calendar?(scope),
      do: transact_start(scope, year_id, attrs),
      else: {:error, :forbidden}
  end

  defp transact_start(scope, year_id, attrs) do
    Ash.transact([AcademicYear, ClassGroup, TeachingContext, CombinedCourse, EnrollmentRecord], fn ->
      with {:ok, year} <- lock_open(scope, year_id),
           plan = plan(scope, year),
           targets = targets(plan, Map.get(attrs, :targets, %{})),
           {:ok, new} <- create_year(scope, attrs),
           :ok <- Organization.build_default_calendar(scope, new),
           {:ok, copies} <- copy_classes(scope, plan, new, Map.get(attrs, :labels, %{})),
           :ok <- copy_courses(scope, plan.courses, copies),
           :ok <- enroll(scope, plan, targets, copies, new),
           {:ok, new} <- Organization.activate_academic_year(scope, new),
           {:ok, _closed} <- Organization.close_academic_year(scope, year) do
        {:ok, new}
      end
    end)
    |> case do
      {:ok, {:ok, new}} -> {:ok, new}
      {:error, error} -> {:error, error}
    end
  end

  # Read under a row lock: a concurrent start waits, then finds the year closed.
  defp lock_open(scope, id) do
    AcademicYear
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %AcademicYear{status: :open} = year} -> {:ok, year}
      {:ok, %AcademicYear{}} -> {:error, :already_closed}
      _ -> {:error, :not_found}
    end
  end

  defp targets(plan, overrides) do
    ids = MapSet.new(plan.classes, & &1.id)

    for {class_id, target} <- overrides, MapSet.member?(ids, class_id), into: plan.default_targets do
      {class_id, if(MapSet.member?(ids, target), do: target)}
    end
  end

  defp create_year(scope, attrs) do
    Organization.create_academic_year(scope, %{
      name: attrs.name,
      start_date: attrs.start_date,
      end_date: attrs.end_date,
      active: false
    })
  end

  defp copy_classes(scope, plan, new, labels) do
    Enum.reduce_while(plan.classes, {:ok, %{}}, fn cg, {:ok, acc} ->
      label = labels |> Map.get(cg.id, cg.label) |> String.trim()

      with {:ok, copy} <-
             Enrollment.create_class_group(scope, new, %{
               label: label,
               level: cg.level,
               serie: cg.serie,
               subsystem: cg.subsystem
             }),
           {:ok, copy} <- form_master(scope, copy, cg.form_master_user_id, plan.members) do
        {:cont, {:ok, Map.put(acc, cg.id, copy)}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # A form master who left the school is not carried over.
  defp form_master(scope, copy, user_id, members) do
    if user_id && MapSet.member?(members, user_id),
      do: Enrollment.set_form_master(scope, copy, user_id),
      else: {:ok, copy}
  end

  defp copy_courses(scope, courses, copies) do
    with {:ok, new_by_old} <- create_courses(scope, courses, copies) do
      courses
      |> Enum.filter(& &1.combined_course_id)
      |> Enum.group_by(& &1.combined_course_id, &Map.fetch!(new_by_old, &1.id))
      |> Enum.reduce_while(:ok, fn {_old_course, members}, :ok ->
        case Curriculum.combine_course(scope, members) do
          {:ok, _course} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  # Copied as is — a departed teacher's course too (rule 10) — hence the plain create
  # rather than `Curriculum.assign_teacher/4`, which wants an active member.
  defp create_courses(scope, courses, copies) do
    Enum.reduce_while(courses, {:ok, %{}}, fn tc, {:ok, acc} ->
      copy = Map.fetch!(copies, tc.class_group_id)

      TeachingContext
      |> Ash.Changeset.for_create(
        :create,
        %{
          subject: tc.subject,
          subject_id: tc.subject_id,
          level: copy.level,
          serie: copy.serie,
          subsystem: copy.subsystem,
          weekly_hours: tc.weekly_hours,
          coefficient: tc.coefficient,
          teacher_user_id: tc.teacher_user_id,
          class_group_id: copy.id,
          academic_year_id: copy.academic_year_id
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, new_tc} -> {:cont, {:ok, Map.put(acc, tc.id, new_tc)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp enroll(scope, plan, targets, copies, new) do
    plan.students
    |> NewYearPlan.placements(targets)
    |> Enum.filter(& &1.to)
    |> Enum.reduce_while(:ok, fn placed, :ok ->
      EnrollmentRecord
      |> Ash.Changeset.for_create(
        :create,
        %{
          student_id: placed.student_id,
          class_group_id: Map.fetch!(copies, placed.to).id,
          academic_year_id: new.id,
          status: :reinscription,
          repeater: placed.repeater?
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, _enrollment} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
```

- [ ] **Step 4: Run the tests**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant/new_year_test.exs
```

Expected: PASS. If the duplicate-label test passes `{:ok, _}`, `ClassGroup`'s label identity is not
per year as assumed: read `class_group.ex` identities and use whatever makes the copy fail (e.g. a blank
label `" "`), ledger it.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/new_year.ex test/teacher_assistant/new_year_test.exs
git commit -m "feat: start the next year — classes, courses and students carried over, old year closed"
```

---

### Task 6: « Préparer l'année suivante » — the wizard

**Files:**
- Create: `lib/teacher_assistant_web/live/school/new_year_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (route in `:school_workspace`)
- Modify: `lib/teacher_assistant_web/live/school/settings_live.ex` (link in the active year's actions cell)
- Test: `test/teacher_assistant_web/live/school/new_year_live_test.exs`

**Interfaces:**
- Consumes: `NewYear.plan/2`, `NewYear.start/3` (Task 5); `NewYearPlan.next_name/1`, `placements/2`,
  `sizes/1`, `totals/1` (Task 4).
- Produces: route `/school/settings/new-year`; DOM ids `#new-year`, `#step-checks`, `#check-before-end`,
  `#check-councils`, `#check-proposals`, `#check-departed`, `#to-step-2`, `#new-year-form`, `#year-error`,
  `#classes-form`, `#class-row-<id>`, `#class-size-<id>`, `#classes-error`, `#step-summary`,
  `#summary-reenrolled`, `#summary-repeaters`, `#summary-not`, `#start-year`, settings `#new-year-link`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.School.NewYearLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Councils, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, a6} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, a5} = Enrollment.create_class_group(scope, year, %{label: "5ème A", level: "5ème"})
    {:ok, awa} = Enrollment.add_student(scope, a6, %{full_name: "Awa", sex: :f})
    {:ok, bob} = Enrollment.add_student(scope, a6, %{full_name: "Bob", sex: :m})

    for {s, d} <- [{awa, "admis"}, {bob, "redouble"}] do
      {:ok, _} = Councils.set_decision(scope, a6, {:annual, year}, s.id, %{"passage_decision" => d})
    end

    %{a6: a6, a5: a5}
  end

  test "a teacher is sent back to /school", %{scope: scope, workspace: school} do
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/settings/new-year")
  end

  test "settings links to the wizard for the open year", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, ~s|#new-year-link[href="/school/settings/new-year"]|)
  end

  test "four steps from checks to the new year", %{conn: conn, scope: scope} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")

    assert has_element?(view, "#step-checks")
    assert has_element?(view, "#check-councils", "6ème A")
    assert has_element?(view, "#check-before-end")

    view |> element("#to-step-2") |> render_click()
    # Default dates: the old ones + 1 year.
    assert view |> element("#new-year-form") |> render() =~ "2026-09-08"

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    assert has_element?(view, "#class-row-#{ctx.a6.id}")
    # Awa is admis into the copy of 5ème A, Bob repeats 6ème A.
    assert has_element?(view, "#class-size-#{ctx.a5.id}", "1")
    assert has_element?(view, "#class-size-#{ctx.a6.id}", "1")

    view |> form("#classes-form", %{"targets" => %{ctx.a6.id => ""}}) |> render_change()
    assert has_element?(view, "#class-size-#{ctx.a5.id}", "0")

    view |> form("#classes-form") |> render_submit()
    assert has_element?(view, "#summary-reenrolled", "1")
    assert has_element?(view, "#summary-repeaters", "1")
    assert has_element?(view, "#summary-not", "1")

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             view |> element("#start-year") |> render_click()

    assert Organization.current_academic_year(scope).name == "2026-2027"
  end

  test "blank or duplicate labels are refused at step 3", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")
    view |> element("#to-step-2") |> render_click()

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    view |> form("#classes-form", %{"labels" => %{ctx.a5.id => "6ème A"}}) |> render_submit()
    assert has_element?(view, "#classes-error")
    refute has_element?(view, "#step-summary")

    view |> form("#classes-form", %{"labels" => %{ctx.a5.id => "  "}}) |> render_submit()
    assert has_element?(view, "#classes-error")
  end

  test "an end before the start, or a name already used, stays on step 2", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/new-year")
    view |> element("#to-step-2") |> render_click()

    view
    |> form("#new-year-form",
      year: %{name: "2026-2027", start_date: "2026-09-07", end_date: "2026-01-01"}
    )
    |> render_submit()

    assert has_element?(view, "#year-error")

    view
    |> form("#new-year-form",
      year: %{name: "Année de référence", start_date: "2026-09-07", end_date: "2027-07-30"}
    )
    |> render_submit()

    assert has_element?(view, "#year-error")
    refute has_element?(view, "#classes-form")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/new_year_live_test.exs`
Expected: FAIL — no route.

- [ ] **Step 3: Route and settings link**

Router, in `:school_workspace`, after `live "/school/settings/school-life", …`:

```elixir
      live "/school/settings/new-year", School.NewYearLive, :index
```

`settings_live.ex`, the actions cell from Task 3 becomes:

```heex
                  <td class="text-right">
                    <.link
                      :if={year.status == :open and year.active}
                      id="new-year-link"
                      navigate={~p"/school/settings/new-year"}
                      class="btn btn-primary btn-xs"
                    >
                      {gettext("Préparer l'année suivante")}
                    </.link>
                  </td>
```

- [ ] **Step 4: The LiveView**

`lib/teacher_assistant_web/live/school/new_year_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.NewYearLive do
  @moduledoc """
  Spec KLM9 (rule 11): « Préparer l'année suivante », four steps — checks, the new year,
  the classes (label, admis target, projected size), the confirmation — then
  `NewYear.start/3`. The plan lives in the LiveView; nothing is saved before the start.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, NewYear, Organization}
  alias TeacherAssistant.Academics.NewYearPlan
  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    cond do
      not Organization.can_manage_calendar?(scope) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           gettext("La préparation de l'année est réservée au Proviseur et au Censeur.")
         )
         |> push_navigate(to: ~p"/school")}

      year == nil or year.status == :closed ->
        {:ok, push_navigate(socket, to: ~p"/school/settings")}

      true ->
        plan = NewYear.plan(scope, year)

        max =
          case Accounts.fetch_school_profile(scope) do
            {:ok, profile} -> profile.max_class_size
            _ -> nil
          end

        {:ok,
         socket
         |> assign(
           year: year,
           plan: plan,
           max: max,
           step: 1,
           taken_names: scope |> Organization.list_academic_years() |> MapSet.new(& &1.name),
           year_params: %{
             "name" => NewYearPlan.next_name(year.name),
             "start_date" => year.start_date |> Date.shift(year: 1) |> Date.to_iso8601(),
             "end_date" => year.end_date |> Date.shift(year: 1) |> Date.to_iso8601()
           },
           year_attrs: nil,
           year_error: nil,
           labels: Map.new(plan.classes, &{&1.id, &1.label}),
           targets: plan.default_targets,
           classes_error: nil
         )
         |> derive()}
    end
  end

  def handle_event("checked", _params, %{assigns: %{step: 1}} = socket),
    do: {:noreply, assign(socket, step: 2)}

  # Back to an earlier step only.
  def handle_event("back", %{"step" => step}, socket) do
    case Integer.parse(step) do
      {n, ""} when n >= 1 and n < socket.assigns.step -> {:noreply, assign(socket, step: n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_year", %{"year" => params}, %{assigns: %{step: 2}} = socket) do
    case parse_year(params, socket.assigns.taken_names) do
      {:ok, attrs} ->
        {:noreply,
         socket
         |> assign(year_params: params, year_attrs: attrs, year_error: nil, step: 3)
         |> derive()}

      {:error, message} ->
        {:noreply, socket |> assign(year_params: params, year_error: message) |> derive()}
    end
  end

  def handle_event("change_classes", params, %{assigns: %{step: 3}} = socket),
    do: {:noreply, socket |> put_classes(params) |> derive()}

  def handle_event("save_classes", params, %{assigns: %{step: 3}} = socket) do
    socket = put_classes(socket, params)

    case labels_error(socket.assigns.labels) do
      nil -> {:noreply, socket |> assign(classes_error: nil, step: 4) |> derive()}
      message -> {:noreply, socket |> assign(classes_error: message) |> derive()}
    end
  end

  def handle_event("start", _params, %{assigns: %{step: 4}} = socket) do
    %{current_scope: scope, year: year, year_attrs: attrs, labels: labels, targets: targets} =
      socket.assigns

    case NewYear.start(scope, year, Map.merge(attrs, %{labels: labels, targets: targets})) do
      {:ok, new} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("L'année %{name} a démarré.", name: new.name))
         |> push_navigate(to: ~p"/school/classes")}

      {:error, :already_closed} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("L'année %{name} est déjà clôturée.", name: year.name))
         |> push_navigate(to: ~p"/school/settings")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("L'année suivante n'a pas pu démarrer ; rien n'a été modifié.")
         )}
    end
  end

  # Events of another step (a stale or forged click) do nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp parse_year(params, taken) do
    name = params |> Map.get("name", "") |> String.trim()

    with {:name, false} <- {:name, name == ""},
         {:taken, false} <- {:taken, MapSet.member?(taken, name)},
         {:ok, start} <- Date.from_iso8601(Map.get(params, "start_date", "")),
         {:ok, finish} <- Date.from_iso8601(Map.get(params, "end_date", "")),
         :gt <- Date.compare(finish, start) do
      {:ok, %{name: name, start_date: start, end_date: finish}}
    else
      {:name, true} -> {:error, gettext("Donnez un nom à la nouvelle année.")}
      {:taken, true} -> {:error, gettext("Une année porte déjà ce nom.")}
      order when order in [:lt, :eq] -> {:error, gettext("La fin doit suivre le début.")}
      _ -> {:error, gettext("Dates invalides.")}
    end
  end

  defp put_classes(socket, params) do
    ids = MapSet.new(socket.assigns.plan.classes, & &1.id)

    labels =
      for {id, label} <- Map.get(params, "labels", %{}),
          MapSet.member?(ids, id),
          into: socket.assigns.labels,
          do: {id, label}

    targets =
      for {id, target} <- Map.get(params, "targets", %{}),
          MapSet.member?(ids, id),
          into: socket.assigns.targets,
          do: {id, if(MapSet.member?(ids, target), do: target)}

    assign(socket, labels: labels, targets: targets)
  end

  defp labels_error(labels) do
    names = labels |> Map.values() |> Enum.map(&String.trim/1)

    cond do
      Enum.any?(names, &(&1 == "")) ->
        gettext("Chaque classe doit avoir un nom.")

      length(Enum.uniq_by(names, &String.downcase/1)) != length(names) ->
        gettext("Deux classes portent le même nom.")

      true ->
        nil
    end
  end

  defp derive(socket) do
    placements = NewYearPlan.placements(socket.assigns.plan.students, socket.assigns.targets)

    assign(socket,
      sizes: NewYearPlan.sizes(placements),
      totals: NewYearPlan.totals(placements),
      year_form: to_form(socket.assigns.year_params, as: :year)
    )
  end

  defp steps do
    [
      {1, gettext("Vérification")},
      {2, gettext("Nouvelle année")},
      {3, gettext("Classes")},
      {4, gettext("Confirmation")}
    ]
  end

  defp target_options(classes, labels),
    do: [{gettext("Ne pas réinscrire"), ""} | Enum.map(classes, &{labels[&1.id], &1.id})]

  defp over?(size, max), do: is_integer(max) and size > max

  defp size_text(size, nil), do: to_string(size)
  defp size_text(size, max), do: "#{size} / #{max}"

  defp reason_label(:exclu), do: gettext("Exclus")
  defp reason_label(:sans_decision), do: gettext("Sans décision")
  defp reason_label(:sans_classe), do: gettext("Admis sans classe d'accueil")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="new-year" class="mx-auto flex w-full max-w-3xl flex-col gap-5">
        <.page_header
          eyebrow={gettext("Paramètres · Année")}
          title={gettext("Préparer l'année suivante")}
          subtitle={gettext("À partir de %{name}", name: @year.name)}
        />

        <ol id="new-year-steps" class="flex flex-wrap gap-2 text-xs font-semibold">
          <li
            :for={{n, label} <- steps()}
            aria-current={n == @step && "step"}
            class={[
              "rounded-full border px-3 py-1 transition-colors",
              cond do
                n == @step -> "border-primary bg-primary/15 text-primary"
                n < @step -> "border-base-300 text-base-content/80"
                true -> "border-base-300 text-base-content/40"
              end
            ]}
          >
            <span class="ta-num">{n}</span> · {label}
          </li>
        </ol>

        <div :if={@step == 1} id="step-checks" class="ta-panel flex flex-col gap-3">
          <h2 class="ta-eyebrow">{gettext("Vérification")}</h2>
          <p :if={@plan.checks.before_end?} id="check-before-end" class="alert alert-warning text-sm">
            {gettext("L'année %{name} se termine le %{date} : vous la clôturez en avance.",
              name: @year.name,
              date: Dates.short(@year.end_date)
            )}
          </p>
          <p id="check-councils" class="text-sm">
            <%= if @plan.checks.open_councils == [] do %>
              {gettext("Tous les conseils de fin d'année sont clos.")}
            <% else %>
              {gettext("Conseil de fin d'année non clos : %{classes}",
                classes: Enum.map_join(@plan.checks.open_councils, ", ", & &1.label)
              )}
            <% end %>
          </p>
          <div :if={@plan.checks.proposals != %{}} id="check-proposals" class="text-sm">
            <p>{gettext("Décisions non confirmées par le conseil (la proposition sera suivie) :")}</p>
            <ul class="mt-1 list-inside list-disc text-base-content/80">
              <li :for={cg <- @plan.classes} :if={@plan.checks.proposals[cg.id]}>
                {cg.label} · <span class="ta-num">{@plan.checks.proposals[cg.id]}</span>
              </li>
            </ul>
          </div>
          <p :if={@plan.checks.departed_courses > 0} id="check-departed" class="text-sm">
            {ngettext(
              "%{count} cours est attribué à un enseignant parti : à réattribuer dans Affectations.",
              "%{count} cours sont attribués à des enseignants partis : à réattribuer dans Affectations.",
              @plan.checks.departed_courses
            )}
          </p>
          <button id="to-step-2" type="button" phx-click="checked" class="btn btn-primary btn-sm self-end">
            {gettext("Continuer")}
          </button>
        </div>

        <.form
          :if={@step == 2}
          for={@year_form}
          id="new-year-form"
          phx-submit="save_year"
          class="ta-panel flex flex-col gap-3"
        >
          <h2 class="ta-eyebrow">{gettext("Nouvelle année")}</h2>
          <div class="grid gap-3 sm:grid-cols-3">
            <.input field={@year_form[:name]} label={gettext("Nom")} />
            <.input field={@year_form[:start_date]} type="date" label={gettext("Début")} />
            <.input field={@year_form[:end_date]} type="date" label={gettext("Fin")} />
          </div>
          <p :if={@year_error} id="year-error" class="text-sm text-error">{@year_error}</p>
          <div class="flex justify-between gap-2">
            <button type="button" phx-click="back" phx-value-step="1" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Continuer")}</button>
          </div>
        </.form>

        <form
          :if={@step == 3}
          id="classes-form"
          phx-change="change_classes"
          phx-submit="save_classes"
          class="ta-panel flex flex-col gap-2"
        >
          <h2 class="ta-eyebrow">{gettext("Classes de %{name}", name: @year_attrs.name)}</h2>
          <div
            :for={cg <- @plan.classes}
            id={"class-row-#{cg.id}"}
            class="grid items-end gap-2 border-t border-base-300 pt-2 sm:grid-cols-[1fr_1fr_5rem]"
          >
            <.input name={"labels[#{cg.id}]"} value={@labels[cg.id]} label={cg.label} />
            <.input
              type="select"
              name={"targets[#{cg.id}]"}
              value={@targets[cg.id] || ""}
              label={gettext("Admis vers")}
              options={target_options(@plan.classes, @labels)}
            />
            <span
              id={"class-size-#{cg.id}"}
              title={gettext("Effectif prévu")}
              class={[
                "ta-num pb-3 text-right text-sm",
                over?(@sizes[cg.id] || 0, @max) && "font-semibold text-warning"
              ]}
            >
              {size_text(@sizes[cg.id] || 0, @max)}
            </span>
          </div>
          <p :if={@classes_error} id="classes-error" class="text-sm text-error">{@classes_error}</p>
          <div class="flex justify-between gap-2 pt-2">
            <button type="button" phx-click="back" phx-value-step="2" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Continuer")}</button>
          </div>
        </form>

        <div :if={@step == 4} id="step-summary" class="ta-panel flex flex-col gap-4">
          <h2 class="ta-eyebrow">{gettext("Confirmation")}</h2>
          <dl class="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <div>
              <dt class="ta-eyebrow">{gettext("Classes")}</dt>
              <dd class="ta-num text-xl font-semibold">{length(@plan.classes)}</dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Réinscrits")}</dt>
              <dd id="summary-reenrolled" class="ta-num text-xl font-semibold">
                {@totals.reenrolled}
              </dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("dont redoublants")}</dt>
              <dd id="summary-repeaters" class="ta-num text-xl font-semibold">{@totals.repeaters}</dd>
            </div>
            <div>
              <dt class="ta-eyebrow">{gettext("Non réinscrits")}</dt>
              <dd id="summary-not" class="ta-num text-xl font-semibold">
                {@totals.not_reenrolled |> Map.values() |> Enum.sum()}
              </dd>
            </div>
          </dl>
          <ul :if={@totals.not_reenrolled != %{}} class="text-sm text-base-content/80">
            <li :for={{reason, n} <- @totals.not_reenrolled}>
              {reason_label(reason)} · <span class="ta-num">{n}</span>
            </li>
          </ul>
          <p class="text-sm text-base-content/70">
            {gettext("L'année %{old} sera clôturée : plus aucune modification n'y sera possible.",
              old: @year.name
            )}
          </p>
          <div class="flex justify-between gap-2">
            <button type="button" phx-click="back" phx-value-step="3" class="btn btn-ghost btn-sm">
              {gettext("Retour")}
            </button>
            <button
              id="start-year"
              type="button"
              phx-click="start"
              phx-disable-with={gettext("Démarrage…")}
              class="btn btn-primary btn-sm"
            >
              {gettext("Démarrer l'année %{name}", name: @year_attrs.name)}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Run the tests**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/new_year_live_test.exs \
  test/teacher_assistant_web/live/school/settings_live_test.exs
mix compile --warnings-as-errors
```

Expected: PASS; no warnings. (If `has_element?(view, "#class-size-…", "1")` matches more than intended
because of the `/ max` suffix, the school has no `max_class_size` in this fixture, so the text is the bare
count.)

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/new_year_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/new_year_live_test.exs
git commit -m "feat: « Préparer l'année suivante » — four-step wizard"
```

---

## 9c — Viewing past years

### Task 7: Results and bulletins in the class's own year; `/school/years/:id`

**Files:**
- Modify: `lib/teacher_assistant/organization.ex` (`class_year/2`)
- Modify: `lib/teacher_assistant/report_cards.ex` (`teaches_class?/2` uses the class's year)
- Modify: `lib/teacher_assistant_web/live/school/results_live.ex`,
  `lib/teacher_assistant_web/live/school/bulletin_live.ex` (year + closed badge)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_controller.ex` (year)
- Create: `lib/teacher_assistant_web/live/school/year_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/live/school/settings_live.ex`
  (« Consulter »)
- Test: `test/teacher_assistant_web/live/school/past_years_test.exs`

**Interfaces:**
- Consumes: `TeacherFixtures.close_year!/2` (Task 1); Task 3/6's actions cell.
- Produces: `Organization.class_year(%Scope{}, %{academic_year_id: id}) :: %AcademicYear{} | nil`; route
  `/school/years/:id`; DOM ids `#year-closed` (results and bulletin pages), `#past-year`,
  `#past-class-<id>`, settings `#year-open-<id>`.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistantWeb.School.PastYearsTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Curriculum, Enrollment, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6ème A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    teacher = TeacherFixtures.member_scope_fixture(scope).current_user
    {:ok, _} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Maths"})
    [seq | _] = Organization.list_sequences(scope, year)
    %{closed: closed} = TeacherFixtures.close_year!(scope, year)
    %{cg: cg, awa: awa, enrollment: e, teacher: teacher, seq: seq, closed: closed}
  end

  defp conn_for(user, school) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "settings opens a closed year, which lists its classes", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, ~s|#year-open-#{ctx.closed.id}[href="/school/years/#{ctx.closed.id}"]|)

    {:ok, view, _} = live(conn, ~p"/school/years/#{ctx.closed.id}")
    assert has_element?(view, "#past-year", "Année de référence")
    assert has_element?(view, ~s|#past-class-#{ctx.cg.id} a[href="/school/classes/#{ctx.cg.id}/results"]|)
  end

  test "a past class's results use its own year and say it is closed", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, ~p"/school/classes/#{ctx.cg.id}/results")
    assert has_element?(view, "#year-closed", "Année de référence")
    # The period list is the closed year's, not the current one's.
    assert html =~ "seq:#{ctx.seq.id}"

    {:ok, view, _} =
      live(conn, ~p"/school/classes/#{ctx.cg.id}/students/#{ctx.enrollment.id}/bulletin")

    assert has_element?(view, "#year-closed")
  end

  test "the printed bulletins of a past class name its year", %{conn: conn} = ctx do
    conn = get(conn, ~p"/school/classes/#{ctx.cg.id}/bulletin/print?period=annee")
    assert html_response(conn, 200) =~ "Année de référence"
  end

  test "the student profile links to the past bulletin", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/students/#{ctx.awa.id}")

    assert has_element?(
             view,
             ~s|#student-history a[href="/school/classes/#{ctx.cg.id}/students/#{ctx.enrollment.id}/bulletin"]|
           )
  end

  test "the past class's teacher still opens its results; another teacher does not",
       %{scope: scope, workspace: school} = ctx do
    assert {:ok, _view, _} =
             live(conn_for(ctx.teacher, school), ~p"/school/classes/#{ctx.cg.id}/results")

    stranger = TeacherFixtures.member_scope_fixture(scope).current_user

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(stranger, school), ~p"/school/classes/#{ctx.cg.id}/results")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/past_years_test.exs`
Expected: FAIL — no `#year-open-…`, no route `/school/years/:id`, results show the current year's séquences.

- [ ] **Step 3: The year of a class; report-card access by that year**

`lib/teacher_assistant/organization.ex`, after `get_academic_year/2`:

```elixir
  @doc "Spec KLM9: the year a class (or any record with `academic_year_id`) belongs to."
  def class_year(%Scope{current_academic_year: %AcademicYear{id: id} = year}, %{
        academic_year_id: id
      }),
      do: year

  def class_year(%Scope{} = scope, %{academic_year_id: id}) when is_binary(id) do
    case get_academic_year(scope, id) do
      {:ok, year} -> year
      _ -> nil
    end
  end

  def class_year(_scope, _record), do: nil
```

`lib/teacher_assistant/report_cards.ex`, replace the two `teaches_class?/2` clauses with:

```elixir
  # Spec KLM9: checked against the class's own year, so a teacher keeps access to a past class.
  defp teaches_class?(%Scope{current_user: %{}} = scope, %ClassGroup{academic_year_id: year_id} = cg)
       when is_binary(year_id),
       do: MapSet.member?(taught_class_ids(scope, %AcademicYear{id: year_id}), cg.id)

  defp teaches_class?(_scope, _cg), do: false
```

- [ ] **Step 4: Results, bulletin and print pages**

`results_live.ex` and `bulletin_live.ex`, in `mount/3`, replace `year = scope.current_academic_year` with:

```elixir
      year = Organization.class_year(scope, cg)
```

and in each `render/1`, right after the `<.page_header …>` element (its closing tag or self-closing end):

```heex
        <p
          :if={@year && @year.status == :closed}
          id="year-closed"
          class="badge badge-ghost gap-1 self-start"
        >
          <.icon name="hero-lock-closed" class="size-3.5" />
          {gettext("Année %{name} · clôturée", name: @year.name)}
        </p>
```

`bulletin_print_controller.ex`:
- in `with_view/4`, replace `year when not is_nil(year) <- scope.current_academic_year,` with
  `year when not is_nil(year) <- Organization.class_year(scope, cg),`;
- in the render call, replace
  `annee: scope.current_academic_year && scope.current_academic_year.name,` with

```elixir
      annee: (year = Organization.class_year(scope, cg)) && year.name,
```

- [ ] **Step 5: `/school/years/:id` and « Consulter »**

Router, in `:school_workspace`, after the new-year route:

```elixir
      live "/school/years/:id", School.YearLive, :show
```

`settings_live.ex` actions cell, inside the `<td class="text-right">`, after the `#new-year-link`:

```heex
                    <.link
                      :if={year.status == :closed}
                      id={"year-open-#{year.id}"}
                      navigate={~p"/school/years/#{year.id}"}
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Consulter")}
                    </.link>
```

`lib/teacher_assistant_web/live/school/year_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.YearLive do
  @moduledoc """
  Spec KLM9 (rule 12): one school year's classes, each linking to its results and its
  printed bulletins — read only when the year is closed. Proviseur and Censeur.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Enrollment, Organization}

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with true <- Organization.can_manage_calendar?(scope),
         {:ok, year} <- Organization.get_academic_year(scope, id) do
      {:ok, assign(socket, year: year, classes: Enrollment.list_class_groups(scope, year))}
    else
      false -> {:ok, push_navigate(socket, to: ~p"/school")}
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="past-year" class="mx-auto flex w-full max-w-3xl flex-col gap-4">
        <.page_header
          eyebrow={gettext("Paramètres · Année")}
          title={@year.name}
          subtitle={
            if @year.status == :closed,
              do: gettext("Année clôturée · lecture seule"),
              else: gettext("Année en cours")
          }
        />
        <div class="ta-panel flex flex-col !p-0">
          <p :if={@classes == []} id="past-year-empty" class="p-4 text-sm text-base-content/60">
            {gettext("Aucune classe cette année-là.")}
          </p>
          <div
            :for={cg <- @classes}
            id={"past-class-#{cg.id}"}
            class="flex flex-wrap items-center justify-between gap-2 border-b border-base-300 px-4 py-2.5 last:border-0"
          >
            <span class="font-semibold">{cg.label}</span>
            <span class="flex gap-4 text-sm">
              <.link navigate={~p"/school/classes/#{cg.id}/results"} class="link link-primary">
                {gettext("Résultats")}
              </.link>
              <.link
                href={~p"/school/classes/#{cg.id}/bulletin/print?period=annee"}
                class="link link-primary"
              >
                {gettext("Bulletins de l'année")}
              </.link>
            </span>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 6: Run the tests**

```bash
MIX_TEST_PARTITION=9 mix test test/teacher_assistant_web/live/school/past_years_test.exs \
  test/teacher_assistant_web/live/school/results_live_test.exs \
  test/teacher_assistant_web/live/school/bulletin_live_test.exs test/teacher_assistant_web/controllers \
  test/teacher_assistant/report_cards_access_test.exs test/teacher_assistant/report_cards_test.exs
mix compile --warnings-as-errors
```

Expected: PASS; no warnings. (`html =~ "seq:#{ctx.seq.id}"` relies on the results page's period select
using `Organization.period_param/1` values; if it renders them differently, assert on the séquence's
period param as the page writes it.)

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/organization.ex lib/teacher_assistant/report_cards.ex \
  lib/teacher_assistant_web/live/school/results_live.ex lib/teacher_assistant_web/live/school/bulletin_live.ex \
  lib/teacher_assistant_web/controllers/bulletin_print_controller.ex \
  lib/teacher_assistant_web/live/school/year_live.ex lib/teacher_assistant_web/router.ex \
  lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/past_years_test.exs
git commit -m "feat: past years viewable — results and bulletins in the class's own year, read only"
```

---

### Task 8: Translations, status, full checks

**Files:**
- Modify: `priv/gettext/**`, `docs/superpowers/specs/2026-09-27-mockups-roadmap.md`

- [ ] **Step 1: Codegen check** — `mix ash.codegen --check` prints no change (the Task 1 migration is the only
  one).

- [ ] **Step 2: Translations** — `mix gettext.extract --merge`; fill every new `en` msgstr (e.g. « Préparer
  l'année suivante » → "Prepare next year", « Clôturée » → "Closed", « Consulter » → "View", « Année %{name}
  · clôturée » → "Year %{name} · closed", « Démarrer l'année %{name} » → "Start year %{name}", « Ne pas
  réinscrire » → "Do not re-enrol", « Admis vers » → "Promoted to", « Réinscrits » → "Re-enrolled", « dont
  redoublants » → "of whom repeating", « Non réinscrits » → "Not re-enrolled", « Exclus » → "Expelled", « Sans
  décision » → "No decision", « Admis sans classe d'accueil » → "Promoted, no class to go to"); for every
  entry the merge marked fuzzy with a wrong guess, set the right `en` msgstr (fr: empty) and remove the
  fuzzy flag. `grep -c fuzzy priv/gettext/{en,fr}/LC_MESSAGES/default.po` equals main's counts.

- [ ] **Step 3: Roadmap status** — under `## KLM9 — Next school year and closed years (spec)` add
  `Status: implemented 2026-10-06 (branch \`klm9-next-year\`, plan
  \`docs/superpowers/plans/2026-10-06-klm9-next-year.md\`); no visual check done.`

- [ ] **Step 4: Full checks** — `mix compile --warnings-as-errors`, then `MIX_TEST_PARTITION=9 mix precommit`;
  both exit 0; stage what `format` rewrote.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test
git commit -m "chore: KLM9 translations and status"
```
