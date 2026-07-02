defmodule TeacherAssistantWeb.SchoolInvitationControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "accepting a matching invitation joins the school", %{conn: conn, actor: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "École Accept"})
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/school"
    assert {:ok, _m} = Schools.fetch_school_membership(school, user)
  end

  test "a mismatched invitation is rejected", %{conn: conn} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "École Mismatch"})
    {:ok, inv} = Schools.invite_member(school, head, %{email: "someone@example.com", roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/teacher"
    refute match?({:ok, _}, Schools.fetch_school_membership(school, conn.assigns.current_user))
  end
end
