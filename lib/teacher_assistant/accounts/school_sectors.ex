defmodule TeacherAssistant.Accounts.SchoolSectors do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:public, :private_lay, :private_confessional, :community]
  def all, do: @order
  def label(:public), do: gettext("Public")
  def label(:private_lay), do: gettext("Privé laïc")
  def label(:private_confessional), do: gettext("Privé confessionnel")
  def label(:community), do: gettext("Communautaire")
end
