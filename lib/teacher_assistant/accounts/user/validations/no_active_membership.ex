defmodule TeacherAssistant.Accounts.User.Validations.NoActiveMembership do
  @moduledoc """
  An account is deleted by its owner only once no school counts them as a member
  (A9): a member of a school is first removed by its head, who keeps the school's
  records straight. Internal read (`authorize?: false`).
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolMembership

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    member? =
      SchoolMembership
      |> Ash.Query.filter(user_id == ^changeset.data.id and active == true)
      |> Ash.exists?(authorize?: false)

    if member?,
      do:
        {:error,
         field: :id,
         message: "Demandez d'abord au chef d'établissement de vous retirer de l'école."},
      else: :ok
  end
end
