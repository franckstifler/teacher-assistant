defmodule TeacherAssistantWeb.SchoolShellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée Rail"
      })

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, user, %{subject: "Maths"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, tc: tc, user: user}
  end

  test "a course page offers Mes cours and its own tabs, not a rail switcher", %{
    conn: conn,
    tc: tc
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    refute has_element?(view, "#class-switcher")
    refute has_element?(view, "#per-class-nav")
    assert has_element?(view, "#teaching-nav-back[href='/school/courses']")
    assert has_element?(view, "#teaching-nav-roster[aria-current='page']")
    assert has_element?(view, "#teaching-nav-marks[href='/teacher/contexts/#{tc.id}/marks']")

    assert has_element?(
             view,
             "#teaching-nav-summary[href='/teacher/contexts/#{tc.id}/marks/summary']"
           )
  end

  test "the rail marks the current page as active", %{conn: conn} do
    conn = post(conn, ~p"/school/space/enseignant")
    {:ok, view, _html} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-courses[aria-current='page']")
    refute has_element?(view, "#nav-school-classes[aria-current='page']")
  end

  test "staff and settings nav items show for the head only", %{
    conn: conn,
    school: school,
    user: head
  } do
    {:ok, view, _html} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#nav-school-members")
    assert has_element?(view, "#nav-school-settings")

    teacher =
      TeacherAssistant.TeacherFixtures.member_scope_fixture(school_scope(head, school), %{
        roles: [:teacher]
      })

    teacher_conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(teacher_conn, ~p"/school/courses")
    refute has_element?(view, "#nav-school-members")
    refute has_element?(view, "#nav-school-settings")
  end
end
