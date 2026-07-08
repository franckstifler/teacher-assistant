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
  Reduces a list of `%{status, justified, period: %Period{}}` entries into
  `%{justified_hours: Decimal, unjustified_hours: Decimal, retards: integer}`.
  Absence hours are summed via `period_hours/1`, split by the `justified`
  flag; `:late` entries are counted as retards; `:present` entries are
  ignored.
  """
  def totals(entries) do
    zero = Decimal.new(0)

    Enum.reduce(
      entries,
      %{justified_hours: zero, unjustified_hours: zero, retards: 0},
      fn entry, acc ->
        case entry.status do
          :absent ->
            hours = period_hours(entry.period)

            if entry.justified do
              Map.update!(acc, :justified_hours, &Decimal.add(&1, hours))
            else
              Map.update!(acc, :unjustified_hours, &Decimal.add(&1, hours))
            end

          :late ->
            Map.update!(acc, :retards, &(&1 + 1))

          _ ->
            acc
        end
      end
    )
  end
end
