defmodule TeacherAssistant.Accounts.SchoolRole do
  @moduledoc "Bilingual display labels for school roles (Décret 2001/041, doc 05 §1)."

  use Ash.Type.Enum,
    values: [
      :head,
      :vice_principal,
      :discipline_master,
      :bursar,
      :hod,
      :teacher,
      :guidance_counsellor,
      :librarian
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:head), do: gettext("Chef d'établissement")
  def label(:vice_principal), do: gettext("Censeur")
  def label(:discipline_master), do: gettext("Surveillant général")
  def label(:bursar), do: gettext("Intendant")
  def label(:hod), do: gettext("Animateur pédagogique")
  def label(:teacher), do: gettext("Enseignant")
  def label(:guidance_counsellor), do: gettext("Conseiller d'orientation")
  def label(:librarian), do: gettext("Documentaliste")
end
