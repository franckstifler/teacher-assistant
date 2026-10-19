defmodule TeacherAssistant.Academics.TimetableConflictsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.TimetableConflicts, as: C

  defp s(id, cg, day, p, teacher, combined \\ nil, opts \\ []),
    do: %{
      id: id,
      class_group_id: cg,
      day: day,
      period_id: p,
      teacher_id: teacher,
      combined_course_id: combined,
      teaching_context_id: "tc-#{id}",
      room_id: opts[:room],
      home_room_id: opts[:home],
      class_size: Keyword.get(opts, :size, 30)
    }

  defp r(id, cg, day, p, teacher, room, opts \\ []),
    do: s(id, cg, day, p, teacher, opts[:combined], Keyword.put(opts, :room, room))

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

  # --- J3: rooms, unavailability, capacity ---------------------------------------------

  test "two classes in the same shared room at the same time: a room clash on both, counted once" do
    slots = [r(1, "6a", :monday, "p1", "t", "info"), r(2, "6b", :monday, "p1", "u", "info")]

    assert C.room_clashes(slots) == %{
             {"6a", :monday, "p1"} => ["6b"],
             {"6b", :monday, "p1"} => ["6a"]
           }

    assert C.count(slots) == 1
  end

  test "two classes sharing a home room at different times: no clash; same time: one clash" do
    apart = [
      r(1, "6a", :monday, "p1", "t", "b12", home: "b12"),
      r(2, "6b", :monday, "p7", "u", "b12", home: "b12")
    ]

    assert C.room_clashes(apart) == %{}

    together = [
      r(1, "6a", :monday, "p1", "t", "b12", home: "b12"),
      r(2, "6b", :monday, "p1", "u", "b12", home: "b12")
    ]

    assert map_size(C.room_clashes(together)) == 2
    assert C.count(together) == 1
  end

  test "a nil effective room never clashes" do
    slots = [s(1, "6a", :monday, "p1", "t"), s(2, "6b", :monday, "p1", "u")]
    assert C.room_clashes(slots) == %{}
    refute C.room_busy?(slots, nil, :monday, "p1", [])
  end

  test "a combined course in one room is not a room clash between its own classes" do
    slots = [
      r(1, "maco", :monday, "p1", "t", "info", combined: "cc"),
      r(2, "eleq", :monday, "p1", "t", "info", combined: "cc")
    ]

    assert C.room_clashes(slots) == %{}
    assert C.count(slots) == 0
  end

  test "a lesson at an unavailable time is a problem and counted" do
    slots = [s(1, "6a", :monday, "p1", "t")]
    unavailable = MapSet.new([{"t", :monday, "p1"}])

    assert C.unavailable_cells(slots, unavailable) == MapSet.new([{"6a", :monday, "p1"}])
    assert C.count(slots, unavailable) == 1
    assert C.problem?(slots, unavailable, {"6a", :monday, "p1"})
    refute C.available?(unavailable, "t", :monday, "p1")
    assert C.available?(unavailable, "t", :monday, "p2")
  end

  test "teacher clash + room clash + unavailable add up in count" do
    slots = [
      # teacher clash: t in 6a and 6b at monday p1
      s(1, "6a", :monday, "p1", "t"),
      s(2, "6b", :monday, "p1", "t"),
      # room clash: labo at tuesday p1
      r(3, "6a", :tuesday, "p1", "u", "labo"),
      r(4, "6c", :tuesday, "p1", "v", "labo"),
      # unavailable: w on wednesday p1
      s(5, "6a", :wednesday, "p1", "w")
    ]

    assert C.count(slots, MapSet.new([{"w", :wednesday, "p1"}])) == 3
  end

  test "over capacity: shared room flagged with size and capacity, home room skipped, nil capacity skipped" do
    slots = [
      r(1, "6a", :monday, "p1", "t", "labo", size: 62),
      r(2, "6b", :monday, "p2", "t", "b12", home: "b12", size: 90),
      r(3, "6c", :monday, "p3", "t", "cour", size: 90)
    ]

    caps = %{"labo" => 40, "b12" => 60, "cour" => nil}

    assert C.over_capacity(slots, caps) == %{
             {"6a", :monday, "p1"} => %{size: 62, capacity: 40, room_id: "labo"}
           }
  end

  test "over capacity: a combined course sums its classes (25 + 30 > 40), flagged on both, not counted" do
    slots = [
      r(1, "maco", :monday, "p1", "t", "labo", combined: "cc", size: 25),
      r(2, "eleq", :monday, "p1", "t", "labo", combined: "cc", size: 30)
    ]

    over = C.over_capacity(slots, %{"labo" => 40})
    assert over[{"maco", :monday, "p1"}] == %{size: 55, capacity: 40, room_id: "labo"}
    assert over[{"eleq", :monday, "p1"}] == %{size: 55, capacity: 40, room_id: "labo"}
    assert C.count(slots) == 0
  end

  test "suggestions for an unavailable lesson: moves only to available times with the room free" do
    slots = [
      r(1, "6a", :monday, "p1", "t", "info"),
      # the computer room is taken at monday p2
      r(2, "6b", :monday, "p2", "u", "info")
    ]

    unavailable = MapSet.new([{"t", :monday, "p1"}, {"t", :monday, "p3"}])
    open = [{:monday, "p1"}, {:monday, "p2"}, {:monday, "p3"}, {:monday, "p4"}]

    moves =
      slots
      |> C.suggestions(open, "6a", {:monday, "p1"}, unavailable)
      |> Enum.filter(&(&1.kind == :move))

    assert Enum.map(moves, & &1.to) == [{:monday, "p4"}]
  end

  test "suggestions never swap a lesson into an occupied room or an unavailable time" do
    slots = [
      # t is unavailable at monday p1
      s(1, "6a", :monday, "p1", "t"),
      # candidate swap partner in the computer room at tuesday p1; at monday p1 the room is taken by 6c
      r(2, "6a", :tuesday, "p1", "u", "info"),
      r(3, "6c", :monday, "p1", "v", "info"),
      # candidate partner at tuesday p2: t unavailable there
      s(4, "6a", :tuesday, "p2", "w"),
      # candidate partner at tuesday p3: fine
      s(5, "6a", :tuesday, "p3", "x")
    ]

    unavailable = MapSet.new([{"t", :monday, "p1"}, {"t", :tuesday, "p2"}])
    open = [{:monday, "p1"}, {:tuesday, "p1"}, {:tuesday, "p2"}, {:tuesday, "p3"}]

    swaps =
      slots
      |> C.suggestions(open, "6a", {:monday, "p1"}, unavailable)
      |> Enum.filter(&(&1.kind == :swap))

    assert Enum.map(swaps, & &1.with.id) == [5]
  end

  test "suggestions for a room clash exist; none for a problem-free cell" do
    slots = [r(1, "6a", :monday, "p1", "t", "info"), r(2, "6b", :monday, "p1", "u", "info")]
    open = [{:monday, "p1"}, {:monday, "p2"}]

    assert [%{kind: :move, to: {:monday, "p2"}}] =
             C.suggestions(slots, open, "6a", {:monday, "p1"}, MapSet.new())

    assert C.suggestions([r(1, "6a", :monday, "p1", "t", "info")], open, "6a", {:monday, "p1"}) ==
             []
  end

  test "over capacity: a combined course in one member's home room still sums its classes" do
    slots = [
      r(1, "maco", :monday, "p1", "t", "b12", combined: "cc", home: "b12", size: 25),
      r(2, "eleq", :monday, "p1", "t", "b12", combined: "cc", home: "b14", size: 30)
    ]

    over = C.over_capacity(slots, %{"b12" => 40})
    assert over[{"maco", :monday, "p1"}] == %{size: 55, capacity: 40, room_id: "b12"}
    assert over[{"eleq", :monday, "p1"}] == %{size: 55, capacity: 40, room_id: "b12"}
  end
end
