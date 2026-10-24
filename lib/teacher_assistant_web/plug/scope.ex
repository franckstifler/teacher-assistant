defmodule TeacherAssistantWeb.Plug.Scope do
  @moduledoc """
  Assigns `current_user` and `current_scope` for controller routes, the way
  `TeacherAssistantWeb.LiveUserAuth` does for LiveViews: the signed-in user
  (AshAuthentication's `current_user` assign, from the session token) and
  `Workspaces.session_scope/3` for the session's school and teaching context, with
  the member's role space (`TeacherAssistantWeb.Spaces.put_space/3`), without badges.
  Runs after `TeacherAssistantWeb.Plug.Locale`.
  """
  @behaviour Plug

  import Plug.Conn

  alias TeacherAssistant.Accounts.Workspaces

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    scope =
      Workspaces.session_scope(
        user,
        get_session(conn, :workspace_id),
        get_session(conn, :context_id)
      )

    # No menu badges: controller responses (photos, logos, prints) draw no menu.
    scope = TeacherAssistantWeb.Spaces.put_space(scope, get_session(conn, :space), counts?: false)

    conn
    |> assign(:current_user, user)
    |> assign(:current_scope, %{scope | locale: conn.assigns[:locale] || "fr"})
  end
end
