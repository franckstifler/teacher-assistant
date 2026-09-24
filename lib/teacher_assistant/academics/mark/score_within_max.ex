defmodule TeacherAssistant.Academics.Mark.ScoreWithinMax do
  @moduledoc """
  A `Mark`'s `score` can never exceed its `Assessment`'s `max_score`. Runs on
  both `:create` and `:update` so this holds regardless of entry point
  (including a raw `Ash.Changeset.for_create`/`for_update` that bypasses the
  `TeacherAssistant.Assessment.upsert_marks/2` domain-level guard).

  Skips the check entirely unless `:score` is actually changing (an `:update`
  that only touches other fields never needs to re-fetch the assessment), and
  fetches the assessment scoped to `changeset.tenant` — both `Mark` and
  `Assessment` are attribute-multitenant on `workspace_id`.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :score) do
      do_validate(changeset)
    else
      :ok
    end
  end

  defp do_validate(changeset) do
    assessment_id = Ash.Changeset.get_attribute(changeset, :assessment_id)
    score = Ash.Changeset.get_attribute(changeset, :score)

    if is_nil(assessment_id) or is_nil(score) do
      :ok
    else
      case Ash.get(TeacherAssistant.Academics.Assessment, assessment_id, tenant: changeset.tenant) do
        {:ok, assessment} ->
          if Decimal.compare(score, assessment.max_score) == :gt do
            {:error, field: :score, message: "exceeds the assessment's maximum"}
          else
            :ok
          end

        {:error, _reason} ->
          {:error, field: :assessment_id, message: "assessment not found"}
      end
    end
  end
end
