defmodule TeacherAssistant.Academics.Timetables do
  @moduledoc "Bell schedule periods and class timetables for a workspace (P2.7)."

  require Ash.Query

  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Academics.Workspace

  def list_periods(%Workspace{id: ws_id}) do
    Period
    |> Ash.Query.filter(workspace_id == ^ws_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def build_default_periods(%Workspace{} = ws) do
    case list_periods(ws) do
      [] ->
        Enum.each(Reference.default_periods_preset(), fn preset ->
          Period
          |> Ash.Changeset.for_create(:create, Map.put(preset, :workspace_id, ws.id))
          |> Ash.create!(authorize?: false)
        end)

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Places a teaching context into a (day, period) cell of a class's timetable.

  Rejects a `teaching_context_id` that doesn't belong to `class_group` with
  `{:error, :invalid}`. Rejects a placement that would double-book the
  context's teacher in another class at the same (workspace, day, period)
  with `{:error, {:teacher_clash, other_class_label}}`. Otherwise upserts the
  cell (replacing any current occupant) and returns `{:ok, slot}`.
  """
  def place_slot(%ClassGroup{} = cg, %{
        day: day,
        period_id: period_id,
        teaching_context_id: teaching_context_id
      }) do
    with {:ok, %TeachingContext{class_group_id: cg_id} = tc} when cg_id == cg.id <-
           Ash.get(TeachingContext, teaching_context_id, authorize?: false) do
      case teacher_clash(cg, day, period_id, tc.teacher_user_id) do
        {:clash, class_label} ->
          {:error, {:teacher_clash, class_label}}

        :ok ->
          upsert_slot(cg, day, period_id, teaching_context_id)
      end
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Clears the (day, period) cell of a class's timetable, if occupied. Always
  returns `:ok`.
  """
  def clear_slot(%ClassGroup{id: cg_id}, day, period_id) do
    TimetableSlot
    |> Ash.Query.filter(class_group_id == ^cg_id and day == ^day and period_id == ^period_id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))

    :ok
  end

  defp teacher_clash(%ClassGroup{id: cg_id, workspace_id: ws_id}, day, period_id, teacher_user_id) do
    TimetableSlot
    |> Ash.Query.filter(
      workspace_id == ^ws_id and day == ^day and period_id == ^period_id and
        class_group_id != ^cg_id
    )
    |> Ash.Query.load(:teaching_context)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn slot -> slot.teaching_context.teacher_user_id == teacher_user_id end)
    |> case do
      nil ->
        :ok

      slot ->
        {:ok, class_group} = Ash.get(ClassGroup, slot.class_group_id, authorize?: false)
        {:clash, class_group.label}
    end
  end

  defp upsert_slot(%ClassGroup{id: cg_id, workspace_id: ws_id}, day, period_id, teaching_context_id) do
    TimetableSlot
    |> Ash.Query.filter(class_group_id == ^cg_id and day == ^day and period_id == ^period_id)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        TimetableSlot
        |> Ash.Changeset.for_create(:create, %{
          class_group_id: cg_id,
          teaching_context_id: teaching_context_id,
          period_id: period_id,
          day: day,
          workspace_id: ws_id
        })
        |> Ash.create(authorize?: false)

      %TimetableSlot{} = slot ->
        slot
        |> Ash.Changeset.for_update(:update, %{teaching_context_id: teaching_context_id})
        |> Ash.update(authorize?: false)
    end
  end
end
