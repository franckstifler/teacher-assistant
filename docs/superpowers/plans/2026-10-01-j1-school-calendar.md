# J1 — School calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A school says which days it teaches, whether Wednesday afternoon is free, how long a lesson lasts and
which dates are holidays; timetables, day views and roll-call expectations follow.

**Architecture:** A pure `Academics.SchoolCalendar` struct answers `lesson_day?/2`, `holiday_on/2` and
`open_cell?/3`. It is built by `Attendance.school_calendar/1` from three new `SchoolProfile` fields and the
active year's `Holiday` rows. Timetabling refuses closed cells, the timetable grids show only lesson days,
and `SchoolLife` (G's day views) expects no roll call on days off or in closed cells. The « Périodes » page
becomes « Horaires » (settings + add a period, with an overlap check), and a new « Congés & jours fériés »
page edits the holidays; creating a year prefills the national holidays.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3 (attribute multitenancy on `workspace_id`), AshPostgres, Gettext
(French source msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"J1 — School calendar (spec)".

## Global Constraints

- Never write migrations by hand: `mix ash.codegen --dev`, then `mix ash.codegen j1_school_calendar` to name
  it; `mix ash.codegen --check` clean at the end. Do NOT run `mix ash.migrate` on the dev DB from the worktree
  (it is shared with another session); migrate the test DB with `MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.migrate`.
- Enums are `Ash.Type.Enum` modules (reuse `Academics.DayOfWeek`), never bare `:atom`.
- Strings through gettext; msgids French. After `mix gettext.extract --merge`, fix every new fuzzy entry in
  `en` and `fr` (compare with main: en 24, fr 17 fuzzy).
- Worktree `.claude/worktrees/j1`, branch `j1-school-calendar`, `MIX_TEST_PARTITION=2` for `mix test`. Stage
  explicit paths only — never `git commit -a`.
- `lesson_days` nil = all six days (Monday–Saturday, today's behaviour). The afternoon = periods starting at
  or after **13:00**. `default_lesson_minutes` default **50**, range 1..240.
- Closing a day or Wednesday afternoon that holds timetable slots of the active year is refused; nothing is
  written.
- Default schedule (new schools only): Cours 1 07:30–08:20, Cours 2 08:20–09:10, Cours 3 09:10–10:00,
  Récréation 10:00–10:15, Cours 4 10:15–11:05, Cours 5 11:05–11:55, Cours 6 11:55–12:45, Pause 13:00–13:30,
  Cours 7 13:30–14:20, Cours 8 14:20–15:10, Cours 9 15:10–16:00.
- National holidays prefilled: Noël 25 Dec, Jour de l'an 1 Jan, Fête de la Jeunesse 11 Feb, Vendredi saint
  and Ascension (from Easter), Fête du Travail 1 May, Fête nationale 20 May — only those inside the year.
- `mix precommit` before the last commit; re-stage what the formatter rewrote.

## Review Focus

1. A holiday spanning a weekend or several weeks (« Congés de Noël 19 déc. → 4 janv. ») — every date in the
   range, inclusive of both ends, is a day off (test in Task 1).
2. Unticking Saturday when only a *previous* year's timetable has Saturday slots — allowed (only the active
   year counts) (test in Task 3).
3. « Appels manquants cette semaine » on a week with a holiday on Monday — Monday's slots are not listed as
   missed (test in Task 5).
4. Pressing « Préremplir » twice, or after the year was created (which already prefilled) — no duplicates
   (test in Task 2).
5. A crafted `place` event on a closed cell (Wednesday afternoon, an unticked day) — refused, nothing written
   (test in Task 4).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/teacher_assistant/academics/school_calendar.ex` (new) | Pure calendar: struct, `lesson_day?`, `holiday_on`, `open_cell?`, `afternoon?`, Easter, national holidays |
| `lib/teacher_assistant/academics/holiday.ex` (new) | `Holiday` resource (Organization domain) |
| `lib/teacher_assistant/academics/holiday/validate_dates.ex` (new) | end ≥ start, inside the year |
| `lib/teacher_assistant/academics/academic_year/prefill_holidays.ex` (new) | after_action change on `:create_for_workspace` |
| `lib/teacher_assistant/academics/period/validate_times.ex` (new) | end > start, no overlap |
| `lib/teacher_assistant/accounts/school_profile.ex` | `lesson_days`, `wednesday_afternoon_off?`, `default_lesson_minutes` |
| `lib/teacher_assistant/organization.ex` | Holiday functions |
| `lib/teacher_assistant/attendance.ex` | `school_calendar/1`, `update_school_days/2`, `create_period/2`, `day_off/2` |
| `lib/teacher_assistant/academics/reference.ex` | 50-minute default schedule |
| `lib/teacher_assistant/timetabling.ex` | closed-cell refusal |
| `lib/teacher_assistant/academics/school_life.ex` | days off and closed cells |
| `lib/teacher_assistant_web/live/school/{timetable_live,my_timetable_live}.ex`, `controllers/timetable_print_*` | lesson-day columns, greyed cells |
| `lib/teacher_assistant_web/live/school/{day_live,my_day_live}.ex` | holiday message |
| `lib/teacher_assistant_web/live/school/periods_live.ex` | « Horaires »: settings + add row |
| `lib/teacher_assistant_web/live/school/holidays_live.ex` (new) | « Congés & jours fériés » |
| `router.ex`, `spaces.ex`, `settings_live.ex` | route and links |

---

### Task 0: Worktree

- [ ] **Step 1**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/j1 -b j1-school-calendar main
cd .claude/worktrees/j1 && mix deps.get
MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_life_test.exs
```

Expected: 0 failures.

---

### Task 1: The calendar (pure)

**Files:**
- Create: `lib/teacher_assistant/academics/school_calendar.ex`
- Test: `test/teacher_assistant/academics/school_calendar_test.exs`

**Interfaces:**
- Produces:
  - `%SchoolCalendar{lesson_days: [atom], wednesday_afternoon_off?: boolean, holidays: [%{label, start_date, end_date}]}`
  - `SchoolCalendar.new(lesson_days | nil, wednesday_afternoon_off?, holidays)` (nil days → all six)
  - `SchoolCalendar.all_days/0 :: [atom]` (Monday..Saturday)
  - `SchoolCalendar.weekday(Date) :: atom`
  - `SchoolCalendar.lesson_day?(cal, Date) :: boolean`
  - `SchoolCalendar.holiday_on(cal, Date) :: holiday | nil`
  - `SchoolCalendar.open_cell?(cal, day_atom, %{start_time: Time}) :: boolean`
  - `SchoolCalendar.afternoon?(%{start_time: Time}) :: boolean` (start ≥ 13:00)
  - `SchoolCalendar.easter(year :: integer) :: Date`
  - `SchoolCalendar.national_holidays(first :: Date, last :: Date) :: [%{label, start_date, end_date}]` (current locale)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Academics.SchoolCalendarTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.SchoolCalendar

  @noel %{label: "Congés de Noël", start_date: ~D[2025-12-19], end_date: ~D[2026-01-04]}

  test "nil lesson days means Monday to Saturday" do
    cal = SchoolCalendar.new(nil, false, [])
    assert cal.lesson_days == SchoolCalendar.all_days()
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-09-20])
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-09-21])
  end

  test "an unticked weekday is not a lesson day" do
    cal = SchoolCalendar.new([:monday, :tuesday, :wednesday, :thursday, :friday], false, [])
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-09-20])
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-09-19])
  end

  test "a holiday range is a day off on every date, both ends included" do
    cal = SchoolCalendar.new(nil, false, [@noel])
    for d <- [~D[2025-12-19], ~D[2025-12-25], ~D[2026-01-03], ~D[2026-01-04]] do
      refute SchoolCalendar.lesson_day?(cal, d)
      assert SchoolCalendar.holiday_on(cal, d) == @noel
    end

    assert SchoolCalendar.lesson_day?(cal, ~D[2026-01-05])
    assert SchoolCalendar.holiday_on(cal, ~D[2026-01-05]) == nil
  end

  test "Wednesday afternoon: periods from 13:00 close when the toggle is on" do
    off = SchoolCalendar.new(nil, true, [])
    on = SchoolCalendar.new(nil, false, [])
    late = %{start_time: ~T[13:00:00]}
    morning = %{start_time: ~T[11:55:00]}

    refute SchoolCalendar.open_cell?(off, :wednesday, late)
    assert SchoolCalendar.open_cell?(off, :wednesday, morning)
    assert SchoolCalendar.open_cell?(off, :thursday, late)
    assert SchoolCalendar.open_cell?(on, :wednesday, late)
  end

  test "a cell on an unticked day is closed" do
    cal = SchoolCalendar.new([:monday], false, [])
    refute SchoolCalendar.open_cell?(cal, :tuesday, %{start_time: ~T[08:00:00]})
  end

  test "Easter dates" do
    assert SchoolCalendar.easter(2026) == ~D[2026-04-05]
    assert SchoolCalendar.easter(2025) == ~D[2025-04-20]
    assert SchoolCalendar.easter(2027) == ~D[2027-03-28]
  end

  test "national holidays inside a school year" do
    list = SchoolCalendar.national_holidays(~D[2025-09-08], ~D[2026-07-31])
    dates = Enum.map(list, & &1.start_date)

    assert ~D[2025-12-25] in dates
    assert ~D[2026-01-01] in dates
    assert ~D[2026-02-11] in dates
    assert ~D[2026-04-03] in dates
    assert ~D[2026-05-01] in dates
    assert ~D[2026-05-14] in dates
    assert ~D[2026-05-20] in dates
    assert length(list) == 7
    assert Enum.all?(list, &(&1.start_date == &1.end_date))
    assert dates == Enum.sort(dates, Date)

    assert SchoolCalendar.national_holidays(~D[2026-01-02], ~D[2026-02-01]) == []
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_calendar_test.exs`
Expected: FAIL — `SchoolCalendar` undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule TeacherAssistant.Academics.SchoolCalendar do
  @moduledoc """
  The school calendar (spec J1, S02/S03), pure: which weekdays have lessons, whether
  Wednesday afternoon is free (every period starting at or after 13:00), and the
  year's holidays. Built by `TeacherAssistant.Attendance.school_calendar/1`.
  """
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @all_days ~w(monday tuesday wednesday thursday friday saturday)a
  @afternoon ~T[13:00:00]

  defstruct lesson_days: @all_days, wednesday_afternoon_off?: false, holidays: []

  def all_days, do: @all_days

  def new(lesson_days, wednesday_afternoon_off?, holidays) do
    %__MODULE__{
      lesson_days: if(lesson_days in [nil, []], do: @all_days, else: lesson_days),
      wednesday_afternoon_off?: wednesday_afternoon_off? == true,
      holidays: holidays
    }
  end

  @doc "The weekday atom of `date`, or nil on a Sunday."
  def weekday(%Date{} = date), do: Enum.at(@all_days ++ [nil], Date.day_of_week(date) - 1)

  def lesson_day?(%__MODULE__{} = cal, %Date{} = date),
    do: weekday(date) in cal.lesson_days and is_nil(holiday_on(cal, date))

  def holiday_on(%__MODULE__{holidays: holidays}, %Date{} = date) do
    Enum.find(holidays, fn h ->
      Date.compare(date, h.start_date) != :lt and Date.compare(date, h.end_date) != :gt
    end)
  end

  @doc "Whether a lesson may sit in this (weekday, period) cell of the weekly timetable."
  def open_cell?(%__MODULE__{} = cal, day, period) do
    day in cal.lesson_days and
      not (cal.wednesday_afternoon_off? and day == :wednesday and afternoon?(period))
  end

  def afternoon?(%{start_time: %Time{} = start}), do: Time.compare(start, @afternoon) != :lt

  @doc "Easter Sunday (anonymous Gregorian algorithm)."
  def easter(year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    d = div(b, 4)
    e = rem(b, 4)
    f = div(b + 8, 25)
    g = div(b - f + 1, 3)
    h = rem(19 * a + b - d - g + 15, 30)
    i = div(c, 4)
    k = rem(c, 4)
    l = rem(32 + 2 * e + 2 * i - h - k, 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)
    day = rem(h + l - 7 * m + 114, 31) + 1
    Date.new!(year, month, day)
  end

  @doc "The national holidays between `first` and `last`, one day each, labels in the current locale."
  def national_holidays(%Date{} = first, %Date{} = last) do
    first.year..last.year
    |> Enum.flat_map(fn y ->
      easter = easter(y)

      [
        {Date.new!(y, 1, 1), gettext("Jour de l'an")},
        {Date.new!(y, 2, 11), gettext("Fête de la Jeunesse")},
        {Date.add(easter, -2), gettext("Vendredi saint")},
        {Date.new!(y, 5, 1), gettext("Fête du Travail")},
        {Date.add(easter, 39), gettext("Ascension")},
        {Date.new!(y, 5, 20), gettext("Fête nationale")},
        {Date.new!(y, 12, 25), gettext("Noël")}
      ]
    end)
    |> Enum.filter(fn {d, _} -> Date.compare(d, first) != :lt and Date.compare(d, last) != :gt end)
    |> Enum.sort_by(fn {d, _} -> Date.to_gregorian_days(d) end)
    |> Enum.map(fn {d, label} -> %{label: label, start_date: d, end_date: d} end)
  end
end
```

