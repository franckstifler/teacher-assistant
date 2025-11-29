defmodule TeacherAssistant.Academics.Enums.Gender do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      male: gettext("Male"),
      female: gettext("Female")
    ]
end
