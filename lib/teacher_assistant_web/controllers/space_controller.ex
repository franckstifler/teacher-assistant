defmodule TeacherAssistantWeb.SpaceController do
  @moduledoc "Switches the member's role space (spec E, R02). Only their own spaces are accepted."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.Spaces

  def select(%{assigns: %{current_user: nil}} = conn, _params),
    do: redirect(conn, to: ~p"/sign-in")

  def select(conn, %{"key" => param}) do
    scope = conn.assigns.current_scope

    with %{current_workspace: %{}, capabilities: %{spaces: keys}} <- scope,
         key when not is_nil(key) <- Spaces.parse_key(param),
         true <- key in keys do
      conn
      |> put_session(:space, Atom.to_string(key))
      |> redirect(to: Spaces.space(key, Spaces.facts(scope)).home)
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
