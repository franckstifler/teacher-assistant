defmodule TeacherAssistant.Academics.ProgressionEntryType do
  use Ash.Type.Enum,
    values: [:lesson, :integration, :evaluation, :revision, :correction, :remediation, :holiday]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:lesson), do: gettext("Leçon")
  def label(:integration), do: gettext("Intégration")
  def label(:evaluation), do: gettext("Évaluation")
  def label(:revision), do: gettext("Révision")
  def label(:correction), do: gettext("Correction")
  def label(:remediation), do: gettext("Remédiation")
  def label(:holiday), do: gettext("Congé")
end
