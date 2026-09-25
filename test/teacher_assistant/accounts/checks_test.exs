defmodule TeacherAssistant.Accounts.ChecksTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Academics.{ClassGroup, Workspace}
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.Checks.{SchoolRole, SchoolVerified}
  alias TeacherAssistant.Accounts.SchoolRole, as: Roles

  setup do
    %{workspace: ws, scope: head} = school_fixture()
    %{ws: ws, head: head}
  end

  defp tenant_subject(ws),
    do: %{subject: ClassGroup |> Ash.Query.new() |> Ash.Query.set_tenant(ws.id)}

  describe "SchoolRole.axis/1" do
    test "defines the role sets" do
      assert Enum.sort(Roles.axis(:member)) == Enum.sort(Roles.values())
      assert Roles.axis(:admin) == [:head, :vice_principal]
      assert Roles.axis(:head) == [:head]
      assert Roles.axis(:conduct) == [:head, :vice_principal, :discipline_master]
      assert Roles.axis(:fees) == [:head, :vice_principal, :bursar]
    end
  end

  describe "Checks.SchoolRole" do
    test "passes when the actor's active roles intersect the axis", %{ws: ws, head: head} do
      assert SchoolRole.match?(head.current_user, tenant_subject(ws), any_of: :admin)
      assert SchoolRole.match?(head.current_user, tenant_subject(ws), any_of: :member)
    end

    test "each axis admits exactly its roles", %{ws: ws, head: head} do
      bursar = member_scope_fixture(head, %{roles: [:bursar]}).current_user
      dm = member_scope_fixture(head, %{roles: [:discipline_master]}).current_user
      teacher = member_scope_fixture(head, %{roles: [:teacher]}).current_user

      assert SchoolRole.match?(bursar, tenant_subject(ws), any_of: :fees)
      refute SchoolRole.match?(bursar, tenant_subject(ws), any_of: :conduct)
      assert SchoolRole.match?(dm, tenant_subject(ws), any_of: :conduct)
      refute SchoolRole.match?(dm, tenant_subject(ws), any_of: :admin)
      assert SchoolRole.match?(teacher, tenant_subject(ws), any_of: :member)
      refute SchoolRole.match?(teacher, tenant_subject(ws), any_of: :admin)
      refute SchoolRole.match?(bursar, tenant_subject(ws), any_of: :head)
    end

    test "fails with no actor, no tenant, or a non-member", %{ws: ws} do
      refute SchoolRole.match?(nil, tenant_subject(ws), any_of: :member)
      refute SchoolRole.match?(user_fixture(), tenant_subject(ws), any_of: :member)
      no_tenant = %{subject: Ash.Query.new(ClassGroup)}
      refute SchoolRole.match?(user_fixture(), no_tenant, any_of: :member)
    end

    test "an inactive membership does not count", %{ws: ws, head: head} do
      teacher = member_scope_fixture(head, %{roles: [:teacher]})
      {:ok, m} = Accounts.fetch_school_membership(ws, teacher.current_user)
      {:ok, _} = m |> Ash.Changeset.for_update(:deactivate, %{}) |> Ash.update(authorize?: false)

      refute SchoolRole.holds?(teacher.current_user, ws.id, :member)
    end

    test "reads the school from the record for Workspace", %{ws: ws, head: head} do
      subject = %{subject: Ash.Changeset.new(ws)}
      assert SchoolRole.workspace_id(subject.subject) == ws.id
      assert SchoolRole.match?(head.current_user, subject, any_of: :head)
    end
  end

  describe "Checks.SchoolVerified" do
    test "passes only once the school is verified", %{ws: ws, head: head} do
      refute SchoolVerified.match?(head.current_user, tenant_subject(ws), [])
      verify_school!(head)
      assert SchoolVerified.match?(head.current_user, tenant_subject(ws), [])
    end

    test "fails without a resolvable school" do
      refute SchoolVerified.match?(nil, %{subject: Ash.Query.new(Workspace)}, [])
    end
  end
end
