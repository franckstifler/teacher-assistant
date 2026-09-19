defmodule TeacherAssistantWeb.Teacher.SchoolScopeUxTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée UX"})

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(cg, user, %{subject: "Maths"})
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, tc: tc, user: user}
  end

  test "roster is read-only under school scope", %{conn: conn, tc: tc} do
    {:ok, view, html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    assert html =~ "Awa"
    refute has_element?(view, "#student-form")
    refute has_element?(view, "[id^='student-delete-']")
  end

  test "forged roster mutation events are rejected under school scope", %{conn: conn, tc: tc} do
    {:ok, view, _} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    # event name must match RosterLive's actual add handler
    render_hook(view, "add_student", %{"student" => %{"full_name" => "X", "sex" => "m"}})

    assert Enrollment.list_students(%TeacherAssistant.Academics.ClassGroup{id: tc.class_group_id})
           |> length() == 1
  end

  test "setup redirects to /school under school scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher/setup")
  end

  test "fiche print shows the school name as établissement", ctx do
    %{conn: conn, tc: tc} = ctx
    {:ok, plan} = Curriculum.create_progression_plan(tc, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    conn = get(conn, ~p"/teacher/entries/#{entry.id}/fiche/print")
    assert html_response(conn, 200) =~ "Lycée UX"
  end
end
