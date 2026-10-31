defmodule TeacherAssistant.Timetabling do
  @moduledoc "Class timetables: placing/clearing teaching contexts into (day, period) cells (P2.7)."

  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.{Accounts, Curriculum}
  alias TeacherAssistant.Academics.AssignmentGrid
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.Room
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.Academics.SchoolCalendar
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableConflicts
  alias TeacherAssistant.Academics.TeacherUnavailability
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Scope

  resources do
    resource TimetableSlot do
      define :list_for_class, action: :for_class, args: [:class_group_id]

      define :list_for_teacher,
        action: :for_workspace_teacher,
        args: [:teacher_user_id, :academic_year_id]

      define :list_for_cell, action: :for_cell, args: [:class_group_id, :day, :period_id]
      define :list_for_period, action: :for_period, args: [:period_id]
    end

    resource TeacherUnavailability
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

  Spec J3: a new occupant takes its subject's default room (when active), else the
  class's home room (`room_id` nil); placing the cell's own occupant again changes
  nothing, so a room picked by hand stays.
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
    with {:ok, %TeachingContext{class_group_id: cg_id} = tc} when cg_id == cg.id <-
           Ash.get(TeachingContext, teaching_context_id, scope: scope),
         {:ok, %Period{} = period} <- Ash.get(Period, period_id, scope: scope),
         :open <- open_or_closed(scope, day, period) do
      case list_for_cell!(cg.id, day, period_id, scope: scope) do
        [%TimetableSlot{teaching_context_id: ^teaching_context_id} = slot] ->
          {:ok, slot}

        _ ->
          upsert_slot(
            scope,
            cg,
            teaching_context_id,
            period_id,
            day,
            default_room_id(scope, [tc])
          )
      end
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
      existing =
        Enum.map(contexts, &list_for_cell!(&1.class_group_id, day, period_id, scope: scope))

      case contexts do
        [] ->
          {:error, :invalid}

        _ ->
          if already_placed?(contexts, existing),
            do: {:ok, List.flatten(existing)},
            else: place_combined(scope, contexts, existing, day, period_id)
      end
    else
      :closed -> {:error, :closed_cell}
      _ -> {:error, :invalid}
    end
  end

  # Every member class's cell already holds that class's context of the course.
  defp already_placed?(contexts, existing) do
    contexts
    |> Enum.zip(existing)
    |> Enum.all?(fn
      {tc, [%TimetableSlot{teaching_context_id: id}]} -> id == tc.id
      _ -> false
    end)
  end

  # A member cell still holding the course keeps its room (maybe picked by hand) for every
  # member; otherwise the subject's default room.
  defp place_combined(scope, contexts, existing, day, period_id) do
    tc_ids = MapSet.new(contexts, & &1.id)

    room_id =
      case existing
           |> List.flatten()
           |> Enum.find(&MapSet.member?(tc_ids, &1.teaching_context_id)) do
        %TimetableSlot{room_id: room_id} -> room_id
        nil -> default_room_id(scope, contexts)
      end

    placements =
      Enum.map(contexts, fn tc ->
        %{class_group_id: tc.class_group_id, teaching_context_id: tc.id, room_id: room_id}
      end)

    TimetableSlot
    |> Ash.ActionInput.for_action(
      :place_combined,
      %{day: day, period_id: period_id, placements: placements},
      scope: scope
    )
    |> Ash.run_action()
  end

  # Spec J3: the first of the contexts' subjects with an active default room, else nil.
  defp default_room_id(scope, contexts) do
    Enum.find_value(contexts, fn
      %TeachingContext{subject_id: nil} ->
        nil

      %TeachingContext{subject_id: subject_id} ->
        with {:ok, subject} <- Ash.get(Subject, subject_id, scope: scope, load: [:default_room]),
             %Room{active?: true, id: id} <- subject.default_room do
          id
        else
          _ -> nil
        end
    end)
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
  `slot_view` is `%{teaching_context_id, subject, teacher_name, day, period_id, room_id, room_name}`
  (`teacher_name`: the name, else the e-mail; the room: the lesson's, else the class's home room, else nil).
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
  The current year's slots in the scope's school taught by `user` (`%{}` without
  a current year), as `{day, period_id} => [slot_view]`:
  a list, because a teacher may have several classes at once (a combined course, or a
  clash the editor saved — spec J4).

  `slot_view` additionally carries `class_label` so a teacher can see which
  class each cell belongs to.
  """
  def teacher_timetable(%Scope{current_academic_year: nil}, _user), do: %{}

  def teacher_timetable(%Scope{current_academic_year: year} = scope, %User{id: user_id}) do
    user_id
    # `TimetableSlot` is multitenant — pass the scope.
    |> list_for_teacher!(year.id, scope: scope)
    |> teacher_grid()
  end

  @doc """
  Spec 2026-10-31 §2: every teacher with a lesson this year, each with their
  `teacher_timetable/2` grid, by name; `[]` without a current year. One read.
  """
  def all_teacher_timetables(%Scope{current_academic_year: nil}), do: []

  def all_teacher_timetables(%Scope{current_academic_year: year} = scope) do
    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load([:room, class_group: :home_room, teaching_context: :teacher])
    |> Ash.read!(scope: scope)
    |> Enum.reject(&is_nil(&1.teaching_context.teacher))
    |> Enum.group_by(& &1.teaching_context.teacher_user_id)
    |> Enum.map(fn {_id, [slot | _] = slots} ->
      %{teacher: slot.teaching_context.teacher, grid: teacher_grid(slots)}
    end)
    |> Enum.sort_by(&String.downcase(User.display_name(&1.teacher)))
  end

  @doc """
  Spec 2026-10-31 §3: the current year's slots as `class_group_id => cell => [slot_view]`,
  each view carrying `subject_code` (the catalogue subject's code, else its name);
  `%{}` without a current year. One read.
  """
  def school_timetable(%Scope{current_academic_year: nil}), do: %{}

  def school_timetable(%Scope{current_academic_year: year} = scope) do
    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load([
      :room,
      class_group: :home_room,
      teaching_context: [:teacher, :catalog_subject]
    ])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.class_group_id)
    |> Map.new(fn {cg_id, slots} ->
      {cg_id,
       Enum.group_by(slots, &{&1.day, &1.period_id}, fn slot ->
         Map.put(slot_view(slot), :subject_code, subject_code(slot.teaching_context))
       end)}
    end)
  end

  defp subject_code(%{catalog_subject: %{code: code}}) when is_binary(code) and code != "",
    do: code

  defp subject_code(tc), do: tc.subject

  defp teacher_grid(slots) do
    slots
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
      teacher_name: User.display_name(slot.teaching_context.teacher),
      day: slot.day,
      period_id: slot.period_id,
      class_group_id: slot.class_group_id,
      # Spec J3: the lesson's room, else the class's home room.
      room_id: slot.room_id || slot.class_group.home_room_id,
      room_name: room_name(slot.room || slot.class_group.home_room)
    }

    if class_label, do: Map.put(base, :class_label, class_label), else: base
  end

  defp room_name(%Room{name: name}), do: name
  defp room_name(_none), do: nil

  defp upsert_slot(
         %Scope{} = scope,
         %ClassGroup{id: cg_id},
         teaching_context_id,
         period_id,
         day,
         room_id
       ) do
    TimetableSlot
    |> Ash.Changeset.for_create(
      :place,
      %{
        class_group_id: cg_id,
        teaching_context_id: teaching_context_id,
        period_id: period_id,
        day: day,
        room_id: room_id
      },
      scope: scope
    )
    |> Ash.create()
  end

  @doc """
  The active year's blocked times (spec J3) as a set of `{teacher_user_id, day, period_id}`;
  empty without an active year or for a scope that may not read them (admin axis only).
  """
  def unavailability(%Scope{current_academic_year: nil}), do: MapSet.new()

  def unavailability(%Scope{current_academic_year: year} = scope) do
    TeacherUnavailability
    |> Ash.Query.for_read(:for_year, %{academic_year_id: year.id}, scope: scope)
    |> Ash.read()
    |> case do
      {:ok, rows} -> MapSet.new(rows, &{&1.teacher_user_id, &1.day, &1.period_id})
      {:error, _} -> MapSet.new()
    end
  end

  @doc """
  Blocks (`blocked?` true) or frees the teacher's `cells` (`[{day, period_id}]`) in the
  active year, in one transaction; already-blocked or already-free cells are left alone.
  `{:error, :invalid}` when the user is not an active member of the school or a period
  is not one of its lesson periods.
  """
  def set_unavailable(%Scope{current_academic_year: nil}, _user_id, _cells, _blocked?),
    do: {:error, :invalid}

  def set_unavailable(%Scope{current_academic_year: year} = scope, user_id, cells, blocked?) do
    lesson_ids =
      scope
      |> TeacherAssistant.Attendance.list_periods()
      |> Enum.filter(&(&1.kind == :lesson))
      |> MapSet.new(& &1.id)

    with true <- Enum.any?(Accounts.list_members(scope), &(&1.user_id == user_id)),
         true <- Enum.all?(cells, fn {_day, p} -> MapSet.member?(lesson_ids, p) end) do
      Ash.transact([TeacherUnavailability], fn ->
        existing =
          TeacherUnavailability
          |> Ash.Query.for_read(:for_year, %{academic_year_id: year.id}, scope: scope)
          |> Ash.Query.filter(teacher_user_id == ^user_id)
          |> Ash.read!()
          |> Map.new(&{{&1.day, &1.period_id}, &1})

        cells
        |> Enum.uniq()
        |> Enum.each(fn {day, period_id} = cell ->
          case {blocked?, existing[cell]} do
            {true, nil} ->
              TeacherUnavailability
              |> Ash.Changeset.for_create(
                :create,
                %{
                  academic_year_id: year.id,
                  teacher_user_id: user_id,
                  day: day,
                  period_id: period_id
                },
                scope: scope
              )
              |> Ash.create!()

            {false, %TeacherUnavailability{} = row} ->
              Ash.destroy!(row, scope: scope)

            _ ->
              :ok
          end
        end)
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    else
      _ -> {:error, :invalid}
    end
  rescue
    error in [Ash.Error.Forbidden, Ash.Error.Invalid] -> {:error, error}
  end

  @doc "The active year's slots as plain maps for `TimetableConflicts` (specs J4, J3)."
  def school_slots(%Scope{current_academic_year: nil}), do: []

  def school_slots(%Scope{current_academic_year: year} = scope) do
    sizes = TeacherAssistant.Enrollment.class_sizes(scope, year)

    TimetableSlot
    |> Ash.Query.filter(teaching_context.academic_year_id == ^year.id)
    |> Ash.Query.load([:teaching_context, :class_group])
    |> Ash.read!(scope: scope)
    |> Enum.map(fn s ->
      %{
        id: s.id,
        class_group_id: s.class_group_id,
        day: s.day,
        period_id: s.period_id,
        teaching_context_id: s.teaching_context_id,
        teacher_id: s.teaching_context.teacher_user_id,
        combined_course_id: s.teaching_context.combined_course_id,
        # Spec J3: the effective room — the lesson's own, else the class's home room.
        room_id: s.room_id || s.class_group.home_room_id,
        home_room_id: s.class_group.home_room_id,
        class_size: Map.get(sizes, s.class_group_id, 0)
      }
    end)
  end

  @doc """
  The user's weekly load this year against their expected service (spec 2026-10-09
  §2.5), computed as the « Confier à » editor does; `service` nil when none is set.
  """
  def teacher_service(%Scope{current_academic_year: nil}, _user), do: %{load: 0, service: nil}

  def teacher_service(%Scope{current_academic_year: year} = scope, %{id: user_id}) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    member = Enum.find(Accounts.list_members(scope), &(&1.user_id == user_id))

    contexts =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id and teacher_user_id == ^user_id)
      |> Ash.read!(scope: scope)

    grid = %{
      services: %{user_id => member && member.statutory_hours},
      school_hours: profile.statutory_hours
    }

    case AssignmentGrid.loads(contexts, grid) do
      %{^user_id => %{load: load, service: service}} -> %{load: load, service: service}
      _none -> %{load: 0, service: AssignmentGrid.service(grid, user_id)}
    end
  end

  @doc """
  « Confier à un autre enseignant » (Vie scolaire redesign §1.4): the teachers who
  could take `tc` (the whole subject of that class, every slot of it) — active
  teachers other than its own, free at every one of its slots in `slots` (as
  `school_slots/1` returns them), and still within their service (theirs, else
  the school's) once its weekly hours are added, and not blocked (spec J3,
  `unavailable` as `unavailability/1` returns it) at any of those slots. Those already
  teaching that subject come first, then the lightest load, then the name. Each
  is `%{user, load, service}`; none for a combined course.
  """
  def reassign_candidates(scope, tc, slots, unavailable \\ MapSet.new())

  def reassign_candidates(
        %Scope{},
        %TeachingContext{combined_course_id: cc},
        _slots,
        _unavailable
      )
      when not is_nil(cc),
      do: []

  def reassign_candidates(
        %Scope{current_academic_year: year} = scope,
        %TeachingContext{} = tc,
        slots,
        unavailable
      ) do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    members = Accounts.list_members(scope)
    own_slots = Enum.filter(slots, &(&1.teaching_context_id == tc.id))

    contexts =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id)
      |> Ash.read!(scope: scope)

    grid = %{
      services: Map.new(members, &{&1.user_id, &1.statutory_hours}),
      school_hours: profile.statutory_hours
    }

    loads = AssignmentGrid.loads(contexts, grid)

    teaches_subject =
      contexts
      |> Enum.filter(&same_subject?(&1, tc))
      |> MapSet.new(& &1.teacher_user_id)

    for m <- members,
        :teacher in m.roles,
        m.user_id != tc.teacher_user_id,
        Enum.all?(
          own_slots,
          &(not TimetableConflicts.busy?(slots, m.user_id, &1.day, &1.period_id) and
              TimetableConflicts.available?(unavailable, m.user_id, &1.day, &1.period_id))
        ),
        load = get_in(loads, [m.user_id, :load]) || 0,
        service = AssignmentGrid.service(grid, m.user_id),
        load + (tc.weekly_hours || 0) <= service do
      %{user: m.user, load: load, service: service}
    end
    |> Enum.sort_by(
      &{not MapSet.member?(teaches_subject, &1.user.id), &1.load,
       String.downcase(User.display_name(&1.user))}
    )
  end

  defp same_subject?(%{subject_id: id}, %{subject_id: id}) when not is_nil(id),
    do: true

  defp same_subject?(a, b), do: a.subject == b.subject

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

  @doc """
  Exchanges the class's lessons at two cells, in one transaction (spec J4); each lesson
  takes its room along (spec J3).
  """
  def swap_slots(%Scope{} = scope, %ClassGroup{} = cg, {ad, ap}, {bd, bp}) do
    with {:ok, a} <- single_slot(scope, cg, ad, ap),
         {:ok, b} <- single_slot(scope, cg, bd, bp) do
      Ash.transact([TimetableSlot], fn ->
        with {:ok, _} <- set_lesson(scope, a, b),
             {:ok, _} <- set_lesson(scope, b, a) do
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

  # Puts `from`'s lesson (course and room) into `slot`'s cell.
  defp set_lesson(scope, slot, from),
    do:
      slot
      |> Ash.Changeset.for_update(
        :update,
        %{teaching_context_id: from.teaching_context_id, room_id: from.room_id},
        scope: scope
      )
      |> Ash.update()

  @doc """
  Puts the class's lesson at `{day, period_id}` in `room_id`, or back in the class's home
  room with nil (spec J3); a combined lesson changes on every member class, in one
  transaction. `{:error, :invalid}` for an empty cell or a room that is not an active
  room of the school.
  """
  def set_slot_room(%Scope{} = scope, %ClassGroup{} = cg, {day, period_id}, room_id) do
    with [slot] <- list_for_cell!(cg.id, day, period_id, scope: scope),
         :ok <- usable_room(scope, room_id) do
      slot = Ash.load!(slot, :teaching_context, scope: scope)

      slots =
        case slot.teaching_context.combined_course_id do
          nil ->
            [slot]

          course_id ->
            course_id
            |> Curriculum.contexts_of_course!(scope: scope)
            |> Enum.flat_map(&list_for_cell!(&1.class_group_id, day, period_id, scope: scope))
        end

      Ash.transact([TimetableSlot], fn ->
        Enum.reduce_while(slots, :ok, fn s, :ok ->
          s
          |> Ash.Changeset.for_update(:update, %{room_id: room_id}, scope: scope)
          |> Ash.update()
          |> case do
            {:ok, _} -> {:cont, :ok}
            {:error, error} -> {:halt, Ash.DataLayer.rollback([TimetableSlot], error)}
          end
        end)
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, _} = error -> error
      end
    else
      _ -> {:error, :invalid}
    end
  end

  defp usable_room(_scope, nil), do: :ok

  defp usable_room(scope, room_id) do
    case Ash.get(Room, room_id, scope: scope) do
      {:ok, %Room{active?: true}} -> :ok
      _ -> :invalid
    end
  end

  @doc "Every room's capacity (nil = not checked), active or not (spec J3)."
  def room_capacities(%Scope{} = scope),
    do: scope |> TeacherAssistant.Organization.list_rooms() |> Map.new(&{&1.id, &1.capacity})

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
