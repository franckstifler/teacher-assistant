defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Scope
  use TeacherAssistantWeb, :verified_routes

  def session_context(conn) do
    workspace_id =
      Plug.Conn.get_session(conn, :workspace_id) ||
        Plug.Conn.get_session(conn, :tenant)

    %{
      "workspace_id" => workspace_id,
      "user_id" => Plug.Conn.get_session(conn, :user_id)
    }
  end

  def on_mount(:current_user, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount({:role_required, roles}, _params, session, socket) do
    socket = assign_scope(socket, session)

    cond do
      !socket.assigns.current_user ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      !socket.assigns.current_scope.current_workspace ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/workspaces")}

      socket.assigns.current_scope.current_role in roles ->
        {:cont, socket}

      true ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "You are not authorized to access this page")
         |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  def on_mount(:workspace_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user && socket.assigns.current_scope.current_workspace do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/workspaces")}
    end
  end

  def on_mount(:school_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if Scope.school_context?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Switch to a school workspace to use this section")
       |> Phoenix.LiveView.redirect(to: ~p"/workspaces")}
    end
  end

  def on_mount(:personal_workspace_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    if Scope.personal_context?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(
         :error,
         "Switch to your personal workspace to use this section"
       )
       |> Phoenix.LiveView.redirect(to: ~p"/workspaces")}
    end
  end

  def on_mount(:academic_year_required, _params, session, socket) do
    socket = assign_scope(socket, session)

    cond do
      !socket.assigns.current_user ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      !socket.assigns.current_scope.current_workspace ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/workspaces")}

      Scope.academic_year_ready?(socket.assigns.current_scope) ->
        {:cont, socket}

      Scope.personal_context?(socket.assigns.current_scope) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/teacher/setup")}

      true ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup/academic-year")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  defp assign_scope(socket, session) do
    user = socket.assigns[:current_user] || load_user(session["user_id"])
    workspace_id = session["workspace_id"] || session["tenant"]
    scope = resolve_scope(user, workspace_id)

    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  defp resolve_scope(nil, _workspace_id), do: %Scope{}

  defp resolve_scope(user, workspace_id) do
    Workspaces.ensure_personal_workspace!(user)

    case Workspaces.scope_for(user, workspace_id) do
      {:ok, scope} ->
        scope

      {:error, _reason} ->
        %Scope{current_user: user}
    end
  end
end
