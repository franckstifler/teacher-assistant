defmodule TeacherAssistant.Accounts do
  use Ash.Domain,
    otp_app: :teacher_assistant

  alias TeacherAssistant.Accounts.User

  resources do
    resource TeacherAssistant.Accounts.Token
    resource User
    resource TeacherAssistant.Accounts.SchoolMembership
    resource TeacherAssistant.Accounts.SchoolInvitation
    resource TeacherAssistant.Accounts.SchoolProfile
  end

  def create_user(attrs) do
    User
    |> Ash.Changeset.for_create(:register_with_password, attrs)
    |> Ash.create(authorize?: false)
  end

  def get_user(id) when is_binary(id), do: Ash.get(User, id, authorize?: false)
  def get_user(_id), do: {:error, :not_found}

  def promote_to_admin(%User{} = user) do
    user |> Ash.Changeset.for_update(:promote_to_admin, %{}) |> Ash.update(authorize?: false)
  end

  def ensure_personal_workspace!(%TeacherAssistant.Accounts.User{} = user),
    do: TeacherAssistant.Academics.ensure_personal_workspace!(user)
end
