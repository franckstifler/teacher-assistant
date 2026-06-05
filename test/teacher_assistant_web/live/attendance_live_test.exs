defmodule TeacherAssistantWeb.AttendanceLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.PersonalWorkspace

  test "personal teacher selects a classroom and sees the roster", %{conn: conn} do
    teacher = generate(user_without_school(role: :teacher))
    workspace = Workspaces.ensure_personal_workspace!(teacher)
    scope = Workspaces.scope_for!(teacher, workspace.id)

    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2027-2028",
        "start_date" => "2026-06-03",
        "end_date" => "2027-03-30",
        "class_name" => "Form 1",
        "option_name" => "General",
        "subject_name" => "Mathematics",
        "students" => [
          %{"first_name" => "Ada", "last_name" => "Nanga", "gender" => "female"}
        ]
      })

    {:ok, view, _html} =
      conn
      |> log_in_user(workspace, teacher)
      |> live(~p"/teacher/attendance")

    html =
      view
      |> element("select[name=classroom_id]")
      |> render_change(%{classroom_id: setup.classroom.id})

    assert html =~ "Ada Nanga"
  end
end
