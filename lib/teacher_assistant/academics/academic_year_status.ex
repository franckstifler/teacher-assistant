defmodule TeacherAssistant.Academics.AcademicYearStatus do
  @moduledoc "Spec KLM9: a school year is open until the next one starts, then closed for good."
  use Ash.Type.Enum, values: [:open, :closed]
end
