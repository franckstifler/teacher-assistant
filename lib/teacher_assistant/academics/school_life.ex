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
    EntryProgress,
    SchoolCalendar,
    SchoolTemplates,
    TimetableSlot
  }

  alias TeacherAssistant.{Attendance, Organization, Scope}

  @doc "Distinct days with an unjustified absence in the séquence from which a student is flagged (V04)."
  def repeated_absence_threshold, do: 3

  @days ~w(monday tuesday wednesday thursday friday saturday)a

  # --- Roll calls ---------------------------------------------------------------

  @doc """
  The school's roll calls on `date`: `rows` (classes having a slot that weekday,
  each with `cells` keyed by period id, `nil` where no slot), the lesson
  `periods`, and the `missed` roll calls (class, period, teacher, subject).
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
  entry: student, class, periods, whether justified (and why), the student's
  unjustified days in the current séquence and the V04 flag. Flagged students
  first, then newest day.
  """
  def absence_days(%Scope{} = scope, %Date{} = first, %Date{} = last, %Date{} = today) do
    unjustified = unjustified_days(scope, today)

    AttendanceEntry
    |> Ash.Query.filter(status == :absent and date >= ^first and date <= ^last)
    |> Ash.Query.load([:period, enrollment: [:student, :class_group]])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&{&1.enrollment_id, &1.date})
    |> Enum.map(fn {{enrollment_id, date}, [entry | _] = entries} ->
      days = Map.get(unjustified, enrollment_id, 0)
      justified = Enum.find(entries, & &1.justified)

      %{
        id: "#{enrollment_id}-#{Date.to_iso8601(date)}",
        enrollment: entry.enrollment,
        student: entry.enrollment.student,
        class_group: entry.enrollment.class_group,
        date: date,
        periods: entries |> Enum.map(& &1.period) |> Enum.sort_by(& &1.position),
        justified?: Enum.all?(entries, & &1.justified),
        reason: justified && justified.justification_reason,
        unjustified_days: days,
        flagged?: days >= repeated_absence_threshold()
      }
    end)
    |> Enum.sort_by(
      &{not &1.flagged?, -Date.to_gregorian_days(&1.date),
       SchoolTemplates.class_sort_key(&1.class_group), String.downcase(&1.student.full_name)}
    )
  end

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

  # enrollment_id => distinct days with an unjustified absence in the séquence.
  defp unjustified_days(scope, today) do
    case current_sequence_range(scope, today) do
      nil ->
        %{}

      {first, last} ->
        AttendanceEntry
        |> Ash.Query.filter(
          status == :absent and justified == false and date >= ^first and date <= ^last
        )
        |> Ash.Query.select([:enrollment_id, :date])
        |> Ash.read!(scope: scope)
        |> Enum.uniq_by(&{&1.enrollment_id, &1.date})
        |> Enum.frequencies_by(& &1.enrollment_id)
    end
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
