defmodule TeacherAssistantWeb.WorkspaceController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(conn, %{"id" => workspace_id}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    case Workspaces.scope_for(user, workspace_id) do
      {:ok, _scope} ->
        conn
        |> put_session(:workspace_id, workspace_id)
        |> put_session(:tenant, workspace_id)
        |> put_flash(:info, "Workspace selected")
        |> redirect(to: ~p"/teacher/progression")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Select a workspace you belong to")
        |> redirect(to: ~p"/workspaces")
    end
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
