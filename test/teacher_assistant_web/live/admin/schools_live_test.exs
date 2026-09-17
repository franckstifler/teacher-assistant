defmodule TeacherAssistantWeb.Admin.SchoolsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  @attrs %{
    name: "Lycée Op",
    school_type: :lycee,
    subsystem: :francophone,
    sector: :public,
    region: :centre,
    town: "Yaoundé"
  }

  test "a non-admin is redirected", %{conn: conn} = _ctx do
    user = TeacherFixtures.user_fixture()

    conn =
      conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, user.id)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/schools")
  end

  test "an admin sees an unverified school and verifies it", %{conn: conn} do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, @attrs)
    admin = TeacherFixtures.admin_user_fixture()

    conn =
      conn |> Phoenix.ConnTest.init_test_session(%{}) |> Plug.Conn.put_session(:user_id, admin.id)

    {:ok, view, html} = live(conn, ~p"/admin/schools")
    assert html =~ "Lycée Op"
    view |> element("#verify-#{school.id}") |> render_click()

    {:ok, p} = Schools.fetch_school_profile(school)
    assert p.verification_status == :verified
  end
end
