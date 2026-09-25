defmodule TeacherAssistantWeb.TeacherContextController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces

  def select(%{assigns: %{current_user: nil}} = conn, _params) do
    redirect(conn, to: ~p"/sign-in")
  end

  def select(conn, %{"id" => context_id} = params) do
    user = conn.assigns.current_user
    return_to = safe_return_to(params["return_to"])

    case Workspaces.scope_for(user, get_session(conn, :workspace_id), context_id) do
      {:ok, %{current_context: %{id: ^context_id}}} ->
        conn
        |> put_session(:context_id, context_id)
        |> redirect(to: rewrite_return_to(return_to, context_id))

      _ ->
        redirect(conn, to: ~p"/school")
    end
  end

  # only local teaching/school paths are allowed; anything else defaults to the school dashboard
  defp safe_return_to("/teacher/contexts/" <> _ = path), do: path
  defp safe_return_to("/school" <> _ = path), do: path
  defp safe_return_to(_), do: "/school"

  # if the path targets a specific class, swap its id segment to the newly selected class
  defp rewrite_return_to(path, id),
    do: Regex.replace(~r{^(/teacher/contexts/)[^/]+}, path, fn _, prefix -> prefix <> id end)
end
