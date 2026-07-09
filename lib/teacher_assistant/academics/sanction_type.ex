defmodule TeacherAssistant.Academics.SanctionType do
  use Ash.Type.Enum,
    values: [:avertissement, :blame, :exclusion_temporaire, :exclusion_definitive, :consigne]
end
