defmodule TeacherAssistant.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email to the user.

  Builds the reset link against the token-bearing `/password-reset/:token`
  live route (see `reset_route/1` in `TeacherAssistantWeb.Router`) and
  delivers it via `TeacherAssistant.Mailer`.
  """

  use AshAuthentication.Sender
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{Accounts.Emails, Mailer}

  @impl true
  def send(user, token, _opts) do
    reset_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/password-reset/#{token}"

    user
    |> Emails.password_reset(reset_url)
    |> Mailer.deliver()

    :ok
  end
end
