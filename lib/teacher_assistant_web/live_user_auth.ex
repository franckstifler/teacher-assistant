defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  LiveView authentication and workspace scope assignment.
  """

  import Phoenix.Component
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Scope
  alias TeacherAssistantWeb.Impersonation
  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def session_context(conn) do
    %{
      "workspace_id" => Plug.Conn.get_session(conn, :workspace_id),
      "context_id" => Plug.Conn.get_session(conn, :context_id),
      "locale" => Plug.Conn.get_session(conn, :locale),
      "space" => Plug.Conn.get_session(conn, :space),
      "impersonation" => Plug.Conn.get_session(conn, :impersonation)
    }
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)
    user = socket.assigns.current_user
    impersonation = socket.assigns.current_scope.impersonation

    cond do
      is_nil(user) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      # Over or no longer allowed: a full request, where `Plug.EndImpersonation` ends it.
      socket.assigns[:impersonation_ended?] ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin")}

      # The operator acting as a member never changes that member's password nor
      # deletes their account.
      impersonation &&
          socket.view in [
            TeacherAssistantWeb.Account.PasswordLive,
            TeacherAssistantWeb.Account.AccountLive
          ] ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           gettext("Pas pendant que vous agissez en tant que ce membre.")
         )
         |> Phoenix.LiveView.redirect(to: ~p"/school")}

      # A temporary password must be replaced before anything else (spec
      # 2026-10-07); the change screen itself is the only exception.
      user.must_change_password and is_nil(impersonation) and
          socket.view != TeacherAssistantWeb.Account.PasswordLive ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/account/password")}

      true ->
        socket = end_impersonation_on_time(socket, impersonation)

        socket =
          Phoenix.LiveView.attach_hook(socket, :current_path, :handle_params, fn _params,
                                                                                 uri,
                                                                                 socket ->
            {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
          end)

        {:cont, socket}
    end
  end

  # Navigation capabilities for the layout, computed once per mount from the
  # policies (never in render). A scope without a school has none.
  def on_mount(:assign_capabilities, _params, _session, socket) do
    case socket.assigns.current_scope do
      %{current_workspace: %{}} = scope ->
        capabilities = %{
          manage_staff: TeacherAssistant.Accounts.can_manage_staff?(scope),
          manage_school: TeacherAssistant.Organization.can_manage_calendar?(scope),
          workspaces:
            TeacherAssistant.Organization.list_workspaces_for(%Scope{
              current_user: scope.current_user
            })
        }

        {:cont,
         Phoenix.Component.assign(socket, :current_scope, %{scope | capabilities: capabilities})}

      _ ->
        {:cont, socket}
    end
  end

  # The member's role spaces and the current one (spec E), for the layout and the
  # /school landing. Navigation only — never an authorization input.
  def on_mount(:assign_space, _params, session, socket) do
    # Badges only once connected: the first HTTP render would compute them for nothing.
    scope =
      TeacherAssistantWeb.Spaces.put_space(socket.assigns.current_scope, session["space"],
        counts?: Phoenix.LiveView.connected?(socket)
      )

    {:cont,
     socket
     |> Phoenix.Component.assign(:current_scope, scope)
     |> Phoenix.Component.assign(:scope, scope)}
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

  # Operator console spec §2: a suspended school's members wait on /school/suspended.
  def on_mount(:require_active_school, _params, _session, socket) do
    if Scope.suspended?(socket.assigns.current_scope),
      do: {:halt, Phoenix.LiveView.push_navigate(socket, to: ~p"/school/suspended")},
      else: {:cont, socket}
  end

  # Operator console spec §1: a screen of a module the school does not have is refused,
  # typed URL included. Menus hide it too, but this is the guard.
  def on_mount(:require_module, _params, _session, socket) do
    key = TeacherAssistant.Modules.module_for_view(socket.view)

    if key in [nil, :core] or Scope.module?(socket.assigns.current_scope, key) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(
         :error,
         gettext("Ce module n'est pas activé pour votre établissement.")
       )
       |> Phoenix.LiveView.push_navigate(to: ~p"/school")}
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

  # A page left open past the hour leaves for a full request, which ends the impersonation.
  defp end_impersonation_on_time(socket, nil), do: socket

  defp end_impersonation_on_time(socket, impersonation) do
    if Phoenix.LiveView.connected?(socket),
      do:
        Process.send_after(self(), :impersonation_over, Impersonation.remaining_ms(impersonation))

    Phoenix.LiveView.attach_hook(socket, :impersonation_over, :handle_info, fn
      :impersonation_over, socket -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/admin")}
      _message, socket -> {:cont, socket}
    end)
  end

  defp assign_scope(socket, session) do
    {user, impersonation} =
      case Impersonation.resolve(socket.assigns[:current_user], session["impersonation"]) do
        {:acting, member, impersonation} -> {member, impersonation}
        _ -> {socket.assigns[:current_user], nil}
      end

    locale = session["locale"] || "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)

    scope = %{
      Workspaces.session_scope(user, session["workspace_id"], session["context_id"])
      | locale: locale,
        impersonation: impersonation
    }

    TeacherAssistant.ErrorReporting.put_scope(scope)

    socket
    |> assign(:impersonation_ended?, session["impersonation"] != nil and is_nil(impersonation))
    |> assign(:current_user, user)
    |> assign(:current_scope, scope)
    |> assign(:scope, scope)
    |> assign_new(:current_path, fn -> nil end)
  end
end
