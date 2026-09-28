defmodule TeacherAssistant.Academics.BulletinGroup do
  @moduledoc """
  The group a subject is listed under on the bulletin (mockup "Matières & coefficients"):
  G1 lettres, G2 sciences, G3 autres. Groups order the bulletin rows; subtotals per
  group are a school setting (`SchoolProfile.bulletin_group_subtotals?`).
  """
  use Ash.Type.Enum, values: [:g1_lettres, :g2_sciences, :g3_autres]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:g1_lettres), do: gettext("Groupe 1 · Lettres")
  def label(:g2_sciences), do: gettext("Groupe 2 · Sciences")
  def label(:g3_autres), do: gettext("Groupe 3 · Autres")

  def short(:g1_lettres), do: "G1"
  def short(:g2_sciences), do: "G2"
  def short(:g3_autres), do: "G3"

  def rank(:g1_lettres), do: 1
  def rank(:g2_sciences), do: 2
  def rank(:g3_autres), do: 3
end
