defmodule TeacherAssistant.Academics.TeachingLogStatus do
  use Ash.Type.Enum, values: [:done, :partial]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:done), do: gettext("Terminé")
  def label(:partial), do: gettext("Partiel")
end
