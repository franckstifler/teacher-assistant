defmodule TeacherAssistant.Academics do
  # Intentionally NOT registered in :ash_domains — its resources now live in
  # focused domains. It remains an Ash.Domain module only to host legacy
  # functions (dissolved in Phase C), so skip the config-inclusion check.
  use Ash.Domain, otp_app: :teacher_assistant, validate_config_inclusion?: false

  require Ash.Query
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Bulletins
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionModule
  alias TeacherAssistant.Academics.TeachingLogEntry
  alias TeacherAssistant.Repo
  alias TeacherAssistant.Scope

  # Resources have moved to focused domains (Organization, Enrollment,
  # Curriculum, Assessment, Attendance, Discipline, Timetabling, Fees).
  # This domain is no longer registered in :ash_domains; it survives only to
  # host its hand-written functions until Phase C dissolves them.
  resources do
  end

  def period_kind({:sequence, _}), do: :sequence
  def period_kind({:trimester, _}), do: :trimester
  def period_kind({:annual, _}), do: :annual

  def period_param({:sequence, %Sequence{id: id}}), do: "seq:" <> id
  def period_param({:trimester, %Term{id: id}}), do: "trim:" <> id
  def period_param({:annual, _}), do: "annee"

  def resolve_period(%AcademicYear{} = year, "annee"), do: {:annual, year}

  def resolve_period(%AcademicYear{} = year, "seq:" <> id) do
    case Enum.find(Organization.list_sequences(year), &(&1.id == id)) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  def resolve_period(%AcademicYear{} = year, "trim:" <> id) do
    case Enum.find(Organization.list_terms(year), &(&1.id == id)) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  def resolve_period(_year, _param), do: nil

  def period_date_range({:sequence, %Sequence{start_date: start_date, end_date: end_date}}) do
    {start_date, end_date}
  end

  def period_date_range({:trimester, %Term{sequences: sequences}}) do
    sequence_date_range(sequences)
  end

  def period_date_range({:annual, %AcademicYear{} = year}) do
    sequence_date_range(Organization.list_sequences(year))
  end

  defp sequence_date_range([]), do: nil

  defp sequence_date_range(sequences) do
    first = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
    last = sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)
    {first, last}
  end

  def current_sequence(%AcademicYear{} = year, %Date{} = date) do
    year
    |> Organization.list_sequences()
    |> Enum.find(fn s ->
      Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt
    end)
  end

  def create_teaching_context(%Workspace{} = ws, %AcademicYear{} = year, attrs) do
    attrs = attrs |> Map.put(:workspace_id, ws.id) |> Map.put(:academic_year_id, year.id)
    TeachingContext |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def update_teaching_context(id, %Workspace{} = ws, attrs) do
    with {:ok, ctx} <- fetch_owned_teaching_context(id, ws) do
      ctx |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)
    end
  end

  def list_teaching_contexts(%Workspace{id: ws_id}, %AcademicYear{id: year_id}) do
    TeachingContext
    |> Ash.Query.filter(workspace_id == ^ws_id and academic_year_id == ^year_id)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def get_teaching_context(id), do: Ash.get(TeachingContext, id, authorize?: false)

  @doc """
  Scope-aware context listing for the class switcher: under personal scope,
  the workspace's own teaching contexts; under school scope, only the
  contexts assigned to the current user (via Curriculum.list_assignments_for_user/3).
  Returns `[]` when there is no current academic year.
  """
  def list_contexts_for_scope(%TeacherAssistant.Scope{
        current_workspace: ws,
        current_academic_year: year,
        current_workspace_type: type,
        current_user: user
      }) do
    cond do
      is_nil(ws) or is_nil(year) -> []
      type == :school -> TeacherAssistant.Curriculum.list_assignments_for_user(ws, year, user)
      true -> list_teaching_contexts(ws, year)
    end
  end

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
  def unit_select_id({:course, %CombinedCourse{} = course}) do
    course.id |> Curriculum.contexts_of_course!() |> List.first() |> Map.fetch!(:id)
  end

  def unit_select_id({:solo, %TeachingContext{id: id}}), do: id

  defp teaching_context_label(%{subject: subject, class_group: %{label: label}})
       when is_binary(label),
       do: "#{subject} — #{label}"

  defp teaching_context_label(%{level: level, subject: subject}), do: "#{level} · #{subject}"

  @doc """
  Resolves the active TeachingContext for the shell's class switcher.
  Owner + active-year scoped: only the workspace's own contexts are searched, so a
  foreign/invalid/stale id simply falls back to the first (alphabetical) context.
  Returns nil when there is no active year or no contexts.
  """
  def resolve_current_context(_ws, nil, _context_id), do: nil

  def resolve_current_context(%Workspace{} = ws, %AcademicYear{} = year, context_id) do
    contexts = list_teaching_contexts(ws, year)
    Enum.find(contexts, fn c -> c.id == context_id end) || List.first(contexts)
  end

  def create_progression_plan(%TeachingContext{} = ctx, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:academic_year_id, ctx.academic_year_id)
      |> Map.put(:workspace_id, ctx.workspace_id)

    ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  @doc """
  `Curriculum.list_progression_plans/1` filtered down to one plan per
  teaching *unit*: course plans, plus the plans of contexts that are NOT
  part of a combined course. Drops a member context's stale solo plan
  (created before the context was combined) so a `CombinedCourse` surfaces
  exactly one coverage KPI instead of one per member class.
  """
  def list_unit_plans(%Workspace{id: ws_id}) do
    Curriculum.unit_plans!(ws_id)
  end

  def fetch_owned_teaching_context(id, %Workspace{id: ws_id}) do
    TeachingContext
    |> Ash.Query.filter(id == ^id and workspace_id == ^ws_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Fetches a teaching context the current user may open in the teacher workspace.

  In a **personal** workspace, ownership of the (owner-only) workspace is the
  guarantee — every context in it belongs to the sole teacher. In a **school**
  workspace the workspace is shared by all staff, so the user must be the
  *assigned* teacher of the context (`teacher_user_id`); otherwise a colleague
  could open another teacher's roster and marks by id.
  """
  def fetch_assigned_teaching_context(id, %Scope{
        current_workspace_type: :school,
        current_workspace: %Workspace{id: ws_id},
        current_user: %User{id: user_id}
      }) do
    TeachingContext
    |> Ash.Query.filter(id == ^id and workspace_id == ^ws_id and teacher_user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def fetch_assigned_teaching_context(id, %Scope{current_workspace: %Workspace{} = ws}),
    do: fetch_owned_teaching_context(id, ws)

  def fetch_assigned_teaching_context(_id, %Scope{}), do: {:error, :not_found}

  def link_class_group(%TeachingContext{} = ctx, %ClassGroup{id: cg_id}) do
    ctx
    |> Ash.Changeset.for_update(:update, %{class_group_id: cg_id})
    |> Ash.update(authorize?: false)
  end

  @doc """
  Bulletin input for a class + séquence: one entry per school teaching context of
  the class (subject × class, assigned teacher), shaped for `Bulletins.compile/2`.
  """
  def class_subjects(%ClassGroup{id: cg_id}, %Sequence{} = seq) do
    TeachingContext
    |> Ash.Query.filter(class_group_id == ^cg_id and not is_nil(teacher_user_id))
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn tc ->
      assessments = TeacherAssistant.Assessment.list_assessments(tc, seq)

      %{
        context_id: tc.id,
        label: tc.subject,
        coefficient: tc.coefficient,
        assessments_by_id:
          Map.new(assessments, fn a -> {a.id, %{weight: a.weight, max_score: a.max_score}} end),
        marks:
          tc
          |> TeacherAssistant.Assessment.list_marks_for_context_sequence(seq)
          |> Enum.map(fn m ->
            %{student_id: m.student_id, assessment_id: m.assessment_id, score: m.score}
          end)
      }
    end)
  end

  @doc """
  Compiled class bulletins for a séquence, or nil when the class has no subjects.
  """
  def class_results(%ClassGroup{} = cg, %Sequence{} = seq) do
    case class_subjects(cg, seq) do
      [] ->
        nil

      subjects ->
        students =
          cg |> Enrollment.list_students() |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)

        Bulletins.compile(students, subjects)
    end
  end

  @doc """
  Compiled class bulletins for a period (`{:sequence, seq}` / `{:trimester, term}` /
  `{:annual, year}`), or nil when the class has no subjects. Trimester/annual
  averages are the mean of the constituent séquence subject-averages that exist.
  """
  def class_results_for_period(%ClassGroup{} = cg, {:sequence, %Sequence{} = seq}) do
    class_results(cg, seq)
  end

  def class_results_for_period(%ClassGroup{} = cg, {:trimester, %Term{} = term}) do
    seqs = Enum.sort_by(term.sequences, & &1.position_in_term)
    period_result(cg, seqs, :sequences)
  end

  def class_results_for_period(%ClassGroup{} = cg, {:annual, %AcademicYear{} = year}) do
    seqs = Organization.list_sequences(year)
    period_result(cg, seqs, :trimesters)
  end

  # Builds a Bulletins result over a set of séquences. `component_kind` selects the
  # breakdown carried on each subject row: :sequences (per séquence, for trimester)
  # or :trimesters (per term, for annual).
  defp period_result(cg, seqs, component_kind) do
    students = cg |> Enrollment.list_students() |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)

    # per séquence: %{context_id => %{label, coefficient, per_student_avg}}
    per_seq =
      Enum.map(seqs, fn seq ->
        subjects =
          cg
          |> class_subjects(seq)
          |> Map.new(fn subj ->
            psa =
              Map.new(students, fn s ->
                sm = Enum.filter(subj.marks, &(&1.student_id == s.id))

                {s.id,
                 TeacherAssistant.Academics.Marks.subject_average(sm, subj.assessments_by_id)}
              end)

            {subj.context_id,
             %{label: subj.label, coefficient: subj.coefficient, per_student_avg: psa}}
          end)

        {seq, subjects}
      end)

    contexts =
      per_seq |> Enum.flat_map(fn {_seq, m} -> Map.keys(m) end) |> Enum.uniq()

    if contexts == [] or students == [] do
      nil
    else
      subject_inputs =
        Enum.map(contexts, fn cid ->
          {label, coef} = context_label_coef(per_seq, cid)

          per_student_avg =
            Map.new(students, fn s ->
              {s.id, mean_present(sequence_values(per_seq, cid, s.id))}
            end)

          components =
            Map.new(students, fn s ->
              {s.id, build_components(component_kind, per_seq, cid, s.id)}
            end)

          %{
            context_id: cid,
            label: label,
            coefficient: coef,
            per_student_avg: per_student_avg,
            components: components
          }
        end)

      Bulletins.aggregate(students, subject_inputs)
    end
  end

  defp context_label_coef(per_seq, cid) do
    {_seq, m} = Enum.find(per_seq, fn {_seq, m} -> Map.has_key?(m, cid) end)
    sub = m[cid]
    {sub.label, sub.coefficient}
  end

  # this subject's per-séquence average for one student, in séquence order (nils dropped)
  defp sequence_values(per_seq, cid, sid) do
    per_seq
    |> Enum.map(fn {_seq, m} -> m[cid] && m[cid].per_student_avg[sid] end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_components(:sequences, per_seq, cid, sid) do
    seqs =
      Enum.map(per_seq, fn {seq, m} ->
        %{number: seq.number, average: m[cid] && m[cid].per_student_avg[sid]}
      end)

    %{sequences: seqs}
  end

  defp build_components(:trimesters, per_seq, cid, sid) do
    trimesters =
      per_seq
      |> Enum.group_by(fn {seq, _m} -> seq.term.position end)
      |> Enum.sort_by(fn {position, _} -> position end)
      |> Enum.map(fn {position, term_seqs} ->
        vals =
          term_seqs
          |> Enum.map(fn {_seq, m} -> m[cid] && m[cid].per_student_avg[sid] end)
          |> Enum.reject(&is_nil/1)

        %{position: position, average: mean_present(vals)}
      end)

    %{trimesters: trimesters}
  end

  defp mean_present([]), do: nil

  defp mean_present(vals) do
    Decimal.div(Enum.reduce(vals, Decimal.new(0), &Decimal.add/2), Decimal.new(length(vals)))
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
        %Workspace{} = ws,
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
            workspace_id: ctx.workspace_id
          }

          {plan, plan_notifs} =
            case ProgressionPlan
                 |> Ash.Changeset.for_create(:create, plan_attrs)
                 |> Ash.create(authorize?: false, return_notifications?: true) do
              {:ok, plan, notifs} -> {plan, notifs}
              {:error, reason} -> Repo.rollback(reason)
            end

          groups = TeacherAssistant.Academics.ModuleGrouping.group(index_rows(rows))
          rows_by_index = rows |> Enum.with_index() |> Map.new(fn {r, i} -> {i, r} end)

          entry_notifs =
            groups
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {%{key: key, entry_ids: row_indexes}, mod_pos} ->
              {:ok, module, module_notifs} = create_import_module(plan, key, mod_pos)

              row_notifs =
                row_indexes
                |> Enum.with_index(1)
                |> Enum.flat_map(fn {row_index, entry_pos} ->
                  row = Map.fetch!(rows_by_index, row_index)

                  entry_attrs =
                    row
                    |> Map.take([
                      :lesson_title,
                      :planned_hours,
                      :entry_type,
                      :week_no,
                      :sequence_id
                    ])
                    |> Map.put(:progression_plan_id, plan.id)
                    |> Map.put(:progression_module_id, module.id)
                    |> Map.put(:position, entry_pos)

                  case ProgressionEntry
                       |> Ash.Changeset.for_create(:create, entry_attrs)
                       |> Ash.create(authorize?: false, return_notifications?: true) do
                    {:ok, _entry, notifs} -> notifs
                    {:error, reason} -> Repo.rollback(reason)
                  end
                end)

              module_notifs ++ row_notifs
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

  # ModuleGrouping.group/1 keys entries by :id; feed it the row *index* as the id so we
  # can map groups back to rows.
  defp index_rows(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {r, i} -> %{id: i, module: Map.get(r, :module), position: i} end)
  end

  defp create_import_module(plan, :default, pos) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create_default_bucket, %{
      title: "Général",
      position: pos,
      progression_plan_id: plan.id
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
  end

  defp create_import_module(plan, title, pos) when is_binary(title) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create, %{
      title: title,
      position: pos,
      progression_plan_id: plan.id
    })
    |> Ash.create(authorize?: false, return_notifications?: true)
  end

  def duplicate_progression_plan(%ProgressionPlan{} = plan, overrides) do
    attrs = %{
      title: Map.get(overrides, :title, plan.title <> " (copy)"),
      status: :draft,
      template: Map.get(overrides, :template, false),
      teaching_context_id: plan.teaching_context_id,
      academic_year_id: plan.academic_year_id,
      workspace_id: plan.workspace_id
    }

    with {:ok, copy} <-
           ProgressionPlan
           |> Ash.Changeset.for_create(:create, attrs)
           |> Ash.create(authorize?: false) do
      for m <- Curriculum.list_progression_modules!(plan.id) do
        {:ok, new_m} =
          ProgressionModule
          |> Ash.Changeset.for_create(
            if(m.default?, do: :create_default_bucket, else: :create),
            %{title: m.title, position: m.position, progression_plan_id: copy.id}
          )
          |> Ash.create(authorize?: false)

        new_m =
          if m.sequence_id do
            {:ok, nm} =
              new_m
              |> Ash.Changeset.for_update(:update, %{sequence_id: m.sequence_id})
              |> Ash.update(authorize?: false)

            nm
          else
            new_m
          end

        for e <- m.entries do
          ProgressionEntry
          |> Ash.Changeset.for_create(:create, %{
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
          })
          |> Ash.create!(authorize?: false)
        end
      end

      {:ok, copy}
    end
  end

  def ensure_default_module(%ProgressionPlan{id: plan_id}) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id and default? == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %ProgressionModule{} = m} ->
        {:ok, m}

      {:ok, nil} ->
        pos = module_count(plan_id) + 1

        ProgressionModule
        |> Ash.Changeset.for_create(:create_default_bucket, %{
          title: "Général",
          position: pos,
          progression_plan_id: plan_id
        })
        |> Ash.create(authorize?: false)
    end
  end

  def create_module(%ProgressionPlan{id: plan_id}, attrs) do
    pos = module_count(plan_id) + 1

    ProgressionModule
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{position: pos, progression_plan_id: plan_id})
    )
    |> Ash.create(authorize?: false)
  end

  def rename_module(%ProgressionModule{} = m, title),
    do: m |> Ash.Changeset.for_update(:update, %{title: title}) |> Ash.update(authorize?: false)

  def set_entry_completed(%ProgressionEntry{} = e, completed?) when is_boolean(completed?),
    do:
      e
      |> Ash.Changeset.for_update(:update, %{completed?: completed?})
      |> Ash.update(authorize?: false)

  def assign_module_sequence(%ProgressionModule{} = m, sequence_id) do
    with {:ok, m} <-
           m
           |> Ash.Changeset.for_update(:update, %{sequence_id: sequence_id})
           |> Ash.update(authorize?: false) do
      entries_in_module(m.id)
      |> Enum.each(fn e -> update_progression_entry(e, %{sequence_id: sequence_id}) end)

      {:ok, m}
    end
  end

  def update_module_credit(%ProgressionModule{} = m, credit),
    do:
      m
      |> Ash.Changeset.for_update(:update, %{credit_hours: credit})
      |> Ash.update(authorize?: false)

  def delete_module(%ProgressionModule{default?: true}), do: {:error, :default_bucket}

  def delete_module(%ProgressionModule{} = m) do
    {:ok, plan} = Ash.get(ProgressionPlan, m.progression_plan_id, authorize?: false)
    {:ok, bucket} = ensure_default_module(plan)
    base = entry_count(bucket.id)

    entries_in_module(m.id)
    |> Enum.with_index(base + 1)
    |> Enum.each(fn {e, pos} ->
      update_progression_entry(e, %{progression_module_id: bucket.id, position: pos})
    end)

    Ash.destroy(m, authorize?: false)
  end

  def add_progression_entry(
        %ProgressionModule{id: module_id, progression_plan_id: plan_id, sequence_id: module_seq},
        attrs
      ) do
    pos = entry_count(module_id) + 1

    attrs =
      attrs
      |> Map.put(:progression_plan_id, plan_id)
      |> Map.put(:progression_module_id, module_id)
      |> Map.put(:position, pos)
      |> Map.put_new(:sequence_id, module_seq)

    ProgressionEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  defp module_count(plan_id) do
    ProgressionModule
    |> Ash.Query.filter(progression_plan_id == ^plan_id)
    |> Ash.count!(authorize?: false)
  end

  defp entry_count(module_id) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.count!(authorize?: false)
  end

  defp entries_in_module(module_id) do
    ProgressionEntry
    |> Ash.Query.filter(progression_module_id == ^module_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  def update_progression_entry(%ProgressionEntry{} = e, attrs),
    do: e |> Ash.Changeset.for_update(:update, attrs) |> Ash.update(authorize?: false)

  def delete_progression_entry(%ProgressionEntry{} = e), do: Ash.destroy(e, authorize?: false)

  defp list_entries_query(plan_id) do
    ProgressionEntry |> Ash.Query.filter(progression_plan_id == ^plan_id)
  end

  def apply_layout(%ProgressionPlan{id: plan_id}, layout) when is_list(layout) do
    current_modules =
      ProgressionModule
      |> Ash.Query.filter(progression_plan_id == ^plan_id)
      |> Ash.read!(authorize?: false)

    current_entries = list_entries_query(plan_id) |> Ash.read!(authorize?: false)

    layout_module_ids = Enum.map(layout, & &1["module_id"])
    layout_entry_ids = Enum.flat_map(layout, & &1["entry_ids"])

    cond do
      not id_set_matches?(layout_module_ids, Enum.map(current_modules, & &1.id)) ->
        {:error, :invalid_layout}

      not id_set_matches?(layout_entry_ids, Enum.map(current_entries, & &1.id)) ->
        {:error, :invalid_layout}

      true ->
        module_by_id = Map.new(current_modules, &{&1.id, &1})
        entry_by_id = Map.new(current_entries, &{&1.id, &1})

        result =
          Repo.transaction(fn ->
            layout
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {%{"module_id" => mid, "entry_ids" => eids}, mpos} ->
              module_notifs =
                case module_by_id[mid]
                     |> Ash.Changeset.for_update(:update, %{position: mpos})
                     |> Ash.update(authorize?: false, return_notifications?: true) do
                  {:ok, _module, notifs} -> notifs
                  {:error, reason} -> Repo.rollback(reason)
                end

              entry_notifs =
                eids
                |> Enum.with_index(1)
                |> Enum.flat_map(fn {eid, epos} ->
                  case entry_by_id[eid]
                       |> Ash.Changeset.for_update(:update, %{
                         progression_module_id: mid,
                         position: epos
                       })
                       |> Ash.update(authorize?: false, return_notifications?: true) do
                    {:ok, _entry, notifs} -> notifs
                    {:error, reason} -> Repo.rollback(reason)
                  end
                end)

              module_notifs ++ entry_notifs
            end)
          end)

        case result do
          {:ok, notifications} ->
            Ash.Notifier.notify(notifications)
            {:ok, :applied}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp id_set_matches?(a, b), do: MapSet.new(a) == MapSet.new(b) and length(a) == length(b)

  def log_teaching(%Workspace{id: ws_id}, attrs) do
    attrs = Map.put(attrs, :workspace_id, ws_id)
    TeachingLogEntry |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def coverage_for_plan(%ProgressionPlan{id: plan_id}) do
    entries = Curriculum.list_progression_entries!(plan_id)
    logs = Curriculum.list_logs_for_plan!(plan_id)
    TeacherAssistant.Academics.Coverage.summarize(entries, logs)
  end
end
