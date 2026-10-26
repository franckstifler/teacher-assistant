defmodule TeacherAssistantWeb.Teacher.MarksCombinedTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Combiné"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Organization.build_default_calendar(scope, year)
    seq = Organization.list_sequences(scope, year) |> List.first()

    {:ok, maco} =
      Enrollment.create_class_group(scope, year, %{label: "1ère MACO", level: "1ère"})

    {:ok, menu} =
      Enrollment.create_class_group(scope, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, tc_maco} = Curriculum.assign_teacher(scope, maco, head, %{subject: "Mathématiques"})
    {:ok, tc_menu} = Curriculum.assign_teacher(scope, menu, head, %{subject: "Mathématiques"})

    {:ok, s_maco} = Enrollment.add_student(scope, maco, %{full_name: "Awa", sex: :f})
    {:ok, s_menu} = Enrollment.add_student(scope, menu, %{full_name: "Beti", sex: :f})

    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      ws: school,
      seq: seq,
      scope: scope,
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
    scope: scope,
    maco: maco,
    menu: menu,
    s_maco: s_maco,
    s_menu: s_menu
  } do
    {:ok, _} = Assessment.create_combined_assessment(scope, course, seq, %{label: "Devoir 1"})

    %{id: aid} =
      scope |> Assessment.combined_assessments_for(course, seq) |> List.first()

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
    seq: seq,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    assert [a_maco] = Assessment.list_assessments(scope, tc_maco, seq)
    assert [a_menu] = Assessment.list_assessments(scope, tc_menu, seq)
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
         scope: scope,
         s_maco: s_maco,
         s_menu: s_menu
       } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    blur(view, s_maco.id, "15")
    blur(view, s_menu.id, "12")

    [a_maco] = Assessment.list_assessments(scope, tc_maco, seq)
    [a_menu] = Assessment.list_assessments(scope, tc_menu, seq)

    assert [m_maco] = Assessment.list_marks(scope, a_maco)
    assert m_maco.student_id == s_maco.id
    assert Decimal.equal?(m_maco.score, Decimal.new("15"))

    assert [m_menu] = Assessment.list_marks(scope, a_menu)
    assert m_menu.student_id == s_menu.id
    assert Decimal.equal?(m_menu.score, Decimal.new("12"))
  end

  test "a blur on a student of the second class writes only that class's assessment", ctx do
    %{conn: conn, scope: scope, course: course, seq: seq, tc_maco: tc_maco} = ctx
    {:ok, _} = Assessment.create_combined_assessment(scope, course, seq, %{label: "DS"})
    [column] = Assessment.combined_assessments_for(scope, course, seq)
    path = ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}&assessment=#{column.id}"
    {:ok, view, _} = live(conn, path)

    blur(view, ctx.s_menu.id, "13")

    assert [%{student_id: sid}] =
             Assessment.list_marks(scope, column.by_class_group_id[ctx.menu.id])

    assert sid == ctx.s_menu.id
    assert Assessment.list_marks(scope, column.by_class_group_id[ctx.maco.id]) == []
  end

  test "an out-of-range score is refused in its cell; the other class's mark still saves", %{
    conn: conn,
    tc_maco: tc_maco,
    tc_menu: tc_menu,
    seq: seq,
    scope: scope,
    s_maco: s_maco,
    s_menu: s_menu
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#new-assessment-form", %{"assessment" => %{"label" => "Devoir 1"}})
    |> render_submit()

    blur(view, s_maco.id, "15")
    blur(view, s_menu.id, "25")

    assert has_element?(view, "#mark-error-#{s_menu.id}", "Note entre 0 et 20")

    [a_maco] = Assessment.list_assessments(scope, tc_maco, seq)
    [a_menu] = Assessment.list_assessments(scope, tc_menu, seq)

    assert [_] = Assessment.list_marks(scope, a_maco)
    assert Assessment.list_marks(scope, a_menu) == []
  end

  test "abs/abj land on each class's own assessment, a blank deletes only that mark, abx is refused",
       ctx do
    %{conn: conn, scope: scope, course: course, seq: seq, tc_maco: tc_maco} = ctx
    %{maco: maco, menu: menu, s_maco: s_maco, s_menu: s_menu} = ctx

    {:ok, _} = Assessment.create_combined_assessment(scope, course, seq, %{label: "DS"})
    [column] = Assessment.combined_assessments_for(scope, course, seq)
    a_maco = column.by_class_group_id[maco.id]
    a_menu = column.by_class_group_id[menu.id]
    path = ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}&assessment=#{column.id}"

    {:ok, view, _} = live(conn, path)

    blur(view, s_maco.id, "abs")
    blur(view, s_menu.id, "ABJ")

    assert [%{student_id: sid_maco, status: :absent}] = Assessment.list_marks(scope, a_maco)
    assert sid_maco == s_maco.id
    assert [%{student_id: sid_menu, status: :excused}] = Assessment.list_marks(scope, a_menu)
    assert sid_menu == s_menu.id

    # An absent cell is disabled: the toggle brings it back to blank.
    view |> element("#absent-#{s_maco.id}") |> render_click()
    blur(view, s_menu.id, "abj")

    assert Assessment.list_marks(scope, a_maco) == []
    assert [%{status: :excused}] = Assessment.list_marks(scope, a_menu)

    blur(view, s_menu.id, "abx")

    assert Assessment.list_marks(scope, a_maco) == []
    assert [%{status: :excused}] = Assessment.list_marks(scope, a_menu)
    assert has_element?(view, "#mark-error-#{s_menu.id}")
  end

  test "without ?seq= the combined course opens on the current séquence", %{
    conn: conn,
    tc_maco: tc_maco,
    course: course,
    seq: seq,
    scope: scope
  } do
    {:ok, _} = Assessment.create_combined_assessment(scope, course, seq, %{label: "Devoir 1"})

    {:ok, view, html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks")

    assert html =~ "Devoir 1"
    assert has_element?(view, "#new-assessment-form")
  end

  defp blur(view, student_id, value),
    do: view |> element("#mark-input-#{student_id}") |> render_blur(%{"value" => value})

  test "APC: the competence written once lands on every class of the course", %{
    conn: conn,
    seq: seq,
    scope: scope,
    tc_maco: tc_maco,
    tc_menu: tc_menu
  } do
    {:ok, _} =
      Assessment.update_bulletin_settings(scope, %{
        "language" => "by_class",
        "elements" => ["apc"]
      })

    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    view
    |> form("#sequence-competence", %{competence: %{text: "Dériver une fonction"}})
    |> render_submit()

    assert Assessment.sequence_competences(scope, [tc_maco.id, tc_menu.id], [seq.id]) == %{
             {tc_maco.id, seq.id} => "Dériver une fonction",
             {tc_menu.id, seq.id} => "Dériver une fonction"
           }
  end

  test "deleting an assessment removes it from every class of the course", %{
    conn: conn,
    tc_maco: tc_maco,
    tc_menu: tc_menu,
    course: course,
    seq: seq,
    scope: scope
  } do
    {:ok, _} = Assessment.create_combined_assessment(scope, course, seq, %{label: "Devoir 1"})

    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc_maco.id}/marks?seq=#{seq.id}")

    assert view |> element("#delete-assessment") |> render() =~ "toutes les classes"
    view |> element("#delete-assessment") |> render_click()

    assert Assessment.list_assessments(scope, tc_maco, seq) == []
    assert Assessment.list_assessments(scope, tc_menu, seq) == []
    assert has_element?(view, "#marks-empty")
  end
end
