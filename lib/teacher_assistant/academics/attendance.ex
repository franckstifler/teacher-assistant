defmodule TeacherAssistant.Academics.Attendance do
  @moduledoc "Attendance capture: timetable-aware roll call for a class/period/date (P2.8)."

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Conduct
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Repo

  @valid_statuses [:present, :absent, :late]

  @doc """
  Resolves the `TimetableSlot` (with `teaching_context` loaded) for `class_group`
  at the given `date`'s day-of-week and `period_id`.

  Returns `{:error, :no_slot}` for Sundays or when no slot is placed.
  """
  def slot_for(%ClassGroup{id: cg_id}, %Date{} = date, period_id) do
    with {:ok, day} <- day_of_week(date) do
      TimetableSlot
      |> Ash.Query.filter(class_group_id == ^cg_id and day == ^day and period_id == ^period_id)
      |> Ash.Query.load(:teaching_context)
      |> Ash.read_one!(authorize?: false)
      |> case do
        nil -> {:error, :no_slot}
        %TimetableSlot{} = slot -> {:ok, slot}
      end
    end
  end

  @doc """
  Builds the roll for `class_group`/`period`/`date`: every roster student with
  their current attendance status (`nil` when unmarked), plus the teaching
  context for that slot (if any).
  """
  def period_roll(%ClassGroup{} = class_group, %Period{id: period_id}, %Date{} = date) do
    teaching_context =
      case slot_for(class_group, date, period_id) do
        {:ok, %TimetableSlot{teaching_context: %TeachingContext{} = tc}} -> tc
        _ -> nil
      end

    statuses =
      AttendanceEntry
      |> Ash.Query.filter(
        period_id == ^period_id and date == ^date and
          enrollment.class_group_id == ^class_group.id
      )
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.enrollment_id, &1.status})

    students =
      class_group
      |> Academics.list_roster()
      |> Enum.map(fn %{student: student, enrollment: enrollment} ->
        %{
          enrollment_id: enrollment.id,
          student_name: student.full_name,
          status: Map.get(statuses, enrollment.id)
        }
      end)

    %{students: students, teaching_context: teaching_context}
  end

  @doc """
  Builds the union roll for a `CombinedCourse`/`period`/`date`: `period_roll/3`
  run once per member class, concatenated as one group per class — each
  group has the same shape `period_roll/3` returns (`:students`,
  `:teaching_context`) plus its own `:class_group`. A combined attendance
  session shows every member class's roster in one screen; recording still
  writes each `AttendanceEntry` to the student's own class (see
  `record_combined_period/5`) — this is purely a read shape, it never
  merges rosters across classes into one flat list.

  Skips a member context with no `class_group` yet, same as
  `Academics.list_union_students/1`.
  """
  def combined_period_roll(%CombinedCourse{} = course, %Period{} = period, %Date{} = date) do
    course
    |> Academics.contexts_of_course()
    |> Ash.load!(:class_group, authorize?: false)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.map(fn ctx ->
      ctx.class_group
      |> period_roll(period, date)
      |> Map.put(:class_group, ctx.class_group)
    end)
    |> Enum.sort_by(&String.downcase(&1.class_group.label))
  end

  @doc """
  Records one combined attendance session: `marks` (`{enrollment_id, status}`
  pairs covering every member class's roster, as returned by
  `combined_period_roll/3`) are routed to each enrollment's own class and
  written via `record_period/6` — one call per member class. All groups are
  written inside a single transaction: if any member class's marks are
  invalid, NOTHING is persisted for ANY class (no partial commit), mirroring
  the "record once, all classes together" combined-marks save. Returns
  `{:ok, total_count}` or `{:error, reason}`.
  """
  def record_combined_period(
        %CombinedCourse{} = course,
        %Period{} = period,
        %Date{} = date,
        marks,
        recorded_by_user_id
      )
      when is_list(marks) do
    groups = combined_period_roll(course, period, date)

    per_group_marks =
      Enum.map(groups, fn %{class_group: cg, teaching_context: tc, students: students} ->
        group_enrollment_ids = MapSet.new(students, & &1.enrollment_id)

        group_marks =
          Enum.filter(marks, fn {enrollment_id, _status} ->
            MapSet.member?(group_enrollment_ids, enrollment_id)
          end)

        {cg, tc, group_marks}
      end)

    result =
      Repo.transaction(fn ->
        per_group_marks
        |> Enum.reduce_while(0, fn {cg, tc, group_marks}, acc ->
          case record_period(cg, period, tc, date, group_marks, recorded_by_user_id) do
            {:ok, count} -> {:cont, acc + count}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:error, reason} -> Repo.rollback(reason)
          total_count -> total_count
        end
      end)

    case result do
      {:ok, total_count} -> {:ok, total_count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upserts one `AttendanceEntry` per `{enrollment_id, status}` mark for
  `class_group`/`period`/`date`. Rejects the whole batch with `{:error, term}`
  if any enrollment doesn't belong to `class_group` or any status is invalid.
  Marks omitted from the list are left untouched. Returns `{:ok, count}`.
  """
  def record_period(
        %ClassGroup{workspace_id: ws_id} = class_group,
        %Period{id: period_id},
        teaching_context,
        %Date{} = date,
        marks,
        recorded_by_user_id
      )
      when is_list(marks) do
    teaching_context_id =
      case teaching_context do
        %TeachingContext{id: id} -> id
        nil -> nil
      end

    valid_enrollment_ids =
      class_group
      |> Academics.list_roster()
      |> MapSet.new(& &1.enrollment.id)

    with :ok <- validate_marks(marks, valid_enrollment_ids) do
      results =
        Enum.map(marks, fn {enrollment_id, status} ->
          AttendanceEntry
          |> Ash.Changeset.for_create(:record, %{
            date: date,
            status: status,
            enrollment_id: enrollment_id,
            period_id: period_id,
            teaching_context_id: teaching_context_id,
            recorded_by_user_id: recorded_by_user_id,
            workspace_id: ws_id
          })
          |> Ash.create(authorize?: false)
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
  def class_register(%ClassGroup{workspace_id: ws_id} = class_group, %Date{} = date) do
    workspace = Ash.get!(TeacherAssistant.Academics.Workspace, ws_id, authorize?: false)

    periods =
      workspace
      |> Timetables.list_periods()
      |> Enum.filter(&(&1.kind == :lesson))

    period_ids = Enum.map(periods, & &1.id)

    cells_by_enrollment =
      AttendanceEntry
      |> Ash.Query.filter(
        date == ^date and period_id in ^period_ids and
          enrollment.class_group_id == ^class_group.id
      )
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.enrollment_id, &{&1.period_id, &1.status})
      |> Map.new(fn {enrollment_id, pairs} -> {enrollment_id, Map.new(pairs)} end)

    students =
      class_group
      |> Academics.list_roster()
      |> Enum.map(fn %{student: student, enrollment: enrollment} ->
        marks = Map.get(cells_by_enrollment, enrollment.id, %{})
        cells = Map.new(period_ids, &{&1, Map.get(marks, &1)})

        %{
          enrollment_id: enrollment.id,
          student_name: student.full_name,
          cells: cells
        }
      end)

    %{periods: periods, students: students}
  end

  @doc """
  Sets `justified: true` and `justification_note: note` on every `:absent`
  `AttendanceEntry` for `enrollment` (struct or bare id) on `date`. Entries
  with another status, or on another date, are left untouched. Returns
  `{:ok, count}`.
  """
  def justify_day(enrollment, %Date{} = date, note) do
    set_justification(enrollment, date, true, note)
  end

  @doc """
  Sets `justified: false` and clears `justification_note` on every `:absent`
  `AttendanceEntry` for `enrollment` (struct or bare id) on `date`. Returns
  `{:ok, count}`.
  """
  def unjustify_day(enrollment, %Date{} = date) do
    set_justification(enrollment, date, false, nil)
  end

  defp set_justification(enrollment, %Date{} = date, justified, note) do
    enrollment_id = enrollment_id(enrollment)

    entries =
      AttendanceEntry
      |> Ash.Query.filter(enrollment_id == ^enrollment_id and date == ^date and status == :absent)
      |> Ash.read!(authorize?: false)

    results =
      Enum.map(entries, fn entry ->
        entry
        |> Ash.Changeset.for_update(:update, %{justified: justified, justification_note: note})
        |> Ash.update(authorize?: false)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, length(results)}
      {:error, _error} -> {:error, :justify_failed}
    end
  end

  @zero_totals %{
    justified_hours: Decimal.new(0),
    unjustified_hours: Decimal.new(0),
    retards: 0
  }

  @doc """
  Aggregates justified/unjustified absence hours and retards for `enrollment`
  (struct or bare id) within `period_tuple`'s date range (see
  `Academics.period_date_range/1`). Returns zero totals when the range is
  `nil`.
  """
  def student_conduct(enrollment, period_tuple) do
    enrollment_id = enrollment_id(enrollment)

    case Academics.period_date_range(period_tuple) do
      nil ->
        @zero_totals

      {first, last} ->
        AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^enrollment_id and date >= ^first and date <= ^last)
        |> Ash.Query.load(:period)
        |> Ash.read!(authorize?: false)
        |> Enum.map(&%{status: &1.status, justified: &1.justified, period: &1.period})
        |> Conduct.totals()
    end
  end

  @doc """
  Aggregates justified/unjustified absence hours and retards for every
  roster enrollment of `class_group` within `period_tuple`'s date range, in
  one scoped read. Enrollments with no entries in range get zero totals.
  """
  def class_conduct(%ClassGroup{} = class_group, period_tuple) do
    roster_enrollment_ids =
      class_group
      |> Academics.list_roster()
      |> Enum.map(& &1.enrollment.id)

    zero_map = Map.new(roster_enrollment_ids, &{&1, @zero_totals})

    case Academics.period_date_range(period_tuple) do
      nil ->
        zero_map

      {first, last} ->
        totals_by_enrollment =
          AttendanceEntry
          |> Ash.Query.filter(
            enrollment.class_group_id == ^class_group.id and date >= ^first and date <= ^last
          )
          |> Ash.Query.load(:period)
          |> Ash.read!(authorize?: false)
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

  defp enrollment_id(%Enrollment{id: id}), do: id
  defp enrollment_id(id) when is_binary(id), do: id

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
