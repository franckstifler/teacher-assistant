defmodule TeacherAssistant.Academics.Mark.Journal do
  @moduledoc """
  Journals a mark write (spec D3a) in the same transaction: one `MarkEvent` with the
  value before and after. A write that changes nothing (`12` vs `12.0`) records nothing.
  The save's `context.mark_batch_id` groups rows; `context.mark_correction_id` marks an
  approved correction.
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Academics.MarkEvent

  @impl true
  def change(changeset, _opts, context) do
    before = if changeset.action_type == :create, do: nil, else: snapshot(changeset.data)

    Ash.Changeset.after_action(changeset, fn changeset, mark ->
      now = if changeset.action_type == :destroy, do: nil, else: snapshot(mark)

      if now != before do
        correction_id = changeset.context[:mark_correction_id]

        record!(mark.workspace_id, %{
          action: if(correction_id, do: :correction_approuvee, else: :saisie),
          actor_user_id: context.actor && context.actor.id,
          assessment_id: mark.assessment_id,
          student_id: mark.student_id,
          before_status: before && before.status,
          before_score: before && before.score,
          after_status: now && now.status,
          after_score: now && now.score,
          batch_id: changeset.context[:mark_batch_id],
          mark_correction_id: correction_id
        })
      end

      {:ok, mark}
    end)
  end

  @doc "Writes one journal row — the sanctioned bypass of `:record`'s forbid-all policy."
  def record!(workspace_id, attrs) do
    MarkEvent
    |> Ash.Changeset.for_create(:record, attrs, tenant: workspace_id, authorize?: false)
    |> Ash.create!()
  end

  @doc "A mark's value for comparison: `%{status, score}` with a normalized score, or nil."
  def snapshot(nil), do: nil

  def snapshot(mark),
    do: %{status: mark.status, score: mark.score && Decimal.normalize(mark.score)}
end
