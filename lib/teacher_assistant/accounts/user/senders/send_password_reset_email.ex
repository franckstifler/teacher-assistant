defmodule TeacherAssistant.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email to the user.

  A no-op stub for now (mirrors `SendMagicLinkEmail`) — actual delivery isn't
  wired yet, but this makes the `password.resettable` strategy structurally
  complete so the "Mot de passe oublié ?" request-reset flow and the
  `/password-reset/:token` page actually render and function.
  """

  use AshAuthentication.Sender

  @impl true
  def send(_user_or_email, _token, _opts), do: :ok
end
