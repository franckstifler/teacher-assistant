defmodule TeacherAssistant.Accounts.SchoolsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.SchoolMembership
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{head: TeacherFixtures.user_fixture(), other: TeacherFixtures.user_fixture()}
  end

  test "create_school makes the creator a Head", %{head: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Bilingue"
      })

    assert {:ok, m} = Accounts.fetch_school_membership(school_scope(head, school), head)
    assert :head in m.roles
  end

  test "list_workspaces_for returns schools only", %{head: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "École A"})

    ids =
      Organization.list_workspaces_for(%TeacherAssistant.Scope{current_user: head})
      |> Enum.map(& &1.id)

    assert ids == [school.id]
  end

  test "a non-member is rejected", %{head: head, other: other} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "École B"})

    outsider_scope = %TeacherAssistant.Scope{current_user: other, current_workspace: school}
    assert {:error, :not_a_member} = Accounts.fetch_school_membership(outsider_scope, other)
  end

  test "last-Head protection blocks removing the only Head", %{head: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "École C"})

    scope = school_scope(head, school)
    {:ok, m} = Accounts.fetch_school_membership(scope, head)
    assert {:error, :last_head} = Accounts.update_member_roles(scope, m, [:teacher])
    assert {:error, :last_head} = Accounts.deactivate_member(scope, m)
  end

  test "the other_active_heads aggregate lets one of two Heads be removed", %{
    head: head,
    other: other
  } do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "École D"})

    {:ok, other_membership} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        user_id: other.id,
        roles: [:head]
      })
      |> Ash.Changeset.set_tenant(school.id)
      |> Ash.create(authorize?: false)

    scope = school_scope(head, school)
    {:ok, m} = Accounts.fetch_school_membership(scope, head)
    assert Ash.load!(m, :other_active_heads).other_active_heads == 1

    assert {:ok, updated} = Accounts.update_member_roles(scope, m, [:teacher])
    refute :head in updated.roles

    assert Ash.load!(other_membership, :other_active_heads).other_active_heads == 0
    assert {:error, :last_head} = Accounts.deactivate_member(scope, other_membership)
  end
end
