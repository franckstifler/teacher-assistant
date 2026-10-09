defmodule TeacherAssistant.Accounts.NotificationKind do
  @moduledoc "Spec KLM8: what a staff notification is about."
  use Ash.Type.Enum,
    values: [
      :correction_requested,
      :correction_decided,
      :entry_reminder,
      :roll_call_reminder,
      :bulletins_published,
      :missed_roll_calls,
      :temporary_password_expired,
      :member_joined
    ]
end
