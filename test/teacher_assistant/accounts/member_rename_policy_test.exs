defmodule TeacherAssistant.Accounts.MemberRenamePolicyTest do
  @moduledoc """
  A member's name is corrected by their school, never by the member (decided by the
  user, 2026-11-10): the head of the school renames its active members, the
  operator anyone but an operator. A school not yet verified renames only the
  accounts it created.
  """
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Scope, TeacherFixtures}

  setup do
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}
    %{head: head, op: op}
  end

  defp member(head, roles) do
    m = TeacherFixtures.membership_fixture(head, %{roles: roles})
    {:ok, m} = Ash.load(m, :user, scope: head)
    m
  end

  test "the head renames a member, and it is journaled", %{head: head, op: op} do
    m = member(head, [:teacher])
    assert {:ok, user} = Accounts.rename_member(head, m, "  Hélène   Mvondo ")
    assert user.name == "Hélène Mvondo"

    assert [%{target_user_id: target, details: details}] =
             Accounts.list_audit_events(op,
               workspace_id: head.current_workspace.id,
               action: :member_renamed
             )

    assert target == m.user_id
    assert details["after"] == "Hélène Mvondo"
  end

  test "a blank name is refused", %{head: head} do
    m = member(head, [:teacher])
    assert {:error, _} = Accounts.rename_member(head, m, "   ")
  end

  test "the head also renames another head, themself, and someone active in another school",
       %{head: head} do
    assert {:ok, _} = Accounts.rename_member(head, member(head, [:head]), "Co-proviseur")

    {:ok, own} = Accounts.fetch_school_membership(head, head.current_user)
    {:ok, own} = Ash.load(own, :user, scope: head)
    assert {:ok, _} = Accounts.rename_member(head, own, "Proviseur")

    busy = member(head, [:teacher])
    %{scope: other} = TeacherFixtures.school_fixture()
    TeacherFixtures.membership_fixture(other, %{user: busy.user, roles: [:teacher]})
    assert {:ok, _} = Accounts.rename_member(head, busy, "Vacataire")
  end

  test "a member cannot rename anyone, not even themself", %{head: head} do
    m = member(head, [:teacher, :vice_principal])
    member_scope = school_scope(m.user, head.current_workspace)

    assert_forbidden(Accounts.rename_member(member_scope, m, "Autre nom"))
    assert_forbidden(Accounts.rename_member(member_scope, member(head, [:teacher]), "X"))
  end

  test "the head cannot rename an operator", %{head: head, op: op} do
    m = TeacherFixtures.membership_fixture(head, %{user: op.current_user, roles: [:teacher]})
    {:ok, m} = Ash.load(m, :user, scope: head)
    assert_forbidden(Accounts.rename_member(head, m, "Opérateur"))
  end

  describe "a school not yet verified" do
    setup do
      %{scope: unverified} = TeacherFixtures.school_fixture()
      %{unverified: unverified}
    end

    test "cannot rename an existing account it linked", %{unverified: head} do
      victim = Ash.Seed.seed!(Accounts.User, %{phone: "+237677123456", name: "Vrai nom"})
      {:ok, _} = Accounts.add_member_by_phone(head, %{phone: "677123456"})
      {:ok, m} = Accounts.fetch_school_membership(head, victim)
      {:ok, m} = Ash.load(m, :user, scope: head)

      assert_forbidden(Accounts.rename_member(head, m, "Faux nom"))
    end

    test "renames an account it created itself", %{unverified: head} do
      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(head, %{name: "Nouveau prof", phone: "677000222"})

      {:ok, m} = Accounts.fetch_school_membership(head, user)
      {:ok, m} = Ash.load(m, :user, scope: head)
      assert {:ok, %{name: "Nouvelle prof"}} = Accounts.rename_member(head, m, "Nouvelle prof")
    end
  end

  describe "renamable_member_ids/2 agrees with the policy, member by member" do
    defp populate(head) do
      member(head, [:teacher])
      member(head, [:head])
      busy = member(head, [:teacher])
      %{scope: other} = TeacherFixtures.school_fixture()
      TeacherFixtures.membership_fixture(other, %{user: busy.user, roles: [:teacher]})
      {:ok, _} = Accounts.add_member_by_phone(head, %{name: "Créé ici", phone: "677000333"})
      Accounts.list_members(head)
    end

    defp assert_same(scope, members) do
      expected =
        for m <- members,
            Accounts.can_rename_member?(scope, m.user),
            into: MapSet.new(),
            do: m.id

      assert Accounts.renamable_member_ids(scope, members) == expected
    end

    test "in a verified school", %{head: head, op: op} do
      members = populate(head)
      assert_same(head, members)
      assert MapSet.size(Accounts.renamable_member_ids(head, members)) == length(members)
      assert_same(%{head | current_user: op.current_user}, members)
    end

    test "in a school not yet verified" do
      %{scope: head} = TeacherFixtures.school_fixture()
      members = populate(head)
      assert_same(head, members)
      # the accounts it created: its own head's (registered here) is not one of them
      assert MapSet.size(Accounts.renamable_member_ids(head, members)) == 1
    end

    test "for a member who is not a head", %{head: head} do
      members = populate(head)
      [teacher | _] = Enum.filter(members, &(&1.roles == [:teacher]))
      teacher_scope = school_scope(teacher.user, head.current_workspace)
      assert_same(teacher_scope, members)
      assert Accounts.renamable_member_ids(teacher_scope, members) == MapSet.new()
    end
  end
end
