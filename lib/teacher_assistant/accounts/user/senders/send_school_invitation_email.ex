defmodule TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail do
  @moduledoc """
  Delivers the school invitation email via `TeacherAssistant.Mailer`.
  The accept link is `/schools/invitations/<token>`.
  """
  alias TeacherAssistant.Mailer
  alias TeacherAssistant.Accounts.Emails
  use TeacherAssistantWeb, :verified_routes

  def send(email, school_name, token) do
    accept_url = TeacherAssistantWeb.Endpoint.url() <> ~p"/schools/invitations/#{token}"

    email
    |> Emails.school_invitation(school_name, accept_url)
    |> Mailer.deliver()

    :ok
  end
end
