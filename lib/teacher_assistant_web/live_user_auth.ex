defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  LiveView authentication and personal workspace scope assignment.
  """

  import Phoenix.Component
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Scope
  use TeacherAssistantWeb, :verified_routes

  def session_context(conn) do
    %{
      "workspace_id" => Plug.Conn.get_session(conn, :workspace_id),
      "user_id" => Plug.Conn.get_session(conn, :user_id)
    }
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/teacher")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  defp assign_scope(socket, session) do
    user = socket.assigns[:current_user] || load_user(session["user_id"])
    scope = resolve_scope(user, session["workspace_id"])

    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp resolve_scope(nil, _workspace_id), do: %Scope{}

  defp resolve_scope(user, workspace_id) do
    {:ok, scope} = Workspaces.scope_for(user, workspace_id)
    scope
  end
end
