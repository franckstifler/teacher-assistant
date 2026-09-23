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
    {:ok, school} = Organization.create_school(head, %{name: "Lycée Bilingue"})
    assert school.kind == :school
    assert {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert :head in m.roles
  end

  test "list_workspaces_for returns schools only", %{head: head} do
    {:ok, school} = Organization.create_school(head, %{name: "École A"})
    ids = Organization.list_workspaces_for(head) |> Enum.map(& &1.id)
    assert ids == [school.id]
    refute Enum.any?(Organization.list_workspaces_for(head), &(&1.kind == :personal))
  end

  test "a non-member is rejected", %{head: head, other: other} do
    {:ok, school} = Organization.create_school(head, %{name: "École B"})
    assert {:error, :not_a_member} = Accounts.fetch_school_membership(school, other)
  end

  test "last-Head protection blocks removing the only Head", %{head: head} do
    {:ok, school} = Organization.create_school(head, %{name: "École C"})
    {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert {:error, :last_head} = Accounts.update_member_roles(m, [:teacher])
    assert {:error, :last_head} = Accounts.deactivate_member(m)
  end

  test "the other_active_heads aggregate lets one of two Heads be removed", %{
    head: head,
    other: other
  } do
    {:ok, school} = Organization.create_school(head, %{name: "École D"})

    {:ok, other_membership} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: school.id,
        user_id: other.id,
        roles: [:head]
      })
      |> Ash.create(authorize?: false)

    {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert Ash.load!(m, :other_active_heads).other_active_heads == 1

    assert {:ok, updated} = Accounts.update_member_roles(m, [:teacher])
    refute :head in updated.roles

    assert Ash.load!(other_membership, :other_active_heads).other_active_heads == 0
    assert {:error, :last_head} = Accounts.deactivate_member(other_membership)
  end
end
