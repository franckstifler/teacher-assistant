defmodule TeacherAssistant.Accounts.WorkspaceKind do
  use Ash.Type.Enum, values: [:personal, :school]
end
