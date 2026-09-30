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
end
