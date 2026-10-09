defmodule TeacherAssistant.Academics.MarkCorrectionMotive do
  @moduledoc "Why a teacher asks to correct a locked mark (spec D3c)."
  use Ash.Type.Enum,
    values: [
      :erreur_saisie,
      :copie_retrouvee,
      :note_rattrapage,
      :erreur_calcul,
      :copie_mal_corrigee,
      :reclamation_eleve
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  @doc "The motives the request form offers (spec 2026-10-09 §1.2); the last two stay for history."
  def offered, do: [:erreur_saisie, :copie_retrouvee, :note_rattrapage, :erreur_calcul]

  def label(:erreur_saisie), do: gettext("Erreur de saisie")
  def label(:copie_retrouvee), do: gettext("Copie retrouvée")
  def label(:note_rattrapage), do: gettext("Rattrapage")
  def label(:erreur_calcul), do: gettext("Erreur de calcul")
  def label(:copie_mal_corrigee), do: gettext("Copie mal corrigée")
  def label(:reclamation_eleve), do: gettext("Réclamation de l'élève")
end
