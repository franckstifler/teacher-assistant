defmodule TeacherAssistant.Accounts.PermissionsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Permissions
  alias TeacherAssistant.Scope

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
end
