defmodule TeacherAssistant.Academics.ClassGroup.FormMasterIsMember do
  @moduledoc """
  A class's form master is an active member of its school, whichever path sets it
  (the « Nouvelle classe » drawer, the Enseignements tab, a direct action call).
  Internal read (`authorize?: false`): the check must see the membership whatever
  the actor may read.
  """
  use Ash.Resource.Validation
  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Accounts.SchoolMembership

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :form_master_user_id) do
      nil -> :ok
      user_id -> check(user_id, changeset.tenant)
    end
  end

  # A single-record update carries its record: the check runs before the write.
  @impl true
  def atomic(changeset, opts, context) do
    if match?(%{__meta__: %{state: :loaded}}, changeset.data),
      do: validate(changeset, opts, context),
      else: {:not_atomic, "FormMasterIsMember reads the membership"}
  end

  defp check(user_id, tenant) do
    SchoolMembership
    |> Ash.Query.for_read(:for_workspace_and_user, %{user_id: user_id},
      tenant: tenant,
      authorize?: false
    )
    |> Ash.read_one()
    |> case do
      {:ok, %SchoolMembership{}} ->
        :ok

      _ ->
        {:error,
         field: :form_master_user_id,
         message: gettext("Le professeur principal doit être membre de l'établissement.")}
    end
  end
end
