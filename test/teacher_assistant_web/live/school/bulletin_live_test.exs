defmodule TeacherAssistantWeb.School.BulletinLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Discipline
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée Bu"})

    scope = school_scope(head, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, _} =
      Enrollment.add_student(scope, cg, %{full_name: "Awa Ngo", sex: :f, matricule: "M-1"})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student, enrollment: enr}] = Enrollment.list_roster(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, enr: enr, head: head, scope: scope}
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
    scope: scope
  } do
    # grade a second séquence in the same term so the trimester has two components
    year = TeacherAssistant.Organization.current_academic_year(scope)
    [s1, s2 | _] = TeacherAssistant.Organization.list_sequences(scope, year)
    [term1 | _] = TeacherAssistant.Organization.list_terms(scope, year)
    _ = seq

    [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)

    {:ok, a2} =
      TeacherAssistant.Assessment.create_assessment(scope, tc, s2, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [%{student: student}] = TeacherAssistant.Enrollment.list_roster(scope, cg)

    :ok =
      TeacherAssistant.Assessment.upsert_marks(scope, a2, [
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
    scope: scope
  } do
    # Baseline: no attendance recorded yet.
    {:ok, _view, baseline_html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    assert baseline_html =~ "Moyenne générale"
    [_, baseline_moyenne] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, baseline_html)

    :ok = Attendance.build_default_periods(scope)
    [tc] = Curriculum.list_assignments_for_class(scope, cg)
    periods = Attendance.list_periods(scope) |> Enum.filter(&(&1.kind == :lesson))
    [period1, period2 | _] = periods

    # 2025-09-15 is a Monday within séquence 1's date range.
    {:ok, slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period1.id,
        teaching_context_id: tc.id
      })

    date = seq.start_date

    {:ok, _} =
      Attendance.record_period(
        scope,
        cg,
        period1,
        tc,
        date,
        [{enr.id, :absent}]
      )

    {:ok, _} = Attendance.justify_day(scope, enr, date, "Certificat médical")

    {:ok, _} =
      Attendance.record_period(
        scope,
        cg,
        period2,
        tc,
        date,
        [{enr.id, :late}]
      )

    _ = slot

    # Second unjustified absence in a different lesson period, same day.
    [period3 | _] = periods -- [period1, period2]

    {:ok, _} =
      Attendance.record_period(
        scope,
        cg,
        period3,
        tc,
        date,
        [{enr.id, :absent}]
      )

    expected_justified_hours =
      Attendance.student_conduct(scope, enr, {:sequence, seq}).justified_hours
      |> Decimal.round(2)
      |> Decimal.to_string()

    expected_unjustified_hours =
      Attendance.student_conduct(scope, enr, {:sequence, seq}).unjustified_hours
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
       %{conn: conn, cg: cg, enr: enr, seq: seq, scope: scope} do
    # Baseline: no discipline recorded yet.
    {:ok, _view, baseline_html} =
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}")

    [_, baseline_moyenne] = Regex.run(~r/Moyenne générale.*?(\d+[.,]\d+)/s, baseline_html)

    date = seq.start_date

    {:ok, _} =
      Discipline.add_sanction(scope, enr, %{type: :consigne, date: date, reason: "Bavardage"})

    {:ok, _} =
      Discipline.add_sanction(
        scope,
        enr,
        %{type: :avertissement, date: date, reason: "Retards répétés"}
      )

    {:ok, _} =
      Discipline.add_sanction(
        scope,
        enr,
        %{type: :exclusion_temporaire, date: date, duration_days: 3, reason: "Bagarre"}
      )

    {:ok, _} = Discipline.set_conduct_mark(scope, enr, seq, 14)

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
    scope: scope
  } do
    {:ok, cg2} =
      Enrollment.create_class_group(
        scope,
        TeacherAssistant.Organization.current_academic_year(scope),
        %{
          label: "6e B",
          level: "6ème"
        }
      )

    {:ok, _} = Enrollment.add_student(scope, cg2, %{full_name: "Bob", sex: :m})
    [%{enrollment: other_enr}] = Enrollment.list_roster(scope, cg2)

    assert {:error, {:live_redirect, %{}}} =
             live(
               conn,
               ~p"/school/classes/#{cg.id}/students/#{other_enr.id}/bulletin?period=seq:#{seq.id}"
             )
  end

  test "subjects appear under their bulletin group; subtotals only when enabled", ctx do
    %{conn: conn, cg: cg, enr: enr, seq: seq, scope: scope} = ctx
    path = ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?period=seq:#{seq.id}"

    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#bulletin-group-g3_autres", "Groupe 3 · Autres")
    refute has_element?(view, "#bulletin-group-g1_lettres")
    refute has_element?(view, "#bulletin-group-total-g3_autres")

    {:ok, _} = TeacherAssistant.Curriculum.set_bulletin_group_subtotals(scope, true)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#bulletin-group-total-g3_autres", "Total groupe")
  end
end
