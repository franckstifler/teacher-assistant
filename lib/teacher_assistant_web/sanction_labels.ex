defmodule TeacherAssistantWeb.SanctionLabels do
  @moduledoc """
  Shared gettext label helpers for `SanctionType` values, used by both the
  live discipline/bulletin views and the printable bulletin HTML.
  """

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def type_label(:avertissement), do: gettext("Avertissement")
  def type_label(:blame), do: gettext("Blâme")
  def type_label(:exclusion_temporaire), do: gettext("Exclusion temporaire")
  def type_label(:exclusion_definitive), do: gettext("Exclusion définitive")
  def type_label(:consigne), do: gettext("Consigne")

  def sanction_label(%{type: :exclusion_temporaire, duration_days: days}) when is_integer(days) do
    "#{type_label(:exclusion_temporaire)} (#{days} #{gettext("j")})"
  end

  def sanction_label(%{type: type}), do: type_label(type)

  def sanctions_line([]), do: gettext("Aucune sanction")
  def sanctions_line(sanctions), do: sanctions |> Enum.map(&sanction_label/1) |> Enum.join(" · ")
end
