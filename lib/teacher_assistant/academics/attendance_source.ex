defmodule TeacherAssistant.Academics.AttendanceSource do
  @moduledoc "Where a roll-call entry was taken: in the app, or typed in from a paper sheet (spec 2026-10-28)."
  use Ash.Type.Enum, values: [:app, :paper]
end
