defmodule TeacherAssistant.Accounts.WorkspacesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    user = TeacherFixtures.user_fixture()
    %{user: user}
  end

  test "scope_for resolves a school workspace via active membership", %{user: user} do
    {:ok, school} = Organization.create_school(user, %{name: "École Scope"})
    assert {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
    assert scope.current_workspace.id == school.id
    assert :head in scope.current_roles
  end

  test "scope_for rejects a school the user is not a member of", %{user: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(head, %{name: "École X"})

    assert {:error, :not_a_member} =
             TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
  end

  describe "school teaching scope (P2.2)" do
    setup %{user: user} do
      {:ok, school} = Organization.create_school(user, %{name: "Lycée S"})

      {:ok, year} =
        Organization.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
      %{school: school, year: year, cg: cg}
    end

    test "school scope resolves year and assigned context", ctx do
      %{user: user, school: school, year: year, cg: cg} = ctx

      {:ok, tc} =
        Curriculum.assign_teacher(cg, user, %{subject: "Maths"})

      {:ok, scope} = Workspaces.scope_for(user, school.id)
      assert scope.current_academic_year.id == year.id
      assert scope.current_context.id == tc.id
    end

    test "school scope without assignments has nil context but a year", ctx do
      %{user: user, school: school, year: year} = ctx
      {:ok, scope} = Workspaces.scope_for(user, school.id)
      assert scope.current_academic_year.id == year.id
      assert scope.current_context == nil
    end

    test "context_id from another teacher falls back to own first assignment", ctx do
      %{user: user, school: school, cg: cg} = ctx
      other = TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school, user, %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} = Accounts.accept_invitation(inv.token, other)

      {:ok, mine} = Curriculum.assign_teacher(cg, user, %{subject: "Maths"})

      {:ok, theirs} =
        Curriculum.assign_teacher(cg, other, %{subject: "Anglais"})

      {:ok, scope} = Workspaces.scope_for(user, school.id, theirs.id)
      assert scope.current_context.id == mine.id
    end
  end

  describe "default workspace (school-only product)" do
    test "scope_for with nil workspace resolves the first active school membership", %{user: user} do
      {:ok, school} = Organization.create_school(user, %{name: "École Défaut"})
      assert {:ok, scope} = Workspaces.scope_for(user, nil)
      assert scope.current_workspace.id == school.id
    end

    test "scope_for with nil workspace and no membership returns an error" do
      user = TeacherFixtures.user_fixture()
      assert {:error, :no_workspace} = Workspaces.scope_for(user, nil)
    end

    test "list_workspaces_for returns schools only", %{user: user} do
      {:ok, school} = Organization.create_school(user, %{name: "École Liste"})
      ids = user |> Organization.list_workspaces_for() |> Enum.map(& &1.id)
      assert ids == [school.id]
    end

    test "scope_for(user, nil) and list_workspaces_for are stable across several schools", %{
      user: user
    } do
      {:ok, first} = Organization.create_school(user, %{name: "École Première"})
      {:ok, second} = Organization.create_school(user, %{name: "École Seconde"})

      assert {:ok, scope} = Workspaces.scope_for(user, nil)
      assert scope.current_workspace.id == first.id

      assert user |> Organization.list_workspaces_for() |> Enum.map(& &1.id) ==
               [first.id, second.id]
    end
  end

  test "a scope has no workspace type; membership decides everything" do
    %{workspace: school, head_user: head} = TeacherFixtures.school_fixture()
    {:ok, scope} = Workspaces.scope_for(head, school.id)
    refute Map.has_key?(scope, :current_workspace_type)
    assert scope.current_workspace.id == school.id
    assert :head in scope.current_roles
  end
end
