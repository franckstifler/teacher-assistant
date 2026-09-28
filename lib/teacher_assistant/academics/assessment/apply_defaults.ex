defmodule TeacherAssistant.Academics.Assessment.ApplyDefaults do
  @moduledoc """
  On create: copies the assessment type's `default_weight` when no weight was given,
  and the school's `default_max_score` when no maximum was given (spec D2b-2).
  """
  use Ash.Resource.Change
  require Ash.Query

  alias TeacherAssistant.Accounts.SchoolProfile
  alias TeacherAssistant.Academics.AssessmentType

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      changeset
      |> default_weight(context)
      |> default_max(changeset.tenant)
    end)
  end

  defp default_weight(changeset, context) do
    type_id = Ash.Changeset.get_attribute(changeset, :assessment_type_id)

    if type_id && not given?(changeset, :weight) do
      case Ash.get(AssessmentType, type_id, scope: context) do
        {:ok, type} ->
          Ash.Changeset.force_change_attribute(changeset, :weight, type.default_weight)

        _ ->
          Ash.Changeset.add_error(changeset,
            field: :assessment_type_id,
            message: "is not a type of this school"
          )
      end
    else
      changeset
    end
  end

  defp default_max(changeset, tenant) do
    if given?(changeset, :max_score) do
      changeset
    else
      case SchoolProfile
           |> Ash.Query.filter(workspace_id == ^tenant)
           |> Ash.read_one!(authorize?: false) do
        %{default_max_score: max} ->
          Ash.Changeset.force_change_attribute(changeset, :max_score, max)

        nil ->
          changeset
      end
    end
  end

  # Explicitly provided (not just the attribute's own default, which Ash lists in
  # `changeset.defaults` until a value is set).
  defp given?(changeset, attribute) do
    Ash.Changeset.changing_attribute?(changeset, attribute) and
      attribute not in changeset.defaults
  end
end
