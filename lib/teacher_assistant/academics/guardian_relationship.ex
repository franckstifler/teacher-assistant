defmodule TeacherAssistant.Academics.GuardianRelationship do
  @moduledoc "Spec KLM1: how a guardian is related to the student."
  use Ash.Type.Enum, values: [:pere, :mere, :tuteur, :autre]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:pere), do: gettext("Père")
  def label(:mere), do: gettext("Mère")
  def label(:tuteur), do: gettext("Tuteur")
  def label(:autre), do: gettext("Autre")
end