- [ ] **Step 4: Run it**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_calendar_test.exs`
Expected: 7 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/school_calendar.ex test/teacher_assistant/academics/school_calendar_test.exs
git commit -m "feat: pure school calendar (lesson days, Wednesday afternoon, holidays, Easter)"
```

---

### Task 2: Data — profile fields, holidays, prefill, `school_calendar/1`

**Files:**
- Modify: `lib/teacher_assistant/accounts/school_profile.ex`
- Create: `lib/teacher_assistant/academics/holiday.ex`, `lib/teacher_assistant/academics/holiday/validate_dates.ex`,
  `lib/teacher_assistant/academics/academic_year/prefill_holidays.ex`
- Modify: `lib/teacher_assistant/academics/academic_year.ex` (`:create_for_workspace` gets the change),
  `lib/teacher_assistant/organization.ex` (resource + functions), `lib/teacher_assistant/attendance.ex` (`school_calendar/1`)
- Test: `test/teacher_assistant/academics/holidays_test.exs`

**Interfaces:**
- Consumes: Task 1 `SchoolCalendar.new/3`, `national_holidays/2`.
- Produces:
  - profile: `lesson_days` ({:array, DayOfWeek}, nil = all), `wednesday_afternoon_off?` (bool, default false),
    `default_lesson_minutes` (integer, default 50, 1..240)
  - `Organization.list_holidays(scope, year) :: [Holiday]` sorted by start date
  - `Organization.create_holiday(scope, year, %{label, start_date, end_date})`, `update_holiday(scope, holiday, attrs)`,
    `delete_holiday(scope, holiday)`, `prefill_holidays(scope, year) :: {:ok, added_count}`
  - `Attendance.school_calendar(scope) :: %SchoolCalendar{}` (active year's holidays; none without a year)

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/holidays_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.HolidaysTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Organization}
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    year = TeacherFixtures.complete_school_setup!(scope)
    %{scope: %{scope | current_academic_year: year}, year: year}
  end

  test "creating a year prefills the national holidays inside it", %{scope: scope, year: year} do
    labels = scope |> Organization.list_holidays(year) |> Enum.map(& &1.label)
    assert "Noël" in labels
    assert "Fête nationale" in labels
    assert length(labels) == 7
  end

  test "Préremplir adds nothing twice", %{scope: scope, year: year} do
    assert {:ok, 0} = Organization.prefill_holidays(scope, year)
    [first | _] = Organization.list_holidays(scope, year)
    :ok = Organization.delete_holiday(scope, first)
    assert {:ok, 1} = Organization.prefill_holidays(scope, year)
    assert length(Organization.list_holidays(scope, year)) == 7
  end

  test "a holiday ends on or after its start, inside the year", %{scope: scope, year: year} do
    assert {:ok, h} =
             Organization.create_holiday(scope, year, %{
               label: "Congés de Noël",
               start_date: ~D[2025-12-19],
               end_date: ~D[2026-01-04]
             })

    assert h.label == "Congés de Noël"

    for {s, e} <- [{~D[2025-12-20], ~D[2025-12-19]}, {~D[2025-09-01], ~D[2025-09-02]}, {~D[2026-07-30], ~D[2026-08-02]}] do
      assert {:error, %Ash.Error.Invalid{}} =
               Organization.create_holiday(scope, year, %{label: "X", start_date: s, end_date: e})
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Organization.create_holiday(scope, year, %{label: " ", start_date: ~D[2025-10-01], end_date: ~D[2025-10-01]})
  end

  test "school_calendar combines the profile and the active year's holidays", %{scope: scope} do
    cal = Attendance.school_calendar(scope)
    assert cal.lesson_days == SchoolCalendar.all_days()
    refute cal.wednesday_afternoon_off?
    refute SchoolCalendar.lesson_day?(cal, ~D[2025-12-25])
    assert SchoolCalendar.lesson_day?(cal, ~D[2025-12-24])
  end

  test "profile defaults", %{scope: scope} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.lesson_days == nil
    assert profile.default_lesson_minutes == 50
    refute profile.wednesday_afternoon_off?
  end

  test "a plain teacher cannot add a holiday", %{scope: scope, year: year} do
    teacher = %{TeacherFixtures.member_scope_fixture(scope) | current_academic_year: year}

    assert {:error, %Ash.Error.Forbidden{}} =
             Organization.create_holiday(teacher, year, %{label: "X", start_date: ~D[2025-10-01], end_date: ~D[2025-10-01]})
  end
