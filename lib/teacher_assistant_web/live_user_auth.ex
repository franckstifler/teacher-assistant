defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use TeacherAssistantWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {TeacherAssistantWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    # TODO: replace this with actual tenant fetching logic
    school = Ash.read!(TeacherAssistant.Academics.School) |> List.first()

    if socket.assigns[:current_user] do
      {:cont,
       socket
       |> assign(:scope, %TeacherAssistant.Scope{current_tenant: school, current_user: nil})}
    else
      {:cont,
       socket
       |> assign(:current_user, nil)
       |> assign(:scope, %TeacherAssistant.Scope{current_tenant: school, current_user: nil})}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end
end
