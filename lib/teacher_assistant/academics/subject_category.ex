defmodule TeacherAssistant.Academics.SubjectCategory do
  use Ash.Type.Enum, values: [:general, :language, :technical]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:general), do: gettext("Générale")
  def label(:language), do: gettext("Langue")
  def label(:technical), do: gettext("Technique")
end
