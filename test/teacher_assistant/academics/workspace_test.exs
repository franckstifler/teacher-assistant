defmodule TeacherAssistant.Academics.WorkspaceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  test "ensure_personal_workspace! is idempotent per user" do
    user = TeacherFixtures.user_fixture()
    ws1 = Organization.ensure_personal_workspace!(user)
    ws2 = Organization.ensure_personal_workspace!(user)
    assert ws1.id == ws2.id
    assert ws1.owner_user_id == user.id
  end

  test "scope_for returns a personal scope for the owner" do
    user = TeacherFixtures.user_fixture()
    ws = Organization.ensure_personal_workspace!(user)
    assert {:ok, scope} = TeacherAssistant.Accounts.Workspaces.scope_for(user, ws.id)
    assert scope.current_workspace.id == ws.id
    assert scope.current_workspace_type == :personal_teacher
  end
end
