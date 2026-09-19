defmodule TeacherAssistant.Accounts.SchoolVerificationStatus do
  use Ash.Type.Enum, values: [:unverified, :verified, :rejected]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:unverified), do: gettext("Non vérifié")
  def label(:verified), do: gettext("Vérifié")
  def label(:rejected), do: gettext("Rejeté")
end
