defmodule TeacherAssistantWeb.WorkspaceSwitcherTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  test "the switcher lists member schools only", %{conn: conn, actor: user, workspace: personal} do
    {:ok, school} = Organization.create_school(user, %{name: "École Deux"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#workspace-switcher")
    assert has_element?(view, "#workspace-switcher-item-#{school.id}", "École Deux")
    refute has_element?(view, "#workspace-switcher-item-#{personal.id}")
  end
end
