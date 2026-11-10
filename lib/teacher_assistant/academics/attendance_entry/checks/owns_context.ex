defmodule TeacherAssistant.Academics.AttendanceEntry.Checks.OwnsContext do
  @moduledoc """
  Spec audit follow-ups A2: the roll call writes a whole class as one bulk upsert.
  The teaching context is the same for every row, so `Attendance.record_period/7`
  checks once that the signed-in teacher owns it and puts
  `context: %{roll_call: %{owner?: true}}` on the batch. This simple check reads that
  flag and spares the per-row filter query the `expr` ownership rule would run
  after each create; any other caller still goes through that rule.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the roll call's teacher owns its teaching context"

  @impl true
  def match?(_actor, %{changeset: %Ash.Changeset{context: context}}, _opts),
    do: get_in(context, [:roll_call, :owner?]) == true

  def match?(_actor, _context, _opts), do: false
end
