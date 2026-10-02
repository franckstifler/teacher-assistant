defmodule TeacherAssistant.Academics.Guardian.Changes.PhoneKey do
  @moduledoc "Keeps `phone_key` in step with `phone`; refuses a number too short to be real."
  use Ash.Resource.Change

  alias TeacherAssistant.Academics.Guardian.Phone

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :phone) do
      {:ok, phone} when is_binary(phone) ->
        if Phone.valid?(phone) do
          Ash.Changeset.force_change_attribute(changeset, :phone_key, Phone.key(phone))
        else
          Ash.Changeset.add_error(changeset,
            field: :phone,
            message: "numéro de téléphone invalide"
          )
        end

      _ ->
        changeset
    end
  end

  # Only reads values set on the changeset itself, so it is safe in an atomic update.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
