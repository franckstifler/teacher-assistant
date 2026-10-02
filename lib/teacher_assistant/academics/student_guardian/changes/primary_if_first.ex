defmodule TeacherAssistant.Academics.StudentGuardian.Changes.PrimaryIfFirst do
  @moduledoc "A student's first guardian link becomes the main contact."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.StudentGuardian

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      student_id = Ash.Changeset.get_attribute(changeset, :student_id)

      # Bookkeeping read after the action's own policy passed.
      has_primary? =
        StudentGuardian
        |> Ash.Query.filter(student_id == ^student_id and primary_contact == true)
        |> Ash.Query.set_tenant(changeset.tenant)
        |> Ash.exists?(authorize?: false)

      Ash.Changeset.force_change_attribute(changeset, :primary_contact, not has_primary?)
    end)
  end
end
