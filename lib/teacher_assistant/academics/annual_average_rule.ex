defmodule TeacherAssistant.Academics.AnnualAverageRule do
  use Ash.Type.Enum, values: [:mean_of_sequences, :mean_of_trimesters]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:mean_of_sequences), do: gettext("Moyenne des 6 séquences")
  def label(:mean_of_trimesters), do: gettext("Moyenne des 3 trimestres")
end
