defmodule TeacherAssistantWeb.AbsenceTotalsPrintHTML do
  use TeacherAssistantWeb, :html

  import TeacherAssistantWeb.OfficialHeaderComponents, only: [official_header: 1]

  alias TeacherAssistant.Academics.AbsenceTotals
  alias TeacherAssistantWeb.Numbers
  alias TeacherAssistantWeb.School.AbsenceTotalsParams

  embed_templates "absence_totals_print_html/*"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp source_label(:roll_call), do: gettext("Heures de l'appel")
  defp source_label(:typed), do: gettext("Heures saisies à la main")
end
