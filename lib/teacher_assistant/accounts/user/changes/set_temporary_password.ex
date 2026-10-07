defmodule TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword do
  @moduledoc """
  Gives the account a fresh temporary password (valid 7 days, change forced at
  first sign-in). Only the hash is stored; the clear value is returned once as
  `user.__metadata__.temporary_password` for the head to hand over.
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Accounts.TemporaryPassword

  @validity_days 7

  @impl true
  def change(changeset, _opts, _context) do
    password = TemporaryPassword.generate()
    {:ok, hash} = AshAuthentication.BcryptProvider.hash(password)

    expires_at =
      DateTime.utc_now() |> DateTime.add(@validity_days, :day) |> DateTime.truncate(:second)

    changeset
    |> Ash.Changeset.force_change_attribute(:hashed_password, hash)
    |> Ash.Changeset.force_change_attribute(:must_change_password, true)
    |> Ash.Changeset.force_change_attribute(:temporary_password_expires_at, expires_at)
    |> Ash.Changeset.after_action(fn _changeset, user ->
      {:ok, Ash.Resource.put_metadata(user, :temporary_password, password)}
    end)
  end
end
