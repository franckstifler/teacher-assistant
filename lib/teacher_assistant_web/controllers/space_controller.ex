defmodule TeacherAssistantWeb.SpaceController do
  @moduledoc """
  Switches the member's role space (spec E, R02). Only their own spaces are accepted.
  The member stays on the page they were on (`return_to`) when the new space's menu
  has it; otherwise they land on the space's home.
  """
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.Spaces

  def select(%{assigns: %{current_user: nil}} = conn, _params),
    do: redirect(conn, to: ~p"/sign-in")

  def select(conn, %{"key" => param} = params) do
    scope = conn.assigns.current_scope

    with %{current_workspace: %{}, capabilities: %{spaces: keys}} <- scope,
         key when not is_nil(key) <- Spaces.parse_key(param),
         true <- key in keys do
      space = Spaces.put_space(scope, Atom.to_string(key), counts?: false).capabilities.space
      return_to = params["return_to"]

      conn
      |> put_session(:space, Atom.to_string(key))
      |> redirect(to: if(Spaces.in_menu?(space, return_to), do: return_to, else: space.home))
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
