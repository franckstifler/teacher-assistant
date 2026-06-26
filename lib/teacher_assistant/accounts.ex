defmodule TeacherAssistant.Accounts do
  use Ash.Domain,
    otp_app: :teacher_assistant

  alias TeacherAssistant.Accounts.User

  resources do
    resource TeacherAssistant.Accounts.Token
    resource User
  end

  def create_user(attrs) do
    User
    |> Ash.Changeset.for_create(:register_with_password, attrs)
    |> Ash.create(authorize?: false)
  end

  def get_user(id) when is_binary(id), do: Ash.get(User, id, authorize?: false)
  def get_user(_id), do: {:error, :not_found}
end
