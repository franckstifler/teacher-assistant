defmodule TeacherAssistant.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic-link sign-in email to the user.

  Builds the sign-in link against the token-bearing `/magic_link/:token`
  live route (see `magic_sign_in_route/3` in `TeacherAssistantWeb.Router`)
  and delivers it via `TeacherAssistant.Mailer`.
  """

  use AshAuthentication.Sender
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.{Accounts.Emails, Mailer}

  @impl true
  def send(user, token, _opts) do
    magic_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/magic_link/#{token}"

    user
    |> Emails.magic_link(magic_url)
    |> Mailer.deliver()

    :ok
  end
end
