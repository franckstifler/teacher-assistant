defmodule TeacherAssistant.Academics.CouncilDistinctionChoice do
  @moduledoc """
  The class council's work-distinction choice (spec I3): one of the I1 distinctions, or
  `:none` to remove the proposal. No choice (nil) keeps the I1 proposal.
  """
  use Ash.Type.Enum,
    values: [
      :felicitations,
      :encouragements,
      :tableau_honneur,
      :avertissement_travail,
      :blame_travail,
      :none
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:none), do: gettext("Aucune")
  def label(value), do: TeacherAssistant.Academics.Distinction.label(value)
end
