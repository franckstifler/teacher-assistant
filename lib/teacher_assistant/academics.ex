defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.PersonalWorkspace

  resources do
    resource PersonalWorkspace
  end

  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, ws} -> ws
      {:error, :not_found} ->
        {:ok, ws} =
          PersonalWorkspace
          |> Ash.Changeset.for_create(:create, %{name: "Personal workspace", owner_user_id: user.id})
          |> Ash.create(authorize?: false)
        ws
    end
  end

  def personal_workspace_for_user(%User{id: user_id}) do
    PersonalWorkspace
    |> Ash.Query.filter(owner_user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def get_personal_workspace(id), do: Ash.get(PersonalWorkspace, id, authorize?: false)
end
