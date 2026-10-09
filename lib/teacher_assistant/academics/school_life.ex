defmodule TeacherAssistant.Academics.SchoolLife do
  @moduledoc """
  School life, day view (spec G, V01–V04): which roll calls are done, missed, in
  progress or upcoming, and which absences still need a justification.

  A roll call is done when attendance entries exist for (class, period, date) —
  computed, never stored. Times are school-local (`Reference.now/1`). Every
  function runs a fixed number of queries, whatever the number of classes.
  """

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AttendanceEntry,
    Conduct,
    RollCallReminder,
    EntryProgress,
    SchoolCalendar,
    SchoolTemplates,
    TimetableSlot
  }

  alias TeacherAssistant.{Attendance, Organization, Scope}

  @days ~w(monday tuesday wednesday thursday friday saturday)a

  # --- Roll calls ---------------------------------------------------------------

  @doc """
  The school's roll calls on `date`: `rows` (classes having a slot that weekday,
  each with `cells` keyed by period id, `nil` where no slot), the lesson
  `periods`, and the `missed` roll calls (slot id, class, period, teacher, subject).
  """
  def school_day(%Scope{} = scope, %Date{} = date, %NaiveDateTime{} = now) do
    periods = lesson_periods(scope)
    slots = day_slots(scope, date, nil)
    done = done_roll_calls(scope, slots, date, date)
    cells = Enum.map(slots, &cell(&1, date, now, done))

    rows =
      cells
      |> Enum.group_by(& &1.class_group.id)
      |> Enum.map(fn {_id, [first | _] = class_cells} ->
        %{class_group: first.class_group, cells: Map.new(class_cells, &{&1.period.id, &1})}
      end)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))

    %{
      periods: periods,
      rows: rows,
      missed: cells |> Enum.filter(&(&1.status == :missed)) |> sort_cells()
    }
  end

  @doc """
  The roll-call tally of `date`: `done`, the `missed` ones and `expected`
  (`done + missed`, as `/school/day` shows it).
  """
  def roll_call_counts(%Scope{} = scope, %Date{} = date, %NaiveDateTime{} = now),
    do: roll_call_counts(school_day(scope, date, now))

  @doc "The same tally from an already loaded `school_day/3`."
  def roll_call_counts(%{rows: rows, missed: missed}) do
    done =
      Enum.count(for(row <- rows, {_id, cell} <- row.cells, do: cell.status), &(&1 == :done))

    %{done: done, expected: done + length(missed), missed: missed}
  end

  @doc "How many late arrivals were recorded on `date` (Vie scolaire redesign §2.1)."
  def late_count(%Scope{} = scope, %Date{} = date) do
    AttendanceEntry
    |> Ash.Query.filter(date == ^date and status == :late)
    |> Ash.count!(scope: scope)
  end

  @doc """
  « Relancer » (Vie scolaire redesign §1.1): notifies the teacher of the slot
  whose roll call was not taken on `date`. Once per slot and day:
  `{:error, :already_reminded}` after that.
  """
  def remind_roll_call(%Scope{} = scope, slot_id, %Date{} = date) do
    with {:ok, slot} <-
           Ash.get(TimetableSlot, slot_id,
             scope: scope,
             load: [:period, :class_group, teaching_context: [:catalog_subject]]
           ),
         false <- MapSet.member?(reminded_slot_ids(scope, date), slot.id) do
      remind_in_transaction(scope, slot, date)
    else
      true -> {:error, :already_reminded}
      error -> error
    end
  end

  # The log row and the notification together: a failed delivery leaves no
  # « Relancé » behind that would refuse every retry. The unique index still
  # refuses a reminder racing another one.
  defp remind_in_transaction(scope, slot, date) do
    TeacherAssistant.Repo.transaction(fn ->
      case create_reminder(scope, slot, date) do
        {:ok, reminder} ->
          tc = slot.teaching_context

          TeacherAssistant.Notifications.deliver(
            scope,
            :roll_call_reminder,
            Enum.reject([tc.teacher_user_id], &(is_nil(&1) or &1 == scope.current_user.id)),
            %{
              class: slot.class_group.label,
              time: Calendar.strftime(slot.period.start_time, "%H:%M"),
              subject: subject_label(tc)
            },
            "/school/today"
          )

          reminder

        {:error, reason} ->
          TeacherAssistant.Repo.rollback(reason)
      end
    end)
  end

  @doc "The slots reminded with « Relancer » on `date` (a MapSet of slot ids)."
  def reminded_slot_ids(%Scope{} = scope, %Date{} = date) do
    RollCallReminder
    |> Ash.Query.for_read(:on_date, %{date: date}, scope: scope)
    |> Ash.read!()
    |> MapSet.new(& &1.timetable_slot_id)
  end

  defp create_reminder(scope, slot, date) do
    RollCallReminder
    |> Ash.Changeset.for_create(:create, %{timetable_slot_id: slot.id, date: date}, scope: scope)
    |> Ash.create()
  end

  @doc "The user's slots on `date`, sorted by period, with the same statuses as `school_day/3`."
  def teacher_day(%Scope{} = scope, user, %Date{} = date, %NaiveDateTime{} = now) do
    slots = day_slots(scope, date, user.id)
    done = done_roll_calls(scope, slots, date, date)
    slots |> Enum.map(&cell(&1, date, now, done)) |> sort_cells()
  end

  @doc """
  The user's roll calls not done this week, from Monday (never before the active
  year's start) to yesterday — today's are in `teacher_day/4`.
  """
  def teacher_missed_this_week(%Scope{} = scope, user, %Date{} = today, %NaiveDateTime{} = now) do
    monday = Date.beginning_of_week(today)
    year = scope.current_academic_year

    first =
      if year && Date.compare(year.start_date, monday) == :gt, do: year.start_date, else: monday

    cal = Attendance.school_calendar(scope)

    dates =
      Date.range(first, Date.add(today, -1), 1)
      |> Enum.filter(&SchoolCalendar.lesson_day?(cal, &1))

    case dates do
      [] ->
        []

      dates ->
        slots =
          scope
          |> slots(dates |> Enum.map(&weekday/1) |> Enum.uniq(), user.id)
          |> Enum.filter(&SchoolCalendar.open_cell?(cal, &1.day, &1.period))

        done = done_roll_calls(scope, slots, first, List.last(dates))
        slots_by_day = Enum.group_by(slots, & &1.day)

        for date <- dates,
            slot <- Map.get(slots_by_day, weekday(date), []),
            cell = cell(slot, date, now, done),
            cell.status == :missed,
            do: cell
    end
  end

  # Spec J1: no roll call is expected on a day off, nor in a closed cell.
  defp day_slots(scope, date, teacher_id) do
    cal = Attendance.school_calendar(scope)

    if SchoolCalendar.lesson_day?(cal, date) do
      scope
      |> slots([weekday(date)], teacher_id)
      |> Enum.filter(&SchoolCalendar.open_cell?(cal, &1.day, &1.period))
    else
      []
    end
  end

  defp cell(slot, date, now, done) do
    start = NaiveDateTime.new!(date, slot.period.start_time)
    finish = NaiveDateTime.new!(date, slot.period.end_time)

    {status, absent} =
      case Map.fetch(done, {slot.class_group_id, slot.period_id, date}) do
        {:ok, absent} -> {:done, absent}
        :error -> {status(start, finish, now), 0}
      end

    tc = slot.teaching_context

    %{
      slot_id: slot.id,
      date: date,
      period: slot.period,
      class_group: slot.class_group,
      teacher: tc && tc.teacher,
      subject: tc && subject_label(tc),
      status: status,
      absent: absent
    }
  end

  defp status(start, finish, now) do
    cond do
      NaiveDateTime.compare(now, start) == :lt -> :upcoming
      NaiveDateTime.compare(now, finish) == :lt -> :in_progress
      true -> :missed
    end
  end

  defp sort_cells(cells) do
    Enum.sort_by(
      cells,
      &{Date.to_gregorian_days(&1.date), &1.period.position,
       SchoolTemplates.class_sort_key(&1.class_group)}
    )
  end

  defp subject_label(%{catalog_subject: %{name: name}}), do: name
  defp subject_label(tc), do: tc.subject

  # --- Absences -----------------------------------------------------------------

  @doc """
  One row per student-day between `first` and `last` with at least one `:absent`
  entry: student, class, main guardian (or nil), periods and their `minutes`,
  whether justified (and why), the student's unjustified absence hours in the
  current séquence and the V04 flag. Flagged students first, then newest day.
  """
  def absence_days(%Scope{} = scope, %Date{} = first, %Date{} = last, %Date{} = today) do
    rules = Attendance.school_life_rules(scope)
    calendar = Attendance.school_calendar(scope)
    alert = Decimal.new(rules.absence_alert_hours)
    unjustified = unjustified_hours(scope, today, rules)
    zero = Decimal.new(0)

    AttendanceEntry
    |> absences_between(first, last, rules.late_as_absence_minutes)
    |> Ash.Query.load([
      :period,
      enrollment: [:class_group, student: [primary_guardian_link: :guardian]]
    ])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&{&1.enrollment_id, &1.date})
    |> Enum.map(fn {{enrollment_id, date}, [entry | _] = entries} ->
      hours = Map.get(unjustified, enrollment_id, zero)
      justified = Enum.find(entries, & &1.justified)
      justified? = Enum.all?(entries, & &1.justified)
      periods = entries |> Enum.map(& &1.period) |> Enum.sort_by(& &1.position)

      %{
        id: "#{enrollment_id}-#{Date.to_iso8601(date)}",
        enrollment: entry.enrollment,
        student: entry.enrollment.student,
        class_group: entry.enrollment.class_group,
        date: date,
        periods: periods,
        minutes: Enum.sum_by(periods, &div(Time.diff(&1.end_time, &1.start_time), 60)),
        guardian: main_guardian(entry.enrollment.student),
        justified?: justified?,
        reason: justified && justified.justification_reason,
        unjustified_hours: hours,
        flagged?: Decimal.compare(hours, alert) != :lt,
        overdue?:
          not justified? and overdue?(date, today, rules.justification_deadline_days, calendar)
      }
    end)
    |> Enum.sort_by(
      &{not &1.flagged?, -Date.to_gregorian_days(&1.date),
       SchoolTemplates.class_sort_key(&1.class_group), String.downcase(&1.student.full_name)}
    )
  end

  defp main_guardian(%{primary_guardian_link: %{guardian: guardian}}), do: guardian
  defp main_guardian(_student), do: nil

  # Absences, and lates long enough to count as one (spec KLM2).
  defp absences_between(query, first, last, nil),
    do: Ash.Query.filter(query, status == :absent and date >= ^first and date <= ^last)

  defp absences_between(query, first, last, threshold),
    do:
      Ash.Query.filter(
        query,
        (status == :absent or (status == :late and late_minutes > ^threshold)) and
          date >= ^first and date <= ^last
      )

  @doc "The current séquence's date range up to `today` (`nil` without one)."
  def current_sequence_range(%Scope{current_academic_year: nil}, _today), do: nil

  def current_sequence_range(%Scope{} = scope, %Date{} = today) do
    case EntryProgress.default_sequence(
           Organization.list_sequences(scope, scope.current_academic_year),
           today
         ) do
      nil -> nil
      seq -> {seq.start_date, Enum.min([seq.end_date, today], Date)}
    end
  end

  # enrollment_id => unjustified absence hours in the current séquence (a long
  # late counts, spec KLM2).
  defp unjustified_hours(scope, today, rules) do
    case current_sequence_range(scope, today) do
      nil ->
        %{}

      {first, last} ->
        AttendanceEntry
        |> Ash.Query.filter(
          status in [:absent, :late] and justified == false and date >= ^first and date <= ^last
        )
        |> Ash.Query.load(:period)
        |> Ash.read!(scope: scope)
        |> Enum.group_by(& &1.enrollment_id)
        |> Map.new(fn {id, entries} ->
          {id, Conduct.totals(entries, rules.late_as_absence_minutes).unjustified_hours}
        end)
    end
  end

  @doc """
  Whether an absence on `date` is past the justification deadline on `today`:
  more than `deadline` lesson days (holidays and days without lessons skipped)
  since it. A nil deadline means any time.
  """
  def overdue?(_date, _today, nil, _calendar), do: false

  def overdue?(%Date{} = date, %Date{} = today, deadline, %SchoolCalendar{} = calendar) do
    Date.compare(today, date) == :gt and
      date
      |> Date.add(1)
      |> Date.range(today)
      |> Enum.count(&SchoolCalendar.lesson_day?(calendar, &1)) > deadline
  end

  # --- Queries ------------------------------------------------------------------

  defp lesson_periods(scope),
    do: scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

  # Active year's lesson slots on `days`, optionally one teacher's.
  defp slots(%Scope{current_academic_year: nil}, _days, _teacher_id), do: []

  defp slots(%Scope{} = scope, days, teacher_id) do
    case Enum.reject(days, &is_nil/1) do
      [] -> []
      days -> read_slots(scope, days, teacher_id)
    end
  end

  defp read_slots(scope, days, teacher_id) do
    year_id = scope.current_academic_year.id

    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year_id and day in ^days)
    |> then(fn query ->
      if teacher_id,
        do: Ash.Query.filter(query, teaching_context.teacher_user_id == ^teacher_id),
        else: query
    end)
    |> Ash.Query.load([:period, :class_group, teaching_context: [:teacher, :catalog_subject]])
    |> Ash.read!(scope: scope)
    |> Enum.filter(&(&1.period.kind == :lesson))
  end

  # {class_group_id, period_id, date} => number of :absent entries, for roll calls done.
  defp done_roll_calls(_scope, [], _first, _last), do: %{}

  defp done_roll_calls(scope, slots, first, last) do
    class_ids = slots |> Enum.map(& &1.class_group_id) |> Enum.uniq()

    AttendanceEntry
    |> Ash.Query.filter(
      date >= ^first and date <= ^last and enrollment.class_group_id in ^class_ids
    )
    |> Ash.Query.load(:enrollment)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&{&1.enrollment.class_group_id, &1.period_id, &1.date})
    |> Map.new(fn {key, entries} -> {key, Enum.count(entries, &(&1.status == :absent))} end)
  end

  defp weekday(%Date{} = date), do: Enum.at(@days, Date.day_of_week(date) - 1)
end
