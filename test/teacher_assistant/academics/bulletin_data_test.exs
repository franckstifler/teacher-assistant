defmodule TeacherAssistant.Academics.BulletinDataTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée B"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Academics.create_assessment(tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    %{school: school, year: year, seq: seq, cg: cg, tc: tc, a: a}
  end

  test "class_subjects shapes each context with coefficient, assessments and marks", ctx do
    %{cg: cg, seq: seq, tc: tc} = ctx
    [subj] = Academics.class_subjects(cg, seq)
    assert subj.context_id == tc.id
    assert subj.label == "Maths"
    assert Decimal.equal?(subj.coefficient, Decimal.new(4))
    assert map_size(subj.assessments_by_id) == 1
  end

  test "class_results computes a bulletin for the séquence", ctx do
    %{cg: cg, seq: seq, a: a} = ctx
    [student] = Academics.list_students(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])

    r = Academics.class_results(cg, seq)
    assert r.effectif == 1
    assert Decimal.equal?(r.per_student[student.id].moyenne_generale, Decimal.new(15))
  end

  test "class_results is nil when the class has no subjects", ctx do
    {:ok, cg2} =
      Academics.create_class_group(ctx.school, ctx.year, %{label: "6e B", level: "6ème"})

    assert Academics.class_results(cg2, ctx.seq) == nil
  end
end
