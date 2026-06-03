defmodule TeacherAssistant.Academics.Enums.WorkspaceType do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      school: gettext("School"),
      personal_teacher: gettext("Personal teacher")
    ]
end
