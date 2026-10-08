defmodule TeacherAssistant.Attendance do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Conduct
  # `TeacherAssistant.Academics.Enrollment` is the resource struct every
  # function below pattern-matches on; the domain `TeacherAssistant.Enrollment`
  # is always referenced fully qualified so the two never collide under one
  # bare `Enrollment` alias.
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.JustificationReason
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Academics.SanctionType
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Academics.SchoolLifeRules
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Scope

  resources do
    resource Period do
      define :update_period, action: :update
    end

    resource AttendanceEntry do
      define :for_period_date_class,
        action: :for_period_date_class,
        args: [:period_id, :date, :class_group_id]

      define :for_date_periods_class,
        action: :for_date_periods_class,
        args: [:date, :period_ids, :class_group_id]

      define :absences_for_day, action: :absences_for_day, args: [:enrollment_id, :date]

      define :for_enrollment_range,
        action: :for_enrollment_range,
        args: [:enrollment_id, :first, :last]

      define :for_class_range, action: :for_class_range, args: [:class_group_id, :first, :last]
    end

    resource TeacherAssistant.Academics.RollCallReminder
  end

  authorization do
    authorize :by_default
  end

  @valid_statuses [:present, :absent, :late]

  @zero_totals %{
    justified_hours: Decimal.new(0),
    unjustified_hours: Decimal.new(0),
    retards: 0
  }

  # --- School life, day view (spec G) -------------------------------------

  defdelegate school_day(scope, date, now), to: TeacherAssistant.Academics.SchoolLife
  defdelegate teacher_day(scope, user, date, now), to: TeacherAssistant.Academics.SchoolLife
  defdelegate remind_roll_call(scope, slot_id, date), to: TeacherAssistant.Academics.SchoolLife
  defdelegate late_count(scope, date), to: TeacherAssistant.Academics.SchoolLife

  defdelegate teacher_missed_this_week(scope, user, today, now),
    to: TeacherAssistant.Academics.SchoolLife

  defdelegate absence_days(scope, first, last, today), to: TeacherAssistant.Academics.SchoolLife
  defdelegate current_sequence_range(scope, today), to: TeacherAssistant.Academics.SchoolLife

  # --- Periods -------------------------------------------------------------

  @doc "Whether the scope may edit the bell schedule (admin axis)."
  def can_manage_periods?(scope), do: Ash.can?({Period, :create}, scope)

  @doc "Every period in the scope's school, sorted by position."
  def list_periods(%Scope{} = scope) do
    Period
    |> Ash.Query.for_read(:for_workspace, %{}, scope: scope)
    |> Ash.read!()
  end

  @doc """
  Deletes a period, unless a `TimetableSlot` still references it — in that
  case returns `{:error, :has_slots}` without deleting (mirrors the
  `Curriculum.remove_assignment/1` "has data" guard).
  """
  def delete_period(%Scope{} = scope, %Period{id: id} = period) do
    # `TimetableSlot` is now multitenant — pass the scope.
    has_slots = TeacherAssistant.Timetabling.list_for_period!(id, scope: scope) != []

    if has_slots do
      {:error, :has_slots}
    else
      case Ash.destroy(period, scope: scope) do
        :ok -> :ok
        {:error, error} -> {:error, error}
      end
    end
  end

  @doc """
  Seeds the scope's school bell schedule from `Reference.default_periods_preset/0`,
  unless periods are already seeded. Idempotent.
  """
  def build_default_periods(%Scope{} = scope) do
    case list_periods(scope) do
      [] ->
        Enum.reduce_while(Reference.default_periods_preset(), :ok, fn preset, :ok ->
          Period
          |> Ash.Changeset.for_create(:create, preset, scope: scope)
          |> Ash.create()
          |> case do
            {:ok, _} -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)

      _ ->
        :ok
    end
  end

  # --- Slot / roll -------------------------------------------------------

  @doc """
  Resolves the `TimetableSlot` (with `teaching_context` loaded) for `class_group`
  at the given `date`'s day-of-week and `period_id`.

  Returns `{:error, :no_slot}` for Sundays or when no slot is placed.
  """
  def slot_for(%Scope{} = scope, %ClassGroup{id: cg_id}, %Date{} = date, period_id) do
    with {:ok, day} <- day_of_week(date) do
      TimetableSlot
      |> Ash.Query.filter(class_group_id == ^cg_id and day == ^day and period_id == ^period_id)
      # `:teaching_context` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.Query.load(:teaching_context)
      |> Ash.read_one!(scope: scope)
      |> case do
        nil -> {:error, :no_slot}
        %TimetableSlot{} = slot -> {:ok, slot}
      end
    end
  end

  @doc """
  Builds the roll for `class_group`/`period`/`date`: every roster student with
  their current attendance status (`nil` when unmarked), plus the teaching
  context for that slot (if any). Delegates to `AttendanceEntry`'s
  `:period_roll` generic action.
  """
  def period_roll(
        %Scope{} = scope,
        %ClassGroup{} = class_group,
        %Period{} = period,
        %Date{} = date
      ) do
    # A refused actor (e.g. a member revoked mid-session) sees an empty roll,
    # like any policy-filtered read; the next write shows the refusal.
    AttendanceEntry
    |> Ash.ActionInput.for_action(
      :period_roll,
      %{
        class_group: class_group,
        period: period,
        date: date
      },
      scope: scope
    )
    |> Ash.run_action()
    |> case do
      {:ok, roll} -> roll
      {:error, %Ash.Error.Forbidden{}} -> %{students: [], teaching_context: nil}
    end
  end

  @doc """
  Builds the union roll for a `CombinedCourse`/`period`/`date`: `period_roll/4`
  run once per member class, concatenated as one group per class — each
  group has the same shape `period_roll/4` returns (`:students`,
  `:teaching_context`) plus its own `:class_group`. A combined attendance
  session shows every member class's roster in one screen; recording still
  writes each `AttendanceEntry` to the student's own class (see
  `record_combined_period/5`) — this is purely a read shape, it never
  merges rosters across classes into one flat list.

  Skips a member context with no `class_group` yet, same as
  `Curriculum.list_union_students/1`. Delegates to `AttendanceEntry`'s
  `:combined_period_roll` generic action.
  """
  def combined_period_roll(
        %Scope{} = scope,
        %CombinedCourse{} = course,
        %Period{} = period,
        %Date{} = date
      ) do
    AttendanceEntry
    |> Ash.ActionInput.for_action(
      :combined_period_roll,
      %{
        course: course,
        period: period,
        date: date
      },
      scope: scope
    )
    |> Ash.run_action()
    |> case do
      {:ok, groups} -> groups
      {:error, %Ash.Error.Forbidden{}} -> []
    end
  end

  @doc """
  Records one combined attendance session: `marks` (`{enrollment_id, status}`
  or `{enrollment_id, status, late_minutes}` tuples covering every member class's roster, as returned by
  `combined_period_roll/4`) are routed to each enrollment's own class and
  written via the `AttendanceEntry` `:record_combined_period` action — one
  group per member class. Every mark is validated (roster membership + status)
  *before* the transactional action ever runs, so an invalid mark for any
  class never opens a transaction, let alone leaves a partial write: if any
  member class's marks are invalid, NOTHING is persisted for ANY class (no
  partial commit), mirroring the "record once, all classes together"
  combined-marks save. Returns `{:ok, total_count}` or `{:error, reason}`.
  """
  def record_combined_period(
        %Scope{} = scope,
        %CombinedCourse{} = course,
        %Period{} = period,
        %Date{} = date,
        marks
      )
      when is_list(marks) do
    groups = combined_period_roll(scope, course, period, date)

    per_group_marks =
      Enum.map(groups, fn %{class_group: cg, teaching_context: tc, students: students} ->
        group_enrollment_ids = MapSet.new(students, & &1.enrollment_id)

        group_marks =
          Enum.filter(marks, fn mark ->
            {enrollment_id, _status, _minutes} = mark_parts(mark)
            MapSet.member?(group_enrollment_ids, enrollment_id)
          end)

        {cg, tc, group_marks}
      end)

    with :ok <- validate_group_marks(scope, per_group_marks) do
      run_record_combined_period(
        per_group_marks,
        period,
        date,
        scope.current_user && scope.current_user.id,
        scope
      )
    end
  end

  defp validate_group_marks(%Scope{} = scope, per_group_marks) do
    Enum.reduce_while(per_group_marks, :ok, fn {cg, _tc, group_marks}, :ok ->
      valid_enrollment_ids =
        scope
        |> TeacherAssistant.Enrollment.list_roster(cg)
        |> MapSet.new(& &1.enrollment.id)

      case validate_marks(group_marks, valid_enrollment_ids) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_record_combined_period(
         per_group_marks,
         %Period{id: period_id},
         date,
         recorded_by_user_id,
         %Scope{} = scope
       ) do
    groups =
      Enum.map(per_group_marks, fn {_cg, tc, group_marks} ->
        %{
          teaching_context_id: teaching_context_id(tc),
          marks:
            Enum.map(group_marks, fn mark ->
              {enrollment_id, status, minutes} = mark_parts(mark)
              %{enrollment_id: enrollment_id, status: status, late_minutes: minutes}
            end)
        }
      end)

    AttendanceEntry
    |> Ash.ActionInput.for_action(
      :record_combined_period,
      %{
        period_id: period_id,
        date: date,
        recorded_by_user_id: recorded_by_user_id,
        groups: groups
      },
      scope: scope
    )
    |> Ash.run_action()
    |> case do
      {:ok, total_count} -> {:ok, total_count}
      {:error, %Ash.Error.Forbidden{} = forbidden} -> {:error, forbidden}
      {:error, _reason} -> {:error, :record_failed}
    end
  end

  @doc """
  Upserts one `AttendanceEntry` per `{enrollment_id, status}` or
  `{enrollment_id, status, late_minutes}` mark (spec KLM2) for
  `class_group`/`period`/`date`. Rejects the whole batch with `{:error, term}`
  if any enrollment doesn't belong to `class_group` or any status is invalid.
  Marks omitted from the list are left untouched. Returns `{:ok, count}`.
  """
  def record_period(
        %Scope{} = scope,
        %ClassGroup{} = class_group,
        %Period{id: period_id},
        teaching_context,
        %Date{} = date,
        marks
      )
      when is_list(marks) do
    teaching_context_id = teaching_context_id(teaching_context)

    valid_enrollment_ids =
      scope
      |> TeacherAssistant.Enrollment.list_roster(class_group)
      |> MapSet.new(& &1.enrollment.id)

    with :ok <- validate_marks(marks, valid_enrollment_ids) do
      results =
        Enum.map(marks, fn mark ->
          {enrollment_id, status, minutes} = mark_parts(mark)

          AttendanceEntry
          |> Ash.Changeset.for_create(
            :record,
            %{
              date: date,
              status: status,
              late_minutes: minutes,
              enrollment_id: enrollment_id,
              period_id: period_id,
              teaching_context_id: teaching_context_id,
              recorded_by_user_id: scope.current_user && scope.current_user.id
            },
            scope: scope
          )
          |> Ash.create()
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, length(results)}
        {:error, %Ash.Error.Forbidden{} = forbidden} -> {:error, forbidden}
        {:error, _error} -> {:error, :record_failed}
      end
    end
  end

  @doc """
  Builds the class register for `class_group` on `date`: every lesson period
  (breaks excluded) and every roster student with a `cells` map keyed by
  period_id, reflecting that day's attendance marks (`nil` where unmarked).
  """
  def class_register(%Scope{} = scope, %ClassGroup{} = class_group, %Date{} = date) do
    periods =
      scope
      |> list_periods()
      |> Enum.filter(&(&1.kind == :lesson))

    period_ids = Enum.map(periods, & &1.id)

    cells_by_enrollment =
      date
      |> for_date_periods_class!(period_ids, class_group.id, scope: scope)
      |> Enum.group_by(& &1.enrollment_id, &{&1.period_id, &1.status})
      |> Map.new(fn {enrollment_id, pairs} -> {enrollment_id, Map.new(pairs)} end)

    students =
      scope
      |> TeacherAssistant.Enrollment.list_roster(class_group)
      |> Enum.map(fn %{student: student, enrollment: enrollment} ->
        marks = Map.get(cells_by_enrollment, enrollment.id, %{})
        cells = Map.new(period_ids, &{&1, Map.get(marks, &1)})

        %{
          enrollment_id: enrollment.id,
          enrollment: enrollment,
          student_name: student.full_name,
          cells: cells
        }
      end)

    %{periods: periods, students: students}
  end

  @doc """
  Justifies `enrollment`'s day: every `:absent` `AttendanceEntry` on `date` gets
  `justified: true`, the `reason` (a `JustificationReason`, required), the
  optional `note`, the scope's user and the time. Entries with another status,
  or on another date, are left untouched. Returns `{:ok, count}`, or
  `{:error, :invalid_reason}` without writing when `reason` is not a reason.
  """
  def justify_day(
        %Scope{} = scope,
        %Enrollment{} = enrollment,
        %Date{} = date,
        reason,
        note \\ nil
      ) do
    if reason in JustificationReason.values() do
      set_justification(scope, enrollment, date, %{
        justified: true,
        justification_reason: reason,
        justification_note: note,
        justified_by_user_id: scope.current_user && scope.current_user.id,
        justified_at: DateTime.utc_now()
      })
    else
      {:error, :invalid_reason}
    end
  end

  @doc """
  Unjustifies `enrollment`'s day: clears the justification (reason, note, author,
  time) on every `:absent` or `:late` `AttendanceEntry` on `date`. Returns `{:ok, count}`.
  """
  def unjustify_day(%Scope{} = scope, %Enrollment{} = enrollment, %Date{} = date) do
    set_justification(scope, enrollment, date, %{
      justified: false,
      justification_reason: nil,
      justification_note: nil,
      justified_by_user_id: nil,
      justified_at: nil
    })
  end

  defp set_justification(%Scope{} = scope, %Enrollment{id: id}, %Date{} = date, attrs) do
    entries = absences_for_day!(id, date, scope: scope)

    results =
      Enum.map(entries, fn entry ->
        entry
        |> Ash.Changeset.for_update(:update, attrs, scope: scope)
        |> Ash.update()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, length(results)}
      {:error, %Ash.Error.Forbidden{} = forbidden} -> {:error, forbidden}
      {:error, _error} -> {:error, :justify_failed}
    end
  end

  @doc """
  Aggregates justified/unjustified absence hours and retards for `enrollment`
  within `period_tuple`'s date range (see `Organization.period_date_range/2`).
  Returns zero totals when the range is `nil`.
  """
  def student_conduct(%Scope{} = scope, %Enrollment{id: id}, period_tuple) do
    case Organization.period_date_range(scope, period_tuple) do
      nil ->
        @zero_totals

      {first, last} ->
        id
        |> for_enrollment_range!(first, last, scope: scope)
        |> Conduct.totals(school_life_rules(scope).late_as_absence_minutes)
    end
  end

  @doc """
  Aggregates justified/unjustified absence hours and retards for every
  roster enrollment of `class_group` within `period_tuple`'s date range, in
  one scoped read. Enrollments with no entries in range get zero totals.
  """
  def class_conduct(%Scope{} = scope, %ClassGroup{} = class_group, period_tuple) do
    roster_enrollment_ids =
      scope
      |> TeacherAssistant.Enrollment.list_roster(class_group)
      |> Enum.map(& &1.enrollment.id)

    zero_map = Map.new(roster_enrollment_ids, &{&1, @zero_totals})

    case Organization.period_date_range(scope, period_tuple) do
      nil ->
        zero_map

      {first, last} ->
        threshold = school_life_rules(scope).late_as_absence_minutes

        totals_by_enrollment =
          class_group.id
          |> for_class_range!(first, last, scope: scope)
          |> Enum.group_by(& &1.enrollment_id)
          |> Map.new(fn {enrollment_id, entries} ->
            totals = Conduct.totals(entries, threshold)

            {enrollment_id, totals}
          end)

        Map.merge(zero_map, totals_by_enrollment)
    end
  end

  defp teaching_context_id(%TeachingContext{id: id}), do: id
  defp teaching_context_id(nil), do: nil

  defp validate_marks(marks, valid_enrollment_ids) do
    Enum.reduce_while(marks, :ok, fn mark, :ok ->
      {enrollment_id, status, _minutes} = mark_parts(mark)

      cond do
        not MapSet.member?(valid_enrollment_ids, enrollment_id) ->
          {:halt, {:error, :invalid_enrollment}}

        status not in @valid_statuses ->
          {:halt, {:error, :invalid_status}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # A mark is `{enrollment_id, status}` or `{enrollment_id, status, late_minutes}`.
  defp mark_parts({enrollment_id, status}), do: {enrollment_id, status, nil}
  defp mark_parts({enrollment_id, status, minutes}), do: {enrollment_id, status, minutes}

  defp day_of_week(%Date{} = date) do
    case Date.day_of_week(date) do
      1 -> {:ok, :monday}
      2 -> {:ok, :tuesday}
      3 -> {:ok, :wednesday}
      4 -> {:ok, :thursday}
      5 -> {:ok, :friday}
      6 -> {:ok, :saturday}
      _ -> {:error, :no_slot}
    end
  end

  @doc "The school calendar: profile settings and the active year's holidays (spec J1)."
  def school_calendar(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    holidays =
      case scope.current_academic_year do
        nil ->
          []

        year ->
          scope
          |> TeacherAssistant.Organization.list_holidays(year)
          |> Enum.map(&Map.take(&1, [:label, :start_date, :end_date]))
      end

    SchoolCalendar.new(profile.lesson_days, profile.wednesday_afternoon_off?, holidays)
  end

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
      days == [] ->
        {:error, :invalid_setting}

      Enum.all?(days, &Map.has_key?(known, &1)) ->
        {:ok, Enum.filter(SchoolCalendar.all_days(), &(Atom.to_string(&1) in days))}

      true ->
        {:error, :invalid_setting}
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

  @doc """
  The active year's lessons on `period` that moving its start to `new_start` would
  put in a closed cell (Wednesday afternoon off), as `[{day, count}]` — empty when
  the move is safe (spec J1).
  """
  def slots_closed_by_period_move(%Scope{current_academic_year: nil}, _period, _new_start), do: []

  def slots_closed_by_period_move(
        %Scope{current_academic_year: year} = scope,
        period,
        %Time{} = new_start
      ) do
    cal = school_calendar(scope)
    moved = %{period | start_time: new_start}

    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id and period_id == ^period.id)
    |> Ash.read!(scope: scope)
    |> Enum.reject(&SchoolCalendar.open_cell?(cal, &1.day, moved))
    |> Enum.frequencies_by(& &1.day)
    |> Enum.sort_by(fn {day, _} -> Enum.find_index(SchoolCalendar.all_days(), &(&1 == day)) end)
  end

  @doc "Why `date` has no lessons: `{:holiday, label}`, `:no_lessons`, or nil (a lesson day)."
  def day_off(%Scope{} = scope, %Date{} = date) do
    cal = school_calendar(scope)

    case SchoolCalendar.holiday_on(cal, date) do
      %{label: label} -> {:holiday, label}
      nil -> if SchoolCalendar.lesson_day?(cal, date), do: nil, else: :no_lessons
    end
  end

  # --- School-life settings (spec KLM2) ------------------------------------------

  @doc "The school's attendance and discipline settings."
  def school_life_rules(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    SchoolLifeRules.from_profile(profile)
  end

  @doc "Whether the scope may change them (admins and the SG)."
  def can_edit_school_life?(%Scope{} = scope) do
    case TeacherAssistant.Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> Ash.can?({profile, :update_school_life}, scope)
      _ -> false
    end
  end

  @doc """
  Saves the settings from the page's string params. Blank minutes or deadline
  switch that rule off; the alert hours are required; decimals take a comma or
  a dot; at least one sanction type stays in use.
  """
  def update_school_life_rules(%Scope{} = scope, %{} = params) do
    with {:ok, late} <- parse_integer(params["late_as_absence_minutes"], :optional),
         {:ok, deadline} <- parse_integer(params["justification_deadline_days"], :optional),
         {:ok, alert} <- parse_integer(params["absence_alert_hours"], :required),
         {:ok, per_hour} <- parse_decimal(params["conduct_points_per_absence_hour"]),
         {:ok, per_late} <- parse_decimal(params["conduct_points_per_late"]),
         {:ok, points} <- parse_points(params["sanction_points"] || %{}),
         {:ok, types} <- parse_types(params["sanction_types_in_use"]),
         :ok <-
           check_ranges([
             {:late_as_absence_minutes, late, 1, 240},
             {:justification_deadline_days, deadline, 1, 60},
             {:absence_alert_hours, alert, 1, 200},
             {:conduct_points_per_absence_hour, per_hour, 0, 5},
             {:conduct_points_per_late, per_late, 0, 5}
             | Enum.map(points, fn {type, d} -> {{:sanction_points, type}, d, 0, 20} end)
           ]),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      profile
      |> Ash.Changeset.for_update(
        :update_school_life,
        %{
          late_as_absence_minutes: late,
          justification_deadline_days: deadline,
          absence_alert_hours: alert,
          conduct_points_per_absence_hour: per_hour,
          conduct_points_per_late: per_late,
          sanction_points: points,
          sanction_types_in_use: types
        },
        scope: scope
      )
      |> Ash.update()
    end
  end

  # `{:error, {:out_of_range, field, min, max}}` for the first value outside its
  # bounds, so the page can name the field (Ash's own messages are untranslated).
  defp check_ranges(checks) do
    Enum.find_value(checks, :ok, fn
      {_field, nil, _min, _max} ->
        nil

      {field, value, min, max} ->
        if Decimal.lt?(Decimal.new(value), min) or Decimal.gt?(Decimal.new(value), max),
          do: {:error, {:out_of_range, field, min, max}}
    end)
  end

  defp parse_integer(value, mode) do
    case {String.trim(to_string(value || "")), mode} do
      {"", :optional} ->
        {:ok, nil}

      {"", :required} ->
        {:error, :invalid_number}

      {text, _} ->
        case Integer.parse(text) do
          {n, ""} -> {:ok, n}
          _ -> {:error, :invalid_number}
        end
    end
  end

  defp parse_decimal(value) do
    case value |> to_string() |> String.trim() |> String.replace(",", ".") |> Decimal.parse() do
      # NaN and ±Infinity carry an atom coefficient.
      {%Decimal{coef: coef} = d, ""} when is_integer(coef) -> {:ok, d}
      _ -> {:error, :invalid_number}
    end
  end

  defp parse_points(%{} = params) do
    Enum.reduce_while(SanctionType.values(), {:ok, %{}}, fn type, {:ok, acc} ->
      case parse_decimal(Map.get(params, Atom.to_string(type), "")) do
        {:ok, d} -> {:cont, {:ok, Map.put(acc, type, d)}}
        error -> {:halt, error}
      end
    end)
  end

  defp parse_types(values) when is_list(values) do
    by_string = Map.new(SanctionType.values(), &{Atom.to_string(&1), &1})

    case values |> Enum.map(&Map.get(by_string, &1)) |> Enum.reject(&is_nil/1) do
      [] -> {:error, :no_sanction_type}
      types -> {:ok, Enum.filter(SanctionType.values(), &(&1 in types))}
    end
  end

  defp parse_types(_), do: {:error, :no_sanction_type}
end
