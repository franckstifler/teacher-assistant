defmodule TeacherAssistant.Academics.TeacherStatisticsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Academics.{GradingRules, Marks}
  alias TeacherAssistant.{MarksFixtures, TeacherFixtures}

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    year = TeacherFixtures.complete_school_setup!(scope)
    scope = %{scope | current_academic_year: year}
    MarksFixtures.start_sequences!(scope, year)
    [term | _] = Organization.list_terms(scope, year)
    [s1, s2 | _] = Enum.sort_by(term.sequences, & &1.position_in_term)

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, bea} = Enrollment.add_student(scope, cg, %{full_name: "Béa", sex: :f})
    {:ok, carl} = Enrollment.add_student(scope, cg, %{full_name: "Carl", sex: :m})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    %{teacher: other, teaching_context: tc_en} =
      TeacherFixtures.school_teacher_fixture(scope, %{class_group: cg, subject: "Anglais"})

    marks(scope, tc, s1, %{awa => 14, bea => 8, carl => 12})
    marks(scope, tc, s2, %{awa => 16, bea => 9, carl => 11})
    marks(scope, tc_en, s1, %{awa => 10, bea => 10, carl => 10})

    %{
      scope: scope,
      head: head,
      other: other,
      year: year,
      term: term,
      s1: s1,
      s2: s2,
      cg: cg,
      tc: tc,
      awa: awa,
      bea: bea,
      carl: carl
    }
  end

  defp marks(scope, tc, seq, scores) do
    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{label: "Devoir", max_score: Decimal.new(20)})

    :ok =
      Assessment.upsert_marks(
        scope,
        a,
        Enum.map(scores, fn {st, v} -> %{student_id: st.id, score: Decimal.new(v)} end)
      )

    a
  end

  defp subject_average(results, student, tc) do
    results.per_student[student.id].subjects
    |> Enum.find(&(&1.context_id == tc.id))
    |> Map.fetch!(:average)
  end

  test "a séquence course summary equals the Résultats computation", ctx do
    %{scope: scope, tc: tc, s1: s1} = ctx
    stats = Assessment.course_statistics(scope, tc, {:sequence, s1})

    assessments = Assessment.list_assessments(scope, tc, s1)
    marks = Assessment.list_marks_for_context_sequence(scope, tc, s1)

    expected =
      Marks.summarize(
        Enum.map([ctx.awa, ctx.bea, ctx.carl], &%{id: &1.id, sex: &1.sex, name: &1.full_name}),
        Enum.map(assessments, &%{id: &1.id, weight: &1.weight, max_score: &1.max_score}),
        Enum.map(
          marks,
          &%{
            assessment_id: &1.assessment_id,
            student_id: &1.student_id,
            score: &1.score,
            status: &1.status
          }
        ),
        Assessment.grading_rules(scope)
      )

    assert stats.summary == expected
    assert stats.source == :live
    assert length(stats.students) == 3
  end

  test "a trimester figure equals the bulletin's subject average for every student", ctx do
    %{scope: scope, tc: tc, cg: cg, term: term} = ctx
    stats = Assessment.course_statistics(scope, tc, {:trimester, term})
    results = Assessment.class_results_for_period(scope, cg, {:trimester, term})

    for st <- [ctx.awa, ctx.bea, ctx.carl] do
      assert stats.summary.per_student[st.id].average == subject_average(results, st, tc)
    end

    assert stats.source == :live
    assert Decimal.equal?(stats.summary.highest, subject_average(results, ctx.awa, tc))
  end

  test "a published trimester is read from the snapshot even after a later mark change", ctx do
    %{scope: scope, tc: tc, cg: cg, term: term, s2: s2, awa: awa} = ctx
    {:ok, _} = TeacherFixtures.publish_trimester(scope, cg, term)
    published = Assessment.course_statistics(scope, tc, {:trimester, term})

    [a2] = Assessment.list_assessments(scope, tc, s2)
    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: awa.id, score: Decimal.new(2)}])

    stats = Assessment.course_statistics(scope, tc, {:trimester, term})
    assert stats.source == :published

    assert stats.summary.per_student[awa.id].average ==
             published.summary.per_student[awa.id].average

    live = Assessment.class_results_for_period(scope, cg, {:trimester, term})
    refute subject_average(live, awa, tc) == stats.summary.per_student[awa.id].average
  end

  test "an exempted student is out of the headcount and the figures", ctx do
    %{scope: scope, tc: tc, term: term, s1: s1, carl: carl} = ctx
    tc = Ash.load!(tc, :catalog_subject, scope: scope)

    :ok =
      Curriculum.update_coefficient_grid(scope, %{
        "optional" => %{tc.catalog_subject.id => "true"}
      })

    :ok = Curriculum.set_exemptions(scope, tc, [ctx.awa.id, ctx.bea.id])

    for period <- [{:sequence, s1}, {:trimester, term}] do
      stats = Assessment.course_statistics(scope, tc, period)
      assert length(stats.students) == 2
      refute Map.has_key?(stats.summary.per_student, carl.id)
      assert stats.summary.graded_count == 2
    end
  end

  test "a combined course: one union row and one sub-row per class", ctx do
    %{scope: scope, head: head, year: year, tc: tc, s1: s1, term: term} = ctx

    {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    {:ok, dan} = Enrollment.add_student(scope, cg_b, %{full_name: "Dan", sex: :m})
    {:ok, eve} = Enrollment.add_student(scope, cg_b, %{full_name: "Ève", sex: :f})

    {:ok, tc_b} =
      Curriculum.assign_teacher(scope, cg_b, head, %{
        subject: "Maths",
        coefficient: Decimal.new(4)
      })

    marks(scope, tc_b, s1, %{dan => 18, eve => 6})
    {:ok, _course} = Curriculum.combine_course(scope, [tc, tc_b])

    rows =
      scope
      |> Assessment.teacher_statistics(head, {:trimester, term})
      |> Enum.filter(&(&1.course.subject == "Maths"))

    assert [
             %{class_label: nil, headcount: 5, boys: 2, girls: 3},
             %{class_label: "6e A", headcount: 3},
             %{class_label: "6e B", headcount: 2}
           ] = rows

    [union | _] = rows
    assert union.graded == 5
    assert Decimal.equal?(union.highest, 18)
  end

  test "a teacher's table lists every course, one row each, even without marks", ctx do
    %{scope: scope, other: other, s1: s1} = ctx
    rows = Assessment.teacher_statistics(scope, other, {:sequence, s1})
    assert [%{course: %{subject: "Anglais"}, headcount: 3, graded: 3}] = rows

    %{s2: s2} = ctx

    assert [%{graded: 0, average: nil, highest: nil}] =
             Assessment.teacher_statistics(scope, other, {:sequence, s2})
  end

  test "a year table reads the school profile and the séquences a fixed number of times, whatever the classes (minors)",
       ctx do
    %{scope: scope, head: head, year: year} = ctx

    count = fn ->
      {_rows, _total, by} =
        TeacherAssistant.QueryCount.count(
          fn -> Assessment.teacher_statistics(scope, head, {:annual, year}) end,
          [~s(FROM "school_profiles"), ~s(FROM "sequences")]
        )

      by
    end

    one = count.()

    for label <- ["6e B", "6e C"] do
      {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: label, level: "6ème"})
      {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Élève #{label}", sex: :m})
      {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    end

    three = count.()
    assert three == one
  end

  test "from_averages ranks, mentions and sex-splits like summarize" do
    students = [
      %{id: "a", sex: :f, name: "A"},
      %{id: "b", sex: :m, name: "B"},
      %{id: "c", sex: :f, name: "C"}
    ]

    rules = %GradingRules{}

    s =
      Marks.from_averages(
        students,
        %{"a" => Decimal.new(15), "b" => Decimal.new(9), "c" => nil},
        rules
      )

    assert s.per_student["a"].rank == 1
    assert s.per_student["b"].rank == 2
    assert s.per_student["c"].rank == nil
    assert s.pass_rate == 0.5
    assert s.graded_count == 2
    assert s.by_sex.f.graded_count == 1
    assert s.by_sex.f.pass_rate == 1.0
    assert s.by_sex.m.pass_rate == 0.0
    assert s.per_student["a"].mention != nil
  end
end
