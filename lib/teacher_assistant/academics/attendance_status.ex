defmodule TeacherAssistant.Academics.AttendanceStatus do
  use Ash.Type.Enum, values: [:present, :absent, :late]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:present), do: gettext("Présent")
  def label(:absent), do: gettext("Absent")
  def label(:late), do: gettext("Retard")
end
