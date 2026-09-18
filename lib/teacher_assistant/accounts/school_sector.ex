defmodule TeacherAssistant.Accounts.SchoolSector do
  use Ash.Type.Enum, values: [:public, :private_lay, :private_confessional, :community]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:public), do: gettext("Public")
  def label(:private_lay), do: gettext("Privé laïc")
  def label(:private_confessional), do: gettext("Privé confessionnel")
  def label(:community), do: gettext("Communautaire")
end
