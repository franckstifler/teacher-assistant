defmodule TeacherAssistantWeb.PersonalWorkspaceLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.PersonalWorkspace

  setup %{conn: conn} do
    teacher = generate(user_without_school(role: :teacher))
    workspace = Workspaces.ensure_personal_workspace!(teacher)
    scope = Workspaces.scope_for!(teacher, workspace.id)

    %{
      conn: log_in_user(conn, workspace, teacher),
      teacher: teacher,
      workspace: workspace,
      scope: scope
    }
  end

  test "personal teacher completes guided setup and gets personal navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    assert has_element?(view, "#personal-setup-form")
    assert has_element?(view, "#nav-personal-setup")
    assert has_element?(view, "#nav-personal-students")
    assert has_element?(view, "#nav-reports")

    assert {:error, {:live_redirect, %{to: "/teacher/students"}}} =
             view
             |> form("#personal-setup-form",
               setup: %{
                 academic_year_name: "2026-2027",
                 start_date: "2026-09-01",
                 end_date: "2027-06-30",
                 class_name: "Form 5",
                 option_name: "Science",
                 subject_name: "Mathematics",
                 coefficient: "4",
                 students_csv: "first_name,last_name,gender\nAda,Nanga,female\nJean,Meka,male"
               }
             )
             |> render_submit()
  end

  test "personal teacher imports CSV students into a selected class", %{conn: conn, scope: scope} do
    {:ok, setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    {:ok, view, _html} = live(conn, ~p"/teacher/students")

    assert has_element?(view, "#personal-students")
    assert has_element?(view, "#student-import-form")

    html =
      view
      |> form("#student-import-form",
        import: %{
          classroom_id: setup.classroom.id,
          csv: "first_name,last_name,matricule,gender\nAlice,Fotso,A001,female\nNoLast,,A002,male"
        }
      )
      |> render_submit()

    assert html =~ "Imported 1 students"
    assert html =~ "1 rows need attention"
    assert has_element?(view, "#personal-student-count", "1")
  end

  test "personal setup reports duplicate academic year without crashing", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _setup} =
      PersonalWorkspace.create_setup(scope, %{
        "academic_year_name" => "2026-2027",
        "start_date" => "2026-09-01",
        "end_date" => "2027-06-30",
        "class_name" => "Form 5",
        "option_name" => "Science",
        "subject_name" => "Mathematics"
      })

    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    html =
      view
      |> form("#personal-setup-form",
        setup: %{
          academic_year_name: "2026-2027",
          start_date: "2026-09-01",
          end_date: "2027-06-30",
          class_name: "Form 1",
          option_name: "General",
          subject_name: "Mathematics",
          coefficient: "3",
          students_csv: ""
        }
      )
      |> render_submit()

    assert html =~ "Academic year already exists in this personal workspace"
  end

  test "school teacher cannot open personal setup", %{conn: conn, teacher: teacher} do
    school = generate(school())
    generate(user_school(tenant: school, user_id: teacher.id, role: :teacher))

    assert {:error, {:redirect, %{to: "/workspaces"}}} =
             conn
             |> log_in_user(school, teacher)
             |> live(~p"/teacher/setup")
  end
end
