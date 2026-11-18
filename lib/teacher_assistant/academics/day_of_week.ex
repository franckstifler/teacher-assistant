defmodule TeacherAssistant.Academics.DayOfWeek do
  use Ash.Type.Enum,
    values: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:monday), do: gettext("Lundi")
  def label(:tuesday), do: gettext("Mardi")
  def label(:wednesday), do: gettext("Mercredi")
  def label(:thursday), do: gettext("Jeudi")
  def label(:friday), do: gettext("Vendredi")
  def label(:saturday), do: gettext("Samedi")

  @doc "The day's first three letters (« Lun », « Mon »), for narrow day strips."
  def short_label(day), do: day |> label() |> String.slice(0, 3)
end
