defmodule TeacherAssistant.Academics do
  # Intentionally NOT registered in :ash_domains — its resources now live in
  # focused domains. It remains an Ash.Domain module only to host the legacy
  # bulletin/results trio (converted to calculations in a later task), so skip
  # the config-inclusion check.
  use Ash.Domain, otp_app: :teacher_assistant, validate_config_inclusion?: false

  require Ash.Query
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.Bulletins

  # Resources have moved to focused domains (Organization, Enrollment,
  # Curriculum, Assessment, Attendance, Discipline, Timetabling, Fees).
  # This domain is no longer registered in :ash_domains; it survives only to
  # host the bulletin/results trio until a later task converts it.
  resources do
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
end
