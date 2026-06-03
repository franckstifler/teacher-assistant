defmodule TeacherAssistant.Accounts.InvitationStatus do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      pending: gettext("Pending"),
      accepted: gettext("Accepted"),
      revoked: gettext("Revoked")
    ]
end
