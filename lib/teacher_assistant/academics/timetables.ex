defmodule TeacherAssistant.Academics.Timetables do
  @moduledoc "Bell schedule periods and class timetables for a workspace (P2.7)."

  require Ash.Query

  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.User

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

  @doc """
  Builds the class's timetable grid plus a weekly-hours tally.

  Returns `%{slots: %{{day, period_id} => slot_view}, tally: [tally_row]}`.
  `slot_view` is `%{teaching_context_id, subject, teacher_email, day, period_id}`.
  `tally_row` is `%{teaching_context_id, subject, placed, required, status}`,
  one row per assignment from `Assignments.list_for_class/1` (zero-placement
  assignments included), with `status` in `[:under, :exact, :over]`.
  """
  def class_timetable(%ClassGroup{id: cg_id} = cg) do
    slots =
      TimetableSlot
      |> Ash.Query.filter(class_group_id == ^cg_id)
      |> Ash.Query.load(teaching_context: :teacher)
      |> Ash.read!(authorize?: false)

    slot_views =
      Map.new(slots, fn slot ->
        {{slot.day, slot.period_id}, slot_view(slot)}
      end)

    placed_by_tc =
      Enum.reduce(slots, %{}, fn slot, acc ->
        Map.update(acc, slot.teaching_context_id, 1, &(&1 + 1))
      end)

    tally =
      cg
      |> Assignments.list_for_class()
      |> Enum.map(fn tc ->
        placed = Map.get(placed_by_tc, tc.id, 0)
        required = tc.weekly_hours

        %{
          teaching_context_id: tc.id,
          subject: tc.subject,
          placed: placed,
          required: required,
          status: tally_status(placed, required)
        }
      end)

    %{slots: slot_views, tally: tally}
  end

  @doc """
  All slots in `workspace` taught by `user`, keyed by `{day, period_id}`.

  `slot_view` additionally carries `class_label` so a teacher can see which
  class each cell belongs to.
  """
  def teacher_timetable(%Workspace{id: ws_id}, %User{id: user_id}) do
    TimetableSlot
    |> Ash.Query.filter(
      workspace_id == ^ws_id and teaching_context.teacher_user_id == ^user_id
    )
    |> Ash.Query.load(class_group: [], teaching_context: :teacher)
    |> Ash.read!(authorize?: false)
    |> Map.new(fn slot ->
      {{slot.day, slot.period_id}, slot_view(slot, slot.class_group.label)}
    end)
  end

  defp tally_status(placed, required) when placed < required, do: :under
  defp tally_status(placed, required) when placed == required, do: :exact
  defp tally_status(_placed, _required), do: :over

  defp slot_view(slot, class_label \\ nil) do
    base = %{
      teaching_context_id: slot.teaching_context_id,
      subject: slot.teaching_context.subject,
      teacher_email: to_string(slot.teaching_context.teacher.email),
      day: slot.day,
      period_id: slot.period_id
    }

    if class_label, do: Map.put(base, :class_label, class_label), else: base
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
