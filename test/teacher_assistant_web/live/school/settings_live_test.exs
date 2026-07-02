defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "head renames the school", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Ancien Nom"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#school-settings")
    view |> form("#school-settings", %{"school" => %{"name" => "Nouveau Nom"}}) |> render_submit()

    assert TeacherAssistant.Academics.get_personal_workspace(school.id) |> elem(1) |> Map.get(:name) ==
             "Nouveau Nom"
  end
end
