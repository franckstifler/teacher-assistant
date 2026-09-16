defmodule TeacherAssistant.Academics.Quota do
  @moduledoc "Pure planned-vs-target gap calculation for progression quotas."

  def summarize(ctx, modules) do
    entries = Enum.flat_map(modules, &Map.get(&1, :entries, []))
    planned = sum_hours(entries)

    named_modules = Enum.reject(modules, & &1.default?)
    lesson_count = Enum.count(entries, &(&1.entry_type == :lesson))

    annual = ctx && ctx.annual_hours
    target_modules = ctx && ctx.target_module_count
    target_lessons = ctx && ctx.target_lesson_count

    per_module =
      Enum.map(modules, fn m ->
        p = sum_hours(Map.get(m, :entries, []))
        credit = Map.get(m, :credit_hours)
        %{module_id: m.id, planned: p, credit: credit, ratio: ratio(p, credit)}
      end)

    %{
      planned_hours: planned,
      annual_hours: annual,
      hours_ratio: ratio(planned, annual),
      module_count: length(named_modules),
      target_module_count: target_modules,
      lesson_count: lesson_count,
      target_lesson_count: target_lessons,
      per_module: per_module
    }
  end

  defp sum_hours(entries),
    do:
      Enum.reduce(entries, Decimal.new(0), fn e, acc ->
        Decimal.add(acc, to_decimal(e.planned_hours))
      end)

  # ratio numerator/denominator; nil when denominator is nil or zero
  defp ratio(_num, nil), do: nil

  defp ratio(num, %Decimal{} = den) do
    if Decimal.equal?(den, Decimal.new(0)), do: nil, else: Decimal.to_float(Decimal.div(num, den))
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
end
