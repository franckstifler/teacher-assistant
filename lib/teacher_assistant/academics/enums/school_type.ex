defmodule TeacherAssistant.Academics.Enums.SchoolType do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      general: gettext("General"),
      technical: gettext("Technical"),
      commercial: gettext("Commercial")
    ]
end
