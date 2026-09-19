defmodule TeacherAssistant.Accounts.CameroonRegion do
  use Ash.Type.Enum,
    values: [
      :adamawa,
      :centre,
      :east,
      :far_north,
      :littoral,
      :north,
      :northwest,
      :south,
      :southwest,
      :west
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:adamawa), do: gettext("Adamaoua")
  def label(:centre), do: gettext("Centre")
  def label(:east), do: gettext("Est")
  def label(:far_north), do: gettext("Extrême-Nord")
  def label(:littoral), do: gettext("Littoral")
  def label(:north), do: gettext("Nord")
  def label(:northwest), do: gettext("Nord-Ouest")
  def label(:south), do: gettext("Sud")
  def label(:southwest), do: gettext("Sud-Ouest")
  def label(:west), do: gettext("Ouest")
end
