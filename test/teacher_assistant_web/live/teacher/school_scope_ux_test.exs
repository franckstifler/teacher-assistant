defmodule TeacherAssistantWeb.Teacher.SchoolScopeUxTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée UX"})
    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, user, %{subject: "Maths"})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, tc: tc, user: user}
  end

  test "roster is read-only under school scope", %{conn: conn, tc: tc} do
    {:ok, view, html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    assert html =~ "Awa"
    refute has_element?(view, "#student-form")
    refute has_element?(view, "[id^='student-delete-']")
  end

  test "an unknown roster redirects to /school under school scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end
end
