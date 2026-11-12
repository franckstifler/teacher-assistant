defmodule TeacherAssistant.Academics.SchoolLife do
  @moduledoc """
  School life, day view (spec G, V01–V04): which roll calls are done, missed, in
  progress or upcoming, and which absences still need a justification.

  A roll call is done when attendance entries exist for (class, period, date) —
  computed, never stored. A class on paper (spec 2026-10-28) shows an untaken lesson
  as `:on_paper` until its sheet is due, and a lesson marked « cours non assuré » as
  `:not_held` (`PaperRollCall.state/5`). Times are school-local (`Reference.now/1`). Every
  function runs a fixed number of queries, whatever the number of classes.
  """

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AttendanceEntry,
    ClassGroup,
    Conduct,
    LessonNotHeld,
    PaperRollCall,
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
    marks = lesson_marks(scope, slots, date, date, entries: held_entries(scope, date, :all))
    cells = Enum.map(slots, &cell(&1, date, now, marks))

    # Spec 2026-11-12: a lesson held outside its slot sits in the grid at its real
    # period; after the slot cells, so it replaces a « pris par » cell of a swap.
    rows =
      (cells ++ moved_cells(slots, date, marks))
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
  The roll-call tally of `date`: `done`, `on_paper` (waiting for their sheet), the
  `missed` ones and `expected` (`done + on_paper + missed`, as `/school/day` shows it).
  Lessons not held are in none of them.
  """
  def roll_call_counts(%Scope{} = scope, %Date{} = date, %NaiveDateTime{} = now),
    do: roll_call_counts(school_day(scope, date, now))

  @doc "The same tally from an already loaded `school_day/3`."
  def roll_call_counts(%{rows: rows, missed: missed}) do
    statuses = for row <- rows, {_id, cell} <- row.cells, do: cell.status
    done = Enum.count(statuses, &(&1 == :done))
    on_paper = Enum.count(statuses, &(&1 == :on_paper))

    %{done: done, on_paper: on_paper, expected: done + on_paper + length(missed), missed: missed}
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
            "/school/classes/#{slot.class_group_id}/attendance/#{slot.period_id}?date=#{date}"
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

    marks =
      lesson_marks(scope, slots, date, date,
        entries: held_entries(scope, date, {:teacher, user.id})
      )

    moved =
      slots |> moved_cells(date, marks) |> Enum.filter(&(&1.teacher && &1.teacher.id == user.id))

    (Enum.map(slots, &cell(&1, date, now, marks)) ++ moved) |> sort_cells()
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

        marks = lesson_marks(scope, slots, first, List.last(dates))
        slots_by_day = Enum.group_by(slots, & &1.day)

        for date <- dates,
            slot <- Map.get(slots_by_day, weekday(date), []),
            cell = cell(slot, date, now, marks),
            cell.status == :missed,
            do: cell
    end
  end

  @doc """
  One class's lessons from `first` to `last` (lesson days and open cells only), as
  cells with the same statuses as `school_day/3`, sorted by date and period.
  """
  def class_lessons(%Scope{} = scope, %ClassGroup{} = cg, %Date{} = first, %Date{} = last, now) do
    cal = Attendance.school_calendar(scope)
    dates = first |> Date.range(last, 1) |> Enum.filter(&SchoolCalendar.lesson_day?(cal, &1))

    slots =
      scope
      |> slots(dates |> Enum.map(&weekday/1) |> Enum.uniq(), nil, cg.id)
      |> Enum.filter(&SchoolCalendar.open_cell?(cal, &1.day, &1.period))

    marks = lesson_marks(scope, slots, first, last, class_group_id: cg.id)
    slots_by_day = Enum.group_by(slots, & &1.day)

    for(
      date <- dates,
      slot <- Map.get(slots_by_day, weekday(date), []),
      do: cell(slot, date, now, marks)
    )
    |> sort_cells()
  end

  # Spec 2026-11-12: lessons held outside their slot are read on lesson days only —
  # a day off expects no roll call, moved or not (spec J1).
  defp held_entries(scope, date, entries) do
    if SchoolCalendar.lesson_day?(Attendance.school_calendar(scope), date),
      do: entries,
      else: :slot_classes
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

  defp cell(slot, date, now, %{done: done, not_held: not_held}) do
    start = NaiveDateTime.new!(date, slot.period.start_time)
    finish = NaiveDateTime.new!(date, slot.period.end_time)
    key = {slot.class_group_id, slot.period_id, date}

    # Spec 2026-11-12: a roll call under the slot's own context (or none, the
    # surveillant's) is the slot's; under another context, the slot is « pris par ».
    {status, absent, covered_by} =
      case Map.fetch(done, key) do
        {:ok, %{context_id: cid} = roll} when is_nil(cid) or cid == slot.teaching_context_id ->
          {:done, roll.absent, nil}

        {:ok, roll} ->
          {:covered, 0, %{teacher: roll.teacher, subject: roll.subject}}

        :error ->
          {status(start, finish, now), 0, nil}
      end

    marking = Map.get(not_held, key)

    status =
      PaperRollCall.state(
        status,
        slot.class_group.paper_roll_call,
        marking != nil,
        date,
        NaiveDateTime.to_date(now)
      )

    tc = slot.teaching_context

    %{
      slot_id: slot.id,
      moved?: false,
      date: date,
      period: slot.period,
      class_group: slot.class_group,
      teacher: tc && tc.teacher,
      teaching_context_id: tc && tc.id,
      combined_course_id: tc && tc.combined_course_id,
      subject: tc && subject_label(tc),
      code: tc && EntryProgress.column_code(tc.catalog_subject, subject_label(tc)),
      status: status,
      absent: absent,
      covered_by: covered_by,
      moved_to: marking && marking.moved_to,
      marked_by_user_id: marking && marking.marked_by_user_id
    }
  end

  # Spec 2026-11-12: one cell per roll call of `date` whose context is not the
  # class's slot's at that period — the lesson as it was really held. `covers` names
  # the slot it displaced, when there is one.
  defp moved_cells(slots, date, %{done: done}) do
    slots_by_key = Map.new(slots, &{{&1.class_group_id, &1.period_id, date}, &1})

    Enum.flat_map(done, fn
      {{_cg_id, _period_id, ^date} = key,
       %{context: %{} = tc, period: %{}, class_group: %{}} = roll} ->
        case Map.get(slots_by_key, key) do
          %{teaching_context_id: id} when id == tc.id -> []
          slot -> [moved_cell(roll, tc, slot && slot.teaching_context, date)]
        end

      _other ->
        []
    end)
  end

  defp moved_cell(roll, tc, covering, date) do
    %{
      slot_id: nil,
      moved?: true,
      date: date,
      period: roll.period,
      class_group: roll.class_group,
      teacher: tc.teacher,
      teaching_context_id: tc.id,
      combined_course_id: tc.combined_course_id,
      subject: subject_label(tc),
      code: EntryProgress.column_code(tc.catalog_subject, subject_label(tc)),
      status: :done,
      absent: roll.absent,
      covered_by: nil,
      covers: covering && %{teacher: covering.teacher, subject: subject_label(covering)},
      moved_to: nil,
      marked_by_user_id: nil
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

  @doc """
  The current séquence's absences still to justify (spec 2026-10-09 §1.4): `count`
  student-days not justified, `flagged_students` among them at or over the alert
  threshold, and that threshold (`alert_hours`). Zero without a current séquence.
  Drives the dashboard KPI and the « Absences » menu badge.
  """
  def absences_to_justify(%Scope{} = scope, %Date{} = today) do
    rules = Attendance.school_life_rules(scope)
    open = scope |> open_days(today, rules) |> Enum.reject(& &1.justified?)

    flagged =
      case open do
        [] ->
          0

        open ->
          alert = Decimal.new(rules.absence_alert_hours)
          hours = unjustified_hours(scope, today, rules)

          open
          |> Enum.map(& &1.enrollment_id)
          |> Enum.uniq()
          |> Enum.count(&(Decimal.compare(Map.get(hours, &1, Decimal.new(0)), alert) != :lt))
      end

    %{count: length(open), flagged_students: flagged, alert_hours: rules.absence_alert_hours}
  end

  @doc """
  The Surveillant's day counters (A3): students with an absence on `today`, and the
  current séquence's student-days still to justify — the same figures as
  `absence_days/4` gives, read without the rows' students and guardians.
  """
  def absence_counts(%Scope{} = scope, %Date{} = today) do
    days = open_days(scope, today, Attendance.school_life_rules(scope))

    %{
      today_absent_students:
        days |> Enum.filter(&(&1.date == today)) |> Enum.uniq_by(& &1.enrollment_id) |> length(),
      to_justify: Enum.count(days, &(not &1.justified?))
    }
  end

  # The current séquence's student-days with an absence (or a long late), as
  # `absence_days/4` groups them, from the entries' ids and flags only:
  # `[%{enrollment_id, date, justified?}]`, a day justified when all its entries are.
  defp open_days(scope, today, rules) do
    case current_sequence_range(scope, today) do
      nil ->
        []

      {first, last} ->
        AttendanceEntry
        |> absences_between(first, last, rules.late_as_absence_minutes)
        |> Ash.Query.select([:enrollment_id, :date, :justified])
        |> Ash.read!(scope: scope)
        |> Enum.group_by(&{&1.enrollment_id, &1.date})
        |> Enum.map(fn {{enrollment_id, date}, entries} ->
          %{
            enrollment_id: enrollment_id,
            date: date,
            justified?: Enum.all?(entries, & &1.justified)
          }
        end)
    end
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

  # enrollment_id => unjustified absence hours in the current séquence (a long
  # late counts, spec KLM2).
  defp unjustified_hours(scope, today, rules) do
    case current_sequence_range(scope, today) do
      nil ->
        %{}

      {first, last} ->
        # The periods come from the bell schedule (one small read), not a load per row.
        periods = scope |> Attendance.list_periods() |> Map.new(&{&1.id, &1})

        AttendanceEntry
        |> Ash.Query.filter(
          status in [:absent, :late] and justified == false and date >= ^first and date <= ^last
        )
        |> Ash.Query.select([:enrollment_id, :period_id, :status, :late_minutes, :justified])
        |> Ash.read!(scope: scope)
        |> Enum.map(&%{&1 | period: Map.get(periods, &1.period_id)})
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

  # Active year's lesson slots on `days`, optionally one teacher's or one class's.
  defp slots(scope, days, teacher_id, class_group_id \\ nil)
  defp slots(%Scope{current_academic_year: nil}, _days, _teacher_id, _cg_id), do: []

  defp slots(%Scope{} = scope, days, teacher_id, class_group_id) do
    case Enum.reject(days, &is_nil/1) do
      [] -> []
      days -> read_slots(scope, days, teacher_id, class_group_id)
    end
  end

  defp read_slots(scope, days, teacher_id, class_group_id) do
    year_id = scope.current_academic_year.id

    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year_id and day in ^days)
    |> then(fn query ->
      if teacher_id,
        do: Ash.Query.filter(query, teaching_context.teacher_user_id == ^teacher_id),
        else: query
    end)
    |> then(fn query ->
      if class_group_id,
        do: Ash.Query.filter(query, class_group_id == ^class_group_id),
        else: query
    end)
    |> Ash.Query.load([:period, :class_group, teaching_context: [:teacher, :catalog_subject]])
    |> Ash.read!(scope: scope)
    |> Enum.filter(&(&1.period.kind == :lesson))
  end

  # `done`: {class_group_id, period_id, date} => the roll call done there — its
  # `context_id` (nil for a conduct manager's), `absent` count, and for the moved
  # cells its `context`, `teacher`, `subject`, `period` and `class_group`;
  # `not_held`: {key => %{moved_to: %Period{} | nil, marked_by_user_id}} for the
  # lessons marked « cours non assuré ». Options: `class_group_id:` (one class over a
  # term or a year: a lighter read of the entries), `entries:` which roll calls to
  # read beyond the slots' classes — `:all` (the school's day) or `{:teacher, id}`
  # (the teacher's own, wherever they were held); default the slots' classes only.
  defp lesson_marks(scope, slots, first, last, opts \\ [])

  defp lesson_marks(scope, slots, first, last, opts) do
    class_ids = slots |> Enum.map(& &1.class_group_id) |> Enum.uniq()
    entries = Keyword.get(opts, :entries, :slot_classes)

    not_held =
      if class_ids == [] do
        %{}
      else
        LessonNotHeld
        |> Ash.Query.for_read(
          :for_classes_range,
          %{class_group_ids: class_ids, first: first, last: last},
          scope: scope
        )
        |> Ash.Query.load(:moved_to_period)
        |> Ash.read!()
        |> Map.new(
          &{{&1.class_group_id, &1.period_id, &1.date},
           %{moved_to: &1.moved_to_period, marked_by_user_id: &1.marked_by_user_id}}
        )
      end

    done =
      cond do
        opts[:class_group_id] -> class_done_roll_calls(scope, opts[:class_group_id], first, last)
        class_ids == [] and entries == :slot_classes -> %{}
        true -> done_roll_calls(scope, class_ids, first, last, entries)
      end

    %{done: done, not_held: not_held}
  end

  defp class_done_roll_calls(scope, class_group_id, first, last) do
    AttendanceEntry
    |> Ash.Query.filter(
      date >= ^first and date <= ^last and enrollment.class_group_id == ^class_group_id
    )
    |> Ash.Query.select([:period_id, :date, :status, :teaching_context_id])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&{class_group_id, &1.period_id, &1.date})
    |> Map.new(fn {key, entries} -> {key, roll_of(entries, nil)} end)
  end

  defp done_roll_calls(scope, class_ids, first, last, entries) do
    AttendanceEntry
    |> Ash.Query.filter(date >= ^first and date <= ^last)
    |> then(fn query ->
      case entries do
        :all ->
          query

        {:teacher, id} ->
          Ash.Query.filter(
            query,
            enrollment.class_group_id in ^class_ids or teaching_context.teacher_user_id == ^id
          )

        :slot_classes ->
          Ash.Query.filter(query, enrollment.class_group_id in ^class_ids)
      end
    end)
    |> Ash.Query.load([
      :period,
      enrollment: [:class_group],
      teaching_context: [:teacher, :catalog_subject]
    ])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(&{&1.enrollment.class_group_id, &1.period_id, &1.date})
    |> Map.new(fn {key, [first_entry | _] = entries} ->
      {key,
       roll_of(entries, %{
         period: first_entry.period,
         class_group: first_entry.enrollment.class_group
       })}
    end)
  end

  # One roll call's facts from its entries: they share one context (written together).
  defp roll_of(entries, place) do
    tc = entries |> Enum.map(&Map.get(&1, :teaching_context)) |> Enum.find(&match?(%{id: _}, &1))
    context_id = (tc && tc.id) || entries |> Enum.map(& &1.teaching_context_id) |> Enum.find(& &1)

    %{
      context_id: context_id,
      context: tc,
      teacher: tc && tc.teacher,
      subject: tc && subject_label(tc),
      absent: Enum.count(entries, &(&1.status == :absent)),
      period: place && place.period,
      class_group: place && place.class_group
    }
  end

  defp weekday(%Date{} = date), do: Enum.at(@days, Date.day_of_week(date) - 1)
end
