defmodule TeacherAssistant.Accounts.WorkspaceContextTest do
  use TeacherAssistant.DataCase

  import TeacherAssistant.AcademicFixtures

  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics.AcademicYear

  describe "workspace context" do
    test "ensures every user has a personal teacher workspace" do
      user = generate(user_without_school())

      workspace = Workspaces.ensure_personal_workspace!(user)

      assert workspace.workspace_type == :personal_teacher
      assert workspace.owner_user_id == user.id

      assert %{role: :teacher} = Workspaces.membership_for!(user, workspace.id)
    end

    test "resolves role from the selected school membership" do
      school = generate(school())
      user = generate(user_without_school(role: :teacher))
      generate(user_school(tenant: school, user_id: user.id, role: :accountant))

      scope = Workspaces.scope_for!(user, school.id)

      assert scope.current_tenant.id == school.id
      assert scope.current_workspace_type == :school
      assert scope.current_role == :accountant
      assert scope.current_user.role == :accountant
    end

    test "does not silently choose one school when no workspace is selected" do
      school = generate(school())
      user = generate(user_without_school())
      generate(user_school(tenant: school, user_id: user.id, role: :teacher))

      assert {:error, :workspace_required} = Workspaces.scope_for(user, nil)
    end

    test "loads the active academic year into the resolved scope when it exists" do
      school = generate(school())
      user = generate(user_without_school(role: :admin))
      generate(user_school(tenant: school, user_id: user.id, role: :admin))
      year = generate(academic_year(tenant: school, actor: %{user | role: :admin}))

      assert %{current_academic_year: %AcademicYear{id: year_id}} =
               Workspaces.scope_for!(user, school.id)

      assert year_id == year.id
    end
  end
end
