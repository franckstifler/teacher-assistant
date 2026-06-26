defmodule TeacherAssistant.Accounts.Workspaces do
  @moduledoc "Workspace scope resolution (rebuilt in Task 3)."
  alias TeacherAssistant.Scope

  def scope_for(user, _workspace_id) do
    {:ok, %Scope{current_user: user, current_role: :teacher, current_workspace_type: :personal_teacher}}
  end
end
