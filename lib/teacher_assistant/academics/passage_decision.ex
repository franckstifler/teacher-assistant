defmodule TeacherAssistant.Academics.PassageDecision do
  @moduledoc "The end-of-year decision for a student (spec I4)."
  use Ash.Type.Enum, values: [:admis, :admis_rachat, :redouble, :exclu]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:admis), do: gettext("Admis")
  def label(:admis_rachat), do: gettext("Admis par rachat")
  def label(:redouble), do: gettext("Redouble")
  def label(:exclu), do: gettext("Exclu")
end
