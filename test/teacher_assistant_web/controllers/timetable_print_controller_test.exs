defmodule TeacherAssistantWeb.TimetablePrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Print TT"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})

    :ok = Timetables.build_default_periods(school)
    period = Timetables.list_periods(school) |> Enum.find(&(&1.kind == :lesson))

    {:ok, _slot} =
      Timetables.place_slot(cg, %{
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
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    assert redirected_to(conn) == "/school"
  end

  test "the teacher's own timetable print shows their subject", %{conn: conn} do
    conn = get(conn, ~p"/school/timetable/me/print")
    body = html_response(conn, 200)

    assert body =~ "Maths"
  end
end
