defmodule TeacherAssistant.Academics.ReportCards do
  @moduledoc """
  Deterministic report-card calculations.

  AI remarks can build on these results later, but final report-card numbers
  should always come from deterministic calculations.
  """

  def summarize_student(rows) do
    present_rows = Enum.reject(rows, &is_nil(&1.score))

    {weighted_total, total_coefficient} =
      Enum.reduce(present_rows, {Decimal.new("0"), 0}, fn row, {total, coefficients} ->
        coefficient = Map.get(row, :coefficient, 1)
        weighted_score = Decimal.mult(to_decimal(row.score), Decimal.new(coefficient))

        {Decimal.add(total, weighted_score), coefficients + coefficient}
      end)

    average =
      if total_coefficient == 0 do
        Decimal.new("0.00")
      else
        weighted_total
        |> Decimal.div(Decimal.new(total_coefficient))
        |> Decimal.round(2)
      end

    %{
      total_coefficient: total_coefficient,
      weighted_total: Decimal.round(weighted_total, 2),
      average: average,
      missing_marks: Enum.count(rows, &is_nil(&1.score))
    }
  end

  def rank_students(students) do
    students
    |> Enum.sort_by(& &1.average, {:desc, Decimal})
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, nil}, fn {student, position}, {ranked, last_average, last_rank} ->
      rank =
        if last_average && Decimal.equal?(student.average, last_average) do
          last_rank
        else
          position
        end

      {[Map.put(student, :rank, rank) | ranked], student.average, rank}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
end
