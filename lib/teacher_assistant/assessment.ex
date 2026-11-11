defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  # NAME COLLISION: this domain module is `TeacherAssistant.Assessment`, and
  # the resource is `TeacherAssistant.Academics.Assessment`. Inside this module
  # the short alias `Assessment` is bound to the RESOURCE (below); this module
  # calls its own domain functions bare, so there is never a bare
  # `Assessment.<fn>` that could rebind to the wrong module.
  alias TeacherAssistant.Accounts.User

  alias TeacherAssistant.Academics.{
    AbsenceRule,
    AcademicYear,
    AnnualAverageRule,
    Assessment,
    AssessmentType,
    AverageRounding,
    BulletinPublication,
    BulletinTemplate,
    BulletinGroup,
    Bulletins,
    ClassCouncil,
    ClassGroup,
    CombinedCourse,
    CouncilDecision,
    EntryProgress,
    EntryReminder,
    GradingRules,
    Lock,
    Mark,
    MarkCorrection,
    MarkEntry,
    MarkEvent,
    Marks,
    Sequence,
    SequenceCompetence,
    Term,
    TeachingContext,
    TrimesterAverageRule
  }

  alias TeacherAssistant.Notifications
  alias TeacherAssistant.Scope

  resources do
    resource Assessment
    resource AssessmentType
    resource Mark
    resource MarkEvent
    resource MarkCorrection
    resource BulletinPublication
    resource ClassCouncil
    resource CouncilDecision
    resource EntryReminder
    resource TeacherAssistant.Academics.SequenceCompetence
  end

  authorization do
    authorize :by_default
  end

  # --- Competences (spec bulletin v2 §6) --------------------------------------

  @doc """
  Saves the competence `ctx` evaluated in `seq`; blank text removes it. A combined
  course writes it on every member context, so each class's card reads its own.
  """
  def put_sequence_competence(%Scope{} = scope, %TeachingContext{} = ctx, %Sequence{} = seq, text) do
    contexts = competence_contexts(scope, ctx)
    text = String.trim(text || "")

    TeacherAssistant.Repo.transaction(fn ->
      result =
        if text == "",
          do: remove_competences(scope, contexts, seq),
          else: upsert_competences(scope, contexts, seq, text)

      with {:error, error} <- result, do: TeacherAssistant.Repo.rollback(error)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "The saved competences as `%{{context_id, sequence_id} => text}`."
  def sequence_competences(%Scope{} = scope, context_ids, sequence_ids) do
    SequenceCompetence
    |> Ash.Query.for_read(
      :for_contexts,
      %{context_ids: context_ids, sequence_ids: sequence_ids},
      scope: scope
    )
    |> Ash.read!()
    |> Map.new(&{{&1.teaching_context_id, &1.sequence_id}, &1.text})
  end

  @doc "Whether the class's report cards are APC (the school ticked `:apc`)."
  def apc?(%Scope{} = scope, %ClassGroup{} = cg),
    do: :apc in TeacherAssistant.ReportCards.template(scope, cg).elements

  @doc """
  Each course's competence for `seq` as `%{context_id => text}`, nil where none is
  written yet; `nil` when none is due: the school's report cards are not APC, or `seq`
  has not started.
  """
  def competences_due(%Scope{} = scope, %Sequence{} = seq, context_ids) do
    if apc_school?(scope) and not Lock.not_started?(seq) do
      texts = sequence_competences(scope, context_ids, [seq.id])
      Map.new(context_ids, &{&1, texts[{&1, seq.id}]})
    end
  end

  # The APC element is school-wide (the profile's bulletin elements), whatever the class.
  defp apc_school?(scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)
    :apc in BulletinTemplate.elements(profile.bulletin_elements)
  end

  defp competence_contexts(_scope, %TeachingContext{combined_course_id: nil} = ctx), do: [ctx]

  defp competence_contexts(scope, %TeachingContext{combined_course_id: course_id}),
    do: TeacherAssistant.Curriculum.contexts_of_course!(course_id, scope: scope)

  defp upsert_competences(scope, contexts, seq, text) do
    Enum.reduce_while(contexts, :ok, fn ctx, :ok ->
      SequenceCompetence
      |> Ash.Changeset.for_create(
        :upsert,
        %{teaching_context_id: ctx.id, sequence_id: seq.id, text: text},
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp remove_competences(scope, contexts, seq) do
    SequenceCompetence
    |> Ash.Query.for_read(
      :for_contexts,
      %{context_ids: Enum.map(contexts, & &1.id), sequence_ids: [seq.id]},
      scope: scope
    )
    |> Ash.read!()
    |> Enum.reduce_while(:ok, fn row, :ok ->
      case Ash.destroy(row, scope: scope) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # --- Assessments -----------------------------------------------------------

  def create_assessment(%Scope{} = scope, %TeachingContext{} = ctx, %Sequence{id: seq_id}, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:sequence_id, seq_id)

    Assessment
    |> Ash.Changeset.for_create(:create, attrs, scope: scope)
    |> Ash.create()
  end

  def list_assessments(
        %Scope{} = scope,
        %TeachingContext{id: ctx_id},
        %Sequence{id: seq_id}
      ) do
    Assessment
    |> Ash.Query.for_read(
      :for_context_and_sequence,
      %{
        teaching_context_id: ctx_id,
        sequence_id: seq_id
      },
      scope: scope
    )
    |> Ash.read!()
  end

  @doc """
  Per-séquence assessments for a `CombinedCourse`, one teacher-facing column
  per label backed by one real `Assessment` per member class. See the
  `:combined_for` action on `TeacherAssistant.Academics.Assessment` for the
  full contract. Returns the list of column maps.
  """
  def combined_assessments_for(%Scope{} = scope, %CombinedCourse{} = course, %Sequence{} = seq) do
    Assessment
    |> Ash.ActionInput.for_action(:combined_for, %{course: course, sequence: seq}, scope: scope)
    |> Ash.run_action()
    |> case do
      {:ok, entries} -> entries
      # A refused actor sees no columns, like any policy-filtered read.
      {:error, %Ash.Error.Forbidden{}} -> []
    end
  end

  @doc """
  Creates one `Assessment{label, sequence}` per member context of a
  `CombinedCourse`, atomically. Returns `{:ok, [%Assessment{}, ...]}` or
  `{:error, reason}`.
  """
  def create_combined_assessment(
        %Scope{} = scope,
        %CombinedCourse{} = course,
        %Sequence{} = seq,
        attrs
      ) do
    label = Map.get(attrs, :label) || Map.get(attrs, "label")

    args = %{
      course: course,
      sequence: seq,
      label: label,
      assessment_type_id: Map.get(attrs, :assessment_type_id),
      max_score: Map.get(attrs, :max_score)
    }

    Assessment
    |> Ash.ActionInput.for_action(:create_combined, args, scope: scope)
    |> Ash.run_action()
  end

  @doc """
  Deletes an assessment created by mistake: all the given rows (a combined course's
  column is one per member class) or none. Refused while any of them has a mark,
  an absence included (`{:error, :has_marks}`); the destroy itself refuses a locked
  séquence or another teacher's course.
  """
  def delete_assessments(%Scope{} = scope, assessments) when is_list(assessments) do
    ids = Enum.map(assessments, & &1.id)

    TeacherAssistant.Repo.transaction(fn ->
      if Mark |> Ash.Query.filter(assessment_id in ^ids) |> Ash.exists?(scope: scope),
        do: TeacherAssistant.Repo.rollback(:has_marks)

      Enum.each(assessments, fn a ->
        with {:error, error} <- Ash.destroy(a, scope: scope),
             do: TeacherAssistant.Repo.rollback(error)
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Renames an assessment or changes its maximum: all the given rows (a combined
  course's column is one per member class) or none. A maximum under a mark
  already entered is refused (`{:error, :marks_above_max}`); the update itself
  refuses a locked séquence or another teacher's course.
  """
  def update_assessments(%Scope{} = scope, assessments, attrs)
      when is_list(assessments) and is_map(attrs) do
    ids = Enum.map(assessments, & &1.id)

    TeacherAssistant.Repo.transaction(fn ->
      with %{max_score: max} when not is_nil(max) <- attrs,
           {:ok, max} <- Ash.Type.cast_input(:decimal, max),
           true <- marks_above?(scope, ids, max),
           do: TeacherAssistant.Repo.rollback(:marks_above_max)

      Enum.each(assessments, fn a ->
        with {:error, error} <- Ash.update(a, attrs, scope: scope),
             do: TeacherAssistant.Repo.rollback(error)
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp marks_above?(scope, ids, max) do
    Mark
    |> Ash.Query.filter(assessment_id in ^ids and score > ^max)
    |> Ash.exists?(scope: scope)
  end

  @doc """
  `%{assessment_id => MapSet of student ids}`: who has a mark (an absence
  included) on each given assessment — one read, whatever their number.
  """
  def marked_students(%Scope{}, []), do: %{}

  def marked_students(%Scope{} = scope, assessments) when is_list(assessments) do
    ids = Enum.map(assessments, & &1.id)
    empty = Map.new(ids, &{&1, MapSet.new()})

    Mark
    |> Ash.Query.filter(assessment_id in ^ids)
    |> Ash.Query.select([:assessment_id, :student_id])
    |> Ash.read!(scope: scope)
    |> Enum.reduce(empty, fn m, acc ->
      Map.update!(acc, m.assessment_id, &MapSet.put(&1, m.student_id))
    end)
  end

  def fetch_owned_assessment(%Scope{} = scope, id) do
    case Ash.get(Assessment, id, scope: scope) do
      {:ok, assessment} -> {:ok, assessment}
      _ -> {:error, :not_found}
    end
  end

  # --- Séquence entry tracking (spec F) ---------------------------------------

  @doc """
  The classes × subjects mark-entry grid of a séquence, with its KPIs. See
  `TeacherAssistant.Academics.EntryProgress.grid/3`.
  """
  def sequence_entry_grid(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq),
    do: EntryProgress.grid(scope, year, seq)

  # --- Teacher statistics (spec audit follow-ups A4) ---------------------------

  @doc """
  One course's statistics for a séquence, a trimester or the year. See
  `TeacherAssistant.Academics.TeacherStatistics.course/3`.
  """
  def course_statistics(%Scope{} = scope, ctx, period),
    do: TeacherAssistant.Academics.TeacherStatistics.course(scope, ctx, period)

  @doc """
  A teacher's statistics table for a period, a row per course (and per class of a
  combined course). See `TeacherAssistant.Academics.TeacherStatistics.table/3`.
  """
  def teacher_statistics(%Scope{} = scope, teacher, period),
    do: TeacherAssistant.Academics.TeacherStatistics.table(scope, teacher, period)

  @doc "The séquence shown by default on `today` (current, else last started, else first)."
  def default_sequence(sequences, %Date{} = today),
    do: EntryProgress.default_sequence(sequences, today)

  # --- Entry reminders (spec KLM8, N06) ------------------------------------------

  @doc """
  « Relancer »: logs a reminder for the course and séquence and notifies the course's
  teacher. Once per course, séquence and school day: a second one is
  `{:error, :already_reminded}` and notifies nobody.
  """
  def remind_entry(%Scope{} = scope, %Sequence{} = seq, teaching_context_id) do
    with {:ok, tc} <-
           Ash.get(TeachingContext, teaching_context_id,
             scope: scope,
             load: [:class_group, :catalog_subject]
           ) do
      remind_in_transaction(scope, seq, tc)
    end
  end

  # The reminder row and its notification together, as `SchoolLife` does for roll
  # calls: a failed delivery leaves no « Relancé » that would refuse every retry
  # that day. A refused create rolls the transaction back with its bare error, so
  # « already reminded today » (the unique index) is recognised afterwards.
  defp remind_in_transaction(scope, seq, tc) do
    TeacherAssistant.Repo.transaction(fn ->
      case create_reminder(scope, seq, tc) do
        {:ok, reminder} ->
          Notifications.deliver(
            scope,
            :entry_reminder,
            others(scope, [tc.teacher_user_id]),
            %{
              subject: (tc.catalog_subject && tc.catalog_subject.name) || tc.subject,
              class: tc.class_group && tc.class_group.label,
              sequence: seq.number
            },
            "/teacher/contexts/#{tc.id}/marks?seq=#{seq.id}"
          )

          reminder

        {:error, reason} ->
          TeacherAssistant.Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, reminder} ->
        {:ok, reminder}

      {:error, :already_reminded} ->
        {:error, :already_reminded}

      {:error, error} ->
        error = Ash.Error.to_error_class(error)
        if reminded_today?(error), do: {:error, :already_reminded}, else: {:error, error}
    end
  end

  @doc "« Relancer tous les retards »: reminds every lagging course; the count sent."
  def remind_late(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq) do
    scope
    |> sequence_entry_grid(year, seq)
    |> Map.fetch!(:late)
    |> remind_courses(scope, seq)
  end

  @doc "Reminds each lagging course of one teacher; the count sent (once per course and day)."
  def remind_teacher(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq, teacher_id),
    do: remind_teachers(scope, year, seq, [teacher_id])

  @doc """
  « Relancer la sélection »: reminds each lagging course of the given teachers (ids
  that are not late are ignored), reading the grid once; the count sent (once per
  course and day).
  """
  def remind_teachers(%Scope{}, %AcademicYear{}, %Sequence{}, []), do: {:ok, 0}

  def remind_teachers(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq, teacher_ids) do
    ids = MapSet.new(teacher_ids)

    scope
    |> sequence_entry_grid(year, seq)
    |> Map.fetch!(:late)
    |> Enum.filter(&MapSet.member?(ids, &1.teacher_id))
    |> remind_courses(scope, seq)
  end

  defp remind_courses(late, scope, seq) do
    tc_ids = for %{courses: courses} <- late, %{tc_id: id} <- courses, do: id
    {:ok, Enum.count(tc_ids, &match?({:ok, _}, remind_entry(scope, seq, &1)))}
  end

  @doc "The latest reminder day of each course reminded for the séquence."
  def reminder_dates(%Scope{} = scope, %Sequence{id: seq_id}) do
    EntryReminder
    |> Ash.Query.filter(sequence_id == ^seq_id)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.teaching_context_id, & &1.sent_on)
    |> Map.new(fn {tc_id, days} -> {tc_id, Enum.max(days, Date)} end)
  end

  defp create_reminder(scope, seq, tc) do
    EntryReminder
    |> Ash.Changeset.for_create(
      :create,
      %{teaching_context_id: tc.id, sequence_id: seq.id},
      scope: scope
    )
    |> Ash.create()
    |> case do
      {:error, error} ->
        if reminded_today?(error), do: {:error, :already_reminded}, else: {:error, error}

      ok ->
        ok
    end
  end

  defp reminded_today?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &reminded_today?/1)

  defp reminded_today?(%Ash.Error.Changes.InvalidAttribute{private_vars: vars}) do
    constraint = vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, "once_a_day")
  end

  defp reminded_today?(_error), do: false

  # --- Assessment types (spec D2b-2) -----------------------------------------------

  def list_assessment_types(%Scope{} = scope) do
    AssessmentType
    |> Ash.Query.sort(position: :asc, name: :asc)
    |> Ash.Query.load(:usage_count)
    |> Ash.read!(scope: scope)
  end

  def create_assessment_type(%Scope{} = scope, attrs) do
    position = length(list_assessment_types(scope))

    AssessmentType
    |> Ash.Changeset.for_create(:create, Map.put_new(attrs, :position, position), scope: scope)
    |> Ash.create()
  end

  def update_assessment_type(%Scope{} = scope, %AssessmentType{} = type, attrs) do
    type |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  @doc """
  Saves several types at once (the settings list's one save), all or nothing:
  `changes` is `[{%AssessmentType{}, %{name: …, default_weight: …}}]`. A refused
  row (forbidden, duplicate name) rolls every write back.
  """
  def update_assessment_types(%Scope{} = scope, changes) when is_list(changes) do
    Ash.transact(AssessmentType, fn ->
      Enum.reduce_while(changes, :ok, fn {type, attrs}, :ok ->
        case update_assessment_type(scope, type, attrs) do
          {:ok, _} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc "Deletes a type no assessment uses; a used type is kept (`{:error, :in_use}`)."
  def delete_assessment_type(%Scope{} = scope, %AssessmentType{} = type) do
    case Ash.load!(type, :usage_count, scope: scope) do
      %{usage_count: 0} -> Ash.destroy(type, scope: scope)
      _ -> {:error, :in_use}
    end
  end

  # --- Marks -----------------------------------------------------------------

  @doc """
  Creates or updates a `Mark` per `(assessment, student)` in a single
  transaction. A `nil` score is "not entered" and removes any existing mark;
  `status: :absent | :excused` records an absence (with no score). Scores are
  range-checked against the assessment's `max_score` before anything is
  written; an out-of-range score persists nothing (`{:error, :out_of_range}`).
  """
  def upsert_marks(
        %Scope{} = scope,
        %Assessment{id: assessment_id, max_score: max_score},
        entries
      ) do
    if Enum.all?(entries, &score_in_range?(&1, max_score)) do
      entries
      |> Enum.map(fn entry ->
        %{
          assessment_id: assessment_id,
          student_id: entry.student_id,
          score: Map.get(entry, :score),
          status: Map.get(entry, :status)
        }
      end)
      |> run_upsert_all(scope)
    else
      {:error, :out_of_range}
    end
  end

  def list_marks(%Scope{} = scope, %Assessment{id: assessment_id}) do
    Mark
    |> Ash.Query.for_read(:for_assessment, %{assessment_id: assessment_id}, scope: scope)
    |> Ash.read!()
  end

  def list_marks_for_context_sequence(
        %Scope{} = scope,
        %TeachingContext{id: ctx_id},
        %Sequence{
          id: seq_id
        }
      ) do
    assessment_ids =
      Assessment
      |> Ash.Query.for_read(
        :for_context_and_sequence,
        %{
          teaching_context_id: ctx_id,
          sequence_id: seq_id
        },
        scope: scope
      )
      |> Ash.read!()
      |> Enum.map(& &1.id)

    Mark
    |> Ash.Query.for_read(:for_assessments, %{assessment_ids: assessment_ids}, scope: scope)
    |> Ash.read!()
  end

  @doc "The marks journal, newest first (spec D3a). Admins only; anyone else gets []."
  def list_mark_events(%Scope{} = scope, opts \\ []) do
    MarkEvent
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(Keyword.get(opts, :limit, 200))
    |> Ash.Query.load([:actor, :student, assessment: [:teaching_context]])
    |> Ash.read(scope: scope)
    |> case do
      {:ok, events} -> events
      {:error, %Ash.Error.Forbidden{}} -> []
    end
  end

  # --- Correction requests (spec D3c) -----------------------------------------

  @correction_loads [
    :student,
    :requester,
    :decider,
    assessment: [:sequence, teaching_context: [:class_group]]
  ]

  @doc "Asks to change a locked mark (the course's teacher only); notifies the deciders."
  def request_correction(%Scope{} = scope, attrs) do
    with {:ok, correction} <-
           MarkCorrection
           |> Ash.Changeset.for_create(:request, attrs, scope: scope)
           |> Ash.create(load: @correction_loads) do
      Notifications.deliver(
        scope,
        :correction_requested,
        others(scope, Notifications.admin_ids(scope)),
        correction
        |> correction_params()
        |> Map.put(:teacher, user_name(correction.requester))
        |> Map.put(:change, correction_change(correction)),
        "/school/corrections/review"
      )

      {:ok, correction}
    end
  end

  @doc """
  Assessments whose marks the scope may ask to correct: the scope's own courses' in the
  current year, once locked. Loads the class and the séquence.
  """
  def list_correctable_assessments(%Scope{current_user: %{id: user_id}} = scope) do
    year_id = scope.current_academic_year && scope.current_academic_year.id

    Assessment
    |> Ash.Query.filter(
      teaching_context.teacher_user_id == ^user_id and
        sequence.term.academic_year_id == ^year_id
    )
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.load(sequence: [:grade_entry_deadline], teaching_context: [:class_group])
    |> Ash.read!(scope: scope)
    |> Enum.filter(&TeacherAssistant.Academics.Lock.locked?(&1.sequence))
  end

  @doc """
  The student's séquence average in the correction's subject, before and after the
  requested value: `{before, after}` (rounded as the school rounds; nil = none yet).
  """
  def correction_averages(%Scope{} = scope, %MarkCorrection{} = correction) do
    %{assessment: %{teaching_context: tc} = assessment, student_id: student_id} = correction
    seq = %Sequence{id: assessment.sequence_id}
    rules = grading_rules(scope)

    weights =
      scope
      |> list_assessments(tc, seq)
      |> Map.new(&{&1.id, %{weight: &1.weight, max_score: &1.max_score}})

    marks =
      for m <- list_marks_for_context_sequence(scope, tc, seq),
          m.student_id == student_id,
          do: %{assessment_id: m.assessment_id, score: m.score, status: m.status}

    requested =
      Enum.reject(marks, &(&1.assessment_id == assessment.id)) ++
        if(correction.requested_status,
          do: [
            %{
              assessment_id: assessment.id,
              score: correction.requested_score,
              status: correction.requested_status
            }
          ],
          else: []
        )

    average = &GradingRules.round_average(Marks.subject_average(&1, weights, rules), rules)
    {average.(marks), average.(requested)}
  end

  @doc """
  Approves a pending request: writes the mark, unless it changed since ("stale").
  `note` is the admin's optional word to the teacher.
  """
  def approve_correction(%Scope{} = scope, %MarkCorrection{} = correction, note \\ nil),
    do: decide_correction(scope, correction, :approve, note)

  @doc """
  Approves each of `corrections` in turn — one decision per request, each atomic and
  traced like `approve_correction/3`. Returns `{approved, failed}` counts (a request
  whose mark changed since it was asked fails and stays pending).
  """
  def approve_corrections(%Scope{} = scope, corrections, note \\ nil) do
    Enum.reduce(corrections, {0, 0}, fn correction, {approved, failed} ->
      case approve_correction(scope, correction, note) do
        {:ok, _} -> {approved + 1, failed}
        {:error, _} -> {approved, failed + 1}
      end
    end)
  end

  @doc "Refuses a pending request; the mark is untouched. `note` as in `approve_correction/3`."
  def refuse_correction(%Scope{} = scope, %MarkCorrection{} = correction, note \\ nil),
    do: decide_correction(scope, correction, :refuse, note)

  defp decide_correction(scope, correction, action, note) do
    with {:ok, decided} <-
           correction
           |> Ash.Changeset.for_update(action, %{decision_note: note}, scope: scope)
           |> Ash.update(load: @correction_loads) do
      Notifications.deliver(
        scope,
        :correction_decided,
        others(scope, [decided.requester_user_id]),
        Map.put(correction_params(decided), :decision, decided.status),
        "/school/corrections"
      )

      {:ok, decided}
    end
  end

  # Spec KLM8: the short strings a correction notice shows.
  defp correction_params(%MarkCorrection{student: student, assessment: assessment}) do
    tc = assessment.teaching_context

    %{
      student: student.full_name,
      subject: tc.subject,
      class: tc.class_group && tc.class_group.label,
      assessment: assessment.label
    }
  end

  defp correction_change(%MarkCorrection{} = c) do
    "#{MarkEntry.format(c.current_status, c.current_score)} → " <>
      MarkEntry.format(c.requested_status, c.requested_score)
  end

  # Nobody is notified of their own action; a requester gone from the school (nil) is skipped.
  defp others(%Scope{current_user: %{id: actor_id}}, ids),
    do: Enum.reject(ids, &(is_nil(&1) or &1 == actor_id))

  defp user_name(nil), do: ""
  defp user_name(user), do: User.display_name(user)

  @doc """
  The display name of the school's Censeur, to name them on a request; nil when the
  school has none or several (`:vice_principal` members).
  """
  def censeur_name(%Scope{} = scope) do
    scope
    |> TeacherAssistant.Accounts.list_members()
    |> Enum.filter(&(:vice_principal in &1.roles))
    |> case do
      [member] -> User.display_name(member.user)
      _none_or_several -> nil
    end
  end

  @doc "The scope's own requests, newest first."
  def list_my_corrections(%Scope{current_user: %{id: user_id}} = scope) do
    MarkCorrection
    |> Ash.Query.filter(requester_user_id == ^user_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(@correction_loads)
    |> Ash.read!(scope: scope)
  end

  @doc "Requests awaiting a decision (`:pending`, oldest first) or decided (newest first)."
  def list_corrections(%Scope{} = scope, :pending) do
    MarkCorrection
    |> Ash.Query.filter(status == :pending)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.load(@correction_loads)
    |> Ash.read!(scope: scope)
  end

  def list_corrections(%Scope{} = scope, :decided) do
    MarkCorrection
    |> Ash.Query.filter(status != :pending)
    |> Ash.Query.sort(decided_at: :desc)
    |> Ash.Query.load(@correction_loads)
    |> Ash.read!(scope: scope)
  end

  @doc "Requests awaiting a decision, as the scope may see them."
  def pending_corrections_count(%Scope{} = scope) do
    MarkCorrection |> Ash.Query.filter(status == :pending) |> Ash.count!(scope: scope)
  end

  @doc "The scope's own requests decided since they last looked (menu badge)."
  def unseen_decisions_count(%Scope{current_user: %{id: user_id}} = scope) do
    MarkCorrection
    |> Ash.Query.filter(requester_user_id == ^user_id and status != :pending and is_nil(seen_at))
    |> Ash.count!(scope: scope)
  end

  @doc "Marks the scope's decided requests as seen."
  def mark_corrections_seen(%Scope{current_user: %{id: user_id}} = scope) do
    MarkCorrection
    |> Ash.Query.filter(requester_user_id == ^user_id and status != :pending and is_nil(seen_at))
    |> Ash.bulk_update!(:mark_seen, %{}, scope: scope, strategy: [:atomic, :stream])

    :ok
  end

  @doc "Whether the scope decides correction requests (admin axis: Proviseur, Censeur)."
  def can_decide_corrections?(%Scope{current_user: user, current_workspace: %{id: ws_id}}),
    do: TeacherAssistant.Accounts.Checks.SchoolRole.holds?(user, ws_id, :admin)

  def can_decide_corrections?(%Scope{}), do: false

  # The `:upsert_all` action does the all-or-nothing transactional upsert and
  # returns `:ok`; unwrap it back to the bare `:ok` the callers expect.
  defp run_upsert_all(marks, %Scope{} = scope) do
    Mark
    |> Ash.ActionInput.for_action(:upsert_all, %{marks: marks}, scope: scope)
    |> Ash.run_action()
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A mark is valid when absent (nil) or within 0..max_score inclusive. Callers
  # pass a `%Decimal{}` or nil; anything else is left to the resource layer.
  defp score_in_range?(entry, max_score) do
    case Map.get(entry, :score) do
      nil ->
        true

      %Decimal{} = s ->
        Decimal.compare(s, 0) != :lt and Decimal.compare(s, max_score) != :gt

      _ ->
        true
    end
  end

  # --- Grading rules (spec D2b-1) -----------------------------------------------

  @doc "The school's averaging rules, from its profile."
  def grading_rules(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    %GradingRules{
      trimester: profile.trimester_average_rule,
      annual: profile.annual_average_rule,
      rounding: profile.average_rounding,
      shared_ranks?: profile.shared_ranks?,
      absence: profile.absence_rule,
      appreciation_bands: profile.appreciation_bands,
      felicitations_min: profile.felicitations_min,
      encouragements_min: profile.encouragements_min,
      tableau_honneur_min: profile.tableau_honneur_min,
      avertissement_travail_below: profile.avertissement_travail_below,
      blame_travail_below: profile.blame_travail_below,
      distinctions_require_all_passed?: profile.distinctions_require_all_passed?,
      distinctions_require_conduct?: profile.distinctions_require_conduct?
    }
  end

  @rule_fields %{
    "trimester_average_rule" => {:trimester_average_rule, TrimesterAverageRule},
    "annual_average_rule" => {:annual_average_rule, AnnualAverageRule},
    "average_rounding" => {:average_rounding, AverageRounding},
    "absence_rule" => {:absence_rule, AbsenceRule}
  }

  @doc """
  Saves averaging rules from string params. Every key must be a known rule and every
  value one of its options (matched, never converted with `String.to_atom`); otherwise
  `{:error, :invalid_rule}` and nothing is written. Authorization is the school
  profile's update policy.
  """
  def update_grading_rules(%Scope{} = scope, %{} = params) do
    with {:ok, attrs} <- parse_rule_params(params),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end

  @doc "Sets the school's default maximum mark for new assessments (a positive number)."
  def update_default_max_score(%Scope{} = scope, value) when is_binary(value) do
    with {:ok, max} <- TeacherAssistant.Curriculum.parse_coefficient(value),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, %{default_max_score: max},
        scope: scope
      )
    else
      :error -> {:error, :invalid_max}
      other -> other
    end
  end

  @doc "Sets the school's grade-entry grace days (an integer in 0..30, spec D3b)."
  def update_entry_grace_days(%Scope{} = scope, value) when is_binary(value) do
    with {days, ""} <- Integer.parse(String.trim(value)),
         {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, %{entry_grace_days: days},
        scope: scope
      )
    else
      :error -> {:error, :invalid_days}
      {_days, _rest} -> {:error, :invalid_days}
      other -> other
    end
  end

  @doc """
  Saves the grade-entry settings together — the default maximum mark and the grace
  days — in one profile update. `{:error, {:invalid, fields}}` names the fields that
  do not parse (nothing is saved); the profile validation bounds the days (0..30).
  """
  def update_entry_settings(%Scope{} = scope, %{} = params) do
    max = TeacherAssistant.Curriculum.parse_coefficient(params["default_max_score"] || "")
    days = parse_grace_days(params["entry_grace_days"] || "")

    case {max, days} do
      {{:ok, max}, {:ok, days}} ->
        with {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
          TeacherAssistant.Accounts.update_school_profile(
            profile,
            %{default_max_score: max, entry_grace_days: days},
            scope: scope
          )
        end

      _ ->
        {:error,
         {:invalid,
          for({field, :error} <- [default_max_score: max, entry_grace_days: days], do: field)}}
    end
  end

  defp parse_grace_days(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {days, ""} -> {:ok, days}
      _ -> :error
    end
  end

  defp parse_grace_days(_), do: :error

  # --- Appreciations and distinctions (spec I1) -----------------------------------

  @threshold_fields ~w(felicitations_min encouragements_min tableau_honneur_min avertissement_travail_below blame_travail_below)a
  @distinction_gates ~w(distinctions_require_all_passed? distinctions_require_conduct?)a

  @doc """
  Saves the school's appreciation scale from `[%{from: "0", label: "…"}, …]`, lowest
  band first; bounds accept a comma. `{:error, :invalid_number}` when a bound is not a
  number; the profile validation enforces the scale's rules.
  """
  def update_appreciation_bands(%Scope{} = scope, rows) when is_list(rows) do
    with {:ok, bands} <- parse_bands(rows) do
      update_profile(scope, %{appreciation_bands: bands})
    end
  end

  @doc "Goes back to the default appreciation scale."
  def reset_appreciation_bands(%Scope{} = scope),
    do: update_profile(scope, %{appreciation_bands: nil})

  @doc """
  Saves the distinction thresholds and gates from string params. An empty threshold
  switches it off; a missing gate is false; a non-number gives `{:error, :invalid_number}`.
  """
  def update_distinction_rules(%Scope{} = scope, %{} = params) do
    with {:ok, thresholds} <- parse_thresholds(params) do
      gates = Map.new(@distinction_gates, &{&1, Map.get(params, Atom.to_string(&1)) == "true"})
      update_profile(scope, Map.merge(thresholds, gates))
    end
  end

  # --- Passage rules (spec I4) ------------------------------------------------------

  @passage_decimals ~w(passage_min rachat_min exclusion_below)a
  @passage_toggles ~w(one_repeat_per_cycle? exclusion_on_conduct?)a

  @doc "The school's passage rules, from its profile."
  def passage_rules(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    %TeacherAssistant.Academics.PassageRules{
      passage_min: profile.passage_min,
      rachat_min: profile.rachat_min,
      exclusion_below: profile.exclusion_below,
      one_repeat_per_cycle?: profile.one_repeat_per_cycle?,
      exclusion_on_conduct?: profile.exclusion_on_conduct?,
      exclusion_absence_hours: profile.exclusion_absence_hours
    }
  end

  @doc """
  Saves the passage rules from string params: an empty rachat, exclusion or hours value
  switches that rule off; the passing average is required; a missing toggle is false.
  """
  def update_passage_rules(%Scope{} = scope, %{} = params) do
    with {:ok, decimals} <- parse_passage_decimals(params),
         {:ok, hours} <- parse_hours(Map.get(params, "exclusion_absence_hours", "")) do
      toggles = Map.new(@passage_toggles, &{&1, Map.get(params, Atom.to_string(&1)) == "true"})

      update_profile(
        scope,
        decimals |> Map.merge(toggles) |> Map.put(:exclusion_absence_hours, hours)
      )
    end
  end

  defp parse_passage_decimals(params) do
    Enum.reduce_while(@passage_decimals, {:ok, %{}}, fn field, {:ok, acc} ->
      case {field, parse_score(Map.get(params, Atom.to_string(field), ""))} do
        {:passage_min, {:ok, nil}} -> {:halt, {:error, :invalid_number}}
        {_, {:ok, value}} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {_, :error} -> {:halt, {:error, :invalid_number}}
      end
    end)
  end

  defp parse_hours(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_hours(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {hours, ""} -> {:ok, hours}
      _ -> {:error, :invalid_number}
    end
  end

  # --- Report card template (spec I5) ---------------------------------------------

  @doc "The school's report card template settings, defaults applied."
  def bulletin_settings(%Scope{} = scope) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    %{
      language: profile.bulletin_language,
      elements: TeacherAssistant.Academics.BulletinTemplate.elements(profile.bulletin_elements),
      grade_scale: TeacherAssistant.Academics.BulletinTemplate.grade_scale(profile.grade_scale),
      custom_scale?: profile.grade_scale not in [nil, []]
    }
  end

  @doc """
  Saves the language mode and the elements shown from string params. Values are
  matched against the enums (never `String.to_atom`); blanks are dropped, duplicates
  removed, order kept. `{:error, :invalid_setting}` on anything unknown.
  """
  def update_bulletin_settings(%Scope{} = scope, %{} = params) do
    with {:ok, language} <-
           enum_value(TeacherAssistant.Academics.BulletinLanguage, params["language"]),
         {:ok, elements} <- parse_elements(Map.get(params, "elements", [])) do
      update_profile(scope, %{bulletin_language: language, bulletin_elements: elements})
    end
  end

  @doc """
  Saves the grade scale from `[%{from: "0", letter: "F", remark: "Fail"}, …]`, lowest
  band first; bounds accept a comma. `{:error, :invalid_number}` when a bound is not a
  number; the profile validation enforces the scale's rules.
  """
  def update_grade_scale(%Scope{} = scope, rows) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case parse_score(row.from) do
        {:ok, %Decimal{} = from} ->
          band = %{
            from: from,
            letter: String.trim(row.letter || ""),
            remark: String.trim(row.remark || "")
          }

          {:cont, {:ok, [band | acc]}}

        _ ->
          {:halt, {:error, :invalid_number}}
      end
    end)
    |> case do
      {:ok, bands} -> update_profile(scope, %{grade_scale: Enum.reverse(bands)})
      error -> error
    end
  end

  @doc "Goes back to the default grade scale."
  def reset_grade_scale(%Scope{} = scope), do: update_profile(scope, %{grade_scale: nil})

  defp enum_value(enum, value) when is_binary(value) do
    case Enum.find(enum.values(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_setting}
      atom -> {:ok, atom}
    end
  end

  defp enum_value(_enum, _value), do: {:error, :invalid_setting}

  defp parse_elements(values) when is_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case enum_value(TeacherAssistant.Academics.BulletinElement, value) do
        {:ok, atom} -> {:cont, {:ok, [atom | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp parse_elements(_), do: {:error, :invalid_setting}

  defp update_profile(scope, attrs) do
    with {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end

  defp parse_bands(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case parse_score(row.from) do
        {:ok, %Decimal{} = from} ->
          band = %{from: from, label: String.trim(row.label || ""), code: band_code(row)}
          {:cont, {:ok, acc ++ [band]}}

        _ ->
          {:halt, {:error, :invalid_number}}
      end
    end)
  end

  # Spec bulletin v2: a blank « cote » is no code.
  defp band_code(row) do
    case String.trim(Map.get(row, :code) || "") do
      "" -> nil
      code -> String.upcase(code)
    end
  end

  defp parse_thresholds(params) do
    Enum.reduce_while(@threshold_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case parse_score(Map.get(params, Atom.to_string(field), "")) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        :error -> {:halt, {:error, :invalid_number}}
      end
    end)
  end

  # "" → nil; "9,5" → 9.5; anything else not a finite number (incl. "NaN", "inf") → :error. Range checks are the
  # profile validation's job.
  defp parse_score(%Decimal{} = d), do: {:ok, d}

  defp parse_score(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") do
      "" ->
        {:ok, nil}

      text ->
        case Decimal.parse(text) do
          # NaN and ±Infinity carry an atom coefficient.
          {%Decimal{coef: coef} = dec, ""} when is_integer(coef) -> {:ok, dec}
          _ -> :error
        end
    end
  end

  defp parse_score(nil), do: {:ok, nil}
  defp parse_score(_), do: :error

  defp parse_rule_params(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case parse_rule(key, value) do
        {:ok, field, parsed} -> {:cont, {:ok, Map.put(acc, field, parsed)}}
        :error -> {:halt, {:error, :invalid_rule}}
      end
    end)
  end

  defp parse_rule("shared_ranks?", "true"), do: {:ok, :shared_ranks?, true}
  defp parse_rule("shared_ranks?", "false"), do: {:ok, :shared_ranks?, false}

  defp parse_rule(key, value) do
    with {field, enum} <- Map.get(@rule_fields, key),
         %{} = by_string <- Map.new(enum.values(), &{Atom.to_string(&1), &1}),
         {:ok, parsed} <- Map.fetch(by_string, value) do
      {:ok, field, parsed}
    else
      _ -> :error
    end
  end

  # --- Class results / bulletins ---------------------------------------------
  # Data gathering + orchestration for whole-class bulletins. The arithmetic
  # (per-subject averages, coefficient weighting, ranking, distinctions) lives
  # in the pure, deterministic `Academics.Marks` / `Academics.Bulletins`
  # modules and is reused verbatim so the numbers never drift. This mirrors the
  # `Attendance.class_conduct/3` / `Discipline.class_discipline/3` shape: a thin
  # domain function over authorized reads + a pure computation module.

  @doc """
  Bulletin input for a class + séquence: one entry per school teaching context of
  the class (subject × class, assigned teacher), shaped for `Bulletins.compile/2`.
  """
  def class_subjects(%Scope{} = scope, %ClassGroup{} = cg, %Sequence{id: seq_id} = seq) do
    scope |> class_subjects_by_sequence(cg, [seq]) |> Map.fetch!(seq_id)
  end

  @doc """
  `class_subjects/3` for several séquences of the class at once:
  `%{sequence_id => subjects}`. A fixed number of reads (courses, assessments,
  marks, exemptions), whatever the number of subjects or séquences.
  """
  def class_subjects_by_sequence(%Scope{} = scope, %ClassGroup{} = cg, seqs) do
    contexts = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
    ctx_ids = Enum.map(contexts, & &1.id)
    assessments = class_assessments(scope, ctx_ids, Enum.map(seqs, & &1.id))
    marks_by_assessment = scope |> class_marks(assessments) |> Enum.group_by(& &1.assessment_id)
    exempt = TeacherAssistant.Curriculum.exempt_student_ids_by_context(scope, ctx_ids)

    assessments_by =
      Enum.group_by(assessments, &{&1.teaching_context_id, &1.sequence_id})

    Map.new(seqs, fn seq ->
      {seq.id,
       Enum.map(contexts, fn tc ->
         tc_assessments = Map.get(assessments_by, {tc.id, seq.id}, [])

         %{
           context_id: tc.id,
           label: tc.subject,
           code: tc.catalog_subject.code,
           coefficient: tc.effective_coefficient,
           group: tc.catalog_subject.bulletin_group,
           position: tc.catalog_subject.position,
           assessments_by_id:
             Map.new(tc_assessments, fn a ->
               {a.id, %{weight: a.weight, max_score: a.max_score}}
             end),
           marks:
             Enum.flat_map(tc_assessments, fn a ->
               marks_by_assessment
               |> Map.get(a.id, [])
               |> Enum.map(fn m ->
                 %{
                   student_id: m.student_id,
                   assessment_id: m.assessment_id,
                   score: m.score,
                   status: m.status
                 }
               end)
             end),
           exempt: Map.fetch!(exempt, tc.id)
         }
       end)}
    end)
  end

  defp class_assessments(_scope, [], _seq_ids), do: []
  defp class_assessments(_scope, _ctx_ids, []), do: []

  defp class_assessments(scope, ctx_ids, seq_ids) do
    Assessment
    |> Ash.Query.filter(teaching_context_id in ^ctx_ids and sequence_id in ^seq_ids)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(scope: scope)
  end

  defp class_marks(_scope, []), do: []

  defp class_marks(scope, assessments) do
    Mark
    |> Ash.Query.for_read(:for_assessments, %{assessment_ids: Enum.map(assessments, & &1.id)},
      scope: scope
    )
    |> Ash.read!()
  end

  @doc """
  Compiled class bulletins for a séquence, or nil when the class has no subjects.
  """
  def class_results(%Scope{} = scope, %ClassGroup{} = cg, %Sequence{} = seq) do
    case class_subjects(scope, cg, seq) do
      [] ->
        nil

      subjects ->
        rules = grading_rules(scope)
        students = bulletin_students(scope, cg, {:sequence, seq}, rules)
        Bulletins.compile(students, subjects, rules)
    end
  end

  @doc """
  Compiled class bulletins for a period (`{:sequence, seq}` / `{:trimester, term}` /
  `{:annual, year}`), or nil when the class has no subjects. Trimester/annual
  averages are the mean of the constituent séquence subject-averages that exist.
  """
  def class_results_for_period(
        %Scope{} = scope,
        %ClassGroup{} = cg,
        {:sequence, %Sequence{} = seq}
      ) do
    class_results(scope, cg, seq)
  end

  def class_results_for_period(%Scope{} = scope, %ClassGroup{} = cg, {:trimester, %Term{} = term}) do
    seqs = Enum.sort_by(term.sequences, & &1.position_in_term)
    period_result(scope, cg, {:trimester, term}, seqs, :sequences)
  end

  def class_results_for_period(
        %Scope{} = scope,
        %ClassGroup{} = cg,
        {:annual, %AcademicYear{} = year}
      ) do
    seqs = TeacherAssistant.Organization.list_sequences(scope, year)
    period_result(scope, cg, {:annual, year}, seqs, :trimesters)
  end

  @doc """
  The séquence marks of a class for the « relevé des notes » the Censeur prints so
  students check them: `seqs` side by side, no average and no rank. Each cell is the
  subject's séquence mark the bulletin uses (its evaluations weighted, rounded),
  `:absent` when the student missed every evaluation, `:exempt` for a
  subject they do not take, else `:blank` (nothing entered yet).

      %{subjects: [%{context_id, label, code}], students: [%{id, name, cells}]}

  `cells` are `%{{context_id, sequence_id} => cell}`; subjects come in bulletin order,
  students in roster order.
  """
  def mark_sheet(%Scope{} = scope, %ClassGroup{} = cg, seqs) do
    rules = grading_rules(scope)
    students = TeacherAssistant.Enrollment.list_students(scope, cg)
    by_seq = class_subjects_by_sequence(scope, cg, seqs)

    subjects =
      by_seq
      |> Map.values()
      |> List.first([])
      |> Enum.sort_by(&{BulletinGroup.rank(&1.group), &1.position, &1.label})

    # %{{context_id, sequence_id} => %{student_id => [mark]}}
    marks =
      for seq <- seqs, subj <- Map.fetch!(by_seq, seq.id), into: %{} do
        {{subj.context_id, seq.id}, {subj, Enum.group_by(subj.marks, & &1.student_id)}}
      end

    %{
      subjects: Enum.map(subjects, &Map.take(&1, [:context_id, :label, :code])),
      students:
        Enum.map(students, fn s ->
          cells =
            Map.new(marks, fn {key, {subj, by_student}} ->
              {key, sheet_cell(s.id, subj, Map.get(by_student, s.id, []), rules)}
            end)

          %{id: s.id, name: s.full_name, cells: cells}
        end)
    }
  end

  # Absent from every evaluation reads « Abs », even where the school counts an
  # absence as 0: the student checks what happened, not the arithmetic.
  defp sheet_cell(student_id, subj, marks, rules) do
    absent? = &(&1.status in [:absent, :excused])

    cond do
      MapSet.member?(subj.exempt, student_id) ->
        :exempt

      marks != [] and Enum.all?(marks, absent?) ->
        :absent

      true ->
        case Marks.subject_average(marks, subj.assessments_by_id, rules) do
          nil -> :blank
          avg -> {:mark, GradingRules.round_average(avg, rules)}
        end
    end
  end

  # The roster as bulletin inputs. With the conduct gate on (spec I1), each student
  # carries the period's note de conduite, read once for the class.
  defp bulletin_students(scope, cg, period, %GradingRules{distinctions_require_conduct?: true}) do
    conduct = TeacherAssistant.Discipline.class_discipline(scope, cg, period)

    scope
    |> TeacherAssistant.Enrollment.list_roster(cg)
    |> Enum.map(fn %{student: s, enrollment: e} ->
      note = conduct |> Map.get(e.id, %{}) |> Map.get(:note_de_conduite)
      %{id: s.id, sex: s.sex, name: s.full_name, conduct: note}
    end)
  end

  defp bulletin_students(scope, cg, _period, _rules) do
    scope
    |> TeacherAssistant.Enrollment.list_students(cg)
    |> Enum.map(fn s -> %{id: s.id, sex: s.sex, name: s.full_name} end)
  end

  # Builds a Bulletins result over a set of séquences. `component_kind` selects the
  # breakdown carried on each subject row: :sequences (per séquence, for trimester)
  # or :trimesters (per term, for annual).
  defp period_result(%Scope{} = scope, cg, period, seqs, component_kind) do
    rules = grading_rules(scope)
    students = bulletin_students(scope, cg, period, rules)

    subjects_by_seq = class_subjects_by_sequence(scope, cg, seqs)

    # per séquence: %{context_id => %{label, coefficient, per_student_avg}}
    per_seq =
      Enum.map(seqs, fn seq ->
        subjects =
          subjects_by_seq
          |> Map.fetch!(seq.id)
          |> Map.new(fn subj ->
            marks_by_student = Enum.group_by(subj.marks, & &1.student_id)

            psa =
              Map.new(students, fn s ->
                sm = Map.get(marks_by_student, s.id, [])

                {s.id,
                 GradingRules.round_average(
                   Marks.subject_average(sm, subj.assessments_by_id, rules),
                   rules
                 )}
              end)

            makeup =
              Map.new(students, fn s ->
                {s.id, Marks.makeup_pending?(Map.get(marks_by_student, s.id, []), rules)}
              end)

            {subj.context_id,
             %{
               label: subj.label,
               coefficient: subj.coefficient,
               group: subj.group,
               position: subj.position,
               per_student_avg: psa,
               makeup: makeup,
               exempt: subj.exempt
             }}
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
          meta = context_meta(per_seq, cid)

          per_student_precise =
            Map.new(students, fn s ->
              {s.id, period_mean(component_kind, per_seq, cid, s.id, rules)}
            end)

          per_student_avg =
            Map.new(per_student_precise, fn {id, mean} ->
              {id, GradingRules.round_average(mean, rules)}
            end)

          components =
            Map.new(students, fn s ->
              {s.id, build_components(component_kind, per_seq, cid, s.id, rules)}
            end)

          %{
            context_id: cid,
            label: meta.label,
            coefficient: meta.coefficient,
            group: meta.group,
            position: meta.position,
            per_student_avg: per_student_avg,
            per_student_precise: per_student_precise,
            components: components,
            exempt: meta.exempt,
            makeup_pending:
              Map.new(students, fn s ->
                {s.id,
                 Enum.any?(per_seq, fn {_seq, m} -> m[cid] != nil and m[cid].makeup[s.id] end)}
              end)
          }
        end)

      Bulletins.aggregate(students, subject_inputs, rules)
    end
  end

  defp context_meta(per_seq, cid) do
    {_seq, m} = Enum.find(per_seq, fn {_seq, m} -> Map.has_key?(m, cid) end)
    m[cid]
  end

  # A subject's period average for one student under the school's rules, before its
  # final rounding (kept as the rank tie-break).
  # :sequences = one trimester; :trimesters = the whole year.
  defp period_mean(:sequences, per_seq, cid, sid, rules),
    do: GradingRules.trimester_mean(sequence_pairs(per_seq, cid, sid), rules)

  defp period_mean(:trimesters, per_seq, cid, sid, rules),
    do: GradingRules.annual_mean(term_pairs(per_seq, cid, sid), rules)

  # [{position_in_term, avg}] for the séquences of `per_seq`, in order.
  defp sequence_pairs(per_seq, cid, sid) do
    Enum.map(per_seq, fn {seq, m} ->
      {seq.position_in_term, m[cid] && m[cid].per_student_avg[sid]}
    end)
  end

  # [{term_position, [{position_in_term, avg}]}], by term.
  defp term_pairs(per_seq, cid, sid) do
    per_seq
    |> Enum.group_by(fn {seq, _m} -> seq.term.position end)
    |> Enum.sort_by(fn {position, _} -> position end)
    |> Enum.map(fn {position, term_seqs} -> {position, sequence_pairs(term_seqs, cid, sid)} end)
  end

  defp build_components(:sequences, per_seq, cid, sid, _rules) do
    %{
      sequences:
        Enum.map(per_seq, fn {seq, m} ->
          %{number: seq.number, average: m[cid] && m[cid].per_student_avg[sid]}
        end)
    }
  end

  defp build_components(:trimesters, per_seq, cid, sid, rules) do
    %{
      trimesters:
        per_seq
        |> term_pairs(cid, sid)
        |> Enum.map(fn {position, pairs} ->
          %{position: position, average: GradingRules.trimester_average(pairs, rules)}
        end)
    }
  end
end
