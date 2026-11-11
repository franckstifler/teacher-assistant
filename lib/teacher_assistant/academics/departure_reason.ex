defmodule TeacherAssistant.Academics.DepartureReason do
  @moduledoc "Why a student left their class during the year (spec audit follow-ups A7)."
  use Ash.Type.Enum, values: [:transfer, :dropout, :exclusion, :other]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:transfer), do: gettext("Transfert")
  def label(:dropout), do: gettext("Abandon")
  def label(:exclusion), do: gettext("Exclusion")
  def label(:other), do: gettext("Autre")
end
