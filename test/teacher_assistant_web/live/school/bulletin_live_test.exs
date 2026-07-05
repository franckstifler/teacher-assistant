defmodule TeacherAssistantWeb.School.BulletinLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
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
      live(conn, ~p"/school/classes/#{cg.id}/students/#{enr.id}/bulletin?seq=#{seq.id}")

    assert html =~ "Awa Ngo"
    assert html =~ "M-1"
    assert html =~ "Maths"
    assert html =~ "15"
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
               ~p"/school/classes/#{cg.id}/students/#{other_enr.id}/bulletin?seq=#{seq.id}"
             )
  end
end
