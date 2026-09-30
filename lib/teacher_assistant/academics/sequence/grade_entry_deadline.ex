defmodule TeacherAssistant.Academics.Sequence.GradeEntryDeadline do
  @moduledoc """
  The effective grade-entry deadline of a séquence: its explicit `entry_deadline`,
  or `end_date +` the school's `entry_grace_days` when none is set (spec D3b).
  """
  use Ash.Resource.Calculation

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.Reference

  @impl true
  def load(_query, _opts, _context), do: [:entry_deadline, :end_date, :workspace_id]

  @impl true
  def calculate(records, _opts, _context) do
    grace =
      records
      |> Enum.map(& &1.workspace_id)
      |> Enum.uniq()
      |> Map.new(&{&1, grace_days(&1)})

    Enum.map(records, fn seq ->
      seq.entry_deadline || Date.add(seq.end_date, grace[seq.workspace_id])
    end)
  end

  # A school setting, not member data: read without an actor so every caller (screens,
  # the marks lock) computes the same deadline.
  defp grace_days(workspace_id) do
    SchoolProfile
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: workspace_id}, authorize?: false)
    |> Ash.read_one()
    |> case do
      {:ok, %{entry_grace_days: days}} -> days
      _ -> Reference.entry_grace_days()
    end
  end
end
