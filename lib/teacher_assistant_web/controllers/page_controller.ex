defmodule TeacherAssistantWeb.PageController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Organization, Scope}

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Entry point for the "create a school" intent.

  Registration is the same for everyone — it creates a person, not a role —
  so what differs is where you land afterwards. A member of a school goes to
  that school (a teacher tapping the landing's button wants their school, not
  a second one — the in-app switcher still offers « Créer un établissement »);
  a signed-in user without a school goes straight to school creation; a
  visitor is sent to register with `/schools/new` stored as the post-auth
  destination, so they arrive at school setup instead of the default school
  dashboard.
  """
  def start_school(conn, _params), do: start_school_for(conn, conn.assigns[:current_user])

  defp start_school_for(conn, nil) do
    conn
    |> put_session(:return_to, ~p"/schools/new")
    |> redirect(to: ~p"/register")
  end

  defp start_school_for(conn, user) do
    case Organization.list_workspaces_for(%Scope{current_user: user}) do
      [] -> redirect(conn, to: ~p"/schools/new")
      [_ | _] -> redirect(conn, to: ~p"/school")
    end
  end
end
