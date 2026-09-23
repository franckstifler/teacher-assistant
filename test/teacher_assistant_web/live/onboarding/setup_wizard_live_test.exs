defmodule TeacherAssistantWeb.Onboarding.SetupWizardLiveTest do
  use TeacherAssistantWeb.ConnCase
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Enrollment

  setup %{conn: conn} do
    %{workspace: ws, head_user: head} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    %{conn: conn, ws: ws, head: head}
  end

  test "renders the wizard on the academic-year step for a fresh school", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school/setup")
    assert html =~ "setup-wizard"
    # year step is first for a fresh school
    assert html =~ "Académique" or html =~ "Année"
  end

  test "creating the academic year seeds classes and advances to the classes step", %{
    conn: conn,
    ws: ws
  } do
    {:ok, view, _} = live(conn, ~p"/school/setup")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2026-2027", "start_date" => "2026-09-01", "end_date" => "2027-07-05"}
    })
    |> render_submit()

    assert TeacherAssistant.Organization.current_academic_year(ws) != nil
    assert Enrollment.list_class_groups(ws, TeacherAssistant.Organization.current_academic_year(ws)) != []

    html = render(view)
    assert html =~ "wizard-panel-classes"
  end
end
