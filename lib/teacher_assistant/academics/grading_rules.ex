defmodule TeacherAssistant.Academics.GradingRules do
  @moduledoc """
  A school's averaging rules (spec D2b-1), as a pure struct: rounding, the trimester
  and annual rules, and whether tied students share a rank. Built from the school
  profile by `TeacherAssistant.Assessment.grading_rules/1`. The struct default
  (`rounding: :none`) reproduces the historical unrounded computation for callers
  that pass no rules. `absence` (`:zero | :excluded | :makeup`) decides what an
  unjustified absence counts; its struct default is the historic `:excluded`.
  """

  defstruct trimester: :mean_of_sequences,
            annual: :mean_of_sequences,
            rounding: :none,
            shared_ranks?: true,
            absence: :excluded

  @four Decimal.new(4)

  def round_average(nil, _rules), do: nil
  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :none}), do: avg

  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :hundredth}),
    do: Decimal.round(avg, 2, :half_up)

  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :tenth}),
    do: Decimal.round(avg, 1, :half_up)

  def round_average(%Decimal{} = avg, %__MODULE__{rounding: :quarter}) do
    avg |> Decimal.mult(@four) |> Decimal.round(0, :half_up) |> Decimal.div(@four)
  end

  @doc "A subject's trimester average from its `{position_in_term, séquence average}` pairs."
  def trimester_average(sequence_averages, %__MODULE__{} = rules),
    do: sequence_averages |> trimester_mean(rules) |> round_average(rules)

  @doc "The trimester average before its final rounding (the rank tie-break)."
  def trimester_mean(sequence_averages, %__MODULE__{} = rules) do
    sequence_averages
    |> Enum.map(fn {position, avg} -> {avg, sequence_weight(position, rules)} end)
    |> weighted_mean()
  end

  @doc "A subject's annual average from `{term_position, [{position_in_term, avg}]}` entries."
  def annual_average(terms, %__MODULE__{} = rules),
    do: terms |> annual_mean(rules) |> round_average(rules)

  @doc """
  The annual average before its final rounding (the rank tie-break). Under
  `:mean_of_trimesters` the trimesters themselves are the rounded trimester averages.
  """
  def annual_mean(terms, %__MODULE__{annual: :mean_of_sequences}) do
    terms
    |> Enum.flat_map(fn {_term, seqs} -> Enum.map(seqs, fn {_pos, avg} -> {avg, 1} end) end)
    |> weighted_mean()
  end

  def annual_mean(terms, %__MODULE__{annual: :mean_of_trimesters} = rules) do
    terms
    |> Enum.map(fn {_term, seqs} -> {trimester_average(seqs, rules), 1} end)
    |> weighted_mean()
  end

  defp sequence_weight(2, %__MODULE__{trimester: :second_sequence_double}), do: 2
  defp sequence_weight(_position, _rules), do: 1

  # Mean of the present values with their weights; nil values drop out with their weight.
  defp weighted_mean(pairs) do
    present = Enum.reject(pairs, fn {avg, _w} -> is_nil(avg) end)
    total_weight = present |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total_weight == 0 do
      nil
    else
      present
      |> Enum.reduce(Decimal.new(0), fn {avg, w}, acc ->
        Decimal.add(acc, Decimal.mult(avg, w))
      end)
      |> Decimal.div(Decimal.new(total_weight))
    end
  end

  @doc """
  Ranks by (rounded) `average`, best first. With `shared_ranks?`, equal averages share a
  rank (ex æquo); otherwise ties are broken by the unrounded `precise` average, then by
  `name`, so every graded entry gets its own rank.
  """
  def ranks(entries, %__MODULE__{shared_ranks?: shared?}) do
    ordered =
      entries
      |> Enum.reject(&is_nil(&1.average))
      |> Enum.sort(&ranks_before?(&1, &2, shared?))

    {ranks, _} =
      ordered
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, nil}, fn {entry, position}, {acc, prev} ->
        rank =
          case prev do
            {prev_avg, prev_rank} when shared? ->
              if Decimal.equal?(prev_avg, entry.average), do: prev_rank, else: position

            _ ->
              position
          end

        {Map.put(acc, entry.id, rank), {entry.average, rank}}
      end)

    ranks
  end

  defp ranks_before?(a, b, shared?) do
    case Decimal.compare(a.average, b.average) do
      :gt -> true
      :lt -> false
      :eq when shared? -> true
      :eq -> precise_before?(a, b)
    end
  end

  defp precise_before?(a, b) do
    case Decimal.compare(a.precise || a.average, b.precise || b.average) do
      :gt -> true
      :lt -> false
      :eq -> Map.get(a, :name, "") <= Map.get(b, :name, "")
    end
  end
end
