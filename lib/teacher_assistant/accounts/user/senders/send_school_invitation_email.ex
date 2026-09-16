defmodule TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail do
  @moduledoc """
  Stub sender for school invitations. Email delivery is not yet wired in this
  app (the magic-link sender is likewise a no-op); this returns `:ok` and is
  the single place to add real Swoosh delivery once a Mailer is configured.
  The accept link is `/schools/invitations/<token>`.
  """
  require Logger

  def send(email, school_name, token) do
    Logger.debug("[school-invite] #{email} → #{school_name} (/schools/invitations/#{token})")
    :ok
  end
end
