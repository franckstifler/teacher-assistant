defmodule TeacherAssistantWeb.RollSheetPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistantWeb.Dates

  embed_templates "roll_sheet_print_html/*"

  # Rows left empty under the roster for students who join during the week.
  @blank_rows 3

  defp blank_rows, do: 1..@blank_rows

  # « Semaine du lundi 15 au samedi 20 septembre 2025 »
  defp week_label(%{monday: monday, saturday: saturday}),
    do:
      gettext("Semaine du %{from} au %{to}",
        from: Dates.weekday_day(monday),
        to: "#{Dates.long(saturday)} #{saturday.year}"
      )

  # A closed day still takes one column, so its band shows.
  defp day_span(%{closed: nil, lessons: lessons}), do: max(length(lessons), 1)
  defp day_span(_day), do: 1

  # Every row of the body: students, blank rows and the visa row.
  defp body_rows(week), do: length(week.students) + @blank_rows + 1
end
