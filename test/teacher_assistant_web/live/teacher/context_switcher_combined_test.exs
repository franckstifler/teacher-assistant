defmodule TeacherAssistantWeb.Teacher.ContextSwitcherCombinedTest do
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

    {:ok, cg_a} = Academics.create_class_group(school, year, %{label: "1ère A", level: "1ère"})
    {:ok, cg_b} = Academics.create_class_group(school, year, %{label: "1ère B", level: "1ère"})

    {:ok, tc_a} = Assignments.assign(cg_a, head, %{subject: "Mathématiques"})
    {:ok, tc_b} = Assignments.assign(cg_b, head, %{subject: "Mathématiques"})

    {:ok, course} = Courses.combine([tc_a, tc_b])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{conn: conn, ws: school, year: year, head: head, course: course, tc_a: tc_a, tc_b: tc_b}
  end

  test "the class switcher shows one row for a combined course, not one per class", %{
    conn: conn,
    course: course
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher")

    # exactly one switcher row for the whole course, labelled with the course label
    assert has_element?(view, "#class-switcher", course.label)

    item_ids =
      view
      |> render()
      |> then(&Regex.scan(~r/id="class-switcher-item-([^"]+)"/, &1))

    assert length(item_ids) == 1

    representative_id = Academics.unit_select_id({:course, course})
    assert has_element?(view, "#class-switcher-item-#{representative_id}", course.label)
  end

  test "dashboard shows exactly one coverage KPI for a combined course over two classes", %{
    conn: conn,
    ws: ws,
    course: course
  } do
    [plan] =
      ws
      |> Academics.list_progression_plans()
      |> Enum.filter(&(&1.combined_course_id == course.id))

    {:ok, view, _html} = live(conn, ~p"/teacher")

    assert has_element?(view, "#kpi-#{plan.id}")

    kpi_ids =
      view
      |> render()
      |> then(&Regex.scan(~r/id="kpi-(?!roster-|coverage-)([^"]+)"/, &1))

    assert length(kpi_ids) == 1
  end
end
