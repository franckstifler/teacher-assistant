defmodule TeacherAssistantWeb.WorkspaceSwitcherTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  test "the switcher lists every school the member belongs to", %{
    conn: conn,
    actor: user,
    workspace: home_school
  } do
    {:ok, school} = Organization.create_school(user, %{name: "École Deux"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#workspace-switcher")
    assert has_element?(view, "#workspace-switcher-item-#{school.id}", "École Deux")
    assert has_element?(view, "#workspace-switcher-item-#{home_school.id}")
  end
end
