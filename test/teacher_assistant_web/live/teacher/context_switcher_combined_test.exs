defmodule TeacherAssistantWeb.Teacher.ContextSwitcherCombinedTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

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

    {:ok, cg_a} = Enrollment.create_class_group(scope, year, %{label: "1ère A", level: "1ère"})
    {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "1ère B", level: "1ère"})

    {:ok, tc_a} = Curriculum.assign_teacher(scope, cg_a, head, %{subject: "Mathématiques"})
    {:ok, tc_b} = Curriculum.assign_teacher(scope, cg_b, head, %{subject: "Mathématiques"})

    {:ok, course} = Curriculum.combine_course(scope, [tc_a, tc_b])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      ws: school,
      year: year,
      head: head,
      scope: scope,
      course: course,
      tc_a: tc_a,
      tc_b: tc_b
    }
  end

  test "Mes cours shows one card for a combined course, not one per class", %{
    conn: conn,
    course: course
  } do
    conn = post(conn, ~p"/school/space/enseignant")
    {:ok, view, html} = live(conn, ~p"/school/courses")

    # under its subject's heading, the row names the course without the subject
    name = String.replace_prefix(course.label, course.subject <> " · ", "")
    assert has_element?(view, "#course-combined-#{course.id}", name <> " · 2 classes")
    assert length(Regex.scan(~r/id="course-[^"]+"/, html)) == 1
  end
end
