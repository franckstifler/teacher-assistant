defmodule TeacherAssistant.Accounts.SchoolsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{head: TeacherFixtures.user_fixture(), other: TeacherFixtures.user_fixture()}
  end

  test "create_school makes the creator a Head", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Bilingue"})
    assert school.kind == :school
    assert {:ok, m} = Schools.fetch_school_membership(school, head)
    assert :head in m.roles
  end

  test "list_workspaces_for returns the personal workspace plus member schools", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "École A"})
    ids = Schools.list_workspaces_for(head) |> Enum.map(& &1.id)
    assert school.id in ids
    # personal workspace also present
    assert Enum.any?(Schools.list_workspaces_for(head), &(&1.kind == :personal))
  end

  test "a non-member is rejected", %{head: head, other: other} do
    {:ok, school} = Schools.create_school(head, %{name: "École B"})
    assert {:error, :not_a_member} = Schools.fetch_school_membership(school, other)
  end

  test "last-Head protection blocks removing the only Head", %{head: head} do
    {:ok, school} = Schools.create_school(head, %{name: "École C"})
    {:ok, m} = Schools.fetch_school_membership(school, head)
    assert {:error, :last_head} = Schools.update_member_roles(m, [:teacher])
    assert {:error, :last_head} = Schools.deactivate_member(m)
  end
end
