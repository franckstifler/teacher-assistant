defmodule TeacherAssistant.Academics.StudentDeletionTest do
  @moduledoc """
  Deleting a student added by mistake: allowed while nothing official exists for
  them (no mark, no receipt, warning letter or return note), refused afterwards.
  """
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Enrollment, Fees, FeesFixtures, MarksFixtures}
  alias TeacherAssistant.TeacherFixtures

  describe "a student with nothing official" do
    setup do
      %{head: scope, cg: cg} = MarksFixtures.marks_world()
      {:ok, s} = Enrollment.add_student(scope, cg, %{full_name: "Doublon Awa", sex: :f})

      {:ok, _guardian} =
        Enrollment.add_guardian(scope, s, %{
          full_name: "Jean Doublon",
          relationship: :pere,
          phone: "677000111"
        })

      %{scope: scope, cg: cg, s: s}
    end

    test "can be deleted, with their enrolment and parent links", %{scope: scope, cg: cg, s: s} do
      assert Enrollment.student_deletion_blocker(scope, s) == nil
      assert :ok = Enrollment.delete_student(scope, s)

      refute Enum.any?(Enrollment.list_roster(scope, cg), &(&1.student.id == s.id))
      assert {:error, :not_found} = Enrollment.fetch_owned_student(scope, s.id)
    end

    test "cannot be deleted by the head of discipline", %{scope: scope, s: s} do
      sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})

      assert {:error, %Ash.Error.Forbidden{}} = Enrollment.delete_student(sg, s)
      assert {:ok, _} = Enrollment.fetch_owned_student(scope, s.id)
    end
  end

  test "a student with a mark is kept" do
    %{head: head, t: t, a: a, s1: s1} = MarksFixtures.marks_world()
    :ok = Assessment.upsert_marks(t, a, [%{student_id: s1.id, score: Decimal.new(12)}])

    assert Enrollment.student_deletion_blocker(head, s1) == :marks
    assert {:error, :marks} = Enrollment.delete_student(head, s1)
    assert {:ok, _} = Enrollment.fetch_owned_student(head, s1.id)
  end

  test "a student with a receipt is kept" do
    %{scope: scope, e: e, student: s} = FeesFixtures.fees_school_fixture()
    {:ok, _} = Fees.record_payment(scope, e, FeesFixtures.cash(10_000))

    assert Enrollment.student_deletion_blocker(scope, s) == :fee_documents
    assert {:error, :fee_documents} = Enrollment.delete_student(scope, s)
    assert {:ok, _} = Enrollment.fetch_owned_student(scope, s.id)
  end
end
