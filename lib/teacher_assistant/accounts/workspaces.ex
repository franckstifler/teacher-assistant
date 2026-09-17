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
      {:ok, %{kind: :school} = ws} -> school_scope(user, ws, context_id)
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

  defp school_scope(user, ws, context_id) do
    case Schools.fetch_school_membership(ws, user) do
      {:ok, membership} ->
        year = Academics.current_academic_year(ws)

        status =
          case Schools.fetch_school_profile(ws) do
            {:ok, p} -> p.verification_status
            _ -> :unverified
          end

        {:ok,
         %Scope{
           current_user: user,
           current_workspace: ws,
           current_workspace_type: :school,
           current_role: List.first(membership.roles),
           current_roles: membership.roles,
           current_membership: membership,
           current_academic_year: year,
           current_context: resolve_assigned_context(ws, year, user, context_id),
           school_verification_status: status
         }}

      {:error, :not_a_member} ->
        {:error, :not_a_member}
    end
  end

  defp resolve_assigned_context(_ws, nil, _user, _context_id), do: nil

  defp resolve_assigned_context(ws, year, user, context_id) do
    contexts = TeacherAssistant.Academics.Assignments.list_for_user(ws, year, user)
    Enum.find(contexts, &(&1.id == context_id)) || List.first(contexts)
  end
end
