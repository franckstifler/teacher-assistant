defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  embed_templates "bulletin_print_html/*"

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp comp(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp sex_label(:f), do: gettext("Féminin")
  defp sex_label(_), do: gettext("Masculin")

  defp sanction_type_label(:avertissement), do: gettext("Avertissement")
  defp sanction_type_label(:blame), do: gettext("Blâme")
  defp sanction_type_label(:exclusion_temporaire), do: gettext("Exclusion temporaire")
  defp sanction_type_label(:exclusion_definitive), do: gettext("Exclusion définitive")

  defp sanction_label(%{type: :exclusion_temporaire, duration_days: days}) when is_integer(days) do
    "#{sanction_type_label(:exclusion_temporaire)} (#{days} #{gettext("j")})"
  end

  defp sanction_label(%{type: type}), do: sanction_type_label(type)

  defp sanctions_line([]), do: gettext("Aucune sanction")
  defp sanctions_line(sanctions), do: sanctions |> Enum.map(&sanction_label/1) |> Enum.join(" · ")
end
