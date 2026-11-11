defmodule TeacherAssistant.Academics.MarkCorrection.Decide do
  @moduledoc """
  Approves or refuses a pending correction (spec D3c). Approval first checks the mark
  still holds the value seen at request time (else "stale"), records the decision, then
  writes the mark through the normal `Mark` actions in the same transaction: the lock
  lets that write through because the correction is now approved and not yet applied
  (`Mark.AssessmentOpen`). Refusal journals the refusal; the mark is untouched.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.{Mark, MarkCorrection, StampOperator}
  alias TeacherAssistant.Academics.Mark.Journal

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, opts, context) do
    decision = Keyword.fetch!(opts, :decision)

    changeset
    |> Ash.Changeset.before_action(&decide(&1, decision, context))
    |> Ash.Changeset.after_action(fn changeset, correction ->
      apply_decision(decision, correction, context, StampOperator.operator_id(changeset))
    end)
  end

  # Decides from the row as it is now, locked for the transaction — never from the
  # caller's copy, which may come from a page loaded before another admin decided.
  defp decide(changeset, decision, context) do
    case locked_row(changeset) do
      %{status: :pending} = current ->
        cond do
          decision == :approved and stale?(current, context) ->
            Ash.Changeset.add_error(changeset,
              field: :status,
              message: "stale: the mark changed since the request"
            )

          decision == :refused and blank?(Ash.Changeset.get_argument(changeset, :decision_note)) ->
            Ash.Changeset.add_error(changeset,
              field: :decision_note,
              message: "a refusal needs a note"
            )

          true ->
            Ash.Changeset.force_change_attributes(changeset, %{
              status: decision,
              decider_user_id: context.actor.id,
              decided_at: DateTime.utc_now(),
              decision_note: Ash.Changeset.get_argument(changeset, :decision_note)
            })
        end

      _decided_or_gone ->
        Ash.Changeset.add_error(changeset, field: :status, message: "already decided")
    end
  end

  defp blank?(nil), do: true
  defp blank?(note) when is_binary(note), do: String.trim(note) == ""

  # Internal read under the action's own authorization, hence `authorize?: false`.
  defp locked_row(%{data: %{id: id}, tenant: tenant}) do
    MarkCorrection
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(tenant: tenant, authorize?: false)
  end

  defp stale?(correction, context) do
    current = correction |> current_mark(context) |> Journal.snapshot()

    recorded =
      correction.current_status &&
        Journal.snapshot(%{status: correction.current_status, score: correction.current_score})

    current != recorded
  end

  defp apply_decision(:refused, correction, context, operator_id) do
    Journal.record!(correction.workspace_id, %{
      action: :correction_refusee,
      actor_user_id: context.actor.id,
      operator_user_id: operator_id,
      assessment_id: correction.assessment_id,
      student_id: correction.student_id,
      before_status: correction.current_status,
      before_score: correction.current_score,
      after_status: correction.requested_status,
      after_score: correction.requested_score,
      mark_correction_id: correction.id
    })

    {:ok, correction}
  end

  defp apply_decision(:approved, correction, context, _operator_id) do
    opts = [scope: context, context: %{mark_correction_id: correction.id}]
    attrs = %{status: correction.requested_status, score: correction.requested_score}

    result =
      case {current_mark(correction, context), correction.requested_status} do
        {nil, _status} ->
          Mark
          |> Ash.Changeset.for_create(
            :create,
            Map.merge(attrs, %{
              assessment_id: correction.assessment_id,
              student_id: correction.student_id
            }),
            opts
          )
          |> Ash.create(return_notifications?: true)

        {mark, nil} ->
          Ash.destroy(mark, [return_notifications?: true] ++ opts)

        {mark, _status} ->
          mark
          |> Ash.Changeset.for_update(:update, attrs, opts)
          |> Ash.update(return_notifications?: true)
      end

    case result do
      {:ok, _mark, notifications} -> {:ok, correction, notifications}
      {:ok, notifications} -> {:ok, correction, notifications}
      :ok -> {:ok, correction}
      {:error, error} -> {:error, error}
    end
  end

  defp current_mark(%{assessment_id: assessment_id, student_id: student_id}, context) do
    Mark
    |> Ash.Query.filter(assessment_id == ^assessment_id and student_id == ^student_id)
    |> Ash.read_one!(scope: context)
  end
end
