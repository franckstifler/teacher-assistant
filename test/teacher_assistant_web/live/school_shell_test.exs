defmodule TeacherAssistantWeb.SchoolShellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Rail"})

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(cg, user, %{subject: "Maths"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, tc: tc, user: user}
  end

  test "shell shows the class switcher with the active class and per-class tabs", %{
    conn: conn,
    tc: tc
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    assert has_element?(view, "#class-switcher")
    assert has_element?(view, "#class-switcher-item-#{tc.id}")
    assert has_element?(view, "#per-class-nav")
    # per-class links point at the active context
    assert has_element?(view, "#per-class-nav a[href='/teacher/contexts/#{tc.id}/marks']")
  end

  test "switcher items link through select-context carrying the current path", %{
    conn: conn,
    tc: tc
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")

    assert has_element?(
             view,
             "#class-switcher-item-#{tc.id} a[href*='/teacher/select-context/#{tc.id}']"
           )
  end
end
