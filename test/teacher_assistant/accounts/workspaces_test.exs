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
    assert {:error, :not_a_member} = TeacherAssistant.Accounts.Workspaces.scope_for(user, school.id)
  end
end
