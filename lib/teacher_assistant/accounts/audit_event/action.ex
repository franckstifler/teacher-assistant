defmodule TeacherAssistant.Accounts.AuditEvent.Action do
  use Ash.Type.Enum,
    values: [
      :school_verified,
      :school_rejected,
      :school_suspended,
      :school_reactivated,
      :modules_changed,
      :password_reset,
      :member_renamed,
      :impersonation_started,
      :impersonation_ended,
      # A9: the weekly sweep of upload files nothing points at.
      :files_swept
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:school_verified), do: gettext("Établissement vérifié")
  def label(:school_rejected), do: gettext("Établissement rejeté")
  def label(:school_suspended), do: gettext("Établissement suspendu")
  def label(:school_reactivated), do: gettext("Établissement réactivé")
  def label(:modules_changed), do: gettext("Modules modifiés")
  def label(:password_reset), do: gettext("Mot de passe réinitialisé")
  def label(:member_renamed), do: gettext("Membre renommé")
  def label(:impersonation_started), do: gettext("Accès en tant que")
  def label(:impersonation_ended), do: gettext("Fin de l'accès en tant que")
  def label(:files_swept), do: gettext("Fichiers orphelins supprimés")
end
