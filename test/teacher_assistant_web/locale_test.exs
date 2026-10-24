defmodule TeacherAssistantWeb.LocaleTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Locale"
      })

    TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn}
  end

  test "defaults to french and switches to english", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Tableau de bord")

    conn = get(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/school"
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#nav-school-dashboard", "Dashboard")
  end

  test "returns to the page the switch was clicked on", %{conn: conn} do
    conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/school/students?q=ab")
      |> get(~p"/locale/en")

    assert redirected_to(conn) == "/school/students?q=ab"
  end

  test "never follows a referer from another host", %{conn: conn} do
    for referer <- ["https://evil.example/school", "http://www.example.com//evil.example"] do
      conn = conn |> recycle() |> put_req_header("referer", referer) |> get(~p"/locale/en")
      assert redirected_to(conn) == "/school"
    end
  end

  test "a signed-out visitor stays on the landing page" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("referer", "http://www.example.com/")
      |> get(~p"/locale/en")

    assert redirected_to(conn) == "/"

    conn = get(Phoenix.ConnTest.build_conn(), ~p"/locale/en")
    assert redirected_to(conn) == "/"
  end
end
