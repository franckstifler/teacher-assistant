defmodule TeacherAssistant.Academics.SubjectCategory do
  use Ash.Type.Enum, values: [:general, :language, :technical]
end
