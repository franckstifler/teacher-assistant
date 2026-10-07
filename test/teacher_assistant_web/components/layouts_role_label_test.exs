defmodule TeacherAssistantWeb.LayoutsRoleLabelTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "the rail names the member's role in words, not the internal name", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school")
    rail = view |> element("aside[aria-label]") |> render()

    assert rail =~ "Chef d&#39;établissement" or rail =~ "Chef d'établissement"
    refute rail =~ ~r/·\s*head\b/i
  end
end
