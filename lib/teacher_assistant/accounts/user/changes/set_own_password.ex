defmodule TeacherAssistant.Accounts.User.Changes.SetOwnPassword do
  @moduledoc "Stores the password the user chose and lifts the forced change."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      {:ok, hash} =
        changeset
        |> Ash.Changeset.get_argument(:password)
        |> AshAuthentication.BcryptProvider.hash()

      changeset
      |> Ash.Changeset.force_change_attribute(:hashed_password, hash)
      |> Ash.Changeset.force_change_attribute(:must_change_password, false)
      |> Ash.Changeset.force_change_attribute(:temporary_password_expires_at, nil)
    end)
  end
end
