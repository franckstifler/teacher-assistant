defmodule TeacherAssistant.Academics.Enums.ProgressionPlanStatus do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      draft: gettext("Draft"),
      active: gettext("Active"),
      archived: gettext("Archived")
    ]
end
