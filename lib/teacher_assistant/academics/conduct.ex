defmodule TeacherAssistant.Academics.Conduct do
  @moduledoc """
  Pure, deterministic conduct/attendance arithmetic (justified/unjustified
  absence hours, retards). No database access — operates on plain structs and
  maps, like `Academics.Bulletins`.
  """

  @doc """
  Hours (as a `Decimal`) covered by a `%Period{}`, computed from the minutes
  between `start_time` and `end_time`.
  """
  def period_hours(period) do
    minutes = Time.diff(period.end_time, period.start_time, :minute)
    Decimal.div(Decimal.new(minutes), Decimal.new(60))
  end

  @doc """
  Reduces `%{status, justified, period}` entries (optionally `late_minutes`)
  into `%{justified_hours, unjustified_hours, retards}`. With
  `late_as_absence_minutes`, a late of more minutes counts as an absence of
  that period (spec KLM2); a late without minutes stays a late.
  """
  def totals(entries, late_as_absence_minutes \\ nil) do
    zero = Decimal.new(0)

    Enum.reduce(
      entries,
      %{justified_hours: zero, unjustified_hours: zero, retards: 0},
      fn entry, acc ->
        case kind(entry, late_as_absence_minutes) do
          :absent ->
            key = if entry.justified, do: :justified_hours, else: :unjustified_hours
            Map.update!(acc, key, &Decimal.add(&1, period_hours(entry.period)))

          :late ->
            Map.update!(acc, :retards, &(&1 + 1))

          :ignore ->
            acc
        end
      end
    )
  end

  defp kind(%{status: :absent}, _threshold), do: :absent

  defp kind(%{status: :late} = entry, threshold) do
    minutes = Map.get(entry, :late_minutes)

    if is_integer(threshold) and is_integer(minutes) and minutes > threshold,
      do: :absent,
      else: :late
  end

  defp kind(_entry, _threshold), do: :ignore
end
