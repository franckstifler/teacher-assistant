defmodule TeacherAssistant.Academics.EntryProgress do
  @moduledoc """
  Per-course mark-entry progress for one séquence (spec F, N05): a classes ×
  subjects grid where each cell is one course (teaching context).

  A cell's % is marks entered ÷ (students taking the course × the course's
  assessments in the séquence), rounded down so 100 means complete. Students
  taking = the class's enrollments minus the course's subject exemptions; only
  their marks count, whatever the mark's status. Everything is loaded in a
  fixed number of queries, whatever the number of classes or courses.
  """

  require Ash.Query

  alias TeacherAssistant.Accounts.User

  alias TeacherAssistant.Academics.{
    AcademicYear,
    Assessment,
    ClassGroup,
    Enrollment,
    Mark,
    Sequence,
    SubjectExemption,
    TeachingContext
  }

  alias TeacherAssistant.Scope

  @doc "Rounded-down percentage; `nil` when nothing is expected."
  def pct(_entered, 0), do: nil
  def pct(entered, expected), do: div(entered * 100, expected)

  def grid(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq) do
    class_groups = TeacherAssistant.Enrollment.list_class_groups(scope, year)
    contexts = load_contexts(scope, year)
    enrolled = load_enrolled(scope, year)
    exempt = load_exempt(scope, contexts)
    assessments = load_assessments(scope, seq)
    marks = load_marks(scope, assessments)

    assessments_by_tc = Enum.group_by(assessments, & &1.teaching_context_id)
    marks_by_assessment = Enum.group_by(marks, & &1.assessment_id)

    cells =
      Map.new(contexts, fn tc ->
        {{tc.class_group_id, column_key(tc)},
         cell(
           tc,
           taking(tc, enrolled, exempt),
           Map.get(assessments_by_tc, tc.id, []),
           marks_by_assessment
         )}
      end)

    subjects = subjects(contexts)

    rows =
      Enum.map(class_groups, fn cg ->
        %{
          class_group: cg,
          cells: Map.new(subjects, &{&1.key, Map.get(cells, {cg.id, &1.key})})
        }
      end)

    late = late(rows, subjects)

    %{
      subjects: subjects,
      rows: rows,
      overall_pct: overall_pct(rows),
      complete_classes: {Enum.count(rows, &complete?/1), length(rows)},
      late: late,
      late_teacher_count: length(late),
      council_date: council_date(scope, seq)
    }
  end

  @doc """
  The `grid/3` cell figures of the given courses only (« Mes cours » cards):
  `%{tc_id => %{entered:, expected:, pct:}}`. Contexts need `:class_group_id`.
  """
  def context_cells(%Scope{}, _year, _seq, []), do: %{}

  def context_cells(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq, contexts) do
    ids = Enum.map(contexts, & &1.id)
    class_ids = contexts |> Enum.map(& &1.class_group_id) |> Enum.uniq()
    enrolled = load_enrolled(scope, year, class_ids)
    exempt = load_exempt(scope, contexts)
    assessments = load_assessments(scope, seq, ids)
    marks_by_assessment = scope |> load_marks(assessments) |> Enum.group_by(& &1.assessment_id)
    assessments_by_tc = Enum.group_by(assessments, & &1.teaching_context_id)

    Map.new(contexts, fn tc ->
      tc_assessments = Map.get(assessments_by_tc, tc.id, [])
      cell = cell(tc, taking(tc, enrolled, exempt), tc_assessments, marks_by_assessment)
      {tc.id, Map.take(cell, [:entered, :expected, :pct])}
    end)
  end

  @doc """
  Every class's mark-entry rate over `sequences` (spec I2/I3: a trimester's or the year's
  séquences): per class, the mean of its course cells' % across those séquences, with the
  cell rules of `grid/3` (a course with students but no assessment is 0 %); rounded down,
  nil when no cell has a %. One grid per séquence, whatever the number of classes.
  """
  def class_rates(%Scope{} = scope, %AcademicYear{} = year, sequences) do
    sequences
    |> Enum.flat_map(fn seq ->
      scope
      |> grid(year, seq)
      |> Map.fetch!(:rows)
      |> Enum.map(fn row ->
        {row.class_group.id,
         row.cells |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.map(& &1.pct)}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {cg_id, lists} ->
      pcts = lists |> List.flatten() |> Enum.reject(&is_nil/1)
      {cg_id, if(pcts == [], do: nil, else: div(Enum.sum(pcts), length(pcts)))}
    end)
  end

  @doc "One class's mark-entry rate over `sequences` (see `class_rates/3`)."
  def class_rate(%Scope{} = scope, %AcademicYear{} = year, %ClassGroup{id: cg_id}, sequences),
    do: scope |> class_rates(year, sequences) |> Map.get(cg_id)

  @doc """
  The séquence to show by default: the one whose dates contain `today`, else
  the last one already started, else the first.
  """
  def default_sequence([], _today), do: nil

  def default_sequence(sequences, %Date{} = today) do
    Enum.find(sequences, &within?(&1, today)) ||
      sequences |> Enum.filter(&started?(&1, today)) |> List.last() ||
      hd(sequences)
  end

  defp within?(seq, today), do: started?(seq, today) and Date.compare(today, seq.end_date) != :gt
  defp started?(seq, today), do: Date.compare(seq.start_date, today) != :gt

  # --- Queries (one each) ------------------------------------------------------

  defp load_contexts(scope, %AcademicYear{id: year_id}) do
    TeachingContext
    |> Ash.Query.filter(academic_year_id == ^year_id and not is_nil(class_group_id))
    |> Ash.Query.load([:teacher, :catalog_subject])
    |> Ash.read!(scope: scope)
  end

  defp load_enrolled(scope, %AcademicYear{id: year_id}) do
    Enrollment
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> enrolled_by_class(scope)
  end

  defp load_enrolled(scope, %AcademicYear{id: year_id}, class_ids) do
    Enrollment
    |> Ash.Query.filter(academic_year_id == ^year_id and class_group_id in ^class_ids)
    |> enrolled_by_class(scope)
  end

  defp enrolled_by_class(query, scope) do
    query
    |> Ash.Query.select([:class_group_id, :student_id])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.class_group_id, & &1.student_id)
    |> Map.new(fn {cg_id, ids} -> {cg_id, MapSet.new(ids)} end)
  end

  defp load_exempt(_scope, []), do: %{}

  defp load_exempt(scope, contexts) do
    ids = Enum.map(contexts, & &1.id)

    SubjectExemption
    |> Ash.Query.filter(teaching_context_id in ^ids)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.teaching_context_id, & &1.student_id)
    |> Map.new(fn {tc_id, ids} -> {tc_id, MapSet.new(ids)} end)
  end

  defp load_assessments(scope, %Sequence{id: seq_id}) do
    Assessment
    |> Ash.Query.filter(sequence_id == ^seq_id)
    |> sorted_assessments(scope)
  end

  defp load_assessments(scope, %Sequence{id: seq_id}, context_ids) do
    Assessment
    |> Ash.Query.filter(sequence_id == ^seq_id and teaching_context_id in ^context_ids)
    |> sorted_assessments(scope)
  end

  defp sorted_assessments(query, scope) do
    query
    |> Ash.Query.select([:teaching_context_id, :label, :given_on, :inserted_at])
    |> Ash.Query.sort(given_on: :asc_nils_last, inserted_at: :asc)
    |> Ash.read!(scope: scope)
  end

  defp load_marks(_scope, []), do: []

  defp load_marks(scope, assessments) do
    ids = Enum.map(assessments, & &1.id)

    Mark
    |> Ash.Query.filter(assessment_id in ^ids)
    |> Ash.Query.select([:assessment_id, :student_id, :updated_at])
    |> Ash.read!(scope: scope)
  end

  defp council_date(scope, %Sequence{term: %Ash.NotLoaded{}} = seq),
    do: council_date(scope, Ash.load!(seq, :term, scope: scope))

  defp council_date(_scope, %Sequence{term: term}), do: term && term.class_council_date

  # --- Pure computation ----------------------------------------------------------

  # Students taking the course: its class's enrollments minus its exemptions.
  defp taking(tc, enrolled, exempt) do
    enrolled
    |> Map.get(tc.class_group_id, MapSet.new())
    |> MapSet.difference(Map.get(exempt, tc.id, MapSet.new()))
  end

  defp cell(tc, taking, assessments, marks_by_assessment) do
    marks =
      assessments
      |> Enum.flat_map(&Map.get(marks_by_assessment, &1.id, []))
      |> Enum.filter(&MapSet.member?(taking, &1.student_id))

    students = MapSet.size(taking)
    expected = students * length(assessments)
    entered = length(marks)

    %{
      teaching_context: tc,
      teacher: Map.get(tc, :teacher),
      entered: entered,
      expected: expected,
      # A course with students but no assessment yet is "Rien saisi" (0 %).
      pct: if(assessments == [] and students > 0, do: 0, else: pct(entered, expected)),
      assessments: Enum.map(assessments, & &1.label),
      last_entry_at: marks |> Enum.map(& &1.updated_at) |> Enum.max(DateTime, fn -> nil end)
    }
  end

  defp column_key(%TeachingContext{subject_id: nil, subject: subject}), do: subject
  defp column_key(%TeachingContext{subject_id: id}), do: id

  # Columns: the subjects taught in at least one class, catalog order then name.
  defp subjects(contexts) do
    contexts
    |> Enum.uniq_by(&column_key/1)
    |> Enum.map(fn tc ->
      label = if tc.catalog_subject, do: tc.catalog_subject.name, else: tc.subject
      position = if tc.catalog_subject, do: tc.catalog_subject.position, else: nil

      %{
        key: column_key(tc),
        label: label,
        code: column_code(tc.catalog_subject, label),
        sort: {is_nil(position), position, label}
      }
    end)
    |> Enum.sort_by(& &1.sort)
    |> Enum.map(&Map.delete(&1, :sort))
  end

  # The short column heading: the catalog code ("MATH"), else the label's first letters.
  defp column_code(%{code: code}, _label) when is_binary(code) and code != "", do: code
  defp column_code(_subject, label), do: label |> String.slice(0, 4) |> String.upcase()

  defp known_pcts(%{cells: cells}),
    do:
      cells
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.pct)
      |> Enum.reject(&is_nil/1)

  defp overall_pct(rows) do
    case Enum.flat_map(rows, &known_pcts/1) do
      [] -> nil
      pcts -> div(Enum.sum(pcts), length(pcts))
    end
  end

  # A class with no measurable course (no course, or no student) is not complete.
  defp complete?(row) do
    case known_pcts(row) do
      [] -> false
      pcts -> Enum.all?(pcts, &(&1 == 100))
    end
  end

  # Every lagging course (entry below 100 %, at least one student) with a teacher,
  # grouped per teacher: classes in row order, subjects in column order; teachers by name.
  defp late(rows, subjects) do
    labels = Map.new(subjects, &{&1.key, &1.label})

    for %{class_group: cg, cells: cells} <- rows,
        %{key: key} <- subjects,
        %{pct: pct, teacher: teacher, teaching_context: tc} when is_integer(pct) and pct < 100 <-
          [cells[key]],
        not is_nil(tc.teacher_user_id) do
      {tc.teacher_user_id, teacher,
       %{tc_id: tc.id, subject: labels[key], class: cg.label, pct: pct}}
    end
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {teacher_id, [{_, teacher, _} | _] = entries} ->
      %{teacher: teacher, teacher_id: teacher_id, courses: Enum.map(entries, &elem(&1, 2))}
    end)
    |> Enum.sort_by(&{teacher_name(&1.teacher), &1.teacher_id})
  end

  defp teacher_name(nil), do: ""
  defp teacher_name(teacher), do: User.display_name(teacher)
end
