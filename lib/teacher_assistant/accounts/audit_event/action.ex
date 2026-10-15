defmodule TeacherAssistant.Accounts.AuditEvent.Action do
  use Ash.Type.Enum,
    values: [
      :school_verified,
      :school_rejected,
      :school_suspended,
      :school_reactivated,
      :modules_changed,
      :password_reset
    ]

  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:school_verified), do: gettext("Établissement vérifié")
  def label(:school_rejected), do: gettext("Établissement rejeté")
  def label(:school_suspended), do: gettext("Établissement suspendu")
  def label(:school_reactivated), do: gettext("Établissement réactivé")
  def label(:modules_changed), do: gettext("Modules modifiés")
  def label(:password_reset), do: gettext("Mot de passe réinitialisé")
end
