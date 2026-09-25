defmodule TeacherAssistant.Academics.MarkTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    seq = Organization.list_sequences(year) |> List.first()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
    {:ok, s1} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, s2} = Enrollment.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, a} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 1"})
    %{ctx: ctx, seq: seq, a: a, s1: s1, s2: s2}
  end

  test "upsert creates marks", %{a: a, s1: s1, s2: s2} do
    :ok =
      Assessment.upsert_marks(a, [
        %{student_id: s1.id, score: Decimal.new("15")},
        %{student_id: s2.id, score: Decimal.new("9")}
      ])

    scores =
      Assessment.list_marks(a)
      |> Map.new(fn m -> {m.student_id, m.score} end)

    assert Decimal.equal?(scores[s1.id], Decimal.new("15"))
    assert Decimal.equal?(scores[s2.id], Decimal.new("9"))
  end

  test "upsert updates an existing mark (no duplicate)", %{a: a, s1: s1} do
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("18")}])
    assert [m] = Assessment.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("18"))
  end

  test "nil score records absent", %{a: a, s1: s1} do
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: nil}])
    assert [m] = Assessment.list_marks(a)
    assert m.score == nil
  end

  test "upsert rejects a score above the assessment maximum and writes nothing", %{a: a, s1: s1} do
    assert {:error, :out_of_range} =
             Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("25")}])

    assert Assessment.list_marks(a) == []
  end

  test "upsert rejects a negative score and writes nothing", %{a: a, s1: s1} do
    assert {:error, :out_of_range} =
             Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("-3")}])

    assert Assessment.list_marks(a) == []
  end

  test "upsert accepts a score exactly at the maximum", %{a: a, s1: s1} do
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("20")}])
    assert [m] = Assessment.list_marks(a)
    assert Decimal.equal?(m.score, Decimal.new("20"))
  end

  test "a single out-of-range entry rejects the whole batch", %{a: a, s1: s1, s2: s2} do
    assert {:error, :out_of_range} =
             Assessment.upsert_marks(a, [
               %{student_id: s1.id, score: Decimal.new("12")},
               %{student_id: s2.id, score: Decimal.new("99")}
             ])

    assert Assessment.list_marks(a) == []
  end

  test "list_marks_for_context_sequence spans assessments", %{ctx: ctx, seq: seq, a: a, s1: s1} do
    {:ok, a2} = Assessment.create_assessment(ctx, seq, %{label: "Devoir 2"})
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])
    :ok = Assessment.upsert_marks(a2, [%{student_id: s1.id, score: Decimal.new("11")}])
    assert length(Assessment.list_marks_for_context_sequence(ctx, seq)) == 2
  end

  test "saving a new mark broadcasts a create notification on marks:assessment:<id>", %{
    a: a,
    s1: s1
  } do
    topic = "marks:assessment:#{a.id}"
    Phoenix.PubSub.subscribe(TeacherAssistant.PubSub, topic)

    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic,
      event: "create",
      payload: %Ash.Notifier.Notification{
        resource: TeacherAssistant.Academics.Mark,
        data: %TeacherAssistant.Academics.Mark{
          assessment_id: assessment_id,
          student_id: student_id
        }
      }
    }

    assert assessment_id == a.id
    assert student_id == s1.id
  end

  test "saving over an existing mark broadcasts an update notification on marks:assessment:<id>",
       %{a: a, s1: s1} do
    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("15")}])

    topic = "marks:assessment:#{a.id}"
    Phoenix.PubSub.subscribe(TeacherAssistant.PubSub, topic)

    :ok = Assessment.upsert_marks(a, [%{student_id: s1.id, score: Decimal.new("18")}])

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic,
      event: "update",
      payload: %Ash.Notifier.Notification{
        resource: TeacherAssistant.Academics.Mark,
        data: %TeacherAssistant.Academics.Mark{
          assessment_id: assessment_id,
          student_id: student_id
        }
      }
    }

    assert assessment_id == a.id
    assert student_id == s1.id
  end
end
