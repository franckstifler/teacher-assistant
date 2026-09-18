defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  # NAME COLLISION: this domain module is `TeacherAssistant.Assessment`, and
  # the resource is `TeacherAssistant.Academics.Assessment`. Inside this module
  # the short alias `Assessment` is bound to the RESOURCE (below); this module
  # calls its own domain functions bare, so there is never a bare
  # `Assessment.<fn>` that could rebind to the wrong module.
  alias TeacherAssistant.Academics.{
    Assessment,
    CombinedCourse,
    Mark,
    Sequence,
    TeachingContext,
    Workspace
  }

  resources do
    resource Assessment
    resource Mark
  end

  authorization do
    authorize :when_requested
  end

  # --- Assessments -----------------------------------------------------------

  def create_assessment(%TeachingContext{} = ctx, %Sequence{id: seq_id}, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:sequence_id, seq_id)

    Assessment |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
  end

  def list_assessments(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    Assessment
    |> Ash.Query.for_read(:for_context_and_sequence, %{
      teaching_context_id: ctx_id,
      sequence_id: seq_id
    })
    |> Ash.read!()
  end

  @doc """
  Per-séquence assessments for a `CombinedCourse`, one teacher-facing column
  per label backed by one real `Assessment` per member class. See the
  `:combined_for` action on `TeacherAssistant.Academics.Assessment` for the
  full contract. Returns the list of column maps.
  """
  def combined_assessments_for(%CombinedCourse{} = course, %Sequence{} = seq) do
    {:ok, entries} =
      Assessment
      |> Ash.ActionInput.for_action(:combined_for, %{course: course, sequence: seq})
      |> Ash.run_action()

    entries
  end

  @doc """
  Creates one `Assessment{label, sequence}` per member context of a
  `CombinedCourse`, atomically. Returns `{:ok, [%Assessment{}, ...]}` or
  `{:error, reason}`.
  """
  def create_combined_assessment(%CombinedCourse{} = course, %Sequence{} = seq, attrs) do
    label = Map.get(attrs, :label) || Map.get(attrs, "label")

    Assessment
    |> Ash.ActionInput.for_action(:create_combined, %{course: course, sequence: seq, label: label})
    |> Ash.run_action()
  end

  def fetch_owned_assessment(id, %Workspace{} = ws) do
    case Ash.get(Assessment, id) do
      {:ok, assessment} ->
        case TeacherAssistant.Academics.fetch_owned_teaching_context(
               assessment.teaching_context_id,
               ws
             ) do
          {:ok, _} -> {:ok, assessment}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # --- Marks -----------------------------------------------------------------

  @doc """
  Creates or updates a `Mark` per `(assessment, student)` in a single
  transaction. A `nil` score is valid (records the student absent). Scores are
  range-checked against the assessment's `max_score` before anything is
  written; an out-of-range score persists nothing (`{:error, :out_of_range}`).
  """
  def upsert_marks(%Assessment{id: assessment_id, max_score: max_score}, entries) do
    if Enum.all?(entries, &score_in_range?(&1, max_score)) do
      entries
      |> Enum.map(fn entry ->
        %{
          assessment_id: assessment_id,
          student_id: entry.student_id,
          score: Map.get(entry, :score)
        }
      end)
      |> run_upsert_all()
    else
      {:error, :out_of_range}
    end
  end

  @doc """
  Like `upsert_marks/2`, but atomic across several assessments at once — the
  combined-marks save path. `assessment_entries` is `[{%Assessment{}, [entry]}]`,
  one pair per member class. Every pair's entries are range-checked against
  *their own* assessment's `max_score` BEFORE anything is written, and every
  write happens inside a single transaction, so a combined course's per-class
  saves are all-or-nothing: one class's out-of-range score can never leave
  another class's valid score persisted (no partial commit across classes).
  """
  def upsert_marks_all_or_nothing(assessment_entries) do
    out_of_range? =
      Enum.any?(assessment_entries, fn {%Assessment{max_score: max_score}, entries} ->
        not Enum.all?(entries, &score_in_range?(&1, max_score))
      end)

    if out_of_range? do
      {:error, :out_of_range}
    else
      assessment_entries
      |> Enum.flat_map(fn {%Assessment{id: assessment_id}, entries} ->
        Enum.map(entries, fn entry ->
          %{
            assessment_id: assessment_id,
            student_id: entry.student_id,
            score: Map.get(entry, :score)
          }
        end)
      end)
      |> run_upsert_all()
    end
  end

  def list_marks(%Assessment{id: assessment_id}) do
    Mark
    |> Ash.Query.for_read(:for_assessment, %{assessment_id: assessment_id})
    |> Ash.read!()
  end

  def list_marks_for_context_sequence(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    assessment_ids =
      Assessment
      |> Ash.Query.for_read(:for_context_and_sequence, %{
        teaching_context_id: ctx_id,
        sequence_id: seq_id
      })
      |> Ash.read!()
      |> Enum.map(& &1.id)

    Mark
    |> Ash.Query.for_read(:for_assessments, %{assessment_ids: assessment_ids})
    |> Ash.read!()
  end

  # The `:upsert_all` action does the all-or-nothing transactional upsert and
  # returns `:ok`; unwrap it back to the bare `:ok` the callers expect.
  defp run_upsert_all(marks) do
    Mark
    |> Ash.ActionInput.for_action(:upsert_all, %{marks: marks})
    |> Ash.run_action()
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A mark is valid when absent (nil) or within 0..max_score inclusive. Callers
  # pass a `%Decimal{}` or nil; anything else is left to the resource layer.
  defp score_in_range?(entry, max_score) do
    case Map.get(entry, :score) do
      nil ->
        true

      %Decimal{} = s ->
        Decimal.compare(s, 0) != :lt and Decimal.compare(s, max_score) != :gt

      _ ->
        true
    end
  end
end
