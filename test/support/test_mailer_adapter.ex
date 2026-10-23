defmodule TeacherAssistant.TestMailerAdapter do
  @moduledoc """
  Swoosh's test adapter, except that mail to an `@undeliverable.test` address is
  refused, as the mail provider refuses a bad address — to test what users see then.
  """
  use Swoosh.Adapter

  alias Swoosh.Adapters.Test

  @impl true
  def deliver(%Swoosh.Email{to: to} = email, config) do
    if Enum.any?(to, fn {_name, address} -> String.ends_with?(address, "@undeliverable.test") end),
       do: {:error, :refused},
       else: Test.deliver(email, config)
  end

  @impl true
  def deliver_many(emails, config), do: Test.deliver_many(emails, config)
end
