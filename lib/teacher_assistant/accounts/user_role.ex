defmodule TeacherAssistant.Accounts.UserRole do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      teacher: gettext("Teacher"),
      principal_teacher: gettext("Principal Teacher"),
      admin: gettext("Admin")
    ]
end
