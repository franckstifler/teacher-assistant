defmodule TeacherAssistantWeb.SanctionLabels do
  @moduledoc """
  Shared gettext label helpers for `SanctionType` values, used by both the
  live discipline/bulletin views and the printable bulletin HTML.
  """

  use Gettext, backend: TeacherAssistantWeb.Gettext

  alias TeacherAssistant.Academics.SanctionType

  def type_label(type), do: SanctionType.label(type)

  def sanction_label(%{type: type} = sanction) do
    case duration(sanction) do
      nil -> type_label(type)
      text -> "#{type_label(type)} (#{text})"
    end
  end

  @doc "« 3 j » for an exclusion temporaire, « 2 h » for a consigne, else nil."
  def duration(%{type: :exclusion_temporaire, duration_days: days}) when is_integer(days),
    do: "#{days} #{gettext("j")}"

  def duration(%{type: :consigne, duration_hours: hours}) when is_integer(hours),
    do: "#{hours} #{gettext("h")}"

  def duration(_sanction), do: nil

  def sanctions_line([]), do: gettext("Aucune sanction")
  def sanctions_line(sanctions), do: sanctions |> Enum.map(&sanction_label/1) |> Enum.join(" · ")
end
