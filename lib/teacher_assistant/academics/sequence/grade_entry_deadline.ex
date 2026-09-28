defmodule TeacherAssistant.Academics.Sequence.GradeEntryDeadline do
  @moduledoc """
  The effective grade-entry deadline of a séquence: its explicit `entry_deadline`,
  or `end_date + Reference.entry_grace_days/0` when none is set (the school default).
  """
  use Ash.Resource.Calculation

  alias TeacherAssistant.Academics.Reference

  @impl true
  def load(_query, _opts, _context), do: [:entry_deadline, :end_date]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn seq ->
      seq.entry_deadline || Date.add(seq.end_date, Reference.entry_grace_days())
    end)
  end
end
