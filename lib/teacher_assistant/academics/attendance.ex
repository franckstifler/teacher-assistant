defmodule TeacherAssistant.Academics.Attendance do
  @moduledoc "Attendance capture: timetable-aware roll call for a class/period/date (P2.8)."

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot

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
        {:error, error} -> {:error, error}
      end
    end
  end

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
