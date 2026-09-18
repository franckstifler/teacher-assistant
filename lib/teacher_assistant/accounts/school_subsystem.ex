defmodule TeacherAssistant.Accounts.SchoolSubsystem do
  use Ash.Type.Enum, values: [:francophone, :anglophone, :bilingual]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:francophone), do: gettext("Francophone")
  def label(:anglophone), do: gettext("Anglophone")
  def label(:bilingual), do: gettext("Bilingue")
end
