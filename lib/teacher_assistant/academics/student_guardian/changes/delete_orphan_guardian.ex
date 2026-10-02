defmodule TeacherAssistant.Academics.StudentGuardian.Changes.DeleteOrphanGuardian do
  @moduledoc "After the last link of a guardian is removed, the guardian is deleted."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.{Guardian, StudentGuardian}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, link ->
      guardian_id = link.guardian_id

      orphan? =
        not (StudentGuardian
             |> Ash.Query.filter(guardian_id == ^guardian_id)
             |> Ash.Query.set_tenant(changeset.tenant)
             |> Ash.exists?(authorize?: false))

      if orphan? do
        Guardian
        |> Ash.get!(guardian_id, tenant: changeset.tenant, authorize?: false)
        |> Ash.destroy!(tenant: changeset.tenant, authorize?: false)
      end

      {:ok, link}
    end)
  end
end
