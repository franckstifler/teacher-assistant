defmodule TeacherAssistantWeb.WorkspaceController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(conn, %{"id" => workspace_id}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    case Workspaces.scope_for(user, workspace_id) do
      {:ok, scope} ->
        to = if scope.current_workspace_type == :school, do: ~p"/school", else: ~p"/teacher"

        conn
        |> put_session(:workspace_id, workspace_id)
        |> put_flash(:info, gettext("Workspace selected"))
        |> redirect(to: to)

      {:error, _} ->
        conn
        |> delete_session(:workspace_id)
        |> put_flash(:error, gettext("Workspace not found or access denied"))
        |> redirect(to: ~p"/teacher")
    end
  end

  def create(conn, %{"school" => %{"name" => name}}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))

    case name && String.trim(name) != "" && TeacherAssistant.Accounts.Schools.create_school(user, %{name: name}) do
      {:ok, school} ->
        conn |> put_session(:workspace_id, school.id) |> redirect(to: ~p"/school")

      _ ->
        conn |> put_flash(:error, gettext("Enter a school name")) |> redirect(to: ~p"/teacher")
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
