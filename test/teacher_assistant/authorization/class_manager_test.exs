defmodule TeacherAssistant.Authorization.ClassManagerTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Accounts, Enrollment, Scope}

  test "admins and the class's form master manage the class; others do not" do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg, other | _] = Enrollment.list_class_groups(head, year)
    fm = member_scope_fixture(head, %{roles: [:teacher]})
    {:ok, cg} = Enrollment.set_form_master(head, cg, fm.current_user.id)

    assert Enrollment.class_manager?(head, cg)
    assert Enrollment.class_manager?(fm, cg)
    refute Enrollment.class_manager?(fm, other)

    refute Enrollment.class_manager?(
             %Scope{current_user: user_fixture(), current_workspace: ws},
             cg
           )

    {:ok, m} = Accounts.fetch_school_membership(head, fm.current_user)
    {:ok, _} = Accounts.deactivate_member(head, m)
    refute Enrollment.class_manager?(fm, cg)
  end
end
