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
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Reference
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
  end

  authorization do
    authorize :when_requested
  end

  @valid_statuses [:present, :absent, :late]

  @zero_totals %{
    justified_hours: Decimal.new(0),
    unjustified_hours: Decimal.new(0),
    retards: 0
  }

  # --- Periods -------------------------------------------------------------

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
      Ash.destroy!(period, scope: scope)
      :ok
    end
  end

  @doc """
  Seeds the scope's school bell schedule from `Reference.default_periods_preset/0`,
  unless periods are already seeded. Idempotent.
  """
  def build_default_periods(%Scope{} = scope) do
    case list_periods(scope) do
      [] ->
        Enum.each(Reference.default_periods_preset(), fn preset ->
          Period
          |> Ash.Changeset.for_create(:create, preset, scope: scope)
          |> Ash.create!()
        end)

        :ok

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
    {:ok, roll} =
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

    roll
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
    {:ok, groups} =
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

    groups
  end

  @doc """
  Records one combined attendance session: `marks` (`{enrollment_id, status}`
  pairs covering every member class's roster, as returned by
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
          Enum.filter(marks, fn {enrollment_id, _status} ->
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
            Enum.map(group_marks, fn {enrollment_id, status} ->
              %{enrollment_id: enrollment_id, status: status}
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
      {:error, _reason} -> {:error, :record_failed}
    end
  end

  @doc """
  Upserts one `AttendanceEntry` per `{enrollment_id, status}` mark for
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
        Enum.map(marks, fn {enrollment_id, status} ->
          AttendanceEntry
          |> Ash.Changeset.for_create(
            :record,
            %{
              date: date,
              status: status,
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
  Sets `justified: true` and `justification_note: note` on every `:absent`
  `AttendanceEntry` for `enrollment` on `date`. Entries with another status,
  or on another date, are left untouched. Returns `{:ok, count}`.
  """
  def justify_day(%Scope{} = scope, %Enrollment{} = enrollment, %Date{} = date, note) do
    set_justification(scope, enrollment, date, true, note)
  end

  @doc """
  Sets `justified: false` and clears `justification_note` on every `:absent`
  `AttendanceEntry` for `enrollment` on `date`. Returns `{:ok, count}`.
  """
  def unjustify_day(%Scope{} = scope, %Enrollment{} = enrollment, %Date{} = date) do
    set_justification(scope, enrollment, date, false, nil)
  end

  defp set_justification(
         %Scope{} = scope,
         %Enrollment{id: id},
         %Date{} = date,
         justified,
         note
       ) do
    entries = absences_for_day!(id, date, scope: scope)

    results =
      Enum.map(entries, fn entry ->
        entry
        |> Ash.Changeset.for_update(
          :update,
          %{justified: justified, justification_note: note},
          scope: scope
        )
        |> Ash.update()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, length(results)}
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
        |> Enum.map(&%{status: &1.status, justified: &1.justified, period: &1.period})
        |> Conduct.totals()
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
        totals_by_enrollment =
          class_group.id
          |> for_class_range!(first, last, scope: scope)
          |> Enum.group_by(& &1.enrollment_id)
          |> Map.new(fn {enrollment_id, entries} ->
            totals =
              entries
              |> Enum.map(&%{status: &1.status, justified: &1.justified, period: &1.period})
              |> Conduct.totals()

            {enrollment_id, totals}
          end)

        Map.merge(zero_map, totals_by_enrollment)
    end
  end

  defp teaching_context_id(%TeachingContext{id: id}), do: id
  defp teaching_context_id(nil), do: nil

  defp validate_marks(marks, valid_enrollment_ids) do
    Enum.reduce_while(marks, :ok, fn {enrollment_id, status}, :ok ->
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
end
