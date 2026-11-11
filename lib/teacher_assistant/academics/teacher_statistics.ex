defmodule TeacherAssistant.Academics.TeacherStatistics do
  @moduledoc """
  The figures a teacher copies into their pedagogical forms (spec audit follow-ups
  A4): per course and per period — effectif, garçons / filles, notés, moyenne,
  taux de réussite (overall and by sex), extrêmes, mentions.

  A séquence is computed from its marks as the Résultats page always did. A
  trimester or the year takes each student's subject average from the class's
  bulletin — the published snapshot when the period is published for that class
  (so the figure equals the printed bulletin even after later corrections), else
  the bulletin computed now — so no figure here can differ from the bulletin.
  """
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, ReportCards, Scope}
  alias TeacherAssistant.Academics.{Marks, SchoolTemplates, TeacherCourses, TeachingContext}

  @type period ::
          {:sequence, struct()} | {:trimester, struct()} | {:annual, struct()}

  @doc """
  One course's statistics: `%{summary, students, source, members}`. `ctx` may be any
  member context of a combined course; every member class is covered. `summary` is
  `Marks.summarize/4`'s map over the union of the member classes (nil without any
  assessment or average); `source` is `:live`, `:published` (every member class
  published for the period) or `:mixed`; `members` holds each class's own figures.
  """
  def course(%Scope{} = scope, %TeachingContext{} = ctx, period) do
    shared = shared(scope, period)
    members = scope |> member_contexts(ctx) |> members(scope, period, shared)
    stats(scope, members, period, class_results(scope, members, period, shared), shared)
  end

  @doc """
  The teacher's table for a period: one row per course (as `TeacherCourses.list/2`
  gives them), each followed by one sub-row per member class when the course is
  combined (`class_label` set). Results of a class are computed once for the table.
  """
  def table(%Scope{} = scope, teacher, period) do
    courses = TeacherCourses.list(%{scope | current_user: teacher}, nil)
    shared = shared(scope, period)
    per_course = Enum.map(courses, &{&1, members(&1.contexts, scope, period, shared)})
    results = class_results(scope, Enum.flat_map(per_course, &elem(&1, 1)), period, shared)

    Enum.flat_map(per_course, fn {course, members} ->
      stats = stats(scope, members, period, results, shared)
      head = row(course, nil, stats.students, stats.summary, stats.source)

      case stats.members do
        [_single] ->
          [head]

        many ->
          [
            head
            | Enum.map(
                many,
                &row(course, &1.class_group, &1.students, &1.summary, &1.source)
              )
          ]
      end
    end)
  end

  # What every class of the table shares, read once: the grading rules, the period's
  # séquences and its first day.
  defp shared(scope, period) do
    %{
      rules: Assessment.grading_rules(scope),
      sequences: Organization.period_sequences(scope, period),
      first_day: Organization.period_first_day(scope, period)
    }
  end

  # --- members ----------------------------------------------------------------

  defp member_contexts(scope, %TeachingContext{combined_course_id: nil} = ctx),
    do: [Ash.load!(ctx, :class_group, scope: scope)]

  defp member_contexts(scope, %TeachingContext{combined_course_id: course_id}) do
    course_id
    |> Curriculum.contexts_of_course!(scope: scope)
    |> Ash.load!(:class_group, scope: scope)
    |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))
  end

  # Each member class with the students taking the subject (exempted ones are out), as
  # the class stood on the period's first day (A7: as the bulletin counts them).
  defp members(contexts, scope, _period, %{first_day: first_day}) do
    Enum.map(contexts, fn ctx ->
      exempt = Curriculum.exempt_student_ids(scope, ctx)
      cg = ctx.class_group

      students =
        for s <- Enrollment.list_students(scope, cg, on: first_day),
            not MapSet.member?(exempt, s.id) do
          %{id: s.id, sex: s.sex, full_name: s.full_name, class_label: cg.label}
        end

      %{ctx: ctx, class_group: cg, students: students}
    end)
  end

  # --- figures ----------------------------------------------------------------

  defp stats(scope, members, {:sequence, seq}, _results, %{rules: rules}) do
    per_member =
      Enum.map(members, fn m ->
        assessments = Assessment.list_assessments(scope, m.ctx, seq)

        marks =
          if assessments == [],
            do: [],
            else: Assessment.list_marks_for_context_sequence(scope, m.ctx, seq)

        Map.merge(m, %{assessments: assessments, marks: marks})
      end)

    member_stats =
      Enum.map(per_member, fn m ->
        %{
          class_group: m.class_group,
          ctx: m.ctx,
          students: m.students,
          summary: summarize(m.students, m.assessments, m.marks, rules),
          source: :live
        }
      end)

    students = Enum.flat_map(members, & &1.students)

    %{
      summary:
        summarize(
          students,
          Enum.flat_map(per_member, & &1.assessments),
          Enum.flat_map(per_member, & &1.marks),
          rules
        ),
      students: students,
      source: :live,
      members: member_stats
    }
  end

  defp stats(_scope, members, _period, results, %{rules: rules}) do
    member_stats =
      Enum.map(members, fn m ->
        {class_results, source} = Map.fetch!(results, m.class_group.id)
        averages = Map.new(m.students, &{&1.id, subject_average(class_results, &1.id, m.ctx.id)})

        %{
          class_group: m.class_group,
          ctx: m.ctx,
          students: m.students,
          averages: averages,
          summary: from_averages(m.students, averages, rules),
          source: source
        }
      end)

    students = Enum.flat_map(members, & &1.students)
    averages = member_stats |> Enum.map(& &1.averages) |> Enum.reduce(%{}, &Map.merge/2)

    %{
      summary: from_averages(students, averages, rules),
      students: students,
      source: source(Enum.map(member_stats, & &1.source)),
      members: Enum.map(member_stats, &Map.delete(&1, :averages))
    }
  end

  defp summarize(_students, [], _marks, _rules), do: nil

  defp summarize(students, assessments, marks, rules) do
    Marks.summarize(
      Enum.map(students, &%{id: &1.id, sex: &1.sex, name: &1.full_name}),
      Enum.map(assessments, &%{id: &1.id, weight: &1.weight, max_score: &1.max_score}),
      Enum.map(marks, fn m ->
        %{
          assessment_id: m.assessment_id,
          student_id: m.student_id,
          score: m.score,
          status: m.status
        }
      end),
      rules
    )
  end

  defp from_averages(students, averages, rules) do
    if Enum.all?(Map.values(averages), &is_nil/1) do
      nil
    else
      Marks.from_averages(
        Enum.map(students, &%{id: &1.id, sex: &1.sex, name: &1.full_name}),
        averages,
        rules
      )
    end
  end

  # `%{class id => {results, :published | :live}}` for a trimester or the year; the
  # published snapshot wins. Séquences need none.
  defp class_results(_scope, _members, {:sequence, _}, _shared), do: %{}

  defp class_results(scope, members, period, shared) do
    members
    |> Enum.map(& &1.class_group)
    |> Enum.uniq_by(& &1.id)
    |> Map.new(fn cg ->
      case ReportCards.current_publication(scope, cg, period, snapshot: true) do
        nil ->
          inputs =
            scope
            |> Assessment.period_inputs(cg, shared.sequences, shared.rules)
            |> Map.merge(Map.take(shared, [:sequences, :first_day]))

          {cg.id, {Assessment.class_results_for_period(scope, cg, period, inputs: inputs), :live}}

        pub ->
          {cg.id, {pub.snapshot.results, :published}}
      end
    end)
  end

  defp subject_average(nil, _student_id, _ctx_id), do: nil

  defp subject_average(%{per_student: per_student}, student_id, ctx_id) do
    with %{subjects: subjects} <- Map.get(per_student, student_id),
         %{average: average} <- Enum.find(subjects, &(&1.context_id == ctx_id)) do
      average
    else
      _ -> nil
    end
  end

  defp source(sources) do
    cond do
      Enum.all?(sources, &(&1 == :published)) -> :published
      Enum.all?(sources, &(&1 == :live)) -> :live
      true -> :mixed
    end
  end

  # --- table rows ---------------------------------------------------------------

  defp row(course, class_group, students, summary, source) do
    graded = (summary && summary.graded_count) || 0

    %{
      course: course,
      class_id: class_group && class_group.id,
      class_label: class_group && class_group.label,
      headcount: length(students),
      boys: Enum.count(students, &(&1.sex == :m)),
      girls: Enum.count(students, &(&1.sex == :f)),
      graded: graded,
      average: summary && summary.class_average,
      pass_rate: if(graded > 0, do: summary.pass_rate),
      pass_m: sex_rate(summary, :m),
      pass_f: sex_rate(summary, :f),
      lowest: summary && summary.lowest,
      highest: summary && summary.highest,
      mentions: mentions(summary),
      source: source
    }
  end

  defp sex_rate(nil, _sex), do: nil
  defp sex_rate(summary, sex), do: rate(summary.by_sex[sex])

  defp rate(%{graded_count: 0}), do: nil
  defp rate(%{pass_rate: rate}), do: rate

  @doc "`[{mention label, count}]`, best mention first (`[]` without figures)."
  def mentions(nil), do: []

  def mentions(summary) do
    summary.per_student
    |> Map.values()
    |> Enum.reject(&is_nil(&1.mention))
    |> Enum.frequencies_by(& &1.mention)
    |> Enum.sort_by(fn {mention, _count} -> mention.position end, :desc)
    |> Enum.map(fn {mention, count} -> {mention.label, count} end)
  end
end
