defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Academics, Scope}
  alias TeacherAssistant.Accounts.Schools

  def ensure_personal_workspace!(user), do: Academics.ensure_personal_workspace!(user)

  def scope_for(user, workspace_id, context_id \\ nil)

  def scope_for(user, nil, context_id) do
    ws = ensure_personal_workspace!(user)
    scope_for(user, ws.id, context_id)
  end

  def scope_for(user, workspace_id, context_id) do
    case Academics.get_personal_workspace(workspace_id) do
      {:ok, %{kind: :personal} = ws} -> personal_scope(user, ws, context_id)
      {:ok, %{kind: :school} = ws} -> school_scope(user, ws)
      _ -> {:error, :workspace_not_found}
    end
  end

  defp personal_scope(user, ws, context_id) do
    if ws.owner_user_id == user.id do
      year = Academics.current_academic_year(ws)

      {:ok,
       %Scope{
         current_user: user,
         current_workspace: ws,
         current_workspace_type: :personal_teacher,
         current_role: :teacher,
         current_roles: [:teacher],
         current_membership: nil,
         current_academic_year: year,
         current_context: Academics.resolve_current_context(ws, year, context_id)
       }}
    else
      {:error, :workspace_not_found}
    end
  end

  defp school_scope(user, ws) do
    case Schools.fetch_school_membership(ws, user) do
      {:ok, membership} ->
        {:ok,
         %Scope{
           current_user: user,
           current_workspace: ws,
           current_workspace_type: :school,
           current_role: List.first(membership.roles),
           current_roles: membership.roles,
           current_membership: membership,
           current_academic_year: nil,
           current_context: nil
         }}

      {:error, :not_a_member} ->
        {:error, :not_a_member}
    end
  end
end
