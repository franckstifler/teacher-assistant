defmodule TeacherAssistant.Academics.TimetableConflicts do
  @moduledoc """
  Teacher clashes in a school timetable (spec J4, T01), pure. A clash is one teacher
  in two or more classes at the same day and period, unless every one of those slots
  belongs to the same combined course (« cours regroupé »). Suggestions fix a clash
  on a non-combined lesson: moves to an empty open cell of the class where the
  teacher is free, then swaps with another lesson of the class that leave neither
  teacher in a clash.
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

  @doc "One per (teacher, day, period) that clashes."
  def count(slots), do: slots |> clash_groups() |> length()

  @doc "Whether the teacher has a lesson at that time, ignoring the given slot ids."
  def busy?(slots, teacher_id, day, period_id, ignore_ids \\ []) do
    Enum.any?(slots, fn s ->
      s.teacher_id == teacher_id and s.day == day and s.period_id == period_id and
        s.id not in ignore_ids
    end)
  end

  @doc "Fixes for the class's lesson at `cell`, when it clashes and is not combined."
  def suggestions(slots, open_cells, class_group_id, {day, period_id} = cell) do
    slot =
      Enum.find(
        slots,
        &(&1.class_group_id == class_group_id and &1.day == day and &1.period_id == period_id)
      )

    cond do
      is_nil(slot) or not is_nil(slot.combined_course_id) -> []
      not Map.has_key?(clashes(slots), {class_group_id, day, period_id}) -> []
      true -> moves(slots, open_cells, slot, cell) ++ swaps(slots, open_cells, slot, cell)
    end
  end

  defp moves(slots, open_cells, slot, cell) do
    class_cells =
      slots
      |> Enum.filter(&(&1.class_group_id == slot.class_group_id))
      |> MapSet.new(&{&1.day, &1.period_id})

    open_cells
    |> Enum.reject(&(&1 == cell or MapSet.member?(class_cells, &1)))
    |> Enum.reject(fn {d, p} -> busy?(slots, slot.teacher_id, d, p, [slot.id]) end)
    |> Enum.take(@max)
    |> Enum.map(&%{kind: :move, to: &1})
  end

  defp swaps(slots, open_cells, slot, {day, period_id}) do
    open = MapSet.new(open_cells)

    slots
    |> Enum.filter(fn o ->
      o.class_group_id == slot.class_group_id and o.id != slot.id and is_nil(o.combined_course_id) and
        o.teacher_id != slot.teacher_id and MapSet.member?(open, {o.day, o.period_id})
    end)
    |> Enum.sort_by(fn o -> Enum.find_index(open_cells, &(&1 == {o.day, o.period_id})) end)
    |> Enum.filter(fn o ->
      not busy?(slots, slot.teacher_id, o.day, o.period_id, [slot.id, o.id]) and
        not busy?(slots, o.teacher_id, day, period_id, [slot.id, o.id])
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

  defp unit(%{combined_course_id: nil, class_group_id: cg}), do: {:class, cg}
  defp unit(%{combined_course_id: cc}), do: {:combined, cc}

  defp same_unit?(a, b), do: unit(a) == unit(b)
end
