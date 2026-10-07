defmodule TeacherAssistant.Timetabling do
  @moduledoc "Class timetables: placing/clearing teaching contexts into (day, period) cells (P2.7)."

  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Scope

  resources do
    resource TimetableSlot do
      define :list_for_class, action: :for_class, args: [:class_group_id]

      define :list_for_teacher,
        action: :for_workspace_teacher,
        args: [:teacher_user_id]

      define :list_for_cell, action: :for_cell, args: [:class_group_id, :day, :period_id]
      define :list_for_period, action: :for_period, args: [:period_id]
    end
  end

  authorization do
    authorize :by_default
  end

  @doc "Whether the scope may place and clear timetable slots (admin axis)."
  def can_edit_timetable?(scope), do: Ash.can?({TimetableSlot, :place}, scope)

  @doc """
  Places a teaching context into a (day, period) cell of a class's timetable,
  replacing any current occupant, and returns `{:ok, slot}`.

  Rejects a `teaching_context_id` that doesn't belong to `class_group`, or an unknown
  period, with `{:error, :invalid}`, and a closed cell (spec J1) with
  `{:error, :closed_cell}`. A teacher clash is saved (spec J4): the editor shows it.
  """
  def place_slot(
        %Scope{} = scope,
        %ClassGroup{} = cg,
        %{
          day: day,
          period_id: period_id,
          teaching_context_id: teaching_context_id
        }
      ) do
    with {:ok, %TeachingContext{class_group_id: cg_id}} when cg_id == cg.id <-
           Ash.get(TeachingContext, teaching_context_id, scope: scope),
         {:ok, %Period{} = period} <- Ash.get(Period, period_id, scope: scope),
         :open <- open_or_closed(scope, day, period) do
      upsert_slot(scope, cg, teaching_context_id, period_id, day)
    else
      :closed -> {:error, :closed_cell}
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Clears the (day, period) cell of a class's timetable, if occupied. Returns
  `:ok`, `{:error, :invalid}` when `period_id` doesn't name a `Period` in
  the class's own workspace, or `{:error, error}` when a destroy is refused.
  """
  def clear_slot(%Scope{} = scope, %ClassGroup{id: cg_id}, day, period_id) do
    case Ash.get(Period, period_id, scope: scope) do
      {:ok, %Period{}} ->
        cg_id
        |> list_for_cell!(day, period_id, scope: scope)
        |> Enum.reduce_while(:ok, fn slot, :ok ->
          case Ash.destroy(slot, scope: scope) do
            :ok -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)

      _ ->
        {:error, :invalid}
    end
  end

  @doc """
  Places a `TimetableSlot` for EVERY member class of a `CombinedCourse` at the same
  `day`/`period_id`, each referencing that class's own teaching context — the
  combined course occupies one logical cell across its classes, and its classes never
  clash with each other (spec J4 counts a clash with any other class, but saves it).
  The writes run inside `TimetableSlot`'s `:place_combined` action (`transaction?
  true`): on any failure nothing is persisted. Returns `{:ok, [slot, ...]}` or
  `{:error, reason}` (`:invalid`, `:closed_cell`).
  """
  def place_combined_slot(%Scope{} = scope, %CombinedCourse{} = course, day, period_id) do
    contexts =
      course.id
      |> Curriculum.contexts_of_course!(scope: scope)
      # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.load!(:class_group, scope: scope)

    with {:ok, %Period{} = period} <- Ash.get(Period, period_id, scope: scope),
         :open <- open_or_closed(scope, day, period) do
      case contexts do
        [] ->
          {:error, :invalid}

        _ ->
          placements =
            Enum.map(contexts, fn tc ->
              %{
                class_group_id: tc.class_group_id,
                teaching_context_id: tc.id
              }
            end)

          TimetableSlot
          |> Ash.ActionInput.for_action(
            :place_combined,
            %{
              day: day,
              period_id: period_id,
              placements: placements
            },
            scope: scope
          )
          |> Ash.run_action()
      end
    else
      :closed -> {:error, :closed_cell}
      _ -> {:error, :invalid}
    end
  end

  # Spec J1: lessons only in open cells of the school calendar.
  defp open_or_closed(scope, day, period) do
    if SchoolCalendar.open_cell?(TeacherAssistant.Attendance.school_calendar(scope), day, period),
      do: :open,
      else: :closed
  end

  @doc """
  Clears the (day, period) cell for EVERY member class of a `CombinedCourse`.
  Mirrors `clear_slot/4` per member class. Returns `:ok` (idempotent —
  clearing an already-empty cell is a no-op), `{:error, :invalid}` when
  `period_id` doesn't name a `Period` in the course's own workspace, or
  `{:error, error}` when the action is refused.
  """
  def clear_combined_slot(%Scope{} = scope, %CombinedCourse{} = course, day, period_id) do
    case Ash.get(Period, period_id, scope: scope) do
      {:ok, %Period{}} ->
        class_group_ids =
          course.id
          |> Curriculum.contexts_of_course!(scope: scope)
          |> Enum.map(& &1.class_group_id)

        TimetableSlot
        |> Ash.ActionInput.for_action(
          :clear_combined,
          %{
            day: day,
            period_id: period_id,
            class_group_ids: class_group_ids
          },
          scope: scope
        )
        |> Ash.run_action()
        |> case do
          {:error, error} -> {:error, error}
          _ -> :ok
        end

      _ ->
        {:error, :invalid}
    end
  end

  @doc """
  Builds the class's timetable grid plus a weekly-hours tally.

  Returns `%{slots: %{{day, period_id} => slot_view}, tally: [tally_row]}`.
  `slot_view` is `%{teaching_context_id, subject, teacher_name, day, period_id}` (`teacher_name`: the name, else the e-mail).
  `tally_row` is `%{teaching_context_id, subject, placed, required, status}`,
  one row per assignment from `Curriculum.list_assignments_for_class/1` (zero-placement
  assignments included), with `status` in `[:under, :exact, :over]`.
  """
  def class_timetable(%Scope{} = scope, %ClassGroup{id: cg_id} = cg) do
    # `:for_class` loads the multitenant `:teaching_context` — pass the scope.
    slots = list_for_class!(cg_id, scope: scope)

    slot_views =
      Map.new(slots, fn slot ->
        {{slot.day, slot.period_id}, slot_view(slot)}
      end)

    placed_by_tc =
      Enum.reduce(slots, %{}, fn slot, acc ->
        Map.update(acc, slot.teaching_context_id, 1, &(&1 + 1))
      end)

    tally =
      scope
      |> Curriculum.list_assignments_for_class(cg)
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
  All slots in the scope's school taught by `user`, as `{day, period_id} => [slot_view]`:
  a list, because a teacher may have several classes at once (a combined course, or a
  clash the editor saved — spec J4).

  `slot_view` additionally carries `class_label` so a teacher can see which
  class each cell belongs to.
  """
  def teacher_timetable(%Scope{} = scope, %User{id: user_id}) do
    user_id
    # `TimetableSlot` is multitenant — pass the scope.
    |> list_for_teacher!(scope: scope)
    |> Enum.group_by(&{&1.day, &1.period_id}, &slot_view(&1, &1.class_group.label))
    |> Map.new(fn {cell, views} -> {cell, Enum.sort_by(views, & &1.class_label)} end)
  end

  defp tally_status(placed, required) when placed < required, do: :under
  defp tally_status(placed, required) when placed == required, do: :exact
  defp tally_status(_placed, _required), do: :over

  defp slot_view(slot, class_label \\ nil) do
    base = %{
      teaching_context_id: slot.teaching_context_id,
      subject: slot.teaching_context.subject,
      teacher_name:
        to_string(slot.teaching_context.teacher.name || slot.teaching_context.teacher.email),
      day: slot.day,
      period_id: slot.period_id,
      class_group_id: slot.class_group_id
    }

    if class_label, do: Map.put(base, :class_label, class_label), else: base
  end

  defp upsert_slot(
         %Scope{} = scope,
         %ClassGroup{id: cg_id},
         teaching_context_id,
         period_id,
         day
       ) do
    TimetableSlot
    |> Ash.Changeset.for_create(
      :place,
      %{
        class_group_id: cg_id,
        teaching_context_id: teaching_context_id,
        period_id: period_id,
        day: day
      },
      scope: scope
    )
    |> Ash.create()
  end

  @doc "The active year's slots as plain maps for `TimetableConflicts` (spec J4)."
  def school_slots(%Scope{current_academic_year: nil}), do: []

  def school_slots(%Scope{current_academic_year: year} = scope) do
    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load(:teaching_context)
    |> Ash.read!(scope: scope)
    |> Enum.map(fn s ->
      %{
        id: s.id,
        class_group_id: s.class_group_id,
        day: s.day,
        period_id: s.period_id,
        teaching_context_id: s.teaching_context_id,
        teacher_id: s.teaching_context.teacher_user_id,
        combined_course_id: s.teaching_context.combined_course_id
      }
    end)
  end

  @doc """
  Moves the class's lesson at `from` to the empty, open cell `to` (spec J4). Refused
  for a combined lesson (changed on all its classes from the editor's chips).
  """
  def move_slot(%Scope{} = scope, %ClassGroup{} = cg, {fd, fp} = _from, {td, tp} = _to) do
    with {:ok, slot} <- single_slot(scope, cg, fd, fp),
         [] <- list_for_cell!(cg.id, td, tp, scope: scope),
         {:ok, %Period{} = period} <- Ash.get(Period, tp, scope: scope),
         :open <- open_or_closed(scope, td, period) do
      slot
      |> Ash.Changeset.for_update(:update, %{day: td, period_id: tp}, scope: scope)
      |> Ash.update()
      |> ok()
    else
      [_ | _] -> {:error, :occupied}
      :closed -> {:error, :closed_cell}
      {:error, _} = error -> error
      _ -> {:error, :invalid}
    end
  end

  @doc "Exchanges the class's lessons at two cells, in one transaction (spec J4)."
  def swap_slots(%Scope{} = scope, %ClassGroup{} = cg, {ad, ap}, {bd, bp}) do
    with {:ok, a} <- single_slot(scope, cg, ad, ap),
         {:ok, b} <- single_slot(scope, cg, bd, bp) do
      Ash.transact([TimetableSlot], fn ->
        with {:ok, _} <- set_context(scope, a, b.teaching_context_id),
             {:ok, _} <- set_context(scope, b, a.teaching_context_id) do
          :ok
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:ok, {:error, _} = error} -> error
        {:error, _} = error -> error
      end
    end
  end

  defp set_context(scope, slot, tc_id),
    do:
      slot
      |> Ash.Changeset.for_update(:update, %{teaching_context_id: tc_id}, scope: scope)
      |> Ash.update()

  # The class's non-combined lesson at a cell.
  defp single_slot(scope, cg, day, period_id) do
    case list_for_cell!(cg.id, day, period_id, scope: scope) do
      [slot] ->
        slot = Ash.load!(slot, :teaching_context, scope: scope)
        if slot.teaching_context.combined_course_id, do: {:error, :combined}, else: {:ok, slot}

      _ ->
        {:error, :invalid}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error
end
