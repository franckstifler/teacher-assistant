defmodule TeacherAssistantWeb.PageController do
  use TeacherAssistantWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Entry point for the "create a school" intent.

  Registration is the same for everyone — it creates a person, not a role —
  so what differs is where you land afterwards. A signed-in user goes straight
  to school creation; a visitor is sent to register with `/schools/new` stored
  as the post-auth destination, so they arrive at school setup instead of the
  default teacher dashboard.
  """
  def start_school(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/schools/new")
    else
      conn
      |> put_session(:return_to, ~p"/schools/new")
      |> redirect(to: ~p"/register")
    end
  end
end
