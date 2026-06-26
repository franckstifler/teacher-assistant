defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Academics, Scope}

  def ensure_personal_workspace!(user), do: Academics.ensure_personal_workspace!(user)

  def scope_for(user, nil) do
    ws = ensure_personal_workspace!(user)
    scope_for(user, ws.id)
  end

  def scope_for(user, workspace_id) do
    with {:ok, ws} <- Academics.get_personal_workspace(workspace_id),
         true <- ws.owner_user_id == user.id do
      {:ok, %Scope{
        current_user: user,
        current_workspace: ws,
        current_workspace_type: :personal_teacher,
        current_role: :teacher,
        current_academic_year: nil
      }}
    else
      _ -> {:error, :workspace_not_found}
    end
  end
end
