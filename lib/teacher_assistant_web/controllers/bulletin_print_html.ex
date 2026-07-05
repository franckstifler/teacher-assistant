defmodule TeacherAssistantWeb.BulletinPrintHTML do
  use TeacherAssistantWeb, :html

  embed_templates "bulletin_print_html/*"

  defp fmt(nil), do: "—"
  defp fmt(%Decimal{} = d), do: d |> Decimal.round(2) |> Decimal.to_string()

  defp sex_label(:f), do: gettext("Féminin")
  defp sex_label(_), do: gettext("Masculin")
end
