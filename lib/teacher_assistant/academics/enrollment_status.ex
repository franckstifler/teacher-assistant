defmodule TeacherAssistant.Academics.EnrollmentStatus do
  use Ash.Type.Enum, values: [:inscription, :reinscription]
end
