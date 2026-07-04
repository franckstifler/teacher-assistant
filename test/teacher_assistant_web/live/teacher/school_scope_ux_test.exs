defmodule TeacherAssistantWeb.Teacher.SchoolScopeUxTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Enrollments}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée UX"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, user, %{subject: "Maths"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
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

    assert Academics.list_students(%TeacherAssistant.Academics.ClassGroup{id: tc.class_group_id})
           |> length() == 1
  end

  test "setup redirects to /school under school scope", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher/setup")
  end

  test "fiche print shows the school name as établissement", ctx do
    %{conn: conn, tc: tc} = ctx
    {:ok, plan} = Academics.create_progression_plan(tc, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    conn = get(conn, ~p"/teacher/entries/#{entry.id}/fiche/print")
    assert html_response(conn, 200) =~ "Lycée UX"
  end
end
