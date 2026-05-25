defmodule TeacherAssistant.Academics.ProgrammeCoverage do
  @moduledoc """
  Deterministic programme coverage calculations for fiches de progression.
  """

  def summarize(entries) do
    planned_hours = sum_decimal(entries, :planned_hours)
    taught_hours = sum_decimal(entries, :taught_hours)

    rate =
      if Decimal.equal?(planned_hours, Decimal.new("0")) do
        Decimal.new("0.00")
      else
        taught_hours
        |> Decimal.mult(Decimal.new("100"))
        |> Decimal.div(planned_hours)
        |> Decimal.round(2)
      end

    %{
      planned_hours: Decimal.round(planned_hours, 2),
      taught_hours: Decimal.round(taught_hours, 2),
      rate: rate
    }
  end

  defp sum_decimal(entries, key) do
    Enum.reduce(entries, Decimal.new("0"), fn entry, total ->
      Decimal.add(total, to_decimal(Map.get(entry, key, Decimal.new("0"))))
    end)
  end

  defp to_decimal(nil), do: Decimal.new("0")
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
end
