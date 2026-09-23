defmodule TeacherAssistant.Academics.WorkspaceTest do
  use TeacherAssistant.DataCase, async: true

  test "a workspace has no kind or owner" do
    refute Map.has_key?(%TeacherAssistant.Academics.Workspace{}, :kind)
    refute Map.has_key?(%TeacherAssistant.Academics.Workspace{}, :owner_user_id)
  end
end
