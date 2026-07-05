defmodule TeacherAssistantWeb.BulletinPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Print"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa Ngo", sex: :f, matricule: "M-1"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Bob Eyong", sex: :m})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Academics.create_assessment(tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    roster = Academics.list_roster(cg)

    for %{student: s} <- roster,
        do: Academics.upsert_marks(a, [%{student_id: s.id, score: Decimal.new(14)}])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, roster: roster, head: head}
  end

  test "single bulletin print shows the school and the student", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))
    conn = get(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?seq=#{seq.id}")
    body = html_response(conn, 200)
    assert body =~ "Lycée Print"
    assert body =~ "Awa Ngo"
    assert body =~ "Maths"
  end

  test "whole-class print includes every enrolled student", %{conn: conn, cg: cg, seq: seq} do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    body = html_response(conn, 200)
    assert body =~ "Awa Ngo"
    assert body =~ "Bob Eyong"
  end

  test "a non-admin member is redirected", %{school: school, cg: cg, seq: seq, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?seq=#{seq.id}")
    assert redirected_to(conn) == "/school"
  end
end
