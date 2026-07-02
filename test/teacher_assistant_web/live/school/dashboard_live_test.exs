defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Central"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end
end
