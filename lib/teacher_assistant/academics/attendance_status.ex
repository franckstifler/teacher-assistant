defmodule TeacherAssistant.Academics.AttendanceStatus do
  use Ash.Type.Enum, values: [:present, :absent, :late, :sent_home]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:present), do: gettext("Présent")
  def label(:absent), do: gettext("Absent")
  def label(:late), do: gettext("Retard")
  # Fees 2: sent out of class for unpaid fees — never counted as an absence.
  def label(:sent_home), do: gettext("Renvoyé pour frais")
end
