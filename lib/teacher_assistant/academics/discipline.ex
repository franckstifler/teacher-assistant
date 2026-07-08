defmodule TeacherAssistant.Academics.Discipline do
  @moduledoc "Discipline: sanctions capture and listing (P2.9)."

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.SanctionEntry

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
