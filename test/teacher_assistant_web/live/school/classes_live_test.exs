defmodule TeacherAssistantWeb.School.ClassesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée C"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, user: user}
  end

  test "lists classes with effectif", %{conn: conn, school: school, year: year} do
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    assert html =~ "6e A"
    assert html =~ "1"
  end

  test "head can create a class", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")

    view
    |> form("#class-form", %{
      "class_group" => %{"label" => "2nde C", "level" => "2nde", "serie" => "C"}
    })
    |> render_submit()

    assert render(view) =~ "2nde C"
  end

  test "delete is blocked when the class has enrollments", ctx do
    %{conn: conn, school: school, year: year} = ctx
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#class-delete-#{cg.id}") |> render_click()
    assert render(view) =~ "6e A"
  end

  test "a plain teacher member sees no admin controls and forged events are rejected", ctx do
    %{conn: _conn, school: school, year: year, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#class-form")

    render_hook(view, "create_class", %{"class_group" => %{"label" => "X", "level" => "6ème"}})
    assert Academics.list_class_groups(school, year) == []
  end

  test "no active year shows the setup gate", %{conn: conn, actor: user} do
    {:ok, school2} = Schools.create_school(user, %{name: "Lycée SansAnnée"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school2.id)
    {:ok, view, html} = live(conn, ~p"/school/classes")
    assert html =~ "année" or html =~ "year"
    assert has_element?(view, ~s(#school-classes a[href="/school/settings"]))
  end

  test "a plain teacher member sees the no-year gate without a settings link", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school2} = Schools.create_school(head, %{name: "Lycée SansAnnéeVP"})
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school2, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school2.id)

    {:ok, view, html} = live(conn, ~p"/school/classes")
    assert html =~ "année" or html =~ "year"
    refute has_element?(view, ~s(#school-classes a[href="/school/settings"]))
  end
end
