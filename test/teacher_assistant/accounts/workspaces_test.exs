defmodule TeacherAssistant.Accounts.WorkspacesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.Workspaces
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "3ème", subsystem: :francophone, weekly_hours: 4})
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
end
