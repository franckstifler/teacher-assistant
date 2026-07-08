defmodule TeacherAssistant.Academics.AttendanceStatus do
  use Ash.Type.Enum, values: [:present, :absent, :late]
end
