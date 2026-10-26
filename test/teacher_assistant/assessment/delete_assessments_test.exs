defmodule TeacherAssistant.Assessment.DeleteAssessmentsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.{Curriculum, Enrollment, MarksFixtures, TeacherFixtures}

  setup do
    MarksFixtures.marks_world()
  end

  defp exists?(scope, a), do: match?({:ok, _}, Assessment.fetch_owned_assessment(scope, a.id))

  test "the course's teacher deletes an assessment with no marks", %{t: t, head: head, a: a} do
    assert :ok = Assessment.delete_assessments(t, [a])
    refute exists?(head, a)
  end

  test "an assessment with a mark is kept", %{t: t, head: head, a: a, s1: s1} do
    :ok = Assessment.upsert_marks(t, a, [%{student_id: s1.id, score: Decimal.new(12)}])

    assert {:error, :has_marks} = Assessment.delete_assessments(t, [a])
    assert exists?(head, a)
  end

  test "an absence counts as a mark", %{t: t, head: head, a: a, s1: s1} do
    :ok = Assessment.upsert_marks(t, a, [%{student_id: s1.id, status: :absent}])

    assert {:error, :has_marks} = Assessment.delete_assessments(t, [a])
    assert exists?(head, a)
  end

  test "a locked séquence keeps its assessments", %{t: t, head: head, a: a} = world do
    MarksFixtures.lock!(world, Date.add(Reference.today(), -1))

    assert {:error, _} = Assessment.delete_assessments(t, [a])
    assert exists?(head, a)
  end

  test "another teacher may not delete it", %{head: head, a: a} do
    %{scope: other} = TeacherFixtures.school_teacher_fixture(head, %{subject: "Anglais"})

    assert {:error, %Ash.Error.Forbidden{}} = Assessment.delete_assessments(other, [a])
    assert exists?(head, a)
  end

  test "a combined column goes as a whole, or not at all when one class has a mark",
       %{head: head, t: t, tc: tc, year: year, seq: seq} do
    {:ok, cg2} = Enrollment.create_class_group(head, year, %{label: "3e B", level: "3ème"})
    {:ok, s3} = Enrollment.add_student(head, cg2, %{full_name: "Chantal", sex: :f})
    {:ok, tc2} = Curriculum.assign_teacher(head, cg2, t.current_user, %{subject: tc.subject})
    {:ok, course} = Curriculum.combine_course(head, [tc, tc2])

    {:ok, created} = Assessment.create_combined_assessment(t, course, seq, %{label: "Interro"})
    {[a2], [a1]} = Enum.split_with(created, &(&1.teaching_context_id == tc2.id))

    :ok = Assessment.upsert_marks(t, a2, [%{student_id: s3.id, score: Decimal.new(9)}])
    assert {:error, :has_marks} = Assessment.delete_assessments(t, [a1, a2])
    assert exists?(head, a1) and exists?(head, a2)

    :ok = Assessment.upsert_marks(t, a2, [%{student_id: s3.id, score: nil}])
    assert :ok = Assessment.delete_assessments(t, [a1, a2])
    refute exists?(head, a1) or exists?(head, a2)
  end
end
