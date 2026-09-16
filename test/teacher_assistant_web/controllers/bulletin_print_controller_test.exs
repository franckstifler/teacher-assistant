defmodule TeacherAssistantWeb.BulletinPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Academics.Timetables
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

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Lycée Print"
    assert body =~ "Awa Ngo"
    assert body =~ "Maths"
  end

  test "single bulletin print shows the conduct figures", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    school: school
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))

    :ok = Timetables.build_default_periods(school)
    [tc] = Assignments.list_for_class(cg)
    [period1, period2 | _] = Timetables.list_periods(school) |> Enum.filter(&(&1.kind == :lesson))

    {:ok, slot} =
      Timetables.place_slot(cg, %{
        day: :monday,
        period_id: period1.id,
        teaching_context_id: tc.id
      })

    _ = slot
    date = seq.start_date

    {:ok, _} =
      Attendance.record_period(cg, period1, tc, date, [{enr.id, :absent}], cg.workspace_id)

    {:ok, _} = Attendance.justify_day(enr.id, date, "Certificat médical")
    {:ok, _} = Attendance.record_period(cg, period2, tc, date, [{enr.id, :late}], cg.workspace_id)

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Conduite"
    assert body =~ "Absences justifiées"
    assert body =~ "Absences non justifiées"
    assert body =~ "Retards"
  end

  test "single bulletin print shows the sanctions, consignes and note de conduite figures", %{
    conn: conn,
    cg: cg,
    seq: seq,
    roster: roster,
    head: head
  } do
    %{enrollment: enr} = Enum.find(roster, &(&1.student.full_name == "Awa Ngo"))
    date = seq.start_date

    {:ok, _} =
      Discipline.add_sanction(enr, %{type: :consigne, date: date, reason: "Bavardage"}, head.id)

    {:ok, _} =
      Discipline.add_sanction(
        enr,
        %{type: :avertissement, date: date, reason: "Retards répétés"},
        head.id
      )

    {:ok, _} =
      Discipline.add_sanction(
        enr,
        %{type: :exclusion_temporaire, date: date, duration_days: 3, reason: "Bagarre"},
        head.id
      )

    {:ok, _} = Discipline.set_conduct_mark(enr, seq, 14, head.id)

    conn =
      get(
        conn,
        ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin/print?period=seq:#{seq.id}"
      )

    body = html_response(conn, 200)
    assert body =~ "Consignes"
    assert body =~ "Avertissement"
    assert body =~ "Exclusion temporaire"
    assert body =~ "3 j"
    assert body =~ "Note de conduite"
    assert body =~ "14"
  end

  test "whole-class print includes every enrolled student", %{conn: conn, cg: cg, seq: seq} do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
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

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert redirected_to(conn) == "/school"
  end

  test "the form master can print their class", %{
    conn: conn,
    cg: cg,
    seq: seq,
    head: head,
    school: school
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert html_response(conn, 200) =~ "Awa Ngo"
  end

  test "the bulletin names the form master when set", %{conn: conn, cg: cg, seq: seq, head: head} do
    {:ok, _} = Academics.set_form_master(cg, head.id)
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=seq:#{seq.id}")
    assert html_response(conn, 200) =~ to_string(head.email)
  end

  test "the whole-class print renders a trimester with séquence columns", %{
    conn: conn,
    cg: cg,
    seq: seq,
    school: school
  } do
    year = TeacherAssistant.Academics.current_academic_year(school)
    [_s1, s2 | _] = TeacherAssistant.Academics.list_sequences(year)
    [term1 | _] = TeacherAssistant.Academics.list_terms(year)
    _ = seq

    [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

    {:ok, a2} =
      TeacherAssistant.Academics.create_assessment(tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    for %{student: s} <- TeacherAssistant.Academics.list_roster(cg),
        do:
          TeacherAssistant.Academics.upsert_marks(a2, [
            %{student_id: s.id, score: Decimal.new(15)}
          ])

    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=trim:#{term1.id}")
    body = html_response(conn, 200)
    assert body =~ "Trimestre 1"
    assert body =~ "Séq 1"
    assert body =~ "Awa Ngo"
  end

  test "the whole-class print renders the annual period with trimester columns", %{
    conn: conn,
    cg: cg
  } do
    conn = get(conn, ~p"/school/classes/#{cg.id}/bulletin/print?period=annee")
    body = html_response(conn, 200)
    assert body =~ "Trim 1"
    assert body =~ "Moy. ann."
    assert body =~ "Awa Ngo"
  end
end
