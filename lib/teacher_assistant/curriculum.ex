defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics

  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    CombinedCourse,
    LessonPlan,
    LessonStep,
    ProgressionEntry,
    ProgressionModule,
    ProgressionPlan,
    Subject,
    TeachingContext,
    TeachingLogEntry,
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
      define :create_course_plan, action: :for_course, args: [:course]
      define :list_progression_plans, action: :for_workspace, args: [:workspace_id]
      define :get_progression_plan, action: :read, get_by: [:id]
    end

    resource ProgressionEntry do
      define :list_progression_entries, action: :for_plan, args: [:progression_plan_id]
      define :get_progression_entry, action: :read, get_by: [:id]
    end

    resource ProgressionModule do
      define :list_progression_modules, action: :for_plan, args: [:progression_plan_id]
    end

    resource TeachingLogEntry do
      define :list_logs_for_plan, action: :for_plan, args: [:progression_plan_id]
      define :list_recent_logs, action: :recent, args: [:workspace_id, :limit]
    end

    resource LessonPlan do
      define :update_lesson_plan, action: :update
    end

    resource LessonStep do
      define :list_lesson_steps, action: :for_lesson_plan, args: [:lesson_plan_id]
      define :update_lesson_step, action: :update
      define :delete_lesson_step, action: :destroy
      define :move_lesson_step, action: :move, args: [:direction]
    end
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

  # --- Progression plans -------------------------------------------------

  @doc """
  Owner-scoped single-plan lookup (IDOR guard): `id` must name a plan of
  `ws`. Returns `{:error, :not_found}` (not an Ash error struct) so call
  sites can pattern-match the bare atom as before.
  """
  def fetch_owned_plan(id, %Workspace{id: ws_id}) do
    ProgressionPlan
    |> Ash.Query.for_read(:owned, %{id: id, workspace_id: ws_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  # --- Progression entries ------------------------------------------------

  @doc """
  Owner-scoped single-entry lookup (IDOR guard): `id` must name an entry
  whose plan belongs to `ws`.
  """
  def fetch_owned_entry(id, %Workspace{id: ws_id}) do
    ProgressionEntry
    |> Ash.Query.for_read(:owned, %{id: id, workspace_id: ws_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  The "prepare a lesson" cartouche bundle for a progression entry: the
  entry (with its module loaded), its plan, its teaching context, the
  linked class group (if any), the active academic year, and the class's
  headcount. Owner-scoped end to end — every lookup is workspace-filtered,
  so a foreign entry id resolves to `{:error, :not_found}` (IDOR guard).
  """
  def fetch_owned_entry_with_context(entry_id, %Workspace{} = ws) do
    with {:ok, entry} <- fetch_owned_entry(entry_id, ws),
         {:ok, plan} <- fetch_owned_plan(entry.progression_plan_id, ws),
         {:ok, ctx} <- Academics.fetch_owned_teaching_context(plan.teaching_context_id, ws) do
      entry = Ash.load!(entry, :progression_module)
      class_group = load_owned_class_group(ctx.class_group_id, ws)
      effectif = if class_group, do: length(Enrollment.list_students(class_group)), else: 0

      {:ok,
       %{
         entry: entry,
         plan: plan,
         ctx: ctx,
         class_group: class_group,
         year: TeacherAssistant.Organization.current_academic_year(ws),
         effectif: effectif
       }}
    end
  end

  defp load_owned_class_group(nil, _ws), do: nil

  defp load_owned_class_group(id, ws) do
    case Enrollment.fetch_owned_class_group(id, ws) do
      {:ok, cg} -> cg
      _ -> nil
    end
  end

  # --- Progression modules -------------------------------------------------

  @doc """
  Owner-scoped single-module lookup (IDOR guard): `id` must name a module
  whose plan belongs to `ws`.
  """
  def fetch_owned_module(id, %Workspace{id: ws_id}) do
    ProgressionModule
    |> Ash.Query.for_read(:owned, %{id: id, workspace_id: ws_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  # --- Lesson plans & steps -------------------------------------------------

  @doc """
  The (at most one) `LessonPlan` for a progression entry, or `nil`.
  """
  def get_lesson_plan_for_entry(entry_id) do
    LessonPlan
    |> Ash.Query.for_read(:for_entry, %{progression_entry_id: entry_id})
    |> Ash.read_one!()
  end

  @doc """
  Gets or creates the `LessonPlan` for a progression entry ("préparer" /
  fiche de préparation). Race-safe: if two requests lose to each other on
  the first open, the `unique_entry` identity rejects the second insert and
  this re-fetches the winner rather than erroring or duplicating.
  """
  def ensure_lesson_plan(%ProgressionEntry{} = entry, %TeachingContext{} = _ctx) do
    case get_lesson_plan_for_entry(entry.id) do
      %LessonPlan{} = lp ->
        {:ok, lp}

      nil ->
        case create_lesson_plan_from_entry(entry) do
          {:ok, lp} ->
            {:ok, lp}

          {:error, error} ->
            case get_lesson_plan_for_entry(entry.id) do
              %LessonPlan{} = lp -> {:ok, lp}
              nil -> {:error, error}
            end
        end
    end
  end

  defp create_lesson_plan_from_entry(%ProgressionEntry{} = entry) do
    duration =
      entry.planned_hours
      |> Decimal.mult(60)
      |> Decimal.round(0)
      |> Decimal.to_integer()

    attrs = %{
      progression_entry_id: entry.id,
      titre: entry.lesson_title,
      competence_attendue: entry.competence_visee,
      duration_minutes: duration
    }

    LessonPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
  end

  @doc """
  Appends a new step to a lesson plan at the next free position
  (`max(position) + 1`, or `1` for the first step).
  """
  def add_lesson_step(%LessonPlan{} = lp, attrs \\ %{}) do
    next =
      lp.id
      |> list_lesson_steps!()
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    attrs =
      attrs
      |> Map.put(:lesson_plan_id, lp.id)
      |> Map.put_new(:position, next)

    LessonStep |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
  end

  @doc """
  Owner-scoped single-step lookup (IDOR guard): `id` must name a step of
  `lp`.
  """
  def fetch_owned_lesson_step(id, %LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.for_read(:owned, %{id: id, lesson_plan_id: lp_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end
end
