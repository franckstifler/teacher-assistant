defmodule TeacherAssistantWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  require Ash.Query
  use TeacherAssistantWeb, :verified_routes

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

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_scope(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  defp assign_scope(socket, session) do
    user = load_user(session["user_id"])
    school = load_school(session["tenant"], user)
    scope = %TeacherAssistant.Scope{current_tenant: school, current_user: user}

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

  defp load_school(nil, nil), do: nil

  defp load_school(school_id, _user) when is_binary(school_id) do
    case Ash.get(TeacherAssistant.Academics.School, school_id, authorize?: false) do
      {:ok, school} -> school
      _ -> nil
    end
  end

  defp load_school(nil, user) do
    TeacherAssistant.Accounts.UserSchool
    |> Ash.Query.filter(user_id: user.id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{school_id: school_id}} -> load_school(school_id, user)
      _ -> nil
    end
  end
end
