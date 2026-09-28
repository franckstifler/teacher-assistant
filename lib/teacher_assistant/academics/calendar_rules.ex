defmodule TeacherAssistant.Academics.CalendarRules do
  @moduledoc """
  Coherence rules for a whole academic-year calendar, checked before any row is
  written. Single-row checks (see `Sequence`'s check constraints) cannot see an
  overlap between two séquences or a council date against its trimester, so the
  whole proposed calendar is validated at once.

  Dates are `Date.t()`, `nil` (blank) or `:invalid` (unparseable input). Errors are
  `{field, code}` codes keyed by row id; the UI translates them.
  """

  def validate(year, sequences, terms) do
    sequences = Enum.sort_by(sequences, & &1.number)

    errors =
      Enum.flat_map(sequences, &sequence_errors(year, &1)) ++
        order_errors(sequences) ++ Enum.flat_map(terms, &term_errors(&1, sequences))

    case Enum.group_by(errors, &elem(&1, 0), &elem(&1, 1)) do
      map when map_size(map) == 0 -> :ok
      map -> {:error, {:invalid, map}}
    end
  end

  defp sequence_errors(year, %{id: id} = seq) do
    presence =
      [
        presence_error(:start_date, seq.start_date, true),
        presence_error(:end_date, seq.end_date, true),
        presence_error(:entry_deadline, seq.entry_deadline, false)
      ]
      |> Enum.reject(&is_nil/1)

    if presence == [] do
      [
        {Date.before?(seq.end_date, seq.start_date), {:end_date, :end_before_start}},
        {Date.before?(seq.start_date, year.start_date), {:start_date, :outside_year}},
        {Date.after?(seq.end_date, year.end_date), {:end_date, :outside_year}},
        {seq.entry_deadline != nil and Date.before?(seq.entry_deadline, seq.end_date),
         {:entry_deadline, :deadline_before_end}}
      ]
      |> Enum.flat_map(fn {failed?, error} -> if failed?, do: [{id, error}], else: [] end)
    else
      Enum.map(presence, &{id, &1})
    end
  end

  defp presence_error(field, :invalid, _required?), do: {field, :invalid_date}
  defp presence_error(field, nil, true), do: {field, :required}
  defp presence_error(_field, _value, _required?), do: nil

  defp order_errors(sequences) do
    for [prev, next] <- Enum.chunk_every(sequences, 2, 1, :discard),
        match?(%Date{}, prev.end_date) and match?(%Date{}, next.start_date),
        not Date.after?(next.start_date, prev.end_date),
        do: {next.id, {:start_date, :overlaps_previous}}
  end

  defp term_errors(%{class_council_date: :invalid, id: id}, _sequences),
    do: [{id, {:class_council_date, :invalid_date}}]

  defp term_errors(%{class_council_date: %Date{} = council, id: id}, sequences) do
    ends = for %{term_id: ^id, end_date: %Date{} = d} <- sequences, do: d

    if ends != [] and Date.before?(council, Enum.max(ends, Date)),
      do: [{id, {:class_council_date, :council_before_term_end}}],
      else: []
  end

  defp term_errors(_term, _sequences), do: []
end
