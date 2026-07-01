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
      "user_id" => Plug.Conn.get_session(conn, :user_id),
      "context_id" => Plug.Conn.get_session(conn, :context_id),
      "locale" => Plug.Conn.get_session(conn, :locale)
    }
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      socket =
        Phoenix.LiveView.attach_hook(socket, :current_path, :handle_params, fn _params,
                                                                                uri,
                                                                                socket ->
          {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
        end)

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
    locale = session["locale"] || "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)
    scope = %{resolve_scope(user, session["workspace_id"], session["context_id"]) | locale: locale}

    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
    |> assign_new(:current_path, fn -> nil end)
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp resolve_scope(nil, _workspace_id, _context_id), do: %Scope{}

  defp resolve_scope(user, workspace_id, context_id) do
    case Workspaces.scope_for(user, workspace_id, context_id) do
      {:ok, scope} -> scope
      {:error, _} -> %Scope{current_user: user}
    end
  end
end
