defmodule TeacherAssistant.Accounts.SchoolInvitationsTest do
  use TeacherAssistant.DataCase, async: true
  import Swoosh.TestAssertions
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(head, %{name: "Collège Test"})
    %{head: head, school: school}
  end

  test "invite_member creates a pending invitation with a token", %{school: school, head: head} do
    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: "prof@example.com", roles: [:teacher]})

    assert inv.status == :pending
    assert to_string(inv.email) == "prof@example.com"
    assert is_binary(inv.token) and inv.token != ""
  end

  test "accept_invitation as the matching user creates a membership", %{
    school: school,
    head: head
  } do
    invitee = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})

    assert {:ok, joined} = Accounts.accept_invitation(inv.token, invitee)
    assert joined.id == school.id
    assert {:ok, m} = Accounts.fetch_school_membership(school, invitee)
    assert :teacher in m.roles
  end

  test "accept rejects an email mismatch", %{school: school, head: head} do
    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: "someone@example.com", roles: [:teacher]})

    other = TeacherFixtures.user_fixture()
    assert {:error, :email_mismatch} = Accounts.accept_invitation(inv.token, other)
  end

  test "accept rejects a revoked invitation", %{school: school, head: head} do
    invitee = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(invitee.email), roles: [:teacher]})

    {:ok, _} = Accounts.revoke_invitation(inv)
    assert {:error, :invalid} = Accounts.accept_invitation(inv.token, invitee)
  end

  test "inviting an existing active member is rejected", %{school: school, head: head} do
    assert {:error, :already_member} =
             Accounts.invite_member(school, head, %{
               email: to_string(head.email),
               roles: [:teacher]
             })
  end

  test "invite_member delivers an email to the invited address with the accept link" do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, inv} =
      Accounts.invite_member(ws, head, %{email: "new@example.com", roles: [:teacher]})

    assert_email_sent(fn email ->
      assert {_, "new@example.com"} = hd(email.to)
      assert email.text_body =~ inv.token
    end)
  end

  test "invite with employment type carries onto the membership on accept" do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, inv} =
      Accounts.invite_member(ws, head, %{
        email: "t@example.com",
        roles: [:teacher],
        membership_status: :contractuel
      })

    assert inv.membership_status == :contractuel

    user = TeacherFixtures.user_fixture(%{email: "t@example.com"})
    {:ok, _ws} = Accounts.accept_invitation(inv.token, user)
    {:ok, m} = Accounts.fetch_school_membership(ws, user)
    assert m.status == :contractuel
  end

  test "invite without employment type leaves membership status nil" do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, inv} =
      Accounts.invite_member(ws, head, %{email: "u@example.com", roles: [:teacher]})

    user = TeacherFixtures.user_fixture(%{email: "u@example.com"})
    {:ok, _} = Accounts.accept_invitation(inv.token, user)
    {:ok, m} = Accounts.fetch_school_membership(ws, user)
    assert m.status == nil
  end

  test "update_member_status changes a member's employment type" do
    %{workspace: ws} = TeacherFixtures.school_fixture()
    m = TeacherFixtures.membership_fixture(ws, roles: [:teacher])
    {:ok, m2} = Accounts.update_member_status(m, :titulaire)
    assert m2.status == :titulaire
  end

  test "an invitation is found by token without a tenant and accepted into its school" do
    %{workspace: school, head_user: head} = TeacherFixtures.school_fixture()
    other = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    # Compared by id, not pinned as `^school`: `accept_invitation` returns
    # `inv.workspace`, loaded via the `:by_token` read's relationship load,
    # which carries extra (harmless) `__metadata__` (e.g. a keyset entry)
    # that a freshly `create`d struct doesn't — so the two aren't `==`, only
    # the same row.
    assert {:ok, joined} = Accounts.accept_invitation(inv.token, other)
    assert joined.id == school.id
    assert {:ok, m} = Accounts.fetch_school_membership(school, other)
    assert m.workspace_id == school.id
  end

  test "a user's schools are listed without a tenant" do
    %{workspace: s1, head_user: head} = TeacherFixtures.school_fixture()
    %{workspace: s2} = TeacherFixtures.school_fixture(%{head_user: head})
    ids = head |> Organization.list_workspaces_for() |> Enum.map(& &1.id)
    assert Enum.sort(ids) == Enum.sort([s1.id, s2.id])
  end
end
