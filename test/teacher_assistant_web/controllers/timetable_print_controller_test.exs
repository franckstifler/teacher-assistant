defmodule TeacherAssistantWeb.TimetablePrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Print TT"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{conn: conn, school: school, cg: cg, period: period, head: head}
  end

  test "class timetable print shows the school, class label and a placed subject", %{
    conn: conn,
    cg: cg
  } do
    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    body = html_response(conn, 200)

    assert body =~ "Lycée Print TT"
    assert body =~ cg.label
    assert body =~ "Maths"
  end

  test "a non-admin non-form-master member is redirected from the class print", %{
    school: school,
    cg: cg,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(other)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    assert redirected_to(conn) == "/school"
  end

  test "the teacher's own timetable print shows their subject", %{conn: conn} do
    conn = get(conn, ~p"/school/timetable/me/print")
    body = html_response(conn, 200)

    assert body =~ "Maths"
  end

  test "the class print shows the room name", %{conn: conn, school: school, cg: cg, head: head} do
    scope = school_scope(head, school)
    {:ok, room} = Organization.create_room(scope, %{name: "Salle B12"})
    {:ok, _} = Enrollment.set_home_room(scope, cg, room.id)

    html = conn |> get(~p"/school/classes/#{cg.id}/timetable/print") |> html_response(200)
    assert html =~ "Salle B12"
  end
end
