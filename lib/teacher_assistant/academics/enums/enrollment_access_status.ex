defmodule TeacherAssistant.Academics.Enums.EnrollmentAccessStatus do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      allowed: gettext("Allowed"),
      pending: gettext("Pending"),
      suspended: gettext("Suspended"),
      blocked: gettext("Blocked")
    ]
end
