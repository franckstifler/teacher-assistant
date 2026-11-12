defmodule TeacherAssistantWeb.RollSheetPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistantWeb.Dates

  embed_templates "roll_sheet_print_html/*"

  # Rows left empty under the roster for students who join during the week.
  @blank_rows 3

  defp rows(week),
    do: week.students ++ List.duplicate(%{number: nil, student_name: nil}, @blank_rows)

  @doc "« Semaine du lundi 15 au samedi 20 septembre 2025 » (also the entry screen's title)."
  def week_label(%{monday: monday, saturday: saturday}),
    do:
      gettext("Semaine du %{from} au %{to}",
        from: Dates.weekday_day(monday),
        to: "#{Dates.long(saturday)} #{saturday.year}"
      )

  @doc "« 07:30–08:20 », a column's head on the sheet and the entry screen."
  def period_hours(%{start_time: from, end_time: to}),
    do: "#{Calendar.strftime(from, "%H:%M")}–#{Calendar.strftime(to, "%H:%M")}"

  # A closed day still takes one column, so its band shows.
  defp day_span(%{closed: nil, cells: cells}), do: max(length(cells), 1)
  defp day_span(_day), do: 1

  # Every row of the body: students, blank rows and the visa row.
  defp body_rows(week), do: length(week.students) + @blank_rows + 1
end
