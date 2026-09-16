defmodule TeacherAssistant.Academics.PeriodKind do
  use Ash.Type.Enum, values: [:lesson, :break]
end
