defmodule TeacherAssistantWeb.Teacher.MarksCombinedTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Courses}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Combiné"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, maco} = Academics.create_class_group(school, year, %{label: "1ère MACO", level: "1ère"})
    {:ok, menu} = Academics.create_class_group(school, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, tc_maco} = Assignments.assign(maco, head, %{subject: "Mathématiques"})
    {:ok, tc_menu} = Assignments.assign(menu, head, %{subject: "Mathématiques"})

    {:ok, s_maco} = Academics.add_student(maco, %{full_name: "Awa", sex: :f})
    {:ok, s_menu} = Academics.add_student(menu, %{full_name: "Beti", sex: :f})

    {:ok, course} = Courses.combine([tc_maco, tc_menu])

    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, _} = Schools.verify_school(profile, head.id)

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      ws: school,
      seq: seq,
      course: course,
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      maco: maco,
      menu: menu,
      s_maco: s_maco,
      s_menu: s_menu
    }
  end

  test "shows the union roster grouped by class", %{
    conn: conn,
    tc_maco: tc_maco,
    course: course,
    seq: seq,
    maco: maco,
    menu: menu,
    s_maco: s_maco,
    s_menu: s_menu
  } do
    {:ok, _} = Academics.create_combined_assessment(course, seq, %{label: "Devoir 1"})
    %{id: aid} = course |> Academics.combined_assessments_for(seq) |> List.first()

    {:ok, view, _html} =
      live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}&assessment=#{aid}")

    assert has_element?(view, "#mark-row-#{s_maco.id}", s_maco.full_name)
    assert has_element?(view, "#mark-row-#{s_menu.id}", s_menu.full_name)
    assert has_element?(view, "#marks-class-#{maco.id}", maco.label)
    assert has_element?(view, "#marks-class-#{menu.id}", menu.label)
  end

  test "creating an assessment creates one per member context", %{
    conn: conn,
    tc_maco: tc_maco,
    tc_menu: tc_menu,
    seq: seq
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    assert [a_maco] = Academics.list_assessments(tc_maco, seq)
    assert [a_menu] = Academics.list_assessments(tc_menu, seq)
    assert a_maco.label == "Devoir 1"
    assert a_menu.label == "Devoir 1"
    assert a_maco.id != a_menu.id
  end

  test "each student's mark lands on their own class's context assessment, not the other class's",
       %{
         conn: conn,
         tc_maco: tc_maco,
         tc_menu: tc_menu,
         seq: seq,
         s_maco: s_maco,
         s_menu: s_menu
       } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    view
    |> form("#marks-form", %{"scores" => %{s_maco.id => "15", s_menu.id => "12"}})
    |> render_submit()

    [a_maco] = Academics.list_assessments(tc_maco, seq)
    [a_menu] = Academics.list_assessments(tc_menu, seq)

    assert [m_maco] = Academics.list_marks(a_maco)
    assert m_maco.student_id == s_maco.id
    assert Decimal.equal?(m_maco.score, Decimal.new("15"))

    assert [m_menu] = Academics.list_marks(a_menu)
    assert m_menu.student_id == s_menu.id
    assert Decimal.equal?(m_menu.score, Decimal.new("12"))
  end

  test "an out-of-range score in one class saves nothing for either class (all-or-nothing)", %{
    conn: conn,
    tc_maco: tc_maco,
    tc_menu: tc_menu,
    seq: seq,
    s_maco: s_maco,
    s_menu: s_menu
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    # MACO's score (15) is valid; MENU's (25) is out of range (marks are /20).
    html =
      view
      |> form("#marks-form", %{"scores" => %{s_maco.id => "15", s_menu.id => "25"}})
      |> render_submit()

    assert html =~ "0 and 20"

    [a_maco] = Academics.list_assessments(tc_maco, seq)
    [a_menu] = Academics.list_assessments(tc_menu, seq)

    assert Academics.list_marks(a_maco) == []
    assert Academics.list_marks(a_menu) == []
  end
end
