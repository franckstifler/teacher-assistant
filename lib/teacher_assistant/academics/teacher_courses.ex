defmodule TeacherAssistant.Academics.TeacherCourses do
  @moduledoc """
  The signed-in teacher's courses (UX refonte 2026-11-03): one per solo assignment
  or combined course, with what « Mes cours », the « À faire » card of Ma journée
  and the teacher's bulletins view show of it — member classes, students,
  coefficient, form-master badge, séquence entry progress and APC competence.
  """
  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization, Scope}

  alias TeacherAssistant.Academics.{
    CoefficientRules,
    CombinedCourse,
    EntryProgress,
    Reference,
    SchoolTemplates
  }

  @no_progress %{entered: 0, expected: 0, pct: nil, assessments: 0}

  @doc "The séquence a teacher works in today (`Assessment.default_sequence/2`), nil without a year."
  def current_sequence(scope, today \\ Reference.today())
  def current_sequence(%Scope{current_academic_year: nil}, _today), do: nil

  def current_sequence(%Scope{current_academic_year: year} = scope, today),
    do: scope |> Organization.list_sequences(year) |> Assessment.default_sequence(today)

  @doc """
  The scope's courses, in assignment order. Each is a map:

    * `id` — `"combined-<course id>"` or the context's id; `unit` as
      `Curriculum.list_units_for_scope/1` gives it;
    * `title` — « Anglais · Niveau 2 » (the combined course's label) or
      « Maths · 6e A »; `name` — the same without the subject (« Niveau 2 », « 6e A »);
    * `subject`, `context_id` (a member context, which the marks, results and roster
      pages resolve to the course), `contexts`, `classes` (level order),
      `class_sizes` (`%{class id => students}`), `students`, `coefficient` (nil
      when none), `pp?`;
    * `progress` — `%{entered, expected, pct, assessments}` in `seq` (zeros without);
    * `competence` — `:missing`, `:done`, or nil when none is due in `seq`.
  """
  def list(%Scope{current_workspace: nil}, _seq), do: []

  def list(%Scope{} = scope, seq) do
    case scope |> Curriculum.list_units_for_scope() |> Enum.map(&with_contexts(&1, scope)) do
      [] ->
        []

      units ->
        contexts = Enum.flat_map(units, &elem(&1, 1))

        ctx = %{
          user_id: scope.current_user.id,
          sizes: Enrollment.class_sizes(scope, scope.current_academic_year),
          coefficients: Curriculum.coefficient_cells(scope),
          progress: context_progress(scope, seq, contexts),
          competences: competences_due(scope, seq, contexts)
        }

        Enum.map(units, &row(&1, ctx))
    end
  end

  @doc """
  Each course's entry progress in another séquence: `%{course id => progress}` (the
  `progress` map of `list/2`). One batched read for all the courses.
  """
  def progress(%Scope{} = scope, seq, courses) do
    cells = context_progress(scope, seq, Enum.flat_map(courses, & &1.contexts))
    Map.new(courses, &{&1.id, sum_progress(&1.contexts, cells)})
  end

  @doc "The students of the courses' classes, each class counted once."
  def student_total(courses),
    do: courses |> Enum.map(& &1.class_sizes) |> Enum.reduce(%{}, &Map.merge/2) |> Map.values() |> Enum.sum()

  @doc "Whether a course has marks left to enter in the séquence (none yet, or some missing)."
  def to_enter?(%{progress: %{assessments: 0}}), do: true
  def to_enter?(%{progress: %{entered: entered, expected: expected}}), do: entered < expected

  # Every unit with its member contexts (and their class), loaded once.
  defp with_contexts({:course, %CombinedCourse{} = course} = unit, scope) do
    contexts =
      course.id
      |> Curriculum.contexts_of_course!(scope: scope)
      # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.load!(:class_group, scope: scope)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key(&1.class_group))

    {unit, contexts}
  end

  defp with_contexts({:solo, tc} = unit, _scope), do: {unit, [tc]}

  defp context_progress(_scope, nil, _contexts), do: %{}

  defp context_progress(scope, seq, contexts),
    do: EntryProgress.context_cells(scope, scope.current_academic_year, seq, contexts)

  defp competences_due(_scope, nil, _contexts), do: nil

  defp competences_due(scope, seq, contexts),
    do: Assessment.competences_due(scope, seq, Enum.map(contexts, & &1.id))

  defp row({{:course, %CombinedCourse{} = course} = unit, contexts}, ctx) do
    Map.merge(facts(contexts, ctx), %{
      id: "combined-#{course.id}",
      unit: unit,
      title: course.label,
      name: short_name(course.label, course.subject),
      subject: course.subject,
      context_id: List.first(contexts).id
    })
  end

  defp row({{:solo, tc} = unit, contexts}, ctx) do
    Map.merge(facts(contexts, ctx), %{
      id: tc.id,
      unit: unit,
      title: "#{tc.subject} · #{tc.class_group.label}",
      name: tc.class_group.label,
      subject: tc.subject,
      context_id: tc.id
    })
  end

  # « Anglais · Niveau 2 » under the « Anglais » heading reads « Niveau 2 ».
  defp short_name(label, subject) do
    case String.replace_prefix(label, subject <> " · ", "") do
      "" -> label
      name -> name
    end
  end

  defp facts([first | _] = contexts, ctx) do
    classes = Enum.map(contexts, & &1.class_group)

    sizes = Map.new(classes, &{&1.id, Map.get(ctx.sizes, &1.id, 0)})

    %{
      contexts: contexts,
      classes: classes,
      class_sizes: sizes,
      students: sizes |> Map.values() |> Enum.sum(),
      coefficient: coefficient(ctx.coefficients, first),
      pp?: Enum.any?(classes, &(&1.form_master_user_id == ctx.user_id)),
      progress: sum_progress(contexts, ctx.progress),
      competence: competence(contexts, ctx.competences)
    }
  end

  defp sum_progress(contexts, cells) do
    cells = Enum.map(contexts, &Map.get(cells, &1.id, @no_progress))
    entered = Enum.sum_by(cells, & &1.entered)
    expected = Enum.sum_by(cells, & &1.expected)

    %{
      entered: entered,
      expected: expected,
      pct: EntryProgress.pct(entered, expected),
      # A combined course's evaluation is one per member class: count it once.
      assessments: cells |> Enum.map(& &1.assessments) |> Enum.max(fn -> 0 end)
    }
  end

  defp competence(_contexts, nil), do: nil

  defp competence(contexts, texts),
    do: if(Enum.any?(contexts, &is_nil(texts[&1.id])), do: :missing, else: :done)

  defp coefficient(_cells, %{subject_id: nil}), do: nil

  defp coefficient(cells, %{subject_id: subject_id, class_group: cg}) do
    key = %{subject_id: subject_id, subsystem: cg.subsystem, level: cg.level, serie: cg.serie}

    case CoefficientRules.resolve(cells, key) do
      nil -> nil
      found -> cells[found].coefficient
    end
  end
end
