defmodule TeacherAssistant.Academics.JustificationReason do
  @moduledoc "Why an absence day was justified (spec G, V02)."
  use Ash.Type.Enum, values: [:maladie, :famille, :convocation, :autre]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:maladie), do: gettext("Maladie")
  def label(:famille), do: gettext("Raison familiale")
  def label(:convocation), do: gettext("Convocation officielle")
  def label(:autre), do: gettext("Autre motif")
  # Entries justified before reasons existed.
  def label(nil), do: gettext("Motif non précisé")
end
