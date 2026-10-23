defmodule TeacherAssistant.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc """
  Sends a magic-link sign-in email to the user.

  Builds the sign-in link against the token-bearing `/magic_link/:token`
  live route (see `magic_sign_in_route/3` in `TeacherAssistantWeb.Router`)
  and delivers it via `TeacherAssistant.Mailer`.
  """

  use AshAuthentication.Sender
  use TeacherAssistantWeb, :verified_routes

  require Logger

  alias TeacherAssistant.{Accounts.Emails, Mailer, RateLimit}

  @impl true
  def send(user, token, _opts) do
    magic_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/magic_link/#{token}"

    # The request page answers the same either way; past the cap nothing is
    # sent, so no one can flood an inbox or spend the daily email quota.
    if RateLimit.allow?("account_email:#{user.id}", 3, :timer.hours(1)) do
      user
      |> Emails.magic_link(magic_url)
      |> Mailer.deliver()
      |> log_failure(user)
    end

    :ok
  end

  # The page answers the same whatever happens (no account enumeration), so a
  # refused send (bad address, provider quota) is only visible in the logs.
  defp log_failure({:error, reason}, user),
    do: Logger.error("magic link email to user #{user.id} not sent: #{inspect(reason)}")

  defp log_failure(_result, _user), do: :ok
end
