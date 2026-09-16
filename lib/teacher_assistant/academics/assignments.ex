defmodule TeacherAssistant.Academics.Assignments do
  @moduledoc """
  Teaching assignments (P2.2): a school-owned TeachingContext with a teacher.
  One teacher per subject per class (partial unique index); assignment requires
  an active school membership.
  """
  require Ash.Query

  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    ProgressionPlan,
    TeachingContext,
    Workspace
  }

  alias TeacherAssistant.Accounts.{Schools, User}

  def assign(%ClassGroup{} = cg, %User{} = teacher, attrs) do
    with :ok <- assignable(cg, teacher) do
      TeachingContext
      |> Ash.Changeset.for_create(:create, %{
        subject: Map.fetch!(attrs, :subject),
        weekly_hours: Map.get(attrs, :weekly_hours, 4),
        coefficient: Map.get(attrs, :coefficient, Decimal.new(1)),
        level: cg.level,
        serie: cg.serie,
        subsystem: cg.subsystem,
        class_group_id: cg.id,
        teacher_user_id: teacher.id,
        workspace_id: cg.workspace_id,
        academic_year_id: cg.academic_year_id
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, tc} ->
          {:ok, tc}

        {:error, error} ->
          if already_assigned?(error), do: {:error, :already_assigned}, else: {:error, error}
      end
    end
  end

  def reassign(%TeachingContext{} = tc, %User{} = teacher) do
    with :ok <- assignable_ws(tc.workspace_id, teacher) do
      tc
      |> Ash.Changeset.for_update(:update, %{teacher_user_id: teacher.id})
      |> Ash.update(authorize?: false)
    end
  end

  def set_coefficient(%TeachingContext{} = tc, value) do
    case parse_coefficient(value) do
      {:ok, dec} ->
        tc
        |> Ash.Changeset.for_update(:update, %{coefficient: dec})
        |> Ash.update(authorize?: false)

      :error ->
        {:error, :invalid_coefficient}
    end
  end

  defp parse_coefficient(%Decimal{} = d), do: if(Decimal.positive?(d), do: {:ok, d}, else: :error)

  defp parse_coefficient(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {dec, ""} -> if Decimal.positive?(dec), do: {:ok, dec}, else: :error
      _ -> :error
    end
  end

  defp parse_coefficient(_), do: :error

  def remove(%TeachingContext{id: id} = tc) do
    has_plans =
      ProgressionPlan
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(authorize?: false) != []

    has_assessments =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(authorize?: false) != []

    if has_plans or has_assessments do
      {:error, :has_data}
    else
      Ash.destroy!(tc, authorize?: false)
      :ok
    end
  end

  def list_for_class(%ClassGroup{id: cg_id}) do
    TeachingContext
    |> Ash.Query.filter(class_group_id == ^cg_id and not is_nil(teacher_user_id))
    |> Ash.Query.load(:teacher)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def list_for_user(%Workspace{id: ws_id}, %AcademicYear{id: year_id}, %User{id: user_id}) do
    TeachingContext
    |> Ash.Query.filter(
      workspace_id == ^ws_id and academic_year_id == ^year_id and teacher_user_id == ^user_id
    )
    |> Ash.Query.load(:class_group)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp assignable(%ClassGroup{workspace_id: ws_id}, teacher), do: assignable_ws(ws_id, teacher)

  defp assignable_ws(ws_id, teacher) do
    case Schools.fetch_school_membership(%Workspace{id: ws_id}, teacher) do
      {:ok, _membership} -> :ok
      {:error, :not_a_member} -> {:error, :not_assignable}
    end
  end

  defp already_assigned?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &already_assigned?/1)
  end

  defp already_assigned?(%Ash.Error.Changes.InvalidAttribute{private_vars: private_vars}) do
    constraint = private_vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, "unique_school_assignment")
  end

  defp already_assigned?(_error), do: false
end
