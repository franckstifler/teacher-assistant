defmodule TeacherAssistantWeb.School.MyTimetableLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(head, %{name: "Lycée T"})
    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(cg, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      tc: tc,
      period: period,
      head: head
    }
  end

  test "a teacher with placed slots sees class + subject in their cell", %{
    conn: conn,
    cg: cg,
    period: period
  } do
    {:ok, _view, html} = live(conn, ~p"/school/timetable/me")

    assert html =~ "Mon emploi du temps"
    assert html =~ period.label
    assert html =~ "Lundi"
    assert html =~ "Samedi"
    assert html =~ cg.label
    assert html =~ "Maths"
  end

  test "a member who teaches nothing sees an empty grid and empty state", %{
    school: school,
    head: head
  } do
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, member)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, member.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, _view, html} = live(conn, ~p"/school/timetable/me")

    refute html =~ "Maths"
    assert html =~ "vide" or html =~ "empty" or html =~ "aucun" or html =~ "Aucun"
  end

  test "a non-school scope is redirected to /school", %{} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/timetable/me")
  end
end
