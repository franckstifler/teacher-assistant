defmodule TeacherAssistantWeb.TimetablePrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.DayOfWeek
  alias TeacherAssistant.Academics.SchoolCalendar

  embed_templates "timetable_print_html/*"

  defp fmt_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp fmt_time(_), do: "—"

  defp day_label(d), do: DayOfWeek.label(d)

  # The class grid holds one slot per cell; a teacher's grid a list (spec J4).
  defp cell_slots(grid, :me, day, period_id), do: Map.get(grid, {day, period_id}, [])

  defp cell_slots(grid, _mode, day, period_id),
    do: grid |> Map.get({day, period_id}) |> List.wrap()
end
