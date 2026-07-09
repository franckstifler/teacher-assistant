defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistantWeb.SanctionLabels

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

  defp sanctions_line(sanctions), do: SanctionLabels.sanctions_line(sanctions)
end
