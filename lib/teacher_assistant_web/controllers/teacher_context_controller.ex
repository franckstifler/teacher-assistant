defmodule TeacherAssistantWeb.TeacherContextController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(conn, %{"id" => context_id} = params) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))
    return_to = safe_return_to(params["return_to"])

    case user && Workspaces.scope_for(user, get_session(conn, :workspace_id), context_id) do
      {:ok, %{current_context: %{id: ^context_id}}} ->
        conn
        |> put_session(:context_id, context_id)
        |> redirect(to: rewrite_return_to(return_to, context_id))

      _ ->
        redirect(conn, to: ~p"/teacher/setup")
    end
  end

  # only local /teacher paths are allowed; anything else defaults to the dashboard
  defp safe_return_to("/teacher" <> _ = path), do: path
  defp safe_return_to(_), do: "/teacher"

  # if the path targets a specific class, swap its id segment to the newly selected class
  defp rewrite_return_to(path, id),
    do: Regex.replace(~r{^(/teacher/contexts/)[^/]+}, path, fn _, prefix -> prefix <> id end)

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
