defmodule TeacherAssistant.Academics.Enums.SchoolSubsystem do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      francophone: gettext("Francophone"),
      anglophone: gettext("Anglophone"),
      bilingual: gettext("Bilingual")
    ]
end
