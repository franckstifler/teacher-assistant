defmodule TeacherAssistant.Academics.CouncilStatus do
  @moduledoc "A class council is open (being prepared) or held (spec I3)."
  use Ash.Type.Enum, values: [:open, :held]
end
