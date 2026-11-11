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
    Sequence,
    SubjectExemption,
    TeachingContext
  }

  alias TeacherAssistant.Scope

  # A3: the marks are counted in the database (`Assessment` aggregates), never loaded.
  @figures [:marks_count, :last_mark_at]
  @doc "Rounded-down percentage; `nil` when nothing is expected."
  def pct(_entered, 0), do: nil
  def pct(entered, expected), do: div(entered * 100, expected)

  def grid(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq) do
    class_groups = TeacherAssistant.Enrollment.list_class_groups(scope, year)
    contexts = load_contexts(scope, year)
    enrolled = load_enrolled(scope, year, seq.start_date)
    exempt = load_exempt(scope, contexts)
    assessments = load_assessments(scope, seq)
    assessments_by_tc = Enum.group_by(assessments, & &1.teaching_context_id)

    cells =
      Map.new(contexts, fn tc ->
        {{tc.class_group_id, column_key(tc)},
         cell(tc, taking(tc, enrolled, exempt), Map.get(assessments_by_tc, tc.id, []))}
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
  `%{tc_id => %{entered:, expected:, pct:, assessments:}}` (`assessments`: how many
  the course has in the séquence). Contexts need `:class_group_id`.
  """
  def context_cells(%Scope{}, _year, _seq, []), do: %{}

  def context_cells(%Scope{} = scope, %AcademicYear{} = year, %Sequence{} = seq, contexts) do
    ids = Enum.map(contexts, & &1.id)
    class_ids = contexts |> Enum.map(& &1.class_group_id) |> Enum.uniq()
    enrolled = load_enrolled(scope, year, class_ids, seq.start_date)
    exempt = load_exempt(scope, contexts)
    assessments = load_assessments(scope, seq, ids)
    assessments_by_tc = Enum.group_by(assessments, & &1.teaching_context_id)

    Map.new(contexts, fn tc ->
      tc_assessments = Map.get(assessments_by_tc, tc.id, [])
      cell = cell(tc, taking(tc, enrolled, exempt), tc_assessments)

      {tc.id,
       cell
       |> Map.take([:entered, :expected, :pct])
       |> Map.put(:assessments, length(tc_assessments))}
    end)
  end

  @doc """
  UX refonte (class page): how far the class's courses are in `seq` —
  `{started, total}`, `started` being the courses with at least one mark entered
  (`context_cells/4`'s `entered`), `total` the class's courses this year.
  """
  def class_subjects_started(
        %Scope{} = scope,
        %AcademicYear{} = year,
        %ClassGroup{id: cg_id},
        %Sequence{} = seq
      ) do
    contexts =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id and class_group_id == ^cg_id)
      |> Ash.read!(scope: scope)

    started =
      scope
      |> context_cells(year, seq, contexts)
      |> Enum.count(fn {_id, cell} -> cell.entered > 0 end)

    {started, length(contexts)}
  end

  @doc """
  Every class's mark-entry rate over `sequences` (spec I2/I3: a trimester's or the year's
  séquences): per class, the mean of its course cells' % across those séquences, with the
  cell rules of `grid/3` (a course with students but no assessment is 0 %); rounded down,
  nil when no cell has a %. One grid per séquence, whatever the number of classes.
  """
  def class_rates(%Scope{} = scope, %AcademicYear{} = year, sequences) do
    class_ids = scope |> TeacherAssistant.Enrollment.list_class_groups(year) |> Enum.map(& &1.id)
    rates(scope, year, sequences, class_ids)
  end

  @doc "One class's mark-entry rate over `sequences` (see `class_rates/3`); reads that class only."
  def class_rate(%Scope{} = scope, %AcademicYear{} = year, %ClassGroup{id: cg_id}, sequences),
    do: scope |> rates(year, sequences, [cg_id]) |> Map.get(cg_id)

  # The rates of `class_ids`, every séquence's assessments and marks read at once.
  defp rates(_scope, _year, _sequences, []), do: %{}

  defp rates(scope, year, sequences, class_ids) do
    contexts =
      TeachingContext
      |> Ash.Query.filter(academic_year_id == ^year.id and class_group_id in ^class_ids)
      |> Ash.read!(scope: scope)

    first_day = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date, fn -> nil end)
    enrolled = load_enrolled(scope, year, class_ids, first_day)
    exempt = load_exempt(scope, contexts)

    assessments =
      load_sequences_assessments(
        scope,
        Enum.map(sequences, & &1.id),
        Enum.map(contexts, & &1.id)
      )

    assessments_by = Enum.group_by(assessments, &{&1.teaching_context_id, &1.sequence_id})
    # One cell per class × subject column, as in `grid/3`.
    courses = Map.new(contexts, &{{&1.class_group_id, column_key(&1)}, &1})

    pcts =
      for seq <- sequences,
          {{cg_id, _column}, tc} <- courses,
          tc_assessments <- [Map.get(assessments_by, {tc.id, seq.id}, [])],
          %{pct: pct} <- [cell(tc, taking(tc, enrolled, exempt), tc_assessments)],
          not is_nil(pct),
          do: {cg_id, pct}

    by_class = Enum.group_by(pcts, &elem(&1, 0), &elem(&1, 1))

    Map.new(class_ids, fn cg_id ->
      case Map.get(by_class, cg_id, []) do
        [] -> {cg_id, nil}
        list -> {cg_id, div(Enum.sum(list), length(list))}
      end
    end)
  end

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

  # The students a séquence expects (A7): those still in the class on its first day.
  defp load_enrolled(scope, %AcademicYear{id: year_id}, first_day) do
    Enrollment
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> enrolled_by_class(scope, first_day)
  end

  defp load_enrolled(scope, %AcademicYear{id: year_id}, class_ids, first_day) do
    Enrollment
    |> Ash.Query.filter(academic_year_id == ^year_id and class_group_id in ^class_ids)
    |> enrolled_by_class(scope, first_day)
  end

  defp enrolled_by_class(query, scope, first_day) do
    query
    |> then(fn q ->
      if first_day,
        do: Ash.Query.filter(q, is_nil(left_on) or left_on > ^first_day),
        else: q
    end)
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

  defp load_sequences_assessments(_scope, [], _context_ids), do: []
  defp load_sequences_assessments(_scope, _seq_ids, []), do: []

  defp load_sequences_assessments(scope, seq_ids, context_ids) do
    Assessment
    |> Ash.Query.filter(sequence_id in ^seq_ids and teaching_context_id in ^context_ids)
    |> Ash.Query.select([:teaching_context_id, :sequence_id])
    |> Ash.Query.load(@figures)
    |> Ash.read!(scope: scope)
  end

  defp sorted_assessments(query, scope) do
    query
    |> Ash.Query.select([:teaching_context_id, :label, :given_on, :inserted_at])
    |> Ash.Query.load(@figures)
    |> Ash.Query.sort(given_on: :asc_nils_last, inserted_at: :asc)
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

  defp cell(tc, taking, assessments) do
    students = MapSet.size(taking)
    expected = students * length(assessments)
    entered = Enum.sum_by(assessments, & &1.marks_count)

    %{
      teaching_context: tc,
      teacher: Map.get(tc, :teacher),
      entered: entered,
      expected: expected,
      # A course with students but no assessment yet is "Rien saisi" (0 %).
      pct: if(assessments == [] and students > 0, do: 0, else: pct(entered, expected)),
      assessments: Enum.map(assessments, & &1.label),
      last_entry_at:
        assessments
        |> Enum.map(& &1.last_mark_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)
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

  @doc "The short column heading: the catalog code (\"MATH\"), else the label's first letters."
  def column_code(%{code: code}, _label) when is_binary(code) and code != "", do: code
  def column_code(_subject, label), do: label |> String.slice(0, 4) |> String.upcase()

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
