defmodule TeacherAssistant.Academics.Mark.ScoreWithinMax do
  @moduledoc """
  A `Mark`'s `score` can never exceed its `Assessment`'s `max_score`. Runs on
  both `:create` and `:update` so this holds regardless of entry point
  (including a raw `Ash.Changeset.for_create`/`for_update` that bypasses the
  `TeacherAssistant.Assessment.upsert_marks/2` domain-level guard).

  No tenant is set on the `Ash.get!/2` lookup yet — `Assessment` isn't
  multitenant until Task 11 flips it.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, _opts, _context) do
    assessment_id = Ash.Changeset.get_attribute(changeset, :assessment_id)
    score = Ash.Changeset.get_attribute(changeset, :score)

    if is_nil(assessment_id) or is_nil(score) do
      :ok
    else
      assessment = Ash.get!(TeacherAssistant.Academics.Assessment, assessment_id)

      if Decimal.compare(score, assessment.max_score) == :gt do
        {:error, field: :score, message: "exceeds the assessment's maximum"}
      else
        :ok
      end
    end
  end
end
