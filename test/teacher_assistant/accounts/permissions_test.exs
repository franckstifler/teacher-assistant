defmodule TeacherAssistant.Accounts.PermissionsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Scope

  defp scope(uid, roles) do
    %Scope{
      current_user: %{id: uid},
      current_workspace_type: :school,
      current_roles: roles
    }
  end

  test "form_master? is true only for the class's form master" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    assert Permissions.form_master?(scope("u1", [:teacher]), cg)
    refute Permissions.form_master?(scope("u2", [:teacher]), cg)
  end

  test "form_master? is false when class has no form master" do
    refute Permissions.form_master?(scope("u1", [:teacher]), %ClassGroup{form_master_user_id: nil})
  end

  test "form_master? is false outside a school scope" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    refute Permissions.form_master?(%Scope{current_workspace_type: :personal}, cg)
  end

  test "admin_or_form_master? true for admin regardless of form master" do
    cg = %ClassGroup{form_master_user_id: "u2"}
    assert Permissions.admin_or_form_master?(scope("u1", [:head]), cg)
  end

  test "admin_or_form_master? true for the form master who is not admin" do
    cg = %ClassGroup{form_master_user_id: "u1"}
    assert Permissions.admin_or_form_master?(scope("u1", [:teacher]), cg)
  end

  test "admin_or_form_master? false for an unrelated teacher" do
    cg = %ClassGroup{form_master_user_id: "u2"}
    refute Permissions.admin_or_form_master?(scope("u1", [:teacher]), cg)
  end

  test "head? and member? read the school roles" do
    head = %Scope{current_workspace_type: :school, current_roles: [:head, :teacher]}
    plain = %Scope{current_workspace_type: :school, current_roles: [:teacher]}
    personal = %Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]}

    assert Permissions.head?(head)
    refute Permissions.head?(plain)
    assert Permissions.member?(plain)
    refute Permissions.member?(personal)
    refute Permissions.bursar?(plain)
  end

  test "admin?/1 is true for head and vice_principal, false otherwise" do
    alias TeacherAssistant.Accounts.Permissions
    alias TeacherAssistant.Scope
    assert Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:head]})

    assert Permissions.admin?(%Scope{
             current_workspace_type: :school,
             current_roles: [:vice_principal]
           })

    refute Permissions.admin?(%Scope{current_workspace_type: :school, current_roles: [:teacher]})

    refute Permissions.admin?(%Scope{
             current_workspace_type: :personal_teacher,
             current_roles: [:teacher]
           })

    refute Permissions.admin?(nil)
  end

  test "discipline_master?/1 is true only for a school scope with the discipline_master role" do
    dm = scope("u1", [:discipline_master])
    plain = scope("u2", [:teacher])
    personal = %Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]}

    assert Permissions.discipline_master?(dm)
    refute Permissions.discipline_master?(plain)
    refute Permissions.discipline_master?(personal)
  end

  test "conduct_manager?/1 is true for head, vice_principal, and discipline_master" do
    head = scope("u1", [:head])
    vp = scope("u2", [:vice_principal])
    dm = scope("u3", [:discipline_master])
    plain = scope("u4", [:teacher])
    personal = %Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]}

    assert Permissions.conduct_manager?(head)
    assert Permissions.conduct_manager?(vp)
    assert Permissions.conduct_manager?(dm)
    refute Permissions.conduct_manager?(plain)
    refute Permissions.conduct_manager?(personal)
  end

  test "fees_manager?/1 is true for head, vice_principal, and bursar" do
    head = scope("u1", [:head])
    vp = scope("u2", [:vice_principal])
    bursar = scope("u3", [:bursar])
    plain = scope("u4", [:teacher])
    personal = %Scope{current_workspace_type: :personal_teacher, current_roles: [:teacher]}

    assert Permissions.fees_manager?(head)
    assert Permissions.fees_manager?(vp)
    assert Permissions.fees_manager?(bursar)
    refute Permissions.fees_manager?(plain)
    refute Permissions.fees_manager?(personal)
  end
end
