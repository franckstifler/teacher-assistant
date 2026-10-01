defmodule TeacherAssistant.Academics.ConductWarning do
  @moduledoc "A conduct warning given by the class council (spec I3)."
  use Ash.Type.Enum, values: [:avertissement_conduite, :blame_conduite]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:avertissement_conduite), do: gettext("Avertissement de conduite")
  def label(:blame_conduite), do: gettext("Blâme de conduite")
end
