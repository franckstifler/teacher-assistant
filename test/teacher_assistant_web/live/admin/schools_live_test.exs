defmodule TeacherAssistantWeb.Admin.SchoolsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  defp signed_in(conn, user),
    do:
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

  test "a non-admin is redirected", %{conn: conn} do
    user = TeacherFixtures.user_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(conn, user), ~p"/admin/schools")
  end

  test "lists schools and filters to those awaiting verification", %{conn: conn} do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture(%{name: "Lycée Op"})
    op = TeacherFixtures.admin_user_fixture()
    {:ok, view, html} = live(signed_in(conn, op), ~p"/admin/schools")
    assert html =~ "Lycée Op"
    assert html =~ to_string(head.email)

    view |> form("#schools-filter", %{"status" => "unverified"}) |> render_change()
    assert has_element?(view, "#school-row-#{ws.id}")

    view |> form("#schools-filter", %{"status" => "verified"}) |> render_change()
    refute has_element?(view, "#school-row-#{ws.id}")
  end
end
