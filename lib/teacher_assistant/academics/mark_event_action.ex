defmodule TeacherAssistant.Academics.MarkEventAction do
  @moduledoc "What a marks-journal row records (spec D3a)."
  use Ash.Type.Enum,
    values: [:saisie, :correction_demandee, :correction_approuvee, :correction_refusee]
end
