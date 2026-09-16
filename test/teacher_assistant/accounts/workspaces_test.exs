defmodule TeacherAssistant.Accounts.WorkspacesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{user: user, ws: ws, ctx: ctx}
  end

  test "scope_for/3 resolves current_context from a valid id", %{user: user, ws: ws, ctx: ctx} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id, ctx.id)
    assert scope.current_context.id == ctx.id
  end

  test "scope_for/3 defaults current_context when id is nil", %{user: user, ws: ws, ctx: ctx} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id, nil)
    assert scope.current_context.id == ctx.id
  end

  test "scope_for/2 still works (context nil)", %{user: user, ws: ws} do
    {:ok, scope} = Workspaces.scope_for(user, ws.id)
    assert scope.current_workspace.id == ws.id
  end

  test "scope_for resolves a school workspace via active membership", %{user: user} do
    {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(user, %{name: "École Scope"})
    assert {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
    assert scope.current_workspace_type == :school
    assert :head in scope.current_roles
  end

  test "scope_for rejects a school the user is not a member of", %{user: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(head, %{name: "École X"})

    assert {:error, :not_a_member} =
             TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
  end

  describe "school teaching scope (P2.2)" do
    setup %{user: user} do
      {:ok, school} = TeacherAssistant.Accounts.Schools.create_school(user, %{name: "Lycée S"})

      {:ok, year} =
        Academics.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
      %{school: school, year: year, cg: cg}
    end

    test "school scope resolves year and assigned context", ctx do
      %{user: user, school: school, year: year, cg: cg} = ctx

      {:ok, tc} =
        TeacherAssistant.Academics.Assignments.assign(cg, user, %{subject: "Maths"})

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
        TeacherAssistant.Accounts.Schools.invite_member(school, user, %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} = TeacherAssistant.Accounts.Schools.accept_invitation(inv.token, other)

      {:ok, mine} = TeacherAssistant.Academics.Assignments.assign(cg, user, %{subject: "Maths"})

      {:ok, theirs} =
        TeacherAssistant.Academics.Assignments.assign(cg, other, %{subject: "Anglais"})

      {:ok, scope} = Workspaces.scope_for(user, school.id, theirs.id)
      assert scope.current_context.id == mine.id
    end
  end
end
