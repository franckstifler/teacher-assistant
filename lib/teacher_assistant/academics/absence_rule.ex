defmodule TeacherAssistant.Academics.AbsenceRule do
  use Ash.Type.Enum, values: [:zero, :excluded, :makeup]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:zero), do: gettext("Zéro")
  def label(:excluded), do: gettext("Non noté (exclu du calcul)")
  def label(:makeup), do: gettext("Rattrapage obligatoire")
end
