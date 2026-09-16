defmodule TeacherAssistant.Accounts.SchoolVerificationStatuses do
  use Gettext, backend: TeacherAssistantWeb.Gettext
  @order [:unverified, :verified, :rejected]
  def all, do: @order
  def label(:unverified), do: gettext("Non vérifié")
  def label(:verified), do: gettext("Vérifié")
  def label(:rejected), do: gettext("Rejeté")
end
