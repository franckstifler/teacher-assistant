defmodule TeacherAssistantWeb.School.RolesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "shows rights × roles, read only", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#roles-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/roles")
    html = render(view)
    assert html =~ "Gérer la discipline et la conduite"
    assert html =~ "Surveillant général"
    assert html =~ "ses cours"
    assert html =~ "Les droits suivent le rôle"
    refute has_element?(view, "form")
  end

  test "a plain teacher is sent back to settings", %{workspace: ws, scope: scope} do
    teacher = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn, ~p"/school/settings/roles")
  end
end
