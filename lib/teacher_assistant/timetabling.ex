defmodule TeacherAssistant.Timetabling do
  @moduledoc "Class timetables: placing/clearing teaching contexts into (day, period) cells (P2.7)."

  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Period
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

      define :list_for_clash_check,
        action: :for_clash_check,
        args: [:day, :period_id, :teacher_user_id, :exclude_class_group_ids]
    end
  end

  authorization do
    authorize :when_requested
  end

  @doc """
  Places a teaching context into a (day, period) cell of a class's timetable.

  Rejects a `teaching_context_id` that doesn't belong to `class_group` with
  `{:error, :invalid}`. Rejects a placement that would double-book the
  context's teacher in another class at the same (workspace, day, period)
  with `{:error, {:teacher_clash, other_class_label}}`. Otherwise upserts the
  cell (replacing any current occupant) and returns `{:ok, slot}`.
  An optional `:exempt_class_group_ids` key lists other classes whose slots
  should NOT count as a clash against this placement — used by
  `place_combined_slot/4` so a combined course's sibling classes (the same
  teacher, deliberately, at the same cell) don't trip the clash guard
  against each other while a genuine clash with any other class still is.
  """
  def place_slot(
        %Scope{} = scope,
        %ClassGroup{} = cg,
        %{
          day: day,
          period_id: period_id,
          teaching_context_id: teaching_context_id
        } = attrs
      ) do
    exempt_class_group_ids = Map.get(attrs, :exempt_class_group_ids, [])

    with {:ok, %TeachingContext{class_group_id: cg_id} = tc} when cg_id == cg.id <-
           Ash.get(TeachingContext, teaching_context_id, scope: scope),
         {:ok, %Period{}} <- Ash.get(Period, period_id, scope: scope) do
      case teacher_clash(scope, cg, day, period_id, tc.teacher_user_id, exempt_class_group_ids) do
        {:clash, class_label} ->
          {:error, {:teacher_clash, class_label}}

        :ok ->
          upsert_slot(scope, cg, teaching_context_id, period_id, day)
      end
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Clears the (day, period) cell of a class's timetable, if occupied. Returns
  `:ok`, or `{:error, :invalid}` when `period_id` doesn't name a `Period` in
  the class's own workspace.
  """
  def clear_slot(%Scope{} = scope, %ClassGroup{id: cg_id}, day, period_id) do
    with {:ok, %Period{}} <- Ash.get(Period, period_id, scope: scope) do
      cg_id
      |> list_for_cell!(day, period_id, scope: scope)
      |> Enum.each(&Ash.destroy!(&1, scope: scope))

      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Places a `TimetableSlot` for EVERY member class of a `CombinedCourse` at
  the same `day`/`period_id`, each referencing that class's own
  teaching_context — the combined course occupies one logical cell across
  its classes. A combined course is deliberately the same teacher teaching
  several classes at once, so the member classes are exempted from the
  teacher-clash guard against each other (see `place_slot/3`'s
  `:exempt_class_group_ids`); a genuine clash against any class OUTSIDE the
  course is still rejected with `{:error, {:teacher_clash, class_label}}`.

  The clash guard is evaluated for every member class before any write is
  attempted; the writes themselves run inside `TimetableSlot`'s
  `:place_combined` action (`transaction? true`), so on any write failure
  nothing is persisted for any member class. Returns `{:ok, [slot, ...]}`
  (one per member class) or `{:error, reason}`.
  """
  def place_combined_slot(%Scope{} = scope, %CombinedCourse{} = course, day, period_id) do
    contexts =
      course.id
      |> Curriculum.contexts_of_course!(scope: scope)
      # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.load!(:class_group, scope: scope)

    with {:ok, %Period{}} <- Ash.get(Period, period_id, scope: scope) do
      case contexts do
        [] ->
          {:error, :invalid}

        _ ->
          member_class_ids = Enum.map(contexts, & &1.class_group_id)

          with :ok <- validate_no_clash(scope, contexts, day, period_id, member_class_ids) do
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
      end
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Clears the (day, period) cell for EVERY member class of a `CombinedCourse`.
  Mirrors `clear_slot/4` per member class. Returns `:ok` (idempotent —
  clearing an already-empty cell is a no-op), or `{:error, :invalid}` when
  `period_id` doesn't name a `Period` in the course's own workspace.
  """
  def clear_combined_slot(%Scope{} = scope, %CombinedCourse{} = course, day, period_id) do
    with {:ok, %Period{}} <- Ash.get(Period, period_id, scope: scope) do
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
      |> Ash.run_action!()

      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Builds the class's timetable grid plus a weekly-hours tally.

  Returns `%{slots: %{{day, period_id} => slot_view}, tally: [tally_row]}`.
  `slot_view` is `%{teaching_context_id, subject, teacher_email, day, period_id}`.
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
  All slots in the scope's school taught by `user`, keyed by `{day, period_id}`.

  `slot_view` additionally carries `class_label` so a teacher can see which
  class each cell belongs to.
  """
  def teacher_timetable(%Scope{} = scope, %User{id: user_id}) do
    user_id
    # `TimetableSlot` is multitenant — pass the scope.
    |> list_for_teacher!(scope: scope)
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
      period_id: slot.period_id,
      class_group_id: slot.class_group_id
    }

    if class_label, do: Map.put(base, :class_label, class_label), else: base
  end

  defp validate_no_clash(%Scope{} = scope, contexts, day, period_id, member_class_ids) do
    Enum.reduce_while(contexts, :ok, fn tc, :ok ->
      case teacher_clash(
             scope,
             tc.class_group,
             day,
             period_id,
             tc.teacher_user_id,
             member_class_ids
           ) do
        {:clash, class_label} -> {:halt, {:error, {:teacher_clash, class_label}}}
        :ok -> {:cont, :ok}
      end
    end)
  end

  defp teacher_clash(
         %Scope{} = scope,
         %ClassGroup{id: cg_id},
         day,
         period_id,
         teacher_user_id,
         exempt_class_group_ids
       ) do
    excluded_ids = [cg_id | exempt_class_group_ids]

    day
    # `TimetableSlot` is multitenant — pass the scope.
    |> list_for_clash_check!(period_id, teacher_user_id, excluded_ids, scope: scope)
    |> List.first()
    |> case do
      nil ->
        :ok

      slot ->
        {:ok, class_group} = Ash.get(ClassGroup, slot.class_group_id, scope: scope)
        {:clash, class_group.label}
    end
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
end
