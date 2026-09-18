defmodule TeacherAssistant.Academics.Subsystem do
  use Ash.Type.Enum, values: [:francophone, :anglophone]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:francophone), do: gettext("Francophone")
  def label(:anglophone), do: gettext("Anglophone")
end
