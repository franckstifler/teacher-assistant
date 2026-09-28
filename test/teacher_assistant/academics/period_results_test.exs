defmodule TeacherAssistant.Academics.PeriodResultsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup do
    head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée P"})

    scope = school_scope(head, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    sequences = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})

    [student] = Enrollment.list_students(scope, cg)

    # helper: give the student `score`/20 in séquence `seq` for Maths
    grade = fn seq, score ->
      {:ok, a} =
        Assessment.create_assessment(scope, tc, seq, %{
          label: "D",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      :ok =
        Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(score)}])
    end

    %{year: year, cg: cg, sequences: sequences, student: student, grade: grade, scope: scope}
  end

  test "trimester average is the mean of its two séquences", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade, scope: scope} = ctx
    [s1, s2 | _] = seqs
    grade.(s1, 12)
    grade.(s2, 16)

    [term1 | _] = Organization.list_terms(scope, year)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    data = r.per_student[student.id]
    # (12 + 16) / 2 = 14
    assert Decimal.equal?(data.moyenne_generale, Decimal.new(14))
    maths = Enum.find(data.subjects, &(&1.label == "Maths"))
    assert [%{average: a1}, %{average: a2}] = maths.components.sequences
    assert Decimal.equal?(a1, Decimal.new(12)) and Decimal.equal?(a2, Decimal.new(16))
  end

  test "a partially-graded trimester uses the one séquence present", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade, scope: scope} = ctx
    [s1, _s2 | _] = seqs
    grade.(s1, 11)

    [term1 | _] = Organization.list_terms(scope, year)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(11))
  end

  test "annual average is the mean of the graded séquences, with trimester components", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade, scope: scope} = ctx
    [s1, s2, s3 | _] = seqs
    grade.(s1, 10)
    grade.(s2, 12)
    grade.(s3, 8)

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # mean of present séquences: (10 + 12 + 8) / 3 = 10
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(10))
    maths = Enum.find(r.per_student[student.id].subjects, &(&1.label == "Maths"))
    # trimester components: T1 = (10+12)/2 = 11 ; T2 = 8 ; T3 = nil
    assert [%{position: 1, average: t1}, %{position: 2, average: t2}, %{position: 3, average: t3}] =
             maths.components.trimesters

    assert Decimal.equal?(t1, Decimal.new(11))
    assert Decimal.equal?(t2, Decimal.new(8))
    assert t3 == nil
  end

  test "class_results_for_period is nil when the class has no subjects", %{year: _year} do
    head2 = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, school2} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head2}, %{
        name: "Lycée Q"
      })

    scope2 = school_scope(head2, school2)

    {:ok, y2} =
      Organization.create_academic_year(scope2, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope2, y2)
    {:ok, cg2} = Enrollment.create_class_group(scope2, y2, %{label: "6e Z", level: "6ème"})
    assert Assessment.class_results_for_period(scope2, cg2, {:annual, y2}) == nil
  end

  test "resolve_period maps params and rejects bad ones", %{
    year: year,
    sequences: seqs,
    scope: scope
  } do
    [s1 | _] = seqs
    [term1 | _] = Organization.list_terms(scope, year)

    assert {:sequence, got_seq} = Organization.resolve_period(scope, year, "seq:#{s1.id}")
    assert got_seq.id == s1.id
    assert {:trimester, got_term} = Organization.resolve_period(scope, year, "trim:#{term1.id}")
    assert got_term.id == term1.id
    assert {:annual, got_year} = Organization.resolve_period(scope, year, "annee")
    assert got_year.id == year.id
    assert Organization.resolve_period(scope, year, "seq:#{Ecto.UUID.generate()}") == nil
    assert Organization.resolve_period(scope, year, "garbage") == nil

    # round-trips
    assert Organization.period_param({:sequence, s1}) == "seq:#{s1.id}"
    assert Organization.period_param({:trimester, term1}) == "trim:#{term1.id}"
    assert Organization.period_param({:annual, year}) == "annee"
  end

  test "the ×2 trimester rule counts the second séquence twice, and alone when S1 is unmarked",
       ctx do
    %{year: year, cg: cg, sequences: [s1, s2 | _], student: st, grade: grade, scope: scope} = ctx

    {:ok, _} =
      Assessment.update_grading_rules(scope, %{
        "trimester_average_rule" => "second_sequence_double"
      })

    [term1 | _] = Organization.list_terms(scope, year)

    grade.(s2, 15)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 15)

    grade.(s1, 12)
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    # (12 + 2·15) / 3 = 14
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 14)
  end

  test "the trimesters annual rule skips an unmarked trimester instead of counting it as zero",
       ctx do
    %{
      year: year,
      cg: cg,
      sequences: [s1, s2, s3, s4 | _],
      student: st,
      grade: grade,
      scope: scope
    } = ctx

    {:ok, _} =
      Assessment.update_grading_rules(scope, %{"annual_average_rule" => "mean_of_trimesters"})

    grade.(s1, 10)
    grade.(s2, 12)
    grade.(s3, 16)
    grade.(s4, 13)

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # T1 = 11, T2 = 14.5, T3 unmarked → (11 + 14.5) / 2 = 12.75
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.75"))
  end

  test "the two annual rules differ when a trimester has fewer marked séquences", ctx do
    %{
      year: year,
      cg: cg,
      sequences: [s1, _s2, s3, s4 | _],
      student: st,
      grade: grade,
      scope: scope
    } = ctx

    grade.(s1, 10)
    grade.(s3, 16)
    grade.(s4, 13)

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # séquences: (10 + 16 + 13) / 3 = 13
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 13)

    {:ok, _} =
      Assessment.update_grading_rules(scope, %{"annual_average_rule" => "mean_of_trimesters"})

    r = Assessment.class_results_for_period(scope, cg, {:annual, year})
    # trimesters: T1 = 10, T2 = 14.5 → 12.25
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.25"))
  end

  test "school rounding applies to period results", ctx do
    %{year: year, cg: cg, sequences: [s1, s2 | _], student: st, grade: grade, scope: scope} = ctx
    grade.(s1, 12)
    grade.(s2, "13.3")
    [term1 | _] = Organization.list_terms(scope, year)

    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    # (12 + 13.3) / 2 = 12.65 at the default hundredth
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.65"))

    {:ok, _} = Assessment.update_grading_rules(scope, %{"average_rounding" => "quarter"})
    r = Assessment.class_results_for_period(scope, cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, Decimal.new("12.75"))
  end

  test "an absence counts 0 by default and is flagged under the make-up rule", ctx do
    %{year: year, cg: cg, sequences: [s1 | _], student: st, grade: grade, scope: scope} = ctx
    grade.(s1, 16)
    [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)

    {:ok, a2} =
      Assessment.create_assessment(scope, tc, s1, %{
        label: "D2",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    :ok = Assessment.upsert_marks(scope, a2, [%{student_id: st.id, score: nil, status: :absent}])

    r = Assessment.class_results_for_period(scope, cg, {:sequence, s1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 8)

    {:ok, _} = Assessment.update_grading_rules(scope, %{"absence_rule" => "makeup"})
    r = Assessment.class_results_for_period(scope, cg, {:sequence, s1})
    assert Decimal.equal?(r.per_student[st.id].moyenne_generale, 16)
    assert [%{makeup_pending: true}] = r.per_student[st.id].subjects
    _ = year
  end
end
