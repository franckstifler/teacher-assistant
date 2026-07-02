defmodule TeacherAssistant.Accounts.SchoolInvitationsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Collège Test"})
    %{head: head, school: school}
  end

  test "invite_member creates a pending invitation with a token", %{school: school, head: head} do
    {:ok, inv} = Schools.invite_member(school, head, %{email: "prof@example.com", roles: [:teacher]})
    assert inv.status == :pending
    assert to_string(inv.email) == "prof@example.com"
    assert is_binary(inv.token) and inv.token != ""
  end

  test "accept_invitation as the matching user creates a membership", %{school: school, head: head} do
    invitee = TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})

    assert {:ok, joined} = Schools.accept_invitation(inv.token, invitee)
    assert joined.id == school.id
    assert {:ok, m} = Schools.fetch_school_membership(school, invitee)
    assert :teacher in m.roles
  end

  test "accept rejects an email mismatch", %{school: school, head: head} do
    {:ok, inv} = Schools.invite_member(school, head, %{email: "someone@example.com", roles: [:teacher]})
    other = TeacherFixtures.user_fixture()
    assert {:error, :email_mismatch} = Schools.accept_invitation(inv.token, other)
  end

  test "accept rejects a revoked invitation", %{school: school, head: head} do
    invitee = TeacherFixtures.user_fixture()
    {:ok, inv} = Schools.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})
    {:ok, _} = Schools.revoke_invitation(inv)
    assert {:error, :invalid} = Schools.accept_invitation(inv.token, invitee)
  end

  test "inviting an existing active member is rejected", %{school: school, head: head} do
    assert {:error, :already_member} =
             Schools.invite_member(school, head, %{email: to_string(head.email), roles: [:teacher]})
  end
end
