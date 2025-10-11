defmodule TeacherAssistant.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        TeacherAssistant.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:teacher_assistant, :token_signing_secret)
  end
end
