defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Organization, Scope}
  alias TeacherAssistant.Accounts

  def scope_for(user, workspace_id, context_id \\ nil)

  # No workspace chosen yet: default to the first school the user belongs to.
  def scope_for(user, nil, context_id) do
    case Organization.list_workspaces_for(user) do
      [ws | _] -> scope_for(user, ws.id, context_id)
      [] -> {:error, :no_workspace}
    end
  end

  def scope_for(user, workspace_id, context_id) do
    case Organization.get_workspace(workspace_id) do
      {:ok, ws} -> school_scope(user, ws, context_id)
      _ -> {:error, :workspace_not_found}
    end
  end

  defp school_scope(user, ws, context_id) do
    case Accounts.fetch_school_membership(ws, user) do
      {:ok, membership} ->
        year = Organization.current_academic_year(ws)

        status =
          case Accounts.fetch_school_profile(ws) do
            {:ok, p} -> p.verification_status
            _ -> :unverified
          end

        {:ok,
         %Scope{
           current_user: user,
           current_workspace: ws,
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
    contexts = TeacherAssistant.Curriculum.list_assignments_for_user(ws, year, user)
    Enum.find(contexts, &(&1.id == context_id)) || List.first(contexts)
  end
end
