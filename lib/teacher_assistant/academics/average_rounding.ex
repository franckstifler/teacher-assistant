defmodule TeacherAssistant.Academics.AverageRounding do
  use Ash.Type.Enum, values: [:hundredth, :tenth, :quarter]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:hundredth), do: gettext("2 décimales")
  def label(:tenth), do: gettext("1 décimale")
  def label(:quarter), do: gettext("Au quart de point")
end
