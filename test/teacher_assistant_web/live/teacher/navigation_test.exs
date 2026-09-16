defmodule TeacherAssistantWeb.Teacher.NavigationTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "authenticated nav shows dashboard and log links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#main-nav")
    assert has_element?(view, "#nav-log")
    assert has_element?(view, "#locale-switch")
  end
end
