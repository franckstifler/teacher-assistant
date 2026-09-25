defmodule TeacherAssistantWeb.LocaleTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Locale"
      })

    TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn}
  end

  test "defaults to french and switches to english", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Tableau de bord")

    conn = get(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/school"
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Dashboard")
  end
end
