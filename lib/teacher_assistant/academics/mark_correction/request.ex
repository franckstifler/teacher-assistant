defmodule TeacherAssistant.Academics.MarkCorrection.Request do
  @moduledoc """
  Files a correction request (spec D3c): only for a locked assessment, for a value that
  is valid and differs from the mark's; snapshots the mark's current value and journals
  the request.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.{Assessment, Enrollment, Lock, Mark}
  alias TeacherAssistant.Academics.Mark.Journal

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> Ash.Changeset.before_action(&snapshot_current(&1, context))
    |> Ash.Changeset.after_action(fn _changeset, correction ->
      Journal.record!(correction.workspace_id, %{
        action: :correction_demandee,
        actor_user_id: correction.requester_user_id,
        assessment_id: correction.assessment_id,
        student_id: correction.student_id,
        before_status: correction.current_status,
        before_score: correction.current_score,
        after_status: correction.requested_status,
        after_score: correction.requested_score,
        mark_correction_id: correction.id
      })

      {:ok, correction}
    end)
  end

  defp snapshot_current(changeset, context) do
    assessment_id = Ash.Changeset.get_attribute(changeset, :assessment_id)
    student_id = Ash.Changeset.get_attribute(changeset, :student_id)

    with {:ok, assessment} <- Ash.get(Assessment, assessment_id, scope: context),
         {:ok, seq} <- Lock.fetch_sequence(assessment.sequence_id, context),
         :ok <- require_locked(seq),
         :ok <- require_enrolled(assessment, student_id, changeset.tenant),
         {:ok, requested} <- requested_value(changeset, assessment),
         current = Journal.snapshot(current_mark(assessment_id, student_id, context)),
         :ok <- require_change(requested, current) do
      Ash.Changeset.force_change_attributes(changeset, %{
        requested_score: requested && requested.score,
        current_status: current && current.status,
        current_score: current && current.score
      })
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp require_locked(seq) do
    if Lock.locked?(seq), do: :ok, else: {:error, :assessment_id, "not locked"}
  end

  # Once approved, the correction writes a mark: the student must be in the assessment's
  # class. Internal read, hence `authorize?: false`; the requester's own rights are checked
  # by the action's policies.
  defp require_enrolled(assessment, student_id, tenant) do
    with {:ok, %{teaching_context: %{class_group_id: class_group_id}}} <-
           Ash.load(assessment, :teaching_context, tenant: tenant, authorize?: false) do
      Enrollment
      |> Ash.Query.filter(class_group_id == ^class_group_id and student_id == ^student_id)
      |> Ash.exists?(tenant: tenant, authorize?: false)
      |> if(do: :ok, else: {:error, :student_id, "not enrolled in this class"})
    end
  end

  # The requested value as a mark snapshot (nil = blank).
  defp requested_value(changeset, assessment) do
    score = Ash.Changeset.get_attribute(changeset, :requested_score)

    case Ash.Changeset.get_attribute(changeset, :requested_status) do
      nil ->
        {:ok, nil}

      :graded when is_nil(score) ->
        {:error, :requested_score, "is required"}

      :graded ->
        if Decimal.compare(score, 0) == :lt or Decimal.compare(score, assessment.max_score) == :gt,
          do: {:error, :requested_score, "out of range"},
          else: {:ok, Journal.snapshot(%{status: :graded, score: score})}

      status ->
        {:ok, %{status: status, score: nil}}
    end
  end

  defp require_change(same, same), do: {:error, :requested_score, "unchanged"}
  defp require_change(_requested, _current), do: :ok

  defp current_mark(assessment_id, student_id, context) do
    Mark
    |> Ash.Query.filter(assessment_id == ^assessment_id and student_id == ^student_id)
    |> Ash.read_one!(scope: context)
  end
end
