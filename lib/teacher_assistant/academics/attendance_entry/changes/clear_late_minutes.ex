defmodule TeacherAssistant.Academics.AttendanceEntry.Changes.ClearLateMinutes do
  @moduledoc "Spec KLM2: minutes belong to a late only; any other status clears them."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :status) == :late,
      do: changeset,
      else: Ash.Changeset.force_change_attribute(changeset, :late_minutes, nil)
  end
end
