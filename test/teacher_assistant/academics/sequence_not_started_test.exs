defmodule TeacherAssistant.Academics.SequenceNotStartedTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Academics.{Lock, Reference}
  alias TeacherAssistant.{MarksFixtures, Organization}

  setup do
    world = MarksFixtures.marks_world()
    [_first, second | _] = Organization.list_sequences(world.head, world.year)
    Map.put(world, :next_seq, second)
  end

  # The world's séquence (and its « Devoir 1 ») now starts tomorrow.
  defp postpone!(%{head: head, seq: seq}) do
    {:ok, seq} =
      seq
      |> Ash.Changeset.for_update(:update, %{start_date: Date.add(Reference.today(), 1)},
        scope: head
      )
      |> Ash.update()

    seq
  end

  test "a séquence not started yet takes no assessment", %{t: t, tc: tc, next_seq: next} do
    assert Lock.not_started?(next)
    assert {:error, _} = Assessment.create_assessment(t, tc, next, %{label: "Devoir 1"})
  end

  test "a séquence not started yet takes no mark", %{t: t, a: a, s1: s1} = world do
    postpone!(world)

    assert {:error, _} =
             Assessment.upsert_marks(t, a, [%{student_id: s1.id, score: Decimal.new(12)}])

    assert Assessment.list_marks(t, a) == []
  end

  test "an assessment made early can still be deleted", %{t: t, a: a} = world do
    postpone!(world)
    assert :ok = Assessment.delete_assessments(t, [a])
  end
end
