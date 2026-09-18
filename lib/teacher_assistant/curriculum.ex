defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics

  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    CombinedCourse,
    ProgressionPlan,
    Subject,
    TeachingContext,
    Workspace
  }

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment

  resources do
    resource Subject do
      define :deactivate_subject, action: :deactivate
      define :delete_subject, action: :destroy
    end

    resource TeachingContext do
      define :contexts_of_course, action: :for_combined_course, args: [:combined_course_id]
    end

    resource CombinedCourse do
      define :get_course, action: :read, get_by: [:id]
    end

    resource ProgressionPlan do
      define :unit_plans, action: :unit_plans, args: [:workspace_id]
    end

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
  `combine_course/1`: same workspace, academic year, subject and teacher,
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

  # --- Combined courses & teaching units -------------------------------------

  @doc """
  Combines two or more `TeachingContext`s into a fresh `CombinedCourse`.

  All contexts must share the same `teacher_user_id` and `subject`, and none
  may already belong to a course. The transactional create/stamp/plan work runs
  in `CombinedCourse`'s `:combine` action; the validations here return the bare
  error atoms (`:need_two`, `:teacher_mismatch`, `:subject_mismatch`,
  `:already_combined`) that call sites match on.
  """
  def combine_course(contexts) when is_list(contexts) do
    with :ok <- validate_count(contexts),
         :ok <- validate_same_teacher(contexts),
         :ok <- validate_same_subject(contexts),
         :ok <- validate_not_already_combined(contexts) do
      CombinedCourse
      |> Ash.ActionInput.for_action(:combine, %{contexts: contexts})
      |> Ash.run_action()
    end
  end

  defp validate_count(contexts) when length(contexts) >= 2, do: :ok
  defp validate_count(_contexts), do: {:error, :need_two}

  defp validate_same_teacher(contexts) do
    contexts
    |> Enum.map(& &1.teacher_user_id)
    |> Enum.uniq()
    |> case do
      [_single] -> :ok
      _ -> {:error, :teacher_mismatch}
    end
  end

  defp validate_same_subject(contexts) do
    contexts
    |> Enum.map(& &1.subject)
    |> Enum.uniq()
    |> case do
      [_single] -> :ok
      _ -> {:error, :subject_mismatch}
    end
  end

  defp validate_not_already_combined(contexts) do
    if Enum.any?(contexts, & &1.combined_course_id) do
      {:error, :already_combined}
    else
      :ok
    end
  end

  @doc """
  Splits a `CombinedCourse` apart via its `:split` action: unlinks every member
  context, destroys the course's shared `ProgressionPlan`, then destroys the
  course. Always returns `:ok`.
  """
  def split_course(%CombinedCourse{} = course) do
    CombinedCourse
    |> Ash.ActionInput.for_action(:split, %{course: course})
    |> Ash.run_action!()

    :ok
  end

  @doc """
  Lists the teaching units assigned to `user` in `ws`/`year`: each is either
  `{:solo, %TeachingContext{}}` or `{:course, %CombinedCourse{}}` — contexts
  sharing a `combined_course_id` collapse into a single course entry (once per
  course), everything else stays solo.
  """
  def list_units_for_user(%Workspace{} = ws, %AcademicYear{} = year, %User{} = user) do
    contexts = list_assignments_for_user(ws, year, user)

    {units, _seen} =
      Enum.reduce(contexts, {[], MapSet.new()}, fn ctx, {units, seen} ->
        case ctx.combined_course_id do
          nil ->
            {[{:solo, ctx} | units], seen}

          course_id ->
            if MapSet.member?(seen, course_id) do
              {units, seen}
            else
              {:ok, course} = get_course(course_id)
              {[{:course, course} | units], MapSet.put(seen, course_id)}
            end
        end
      end)

    Enum.reverse(units)
  end

  @doc """
  Scope-aware teaching-*unit* listing for the class switcher: contexts
  belonging to the same combined course collapse into a single
  `{:course, %CombinedCourse{}}` entry (via `list_units_for_user/3`);
  everything else stays `{:solo, %TeachingContext{}}`. Returns `[]` when there
  is no current academic year.
  """
  def list_units_for_scope(%TeacherAssistant.Scope{
        current_workspace: ws,
        current_academic_year: year,
        current_workspace_type: type,
        current_user: user
      }) do
    cond do
      is_nil(ws) or is_nil(year) -> []
      type == :school -> list_units_for_user(ws, year, user)
      true -> Enum.map(Academics.list_teaching_contexts(ws, year), &{:solo, &1})
    end
  end

  @doc """
  The union roster of a `CombinedCourse`: every student of every member class,
  grouped by class (each group carries its own `class_group` and
  `teaching_context`, so a mark can always be routed back to the right context).
  Marks stay per-student, per-context — this is purely a read shape for the
  combined marks page; it never merges rosters across classes into one flat
  list. Skips a member context with no `class_group` yet.
  """
  def list_union_students(%CombinedCourse{id: id}) do
    id
    |> contexts_of_course!()
    |> Ash.load!(:class_group)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.map(fn ctx ->
      %{
        teaching_context: ctx,
        class_group: ctx.class_group,
        students: Enrollment.list_students(ctx.class_group)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.class_group.label))
  end
end
