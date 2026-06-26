defmodule TeacherAssistant.Academics.AttendanceStatus do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      present: gettext("Present"),
      absent: gettext("Absent"),
      late: gettext("Late"),
      excused: gettext("Excused")
    ]
end
