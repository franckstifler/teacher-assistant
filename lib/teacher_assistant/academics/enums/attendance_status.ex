defmodule TeacherAssistant.Academics.AttendanceStatus do
  use Gettext, backend: TeacherAssistantWeb.Gettext

  use Ash.Type.Enum,
    values: [
      :present,
      :absent,
      :excused
    ]
end
