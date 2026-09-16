defmodule TeacherAssistantWeb.School.BulletinLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Bu"})

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
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Academics.create_assessment(tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student, enrollment: enr}] = Academics.list_roster(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, enr: enr, head: head}
  end

  test "renders the student's bulletin", %{conn: conn, cg: cg, enr: enr, seq: seq} do
    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "Awa Ngo"
    assert html =~ "M-1"
    assert html =~ "Maths"
    assert html =~ "15"
  end

  test "the bulletin shows séquence breakdown columns for a trimester", %{
    conn: conn,
    cg: cg,
    enr: enr,
    seq: seq,
    school: school
  } do
    # grade a second séquence in the same term so the trimester has two components
    year = TeacherAssistant.Academics.current_academic_year(school)
    [s1, s2 | _] = TeacherAssistant.Academics.list_sequences(year)
    [term1 | _] = TeacherAssistant.Academics.list_terms(year)
    _ = seq

    [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

    {:ok, a2} =
      TeacherAssistant.Academics.create_assessment(tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student}] = TeacherAssistant.Academics.list_roster(cg)

    :ok =
      TeacherAssistant.Academics.upsert_marks(a2, [
        %{student_id: student.id, score: Decimal.new(17)}
      ])

    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=trim:#{term1.id}")

    assert html =~ "Séq 1"
    assert html =~ "Séq 2"
    assert html =~ "Moy. trim."
    _ = s1
  end

  test "the bulletin shows the conduct section without changing the moyenne générale", %{
    conn: conn,
    cg: cg,
    enr: enr,
    seq: seq,
    school: school
  } do
    # Baseline: no attendance recorded yet.
    {:ok, _view, baseline_html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert baseline_html =~ "Moyenne générale"
    [_, baseline_moyenne] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, baseline_html)

    :ok = Timetables.build_default_periods(school)
    [tc] = Assignments.list_for_class(cg)
    periods = Timetables.list_periods(school) |> Enum.filter(&(&1.kind == :lesson))
    [period1, period2 | _] = periods

    # 2025-09-15 is a Monday within séquence 1's date range.
    {:ok, slot} =
      Timetables.place_slot(cg, %{
        day: :monday,
        period_id: period1.id,
        teaching_context_id: tc.id
      })

    date = seq.start_date

    {:ok, _} =
      Attendance.record_period(
        cg,
        period1,
        tc,
        date,
        [{enr.id, :absent}],
        cg.workspace_id
      )

    {:ok, _} = Attendance.justify_day(enr.id, date, "Certificat médical")

    {:ok, _} =
      Attendance.record_period(
        cg,
        period2,
        tc,
        date,
        [{enr.id, :late}],
        cg.workspace_id
      )

    _ = slot

    # Second unjustified absence in a different lesson period, same day.
    [period3 | _] = periods -- [period1, period2]

    {:ok, _} =
      Attendance.record_period(
        cg,
        period3,
        tc,
        date,
        [{enr.id, :absent}],
        cg.workspace_id
      )

    expected_justified_hours =
      Attendance.student_conduct(enr.id, {:sequence, seq}).justified_hours
      |> Decimal.round(2)
      |> Decimal.to_string()

    expected_unjustified_hours =
      Attendance.student_conduct(enr.id, {:sequence, seq}).unjustified_hours
      |> Decimal.round(2)
      |> Decimal.to_string()

    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "Conduite"
    assert html =~ "Absences justifiées"
    assert html =~ "Absences non justifiées"
    assert html =~ "Retards"
    assert html =~ expected_justified_hours
    assert html =~ expected_unjustified_hours
    # 1 retard recorded
    assert html =~ ">1<" or html =~ "1</"

    [_, moyenne_after] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, html)
    assert moyenne_after == baseline_moyenne
  end

  test "the bulletin shows sanctions, consignes and note de conduite without changing the moyenne générale",
       %{conn: conn, cg: cg, enr: enr, seq: seq, head: head} do
    # Baseline: no discipline recorded yet.
    {:ok, _view, baseline_html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    [_, baseline_moyenne] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, baseline_html)

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

    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert html =~ "Consignes"
    assert html =~ "1"
    assert html =~ "Avertissement"
    assert html =~ "Exclusion temporaire"
    assert html =~ "3 j"
    assert html =~ "Note de conduite"
    assert html =~ "14"

    [_, moyenne_after] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, html)
    assert moyenne_after == baseline_moyenne
  end

  test "an enrollment from another class is rejected", %{
    conn: conn,
    cg: cg,
    seq: seq,
    school: school
  } do
    {:ok, cg2} =
      Academics.create_class_group(school, Academics.current_academic_year(school), %{
        label: "6e B",
        level: "6ème"
      })

    {:ok, _} = Academics.add_student(cg2, %{full_name: "Bob", sex: :m})
    [%{enrollment: other_enr}] = Academics.list_roster(cg2)

    assert {:error, {:live_redirect, %{}}} =
             live(
               conn,
               ~p"/school/classes/#{cg.id}/students/#{other_enr.id}/bulletin?period=seq:#{seq.id}"
             )
  end
end