end
```

(`complete_school_setup!/1` returns the active year, as in `report_cards_test.exs`; it creates the year through
`Organization.create_academic_year/2`, so the prefill runs.)

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/holidays_test.exs`
Expected: FAIL — `Organization.list_holidays/2` undefined.

- [ ] **Step 3: Profile fields**

In `SchoolProfile` attributes, after the I5 block (`grade_scale`):

```elixir
    # Spec J1: the school calendar. nil lesson days = Monday to Saturday.
    attribute :lesson_days, {:array, TeacherAssistant.Academics.DayOfWeek}, public?: true

    attribute :wednesday_afternoon_off?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :default_lesson_minutes, :integer,
      allow_nil?: false,
      default: 50,
      public?: true,
      constraints: [min: 1, max: 240]
```

Add `:lesson_days, :wednesday_afternoon_off?, :default_lesson_minutes` to the `update :update` accept list.

- [ ] **Step 4: Holiday resource**

`lib/teacher_assistant/academics/holiday.ex`:

```elixir
defmodule TeacherAssistant.Academics.Holiday do
  @moduledoc """
  A day or range of days without lessons in an academic year (spec J1, S02):
  public holidays, school breaks, religious feasts, exam periods.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "holidays"
    repo TeacherAssistant.Repo

    references do
      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:academic_year_id, :label, :start_date, :end_date],
              update: [:label, :start_date, :end_date]]

    read :for_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(academic_year_id == ^arg(:academic_year_id))
      prepare build(sort: [start_date: :asc, label: :asc])
    end
  end

  validations do
    validate TeacherAssistant.Academics.Holiday.ValidateDates
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    # Nullable so a blank label reaches ValidateDates and its own message.
    attribute :label, :string, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end
  end
end
```

(`belongs_to :workspace` first, so the codegen orders the tenant column first — the I3 lesson. `AcademicYear`
must already have a `(workspace_id, id)` unique key for the tenant-matched reference; `Term` references it the
same way, so it exists.)

`lib/teacher_assistant/academics/holiday/validate_dates.ex`:

```elixir
defmodule TeacherAssistant.Academics.Holiday.ValidateDates do
  @moduledoc "Spec J1: a holiday has a label, ends on or after its start, and lies inside its year."
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.AcademicYear

  @impl true
  def validate(changeset, _opts, _context) do
    label = Ash.Changeset.get_attribute(changeset, :label)
    s = Ash.Changeset.get_attribute(changeset, :start_date)
    e = Ash.Changeset.get_attribute(changeset, :end_date)
    year_id = Ash.Changeset.get_attribute(changeset, :academic_year_id)

    cond do
      is_nil(label) or String.trim(label) == "" ->
        {:error, field: :label, message: gettext("Donnez un libellé.")}

      is_nil(s) or is_nil(e) ->
        :ok

      Date.compare(e, s) == :lt ->
        {:error, field: :end_date, message: gettext("La fin doit être le même jour ou après le début.")}

      not inside_year?(changeset.tenant, year_id, s, e) ->
        {:error, field: :start_date, message: gettext("Les dates doivent être dans l'année scolaire.")}

      true ->
        :ok
    end
  end

  defp inside_year?(tenant, year_id, s, e) do
    case Ash.get(AcademicYear, year_id, tenant: tenant, authorize?: false) do
      {:ok, year} ->
        Date.compare(s, year.start_date) != :lt and Date.compare(e, year.end_date) != :gt

      _ ->
        false
    end
  end
end
```

If `changeset.tenant` is nil at validation time (scope-based tenancy sets it during `for_create`), read the
tenant with `Ash.Changeset.get_attribute(changeset, :workspace_id)` instead — ledger the ruling.

- [ ] **Step 5: Prefill on year creation**

`lib/teacher_assistant/academics/academic_year/prefill_holidays.ex`:

```elixir
defmodule TeacherAssistant.Academics.AcademicYear.PrefillHolidays do
  @moduledoc "Spec J1: a new academic year starts with the national holidays that fall inside it."
  use Ash.Resource.Change

  alias TeacherAssistant.Academics.{Holiday, SchoolCalendar}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, year ->
      year.start_date
      |> SchoolCalendar.national_holidays(year.end_date)
      |> Enum.each(fn h ->
        Holiday
        |> Ash.Changeset.for_create(:create, Map.put(h, :academic_year_id, year.id),
          tenant: year.workspace_id,
          authorize?: false
        )
        |> Ash.create!()
      end)

      {:ok, year}
    end)
  end
end
```

In `AcademicYear`, inside `create :create_for_workspace do … end`, add
`change TeacherAssistant.Academics.AcademicYear.PrefillHolidays` (creating the year was already authorized).

- [ ] **Step 6: Organization and Attendance functions**

`Organization`: add `resource TeacherAssistant.Academics.Holiday` to `resources do`, alias `Holiday` and
`SchoolCalendar`, and:

```elixir
  # --- Holidays (spec J1) ---------------------------------------------------------

  def list_holidays(%Scope{} = scope, %AcademicYear{id: year_id}) do
    Holiday
    |> Ash.Query.for_read(:for_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.read!()
  end

  def create_holiday(%Scope{} = scope, %AcademicYear{id: year_id}, attrs) do
    Holiday
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :academic_year_id, year_id), scope: scope)
    |> Ash.create()
  end

  def update_holiday(%Scope{} = scope, %Holiday{} = holiday, attrs) do
    holiday |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  def delete_holiday(%Scope{} = scope, %Holiday{} = holiday), do: Ash.destroy(holiday, scope: scope)

  @doc "Adds the year's national holidays not already there (same label and start). `{:ok, added}`."
  def prefill_holidays(%Scope{} = scope, %AcademicYear{} = year) do
    existing = scope |> list_holidays(year) |> MapSet.new(&{&1.label, &1.start_date})

    year.start_date
    |> SchoolCalendar.national_holidays(year.end_date)
    |> Enum.reject(&MapSet.member?(existing, {&1.label, &1.start_date}))
    |> Enum.reduce_while({:ok, 0}, fn h, {:ok, n} ->
      case create_holiday(scope, year, h) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        error -> {:halt, error}
      end
    end)
  end
```

(`Ash.Query` must be required in `Organization` if not already.)

`Attendance`:

```elixir
  @doc "The school calendar: profile settings and the active year's holidays (spec J1)."
  def school_calendar(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    holidays =
      case scope.current_academic_year do
        nil -> []
        year -> scope |> TeacherAssistant.Organization.list_holidays(year) |> Enum.map(&Map.take(&1, [:label, :start_date, :end_date]))
      end

    SchoolCalendar.new(profile.lesson_days, profile.wednesday_afternoon_off?, holidays)
  end
```

