defmodule TeacherAssistant.Academics.StudentGuardian.Changes.UnsetOtherPrimaries do
  @moduledoc "Before a link becomes the main contact, clears the student's previous one."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.StudentGuardian

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{id: id, student_id: student_id} = changeset.data

      StudentGuardian
      |> Ash.Query.filter(student_id == ^student_id and primary_contact == true and id != ^id)
      |> Ash.Query.set_tenant(changeset.tenant)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn link ->
        link
        |> Ash.Changeset.for_update(:unset_primary, %{},
          tenant: changeset.tenant,
          authorize?: false
        )
        |> Ash.update!()
      end)

      changeset
    end)
  end
end
