defmodule TeacherAssistant.Academics.DayOfWeek do
  use Ash.Type.Enum,
    values: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]
end
