defmodule TeacherAssistant.Academics.CoefficientRules do
  @moduledoc """
  Pure coefficient-grid rules. `cells` is a map keyed `{subject_id, subsystem, level, serie}`
  (values: anything non-nil). An assignment resolves to its série's cell, else to its
  level's blank-série cell, else to nothing (not taught there).
  """

  def resolve(cells, %{subject_id: s, subsystem: sub, level: l, serie: serie}) do
    cond do
      serie != nil and Map.has_key?(cells, {s, sub, l, serie}) -> {s, sub, l, serie}
      Map.has_key?(cells, {s, sub, l, nil}) -> {s, sub, l, nil}
      true -> nil
    end
  end

  @doc """
  Checks a proposed grid edit before anything is written: every changed cell holds a
  positive coefficient or is cleared, every group is known, and no active-year class
  loses the cell it resolves to without another cell behind it.
  """
  def validate(cells, cell_changes, group_changes, assignments) do
    proposed =
      Enum.reduce(cell_changes, cells, fn
        {key, nil}, acc -> Map.delete(acc, key)
        {_key, :invalid}, acc -> acc
        {key, value}, acc -> Map.put(acc, key, value)
      end)

    errors =
      for({key, :invalid} <- cell_changes, do: {key, :invalid_coefficient}) ++
        for({subject_id, :invalid} <- group_changes, do: {{:group, subject_id}, :invalid_group}) ++
        in_use_errors(cells, proposed, assignments)

    case Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1)) do
      map when map_size(map) == 0 -> :ok
      map -> {:error, {:invalid, map}}
    end
  end

  defp in_use_errors(cells, proposed, assignments) do
    assignments
    |> Enum.flat_map(fn a ->
      current = resolve(cells, a)
      if current != nil and resolve(proposed, a) == nil, do: [{current, a.class_label}], else: []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {key, labels} -> {key, {:in_use, labels |> Enum.uniq() |> Enum.sort()}} end)
  end
end
