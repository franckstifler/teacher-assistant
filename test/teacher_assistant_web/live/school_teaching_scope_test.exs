defmodule TeacherAssistantWeb.SchoolTeachingScopeTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée G"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, user: user}
  end

  test "a member without assignments is bounced from /teacher to /school", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher")
  end

  test "an assigned teacher reaches /teacher under school scope", ctx do
    %{conn: conn, cg: cg, user: user} = ctx
    {:ok, _tc} = Assignments.assign(cg, user, %{subject: "Maths"})
    assert {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Maths"
  end

  test "personal scope still reaches /teacher", %{conn: conn, workspace: personal} do
    conn = Plug.Conn.put_session(conn, :workspace_id, personal.id)
    assert {:ok, _view, _html} = live(conn, ~p"/teacher")
  end
end
