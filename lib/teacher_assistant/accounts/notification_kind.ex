defmodule TeacherAssistant.Accounts.NotificationKind do
  @moduledoc "Spec KLM8: what a staff notification is about."
  use Ash.Type.Enum, values: [:correction_requested, :correction_decided, :entry_reminder]
end
