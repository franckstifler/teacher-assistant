defmodule TeacherAssistantWeb.Onboarding.SetupGateTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  test "an incomplete school head is redirected from /school to the wizard", %{conn: conn} do
    %{workspace: ws, head_user: head} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
  end

  test "a complete school head reaches /school", %{conn: conn} do
    %{workspace: ws, head_user: head} = setup_complete_school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    assert {:ok, _view, _html} = live(conn, ~p"/school")
  end

  test "the wizard route itself is not redirected", %{conn: conn} do
    %{workspace: ws, head_user: head} = school_fixture()
    conn = conn |> log_in_user(head) |> put_session(:workspace_id, ws.id)
    assert {:ok, _view, _html} = live(conn, ~p"/school/setup")
  end

  @tag :teacher_personal
  test "a teacher (personal) scope is never gated", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    assert {:ok, _view, _html} = live(conn, ~p"/teacher")
  end
end
