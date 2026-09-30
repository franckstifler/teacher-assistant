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

    case sequence_id && Lock.fetch_sequence(sequence_id, context) do
      {:ok, seq} ->
        if Lock.locked?(seq),
          do: {:error, field: :sequence_id, message: "locked"},
          else: :ok

      # A missing séquence is the create's own required-field / FK error.
      _ ->
        :ok
    end
  end
end
