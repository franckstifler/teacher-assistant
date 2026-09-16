defmodule TeacherAssistant.Academics.PeriodResultsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup do
    head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée P"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)
    sequences = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})
    [student] = Academics.list_students(cg)

    # helper: give the student `score`/20 in séquence `seq` for Maths
    grade = fn seq, score ->
      {:ok, a} =
        Academics.create_assessment(tc, seq, %{
          label: "D",
          weight: Decimal.new(1),
          max_score: Decimal.new(20)
        })

      :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(score)}])
    end

    %{year: year, cg: cg, sequences: sequences, student: student, grade: grade}
  end

  test "trimester average is the mean of its two séquences", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, s2 | _] = seqs
    grade.(s1, 12)
    grade.(s2, 16)

    [term1 | _] = Academics.list_terms(year)
    r = Academics.class_results_for_period(cg, {:trimester, term1})
    data = r.per_student[student.id]
    # (12 + 16) / 2 = 14
    assert Decimal.equal?(data.moyenne_generale, Decimal.new(14))
    maths = Enum.find(data.subjects, &(&1.label == "Maths"))
    assert [%{average: a1}, %{average: a2}] = maths.components.sequences
    assert Decimal.equal?(a1, Decimal.new(12)) and Decimal.equal?(a2, Decimal.new(16))
  end

  test "a partially-graded trimester uses the one séquence present", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, _s2 | _] = seqs
    grade.(s1, 11)

    [term1 | _] = Academics.list_terms(year)
    r = Academics.class_results_for_period(cg, {:trimester, term1})
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(11))
  end

  test "annual average is the mean of the graded séquences, with trimester components", ctx do
    %{year: year, cg: cg, sequences: seqs, student: student, grade: grade} = ctx
    [s1, s2, s3 | _] = seqs
    grade.(s1, 10)
    grade.(s2, 12)
    grade.(s3, 8)

    r = Academics.class_results_for_period(cg, {:annual, year})
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

  test "class_results_for_period is nil when the class has no subjects", %{year: year} do
    {:ok, school2} =
      Schools.create_school(TeacherAssistant.TeacherFixtures.user_fixture(), %{name: "Lycée Q"})

    {:ok, y2} =
      Academics.create_academic_year(school2, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(y2)
    {:ok, cg2} = Academics.create_class_group(school2, y2, %{label: "6e Z", level: "6ème"})
    assert Academics.class_results_for_period(cg2, {:annual, y2}) == nil
    _ = year
  end

  test "resolve_period maps params and rejects bad ones", %{year: year, sequences: seqs} do
    [s1 | _] = seqs
    [term1 | _] = Academics.list_terms(year)

    assert {:sequence, got_seq} = Academics.resolve_period(year, "seq:#{s1.id}")
    assert got_seq.id == s1.id
    assert {:trimester, got_term} = Academics.resolve_period(year, "trim:#{term1.id}")
    assert got_term.id == term1.id
    assert {:annual, got_year} = Academics.resolve_period(year, "annee")
    assert got_year.id == year.id
    assert Academics.resolve_period(year, "seq:#{Ecto.UUID.generate()}") == nil
    assert Academics.resolve_period(year, "garbage") == nil

    # round-trips
    assert Academics.period_param({:sequence, s1}) == "seq:#{s1.id}"
    assert Academics.period_param({:trimester, term1}) == "trim:#{term1.id}"
    assert Academics.period_param({:annual, year}) == "annee"
  end
end
