defmodule TeacherAssistant.Curriculum do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

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
    Sequence,
    Subject,
    TeachingContext,
    TeachingLogEntry
  }

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Scope

  resources do
    resource Subject do
      define :deactivate_subject, action: :deactivate
      define :delete_subject, action: :destroy
    end

    resource TeachingContext do
      define :contexts_of_course, action: :for_combined_course, args: [:combined_course_id]
    end

    resource CombinedCourse

    resource ProgressionPlan do
      define :unit_plans, action: :unit_plans
      define :create_course_plan, action: :for_course, args: [:course]
      define :list_progression_plans, action: :for_workspace
    end

    resource ProgressionEntry do
      define :list_progression_entries, action: :for_plan, args: [:progression_plan_id]
    end

    resource ProgressionModule do
      define :list_progression_modules, action: :for_plan, args: [:progression_plan_id]
    end

    resource TeachingLogEntry do
      define :list_logs_for_plan, action: :for_plan, args: [:progression_plan_id]
      define :list_recent_logs, action: :recent, args: [:limit]
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

  # Every one of `get_teaching_context/2`, `get_course/2`,
  # `get_progression_plan/2` and `get_progression_entry/2` takes the scope
  # first and the id second, so a caller holding the scope never needs to
  # fetch the workspace separately.

  # --- Subject catalog -------------------------------------------------------

  @doc "The per-school subject catalog (see the 2026-09-17 spec, §1)."
  def list_subjects(%Scope{} = scope) do
    Subject
    |> Ash.Query.for_read(:for_workspace, %{}, scope: scope)
    |> Ash.read!()
  end

  def create_subject(%Scope{} = scope, attrs) do
    Subject
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
    |> case do
      {:ok, s} ->
        {:ok, s}

      {:error, error} ->
        if duplicate_subject_name?(error), do: {:error, :duplicate_name}, else: {:error, error}
    end
  end

  def update_subject(%Scope{} = scope, %Subject{} = s, attrs) do
    s
    |> Ash.Changeset.for_update(:update, attrs, scope: scope)
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
  def assign_teacher(%Scope{} = scope, %ClassGroup{} = cg, %User{} = teacher, attrs) do
    with :ok <- assignable(scope, teacher) do
      TeachingContext
      |> Ash.Changeset.for_create(
        :create,
        %{
          subject: Map.fetch!(attrs, :subject),
          weekly_hours: Map.get(attrs, :weekly_hours, 4),
          coefficient: Map.get(attrs, :coefficient, Decimal.new(1)),
          level: cg.level,
          serie: cg.serie,
          subsystem: cg.subsystem,
          class_group_id: cg.id,
          teacher_user_id: teacher.id,
          academic_year_id: cg.academic_year_id
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, tc} ->
          {:ok, tc}

        {:error, error} ->
          if already_assigned?(error), do: {:error, :already_assigned}, else: {:error, error}
      end
    end
  end

  def reassign_teacher(%Scope{} = scope, %TeachingContext{} = tc, %User{} = teacher) do
    with :ok <- assignable(scope, teacher) do
      tc
      |> Ash.Changeset.for_update(:update, %{teacher_user_id: teacher.id}, scope: scope)
      |> Ash.update()
    end
  end

  def set_assignment_coefficient(%Scope{} = scope, %TeachingContext{} = tc, value) do
    case parse_coefficient(value) do
      {:ok, dec} ->
        tc
        |> Ash.Changeset.for_update(:update, %{coefficient: dec}, scope: scope)
        |> Ash.update()

      :error ->
        {:error, :invalid_coefficient}
    end
  end

  @doc """
  Canonical coefficient parser: accepts a positive `%Decimal{}` or a string that
  parses cleanly to a positive decimal, returning `{:ok, decimal}` or `:error`.
  Shared with the school settings LiveView so the two never drift.
  """
  def parse_coefficient(%Decimal{} = d), do: if(Decimal.positive?(d), do: {:ok, d}, else: :error)

  def parse_coefficient(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {dec, ""} -> if Decimal.positive?(dec), do: {:ok, dec}, else: :error
      _ -> :error
    end
  end

  def parse_coefficient(_), do: :error

  def remove_assignment(%Scope{} = scope, %TeachingContext{id: id} = tc) do
    has_plans =
      ProgressionPlan
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(scope: scope) != []

    has_assessments =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^id)
      |> Ash.read!(scope: scope) != []

    if has_plans or has_assessments do
      {:error, :has_data}
    else
      Ash.destroy!(tc, scope: scope)
      :ok
    end
  end

  def list_assignments_for_class(%Scope{} = scope, %ClassGroup{id: cg_id}) do
    TeachingContext
    |> Ash.Query.for_read(:for_class_group, %{class_group_id: cg_id}, scope: scope)
    |> Ash.read!()
  end

  @doc """
  Sibling `TeachingContext`s eligible to be combined with `ctx` via
  `combine_course/2`: same workspace, academic year, subject and teacher,
  attached to a (different) class, and not already part of a combined
  course. Used to populate the "teach together" picker.
  """
  def combinable_siblings(%Scope{} = scope, %TeachingContext{} = ctx) do
    TeachingContext
    |> Ash.Query.for_read(
      :combinable_siblings,
      %{
        academic_year_id: ctx.academic_year_id,
        subject: ctx.subject,
        teacher_user_id: ctx.teacher_user_id,
        exclude_id: ctx.id
      },
      scope: scope
    )
    # `TeachingContext` is multitenant, and this read's `prepare` also loads
    # the (multitenant) `:class_group` relationship — Ash propagates the
    # query's scope to the load.
    |> Ash.read!()
  end

  def list_assignments_for_user(
        %Scope{} = scope,
        %AcademicYear{id: year_id},
        %User{id: user_id}
      ) do
    TeachingContext
    |> Ash.Query.for_read(
      :for_workspace_year_teacher,
      %{
        academic_year_id: year_id,
        teacher_user_id: user_id
      },
      scope: scope
    )
    # See the comment in `combinable_siblings/2`: this read loads `:class_group`.
    |> Ash.read!()
  end

  defp assignable(%Scope{} = scope, %User{} = teacher) do
    case Accounts.fetch_school_membership(scope, teacher) do
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
  def combine_course(%Scope{} = scope, contexts) when is_list(contexts) do
    with :ok <- validate_count(contexts),
         :ok <- validate_same_teacher(contexts),
         :ok <- validate_same_subject(contexts),
         :ok <- validate_not_already_combined(contexts) do
      CombinedCourse
      |> Ash.ActionInput.for_action(:combine, %{contexts: contexts}, scope: scope)
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
  def split_course(%Scope{} = scope, %CombinedCourse{} = course) do
    CombinedCourse
    |> Ash.ActionInput.for_action(:split, %{course: course}, scope: scope)
    |> Ash.run_action!()

    :ok
  end

  @doc """
  Fetches a `CombinedCourse` by id, scoped to the scope's school.
  Replaces the old unscoped `get_by: [:id]` code interface.
  """
  def get_course(%Scope{} = scope, id), do: Ash.get(CombinedCourse, id, scope: scope)

  @doc """
  Lists the teaching units assigned to `user` in the scope's school/`year`:
  each is either `{:solo, %TeachingContext{}}` or `{:course, %CombinedCourse{}}` —
  contexts sharing a `combined_course_id` collapse into a single course entry
  (once per course), everything else stays solo.
  """
  def list_units_for_user(%Scope{} = scope, %AcademicYear{} = year, %User{} = user) do
    contexts = list_assignments_for_user(scope, year, user)

    {units, _seen} =
      Enum.reduce(contexts, {[], MapSet.new()}, fn ctx, {units, seen} ->
        case ctx.combined_course_id do
          nil ->
            {[{:solo, ctx} | units], seen}

          course_id ->
            if MapSet.member?(seen, course_id) do
              {units, seen}
            else
              {:ok, course} = get_course(scope, course_id)
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
  def list_units_for_scope(
        %TeacherAssistant.Scope{
          current_workspace: ws,
          current_academic_year: year,
          current_user: user
        } = scope
      ) do
    cond do
      is_nil(ws) or is_nil(year) -> []
      true -> list_units_for_user(scope, year, user)
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
  def list_union_students(%Scope{} = scope, %CombinedCourse{id: id}) do
    id
    |> contexts_of_course!(scope: scope)
    # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
    |> Ash.load!(:class_group, scope: scope)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.map(fn ctx ->
      %{
        teaching_context: ctx,
        class_group: ctx.class_group,
        students: Enrollment.list_students(scope, ctx.class_group)
      }
    end)
    |> Enum.sort_by(&String.downcase(&1.class_group.label))
  end

  # --- Progression plans -------------------------------------------------

  @doc """
  Owner-scoped single-plan lookup (IDOR guard): `id` must name a plan of
  the scope's school. Returns `{:error, :not_found}` (not an Ash error struct)
  so call sites can pattern-match the bare atom as before.
  """
  def fetch_owned_plan(%Scope{} = scope, id) do
    ProgressionPlan
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Fetches a `ProgressionPlan` by id, scoped to the scope's school.
  Replaces the old unscoped `get_by: [:id]` code interface.
  """
  def get_progression_plan(%Scope{} = scope, id),
    do: Ash.get(ProgressionPlan, id, scope: scope)

  # --- Progression entries ------------------------------------------------

  @doc """
  Owner-scoped single-entry lookup (IDOR guard): `id` must name an entry
  whose plan belongs to the scope's school.
  """
  def fetch_owned_entry(%Scope{} = scope, id) do
    ProgressionEntry
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Fetches a `ProgressionEntry` by id, scoped to the scope's school.
  Replaces the old unscoped `get_by: [:id]` code interface.
  """
  def get_progression_entry(%Scope{} = scope, id),
    do: Ash.get(ProgressionEntry, id, scope: scope)

  @doc """
  The "prepare a lesson" cartouche bundle for a progression entry: the
  entry (with its module loaded), its plan, its teaching context, the
  linked class group (if any), the active academic year, and the class's
  headcount. Owner-scoped end to end — every lookup is workspace-filtered,
  so a foreign entry id resolves to `{:error, :not_found}` (IDOR guard).
  """
  def fetch_owned_entry_with_context(%Scope{} = scope, entry_id) do
    with {:ok, entry} <- fetch_owned_entry(scope, entry_id),
         {:ok, plan} <- fetch_owned_plan(scope, entry.progression_plan_id),
         {:ok, ctx} <- fetch_owned_teaching_context(scope, plan.teaching_context_id) do
      # `:progression_module` is also multitenant — pass the scope to the load.
      entry = Ash.load!(entry, :progression_module, scope: scope)
      class_group = load_owned_class_group(ctx.class_group_id, scope)
      effectif = if class_group, do: length(Enrollment.list_students(scope, class_group)), else: 0

      {:ok,
       %{
         entry: entry,
         plan: plan,
         ctx: ctx,
         class_group: class_group,
         year: TeacherAssistant.Organization.current_academic_year(scope),
         effectif: effectif
       }}
    end
  end

  defp load_owned_class_group(nil, _scope), do: nil

  defp load_owned_class_group(id, %Scope{} = scope) do
    case Enrollment.fetch_owned_class_group(scope, id) do
      {:ok, cg} -> cg
      _ -> nil
    end
  end

  # --- Progression modules -------------------------------------------------

  @doc """
  Owner-scoped single-module lookup (IDOR guard): `id` must name a module
  whose plan belongs to the scope's school.
  """
  def fetch_owned_module(%Scope{} = scope, id) do
    ProgressionModule
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
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
  def get_lesson_plan_for_entry(%Scope{} = scope, entry_id) do
    LessonPlan
    |> Ash.Query.for_read(:for_entry, %{progression_entry_id: entry_id}, scope: scope)
    |> Ash.read_one!()
  end

  @doc """
  Gets or creates the `LessonPlan` for a progression entry ("préparer" /
  fiche de préparation). Race-safe: if two requests lose to each other on
  the first open, the `unique_entry` identity rejects the second insert and
  this re-fetches the winner rather than erroring or duplicating.
  """
  def ensure_lesson_plan(%Scope{} = scope, %ProgressionEntry{} = entry, %TeachingContext{}) do
    case get_lesson_plan_for_entry(scope, entry.id) do
      %LessonPlan{} = lp ->
        {:ok, lp}

      nil ->
        case create_lesson_plan_from_entry(scope, entry) do
          {:ok, lp} ->
            {:ok, lp}

          {:error, error} ->
            case get_lesson_plan_for_entry(scope, entry.id) do
              %LessonPlan{} = lp -> {:ok, lp}
              nil -> {:error, error}
            end
        end
    end
  end

  defp create_lesson_plan_from_entry(%Scope{} = scope, %ProgressionEntry{} = entry) do
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

    LessonPlan
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
  end

  @doc """
  Appends a new step to a lesson plan at the next free position
  (`max(position) + 1`, or `1` for the first step).
  """
  def add_lesson_step(%Scope{} = scope, %LessonPlan{} = lp, attrs \\ %{}) do
    next =
      lp.id
      |> list_lesson_steps!(scope: scope)
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    attrs =
      attrs
      |> Map.put(:lesson_plan_id, lp.id)
      |> Map.put_new(:position, next)

    LessonStep
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
  end

  @doc """
  Owner-scoped single-step lookup (IDOR guard): `id` must name a step of
  `lp`.
  """
  def fetch_owned_lesson_step(%Scope{} = scope, id, %LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.for_read(:owned, %{id: id, lesson_plan_id: lp_id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  # --- Teaching contexts ----------------------------------------------------

  def fetch_owned_teaching_context(%Scope{} = scope, id) do
    TeachingContext
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Fetches a teaching context the scope's user may open in the teacher workspace.

  The workspace is shared by all staff, so the user must be the *assigned*
  teacher of the context (`teacher_user_id`); otherwise a colleague could open
  another teacher's roster and marks by id.
  """
  def fetch_assigned_teaching_context(
        %Scope{
          current_user: %User{id: user_id}
        } = scope,
        id
      ) do
    TeachingContext
    |> Ash.Query.for_read(
      :assigned_in_school,
      %{
        id: id,
        teacher_user_id: user_id
      },
      scope: scope
    )
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def fetch_assigned_teaching_context(%Scope{}, _id), do: {:error, :not_found}

  @doc """
  Fetches a `TeachingContext` by id, scoped to the scope's school.
  Replaces the old unscoped `get_by: [:id]` code interface: every lookup must
  now run under a scope.
  """
  def get_teaching_context(%Scope{} = scope, id),
    do: Ash.get(TeachingContext, id, scope: scope)

  @doc """
  Display label for a teaching unit as shown in the class switcher: the
  course label for `{:course, _}`, or the usual context label for
  `{:solo, _}`.
  """
  def unit_label({:course, %CombinedCourse{label: label}}), do: label
  def unit_label({:solo, %TeachingContext{} = ctx}), do: teaching_context_label(ctx)

  @doc """
  The context id to select when a teaching unit's switcher row is picked —
  a representative member context for `{:course, _}` (so the existing
  `/teacher/select-context/:id` route still resolves it), or the context's
  own id for `{:solo, _}`.
  """
  def unit_select_id(%Scope{} = scope, {:course, %CombinedCourse{} = course}) do
    course.id
    |> contexts_of_course!(scope: scope)
    |> List.first()
    |> Map.fetch!(:id)
  end

  def unit_select_id(%Scope{} = _scope, {:solo, %TeachingContext{id: id}}), do: id

  defp teaching_context_label(%{subject: subject, class_group: %{label: label}})
       when is_binary(label),
       do: "#{subject} — #{label}"

  defp teaching_context_label(%{level: level, subject: subject}), do: "#{level} · #{subject}"

  # --- Progression plans (writes) -------------------------------------------

  def create_progression_plan(%Scope{} = scope, %TeachingContext{} = ctx, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:academic_year_id, ctx.academic_year_id)

    ProgressionPlan
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
  end

  @doc """
  Creates a draft `ProgressionPlan` and its entries from imported rows in a
  single transaction (via the `ProgressionPlan.:import` generic action). Rolls
  back entirely on any failure (no orphan plan) and defers notifications until
  after commit. Owner-scoped: the teaching context must belong to the scope's
  school, else `{:error, :not_found}`.
  """
  def import_progression_plan(
        %Scope{} = scope,
        %{teaching_context_id: ctx_id} = attrs,
        rows
      ) do
    with {:ok, ctx} <- fetch_owned_teaching_context(scope, ctx_id) do
      ProgressionPlan
      |> Ash.ActionInput.for_action(
        :import,
        %{
          teaching_context: ctx,
          title: attrs.title,
          rows: rows
        },
        scope: scope
      )
      |> Ash.run_action()
    end
  end

  def duplicate_progression_plan(%Scope{} = scope, %ProgressionPlan{} = plan, overrides) do
    attrs = %{
      title: Map.get(overrides, :title, plan.title <> " (copy)"),
      status: :draft,
      template: Map.get(overrides, :template, false),
      teaching_context_id: plan.teaching_context_id,
      academic_year_id: plan.academic_year_id
    }

    with {:ok, copy} <-
           ProgressionPlan
           |> Ash.Changeset.for_create(:create, attrs, scope: scope)
           |> Ash.create() do
      for m <- list_progression_modules!(plan.id, scope: scope) do
        {:ok, new_m} =
          ProgressionModule
          |> Ash.Changeset.for_create(
            if(m.default?, do: :create_default_bucket, else: :create),
            %{
              title: m.title,
              position: m.position,
              progression_plan_id: copy.id
            },
            scope: scope
          )
          |> Ash.create()

        new_m =
          if m.sequence_id do
            {:ok, nm} =
              new_m
              |> Ash.Changeset.for_update(:update, %{sequence_id: m.sequence_id}, scope: scope)
              |> Ash.update()

            nm
          else
            new_m
          end

        for e <- m.entries do
          ProgressionEntry
          |> Ash.Changeset.for_create(
            :create,
            %{
              lesson_title: e.lesson_title,
              planned_hours: e.planned_hours,
              entry_type: e.entry_type,
              week_no: e.week_no,
              position: e.position,
              famille_de_situations: e.famille_de_situations,
              categories_action: e.categories_action,
              competence_visee: e.competence_visee,
              completed?: e.completed?,
              progression_plan_id: copy.id,
              progression_module_id: new_m.id,
              sequence_id: e.sequence_id
            },
            scope: scope
          )
          |> Ash.create!()
        end
      end

      {:ok, copy}
    end
  end

  def ensure_default_module(%Scope{} = scope, %ProgressionPlan{id: plan_id}) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id and default? == true)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %ProgressionModule{} = m} ->
        {:ok, m}

      {:ok, nil} ->
        pos = module_count(plan_id, scope) + 1

        ProgressionModule
        |> Ash.Changeset.for_create(
          :create_default_bucket,
          %{
            title: "Général",
            position: pos,
            progression_plan_id: plan_id
          },
          scope: scope
        )
        |> Ash.create()
    end
  end

  def create_module(%Scope{} = scope, %ProgressionPlan{id: plan_id}, attrs) do
    pos = module_count(plan_id, scope) + 1

    ProgressionModule
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        position: pos,
        progression_plan_id: plan_id
      }),
      scope: scope
    )
    |> Ash.create()
  end

  def rename_module(%Scope{} = scope, %ProgressionModule{} = m, title),
    do:
      m
      |> Ash.Changeset.for_update(:update, %{title: title}, scope: scope)
      |> Ash.update()

  def set_entry_completed(%Scope{} = scope, %ProgressionEntry{} = e, completed?)
      when is_boolean(completed?),
      do:
        e
        |> Ash.Changeset.for_update(:update, %{completed?: completed?}, scope: scope)
        |> Ash.update()

  @doc """
  Sets `sequence_id` on `m` and cascades it to every entry currently in the
  module. `sequence_id` must name a `Sequence` in `m`'s own workspace — a
  foreign or non-existent id is rejected with `{:error, :invalid}` before
  anything is written (defence in depth next to the composite foreign key,
  which ties this reference to `m`'s tenant at the database).
  """
  def assign_module_sequence(%Scope{} = scope, %ProgressionModule{} = m, sequence_id) do
    with {:ok, %Sequence{}} <- fetch_owned_sequence(sequence_id, scope),
         {:ok, m} <-
           m
           |> Ash.Changeset.for_update(:update, %{sequence_id: sequence_id}, scope: scope)
           |> Ash.update() do
      entries_in_module(m.id, scope)
      |> Enum.each(fn e -> update_progression_entry(scope, e, %{sequence_id: sequence_id}) end)

      {:ok, m}
    end
  end

  # `sequence_id` must name a `Sequence` in the scope's school — a foreign or
  # non-existent id is normalized to `{:error, :invalid}` (never a bare
  # `Ash.get/2` miss) before any write is attempted.
  defp fetch_owned_sequence(sequence_id, %Scope{} = scope) do
    case Ash.get(Sequence, sequence_id, scope: scope) do
      {:ok, seq} -> {:ok, seq}
      _ -> {:error, :invalid}
    end
  end

  def update_module_credit(%Scope{} = scope, %ProgressionModule{} = m, credit),
    do:
      m
      |> Ash.Changeset.for_update(:update, %{credit_hours: credit}, scope: scope)
      |> Ash.update()

  def delete_module(%Scope{}, %ProgressionModule{default?: true}), do: {:error, :default_bucket}

  def delete_module(%Scope{} = scope, %ProgressionModule{} = m) do
    {:ok, plan} = get_progression_plan(scope, m.progression_plan_id)
    {:ok, bucket} = ensure_default_module(scope, plan)
    base = entry_count(bucket.id, scope)

    entries_in_module(m.id, scope)
    |> Enum.with_index(base + 1)
    |> Enum.each(fn {e, pos} ->
      update_progression_entry(scope, e, %{progression_module_id: bucket.id, position: pos})
    end)

    Ash.destroy(m, scope: scope)
  end

  def add_progression_entry(
        %Scope{} = scope,
        %ProgressionModule{
          id: module_id,
          progression_plan_id: plan_id,
          sequence_id: module_seq
        },
        attrs
      ) do
    pos = entry_count(module_id, scope) + 1

    attrs =
      attrs
      |> Map.put(:progression_plan_id, plan_id)
      |> Map.put(:progression_module_id, module_id)
      |> Map.put(:position, pos)
      |> Map.put_new(:sequence_id, module_seq)

    ProgressionEntry
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
  end

  def update_progression_entry(%Scope{} = scope, %ProgressionEntry{} = e, attrs),
    do:
      e
      |> Ash.Changeset.for_update(:update, attrs, scope: scope)
      |> Ash.update()

  def delete_progression_entry(%Scope{} = scope, %ProgressionEntry{} = e),
    do: Ash.destroy(e, scope: scope)

  @doc """
  Applies a validated drag-and-drop layout to a plan (module reorder + entry
  moves), transactionally via the `ProgressionPlan.:apply_layout` action.
  Returns `{:error, :invalid_layout}` when the layout's module/entry id-sets
  do not match the plan's exactly (checked here so the bare atom never crosses
  the action boundary).
  """
  def apply_layout(%Scope{} = scope, %ProgressionPlan{id: plan_id} = plan, layout)
      when is_list(layout) do
    current_modules =
      ProgressionModule
      |> Ash.Query.filter(progression_plan_id == ^plan_id)
      |> Ash.read!(scope: scope)

    current_entries =
      ProgressionEntry
      |> Ash.Query.filter(progression_plan_id == ^plan_id)
      |> Ash.read!(scope: scope)

    layout_module_ids = Enum.map(layout, & &1["module_id"])
    layout_entry_ids = Enum.flat_map(layout, & &1["entry_ids"])

    cond do
      not id_set_matches?(layout_module_ids, Enum.map(current_modules, & &1.id)) ->
        {:error, :invalid_layout}

      not id_set_matches?(layout_entry_ids, Enum.map(current_entries, & &1.id)) ->
        {:error, :invalid_layout}

      true ->
        ProgressionPlan
        |> Ash.ActionInput.for_action(:apply_layout, %{plan: plan, layout: layout}, scope: scope)
        |> Ash.run_action()
    end
  end

  defp id_set_matches?(a, b), do: MapSet.new(a) == MapSet.new(b) and length(a) == length(b)

  def coverage_for_plan(%Scope{} = scope, %ProgressionPlan{id: plan_id}) do
    entries = list_progression_entries!(plan_id, scope: scope)
    logs = list_logs_for_plan!(plan_id, scope: scope)
    TeacherAssistant.Academics.Coverage.summarize(entries, logs)
  end

  # --- Teaching log ---------------------------------------------------------

  @doc """
  Logs teaching under the scope's school. `attrs[:progression_entry_id]` must
  name a `ProgressionEntry` in that school — a foreign or non-existent id is
  rejected with `{:error, :invalid}` before anything is written (same rationale
  as `assign_module_sequence/3`: defence in depth next to the composite foreign
  key, which ties this reference to the tenant at the database).
  """
  def log_teaching(%Scope{} = scope, attrs) do
    entry_id = attrs[:progression_entry_id] || attrs["progression_entry_id"]

    with {:ok, %ProgressionEntry{}} <- fetch_owned_progression_entry(entry_id, scope) do
      TeachingLogEntry
      |> Ash.Changeset.for_create(:create, attrs, scope: scope)
      |> Ash.create()
    end
  end

  defp fetch_owned_progression_entry(entry_id, %Scope{} = scope) do
    case Ash.get(ProgressionEntry, entry_id, scope: scope) do
      {:ok, entry} -> {:ok, entry}
      _ -> {:error, :invalid}
    end
  end

  # --- Progression module/entry counts (private) ----------------------------

  defp module_count(plan_id, %Scope{} = scope) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id)
    |> Ash.count!(scope: scope)
  end

  defp entry_count(module_id, %Scope{} = scope) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.count!(scope: scope)
  end

  defp entries_in_module(module_id, %Scope{} = scope) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(scope: scope)
  end
end
