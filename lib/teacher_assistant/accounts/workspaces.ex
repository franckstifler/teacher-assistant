defmodule TeacherAssistant.Accounts.Workspaces do
  @moduledoc """
  Compatibility wrapper for workspace session code.
  """

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Scope

  def ensure_personal_workspace!(user), do: Accounts.ensure_personal_workspace!(user)

  def scope_for(user, nil) do
    workspace = ensure_personal_workspace!(user)
    scope_for(user, workspace.id)
  end

  def scope_for(user, workspace_id) do
    with {:ok, workspace} <- Academics.get_personal_workspace(workspace_id),
         true <- workspace.owner_user_id == user.id do
      {:ok,
       %Scope{
         current_user: user,
         current_workspace: workspace,
         current_workspace_type: :personal_teacher,
         current_role: :teacher,
         current_academic_year: Academics.current_academic_year(workspace)
       }}
    else
      _ -> {:error, :workspace_not_found}
    end
  end
end
