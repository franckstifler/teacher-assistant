defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  # NAME COLLISION: this domain module is `TeacherAssistant.Assessment`, and
  # the resource is `TeacherAssistant.Academics.Assessment`. Inside this module
  # the short alias `Assessment` is bound to the RESOURCE (below); this module
  # calls its own domain functions bare, so there is never a bare
  # `Assessment.<fn>` that could rebind to the wrong module.
  alias TeacherAssistant.Academics.{
    AbsenceRule,
    AcademicYear,
    AnnualAverageRule,
    Assessment,
    AssessmentType,
    AverageRounding,
    BulletinPublication,
    Bulletins,
    ClassGroup,
    CombinedCourse,
    EntryProgress,
    GradingRules,
    Mark,
    MarkCorrection,
    MarkEvent,
    Marks,
    Sequence,
    Term,
    TeachingContext,
    TrimesterAverageRule
  }

  alias TeacherAssistant.Scope

  resources do
    resource Assessment
    resource AssessmentType
    resource Mark
    resource MarkEvent
    resource MarkCorrection
    resource BulletinPublication
  end

  authorization do
    authorize :by_default
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

  @doc "The séquence shown by default on `today` (current, else last started, else first)."
  def default_sequence(sequences, %Date{} = today),
    do: EntryProgress.default_sequence(sequences, today)

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

  @doc """
  Like `upsert_marks/3`, but atomic across several assessments at once — the
  combined-marks save path. `assessment_entries` is `[{%Assessment{}, [entry]}]`,
  one pair per member class. Every pair's entries are range-checked against
  *their own* assessment's `max_score` BEFORE anything is written, and every
  write happens inside a single transaction, so a combined course's per-class
  saves are all-or-nothing: one class's out-of-range score can never leave
  another class's valid score persisted (no partial commit across classes).
  """
  def upsert_marks_all_or_nothing(%Scope{} = _scope, []), do: :ok

  def upsert_marks_all_or_nothing(%Scope{} = scope, assessment_entries) do
    out_of_range? =
      Enum.any?(assessment_entries, fn {%Assessment{max_score: max_score}, entries} ->
        not Enum.all?(entries, &score_in_range?(&1, max_score))
      end)

    if out_of_range? do
      {:error, :out_of_range}
    else
      assessment_entries
      |> Enum.flat_map(fn {%Assessment{id: assessment_id}, entries} ->
        Enum.map(entries, fn entry ->
          %{
            assessment_id: assessment_id,
            student_id: entry.student_id,
            score: Map.get(entry, :score),
            status: Map.get(entry, :status)
          }
        end)
      end)
      |> run_upsert_all(scope)
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

  @correction_loads [:student, :requester, assessment: [teaching_context: [:class_group]]]

  @doc "Asks to change a locked mark (the course's teacher only)."
  def request_correction(%Scope{} = scope, attrs) do
    MarkCorrection
    |> Ash.Changeset.for_create(:request, attrs, scope: scope)
    |> Ash.create(load: @correction_loads)
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

  @doc "Approves a pending request: writes the mark, unless it changed since (\"stale\")."
  def approve_correction(%Scope{} = scope, %MarkCorrection{} = correction),
    do: decide_correction(scope, correction, :approve)

  @doc "Refuses a pending request; the mark is untouched."
  def refuse_correction(%Scope{} = scope, %MarkCorrection{} = correction),
    do: decide_correction(scope, correction, :refuse)

  defp decide_correction(scope, correction, action) do
    correction
    |> Ash.Changeset.for_update(action, %{}, scope: scope)
    |> Ash.update(load: @correction_loads)
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
    |> Ash.Query.load(@correction_loads ++ [:decider])
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

  defp update_profile(scope, attrs) do
    with {:ok, profile} <- TeacherAssistant.Accounts.fetch_school_profile(scope) do
      TeacherAssistant.Accounts.update_school_profile(profile, attrs, scope: scope)
    end
  end

  defp parse_bands(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case parse_score(row.from) do
        {:ok, %Decimal{} = from} ->
          {:cont, {:ok, acc ++ [%{from: from, label: String.trim(row.label || "")}]}}

        _ ->
          {:halt, {:error, :invalid_number}}
      end
    end)
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
  def class_subjects(%Scope{} = scope, %ClassGroup{} = cg, %Sequence{} = seq) do
    scope
    |> TeacherAssistant.Curriculum.list_assignments_for_class(cg)
    |> Enum.map(fn tc ->
      assessments = list_assessments(scope, tc, seq)

      %{
        context_id: tc.id,
        label: tc.subject,
        coefficient: tc.effective_coefficient,
        group: tc.catalog_subject.bulletin_group,
        position: tc.catalog_subject.position,
        assessments_by_id:
          Map.new(assessments, fn a -> {a.id, %{weight: a.weight, max_score: a.max_score}} end),
        marks:
          scope
          |> list_marks_for_context_sequence(tc, seq)
          |> Enum.map(fn m ->
            %{
              student_id: m.student_id,
              assessment_id: m.assessment_id,
              score: m.score,
              status: m.status
            }
          end),
        exempt: TeacherAssistant.Curriculum.exempt_student_ids(scope, tc)
      }
    end)
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

    # per séquence: %{context_id => %{label, coefficient, per_student_avg}}
    per_seq =
      Enum.map(seqs, fn seq ->
        subjects =
          scope
          |> class_subjects(cg, seq)
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
