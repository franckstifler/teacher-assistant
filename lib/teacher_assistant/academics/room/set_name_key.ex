defmodule TeacherAssistant.Academics.Room.SetNameKey do
  @moduledoc "Keeps `name_key` (trimmed, lower-case name) in step with `name`, for the per-school unique name."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      name when is_binary(name) ->
        Ash.Changeset.force_change_attribute(changeset, :name_key, name |> String.trim() |> String.downcase())

      _ ->
        changeset
    end
  end

  # Only the written `name` is read, so the change works the same in an atomic update.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
