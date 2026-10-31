defmodule TeacherAssistant.Academics.TypedAbsences do
  @moduledoc """
  Spec 2026-10-30 §3: which typed records count for a period, under the class's current
  rhythm. Pure — one enrollment's records as `%{sequence_id, term_id, hours}` maps.

  A span is `{:sequence, seq_id}`, `{:term, term_id, [seq_id]}` or
  `{:year, [{term_id, [seq_id]}]}`. Per séquence, a trimester is the sum of its
  séquences (trimester records are ignored); per trimester, a trimester is its own
  record, else the sum of its séquences' records, and a séquence has no figure.
  """

  @doc "`{:ok, hours}`, or `:none` when no record contributes."
  def hours(records, {:sequence, seq_id}, :typed_per_sequence),
    do: sum(Enum.filter(records, &(&1.sequence_id == seq_id)))

  def hours(_records, {:sequence, _seq_id}, :typed_per_term), do: :none

  def hours(records, {:term, _term_id, seq_ids}, :typed_per_sequence),
    do: sum(Enum.filter(records, &(&1.sequence_id in seq_ids)))

  def hours(records, {:term, term_id, seq_ids}, :typed_per_term) do
    case Enum.filter(records, &(&1.term_id == term_id)) do
      [] -> hours(records, {:term, term_id, seq_ids}, :typed_per_sequence)
      own -> sum(own)
    end
  end

  def hours(records, {:year, terms}, rhythm) do
    terms
    |> Enum.map(fn {term_id, seq_ids} -> hours(records, {:term, term_id, seq_ids}, rhythm) end)
    |> Enum.reject(&(&1 == :none))
    |> case do
      [] ->
        :none

      found ->
        {:ok, Enum.reduce(found, Decimal.new(0), fn {:ok, h}, acc -> Decimal.add(h, acc) end)}
    end
  end

  @doc "Whether every figure the period expects has been typed."
  def complete?(records, {:sequence, seq_id}, :typed_per_sequence),
    do: Enum.any?(records, &(&1.sequence_id == seq_id))

  def complete?(_records, {:sequence, _seq_id}, :typed_per_term), do: true

  def complete?(records, {:term, _term_id, seq_ids}, :typed_per_sequence),
    do: Enum.all?(seq_ids, &complete?(records, {:sequence, &1}, :typed_per_sequence))

  def complete?(records, {:term, term_id, seq_ids}, :typed_per_term),
    do:
      Enum.any?(records, &(&1.term_id == term_id)) or
        complete?(records, {:term, term_id, seq_ids}, :typed_per_sequence)

  def complete?(records, {:year, terms}, rhythm),
    do:
      Enum.all?(terms, fn {term_id, seq_ids} ->
        complete?(records, {:term, term_id, seq_ids}, rhythm)
      end)

  defp sum([]), do: :none

  defp sum(records),
    do: {:ok, Enum.reduce(records, Decimal.new(0), &Decimal.add(&1.hours, &2))}
end
