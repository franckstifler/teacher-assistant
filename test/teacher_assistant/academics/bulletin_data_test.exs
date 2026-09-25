defmodule TeacherAssistant.Academics.BulletinDataTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(head, %{name: "Lycée B"})
    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(year)
    [seq | _] = Organization.list_sequences(year)

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    %{school: school, year: year, seq: seq, cg: cg, tc: tc, a: a, scope: scope}
  end

  test "class_subjects shapes each context with coefficient, assessments and marks", ctx do
    %{cg: cg, seq: seq, tc: tc, scope: scope} = ctx
    [subj] = Assessment.class_subjects(scope, cg, seq)
    assert subj.context_id == tc.id
    assert subj.label == "Maths"
    assert Decimal.equal?(subj.coefficient, Decimal.new(4))
    assert map_size(subj.assessments_by_id) == 1
  end

  test "class_results computes a bulletin for the séquence", ctx do
    %{cg: cg, seq: seq, a: a, scope: scope} = ctx
    [student] = Enrollment.list_students(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(15)}])

    r = Assessment.class_results(scope, cg, seq)
    assert r.effectif == 1
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(15))
  end

  test "class_results is nil when the class has no subjects", ctx do
    {:ok, cg2} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    assert Assessment.class_results(ctx.scope, cg2, ctx.seq) == nil
  end
end
