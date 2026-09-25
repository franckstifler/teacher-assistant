defmodule TeacherAssistant.Assessment do
  use Ash.Domain, otp_app: :teacher_assistant

  # NAME COLLISION: this domain module is `TeacherAssistant.Assessment`, and
  # the resource is `TeacherAssistant.Academics.Assessment`. Inside this module
  # the short alias `Assessment` is bound to the RESOURCE (below); this module
  # calls its own domain functions bare, so there is never a bare
  # `Assessment.<fn>` that could rebind to the wrong module.
  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    Bulletins,
    ClassGroup,
    CombinedCourse,
    Mark,
    Marks,
    Sequence,
    Term,
    TeachingContext
  }

  alias TeacherAssistant.Scope

  resources do
    resource Assessment
    resource Mark
  end

  authorization do
    authorize :when_requested
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
    {:ok, entries} =
      Assessment
      |> Ash.ActionInput.for_action(:combined_for, %{course: course, sequence: seq}, scope: scope)
      |> Ash.run_action()

    entries
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
  transaction. A `nil` score is valid (records the student absent). Scores are
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
          score: Map.get(entry, :score)
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
            score: Map.get(entry, :score)
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
    cg
    |> TeacherAssistant.Curriculum.list_assignments_for_class()
    |> Enum.map(fn tc ->
      assessments = list_assessments(scope, tc, seq)

      %{
        context_id: tc.id,
        label: tc.subject,
        coefficient: tc.coefficient,
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
          cg
          |> TeacherAssistant.Enrollment.list_students()
          |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)

        Bulletins.compile(students, subjects)
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
    seqs = TeacherAssistant.Organization.list_sequences(year)
    period_result(scope, cg, seqs, :trimesters)
  end

  # Builds a Bulletins result over a set of séquences. `component_kind` selects the
  # breakdown carried on each subject row: :sequences (per séquence, for trimester)
  # or :trimesters (per term, for annual).
  defp period_result(%Scope{} = scope, cg, seqs, component_kind) do
    students =
      cg
      |> TeacherAssistant.Enrollment.list_students()
      |> Enum.map(fn s -> %{id: s.id, sex: s.sex} end)

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

                {s.id, Marks.subject_average(sm, subj.assessments_by_id)}
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
end
