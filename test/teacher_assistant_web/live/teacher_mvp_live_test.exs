defmodule TeacherAssistantWeb.TeacherMVPLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TeacherAssistant.Academics

  setup :register_and_log_in_user

  test "dashboard renders the academic year setup gate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher")

    assert html =~ "Teacher dashboard"
    assert has_element?(live(conn, ~p"/teacher") |> elem(1), "#academic-year-setup-gate")
  end

  test "teacher can create academic year, classroom, learner, roll call, and progress", %{
    conn: conn,
    workspace: workspace
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    view
    |> form("#academic-year-form",
      academic_year: %{
        name: "2026-2027",
        start_date: "2026-09-01",
        end_date: "2027-06-30"
      }
    )
    |> render_submit()

    assert Academics.current_academic_year(workspace).name == "2026-2027"

    {:ok, view, _html} = live(conn, ~p"/teacher/classrooms")
    assert has_element?(view, "#classroom-form")

    view
    |> form("#classroom-form",
      classroom: %{class_label: "Form 3", subject: "Mathematics"}
    )
    |> render_submit()

    assert has_element?(view, "#classrooms-table")
    [classroom] = Academics.list_personal_classrooms(workspace)

    {:ok, view, _html} = live(conn, ~p"/teacher/classrooms/#{classroom.id}")
    assert has_element?(view, "#learner-form")

    view
    |> form("#learner-form",
      learner: %{first_name: "Grace", last_name: "Nkom", identifier: "M-001"}
    )
    |> render_submit()

    assert has_element?(view, "#learners-table")

    {:ok, view, _html} = live(conn, ~p"/teacher/roll-call")
    assert has_element?(view, "#roll-call-form")

    view
    |> form("#roll-call-form",
      roll_call: %{classroom_id: classroom.id, date: "2026-10-05"}
    )
    |> render_submit()

    assert has_element?(view, "#attendance-records")

    {:ok, view, _html} = live(conn, ~p"/teacher/progress")
    assert has_element?(view, "#lesson-plan-form")

    view
    |> form("#lesson-plan-form",
      lesson_plan: %{
        classroom_id: classroom.id,
        title: "Linear equations",
        planned_on: "2026-10-06",
        planned_hours: "2.0",
        objectives: "Solve one-variable equations"
      }
    )
    |> render_submit()

    assert has_element?(view, "#lesson-plan-entries")
  end
end
