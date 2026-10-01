defmodule TeacherAssistant.Academics.Distinction do
  @moduledoc """
  A student's distinction for a period (spec I1): one of the three honour rolls, or a
  work warning (avertissement / blâme de travail). Computed from the school's
  thresholds by `Academics.Appreciations.distinction/4`.
  """
  use Ash.Type.Enum,
    values: [
      :felicitations,
      :encouragements,
      :tableau_honneur,
      :avertissement_travail,
      :blame_travail
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:felicitations), do: gettext("Félicitations")
  def label(:encouragements), do: gettext("Encouragements")
  def label(:tableau_honneur), do: gettext("Tableau d'honneur")
  def label(:avertissement_travail), do: gettext("Avertissement travail")
  def label(:blame_travail), do: gettext("Blâme travail")

  def honour?(value), do: value in [:felicitations, :encouragements, :tableau_honneur]
end
