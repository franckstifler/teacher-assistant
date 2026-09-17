defmodule TeacherAssistant.Academics.Courses do
  @moduledoc """
  Combines several per-class `TeachingContext`s (same teacher, same subject)
  into one `CombinedCourse` sharing a single `ProgressionPlan` — and splits
  them back apart. Also lists a teacher's "teaching units": each is either a
  standalone `TeachingContext` or a `CombinedCourse` collapsing its members.
  """

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, CombinedCourse, ProgressionPlan, TeachingContext}
  alias TeacherAssistant.Repo

  @doc """
  Combines two or more `TeachingContext`s into a fresh `CombinedCourse`.

  All contexts must share the same `teacher_user_id` and `subject`, and none
  may already belong to a course. Creates the course, stamps
  `combined_course_id` on every member context, and creates the course's one
  shared `ProgressionPlan` — all inside a single transaction, rolled back on
  any error.
  """
  def combine(contexts) when is_list(contexts) do
    with :ok <- validate_count(contexts),
         :ok <- validate_same_teacher(contexts),
         :ok <- validate_same_subject(contexts),
         :ok <- validate_not_already_combined(contexts) do
      do_combine(contexts)
    end
  end

  defp validate_count(contexts) when length(contexts) >= 2, do: :ok
  defp validate_count(_contexts), do: {:error, :need_two}

  defp validate_same_teacher(contexts) do
    contexts
    |> Enum.map(& &1.teacher_user_id)
    |> Enum.uniq()
    |> case do
      [_single] -> :ok
      _ -> {:error, :teacher_mismatch}
    end
  end

  defp validate_same_subject(contexts) do
    contexts
    |> Enum.map(& &1.subject)
    |> Enum.uniq()
    |> case do
      [_single] -> :ok
      _ -> {:error, :subject_mismatch}
    end
  end

  defp validate_not_already_combined(contexts) do
    if Enum.any?(contexts, & &1.combined_course_id) do
      {:error, :already_combined}
    else
      :ok
    end
  end

  defp do_combine([first | _] = contexts) do
    result =
      Repo.transaction(fn ->
        with {:ok, course} <- create_course(first, build_label(contexts)),
             :ok <- stamp_contexts(contexts, course.id),
             {:ok, _plan} <- Academics.create_course_plan(course, %{}) do
          course
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)

    case result do
      {:ok, %CombinedCourse{} = course} -> {:ok, course}
      {:error, error} -> {:error, error}
    end
  end

  defp create_course(%TeachingContext{} = first, label) do
    CombinedCourse
    |> Ash.Changeset.for_create(:create, %{
      subject: first.subject,
      label: label,
      workspace_id: first.workspace_id,
      academic_year_id: first.academic_year_id,
      teacher_user_id: first.teacher_user_id
    })
    |> Ash.create(authorize?: false)
  end

  defp stamp_contexts(contexts, course_id) do
    Enum.reduce_while(contexts, :ok, fn ctx, :ok ->
      ctx
      |> Ash.Changeset.for_update(:update, %{combined_course_id: course_id})
      |> Ash.update(authorize?: false, return_notifications?: true)
      |> case do
        {:ok, _ctx, notifications} ->
          Ash.Notifier.notify(notifications)
          {:cont, :ok}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp build_label(contexts) do
    subject = contexts |> List.first() |> Map.fetch!(:subject)

    labels =
      contexts
      |> Enum.map(&class_label/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()

    subject <> " · " <> Enum.join(labels, "+")
  end

  defp class_label(%TeachingContext{class_group: %{label: label}}) when is_binary(label),
    do: label

  defp class_label(%TeachingContext{level: level, serie: nil}), do: level
  defp class_label(%TeachingContext{level: level, serie: serie}), do: level <> " " <> serie

  @doc """
  Splits a `CombinedCourse` apart: unlinks every member context
  (`combined_course_id` back to `nil`), destroys the course's shared
  `ProgressionPlan` (a split discards the shared fiche — accepted behavior
  for this increment; the FK is `on_delete: :nilify`, so the plan is not
  auto-removed and must be destroyed explicitly), then destroys the course
  itself.
  """
  def split(%CombinedCourse{id: course_id} = course) do
    Repo.transaction(fn ->
      course
      |> Academics.contexts_of_course()
      |> Enum.each(fn ctx ->
        {:ok, _ctx, notifications} =
          ctx
          |> Ash.Changeset.for_update(:update, %{combined_course_id: nil})
          |> Ash.update(authorize?: false, return_notifications?: true)

        Ash.Notifier.notify(notifications)
      end)

      ProgressionPlan
      |> Ash.Query.filter(combined_course_id == ^course_id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      Ash.destroy!(course, authorize?: false)
    end)

    :ok
  end

  @doc """
  Lists the teaching units assigned to `user` in `ws`/`year`: each is either
  `{:solo, %TeachingContext{}}` or `{:course, %CombinedCourse{}}` — contexts
  sharing a `combined_course_id` collapse into a single course entry (once
  per course), everything else stays solo.
  """
  def list_units_for_user(ws, year, user) do
    contexts = Assignments.list_for_user(ws, year, user)

    {units, _seen} =
      Enum.reduce(contexts, {[], MapSet.new()}, fn ctx, {units, seen} ->
        case ctx.combined_course_id do
          nil ->
            {[{:solo, ctx} | units], seen}

          course_id ->
            if MapSet.member?(seen, course_id) do
              {units, seen}
            else
              {:ok, course} = Academics.get_course(course_id)
              course = Ash.load!(course, :teaching_contexts, authorize?: false)
              {[{:course, course} | units], MapSet.put(seen, course_id)}
            end
        end
      end)

    Enum.reverse(units)
  end
end
