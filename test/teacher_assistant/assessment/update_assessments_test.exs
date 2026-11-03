defmodule TeacherAssistant.Assessment.UpdateAssessmentsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.{Curriculum, Enrollment, MarksFixtures, TeacherFixtures}

  setup do
    MarksFixtures.marks_world()
  end

  defp reload(scope, a) do
    {:ok, a} = Assessment.fetch_owned_assessment(scope, a.id)
    a
  end

  describe "update_assessments/3" do
    test "renames and changes the maximum", %{t: t, a: a} do
      assert :ok =
               Assessment.update_assessments(t, [a], %{label: "Devoir A", max_score: "10"})

      a = reload(t, a)
      assert a.label == "Devoir A"
      assert Decimal.equal?(a.max_score, 10)
    end

    test "refuses a maximum under a mark already entered", %{t: t, a: a, s1: s1} do
      :ok = Assessment.upsert_marks(t, a, [%{student_id: s1.id, score: Decimal.new(14)}])

      assert {:error, :marks_above_max} =
               Assessment.update_assessments(t, [a], %{max_score: Decimal.new(10)})

      assert Decimal.equal?(reload(t, a).max_score, 20)
    end

    test "a locked séquence keeps its assessments as they are", %{t: t, a: a} = world do
      MarksFixtures.lock!(world, Date.add(Reference.today(), -1))

      assert {:error, _} = Assessment.update_assessments(t, [a], %{label: "Autre"})
      assert reload(t, a).label == "Devoir 1"
    end

    test "another teacher may not change it", %{head: head, a: a} do
      %{scope: other} = TeacherFixtures.school_teacher_fixture(head, %{subject: "Anglais"})

      assert {:error, %Ash.Error.Forbidden{}} =
               Assessment.update_assessments(other, [a], %{label: "Autre"})
    end

    test "a combined column is renamed in every class at once",
         %{head: head, t: t, tc: tc, year: year, seq: seq} do
      {:ok, cg2} = Enrollment.create_class_group(head, year, %{label: "3e B", level: "3ème"})
      {:ok, tc2} = Curriculum.assign_teacher(head, cg2, t.current_user, %{subject: tc.subject})
      {:ok, course} = Curriculum.combine_course(head, [tc, tc2])
      {:ok, created} = Assessment.create_combined_assessment(t, course, seq, %{label: "Interro"})

      assert :ok = Assessment.update_assessments(t, created, %{label: "Interro 1"})
      assert Enum.all?(created, &(reload(t, &1).label == "Interro 1"))
    end
  end

  describe "marked_students/2" do
    test "lists, per assessment, the students with a mark or an absence",
         %{t: t, tc: tc, seq: seq, a: a, s1: s1, s2: s2} do
      {:ok, b} = Assessment.create_assessment(t, tc, seq, %{label: "Devoir 2"})
      :ok = Assessment.upsert_marks(t, a, [%{student_id: s1.id, score: Decimal.new(12)}])
      :ok = Assessment.upsert_marks(t, a, [%{student_id: s2.id, status: :absent}])

      assert Assessment.marked_students(t, [a, b]) == %{
               a.id => MapSet.new([s1.id, s2.id]),
               b.id => MapSet.new()
             }
    end

    test "nothing to read for no assessment", %{t: t} do
      assert Assessment.marked_students(t, []) == %{}
    end
  end
end
