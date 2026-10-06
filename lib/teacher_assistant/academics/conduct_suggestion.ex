defmodule TeacherAssistant.Academics.ConductSuggestion do
  @moduledoc """
  Spec KLM3 (V05): the conduct mark a student's séquence suggests under the
  school's scale (KLM2) — 20 minus the points of unjustified absence hours,
  lates and sanctions, kept within 0..20 and rounded down to the quarter —
  with the itemised deductions. Pure.
  """

  alias TeacherAssistant.Academics.{SanctionType, SchoolLifeRules}

  @max Decimal.new(20)
  @quarter Decimal.new("0.25")

  def suggest(facts, %SchoolLifeRules{} = rules) do
    deductions =
      [
        %{
          kind: :absences,
          count: facts.unjustified_hours,
          points: Decimal.mult(facts.unjustified_hours, rules.points_per_absence_hour)
        },
        %{
          kind: :retards,
          count: facts.retards,
          points: Decimal.mult(facts.retards, rules.points_per_late)
        }
        | sanction_deductions(facts.sanction_types, rules)
      ]
      |> Enum.reject(&zero_count?/1)

    total = Enum.reduce(deductions, Decimal.new(0), &Decimal.add(&1.points, &2))

    mark =
      @max
      |> Decimal.sub(total)
      |> Decimal.max(0)
      |> Decimal.min(@max)
      |> round_down_to_quarter()

    %{mark: mark, deductions: deductions}
  end

  # One deduction per sanction type, in the enum's order.
  defp sanction_deductions(types, rules) do
    counts = Enum.frequencies(types)

    for type <- SanctionType.values(), count = Map.get(counts, type), count do
      %{
        kind: {:sanction, type},
        count: count,
        points: Decimal.mult(count, rules.sanction_points[type])
      }
    end
  end

  defp zero_count?(%{count: %Decimal{} = count}), do: Decimal.equal?(count, 0)
  defp zero_count?(%{count: count}), do: count == 0

  # Summed lesson hours carry division noise (e.g. 3 × 40 min = 2.000…0001 h);
  # rounding to 10 places first keeps an exact quarter from flooring below it.
  defp round_down_to_quarter(value) do
    value
    |> Decimal.round(10)
    |> Decimal.div(@quarter)
    |> Decimal.round(0, :floor)
    |> Decimal.mult(@quarter)
    |> Decimal.normalize()
  end
end
