defmodule TeacherAssistant.Academics.TrimesterAverageRule do
  use Ash.Type.Enum, values: [:mean_of_sequences, :second_sequence_double]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:mean_of_sequences), do: gettext("Moyenne des 2 séquences")
  def label(:second_sequence_double), do: gettext("Pondérée (2e séquence ×2)")
end
