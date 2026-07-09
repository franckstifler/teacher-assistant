defmodule TeacherAssistant.Academics.Discipline do
  @moduledoc "Discipline: sanctions capture and listing (P2.9)."

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.ConductMark
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.SanctionEntry
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Academics.AcademicYear

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
  `Academics.period_date_range/1`), newest first, with the enrollment's
  student loaded. Returns `[]` when the range is `nil`.
  """
  def list_sanctions(%ClassGroup{id: cg_id}, period_tuple) do
    case Academics.period_date_range(period_tuple) do
      nil ->
        []

      {first, last} ->
        SanctionEntry
        |> Ash.Query.filter(
          enrollment.class_group_id == ^cg_id and date >= ^first and date <= ^last
        )
        |> Ash.Query.load(enrollment: :student)
        |> Ash.Query.sort(date: :desc)
        |> Ash.read!(authorize?: false)
    end
  end

  def list_sanctions(enrollment, period_tuple) do
    id = enrollment_id(enrollment)

    case Academics.period_date_range(period_tuple) do
      nil ->
        []

      {first, last} ->
        SanctionEntry
        |> Ash.Query.filter(enrollment_id == ^id and date >= ^first and date <= ^last)
        |> Ash.Query.load(enrollment: :student)
        |> Ash.Query.sort(date: :desc)
        |> Ash.read!(authorize?: false)
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
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, sanction} -> {:ok, sanction}
        {:error, _error} -> {:error, :sanction_failed}
      end
    end
  end

  defp validate_type(type) do
    if MapSet.member?(@valid_types, type), do: :ok, else: {:error, :invalid_type}
  end

  @doc "Deletes `sanction`."
  def delete_sanction(%SanctionEntry{} = sanction) do
    case Ash.destroy(sanction, authorize?: false) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _error} -> {:error, :delete_failed}
    end
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
      |> Ash.create(authorize?: false)
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

    ConductMark
    |> Ash.Query.filter(enrollment_id == ^id and sequence_id == ^sequence_id)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, marks} ->
        Enum.each(marks, &Ash.destroy!(&1, authorize?: false))
        {:ok, length(marks)}

      {:error, _error} ->
        {:error, :conduct_mark_failed}
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

    ConductMark
    |> Ash.Query.filter(enrollment_id == ^id and sequence_id == ^sequence.id)
    |> Ash.read!(authorize?: false)
    |> case do
      [mark] -> mark.value
      [] -> nil
    end
  end

  def note_de_conduite(enrollment, {:trimester, %Term{} = term}) do
    sequences =
      case term.sequences do
        %Ash.NotLoaded{} ->
          Academics.list_terms(%AcademicYear{id: term.academic_year_id})
          |> Enum.find(&(&1.id == term.id))
          |> then(fn t -> if t, do: t.sequences, else: [] end)

        sequences ->
          sequences
      end

    mean_conduct_marks(enrollment, sequences)
  end

  def note_de_conduite(enrollment, {:annual, %AcademicYear{} = year}) do
    mean_conduct_marks(enrollment, Academics.list_sequences(year))
  end

  defp mean_conduct_marks(enrollment, sequences) do
    id = enrollment_id(enrollment)
    sequence_ids = Enum.map(sequences, & &1.id)

    values =
      ConductMark
      |> Ash.Query.filter(enrollment_id == ^id and sequence_id in ^sequence_ids)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.value)

    case values do
      [] ->
        nil

      _ ->
        Decimal.div(
          Enum.reduce(values, Decimal.new(0), &Decimal.add/2),
          Decimal.new(length(values))
        )
    end
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
    roster = Academics.list_roster(class_group)

    entries_by_enrollment =
      class_group
      |> list_sanctions(period_tuple)
      |> Enum.group_by(& &1.enrollment_id)

    Map.new(roster, fn %{enrollment: enrollment} ->
      entries = Map.get(entries_by_enrollment, enrollment.id, [])
      {consignes, sanctions} = Enum.split_with(entries, &(&1.type == :consigne))

      summary = %{
        sanctions: sanctions,
        consignes_count: length(consignes),
        note_de_conduite: note_de_conduite(enrollment, period_tuple)
      }

      {enrollment.id, summary}
    end)
  end

  defp enrollment_id(%Enrollment{id: id}), do: id
  defp enrollment_id(id) when is_binary(id), do: id

  defp fetch_enrollment(%Enrollment{} = e), do: {:ok, e}

  defp fetch_enrollment(id) when is_binary(id) do
    case Ash.get(Enrollment, id, authorize?: false) do
      {:ok, e} -> {:ok, e}
      {:error, _error} -> {:error, :not_found}
    end
  end
end
