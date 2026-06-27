defmodule TeacherAssistant.Academics.Coverage do
  @moduledoc "Pure taux-de-couverture calculation (planned vs covered hours)."

  def summarize(entries, logs) do
    logs_by_entry =
      logs
      |> Enum.group_by(& &1.progression_entry_id)
      |> Map.new(fn {eid, list} -> {eid, sum_hours(list)} end)

    per_entry =
      Enum.map(entries, fn e ->
        planned = to_decimal(e.planned_hours)
        logged = Map.get(logs_by_entry, e.id, Decimal.new(0))
        covered = if Decimal.compare(logged, planned) == :gt, do: planned, else: logged

        %{
          entry_id: e.id,
          sequence_id: Map.get(e, :sequence_id),
          planned: planned,
          covered: covered
        }
      end)

    planned_total = sum_field(per_entry, :planned)
    covered_total = sum_field(per_entry, :covered)

    by_sequence =
      per_entry
      |> Enum.group_by(& &1.sequence_id)
      |> Map.new(fn {sid, list} ->
        p = sum_field(list, :planned)
        c = sum_field(list, :covered)
        {sid, %{planned: p, covered: c, rate: rate(c, p)}}
      end)

    %{
      planned_hours: planned_total,
      covered_hours: covered_total,
      rate: rate(covered_total, planned_total),
      by_sequence: by_sequence,
      per_entry: per_entry
    }
  end

  defp rate(covered, planned) do
    if Decimal.equal?(planned, Decimal.new(0)),
      do: 0.0,
      else: Decimal.to_float(Decimal.div(covered, planned))
  end

  defp sum_hours(list),
    do: Enum.reduce(list, Decimal.new(0), fn l, acc -> Decimal.add(acc, to_decimal(l.hours)) end)

  defp sum_field(list, key),
    do: Enum.reduce(list, Decimal.new(0), fn m, acc -> Decimal.add(acc, Map.fetch!(m, key)) end)

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
end
