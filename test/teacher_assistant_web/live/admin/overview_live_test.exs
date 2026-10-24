defmodule TeacherAssistantWeb.Admin.OverviewLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  defp signed_in(conn, user),
    do:
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(user)

  test "an operator with no school opens the console", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    {:ok, view, _html} = live(signed_in(conn, op), ~p"/admin")
    assert has_element?(view, "#admin-overview")
    assert has_element?(view, "#overview-schools-unverified")
    assert has_element?(view, "#nav-admin-schools")
  end

  test "a non-operator is redirected", %{conn: conn} do
    user = TeacherFixtures.user_fixture()
    assert {:error, {:redirect, %{to: "/"}}} = live(signed_in(conn, user), ~p"/admin")
  end
end
