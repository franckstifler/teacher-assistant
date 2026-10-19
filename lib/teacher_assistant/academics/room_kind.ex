defmodule TeacherAssistant.Academics.RoomKind do
  @moduledoc "What a room is used for (spec J3)."
  use Ash.Type.Enum,
    values: [:classroom, :laboratory, :computer_room, :workshop, :sports, :other]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:classroom), do: gettext("Salle de classe")
  def label(:laboratory), do: gettext("Laboratoire")
  def label(:computer_room), do: gettext("Salle informatique")
  def label(:workshop), do: gettext("Atelier")
  def label(:sports), do: gettext("Terrain / salle de sport")
  def label(:other), do: gettext("Autre")
end
