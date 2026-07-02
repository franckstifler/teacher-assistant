defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Student
  alias TeacherAssistant.Academics.Assessment
  alias TeacherAssistant.Academics.Mark
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.TeachingLogEntry
  alias TeacherAssistant.Academics.LessonPlan
  alias TeacherAssistant.Academics.LessonStep
  alias TeacherAssistant.Repo

  resources do
    resource PersonalWorkspace
    resource AcademicYear
    resource Term
    resource Sequence
    resource TeachingContext
    resource ClassGroup
    resource Student
    resource Assessment
    resource Mark
    resource ProgressionPlan
    resource ProgressionEntry
    resource TeachingLogEntry
    resource LessonPlan
    resource LessonStep
  end

  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, ws} ->
        ws

      {:error, :not_found} ->
        {:ok, ws} =
          PersonalWorkspace
          |> Ash.Changeset.for_create(:create, %{
            name: "Personal workspace",
            owner_user_id: user.id
          })
          |> Ash.create(authorize?: false)

        ws
    end
  end

  def personal_workspace_for_user(%User{id: user_id}) do
    PersonalWorkspace
    |> Ash.Query.filter(owner_user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def get_personal_workspace(id), do: Ash.get(PersonalWorkspace, id, authorize?: false)

  def create_academic_year(%PersonalWorkspace{} = ws, attrs) do
    attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put_new(:active, true)

    with {:ok, year} <-
           AcademicYear
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false) do
      if year.active, do: deactivate_other_years(ws, year.id)
      {:ok, year}
    end
  end

  def list_academic_years(%PersonalWorkspace{id: id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^id)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read!(authorize?: false)
  end

  def current_academic_year(%PersonalWorkspace{id: id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^id and active == true)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  def get_academic_year(id), do: Ash.get(AcademicYear, id, authorize?: false)

  defp deactivate_other_years(%PersonalWorkspace{id: ws_id}, keep_id) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and id != ^keep_id and active == true)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn y ->
      y |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update!(authorize?: false)
    end)
  end

  def build_default_calendar(%AcademicYear{} = year) do
    preset = TeacherAssistant.Academics.Reference.default_calendar_preset()

    Enum.each(preset.terms, fn term_spec ->
      {:ok, term} =
        Term
        |> Ash.Changeset.for_create(:create, %{
          position: term_spec.position,
          academic_year_id: year.id
        })
        |> Ash.create(authorize?: false)

      Enum.each(term_spec.sequences, fn s ->
        Sequence
        |> Ash.Changeset.for_create(
          :create,
          Map.put(
            Map.take(s, [:number, :position_in_term, :start_date, :end_date, :integration_week]),
            :term_id,
            term.id
          )
        )
        |> Ash.create!(authorize?: false)
      end)
    end)

    :ok
  end

  def list_sequences(%AcademicYear{id: year_id}) do
    Sequence
    |> Ash.Query.filter(term.academic_year_id == ^year_id)
    |> Ash.Query.load(:term)
    |> Ash.Query.sort(number: :asc)
    |> Ash.read!(authorize?: false)
  end

  def current_sequence(%AcademicYear{} = year, %Date{} = date) do
    year
    |> list_sequences()
    |> Enum.find(fn s ->
      Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt
    end)
  end

  def create_teaching_context(%PersonalWorkspace{} = ws, %AcademicYear{} = year, attrs) do
    attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put(:academic_year_id, year.id)
    TeachingContext |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_teaching_contexts(%PersonalWorkspace{id: ws_id}, %AcademicYear{id: year_id}) do
    TeachingContext
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and academic_year_id == ^year_id)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def get_teaching_context(id), do: Ash.get(TeachingContext, id, authorize?: false)

  @doc """
  Resolves the active TeachingContext for the shell's class switcher.
  Owner + active-year scoped: only the workspace's own contexts are searched, so a
  foreign/invalid/stale id simply falls back to the first (alphabetical) context.
  Returns nil when there is no active year or no contexts.
  """
  def resolve_current_context(_ws, nil, _context_id), do: nil

  def resolve_current_context(%PersonalWorkspace{} = ws, %AcademicYear{} = year, context_id) do
    contexts = list_teaching_contexts(ws, year)
    Enum.find(contexts, fn c -> c.id == context_id end) || List.first(contexts)
  end

  def create_progression_plan(%TeachingContext{} = ctx, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:academic_year_id, ctx.academic_year_id)
      |> Map.put(:personal_workspace_id, ctx.personal_workspace_id)

    ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_progression_plans(%PersonalWorkspace{id: ws_id}) do
    ProgressionPlan
    |> Ash.Query.filter(personal_workspace_id == ^ws_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  def get_progression_plan(id), do: Ash.get(ProgressionPlan, id, authorize?: false)

  def fetch_owned_plan(id, %PersonalWorkspace{id: ws_id}) do
    ProgressionPlan
    |> Ash.Query.filter(id == ^id and personal_workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def fetch_owned_entry(id, %PersonalWorkspace{} = ws) do
    case Ash.get(ProgressionEntry, id, authorize?: false) do
      {:ok, entry} ->
        case fetch_owned_plan(entry.progression_plan_id, ws) do
          {:ok, _} -> {:ok, entry}
          _ -> {:error, :not_found}
        end

      error ->
        error
    end
  end

  def fetch_owned_entry_with_context(entry_id, %PersonalWorkspace{} = ws) do
    with {:ok, entry} <- fetch_owned_entry(entry_id, ws),
         {:ok, plan} <- fetch_owned_plan(entry.progression_plan_id, ws),
         {:ok, ctx} <- fetch_owned_teaching_context(plan.teaching_context_id, ws) do
      class_group = load_owned_class_group(ctx.class_group_id, ws)
      effectif = if class_group, do: length(list_students(class_group)), else: 0

      {:ok,
       %{
         entry: entry,
         plan: plan,
         ctx: ctx,
         class_group: class_group,
         year: current_academic_year(ws),
         effectif: effectif
       }}
    end
  end

  defp load_owned_class_group(nil, _ws), do: nil

  defp load_owned_class_group(id, ws) do
    case fetch_owned_class_group(id, ws) do
      {:ok, cg} -> cg
      _ -> nil
    end
  end

  def fetch_owned_teaching_context(id, %PersonalWorkspace{id: ws_id}) do
    TeachingContext
    |> Ash.Query.filter(id == ^id and personal_workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def create_class_group(%PersonalWorkspace{} = ws, %AcademicYear{} = year, attrs) do
    attrs =
      attrs
      |> Map.put(:personal_workspace_id, ws.id)
      |> Map.put(:academic_year_id, year.id)
      |> Map.put_new(:subsystem, :francophone)

    ClassGroup |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_class_groups(%PersonalWorkspace{id: ws_id}, %AcademicYear{id: year_id}) do
    ClassGroup
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and academic_year_id == ^year_id)
    |> Ash.Query.sort(label: :asc)
    |> Ash.read!(authorize?: false)
  end

  def fetch_owned_class_group(id, %PersonalWorkspace{id: ws_id}) do
    ClassGroup
    |> Ash.Query.filter(id == ^id and personal_workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def add_student(%ClassGroup{id: cg_id}, attrs) do
    attrs = Map.put(attrs, :class_group_id, cg_id)
    Student |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_students(%ClassGroup{id: cg_id}) do
    Student
    |> Ash.Query.filter(class_group_id == ^cg_id)
    |> Ash.Query.sort(full_name: :asc)
    |> Ash.read!(authorize?: false)
  end

  def update_student(%Student{} = s, attrs),
    do: s |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_student(%Student{} = s), do: Ash.destroy(s, authorize?: false)

  def fetch_owned_student(id, %PersonalWorkspace{} = ws) do
    case Ash.get(Student, id, authorize?: false) do
      {:ok, student} ->
        case fetch_owned_class_group(student.class_group_id, ws) do
          {:ok, _} -> {:ok, student}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  def link_class_group(%TeachingContext{} = ctx, %ClassGroup{id: cg_id}) do
    ctx
    |> Ash.Changeset.for_update(:update, %{class_group_id: cg_id})
    |> Ash.update(authorize?: false)
  end

  def create_assessment(%TeachingContext{} = ctx, %Sequence{id: seq_id}, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:sequence_id, seq_id)

    Assessment |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_assessments(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    Assessment
    |> Ash.Query.filter(teaching_context_id == ^ctx_id and sequence_id == ^seq_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def fetch_owned_assessment(id, %PersonalWorkspace{} = ws) do
    case Ash.get(Assessment, id, authorize?: false) do
      {:ok, assessment} ->
        case fetch_owned_teaching_context(assessment.teaching_context_id, ws) do
          {:ok, _} -> {:ok, assessment}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates or updates a `Mark` per `(assessment, student)` in a single transaction.
  A `nil` score is valid (records the student absent).

  Notifications are deferred until after the transaction commits so that
  rolled-back rows never produce phantom PubSub events and no
  `:missed_notifications` advisory is emitted.
  """
  def upsert_marks(%Assessment{id: assessment_id}, entries) do
    result =
      Repo.transaction(fn ->
        existing =
          Mark
          |> Ash.Query.filter(assessment_id == ^assessment_id)
          |> Ash.read!(authorize?: false)
          |> Map.new(fn m -> {m.student_id, m} end)

        Enum.flat_map(entries, fn %{student_id: student_id} = entry ->
          score = Map.get(entry, :score)

          case Map.get(existing, student_id) do
            nil ->
              case Mark
                   |> Ash.Changeset.for_create(:create, %{
                     assessment_id: assessment_id,
                     student_id: student_id,
                     score: score
                   })
                   |> Ash.create(authorize?: false, return_notifications?: true) do
                {:ok, _mark, notifs} -> notifs
                {:error, reason} -> Repo.rollback(reason)
              end

            %Mark{} = mark ->
              case mark
                   |> Ash.Changeset.for_update(:update, %{score: score})
                   |> Ash.update(authorize?: false, return_notifications?: true) do
                {:ok, _mark, notifs} -> notifs
                {:error, reason} -> Repo.rollback(reason)
              end
          end
        end)
      end)

    case result do
      {:ok, notifications} ->
        Ash.Notifier.notify(notifications)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_marks(%Assessment{id: assessment_id}) do
    Mark
    |> Ash.Query.filter(assessment_id == ^assessment_id)
    |> Ash.read!(authorize?: false)
  end

  def list_marks_for_context_sequence(%TeachingContext{id: ctx_id}, %Sequence{id: seq_id}) do
    assessment_ids =
      Assessment
      |> Ash.Query.filter(teaching_context_id == ^ctx_id and sequence_id == ^seq_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    Mark
    |> Ash.Query.filter(assessment_id in ^assessment_ids)
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Creates a draft ProgressionPlan and its entries from imported rows in a single
  transaction. Rolls back entirely on any failure (no orphan plan). Owner-scoped:
  the teaching context must belong to `ws`.

  Notifications are deferred until after the transaction commits so that
  rolled-back rows never produce phantom PubSub events and no
  `:missed_notifications` advisory is emitted.
  """
  def import_progression_plan(
        %PersonalWorkspace{} = ws,
        %{teaching_context_id: ctx_id} = attrs,
        rows
      ) do
    with {:ok, ctx} <- fetch_owned_teaching_context(ctx_id, ws) do
      result =
        Repo.transaction(fn ->
          plan_attrs = %{
            title: attrs.title,
            status: :draft,
            teaching_context_id: ctx.id,
            academic_year_id: ctx.academic_year_id,
            personal_workspace_id: ctx.personal_workspace_id
          }

          {plan, plan_notifs} =
            case ProgressionPlan
                 |> Ash.Changeset.for_create(:create, plan_attrs)
                 |> Ash.create(authorize?: false, return_notifications?: true) do
              {:ok, plan, notifs} -> {plan, notifs}
              {:error, reason} -> Repo.rollback(reason)
            end

          entry_notifs =
            rows
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {row, position} ->
              entry_attrs =
                row
                |> Map.take([
                  :module,
                  :lesson_title,
                  :planned_hours,
                  :entry_type,
                  :week_no,
                  :sequence_id
                ])
                |> Map.put(:progression_plan_id, plan.id)
                |> Map.put(:position, position)

              case ProgressionEntry
                   |> Ash.Changeset.for_create(:create, entry_attrs)
                   |> Ash.create(authorize?: false, return_notifications?: true) do
                {:ok, _entry, notifs} -> notifs
                {:error, reason} -> Repo.rollback(reason)
              end
            end)

          {plan, plan_notifs ++ entry_notifs}
        end)

      case result do
        {:ok, {plan, notifications}} ->
          Ash.Notifier.notify(notifications)
          {:ok, plan}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def duplicate_progression_plan(%ProgressionPlan{} = plan, overrides) do
    attrs = %{
      title: Map.get(overrides, :title, plan.title <> " (copy)"),
      status: :draft,
      template: Map.get(overrides, :template, false),
      teaching_context_id: plan.teaching_context_id,
      academic_year_id: plan.academic_year_id,
      personal_workspace_id: plan.personal_workspace_id
    }

    with {:ok, copy} <-
           ProgressionPlan
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false) do
      for e <- list_progression_entries(plan) do
        ProgressionEntry
        |> Ash.Changeset.for_create(:create, %{
          module: e.module,
          lesson_title: e.lesson_title,
          planned_hours: e.planned_hours,
          entry_type: e.entry_type,
          week_no: e.week_no,
          position: e.position,
          famille_de_situations: e.famille_de_situations,
          categories_action: e.categories_action,
          competence_visee: e.competence_visee,
          progression_plan_id: copy.id,
          sequence_id: e.sequence_id
        })
        |> Ash.create!(authorize?: false)
      end

      {:ok, copy}
    end
  end

  def add_progression_entry(%ProgressionPlan{id: plan_id}, attrs) do
    next = (list_entries_query(plan_id) |> Ash.read!(authorize?: false) |> length()) + 1
    attrs = attrs |> Map.put(:progression_plan_id, plan_id) |> Map.put_new(:position, next)
    ProgressionEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_progression_entries(%ProgressionPlan{id: plan_id}) do
    list_entries_query(plan_id) |> Ash.Query.sort(position: :asc) |> Ash.read!(authorize?: false)
  end

  def update_progression_entry(%ProgressionEntry{} = e, attrs),
    do: e |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_progression_entry(%ProgressionEntry{} = e), do: Ash.destroy(e, authorize?: false)
  def get_progression_entry(id), do: Ash.get(ProgressionEntry, id, authorize?: false)

  defp list_entries_query(plan_id) do
    ProgressionEntry |> Ash.Query.filter(progression_plan_id == ^plan_id)
  end

  def get_lesson_plan_for_entry(entry_id) do
    LessonPlan
    |> Ash.Query.filter(progression_entry_id == ^entry_id)
    |> Ash.read_one!(authorize?: false)
  end

  def ensure_lesson_plan(%ProgressionEntry{} = entry, %TeachingContext{} = _ctx) do
    case get_lesson_plan_for_entry(entry.id) do
      %LessonPlan{} = lp ->
        {:ok, lp}

      nil ->
        case create_lesson_plan_from_entry(entry) do
          {:ok, lp} ->
            {:ok, lp}

          {:error, error} ->
            # Lost a concurrent first-open race: the unique_entry identity rejected
            # this insert because another process already created the fiche. Return
            # the winner rather than clobbering it or crashing the caller.
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

    LessonPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def update_lesson_plan(%LessonPlan{} = lp, attrs),
    do: lp |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def list_lesson_steps(%LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.filter(lesson_plan_id == ^lp_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def add_lesson_step(%LessonPlan{} = lp, attrs \\ %{}) do
    next =
      lp
      |> list_lesson_steps()
      |> Enum.map(& &1.position)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    attrs =
      attrs
      |> Map.put(:lesson_plan_id, lp.id)
      |> Map.put_new(:position, next)

    LessonStep |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def update_lesson_step(%LessonStep{} = s, attrs),
    do: s |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_lesson_step(%LessonStep{} = s), do: Ash.destroy(s, authorize?: false)

  def move_lesson_step(%LessonStep{} = step, direction) when direction in [:up, :down] do
    steps =
      LessonStep
      |> Ash.Query.filter(lesson_plan_id == ^step.lesson_plan_id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    idx = Enum.find_index(steps, &(&1.id == step.id))
    swap_idx = if direction == :up, do: idx && idx - 1, else: idx && idx + 1

    cond do
      is_nil(idx) ->
        {:ok, step}

      swap_idx < 0 or swap_idx >= length(steps) ->
        {:ok, step}

      true ->
        other = Enum.at(steps, swap_idx)
        {:ok, _} = update_lesson_step(other, %{position: step.position})
        update_lesson_step(step, %{position: other.position})
    end
  end

  def fetch_owned_lesson_step(id, %LessonPlan{id: lp_id}) do
    LessonStep
    |> Ash.Query.filter(id == ^id and lesson_plan_id == ^lp_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def log_teaching(%PersonalWorkspace{id: ws_id}, attrs) do
    attrs = Map.put(attrs, :personal_workspace_id, ws_id)
    TeachingLogEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_logs_for_plan(%ProgressionPlan{id: plan_id}) do
    entry_ids = list_entries_query(plan_id) |> Ash.read!(authorize?: false) |> Enum.map(& &1.id)

    TeachingLogEntry
    |> Ash.Query.filter(progression_entry_id in ^entry_ids)
    |> Ash.Query.sort(date: :desc)
    |> Ash.read!(authorize?: false)
  end

  def list_recent_logs(%PersonalWorkspace{id: ws_id}, limit \\ 10) do
    TeachingLogEntry
    |> Ash.Query.filter(personal_workspace_id == ^ws_id)
    |> Ash.Query.sort(date: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(authorize?: false)
  end

  def coverage_for_plan(%ProgressionPlan{} = plan) do
    entries = list_progression_entries(plan)
    logs = list_logs_for_plan(plan)
    TeacherAssistant.Academics.Coverage.summarize(entries, logs)
  end
end
