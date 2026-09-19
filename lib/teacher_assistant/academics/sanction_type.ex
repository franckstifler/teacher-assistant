defmodule TeacherAssistant.Academics.SanctionType do
  use Ash.Type.Enum,
    values: [:avertissement, :blame, :exclusion_temporaire, :exclusion_definitive, :consigne]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:avertissement), do: gettext("Avertissement")
  def label(:blame), do: gettext("Blâme")
  def label(:exclusion_temporaire), do: gettext("Exclusion temporaire")
  def label(:exclusion_definitive), do: gettext("Exclusion définitive")
  def label(:consigne), do: gettext("Consigne")
end
