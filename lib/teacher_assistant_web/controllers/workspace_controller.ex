defmodule TeacherAssistantWeb.WorkspaceController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(conn, %{"id" => workspace_id}) do
    user = conn.assigns.current_user

    case Workspaces.scope_for(user, workspace_id) do
      {:ok, _scope} ->
        conn
        |> put_session(:workspace_id, workspace_id)
        |> put_flash(:info, gettext("Workspace selected"))
        |> redirect(to: ~p"/school")

      {:error, _} ->
        conn
        |> delete_session(:workspace_id)
        |> put_flash(:error, gettext("Workspace not found or access denied"))
        |> redirect(to: ~p"/school")
    end
  end
end
