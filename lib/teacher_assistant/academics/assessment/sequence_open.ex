defmodule TeacherAssistant.Academics.Assessment.SequenceOpen do
  @moduledoc "An assessment of a locked séquence cannot be created, edited or deleted (spec D3b)."
  use Ash.Resource.Validation

  alias TeacherAssistant.Academics.Lock

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    sequence_id =
      Ash.Changeset.get_attribute(changeset, :sequence_id) || changeset.data.sequence_id

    case Lock.sequence_state(sequence_id, context) do
      :locked -> {:error, field: :sequence_id, message: "locked"}
      # A missing séquence is the create's own required-field / FK error.
      state when state in [:open, :missing] -> :ok
      # Refuse rather than fail open when the lock cannot be read.
      {:error, _} -> {:error, field: :sequence_id, message: "lock could not be checked"}
    end
  end
end
