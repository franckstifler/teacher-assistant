defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  # NAME COLLISION: this domain module is `TeacherAssistant.Assessment`, and
  # the resource is `TeacherAssistant.Academics.Assessment`. Inside this module
  # the short alias `Assessment` is bound to the RESOURCE (below); this module
  # calls its own domain functions bare, so there is never a bare
  # `Assessment.<fn>` that could rebind to the wrong module.
  alias TeacherAssistant.Academics.{
    AcademicYear,
    AnnualAverageRule,
    Assessment,
    AverageRounding,
    Bulletins,
    ClassGroup,
    CombinedCourse,
    GradingRules,
    Mark,
    Marks,
    Sequence,
    Term,
    TeachingContext,
    TrimesterAverageRule
  }

  alias TeacherAssistant.Scope

  resources do
    resource Assessment
    resource Mark
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
    args = %{course: course, sequence: seq, label: label}

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
      shared_ranks?: profile.shared_ranks?
    }
  end

  @rule_fields %{
    "trimester_average_rule" => {:trimester_average_rule, TrimesterAverageRule},
    "annual_average_rule" => {:annual_average_rule, AnnualAverageRule},
    "average_rounding" => {:average_rounding, AverageRounding}
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
            %{student_id: m.student_id, assessment_id: m.assessment_id, score: m.score}
          end)
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
        students =
          scope
          |> TeacherAssistant.Enrollment.list_students(cg)
          |> Enum.map(fn s -> %{id: s.id, sex: s.sex, name: s.full_name} end)

        Bulletins.compile(students, subjects, grading_rules(scope))
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
    period_result(scope, cg, seqs, :sequences)
  end

  def class_results_for_period(
        %Scope{} = scope,
        %ClassGroup{} = cg,
        {:annual, %AcademicYear{} = year}
      ) do
    seqs = TeacherAssistant.Organization.list_sequences(scope, year)
    period_result(scope, cg, seqs, :trimesters)
  end

  # Builds a Bulletins result over a set of séquences. `component_kind` selects the
  # breakdown carried on each subject row: :sequences (per séquence, for trimester)
  # or :trimesters (per term, for annual).
  defp period_result(%Scope{} = scope, cg, seqs, component_kind) do
    rules = grading_rules(scope)

    students =
      scope
      |> TeacherAssistant.Enrollment.list_students(cg)
      |> Enum.map(fn s -> %{id: s.id, sex: s.sex, name: s.full_name} end)

    # per séquence: %{context_id => %{label, coefficient, per_student_avg}}
    per_seq =
      Enum.map(seqs, fn seq ->
        subjects =
          scope
          |> class_subjects(cg, seq)
          |> Map.new(fn subj ->
            psa =
              Map.new(students, fn s ->
                sm = Enum.filter(subj.marks, &(&1.student_id == s.id))

                {s.id,
                 GradingRules.round_average(
                   Marks.subject_average(sm, subj.assessments_by_id),
                   rules
                 )}
              end)

            {subj.context_id,
             %{
               label: subj.label,
               coefficient: subj.coefficient,
               group: subj.group,
               position: subj.position,
               per_student_avg: psa
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

          per_student_avg =
            Map.new(students, fn s ->
              {s.id, period_average(component_kind, per_seq, cid, s.id, rules)}
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
            components: components
          }
        end)

      Bulletins.aggregate(students, subject_inputs, rules)
    end
  end

  defp context_meta(per_seq, cid) do
    {_seq, m} = Enum.find(per_seq, fn {_seq, m} -> Map.has_key?(m, cid) end)
    m[cid]
  end

  # A subject's period average for one student under the school's rules.
  # :sequences = one trimester; :trimesters = the whole year.
  defp period_average(:sequences, per_seq, cid, sid, rules),
    do: GradingRules.trimester_average(sequence_pairs(per_seq, cid, sid), rules)

  defp period_average(:trimesters, per_seq, cid, sid, rules),
    do: GradingRules.annual_average(term_pairs(per_seq, cid, sid), rules)

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
