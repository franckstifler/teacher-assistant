defmodule TeacherAssistant.Academics.BulletinElement do
  @moduledoc "Spec I5: the optional elements of the printed report card."
  use Ash.Type.Enum,
    values: [
      :rank,
      :class_average,
      :min_max,
      :subject_appreciation,
      :effectif,
      :birth,
      :absences,
      :conduct,
      :pp_signature,
      :signature,
      :stamp,
      :qr_code,
      :subject_rank,
      :subject_teacher,
      :class_extremes,
      :repeater,
      :form_master,
      :parent_visa,
      :verify_link
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc """
  Shown when the school has not chosen: everything but the QR code. A school that
  saved its list keeps exactly that list, so elements added later stay off there.
  """
  def defaults, do: values() -- [:qr_code]

  def label(:rank), do: gettext("Rang")
  def label(:class_average), do: gettext("Moyenne de la classe")
  def label(:min_max), do: gettext("Min / max de la classe")
  def label(:subject_appreciation), do: gettext("Appréciation (ou grade) par matière")
  def label(:effectif), do: gettext("Effectif")
  def label(:birth), do: gettext("Date et lieu de naissance")
  def label(:absences), do: gettext("Absences")
  def label(:conduct), do: gettext("Conduite (note, consignes, sanctions)")
  def label(:pp_signature), do: gettext("Signature du professeur principal")
  def label(:signature), do: gettext("Signature du chef d'établissement")
  def label(:stamp), do: gettext("Cachet")
  def label(:qr_code), do: gettext("QR de vérification")
  def label(:subject_rank), do: gettext("Rang par matière")
  def label(:subject_teacher), do: gettext("Enseignant de chaque matière")
  def label(:class_extremes), do: gettext("Plus forte / plus faible moyenne de la classe")
  def label(:repeater), do: gettext("Redoublant(e)")
  def label(:form_master), do: gettext("Professeur principal")
  def label(:parent_visa), do: gettext("Visa du parent")
  def label(:verify_link), do: gettext("Lien de vérification en ligne")
end
