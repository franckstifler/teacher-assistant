defmodule TeacherAssistant.Academics.NewYearPlan do
  @moduledoc """
  Spec KLM9 (rules 7–8), pure: from the open year's classes and each student's decision,
  every class's default admis target, where each student goes, how big each new class
  would be, and the wizard's totals. Ids are the open year's: a target names the class
  whose copy receives the admis.
  """
  alias TeacherAssistant.Academics.SchoolTemplates

  @doc "The label's last word when it is letters or a number and not the level's or série's own text."
  def suffix(%{label: label, level: level, serie: serie}) do
    case String.split(label) do
      [_, _ | _] = words ->
        last = List.last(words)

        if last != level and last != serie and Regex.match?(~r/^([A-Za-z]{1,3}|\d{1,3})$/, last),
          do: last

      _ ->
        nil
    end
  end

  @doc "Each class's admis target: the next level's class (of those the school has) with the same série and suffix."
  def default_targets(classes) do
    ranks = SchoolTemplates.level_order() |> Enum.with_index() |> Map.new()

    present =
      classes
      |> Enum.map(& &1.level)
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(ranks, &1))
      |> Enum.sort_by(&Map.fetch!(ranks, &1))

    Map.new(classes, fn c -> {c.id, target(c, classes, next_level(c.level, present))} end)
  end

  defp next_level(level, present) do
    case Enum.drop_while(present, &(&1 != level)) do
      [_level, next | _] -> next
      _ -> nil
    end
  end

  defp target(_class, _classes, nil), do: nil

  defp target(class, classes, next) do
    suffix = suffix(class)

    case Enum.find(
           classes,
           &(&1.level == next and &1.serie == class.serie and suffix(&1) == suffix)
         ) do
      nil -> nil
      found -> found.id
    end
  end

  @doc "« 2025-2026 » → « 2026-2027 »; another form of name → \"\" (the admin types it)."
  def next_name(name) do
    case Regex.run(~r/^(\d{4})\s*[-\/]\s*(\d{4})$/, String.trim(name)) do
      [_, first, last] -> "#{String.to_integer(first) + 1}-#{String.to_integer(last) + 1}"
      _ -> ""
    end
  end

  @doc "Where each student goes, given the classes' targets (class id → class id or nil)."
  def placements(students, targets),
    do: Enum.map(students, &Map.merge(&1, place(&1, targets)))

  defp place(%{decision: decision, class_id: id}, targets)
       when decision in [:admis, :admis_rachat] do
    case Map.get(targets, id) do
      nil -> %{to: nil, repeater?: false, reason: :sans_classe}
      to -> %{to: to, repeater?: false, reason: nil}
    end
  end

  defp place(%{decision: :redouble, class_id: id}, _targets),
    do: %{to: id, repeater?: true, reason: nil}

  defp place(%{decision: :exclu}, _targets), do: %{to: nil, repeater?: false, reason: :exclu}
  defp place(_student, _targets), do: %{to: nil, repeater?: false, reason: :sans_decision}

  @doc "The projected size of each receiving class (by the open year's class id)."
  def sizes(placements),
    do: placements |> Enum.filter(& &1.to) |> Enum.frequencies_by(& &1.to)

  def totals(placements) do
    placed = Enum.filter(placements, & &1.to)

    %{
      reenrolled: length(placed),
      repeaters: Enum.count(placed, & &1.repeater?),
      not_reenrolled: placements |> Enum.reject(& &1.to) |> Enum.frequencies_by(& &1.reason)
    }
  end
end
