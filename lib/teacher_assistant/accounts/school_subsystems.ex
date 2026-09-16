defmodule TeacherAssistant.Accounts.SchoolSubsystems do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:francophone, :anglophone, :bilingual]
  def all, do: @order
  def label(:francophone), do: gettext("Francophone")
  def label(:anglophone), do: gettext("Anglophone")
  def label(:bilingual), do: gettext("Bilingue")
end
