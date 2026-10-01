defmodule TeacherAssistant.Academics.PublicationStatus do
  @moduledoc "A report-card publication is in force (`:published`) or was withdrawn (spec I2)."
  use Ash.Type.Enum, values: [:published, :withdrawn]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:published), do: gettext("Publié")
  def label(:withdrawn), do: gettext("Retiré")
end
