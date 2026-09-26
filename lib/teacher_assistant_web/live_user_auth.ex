defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  LiveView authentication and workspace scope assignment.
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

  # Navigation capabilities for the layout, computed once per mount from the
  # policies (never in render). A scope without a school has none.
  def on_mount(:assign_capabilities, _params, _session, socket) do
    case socket.assigns.current_scope do
      %{current_workspace: %{}} = scope ->
        capabilities = %{
          manage_staff: TeacherAssistant.Accounts.can_manage_staff?(scope),
          manage_school: TeacherAssistant.Organization.can_manage_calendar?(scope)
        }

        {:cont,
         Phoenix.Component.assign(socket, :current_scope, %{scope | capabilities: capabilities})}

      _ ->
        {:cont, socket}
    end
  end

  def on_mount(:require_operator, _params, _session, socket) do
    if socket.assigns[:current_user] && socket.assigns.current_user.role == :admin do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  def on_mount(:require_teaching_scope, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope && scope.current_workspace && is_nil(scope.current_context) do
      {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_school_setup, _params, _session, socket) do
    scope = socket.assigns.current_scope

    cond do
      scope == nil or scope.current_workspace == nil ->
        {:cont, socket}

      socket.view == TeacherAssistantWeb.Onboarding.SetupWizardLive ->
        {:cont, socket}

      Scope.setup_complete?(scope) ->
        {:cont, socket}

      true ->
        {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school/setup")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/school")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    {:cont, assign_scope(socket, session)}
  end

  defp assign_scope(socket, session) do
    user = socket.assigns[:current_user] || Accounts.session_user(session["user_id"])
    locale = session["locale"] || "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)

    scope = %{
      Workspaces.session_scope(user, session["workspace_id"], session["context_id"])
      | locale: locale
    }

    socket
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
    |> assign_new(:current_path, fn -> nil end)
  end
end