- [ ] **Step 7: Migration**

Run: `mix ash.codegen --dev`, inspect the migration (new `holidays` table with `workspace_id` before the
`academic_year` composite FK; three profile columns), then `mix ash.codegen j1_school_calendar`,
`MIX_TEST_PARTITION=2 MIX_ENV=test mix ash.migrate`, `mix ash.codegen --check`.
If the test DB still holds the `--dev` migration's version after squashing, recreate it:
`MIX_TEST_PARTITION=2 MIX_ENV=test mix ecto.drop && … ecto.create && … ecto.migrate`.

- [ ] **Step 8: Run tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/holidays_test.exs` → 6 tests, 0 failures.
Then the full suite: any test asserting exact data created with a year (counts of rows) may now see holidays —
fix the assertion and ledger it.

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant/accounts/school_profile.ex lib/teacher_assistant/academics/holiday.ex \
  lib/teacher_assistant/academics/holiday lib/teacher_assistant/academics/academic_year \
  lib/teacher_assistant/academics/academic_year.ex lib/teacher_assistant/organization.ex \
  lib/teacher_assistant/attendance.ex priv/repo/migrations priv/resource_snapshots \
  test/teacher_assistant/academics/holidays_test.exs
git commit -m "feat: holidays per year, prefilled national holidays, lesson-day settings on the profile"
```

---

### Task 3: Periods — overlap check, 50-minute default, add a period, saving the days

**Files:**
- Create: `lib/teacher_assistant/academics/period/validate_times.ex`
- Modify: `lib/teacher_assistant/academics/period.ex` (validation), `lib/teacher_assistant/academics/reference.ex`
  (`default_periods_preset/0`), `lib/teacher_assistant/attendance.ex` (`create_period/2`, `update_school_days/2`)
- Test: `test/teacher_assistant/academics/school_days_test.exs`; update `test/teacher_assistant/academics/timetables_periods_test.exs`

**Interfaces:**
- Consumes: Task 1 `SchoolCalendar.afternoon?/1`, `all_days/0`; Task 2 profile fields.
- Produces: `Attendance.create_period(scope, attrs) :: {:ok, Period} | {:error, _}`;
  `Attendance.update_school_days(scope, %{"lesson_days" => [s], "wednesday_afternoon_off?" => "true" | absent,
  "default_lesson_minutes" => s})` → `{:ok, profile}` | `{:error, :invalid_setting}` |
  `{:error, {:slots_in_closed_cells, [{day_atom, count}]}}` | `{:error, %Ash.Error.*{}}`

- [ ] **Step 1: Write the failing test**

`test/teacher_assistant/academics/school_days_test.exs`:

```elixir
defmodule TeacherAssistant.Academics.SchoolDaysTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    :ok = Attendance.build_default_periods(scope)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e J", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(2)})
    periods = Attendance.list_periods(scope)
    %{scope: scope, year: year, cg: cg, tc: tc, periods: periods}
  end

  defp lesson(periods, label), do: Enum.find(periods, &(&1.label == label))

  test "the default schedule has 50-minute lessons and breaks at 10:00 and 13:00", %{periods: periods} do
    lessons = Enum.filter(periods, &(&1.kind == :lesson))
    assert length(lessons) == 9
    assert Enum.all?(lessons, &(Time.diff(&1.end_time, &1.start_time, :minute) == 50))
    assert %{start_time: ~T[10:00:00], end_time: ~T[10:15:00]} = lesson(periods, "Récréation")
    assert %{start_time: ~T[13:00:00], end_time: ~T[13:30:00]} = lesson(periods, "Pause")
  end

  test "periods may not overlap or end before they start", %{scope: scope} do
    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.create_period(scope, %{position: 20, label: "X", start_time: ~T[08:00:00], end_time: ~T[08:30:00], kind: :lesson})

    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.create_period(scope, %{position: 20, label: "X", start_time: ~T[17:00:00], end_time: ~T[16:30:00], kind: :lesson})

    assert {:ok, _} =
             Attendance.create_period(scope, %{position: 20, label: "Cours 10", start_time: ~T[16:00:00], end_time: ~T[16:50:00], kind: :lesson})
  end

  test "saves lesson days, the Wednesday toggle and the lesson length", %{scope: scope} do
    assert {:ok, profile} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday wednesday thursday friday),
               "wednesday_afternoon_off?" => "true",
               "default_lesson_minutes" => "45"
             })

    assert profile.lesson_days == ~w(monday tuesday wednesday thursday friday)a
    assert profile.wednesday_afternoon_off?
    assert profile.default_lesson_minutes == 45
  end

  test "closing a day or Wednesday afternoon that holds lessons is refused", ctx do
    %{scope: scope, cg: cg, tc: tc, periods: periods} = ctx
    {:ok, _} = Timetabling.place_slot(scope, cg, %{day: :saturday, period_id: lesson(periods, "Cours 1").id, teaching_context_id: tc.id})
    {:ok, _} = Timetabling.place_slot(scope, cg, %{day: :wednesday, period_id: lesson(periods, "Cours 7").id, teaching_context_id: tc.id})

    assert {:error, {:slots_in_closed_cells, [saturday: 1]}} =
             Attendance.update_school_days(scope, %{"lesson_days" => ~w(monday tuesday wednesday thursday friday), "default_lesson_minutes" => "50"})

    assert {:error, {:slots_in_closed_cells, [wednesday: 1]}} =
             Attendance.update_school_days(scope, %{
               "lesson_days" => ~w(monday tuesday wednesday thursday friday saturday),
               "wednesday_afternoon_off?" => "true",
               "default_lesson_minutes" => "50"
             })

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    assert profile.lesson_days == nil
  end

  test "only the active year's slots block a change", ctx do
    %{scope: scope, cg: cg, tc: tc, periods: periods} = ctx
    {:ok, _} = Timetabling.place_slot(scope, cg, %{day: :saturday, period_id: lesson(periods, "Cours 1").id, teaching_context_id: tc.id})

    {:ok, next} =
      Organization.create_academic_year(scope, %{name: "2026-2027", start_date: ~D[2026-09-07], end_date: ~D[2027-07-30]})

    {:ok, _} = Organization.activate_academic_year(scope, next)
    scope = %{scope | current_academic_year: next}

    assert {:ok, _} =
             Attendance.update_school_days(scope, %{"lesson_days" => ~w(monday tuesday), "default_lesson_minutes" => "50"})
  end

  test "unknown days, no day, or a bad length are refused", %{scope: scope} do
    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{"lesson_days" => ["sunday"], "default_lesson_minutes" => "50"})

    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{"lesson_days" => [""], "default_lesson_minutes" => "50"})

    assert {:error, :invalid_setting} =
             Attendance.update_school_days(scope, %{"lesson_days" => ["monday"], "default_lesson_minutes" => "x"})
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_days_test.exs`
Expected: FAIL — default schedule has 8 lessons / `create_period` undefined.

- [ ] **Step 3: Period validation**

`lib/teacher_assistant/academics/period/validate_times.ex`:

```elixir
defmodule TeacherAssistant.Academics.Period.ValidateTimes do
  @moduledoc "Spec J1 (S03): a period ends after it starts and overlaps no other period of the school."
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  require Ash.Query
  alias TeacherAssistant.Academics.Period

  @impl true
  def validate(changeset, _opts, _context) do
    s = Ash.Changeset.get_attribute(changeset, :start_time)
    e = Ash.Changeset.get_attribute(changeset, :end_time)

    cond do
      is_nil(s) or is_nil(e) ->
        :ok

      Time.compare(e, s) != :gt ->
        {:error, field: :end_time, message: gettext("La période doit finir après son début.")}

      other = overlapping(changeset, s, e) ->
        {:error,
         field: :start_time,
         message:
           gettext("Chevauche %{label} (%{start}–%{end}).",
             label: other.label,
             start: hm(other.start_time),
             end: hm(other.end_time)
           )}

      true ->
        :ok
    end
  end

  defp overlapping(changeset, s, e) do
    id = changeset.data.id
    tenant = changeset.tenant || Ash.Changeset.get_attribute(changeset, :workspace_id)

    Period
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn p ->
      p.id != id and Time.compare(s, p.end_time) == :lt and Time.compare(p.start_time, e) == :lt
    end)
  end

  defp hm(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
end
```

