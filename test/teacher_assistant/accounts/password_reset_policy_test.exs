defmodule TeacherAssistant.Accounts.PasswordResetPolicyTest do
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

  test "a head resets an invited (email) member", %{head: head, op: op} do
    m = member(head, [:teacher])
    assert m.user.created_in_workspace_id == nil
    assert {:ok, password} = Accounts.reset_member_password(head, m)
    assert is_binary(password)

    assert [%{action: :password_reset, target_user_id: target}] =
             Accounts.list_audit_events(op,
               workspace_id: head.current_workspace.id,
               action: :password_reset
             )

    assert target == m.user_id
  end

  test "a head cannot reset another head", %{head: head} do
    m = member(head, [:head])
    assert_forbidden(Accounts.reset_member_password(head, m))
  end

  test "a head cannot reset themself", %{head: head} do
    {:ok, own} = Accounts.fetch_school_membership(head, head.current_user)
    assert_forbidden(Accounts.reset_member_password(head, own))
  end

  test "a head cannot reset a member active in another school", %{head: head} do
    m = member(head, [:teacher])
    %{scope: other_head} = TeacherFixtures.school_fixture()
    TeacherFixtures.membership_fixture(other_head, %{user: m.user, roles: [:teacher]})
    assert_forbidden(Accounts.reset_member_password(head, m))
  end

  test "the operator resets anyone but an operator", %{head: head, op: op} do
    m = member(head, [:head])
    assert {:ok, _password} = Accounts.operator_reset_password(op, m.user)
    assert {:ok, _password} = Accounts.operator_reset_password(op, head.current_user)

    other_op = TeacherFixtures.admin_user_fixture()
    assert_forbidden(Accounts.operator_reset_password(op, other_op))
  end

  test "a head cannot use the operator reset on a member of another school", %{head: head} do
    %{head_user: stranger} = TeacherFixtures.school_fixture()
    assert_forbidden(Accounts.operator_reset_password(head, stranger))
  end

  test "an operator's reset is journaled under the member's school, not the operator's",
       %{head: head, op: op} do
    m = member(head, [:teacher])
    %{scope: other_head, workspace: other} = TeacherFixtures.school_fixture()
    TeacherFixtures.membership_fixture(other_head, %{user: op.current_user, roles: [:teacher]})
    op_in_other = school_scope(op.current_user, other)

    assert {:ok, _} = Accounts.operator_reset_password(op_in_other, m.user)

    assert [%{workspace_id: ws_id}] =
             Accounts.list_audit_events(op, action: :password_reset)
             |> Enum.filter(&(&1.target_user_id == m.user_id))

    assert ws_id == head.current_workspace.id
  end

  describe "a school not yet verified" do
    setup do
      %{scope: unverified} = TeacherFixtures.school_fixture()
      %{unverified: unverified}
    end

    test "cannot take over an existing phone account it linked", %{unverified: head} do
      {:ok, hash} = AshAuthentication.BcryptProvider.hash("victim-pass-1")

      victim =
        Ash.Seed.seed!(Accounts.User, %{
          phone: "+237677123456",
          name: "Ancien professeur",
          hashed_password: hash
        })

      assert {:ok, %{user: %{id: id}, temporary_password: nil}} =
               Accounts.add_member_by_phone(head, %{phone: "677123456"})

      assert id == victim.id
      {:ok, m} = Accounts.fetch_school_membership(head, victim)
      assert_forbidden(Accounts.reset_member_password(head, m))

      TeacherFixtures.verify_school!(head)
      assert {:ok, _password} = Accounts.reset_member_password(head, m)
    end

    test "still resets an account it created itself", %{unverified: head} do
      assert {:ok, %{user: user, temporary_password: first}} =
               Accounts.add_member_by_phone(head, %{name: "Nouveau prof", phone: "677000222"})

      assert is_binary(first)
      {:ok, m} = Accounts.fetch_school_membership(head, user)
      assert {:ok, _password} = Accounts.reset_member_password(head, m)
    end
  end

  describe "resettable_member_ids/2 agrees with the policy, member by member" do
    # Every kind of member the policy distinguishes: invited teacher, another head,
    # the actor, someone active in another school, an account the school created.
    defp populate(head) do
      member(head, [:teacher])
      member(head, [:head])
      busy = member(head, [:teacher])
      %{scope: other} = TeacherFixtures.school_fixture()
      TeacherFixtures.membership_fixture(other, %{user: busy.user, roles: [:teacher]})

      {:ok, _} =
        Accounts.add_member_by_phone(head, %{name: "Créé ici", phone: "677000333"})

      Accounts.list_members(head)
    end

    defp assert_same(scope, members) do
      expected =
        for m <- members,
            Accounts.can_reset_member_password?(scope, m.user),
            into: MapSet.new(),
            do: m.id

      assert Accounts.resettable_member_ids(scope, members) == expected
    end

    test "in a verified school", %{head: head, op: op} do
      members = populate(head)
      assert_same(head, members)
      assert MapSet.size(Accounts.resettable_member_ids(head, members)) == 2

      op_here = %{head | current_user: op.current_user}
      assert_same(op_here, members)
    end

    test "in a school not yet verified" do
      %{scope: head} = TeacherFixtures.school_fixture()
      members = populate(head)
      assert_same(head, members)
      assert MapSet.size(Accounts.resettable_member_ids(head, members)) == 1
    end

    test "for a member who is not a head", %{head: head} do
      members = populate(head)
      [teacher | _] = Enum.filter(members, &(&1.roles == [:teacher]))
      teacher_scope = school_scope(teacher.user, head.current_workspace)
      assert_same(teacher_scope, members)
      assert Accounts.resettable_member_ids(teacher_scope, members) == MapSet.new()
    end
  end
end
