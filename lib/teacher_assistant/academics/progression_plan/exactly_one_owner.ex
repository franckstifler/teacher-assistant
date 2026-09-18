defmodule TeacherAssistant.Academics.ProgressionPlan.ExactlyOneOwner do
  @moduledoc """
  A `ProgressionPlan` belongs to exactly one teaching unit: a lone
  `TeachingContext` (`teaching_context_id`) OR a `CombinedCourse`
  (`combined_course_id`) — never both, never neither. Enforced here, on
  `:create`, so the spec's "exactly one owner" rule is checked in the
  context layer rather than left to caller discipline.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    teaching_context_id = Ash.Changeset.get_attribute(changeset, :teaching_context_id)
    combined_course_id = Ash.Changeset.get_attribute(changeset, :combined_course_id)

    case {is_nil(teaching_context_id), is_nil(combined_course_id)} do
      {true, true} ->
        {:error,
         field: :teaching_context_id,
         message: "must set either teaching_context_id or combined_course_id"}

      {false, false} ->
        {:error,
         field: :teaching_context_id,
         message: "must not set both teaching_context_id and combined_course_id"}

      _ ->
        :ok
    end
  end
end
