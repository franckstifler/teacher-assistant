defmodule TeacherAssistantWeb.EntryReportPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.OfficialHeaderComponents, only: [official_header: 1]

  embed_templates "entry_report_print_html/*"

  defp pct(nil), do: "—"
  defp pct(n), do: "#{n} %"

  defp date(nil), do: "—"
  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")
  defp date(%DateTime{} = at), do: at |> DateTime.add(3600) |> DateTime.to_date() |> date()

  defp missing(%{assessments: 0}), do: gettext("Aucun devoir")
  defp missing(%{missing: n}), do: Integer.to_string(n)
end
