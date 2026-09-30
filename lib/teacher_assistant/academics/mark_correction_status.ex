defmodule TeacherAssistant.Academics.MarkCorrectionStatus do
  @moduledoc "Where a correction request stands (spec D3c)."
  use Ash.Type.Enum, values: [:pending, :approved, :refused]
end
