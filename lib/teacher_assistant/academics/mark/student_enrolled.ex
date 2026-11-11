defmodule TeacherAssistant.Academics.Mark.StudentEnrolled do
  @moduledoc """
  A mark is for a student enrolled in the assessment's class — the roster the
  marks screen shows: an enrollment in that class group, still there on the first
  day of the assessment's séquence (A7: a student who left before it has no mark in
  it; one who left during it keeps it). Held here, not only
  on the screen, so every writer (bulk saves, corrections, the mobile app)
  meets it. Internal reads, hence `authorize?: false`; the write's own
  policies decide who may write.
  """
  use Ash.Resource.Validation

  require Ash.Query

  alias TeacherAssistant.Academics.{Assessment, Enrollment}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    assessment_id = Ash.Changeset.get_attribute(changeset, :assessment_id)
    student_id = Ash.Changeset.get_attribute(changeset, :student_id)

    case class_group_id(assessment_id, changeset.tenant) do
      # A missing assessment is reported by the write itself (and `ScoreWithinMax`).
      nil ->
        :ok

      {class_group_id, first_day} ->
        if enrolled?(student_id, class_group_id, first_day, changeset.tenant),
          do: :ok,
          else: {:error, field: :student_id, message: "is not enrolled in this class"}
    end
  end

  defp class_group_id(assessment_id, tenant) when is_binary(assessment_id) do
    case Ash.get(Assessment, assessment_id,
           load: [:teaching_context, :sequence],
           tenant: tenant,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, %Assessment{teaching_context: %{class_group_id: id}, sequence: seq}} ->
        {id, seq && seq.start_date}

      _ ->
        nil
    end
  end

  defp class_group_id(_assessment_id, _tenant), do: nil

  @doc false
  def enrolled?(student_id, class_group_id, first_day, tenant) when is_binary(student_id) do
    Enrollment
    |> Ash.Query.filter(student_id == ^student_id and class_group_id == ^class_group_id)
    |> then(
      &if(first_day, do: Ash.Query.filter(&1, is_nil(left_on) or left_on > ^first_day), else: &1)
    )
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  def enrolled?(_student_id, _class_group_id, _first_day, _tenant), do: false
end
