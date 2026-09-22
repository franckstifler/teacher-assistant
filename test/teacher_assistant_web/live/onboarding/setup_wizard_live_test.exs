defmodule TeacherAssistantWeb.Onboarding.SetupWizardLiveTest do
  use TeacherAssistantWeb.ConnCase
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

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
end
