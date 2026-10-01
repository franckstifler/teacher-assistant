defmodule TeacherAssistantWeb.BulletinVerifyHTML do
  use TeacherAssistantWeb, :html

  embed_templates "bulletin_verify_html/*"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp period(%{period_kind: :annual}), do: gettext("Année scolaire")
  defp period(%{term_position: n}), do: gettext("Trimestre %{n}", n: n)
end
