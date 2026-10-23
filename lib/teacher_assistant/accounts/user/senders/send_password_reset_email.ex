defmodule TeacherAssistant.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email to the user.

  Builds the reset link against the token-bearing `/password-reset/:token`
  live route (see `reset_route/1` in `TeacherAssistantWeb.Router`) and
  delivers it via `TeacherAssistant.Mailer`.
  """

  use AshAuthentication.Sender
  use TeacherAssistantWeb, :verified_routes

  require Logger

  alias TeacherAssistant.{Accounts.Emails, Mailer, RateLimit}

  @impl true
  def send(user, token, _opts) do
    reset_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/password-reset/#{token}"

    # The request page answers the same either way; past the cap nothing is
    # sent, so no one can flood an inbox or spend the daily email quota.
    if RateLimit.allow?("account_email:#{user.id}", 3, :timer.hours(1)) do
      user
      |> Emails.password_reset(reset_url)
      |> Mailer.deliver()
      |> log_failure(user)
    end

    :ok
  end

  # The page answers the same whatever happens (no account enumeration), so a
  # refused send (bad address, provider quota) is only visible in the logs.
  defp log_failure({:error, reason}, user),
    do: Logger.error("password reset email to user #{user.id} not sent: #{inspect(reason)}")

  defp log_failure(_result, _user), do: :ok
end
