defmodule TeacherAssistant.Academics.TimetableConflictsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.TimetableConflicts, as: C

  defp s(id, cg, day, p, teacher, combined \\ nil),
    do: %{
      id: id,
      class_group_id: cg,
      day: day,
      period_id: p,
      teacher_id: teacher,
      combined_course_id: combined,
      teaching_context_id: "tc-#{id}"
    }

  test "two classes, one teacher, one time: a clash on both cells, counted once" do
    slots = [s(1, "6a", :monday, "p1", "t"), s(2, "6b", :monday, "p1", "t")]
    assert C.clashes(slots) == %{{"6a", :monday, "p1"} => ["6b"], {"6b", :monday, "p1"} => ["6a"]}
    assert C.count(slots) == 1
  end

  test "a combined course is not a clash between its own classes" do
    slots = [s(1, "maco", :monday, "p1", "t", "cc"), s(2, "eleq", :monday, "p1", "t", "cc")]
    assert C.clashes(slots) == %{}
    assert C.count(slots) == 0
  end

  test "a combined course plus an unrelated class: one clash flagged on all three cells" do
    slots = [
      s(1, "maco", :monday, "p1", "t", "cc"),
      s(2, "eleq", :monday, "p1", "t", "cc"),
      s(3, "1c", :monday, "p1", "t")
    ]

    clashes = C.clashes(slots)
    assert clashes[{"1c", :monday, "p1"}] |> Enum.sort() == ["eleq", "maco"]
    assert clashes[{"maco", :monday, "p1"}] == ["1c"]
    assert clashes[{"eleq", :monday, "p1"}] == ["1c"]
    assert C.count(slots) == 1
  end

  test "different teachers at the same time are no clash" do
    assert C.count([s(1, "6a", :monday, "p1", "t"), s(2, "6b", :monday, "p1", "u")]) == 0
  end

  test "moves go to empty open cells where the teacher is free, at most two" do
    slots = [
      s(1, "6a", :monday, "p1", "t"),
      s(2, "6b", :monday, "p1", "t"),
      s(3, "6b", :monday, "p2", "t")
    ]

    open = [{:monday, "p1"}, {:monday, "p2"}, {:monday, "p3"}, {:tuesday, "p1"}, {:tuesday, "p2"}]
    moves = C.suggestions(slots, open, "6a", {:monday, "p1"}) |> Enum.filter(&(&1.kind == :move))
    # p2 is busy for t (6b), so the first two free cells are monday p3 and tuesday p1
    assert Enum.map(moves, & &1.to) == [{:monday, "p3"}, {:tuesday, "p1"}]
  end

  test "a swap is offered only when neither teacher ends up in a clash" do
    slots = [
      s(1, "6a", :monday, "p1", "t"),
      s(2, "6b", :monday, "p1", "t"),
      # 6a's other lesson, teacher u, at tuesday p1: t is free there, u is free at monday p1
      s(3, "6a", :tuesday, "p1", "u"),
      # 6a's lesson with teacher v at tuesday p2: v also teaches 6c at monday p1 → swap would clash v
      s(4, "6a", :tuesday, "p2", "v"),
      s(5, "6c", :monday, "p1", "v")
    ]

    open = [{:monday, "p1"}, {:tuesday, "p1"}, {:tuesday, "p2"}]
    swaps = C.suggestions(slots, open, "6a", {:monday, "p1"}) |> Enum.filter(&(&1.kind == :swap))
    assert Enum.map(swaps, & &1.to) == [{:tuesday, "p1"}]
    assert hd(swaps).with.id == 3
  end

  test "no suggestion for a combined lesson or a cell without a clash" do
    slots = [
      s(1, "maco", :monday, "p1", "t", "cc"),
      s(2, "eleq", :monday, "p1", "t", "cc"),
      s(3, "1c", :monday, "p1", "t")
    ]

    assert C.suggestions(slots, [{:monday, "p2"}], "maco", {:monday, "p1"}) == []

    assert C.suggestions(
             [s(9, "6a", :monday, "p1", "t")],
             [{:monday, "p2"}],
             "6a",
             {:monday, "p1"}
           ) == []
  end
end
