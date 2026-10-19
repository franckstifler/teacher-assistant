defmodule TeacherAssistant.Academics.TimetableConflicts do
  @moduledoc """
  Teacher clashes in a school timetable (spec J4, T01), pure. A clash is one teacher
  in two or more classes at the same day and period, unless every one of those slots
  belongs to the same combined course (« cours regroupé »). Suggestions fix a clash
  on a non-combined lesson: moves to an empty open cell of the class where the
  teacher is free, then swaps with another lesson of the class that leave neither
  teacher in a clash.

  Spec J3 adds rooms and unavailability. A slot map also carries `room_id` (its
  effective room: its own, else the class's home room, else nil), `home_room_id` and
  `class_size`; `unavailable` is a set of `{teacher_id, day, period_id}`. A **room
  clash** is one room (never nil) holding two or more units at once; an **unavailable**
  lesson sits at a time its teacher is blocked; **over capacity** (a warning, not
  counted) is a shared room smaller than the class (a combined course: its classes
  summed). A home room is never checked for capacity. Suggestions run for any counted
  problem and keep each lesson in its own room, so they avoid busy rooms and blocked
  times as well as teacher clashes.
  """

  @max 2

  @doc "Clashing cells => the other classes the teacher has at that time."
  def clashes(slots) do
    slots
    |> clash_groups()
    |> Enum.flat_map(fn group ->
      Enum.map(group, fn slot ->
        others =
          group
          |> Enum.reject(&same_unit?(&1, slot))
          |> Enum.map(& &1.class_group_id)
          |> Enum.uniq()

        {{slot.class_group_id, slot.day, slot.period_id}, others}
      end)
    end)
    |> Map.new()
  end

  @doc "Room-clashing cells => the other classes in that room at that time (spec J3)."
  def room_clashes(slots) do
    slots
    |> room_groups()
    |> Enum.flat_map(fn group ->
      Enum.map(group, fn slot ->
        others =
          group
          |> Enum.reject(&same_unit?(&1, slot))
          |> Enum.map(& &1.class_group_id)
          |> Enum.uniq()

        {cell(slot), others}
      end)
    end)
    |> Map.new()
  end

  @doc "Cells whose teacher is blocked at that time (spec J3)."
  def unavailable_cells(slots, unavailable) do
    for slot <- slots,
        not available?(unavailable, slot.teacher_id, slot.day, slot.period_id),
        into: MapSet.new(),
        do: cell(slot)
  end

  @doc """
  Cells in a shared room too small for the class — `%{size, capacity, room_id}`; a
  combined course sums its classes in that room at that time. Home rooms and rooms
  without a capacity are not checked. A warning: never counted (spec J3).
  """
  def over_capacity(slots, capacities) do
    slots
    |> Enum.filter(fn slot ->
      not is_nil(slot.room_id) and slot.room_id != slot.home_room_id and
        is_integer(capacities[slot.room_id])
    end)
    |> Enum.group_by(&{unit(&1), &1.room_id, &1.day, &1.period_id})
    |> Enum.flat_map(fn {{_unit, room_id, _day, _period}, group} ->
      size = group |> Enum.map(&(&1.class_size || 0)) |> Enum.sum()
      capacity = capacities[room_id]

      if size > capacity,
        do: Enum.map(group, &{cell(&1), %{size: size, capacity: capacity, room_id: room_id}}),
        else: []
    end)
    |> Map.new()
  end

  @doc """
  Problems to resolve: one per (teacher, day, period) that clashes, one per (room, day,
  period) that clashes, one per lesson at an unavailable time.
  """
  def count(slots, unavailable \\ MapSet.new()) do
    length(clash_groups(slots)) + length(room_groups(slots)) +
      MapSet.size(unavailable_cells(slots, unavailable))
  end

  @doc "Whether the class's lesson at the cell has a counted problem."
  def problem?(slots, unavailable, {class_group_id, day, period_id} = key) do
    Map.has_key?(clashes(slots), key) or Map.has_key?(room_clashes(slots), key) or
      Enum.any?(
        slots,
        &(&1.class_group_id == class_group_id and &1.day == day and &1.period_id == period_id and
            not available?(unavailable, &1.teacher_id, day, period_id))
      )
  end

  @doc "Whether the teacher is not blocked at that time."
  def available?(unavailable, teacher_id, day, period_id),
    do: not MapSet.member?(unavailable, {teacher_id, day, period_id})

  @doc "Whether the room holds a lesson at that time, ignoring the given slot ids; never for nil."
  def room_busy?(_slots, nil, _day, _period_id, _ignore_ids), do: false

  def room_busy?(slots, room_id, day, period_id, ignore_ids) do
    Enum.any?(slots, fn s ->
      s.room_id == room_id and s.day == day and s.period_id == period_id and
        s.id not in ignore_ids
    end)
  end

  @doc "Whether the teacher has a lesson at that time, ignoring the given slot ids."
  def busy?(slots, teacher_id, day, period_id, ignore_ids \\ []) do
    Enum.any?(slots, fn s ->
      s.teacher_id == teacher_id and s.day == day and s.period_id == period_id and
        s.id not in ignore_ids
    end)
  end

  @doc "Fixes for the class's lesson at `cell`, when it has a problem and is not combined."
  def suggestions(
        slots,
        open_cells,
        class_group_id,
        {day, period_id} = cell,
        unavailable \\ MapSet.new()
      ) do
    slot =
      Enum.find(
        slots,
        &(&1.class_group_id == class_group_id and &1.day == day and &1.period_id == period_id)
      )

    cond do
      is_nil(slot) or not is_nil(slot.combined_course_id) ->
        []

      not problem?(slots, unavailable, {class_group_id, day, period_id}) ->
        []

      true ->
        moves(slots, open_cells, slot, cell, unavailable) ++
          swaps(slots, open_cells, slot, cell, unavailable)
    end
  end

  defp moves(slots, open_cells, slot, cell, unavailable) do
    class_cells =
      slots
      |> Enum.filter(&(&1.class_group_id == slot.class_group_id))
      |> MapSet.new(&{&1.day, &1.period_id})

    open_cells
    |> Enum.reject(&(&1 == cell or MapSet.member?(class_cells, &1)))
    |> Enum.filter(fn {d, p} ->
      not busy?(slots, slot.teacher_id, d, p, [slot.id]) and
        available?(unavailable, slot.teacher_id, d, p) and
        not room_busy?(slots, slot.room_id, d, p, [slot.id])
    end)
    |> Enum.take(@max)
    |> Enum.map(&%{kind: :move, to: &1})
  end

  defp swaps(slots, open_cells, slot, {day, period_id}, unavailable) do
    open = MapSet.new(open_cells)

    slots
    |> Enum.filter(fn o ->
      o.class_group_id == slot.class_group_id and o.id != slot.id and is_nil(o.combined_course_id) and
        o.teacher_id != slot.teacher_id and MapSet.member?(open, {o.day, o.period_id})
    end)
    |> Enum.sort_by(fn o -> Enum.find_index(open_cells, &(&1 == {o.day, o.period_id})) end)
    |> Enum.filter(fn o ->
      ignore = [slot.id, o.id]

      not busy?(slots, slot.teacher_id, o.day, o.period_id, ignore) and
        not busy?(slots, o.teacher_id, day, period_id, ignore) and
        available?(unavailable, slot.teacher_id, o.day, o.period_id) and
        available?(unavailable, o.teacher_id, day, period_id) and
        not room_busy?(slots, slot.room_id, o.day, o.period_id, ignore) and
        not room_busy?(slots, o.room_id, day, period_id, ignore)
    end)
    |> Enum.take(@max)
    |> Enum.map(&%{kind: :swap, to: {&1.day, &1.period_id}, with: &1})
  end

  # Groups of slots (one teacher, one time) holding more than one unit.
  defp clash_groups(slots) do
    slots
    |> Enum.group_by(&{&1.teacher_id, &1.day, &1.period_id})
    |> Map.values()
    |> Enum.filter(fn group -> group |> Enum.map(&unit/1) |> Enum.uniq() |> length() > 1 end)
  end

  # Groups of slots (one room, one time) holding more than one unit (spec J3).
  defp room_groups(slots) do
    slots
    |> Enum.reject(&is_nil(Map.get(&1, :room_id)))
    |> Enum.group_by(&{&1.room_id, &1.day, &1.period_id})
    |> Map.values()
    |> Enum.filter(fn group -> group |> Enum.map(&unit/1) |> Enum.uniq() |> length() > 1 end)
  end

  defp cell(slot), do: {slot.class_group_id, slot.day, slot.period_id}

  defp unit(%{combined_course_id: nil, class_group_id: cg}), do: {:class, cg}
  defp unit(%{combined_course_id: cc}), do: {:combined, cc}

  defp same_unit?(a, b), do: unit(a) == unit(b)
end
