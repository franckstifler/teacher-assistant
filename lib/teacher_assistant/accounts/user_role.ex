defmodule TeacherAssistant.Accounts.UserRole do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      admin: gettext("Admin"),
      teacher: gettext("Teacher"),
      accountant: gettext("Accountant"),
      principal_teacher: gettext("Principal Teacher"),
      discipline_master: gettext("Discipline-Master"),
      vice_principal: gettext("Vice-Principal"),
      principal: gettext("Principal")
    ]
end
