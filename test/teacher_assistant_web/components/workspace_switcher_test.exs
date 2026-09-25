defmodule TeacherAssistantWeb.WorkspaceSwitcherTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  test "the switcher lists only the schools the member belongs to", %{
    conn: conn,
    actor: user,
    workspace: home_school
  } do
    {:ok, school} = Organization.create_school(user, %{name: "École Deux"})
    TeacherFixtures.complete_school_setup!(school_scope(user, school))

    other_head = TeacherFixtures.user_fixture()
    {:ok, other_school} = Organization.create_school(other_head, %{name: "École Étrangère"})

    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#workspace-switcher")
    assert has_element?(view, "#workspace-switcher-item-#{school.id}", "École Deux")
    assert has_element?(view, "#workspace-switcher-item-#{home_school.id}")
    refute has_element?(view, "#workspace-switcher-item-#{other_school.id}")
  end
end
