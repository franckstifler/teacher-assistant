defmodule TeacherAssistant.Accounts.SchoolRoles do
  @moduledoc "Bilingual display labels for school roles (Décret 2001/041, doc 05 §1)."
  use Gettext, backend: TeacherAssistantWeb.Gettext

  @order [
    :head,
    :vice_principal,
    :discipline_master,
    :bursar,
    :hod,
    :form_master,
    :teacher,
    :guidance_counsellor,
    :librarian
  ]

  def all, do: @order

  def label(:head), do: gettext("Chef d'établissement")
  def label(:vice_principal), do: gettext("Censeur")
  def label(:discipline_master), do: gettext("Surveillant général")
  def label(:bursar), do: gettext("Intendant")
  def label(:hod), do: gettext("Animateur pédagogique")
  def label(:form_master), do: gettext("Professeur principal")
  def label(:teacher), do: gettext("Enseignant")
  def label(:guidance_counsellor), do: gettext("Conseiller d'orientation")
  def label(:librarian), do: gettext("Documentaliste")
end
