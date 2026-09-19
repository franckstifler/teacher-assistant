defmodule TeacherAssistant.Academics.PeriodKind do
  use Ash.Type.Enum, values: [:lesson, :break]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:lesson), do: gettext("Cours")
  def label(:break), do: gettext("Récréation")
end
