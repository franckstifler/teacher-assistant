defmodule TeacherAssistant.Discipline do
  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.ConductMark
  # `TeacherAssistant.Academics.Enrollment` is the resource struct (used for
  # the `enrollment_id/1` pattern match below); the domain
  # `TeacherAssistant.Enrollment` is always referenced fully qualified so the
  # two never collide under one bare `Enrollment` alias.
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.SanctionEntry
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Organization

  resources do
    resource SanctionEntry do
      define :list_sanctions_for_class_in_range,
        action: :for_class_in_range,
        args: [:class_group_id, :first, :last]

      define :list_sanctions_for_enrollment_in_range,
        action: :for_enrollment_in_range,
        args: [:enrollment_id, :first, :last]

      define :delete_sanction, action: :destroy
    end

    resource ConductMark do
      define :conduct_mark_for_enrollment_sequence,
        action: :for_enrollment_sequence,
        args: [:enrollment_id, :sequence_id]

      define :conduct_marks_for_enrollment_sequences,
        action: :for_enrollment_sequences,
        args: [:enrollment_id, :sequence_ids]

      define :conduct_marks_for_enrollments_sequences,
        action: :for_enrollments_sequences,
        args: [:enrollment_ids, :sequence_ids]
    end
  end

  authorization do
    authorize :when_requested
  end

  @valid_types MapSet.new([
                 :avertissement,
                 :blame,
                 :exclusion_temporaire,
                 :exclusion_definitive,
                 :consigne
               ])

  @doc """
  Lists `SanctionEntry`s for `class_group` (or a single `enrollment`) whose
  `date` is within `period_tuple`'s inclusive date range (see
  `Organization.period_date_range/1`), newest first, with the enrollment's
  student loaded. Returns `[]` when the range is `nil`.
  """
  def list_sanctions(%ClassGroup{id: cg_id}, period_tuple) do
    case Organization.period_date_range(period_tuple) do
      nil -> []
      {first, last} -> list_sanctions_for_class_in_range!(cg_id, first, last)
    end
  end

  def list_sanctions(enrollment, period_tuple) do
    id = enrollment_id(enrollment)

    case Organization.period_date_range(period_tuple) do
      nil -> []
      {first, last} -> list_sanctions_for_enrollment_in_range!(id, first, last)
    end
  end

  @doc """
  Records a sanction for `enrollment` (struct or bare id). `attrs` carries
  `type` (atom), `date`, optional `reason`, optional `duration_days`.
  Rejects an invalid `type` with `{:error, :invalid_type}`. `duration_days`
  is persisted only for `:exclusion_temporaire`, forced to `nil` otherwise.
  """
  def add_sanction(enrollment, attrs, issued_by_user_id) do
    type = attrs[:type] || attrs["type"]

    with :ok <- validate_type(type),
         {:ok, %Enrollment{} = e} <- fetch_enrollment(enrollment) do
      duration_days =
        if type == :exclusion_temporaire, do: attrs[:duration_days] || attrs["duration_days"]

      SanctionEntry
      |> Ash.Changeset.for_create(:create, %{
        type: type,
        date: attrs[:date] || attrs["date"],
        reason: attrs[:reason] || attrs["reason"],
        duration_days: duration_days,
        issued_by_user_id: issued_by_user_id,
        workspace_id: e.workspace_id,
        enrollment_id: e.id
      })
      |> Ash.create()
      |> case do
        {:ok, sanction} -> {:ok, sanction}
        {:error, _error} -> {:error, :sanction_failed}
      end
    end
  end

  defp validate_type(type) do
    if MapSet.member?(@valid_types, type), do: :ok, else: {:error, :invalid_type}
  end

  @doc """
  Upserts the conduct mark ("note de conduite") for `enrollment` on `sequence`
  to `value` (0..20), recorded by `recorded_by_user_id`. Rejects an
  out-of-bounds value with `{:error, :invalid_value}`.
  """
  def set_conduct_mark(enrollment, %Sequence{} = sequence, value, recorded_by_user_id) do
    with {:ok, decimal_value} <- to_bounded_decimal(value),
         {:ok, %Enrollment{} = e} <- fetch_enrollment(enrollment) do
      ConductMark
      |> Ash.Changeset.for_create(:set, %{
        value: decimal_value,
        recorded_by_user_id: recorded_by_user_id,
        workspace_id: e.workspace_id,
        enrollment_id: e.id,
        sequence_id: sequence.id
      })
      |> Ash.create()
      |> case do
        {:ok, mark} -> {:ok, mark}
        {:error, _error} -> {:error, :conduct_mark_failed}
      end
    end
  end

  defp to_bounded_decimal(value) do
    decimal = Decimal.new(value)

    if Decimal.compare(decimal, Decimal.new(0)) != :lt and
         Decimal.compare(decimal, Decimal.new(20)) != :gt do
      {:ok, decimal}
    else
      {:error, :invalid_value}
    end
  rescue
    _ -> {:error, :invalid_value}
  end

  @doc "Deletes the conduct mark for `enrollment` on `sequence`, if any."
  def clear_conduct_mark(enrollment, %Sequence{id: sequence_id} = _sequence) do
    id = enrollment_id(enrollment)
    marks = conduct_mark_for_enrollment_sequence!(id, sequence_id)

    try do
      Enum.each(marks, &Ash.destroy!/1)
      {:ok, length(marks)}
    rescue
      _ -> {:error, :conduct_mark_failed}
    end
  end

  @doc """
  Returns the "note de conduite" for `enrollment` over `period_tuple`:
  the séquence's mark value, or the mean of present séquence marks for a
  trimester/year. Never a raw sum — mean of present values only, skipping
  missing séquences. `nil` when none present.
  """
  def note_de_conduite(enrollment, {:sequence, %Sequence{} = sequence}) do
    id = enrollment_id(enrollment)

    case conduct_mark_for_enrollment_sequence!(id, sequence.id) do
      [mark | _] -> mark.value
      [] -> nil
    end
  end

  def note_de_conduite(enrollment, {:trimester, %Term{} = term}) do
    mean_conduct_marks(enrollment, resolve_term_sequences(term))
  end

  def note_de_conduite(enrollment, {:annual, %AcademicYear{} = year}) do
    mean_conduct_marks(enrollment, Organization.list_sequences(year))
  end

  defp mean_conduct_marks(enrollment, sequences) do
    id = enrollment_id(enrollment)
    sequence_ids = Enum.map(sequences, & &1.id)

    id
    |> conduct_marks_for_enrollment_sequences!(sequence_ids)
    |> Enum.map(& &1.value)
    |> mean_of_values()
  end

  # Resolves a `Term`'s séquences, re-fetching (with them loaded) if needed.
  defp resolve_term_sequences(%Term{sequences: %Ash.NotLoaded{}} = term) do
    %AcademicYear{id: term.academic_year_id, workspace_id: term.workspace_id}
    |> Organization.list_terms()
    |> Enum.find(&(&1.id == term.id))
    |> then(fn t -> if t, do: t.sequences, else: [] end)
  end

  defp resolve_term_sequences(%Term{sequences: sequences}), do: sequences

  # Shared averaging rule: mean of present values only, never a raw sum.
  # `nil` when the list is empty. Used by both the single-student
  # `note_de_conduite/2` path and the batched `class_discipline/2` path so
  # the two never drift.
  defp mean_of_values([]), do: nil

  defp mean_of_values(values) do
    Decimal.div(
      Enum.reduce(values, Decimal.new(0), &Decimal.add/2),
      Decimal.new(length(values))
    )
  end

  # Séquence ids covered by `period_tuple`, computed once for the whole
  # roster (avoids a per-student `list_terms`/`list_sequences` re-fetch).
  defp period_sequence_ids({:sequence, %Sequence{id: id}}), do: [id]

  defp period_sequence_ids({:trimester, %Term{} = term}) do
    term |> resolve_term_sequences() |> Enum.map(& &1.id)
  end

  defp period_sequence_ids({:annual, %AcademicYear{} = year}) do
    year |> Organization.list_sequences() |> Enum.map(& &1.id)
  end

  @doc """
  Returns `%{sanctions:, consignes_count:, note_de_conduite:}` for `enrollment`
  over `period_tuple`: `sanctions` is the in-range non-consigne ladder
  (newest first), `consignes_count` counts in-range `:consigne` entries.
  """
  def discipline_summary(enrollment, period_tuple) do
    entries = list_sanctions(enrollment, period_tuple)
    {consignes, sanctions} = Enum.split_with(entries, &(&1.type == :consigne))

    %{
      sanctions: sanctions,
      consignes_count: length(consignes),
      note_de_conduite: note_de_conduite(enrollment, period_tuple)
    }
  end

  @doc """
  Returns `%{enrollment_id => discipline_summary}` for the whole roster of
  `class_group` over `period_tuple`, batching reads to avoid N+1. Entry-less
  enrollments get `%{sanctions: [], consignes_count: 0, note_de_conduite: nil}`.
  """
  def class_discipline(%ClassGroup{} = class_group, period_tuple) do
    roster = TeacherAssistant.Enrollment.list_roster(class_group)
    enrollment_ids = Enum.map(roster, & &1.enrollment.id)

    entries_by_enrollment =
      class_group
      |> list_sanctions(period_tuple)
      |> Enum.group_by(& &1.enrollment_id)

    conduct_values_by_enrollment =
      period_tuple
      |> period_sequence_ids()
      |> batch_conduct_values(enrollment_ids)

    Map.new(roster, fn %{enrollment: enrollment} ->
      entries = Map.get(entries_by_enrollment, enrollment.id, [])
      {consignes, sanctions} = Enum.split_with(entries, &(&1.type == :consigne))

      values = Map.get(conduct_values_by_enrollment, enrollment.id, [])

      summary = %{
        sanctions: sanctions,
        consignes_count: length(consignes),
        note_de_conduite: mean_of_values(values)
      }

      {enrollment.id, summary}
    end)
  end

  # Single batched read of ConductMark for the whole roster, scoped to the
  # période's séquence ids. Returns %{enrollment_id => [value, ...]}.
  defp batch_conduct_values([], _enrollment_ids), do: %{}
  defp batch_conduct_values(_sequence_ids, []), do: %{}

  defp batch_conduct_values(sequence_ids, enrollment_ids) do
    enrollment_ids
    |> conduct_marks_for_enrollments_sequences!(sequence_ids)
    |> Enum.group_by(& &1.enrollment_id, & &1.value)
  end

  defp enrollment_id(%Enrollment{id: id}), do: id
  defp enrollment_id(id) when is_binary(id), do: id

  defp fetch_enrollment(%Enrollment{} = e), do: {:ok, e}

  defp fetch_enrollment(id) when is_binary(id) do
    case Ash.get(Enrollment, id) do
      {:ok, e} -> {:ok, e}
      {:error, _error} -> {:error, :not_found}
    end
  end
end
