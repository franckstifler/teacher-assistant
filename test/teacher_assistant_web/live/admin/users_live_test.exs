defmodule TeacherAssistantWeb.Admin.UsersLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.TeacherFixtures

  setup %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(op)

    %{conn: conn, op: op}
  end

  test "finds a user by email and resets their password", %{conn: conn} do
    %{head_user: head} = TeacherFixtures.school_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    view |> form("#users-search", %{"q" => to_string(head.email)}) |> render_change()
    assert has_element?(view, "#user-#{head.id}")
    view |> element("#reset-user-#{head.id}") |> render_click()
    view |> element("#reset-confirm") |> render_click()
    assert has_element?(view, "#reset-password-value")
  end

  test "an operator is listed without a reset button", %{conn: conn, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/users")
    view |> form("#users-search", %{"q" => to_string(op.email)}) |> render_change()
    assert has_element?(view, "#user-#{op.id}")
    refute has_element?(view, "#reset-user-#{op.id}")
  end
end
