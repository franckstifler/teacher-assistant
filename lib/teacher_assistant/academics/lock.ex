defmodule TeacherAssistant.Academics.Lock do
  @moduledoc """
  Marks lock the day after their séquence's grade-entry deadline, in Cameroon time
  (spec D3b). The deadline day itself is still open.
  """
  alias TeacherAssistant.Academics.Reference

  def locked?(%{grade_entry_deadline: %Date{} = deadline}, %Date{} = today \\ Reference.today()),
    do: Date.after?(today, deadline)

  @doc "The séquence of `sequence_id`, with its deadline, read in the scope of `context`."
  def fetch_sequence(sequence_id, context) do
    Ash.get(TeacherAssistant.Academics.Sequence, sequence_id,
      scope: context,
      load: [:grade_entry_deadline]
    )
  end

  @doc """
  Whether writes to `sequence_id` are `:open` or `:locked`, read in the scope of `context`.
  `:missing` when there is no such séquence (the write reports its own FK error). Any other
  read error is returned as is, so that callers refuse the write instead of failing open.
  """
  def sequence_state(nil, _context), do: :missing

  def sequence_state(sequence_id, context) do
    case Ash.get(TeacherAssistant.Academics.Sequence, sequence_id,
           scope: context,
           load: [:grade_entry_deadline],
           not_found_error?: false
         ) do
      {:ok, nil} -> :missing
      {:ok, seq} -> if locked?(seq), do: :locked, else: :open
      {:error, error} -> {:error, error}
    end
  end
end
