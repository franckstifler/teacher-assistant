defmodule TeacherAssistant.Academics.Mark.AssessmentOpen do
  @moduledoc """
  A mark of a locked assessment (spec D3b) cannot be created, changed or deleted — by
  anyone, admins included — except by an approved correction (spec D3c). Nor before its
  séquence starts.
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias TeacherAssistant.Academics.{Assessment, Lock, MarkCorrection, MarkEvent}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    assessment_id = mark_value(changeset, :assessment_id)

    case lock_state(assessment_id, context) do
      :locked ->
        if approved_correction?(changeset),
          do: :ok,
          else: {:error, field: :assessment_id, message: "locked"}

      :not_started ->
        {:error, field: :assessment_id, message: "not started"}

      # A missing assessment is reported by the write itself (and `ScoreWithinMax`).
      state when state in [:open, :missing] ->
        :ok

      # Refuse rather than fail open when the lock cannot be read.
      {:error, _} ->
        {:error, field: :assessment_id, message: "lock could not be checked"}
    end
  end

  defp lock_state(nil, _context), do: :missing

  defp lock_state(assessment_id, context) do
    case Ash.get(Assessment, assessment_id, scope: context, not_found_error?: false) do
      {:ok, nil} -> :missing
      {:ok, assessment} -> Lock.sequence_state(assessment.sequence_id, context)
      {:error, error} -> {:error, error}
    end
  end

  # The write applies an approved correction of this very mark, not yet applied. Only
  # `MarkCorrection.Decide` makes it true: the correction must already be approved in the
  # database (an admin-only action, same transaction), so passing a correction id in a
  # write's context unlocks nothing. Internal reads, hence `authorize?: false`.
  defp approved_correction?(changeset) do
    with id when is_binary(id) <- changeset.context[:mark_correction_id],
         {:ok, %{status: :approved} = correction} <-
           Ash.get(MarkCorrection, id, tenant: changeset.tenant, authorize?: false) do
      correction.assessment_id == mark_value(changeset, :assessment_id) and
        correction.student_id == mark_value(changeset, :student_id) and
        not applied?(correction, changeset.tenant)
    else
      _ -> false
    end
  end

  defp applied?(correction, tenant) do
    MarkEvent
    |> Ash.Query.filter(mark_correction_id == ^correction.id and action == :correction_approuvee)
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  defp mark_value(changeset, field),
    do: Ash.Changeset.get_attribute(changeset, field) || Map.get(changeset.data, field)
end
