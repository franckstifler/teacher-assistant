defmodule TeacherAssistant.Accounts.InvitationStatus do
  use Ash.Type.Enum, values: [:pending, :accepted, :revoked]
end
