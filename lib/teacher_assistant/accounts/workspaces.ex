defmodule TeacherAssistant.Accounts.Workspaces do
  alias TeacherAssistant.{Organization, Scope}
  alias TeacherAssistant.Accounts

  def scope_for(user, workspace_id, context_id \\ nil)

  # No workspace chosen yet: default to the first school the user belongs to.
  def scope_for(user, nil, context_id) do
    case Organization.list_workspaces_for(%Scope{current_user: user}) do
      [ws | _] -> scope_for(user, ws.id, context_id)
      [] -> {:error, :no_workspace}
    end
  end

  def scope_for(user, workspace_id, context_id) do
    case Organization.get_workspace(workspace_id, actor: user) do
      {:ok, ws} -> school_scope(user, ws, context_id)
      _ -> {:error, :workspace_not_found}
    end
  end

  defp school_scope(user, ws, context_id) do
    base = %Scope{current_user: user, current_workspace: ws}

    case Accounts.fetch_school_membership(base, user) do
      {:ok, membership} ->
        year = Organization.current_academic_year(base)

        status =
          case Accounts.fetch_school_profile(base) do
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
           current_context: resolve_assigned_context(base, year, user, context_id),
           school_verification_status: status
         }}

      {:error, :not_a_member} ->
        {:error, :not_a_member}
    end
  end

  defp resolve_assigned_context(_scope, nil, _user, _context_id), do: nil

  defp resolve_assigned_context(%Scope{} = scope, year, user, context_id) do
    contexts = TeacherAssistant.Curriculum.list_assignments_for_user(scope, year, user)
    Enum.find(contexts, &(&1.id == context_id)) || List.first(contexts)
  end

  @doc """
  The scope for a request: `scope_for/3` when the user is an active member of a
  school, otherwise a user-only scope (or an empty one when signed out). Shared
  by `TeacherAssistantWeb.LiveUserAuth` and `TeacherAssistantWeb.Plug.Scope`.
  """
  def session_scope(nil, _workspace_id, _context_id), do: %Scope{}

  def session_scope(user, workspace_id, context_id) do
    case scope_for(user, workspace_id, context_id) do
      {:ok, scope} -> scope
      {:error, _} -> %Scope{current_user: user}
    end
  end
end
