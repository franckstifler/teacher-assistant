defmodule TeacherAssistant.Academics.EnrollmentStatus do
  use Ash.Type.Enum, values: [:inscription, :reinscription]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:inscription), do: gettext("Inscription")
  def label(:reinscription), do: gettext("Réinscription")
end
