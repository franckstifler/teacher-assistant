defmodule TeacherAssistant.Academics.ProgressionPlanStatus do
  use Ash.Type.Enum, values: [:draft, :active]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:draft), do: gettext("Brouillon")
  def label(:active), do: gettext("Actif")
end
