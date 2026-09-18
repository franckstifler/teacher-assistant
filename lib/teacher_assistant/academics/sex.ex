defmodule TeacherAssistant.Academics.Sex do
  use Ash.Type.Enum, values: [:m, :f]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:m), do: gettext("Masculin")
  def label(:f), do: gettext("Féminin")
end
