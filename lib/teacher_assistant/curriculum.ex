defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    ProgressionPlan,
    Subject,
    TeachingContext,
    Workspace
  }

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.User

  resources do
    resource Subject do
      define :deactivate_subject, action: :deactivate
      define :delete_subject, action: :destroy
    end

    resource TeachingContext
    resource TeacherAssistant.Academics.CombinedCourse
    resource ProgressionPlan
    resource TeacherAssistant.Academics.ProgressionEntry
    resource TeacherAssistant.Academics.ProgressionModule
    resource TeacherAssistant.Academics.TeachingLogEntry
    resource TeacherAssistant.Academics.LessonPlan
    resource TeacherAssistant.Academics.LessonStep
  end

  authorization do
    authorize :when_requested
  end

  # --- Subject catalog -------------------------------------------------------

  @doc "The per-school subject catalog (see the 2026-09-17 spec, §1)."
  def list_subjects(%Workspace{id: ws_id}) do
    Subject
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: ws_id})
    |> Ash.read!()
  end

  def create_subject(%Workspace{id: ws_id}, attrs) do
    Subject
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :workspace_id, ws_id))
    |> Ash.create()
    |> case do
      {:ok, s} ->
        {:ok, s}

      {:error, error} ->
        if duplicate_subject_name?(error), do: {:error, :duplicate_name}, else: {:error, error}
    end
  end

  def update_subject(%Subject{} = s, attrs) do
    s
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update()
    |> case do
      {:ok, s} ->
        {:ok, s}

      {:error, error} ->
        if duplicate_subject_name?(error), do: {:error, :duplicate_name}, else: {:error, error}
    end
  end

  defp duplicate_subject_name?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: pvars} ->
        constraint = Keyword.get(pvars, :constraint)
        is_binary(constraint) and String.contains?(constraint, "unique_subject_name")

      _ ->
        false
    end)
  end

  defp duplicate_subject_name?(_), do: false

  # --- Teaching-context assignments ------------------------------------------

  @doc """
  Teaching assignments (P2.2): a school-owned TeachingContext with a teacher.
  One teacher per subject per class (partial unique index); assignment requires
  an active school membership.
  """
  def assign_teacher(%ClassGroup{} = cg, %User{} = teacher, attrs) do
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
      |> Ash.create()
      |> case do
        {:ok, tc} ->
          {:ok, tc}

        {:error, error} ->
          if already_assigned?(error), do: {:error, :already_assigned}, else: {:error, error}
      end
    end
  end

  def reassign_teacher(%TeachingContext{} = tc, %User{} = teacher) do
    with :ok <- assignable_ws(tc.workspace_id, teacher) do
      tc
      |> Ash.Changeset.for_update(:update, %{teacher_user_id: teacher.id})
      |> Ash.update()
    end
  end

  def set_assignment_coefficient(%TeachingContext{} = tc, value) do
    case parse_coefficient(value) do
      {:ok, dec} ->
        tc
        |> Ash.Changeset.for_update(:update, %{coefficient: dec})
        |> Ash.update()

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

  def remove_assignment(%TeachingContext{id: id} = tc) do
    has_plans =
      ProgressionPlan
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!() != []

    has_assessments =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!() != []

    if has_plans or has_assessments do
      {:error, :has_data}
    else
      Ash.destroy!(tc)
      :ok
    end
  end

  def list_assignments_for_class(%ClassGroup{id: cg_id}) do
    TeachingContext
    |> Ash.Query.for_read(:for_class_group, %{class_group_id: cg_id})
    |> Ash.read!()
  end

  @doc """
  Sibling `TeachingContext`s eligible to be combined with `ctx` via
  `Courses.combine/1`: same workspace, academic year, subject and teacher,
  attached to a (different) class, and not already part of a combined
  course. Used to populate the "teach together" picker.
  """
  def combinable_siblings(%TeachingContext{} = ctx) do
    TeachingContext
    |> Ash.Query.for_read(:combinable_siblings, %{
      workspace_id: ctx.workspace_id,
      academic_year_id: ctx.academic_year_id,
      subject: ctx.subject,
      teacher_user_id: ctx.teacher_user_id,
      exclude_id: ctx.id
    })
    |> Ash.read!()
  end

  def list_assignments_for_user(%Workspace{id: ws_id}, %AcademicYear{id: year_id}, %User{
        id: user_id
      }) do
    TeachingContext
    |> Ash.Query.for_read(:for_workspace_year_teacher, %{
      workspace_id: ws_id,
      academic_year_id: year_id,
      teacher_user_id: user_id
    })
    |> Ash.read!()
  end

  defp assignable(%ClassGroup{workspace_id: ws_id}, teacher), do: assignable_ws(ws_id, teacher)

  defp assignable_ws(ws_id, teacher) do
    case Accounts.fetch_school_membership(%Workspace{id: ws_id}, teacher) do
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
