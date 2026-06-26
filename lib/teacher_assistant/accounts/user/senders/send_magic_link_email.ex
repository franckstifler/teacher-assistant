defmodule TeacherAssistant.Accounts.User.Senders.SendMagicLinkEmail do
  @moduledoc false

  use AshAuthentication.Sender

  @impl true
  def send(_user_or_email, _token, _opts), do: :ok
end
