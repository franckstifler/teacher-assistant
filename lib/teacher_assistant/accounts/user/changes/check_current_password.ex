defmodule TeacherAssistant.Accounts.User.Changes.CheckCurrentPassword do
  @moduledoc """
  Refuses a password change unless `current_password` is the account's password.
  At most 10 tries per account in 15 minutes, as for signing in: an open session
  left on a shared phone must not become a way to guess the password. Runs as a
  before-action hook, so a form's live validation neither hashes nor counts.
  """
  use Ash.Resource.Change

  alias AshAuthentication.Strategy.Password.PasswordValidation
  alias TeacherAssistant.RateLimit

  @limit 10
  @scale :timer.minutes(15)

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      key = "change_password:" <> changeset.data.id

      cond do
        not RateLimit.allow?(key, @limit, @scale) ->
          Ash.Changeset.add_error(changeset,
            field: :current_password,
            message: "too many attempts, try again in a quarter of an hour"
          )

        PasswordValidation.validate(
          changeset,
          [strategy_name: :password, password_argument: :current_password],
          context
        ) == :ok ->
          RateLimit.set(key, @scale, 0)
          changeset

        true ->
          Ash.Changeset.add_error(changeset,
            field: :current_password,
            message: "is not your current password"
          )
      end
    end)
  end
end
