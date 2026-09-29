defmodule TeacherAssistantWeb.SpaceController do
  @moduledoc "Switches the member's role space (spec E, R02). Only their own spaces are accepted."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistantWeb.Spaces

  def select(%{assigns: %{current_user: nil}} = conn, _params), do: redirect(conn, to: ~p"/sign-in")

  def select(conn, %{"key" => param}) do
    scope =
      Workspaces.session_scope(
        conn.assigns.current_user,
        get_session(conn, :workspace_id),
        get_session(conn, :context_id)
      )

    with %{current_workspace: %{}} <- scope,
         key when not is_nil(key) <- Spaces.parse_key(param),
         facts = Spaces.facts(scope),
         true <- key in Spaces.keys_for(facts) do
      conn
      |> put_session(:space, Atom.to_string(key))
      |> redirect(to: Spaces.space(key, facts).home)
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
