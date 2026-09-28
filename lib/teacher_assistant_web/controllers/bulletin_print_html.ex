defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{BulletinGroup, Sex}
  alias TeacherAssistantWeb.SanctionLabels

  embed_templates "bulletin_print_html/*"

  # Columns between "Coefficient" and "Note×Coef" for each period kind.
  defp period_cols(:trimester), do: 3
  defp period_cols(:annual), do: 4
  defp period_cols(_), do: 1

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp comp(row, key, idx) do
    case row.components do
      %{^key => list} -> Enum.at(list, idx, %{})[:average]
      _ -> nil
    end
  end

  defp sex_label(s), do: Sex.label(s)

  defp sanctions_line(sanctions), do: SanctionLabels.sanctions_line(sanctions)
end
