defmodule TeacherAssistant.Academics.MarkCorrectionMotive do
  @moduledoc "Why a teacher asks to correct a locked mark (spec D3c)."
  use Ash.Type.Enum,
    values: [:erreur_saisie, :copie_mal_corrigee, :reclamation_eleve, :note_rattrapage]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:erreur_saisie), do: gettext("Erreur de saisie")
  def label(:copie_mal_corrigee), do: gettext("Copie mal corrigée")
  def label(:reclamation_eleve), do: gettext("Réclamation de l'élève")
  def label(:note_rattrapage), do: gettext("Note de rattrapage")
end
