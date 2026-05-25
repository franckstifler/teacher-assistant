defmodule TeacherAssistant.Academics.Enums.ProgressionEntryType do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      lesson: gettext("Lesson"),
      integration: gettext("Integration"),
      evaluation: gettext("Evaluation"),
      correction: gettext("Correction"),
      remediation: gettext("Remediation"),
      holiday: gettext("Holiday")
    ]
end
