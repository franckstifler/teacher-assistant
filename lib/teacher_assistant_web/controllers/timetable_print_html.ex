defmodule TeacherAssistantWeb.TimetablePrintHTML do
  use TeacherAssistantWeb, :html

  embed_templates "timetable_print_html/*"

  defp fmt_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp fmt_time(_), do: "—"

  defp day_label(:monday), do: gettext("Lundi")
  defp day_label(:tuesday), do: gettext("Mardi")
  defp day_label(:wednesday), do: gettext("Mercredi")
  defp day_label(:thursday), do: gettext("Jeudi")
  defp day_label(:friday), do: gettext("Vendredi")
  defp day_label(:saturday), do: gettext("Samedi")
end