In `Period`, add after `actions`:

```elixir
  validations do
    validate TeacherAssistant.Academics.Period.ValidateTimes, on: [:create, :update]
  end
```

- [ ] **Step 4: Default schedule**

Replace the list in `Reference.default_periods_preset/0` with (keep the function's doc):

```elixir
    [
      {1, "Cours 1", ~T[07:30:00], ~T[08:20:00], :lesson},
      {2, "Cours 2", ~T[08:20:00], ~T[09:10:00], :lesson},
      {3, "Cours 3", ~T[09:10:00], ~T[10:00:00], :lesson},
      {4, "Récréation", ~T[10:00:00], ~T[10:15:00], :break},
      {5, "Cours 4", ~T[10:15:00], ~T[11:05:00], :lesson},
      {6, "Cours 5", ~T[11:05:00], ~T[11:55:00], :lesson},
      {7, "Cours 6", ~T[11:55:00], ~T[12:45:00], :lesson},
      {8, "Pause", ~T[13:00:00], ~T[13:30:00], :break},
      {9, "Cours 7", ~T[13:30:00], ~T[14:20:00], :lesson},
      {10, "Cours 8", ~T[14:20:00], ~T[15:10:00], :lesson},
      {11, "Cours 9", ~T[15:10:00], ~T[16:00:00], :lesson}
    ]
    |> Enum.map(fn {position, label, start_time, end_time, kind} ->
      %{position: position, label: label, start_time: start_time, end_time: end_time, kind: kind}
    end)
```

- [ ] **Step 5: Attendance functions**

```elixir
  @doc "Adds a period to the school's schedule (admin axis)."
  def create_period(%Scope{} = scope, attrs) do
    Period |> Ash.Changeset.for_create(:create, attrs, scope: scope) |> Ash.create()
  end

  @doc """
  Saves the lesson days, the Wednesday-afternoon toggle and the default lesson length
  (spec J1). Refused with `{:error, {:slots_in_closed_cells, [{day, count}]}}` when the
  active year's timetable has lessons in a cell the change would close.
  """
  def update_school_days(%Scope{} = scope, %{} = params) do
    with {:ok, days} <- parse_days(Map.get(params, "lesson_days", [])),
         {:ok, minutes} <- parse_minutes(params["default_lesson_minutes"]),
         wed_off? = params["wednesday_afternoon_off?"] == "true",
         cal = SchoolCalendar.new(days, wed_off?, []),
         [] <- closed_slot_counts(scope, cal),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(
        profile,
        %{
          lesson_days: if(days == SchoolCalendar.all_days(), do: nil, else: days),
          wednesday_afternoon_off?: wed_off?,
          default_lesson_minutes: minutes
        },
        scope: scope
      )
    else
      [_ | _] = counts -> {:error, {:slots_in_closed_cells, counts}}
      other -> other
    end
  end

  defp parse_days(values) when is_list(values) do
    days = values |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
    known = Map.new(SchoolCalendar.all_days(), &{Atom.to_string(&1), &1})

    cond do
      days == [] -> {:error, :invalid_setting}
      Enum.all?(days, &Map.has_key?(known, &1)) ->
        {:ok, Enum.filter(SchoolCalendar.all_days(), &(Atom.to_string(&1) in days))}
      true -> {:error, :invalid_setting}
    end
  end

  defp parse_days(_), do: {:error, :invalid_setting}

  defp parse_minutes(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n in 1..240 -> {:ok, n}
      _ -> {:error, :invalid_setting}
    end
  end

  defp parse_minutes(_), do: {:error, :invalid_setting}

  # [{day, count}] of the active year's slots in cells `cal` closes, in weekday order.
  defp closed_slot_counts(%Scope{current_academic_year: nil}, _cal), do: []

  defp closed_slot_counts(%Scope{current_academic_year: year} = scope, cal) do
    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load(:period)
    |> Ash.read!(scope: scope)
    |> Enum.reject(&SchoolCalendar.open_cell?(cal, &1.day, &1.period))
    |> Enum.frequencies_by(& &1.day)
    |> Enum.sort_by(fn {day, _} -> Enum.find_index(SchoolCalendar.all_days(), &(&1 == day)) end)
  end
```

(alias `SchoolCalendar` and `TimetableSlot` in `Attendance`; `require Ash.Query` if missing.)

- [ ] **Step 6: Run and fix the suite**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_days_test.exs` → 6 tests, 0 failures.
Then `MIX_TEST_PARTITION=2 mix test`. Tests that assumed the old preset (8 lessons, `~T[08:25:00]`, a frozen
`now` inside an old period, « Récréation » at 09:20) or created overlapping periods by hand will fail. Fix the
test data — not the behaviour — so each keeps testing what it tested (e.g. pick times inside the new periods,
or give hand-made periods distinct times); ledger one ruling per file touched.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/period.ex lib/teacher_assistant/academics/period \
  lib/teacher_assistant/academics/reference.ex lib/teacher_assistant/attendance.ex \
  test/teacher_assistant/academics/school_days_test.exs test   # only test files changed by step 6 — list them explicitly
git commit -m "feat: period overlap check, 50-minute default schedule, lesson-day settings"
```

---

### Task 4: Timetables follow the calendar

**Files:**
- Modify: `lib/teacher_assistant/timetabling.ex` (`place_slot/3`, `place_combined_slot/4`)
- Modify: `lib/teacher_assistant_web/live/school/timetable_live.ex`, `my_timetable_live.ex`,
  `lib/teacher_assistant_web/controllers/timetable_print_controller.ex` and its `show.html.heex`
- Test: `test/teacher_assistant/academics/timetables_slots_test.exs` (new tests), `test/teacher_assistant_web/live/school/timetable_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.school_calendar/1`, `SchoolCalendar.open_cell?/3`.
- Produces: `{:error, :closed_cell}` from both place functions; assigns `days` (lesson days) and `calendar` in
  the timetable LiveViews and print controller.

- [ ] **Step 1: Write the failing tests**

Add to `timetables_slots_test.exs` (its setup builds periods, a class `cg` and an assignment; read it and use its
names):

```elixir
  describe "school calendar (spec J1)" do
    test "a closed cell or an unticked day refuses a lesson", ctx do
      %{scope: scope, cg: cg} = ctx
      tc = ctx.tc
      periods = TeacherAssistant.Attendance.list_periods(scope)
      late = Enum.find(periods, &(&1.kind == :lesson and Time.compare(&1.start_time, ~T[13:00:00]) != :lt))

      {:ok, _} =
        TeacherAssistant.Attendance.update_school_days(scope, %{
          "lesson_days" => ~w(monday tuesday wednesday thursday friday),
          "wednesday_afternoon_off?" => "true",
          "default_lesson_minutes" => "50"
        })

      assert {:error, :closed_cell} =
               TeacherAssistant.Timetabling.place_slot(scope, cg, %{day: :wednesday, period_id: late.id, teaching_context_id: tc.id})

      assert {:error, :closed_cell} =
               TeacherAssistant.Timetabling.place_slot(scope, cg, %{day: :saturday, period_id: late.id, teaching_context_id: tc.id})

      assert {:ok, _} =
               TeacherAssistant.Timetabling.place_slot(scope, cg, %{day: :thursday, period_id: late.id, teaching_context_id: tc.id})
    end
  end
```

Add to `timetable_live_test.exs`:

```elixir
  test "the grid shows lesson days only and greys Wednesday afternoon (spec J1)", %{conn: conn} = ctx do
    {:ok, _} =
      TeacherAssistant.Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday),
        "wednesday_afternoon_off?" => "true",
        "default_lesson_minutes" => "50"
      })

    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/timetable")
    refute has_element?(view, "th", "Samedi")
    late = Enum.find(TeacherAssistant.Attendance.list_periods(ctx.scope), &(&1.kind == :lesson and Time.compare(&1.start_time, ~T[13:00:00]) != :lt))
    assert has_element?(view, "#cell-wednesday-#{late.id}.closed-cell")
    refute has_element?(view, "#place-wednesday-#{late.id}")
  end
```

(Use the file's own setup names for the scope, class and route; if the file has no periods with an afternoon
lesson, build the default schedule in the test with `Attendance.build_default_periods/1`.)

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/timetables_slots_test.exs test/teacher_assistant_web/live/school/timetable_live_test.exs`
Expected: FAIL — slots placed / Saturday column present.

- [ ] **Step 3: Refuse closed cells**

In `Timetabling.place_slot/3`, after `{:ok, %Period{} = period} <- Ash.get(Period, period_id, scope: scope)`
(bind the period), add:

```elixir
         :open <- open_or_closed(scope, day, period),
```

and in `else`, before `_ -> {:error, :invalid}`, add `:closed -> {:error, :closed_cell}`. Same in
`place_combined_slot/4` before its clash checks (read the period once). Helper:

```elixir
  defp open_or_closed(scope, day, period) do
    if SchoolCalendar.open_cell?(Attendance.school_calendar(scope), day, period), do: :open, else: :closed
  end
```

(alias `TeacherAssistant.Attendance` and `TeacherAssistant.Academics.SchoolCalendar`.)

- [ ] **Step 4: Grids**

In `TimetableLive`, `MyTimetableLive` and `TimetablePrintController`: drop the `@days` constant; assign
`calendar = Attendance.school_calendar(scope)` and `days: calendar.lesson_days`. In each grid cell, when
`not SchoolCalendar.open_cell?(@calendar, day, period)`, render

```heex
<td id={"cell-#{day}-#{period.id}"} class="closed-cell bg-base-200/60 text-center text-xs text-base-content/50">
  {gettext("Libre")}
</td>
```

instead of the placement form (TimetableLive) or the slot (MyTimetableLive, print). In `TimetableLive`, handle
`{:error, :closed_cell}` in both `place_cell` clauses with
`put_flash(socket, :error, gettext("Ce créneau est fermé (jour sans cours ou mercredi après-midi)."))`.

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics test/teacher_assistant_web/live/school/timetable_live_test.exs test/teacher_assistant_web/live/school/my_timetable_live_test.exs test/teacher_assistant_web/controllers/timetable_print_controller_test.exs`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/timetabling.ex lib/teacher_assistant_web/live/school/timetable_live.ex \
  lib/teacher_assistant_web/live/school/my_timetable_live.ex lib/teacher_assistant_web/controllers/timetable_print_controller.ex \
  lib/teacher_assistant_web/controllers/timetable_print_html/show.html.heex \
  test/teacher_assistant/academics/timetables_slots_test.exs test/teacher_assistant_web/live/school/timetable_live_test.exs
git commit -m "feat: timetables show lesson days only and refuse closed cells"
```

---

### Task 5: Day views expect no roll call on days off

**Files:**
- Modify: `lib/teacher_assistant/academics/school_life.ex`, `lib/teacher_assistant/attendance.ex` (`day_off/2`),
  `lib/teacher_assistant_web/live/school/day_live.ex`, `my_day_live.ex`
- Test: `test/teacher_assistant/academics/school_life_test.exs` (new describe), `test/teacher_assistant_web/live/school/school_life_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.school_calendar/1`, `Organization.create_holiday/3`, `SchoolCalendar.lesson_day?/2`, `holiday_on/2`, `open_cell?/3`.
- Produces: `Attendance.day_off(scope, Date) :: nil | {:holiday, label} | :no_lessons`; `school_day/3`,
  `teacher_day/4` return no rows/slots on days off; `teacher_missed_this_week/4` skips days off and closed cells.

- [ ] **Step 1: Write the failing tests**

Read `school_life_test.exs`'s setup (it uses `@monday ~D[2025-09-15]`, a slot on `:monday` at period `p1`, and
`at(date, time)`). Add:

```elixir
  describe "school calendar (spec J1)" do
    test "a holiday expects no roll call", ctx do
      {:ok, _} =
        TeacherAssistant.Organization.create_holiday(ctx.scope, ctx.scope.current_academic_year, %{
          label: "Journée pédagogique",
          start_date: @monday,
          end_date: @monday
        })

      late = at(@monday, ~T[23:00:00])
      assert Attendance.school_day(ctx.scope, @monday, late).rows == []
      assert Attendance.school_day(ctx.scope, @monday, late).missed == []
      assert Attendance.teacher_day(ctx.scope, ctx.head, @monday, late) == []
      assert Attendance.day_off(ctx.scope, @monday) == {:holiday, "Journée pédagogique"}

      tuesday = Date.add(@monday, 1)
      assert Attendance.teacher_missed_this_week(ctx.scope, ctx.head, tuesday, at(tuesday, ~T[08:00:00])) == []
    end

    test "an unticked weekday is a day without lessons", ctx do
      {:ok, _} =
        Attendance.update_school_days(ctx.scope, %{"lesson_days" => ~w(tuesday wednesday), "default_lesson_minutes" => "50"})
      |> case do
        {:error, {:slots_in_closed_cells, _}} ->
          # The setup's Monday slot blocks closing Monday: clear it first.
          :ok = TeacherAssistant.Timetabling.clear_slot(ctx.scope, ctx.cg, :monday, ctx.p1.id)
          Attendance.update_school_days(ctx.scope, %{"lesson_days" => ~w(tuesday wednesday), "default_lesson_minutes" => "50"})

        other ->
          other
      end

      assert Attendance.day_off(ctx.scope, @monday) == :no_lessons
      assert Attendance.day_off(ctx.scope, Date.add(@monday, 1)) == nil
    end
  end
```

(Use the setup's actual names for the head user, class and period; if the setup's user key differs from
`head`, adapt — that is the only allowed change.)

Add to `school_life_live_test.exs` a test that, with a holiday on today's date (`Reference.today()` is frozen at
2025-09-15), `/school/day` and `/school/today` show « Jour férié : Journée pédagogique » (create the holiday with
`Organization.create_holiday/3` on the test's scope and active year).

- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs`
Expected: FAIL — rows present / `day_off/2` undefined.

- [ ] **Step 3: Implement**

`Attendance`:

```elixir
  @doc "Why `date` has no lessons: `{:holiday, label}`, `:no_lessons`, or nil (a lesson day)."
  def day_off(%Scope{} = scope, %Date{} = date) do
    cal = school_calendar(scope)

    case SchoolCalendar.holiday_on(cal, date) do
      %{label: label} -> {:holiday, label}
      nil -> if SchoolCalendar.lesson_day?(cal, date), do: nil, else: :no_lessons
    end
  end
```

`SchoolLife`: build `cal = Attendance.school_calendar(scope)` once per public call.
- `school_day/3`: if `not SchoolCalendar.lesson_day?(cal, date)`, use `slots = []`; otherwise keep only
  `Enum.filter(slots, &SchoolCalendar.open_cell?(cal, &1.day, &1.period))`.
- `teacher_day/4`: same.
- `teacher_missed_this_week/4`: `dates = Enum.filter(dates, &SchoolCalendar.lesson_day?(cal, &1))`, and filter
  the slots with `open_cell?` before building cells.

`DayLive` and `MyDayLive`: assign `day_off: Attendance.day_off(scope, today)`; the empty state's title becomes:

```elixir
  defp no_lessons_title({:holiday, label}), do: gettext("Jour férié : %{label}", label: label)
  defp no_lessons_title(_), do: gettext("Pas de cours aujourd'hui")
```

- [ ] **Step 4: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/academics/school_life.ex lib/teacher_assistant/attendance.ex \
  lib/teacher_assistant_web/live/school/day_live.ex lib/teacher_assistant_web/live/school/my_day_live.ex \
  test/teacher_assistant/academics/school_life_test.exs test/teacher_assistant_web/live/school/school_life_live_test.exs
git commit -m "feat: day views expect no roll call on holidays, days without lessons and closed cells"
```

---

### Task 6: Screens — « Horaires » and « Congés & jours fériés »

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/periods_live.ex`
- Create: `lib/teacher_assistant_web/live/school/holidays_live.ex`
- Modify: `router.ex` (after `live "/school/settings/bulletin", …`), `spaces.ex`, `live/school/settings_live.ex`
- Test: `test/teacher_assistant_web/live/school/periods_live_test.exs` (new tests), `test/teacher_assistant_web/live/school/holidays_live_test.exs`

**Interfaces:**
- Consumes: `Attendance.update_school_days/2`, `create_period/2`, `school_calendar/1`; `Organization` holiday functions; profile `default_lesson_minutes`.
- Produces: DOM ids `#days-form`, `#new-period-form`, `#days-error`, `#new-period-error`; holidays page
  `#holidays-table`, `#holiday-form`, `#holiday-row-<id>`, `#delete-holiday-<id>`, `#prefill-holidays`,
  `#holiday-error`; link `#holidays-link`; route `/school/settings/holidays`.

- [ ] **Step 1: Write the failing tests**

Add to `periods_live_test.exs` (its setup logs in a head with a school; read it):

```elixir
  describe "Horaires (spec J1)" do
    test "the page is titled Horaires and saves the lesson days", %{conn: conn, scope: scope} do
      {:ok, view, html} = live(conn, ~p"/school/periods")
      assert html =~ "Horaires"

      view
      |> form("#days-form", %{days: %{lesson_days: ["monday", "tuesday", "wednesday", "thursday", "friday"], "wednesday_afternoon_off?" => "true", default_lesson_minutes: "50"}})
      |> render_submit()

      assert render(view) =~ "Réglage enregistré."
      assert TeacherAssistant.Attendance.school_calendar(scope).wednesday_afternoon_off?
    end

    test "adding a period pre-fills the end from the default length", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/school/periods")
      view |> form("#new-period-form", %{new_period: %{start_time: "16:00"}}) |> render_change()
      assert has_element?(view, "#new-period-form input[name='new_period[end_time]'][value='16:50']")

      view
      |> form("#new-period-form", %{new_period: %{label: "Cours 10", start_time: "16:00", end_time: "16:50", kind: "lesson"}})
      |> render_submit()

      assert Enum.any?(TeacherAssistant.Attendance.list_periods(scope), &(&1.label == "Cours 10"))
    end

    test "an overlapping period shows the error", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/school/periods")
      view |> element("#seed-periods") |> render_click()

      view
      |> form("#new-period-form", %{new_period: %{label: "X", start_time: "08:00", end_time: "08:30", kind: "lesson"}})
      |> render_submit()

      assert has_element?(view, "#new-period-error", "Chevauche")
    end
  end
```

`test/teacher_assistant_web/live/school/holidays_live_test.exs`:

```elixir
defmodule TeacherAssistantWeb.School.HolidaysLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Organization, TeacherFixtures}

  setup :register_and_log_in_user

  # register_and_log_in_user builds a complete school, with its active year (prefilled on creation).
  setup %{scope: scope} do
    %{year: Organization.current_academic_year(scope)}
  end

  test "settings links to the page, which lists the prefilled holidays", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#holidays-link")
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    assert has_element?(view, "#holidays-table", "Fête nationale")
  end

  test "adds, then deletes a holiday; a bad range shows the error", %{conn: conn, scope: scope, year: year} do
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")

    view
    |> form("#holiday-form", %{holiday: %{label: "Congés de Noël", start_date: "2025-12-19", end_date: "2026-01-04"}})
    |> render_submit()

    h = scope |> Organization.list_holidays(year) |> Enum.find(&(&1.label == "Congés de Noël"))
    assert has_element?(view, "#holiday-row-#{h.id}")

    view |> element("#delete-holiday-#{h.id}") |> render_click()
    refute has_element?(view, "#holiday-row-#{h.id}")

    view
    |> form("#holiday-form", %{holiday: %{label: "X", start_date: "2026-01-04", end_date: "2025-12-19"}})
    |> render_submit()

    assert has_element?(view, "#holiday-error")
  end

  test "Préremplir adds back a deleted national holiday", %{conn: conn, scope: scope, year: year} do
    [first | _] = Organization.list_holidays(scope, year)
    :ok = Organization.delete_holiday(scope, first)
    {:ok, view, _} = live(conn, ~p"/school/settings/holidays")
    view |> element("#prefill-holidays") |> render_click()
    assert length(Organization.list_holidays(scope, year)) == 7
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/holidays")
  end
end
```


- [ ] **Step 2: Run to verify they fail**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/periods_live_test.exs test/teacher_assistant_web/live/school/holidays_live_test.exs`
Expected: FAIL — no `#days-form` / no route.

- [ ] **Step 3: « Horaires »**

In `PeriodsLive`:
- `mount`: also assign `calendar: Attendance.school_calendar(scope)`, `minutes` (profile `default_lesson_minutes`),
  `new_period: %{"label" => "", "start_time" => "", "end_time" => "", "kind" => "lesson"}`,
  `days_error: nil`, `new_period_error: nil`.
- Title: `gettext("Horaires")` (eyebrow stays « École »).
- Above the table, the days form:

```heex
<.form for={%{}} as={:days} id="days-form" phx-submit="save_days"
       class="space-y-3 rounded-box border border-base-300 bg-base-100 p-4">
  <input type="hidden" name="days[lesson_days][]" value="" />
  <div class="flex flex-wrap gap-3">
    <label :for={day <- SchoolCalendar.all_days()} class="flex items-center gap-1.5 text-sm">
      <input type="checkbox" name="days[lesson_days][]" value={day}
             checked={day in @calendar.lesson_days} class="checkbox checkbox-sm" />
      {DayOfWeek.label(day)}
    </label>
  </div>
  <.input type="checkbox" name="days[wednesday_afternoon_off?]" value="true"
          checked={@calendar.wednesday_afternoon_off?}
          label={gettext("Mercredi après-midi libre (périodes à partir de 13 h)")} />
  <.input name="days[default_lesson_minutes]" value={@minutes} inputmode="numeric"
          label={gettext("Durée par défaut d'une heure de cours (min)")} class="input input-sm w-24 text-right" />
  <p :if={@days_error} id="days-error" class="text-sm text-error">{@days_error}</p>
  <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
</.form>
```

- Below the table, the add row:

```heex
<.form for={%{}} as={:new_period} id="new-period-form" phx-change="change_new_period"
       phx-submit="create_period" class="grid items-end gap-2 sm:grid-cols-5">
  <.input name="new_period[label]" value={@new_period["label"]} label={gettext("Libellé")} />
  <.input name="new_period[start_time]" type="time" value={@new_period["start_time"]} label={gettext("Début")} />
  <.input name="new_period[end_time]" type="time" value={@new_period["end_time"]} label={gettext("Fin")} />
  <.input name="new_period[kind]" type="select" value={@new_period["kind"]} label={gettext("Type")}
          options={[{PeriodKind.label(:lesson), "lesson"}, {PeriodKind.label(:break), "break"}]} />
  <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter une période")}</button>
  <p :if={@new_period_error} id="new-period-error" class="text-sm text-error sm:col-span-5">{@new_period_error}</p>
</.form>
```

- Events:

```elixir
  def handle_event("save_days", %{"days" => params}, socket) do
    scope = socket.assigns.scope

    case Attendance.update_school_days(scope, params) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(calendar: Attendance.school_calendar(scope), minutes: profile.default_lesson_minutes, days_error: nil)
         |> put_flash(:info, gettext("Réglage enregistré."))}

      {:error, {:slots_in_closed_cells, counts}} ->
        detail = Enum.map_join(counts, ", ", fn {day, n} -> "#{n} #{String.downcase(DayOfWeek.label(day))}" end)

        {:noreply,
         assign(socket,
           days_error:
             gettext("Des cours sont placés sur les créneaux fermés (%{detail}) : retirez-les de l'emploi du temps d'abord.",
               detail: detail
             )
         )}

      {:error, :invalid_setting} ->
        {:noreply, assign(socket, days_error: gettext("Choisissez au moins un jour et une durée entre 1 et 240 minutes."))}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, assign(socket, days_error: gettext("Réglage non enregistré."))}
    end
  end

  def handle_event("change_new_period", %{"new_period" => params}, socket) do
    params = Map.merge(socket.assigns.new_period, params)

    params =
      with "" <- params["end_time"],
           {:ok, start} <- Time.from_iso8601(params["start_time"] <> ":00") do
        end_time = start |> Time.add(socket.assigns.minutes * 60) |> Calendar.strftime("%H:%M")
        Map.put(params, "end_time", end_time)
      else
        _ -> params
      end

    {:noreply, assign(socket, new_period: params)}
  end

  def handle_event("create_period", %{"new_period" => params}, socket) do
    scope = socket.assigns.scope
    position = (socket.assigns.periods |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)) + 1

    attrs =
      params
      |> normalize_period_params()
      |> Map.take(["label", "start_time", "end_time", "kind"])
      |> Map.put("position", position)

    case Attendance.create_period(scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(new_period: %{"label" => "", "start_time" => "", "end_time" => "", "kind" => "lesson"}, new_period_error: nil)
         |> load_periods()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply, assign(socket, new_period_error: Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1))))}
    end
  end
```

- The existing `update_period` error flash becomes the validation's message
  (`Enum.map_join(form errors …)`) when the form has errors other than forbidden; keep the generic text as
  fallback.
- Alias `TeacherAssistant.Academics.{DayOfWeek, SchoolCalendar}`.

- [ ] **Step 4: « Congés & jours fériés »**

`lib/teacher_assistant_web/live/school/holidays_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.HolidaysLive do
  @moduledoc """
  Settings → Congés & jours fériés (spec J1, S02): the active year's holidays, add /
  delete, and « Préremplir » for the national holidays. Admin axis.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Accounts, Organization}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         %{} = year <- scope.current_academic_year,
         {:ok, profile} <- Accounts.fetch_school_profile(scope),
         true <- Accounts.can_edit_profile?(scope, profile) do
      {:ok, socket |> assign(year: year, error: nil) |> load()}
    else
      _ -> {:ok, push_navigate(socket, to: ~p"/school/settings")}
    end
  end

  defp load(socket),
    do: assign(socket, holidays: Organization.list_holidays(socket.assigns.current_scope, socket.assigns.year))

  def handle_event("add", %{"holiday" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, s} <- Date.from_iso8601(params["start_date"] || ""),
         {:ok, e} <- Date.from_iso8601(params["end_date"] || params["start_date"] || ""),
         {:ok, _} <- Organization.create_holiday(scope, socket.assigns.year, %{label: params["label"], start_date: s, end_date: e}) do
      {:noreply, socket |> assign(error: nil) |> load() |> put_flash(:info, gettext("Jour ajouté."))}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, %Ash.Error.Invalid{errors: errors}} ->
        {:noreply, assign(socket, error: Enum.map_join(errors, " ", &(Map.get(&1, :message) || Exception.message(&1))))}
      _ -> {:noreply, assign(socket, error: gettext("Indiquez des dates valides."))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.holidays, &(&1.id == id)) do
      nil -> {:noreply, socket}
      h ->
        case Organization.delete_holiday(socket.assigns.current_scope, h) do
          :ok -> {:noreply, load(socket)}
          {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  def handle_event("prefill", _params, socket) do
    case Organization.prefill_holidays(socket.assigns.current_scope, socket.assigns.year) do
      {:ok, n} -> {:noreply, socket |> load() |> put_flash(:info, gettext("%{n} jour(s) ajouté(s).", n: n))}
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  defp days(h), do: Date.diff(h.end_date, h.start_date) + 1
  defp d(date), do: Calendar.strftime(date, "%d/%m/%Y")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="holidays" class="space-y-6">
        <.page_header eyebrow={gettext("Paramètres")} title={gettext("Congés & jours fériés")}
                      subtitle={@year.name} />

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table id="holidays-table" class="table">
            <thead>
              <tr><th>{gettext("Libellé")}</th><th>{gettext("Du")}</th><th>{gettext("Au")}</th>
                  <th class="text-right">{gettext("Jours")}</th><th></th></tr>
            </thead>
            <tbody>
              <tr :for={h <- @holidays} id={"holiday-row-#{h.id}"}>
                <td>{h.label}</td>
                <td class="ta-num">{d(h.start_date)}</td>
                <td class="ta-num">{d(h.end_date)}</td>
                <td class="ta-num text-right">{days(h)}</td>
                <td class="text-right">
                  <button id={"delete-holiday-#{h.id}"} type="button" phx-click="delete" phx-value-id={h.id}
                          class="btn btn-ghost btn-xs" data-confirm={gettext("Supprimer ce jour ?")}>
                    {gettext("Supprimer")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.form for={%{}} as={:holiday} id="holiday-form" phx-submit="add"
               class="grid items-end gap-2 rounded-box border border-base-300 bg-base-100 p-4 sm:grid-cols-4">
          <.input name="holiday[label]" value="" label={gettext("Libellé")} />
          <.input name="holiday[start_date]" type="date" value="" label={gettext("Du")} />
          <.input name="holiday[end_date]" type="date" value="" label={gettext("Au (facultatif)")} />
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Ajouter")}</button>
          <p :if={@error} id="holiday-error" class="text-sm text-error sm:col-span-4">{@error}</p>
        </.form>

        <button id="prefill-holidays" type="button" phx-click="prefill" class="btn btn-ghost btn-sm">
          {gettext("Préremplir les jours fériés nationaux")}
        </button>
      </section>
    </Layouts.app>
    """
  end
end
```

(An empty « Au » posts `""`: treat `""` as the start date — replace `params["end_date"] || params["start_date"]`
with a helper `end_param(params)` returning `params["start_date"]` when `end_date` is blank.)

Route after `live "/school/settings/bulletin", …`:
`live "/school/settings/holidays", School.HolidaysLive, :index`.
`spaces.ex`: an item `holidays` (« Congés & jours fériés », `hero-calendar`, `~p"/school/settings/holidays"`)
right after each `bulletin_template()` call; `settings_live.ex`: a `#holidays-link` link after
`#bulletin-template-link`. Rename the « Périodes » menu item (`defp periods` in `spaces.ex`) to « Horaires ».

- [ ] **Step 5: Run the tests**

Run: `MIX_TEST_PARTITION=2 mix test test/teacher_assistant_web/live/school/periods_live_test.exs test/teacher_assistant_web/live/school/holidays_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: 0 failures (update any `spaces_test` assertion on the « Périodes » label or menu ids; ledger it).

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/periods_live.ex lib/teacher_assistant_web/live/school/holidays_live.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex lib/teacher_assistant_web/live/school/settings_live.ex \
  test/teacher_assistant_web/live/school/periods_live_test.exs test/teacher_assistant_web/live/school/holidays_live_test.exs
git commit -m "feat: Horaires settings and add-a-period row; Congés & jours fériés page"
```

---

### Task 7: Translations, status, full checks

- [ ] **Step 1:** `mix gettext.extract --merge`; translate every new msgid in `en` (e.g. « Horaires » → "Timetable
  hours", « Congés & jours fériés » → "Holidays & breaks", « Jour férié : %{label} » → "Public holiday:
  %{label}", « Noël » → "Christmas", « Jour de l'an » → "New Year's Day", « Fête de la Jeunesse » → "Youth Day",
  « Vendredi saint » → "Good Friday", « Ascension » → "Ascension Day", « Fête du Travail » → "Labour Day",
  « Fête nationale » → "National Day", « Mercredi après-midi libre (périodes à partir de 13 h) » →
  "Wednesday afternoon off (periods from 1 pm)", « Chevauche %{label} (%{start}–%{end}). » → "Overlaps
  %{label} (%{start}–%{end})."); remove every new fuzzy flag in `en` and `fr`; fuzzy counts must not exceed
  main's (en 24, fr 17).
- [ ] **Step 2:** In the spec's J1 section add, before "Mockup:":
  `Status: implemented 2026-10-01 (branch \`j1-school-calendar\`, plan \`docs/superpowers/plans/2026-10-01-j1-school-calendar.md\`); no visual check done.`
- [ ] **Step 3:** `MIX_TEST_PARTITION=2 mix precommit`, `mix ash.codegen --check`, `mix compile --warnings-as-errors --force`.
  Expected: 0 failures, clean, no warnings.
- [ ] **Step 4: Commit**

```bash
git add priv/gettext docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git status --short   # stage any formatter-rewritten branch files explicitly
git commit -m "chore: J1 translations and status"
```
