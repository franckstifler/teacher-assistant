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
      :qr_code
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc "Shown when the school has not chosen: everything but the QR code."
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
end
