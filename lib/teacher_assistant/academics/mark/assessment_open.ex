defmodule TeacherAssistant.Academics.Mark.AssessmentOpen do
  @moduledoc """
  A mark of a locked assessment (spec D3b) cannot be created, changed or deleted — by
  anyone, admins included — except by an approved correction (spec D3c).
  """
  use Ash.Resource.Validation

  alias TeacherAssistant.Academics.{Assessment, Lock}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, context) do
    assessment_id =
      Ash.Changeset.get_attribute(changeset, :assessment_id) || changeset.data.assessment_id

    with {:ok, assessment} <- Ash.get(Assessment, assessment_id, scope: context),
         {:ok, seq} <- Lock.fetch_sequence(assessment.sequence_id, context),
         true <- Lock.locked?(seq),
         false <- approved_correction?(changeset) do
      {:error, field: :assessment_id, message: "locked"}
    else
      # A missing assessment is reported by the write itself (and `ScoreWithinMax`).
      _ -> :ok
    end
  end

  # Task 5 replaces this with the pending-correction check.
  defp approved_correction?(_changeset), do: false
end
