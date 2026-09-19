defmodule TeacherAssistantWeb.TimetablePrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.DayOfWeek

  embed_templates "timetable_print_html/*"

  defp fmt_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp fmt_time(_), do: "—"

  defp day_label(d), do: DayOfWeek.label(d)
end
